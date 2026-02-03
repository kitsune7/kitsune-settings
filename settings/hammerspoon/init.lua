hs.loadSpoon("ReloadConfiguration")
spoon.ReloadConfiguration:start()

caffeine = hs.menubar.new()
function setCaffeineDisplay(state)
    if state then
        caffeine:setTitle("AWAKE")
    else
        caffeine:setTitle("SLEEPY")
    end
end

function caffeineClicked()
    setCaffeineDisplay(hs.caffeinate.toggle("displayIdle"))
end

if caffeine then
    caffeine:setClickCallback(caffeineClicked)
    setCaffeineDisplay(hs.caffeinate.get("displayIdle"))
end

--------------------------------------------------------------------------------
-- Text Replacement
--------------------------------------------------------------------------------

local function toCamelCase(str)
    local result = str:gsub("[-_](%w)", function(c) return c:upper() end)
    result = result:gsub("^%u", string.lower) -- lowercase first char
    return result
end

local function toKebabCase(str)
    -- Insert hyphen before uppercase letters, then lowercase everything
    local result = str:gsub("([a-z])([A-Z])", "%1-%2")
    result = result:gsub("_", "-"):lower()
    return result
end

local function toSnakeCase(str)
    local result = str:gsub("([a-z])([A-Z])", "%1_%2")
    result = result:gsub("-", "_"):lower()
    return result
end

local function toPascalCase(str)
    local result = str:gsub("[-_](%w)", function(c) return c:upper() end)
    result = result:gsub("^%l", string.upper) -- uppercase first char
    return result
end

local function transformSelection(transformFn)
    -- Save current clipboard
    local originalClipboard = hs.pasteboard.getContents()
    
    -- Copy selection
    hs.eventtap.keyStroke({"cmd"}, "c")
    
    -- Wait for clipboard to actually update
    hs.timer.doAfter(0.1, function()
        local text = hs.pasteboard.getContents()
        
        -- Only transform if clipboard actually changed
        if text and text ~= originalClipboard then
            local transformed = transformFn(text)
            hs.pasteboard.setContents(transformed)
            hs.eventtap.keyStroke({"cmd"}, "v")
            
            -- Restore original clipboard
            hs.timer.doAfter(0.1, function()
                hs.pasteboard.setContents(originalClipboard)
            end)
        else
            hs.alert.show("Failed to adjust text.")
        end
    end)
end

-- testing-testing

-- Bind hotkeys
hs.hotkey.bind({"ctrl", "alt"}, "c", function() 
    transformSelection(toCamelCase)
    hs.alert.show("→ camelCase")
end)

hs.hotkey.bind({"ctrl", "alt"}, "k", function() 
    transformSelection(toKebabCase)
    hs.alert.show("→ kebab-case")
end)

hs.hotkey.bind({"ctrl", "alt"}, "s", function() 
    transformSelection(toSnakeCase)
    hs.alert.show("→ snake_case")
end)

hs.hotkey.bind({"ctrl", "alt"}, "p", function() 
    transformSelection(toPascalCase)
    hs.alert.show("→ PascalCase")
end)

--------------------------------------------------------------------------------
-- Window Arrangement
--------------------------------------------------------------------------------

-- Configuration
local windowConfig = {
    screens = {
        lg = "LG ULTRAFINE",
        dell = "DELL U2723QE",
        builtin = "Built-in Retina Display"
    },
    -- External monitor arrangements (Tier 1)
    external = {
        lg = {
            { app = "Slack", unit = {0, 0, 0.5, 1} },
            { app = "Warp", unit = {0.5, 0, 0.5, 1} }
        },
        dell = {
            { app = "Comet", unit = {0, 0, 2/3, 1}, allWindows = true },
            { app = "Obsidian", unit = {2/3, 0, 1/3, 1}, allWindows = true }
        }
    },
    -- Built-in display space arrangements (Tier 2)
    builtin = {
        { space = 1, apps = { "zoom.us" } },
        { space = 2, apps = { "Cursor" }, allWindows = true },
        { space = 3, apps = { "Docker Desktop" }, allWindows = true },
        { space = 4, apps = { "LM Studio" }, allWindows = true }
    }
}

-- Helper: Find screen with alert on failure
-- Note: hs.screen.find() has a bug where it can't find "Built-in Retina Display"
-- so we fall back to manual iteration if the initial find fails
local function findScreenSafe(hint, alertOnFail)
    local screen = hs.screen.find(hint)
    if screen then return screen end

    -- Fallback: iterate all screens and match by name
    for _, s in ipairs(hs.screen.allScreens()) do
        if s:name() == hint then
            return s
        end
    end

    if alertOnFail ~= false then
        hs.alert.show("Screen not found: " .. hint)
    end
    return nil
