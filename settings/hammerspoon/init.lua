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

-- Helper to split text into words regardless of input format
local function toWords(str)
    -- First, insert spaces before uppercase letters (for camelCase/PascalCase)
    local spaced = str:gsub("([a-z])([A-Z])", "%1 %2")
    -- Replace underscores and hyphens with spaces
    spaced = spaced:gsub("[-_]", " ")
    -- Split into words and lowercase them
    local words = {}
    for word in spaced:gmatch("%S+") do
        table.insert(words, word:lower())
    end
    return words
end

local function toCamelCase(str)
    local words = toWords(str)
    if #words == 0 then return str end
    
    local result = words[1]
    for i = 2, #words do
        result = result .. words[i]:gsub("^%l", string.upper)
    end
    return result
end

local function toKebabCase(str)
    local words = toWords(str)
    return table.concat(words, "-")
end

local function toSnakeCase(str)
    local words = toWords(str)
    return table.concat(words, "_")
end

local function toPascalCase(str)
    local words = toWords(str)
    local result = ""
    for _, word in ipairs(words) do
        result = result .. word:gsub("^%l", string.upper)
    end
    return result
end

local function toggleBackticks(str)
    if str:match("^`.*`$") then
        return str:sub(2, -2)
    else
        return "`" .. str .. "`"
    end
end

local function toggleQuotes(str)
    if str:match('^".*"$') then
        return str:sub(2, -2)
    else
        return '"' .. str .. '"'
    end
end

local function waitForModifierRelease(callback)
    local function check()
        local flags = hs.eventtap.checkKeyboardModifiers()
        if flags.ctrl or flags.alt or flags.cmd or flags.shift then
            hs.timer.doAfter(0.05, check)
        else
            callback()
        end
    end
    check()
end

local function transformSelection(transformFn)
    local originalClipboard = hs.pasteboard.getContents()
    local originalChangeCount = hs.pasteboard.changeCount()
    
    waitForModifierRelease(function()
        hs.osascript.applescript('tell application "System Events" to keystroke "c" using command down')
        
        hs.timer.doAfter(0.2, function()
            local newChangeCount = hs.pasteboard.changeCount()
            
            if newChangeCount > originalChangeCount then
                local text = hs.pasteboard.getContents()
                local transformed = transformFn(text)
                hs.pasteboard.setContents(transformed)
                hs.osascript.applescript('tell application "System Events" to keystroke "v" using command down')
                
                hs.timer.doAfter(0.1, function()
                    hs.pasteboard.setContents(originalClipboard)
                end)
            else
                hs.alert.show("Clipboard didn't change")
            end
        end)
    end)
end

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

hs.hotkey.bind({"ctrl", "alt"}, "b", function() 
    transformSelection(toggleBackticks)
    hs.alert.show("→ `backticks`")
end)

hs.hotkey.bind({"ctrl", "alt"}, "q", function() 
    transformSelection(toggleQuotes)
    hs.alert.show('→ "quotes"')
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