end

-- Helper: Find app (silent if not running)
local function findAppSafe(name)
    return hs.application.find(name, true)
end

-- Helper: Move and resize window
local function moveAndResize(window, screen, unit)
    if window and screen then
        window:moveToScreen(screen)
        window:moveToUnit(unit)
    end
end

-- Helper: Arrange app windows
local function arrangeApp(appName, screen, unit, allWindows)
    local app = findAppSafe(appName)
    if not app then return end

    local windows = allWindows and app:allWindows() or { app:mainWindow() }
    for _, win in ipairs(windows) do
        if win then
            moveAndResize(win, screen, unit)
        end
    end
end

-- Tier 1: Arrange external monitors (LG + Dell)
local function arrangeExternalMonitors()
    hs.alert.show("Arranging external monitors...")

    -- LG ULTRAFINE arrangements
    local lgScreen = findScreenSafe(windowConfig.screens.lg)
    if lgScreen then
        for _, cfg in ipairs(windowConfig.external.lg) do
            arrangeApp(cfg.app, lgScreen, cfg.unit, cfg.allWindows)
        end
    end

    -- DELL arrangements
    local dellScreen = findScreenSafe(windowConfig.screens.dell)
    if dellScreen then
        for _, cfg in ipairs(windowConfig.external.dell) do
            arrangeApp(cfg.app, dellScreen, cfg.unit, cfg.allWindows)
        end
    end

    hs.alert.show("External monitors arranged")
end

-- Tier 2: Arrange built-in display spaces
local function arrangeBuiltInSpaces()
    hs.alert.show("Arranging built-in display spaces...")

    local builtinScreen = findScreenSafe(windowConfig.screens.builtin)
    if not builtinScreen then return end

    local screenUUID = builtinScreen:getUUID()
    local spaces = hs.spaces.spacesForScreen(screenUUID)

    if not spaces then
        hs.alert.show("Failed to get spaces for built-in display")
        return
    end

    -- Ensure we have enough spaces
    local requiredSpaces = #windowConfig.builtin
    while #spaces < requiredSpaces do
        hs.spaces.addSpaceToScreen(screenUUID)
        spaces = hs.spaces.spacesForScreen(screenUUID)
        if not spaces then
            hs.alert.show("Failed to create spaces")
            return
        end
    end

    -- Arrange apps to their designated spaces
    for _, spaceCfg in ipairs(windowConfig.builtin) do
        local spaceID = spaces[spaceCfg.space]
        if spaceID then
            for _, appName in ipairs(spaceCfg.apps) do
                local app = findAppSafe(appName)
                if app then
                    local windows = spaceCfg.allWindows and app:allWindows() or { app:mainWindow() }
                    for _, win in ipairs(windows) do
                        if win then
                            local winID = win:id()
                            if winID then
                                hs.spaces.moveWindowToSpace(winID, spaceID)
                                win:moveToUnit({0, 0, 1, 1})
                            end
                        end
                    end
                end
            end
        end
    end

    hs.alert.show("Built-in display spaces arranged")
end

-- Full arrangement (both tiers)
local function arrangeAll()
    arrangeExternalMonitors()
    arrangeBuiltInSpaces()
end

-- Debug: Show detected screen names
local function showScreenNames()
    local screens = hs.screen.allScreens()
    local names = {}
    for i, screen in ipairs(screens) do
        table.insert(names, i .. ": " .. screen:name())
    end
    hs.alert.show("Screens:\n" .. table.concat(names, "\n"), 5)
end

-- Hotkey bindings
local hyper = {"cmd", "ctrl", "shift"}
hs.hotkey.bind(hyper, "W", arrangeExternalMonitors)  -- External monitors
hs.hotkey.bind(hyper, "S", arrangeBuiltInSpaces)     -- Built-in spaces
hs.hotkey.bind(hyper, "A", arrangeAll)               -- Full arrangement
hs.hotkey.bind(hyper, "D", showScreenNames)          -- Debug screen names

-- Focus Warp
hs.hotkey.bind({"cmd", "ctrl"}, "T", function()
    hs.application.launchOrFocus("Warp")
end)

-- Focus Cursor
hs.hotkey.bind({"cmd", "ctrl"}, "C", function()
    hs.application.launchOrFocus("Cursor")
end)