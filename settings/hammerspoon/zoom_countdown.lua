--- zoom_countdown.lua
--- Hammerspoon module: menubar countdown + sound before Zoom meetings
--- Drop this file into ~/.hammerspoon/ and require it from init.lua:
---   require("zoom_countdown")
---
--- Prerequisites:
---   1. Sync Google Calendar → Apple Calendar (System Settings → Internet Accounts → Google)
---   2. Place your countdown sound file at the configured path below
---   3. Grant Hammerspoon calendar access if prompted
---
--- Troubleshooting:
---   Open Hammerspoon console and run:
---     require("zoom_countdown").diagnose()

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local config = {
  -- How many seconds before the meeting to START showing the menubar countdown
  countdownStartSecs = 5 * 60, -- 5 minutes

  -- How many seconds before the meeting to PLAY the sound
  -- (e.g., 30 means the sound plays with 30 seconds to go)
  soundTriggerSecs = 62,

  -- Path to your countdown sound file (mp3, wav, aif, etc.)
  soundPath = os.getenv("HOME") .. "/.hammerspoon/sounds/countdown.mp3",

  -- How often (seconds) to poll the calendar for upcoming events
  pollInterval = 60,

  -- How many seconds ahead to look for events when polling
  lookAheadSecs = 10 * 60, -- 10 minutes

  -- Keywords in the event location/notes/URL that indicate a Zoom meeting
  meetingKeywords = { "zoom.us", "zoom.co", "zoommtg://", "teams.microsoft", "meet.google" },

  -- If true, match ALL calendar events (not just ones with video meeting keywords).
  -- Useful for debugging or if you want a countdown for every event.
  matchAllEvents = false,

  -- Menubar icons/labels
  idleIcon = "📅",
  countdownIcon = "🔴",

  -- Set to true to see debug logging in the Hammerspoon console
  debug = false,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local menubar = nil
local pollTimer = nil
local tickTimer = nil
local countdownSound = nil
local soundPlayed = false

local nextMeeting = nil -- { title, startTime, url }

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function log(msg)
  if config.debug then print("[zoom_countdown] " .. msg) end
end

--- Always prints, even when debug is off. Use for errors/warnings.
local function warn(msg)
  print("[zoom_countdown] ⚠ " .. msg)
end

local function formatTime(totalSecs)
  if totalSecs < 0 then totalSecs = 0 end
  local mins = math.floor(totalSecs / 60)
  local secs = totalSecs % 60
  return string.format("%d:%02d", mins, secs)
end

--- Extract a joinable meeting URL from event location, url, or notes.
local function extractMeetingURL(...)
  local fields = { ... }
  for _, text in ipairs(fields) do
    if type(text) == "string" then
      local zoomLink = text:match("(https://[%w%-%.]*zoom%.us/j/%S+)")
                    or text:match("(https://[%w%-%.]*zoom%.us/my/%S+)")
      if zoomLink then return zoomLink end
      local meetLink = text:match("(https://meet%.google%.com/%S+)")
      if meetLink then return meetLink end
      local teamsLink = text:match("(https://teams%.microsoft%.com/%S+)")
      if teamsLink then return teamsLink end
    end
  end
  return nil
end

--- Check whether any keyword matches in the combined text of the event.
local function isMeetingEvent(...)
  if config.matchAllEvents then return true end
  local fields = { ... }
  local blob = ""
  for _, f in ipairs(fields) do
    if type(f) == "string" then blob = blob .. " " .. f end
  end
  blob = blob:lower()
  for _, kw in ipairs(config.meetingKeywords) do
    if blob:find(kw, 1, true) then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- CALENDAR QUERY (via JXA — JavaScript for Automation)
--
-- JXA gives us real Date objects and JSON serialization, completely avoiding
-- the AppleScript date-format-to-epoch locale nightmare.
--------------------------------------------------------------------------------

local function queryNextMeeting()
  local jxa = string.format([[
    ObjC.import('Foundation');

    var calApp  = Application("Calendar");
    calApp.includeStandardAdditions = true;

    var now     = new Date();
    var horizon = new Date(now.getTime() + %d * 1000);

    var results = [];

    var calendars = calApp.calendars();
    for (var ci = 0; ci < calendars.length; ci++) {
      var cal = calendars[ci];
      var calName = cal.name();
      var events;
      try {
        events = cal.events.whose({
          _and: [
            { startDate: { _greaterThan: new Date(now.getTime() - 60000) } },
            { startDate: { _lessThanEquals: horizon } }
          ]
        })();
      } catch(e) {
        continue;
      }

      for (var ei = 0; ei < events.length; ei++) {
        var evt = events[ei];
        var startDate, summary, location, url, description;
        try { startDate   = evt.startDate().getTime() / 1000; } catch(e) { continue; }
        try { summary     = evt.summary()     || ""; } catch(e) { summary = ""; }
        try { location    = evt.location()    || ""; } catch(e) { location = ""; }
        try { url         = evt.url()         || ""; } catch(e) { url = ""; }
        try { description = evt.description() || ""; } catch(e) { description = ""; }

        if (startDate >= (now.getTime() / 1000 - 60)) {
          results.push({
            title:       summary,
            startEpoch:  Math.floor(startDate),
            location:    location,
            url:         url,
            notes:       description,
            calendar:    calName
          });
        }
      }
    }

    results.sort(function(a, b) { return a.startEpoch - b.startEpoch; });

    JSON.stringify(results);
  ]], config.lookAheadSecs)

  local ok, result, rawOutput = hs.osascript.javascript(jxa)

  if not ok then
    warn("JXA calendar query failed. Raw output: " .. tostring(rawOutput))
    warn("Check: System Settings → Privacy & Security → Calendars → Hammerspoon")
    return nil
  end

  -- hs.osascript.javascript may return a parsed table or a JSON string
  local events
  if type(result) == "table" then
    events = result
  elseif type(result) == "string" then
    local decoded, _, err = hs.json.decode(result)
    if not decoded then
      warn("Failed to parse JXA JSON: " .. tostring(err))
      return nil
    end
    events = decoded
  else
    warn("Unexpected JXA result type: " .. type(result))
    return nil
  end

  log("Calendar query returned " .. #events .. " event(s) in the next " .. config.lookAheadSecs .. "s")

  for i, evt in ipairs(events) do
    local secsUntil = (evt.startEpoch or 0) - os.time()
    log(string.format(
      "  [%d] \"%s\" in %ds | cal=%s | loc=%s",
      i, evt.title or "?", secsUntil,
      evt.calendar or "?", (evt.location or ""):sub(1, 60)
    ))

    if isMeetingEvent(evt.location, evt.url, evt.notes) then
      local meetingURL = extractMeetingURL(evt.location, evt.url, evt.notes)
      log("  → Matched as video meeting! URL: " .. tostring(meetingURL))
      return {
        title = evt.title or "Meeting",
        startTime = evt.startEpoch,
        url = meetingURL,
      }
    else
      log("  → Skipped (no meeting keyword match)")
    end
  end

  log("No video meetings found in upcoming events")
  return nil
end

--------------------------------------------------------------------------------
-- MENUBAR
--------------------------------------------------------------------------------

local function updateMenubar(secsRemaining)
  if not menubar then return end

  if not nextMeeting then
    menubar:setTitle(config.idleIcon)
    menubar:setTooltip("No upcoming meetings")
    menubar:setMenu({
      { title = "No upcoming meetings", disabled = true },
      { title = "-" },
      { title = "Check now", fn = function() pollForMeetings() end },
      { title = "Toggle debug logging", fn = function()
          config.debug = not config.debug
          print("[zoom_countdown] Debug logging " .. (config.debug and "ON" or "OFF"))
        end },
    })
    return
  end

  local timeStr = formatTime(secsRemaining)
  local display = config.countdownIcon .. " " .. timeStr

  menubar:setTitle(display)
  menubar:setTooltip(nextMeeting.title .. " in " .. timeStr)

  local menuItems = {
    { title = nextMeeting.title, disabled = true },
    { title = "Starts in " .. timeStr, disabled = true },
    { title = "-" },
  }

  if nextMeeting.url then
    table.insert(menuItems, {
      title = "Join Meeting",
      fn = function() hs.urlevent.openURL(nextMeeting.url) end,
    })
  end

  table.insert(menuItems, {
    title = "Dismiss",
    fn = function()
      nextMeeting = nil
      soundPlayed = false
      stopTicking()
      updateMenubar(0)
    end,
  })

  table.insert(menuItems, { title = "-" })
  table.insert(menuItems, {
    title = "Toggle debug logging",
    fn = function()
      config.debug = not config.debug
      print("[zoom_countdown] Debug logging " .. (config.debug and "ON" or "OFF"))
    end,
  })

  menubar:setMenu(menuItems)
end

--------------------------------------------------------------------------------
-- TICK (once per second during active countdown)
--------------------------------------------------------------------------------

local function tick()
  if not nextMeeting then
    stopTicking()
    updateMenubar(0)
    return
  end

  local secsRemaining = math.floor(nextMeeting.startTime - os.time())

  -- Meeting time has passed — auto-dismiss after 60s grace period
  if secsRemaining < -60 then
    log("Meeting started over a minute ago, dismissing")
    nextMeeting = nil
    soundPlayed = false
    stopTicking()
    updateMenubar(0)
    return
  end

  -- Play sound at the configured trigger point
  if not soundPlayed and secsRemaining <= config.soundTriggerSecs and secsRemaining > 0 then
    log("Playing countdown sound!")
    if countdownSound then
      countdownSound:stop()
      countdownSound:play()
    else
      log("No custom sound loaded, using system sound")
      local fallback = hs.sound.getByName("Submarine")
      if fallback then fallback:play() end
    end
    soundPlayed = true
  end

  updateMenubar(math.max(secsRemaining, 0))
end

function stopTicking()
  if tickTimer then
    tickTimer:stop()
    tickTimer = nil
  end
end

local function startTicking()
  if tickTimer then return end
  tickTimer = hs.timer.doEvery(1, tick)
  log("Tick timer started")
end

--------------------------------------------------------------------------------
-- POLL (periodic calendar check)
--------------------------------------------------------------------------------

function pollForMeetings()
  log("Polling for meetings...")
  local meeting = queryNextMeeting()

  if not meeting then
    if nextMeeting then
      local secsRemaining = nextMeeting.startTime - os.time()
      if secsRemaining < -60 then
        nextMeeting = nil
        soundPlayed = false
        stopTicking()
        updateMenubar(0)
      end
    else
      updateMenubar(0)
    end
    return
  end

  local secsUntil = meeting.startTime - os.time()

  if nextMeeting and (nextMeeting.startTime ~= meeting.startTime or nextMeeting.title ~= meeting.title) then
    soundPlayed = false
  end

  nextMeeting = meeting

  if secsUntil <= config.countdownStartSecs then
    log("Meeting '" .. meeting.title .. "' is within countdown window (" .. secsUntil .. "s away)")
    startTicking()
  else
    log("Meeting '" .. meeting.title .. "' found but too far out (" .. secsUntil .. "s away)")
    updateMenubar(secsUntil)
  end
end

--------------------------------------------------------------------------------
-- DIAGNOSTICS — run from Hammerspoon console:
--   require("zoom_countdown").diagnose()
--------------------------------------------------------------------------------

local function diagnose()
  print("=== Zoom Countdown Diagnostics ===")
  print("")

  -- 1. Check calendar access
  print("[1] Testing Calendar.app access via JXA...")
  local testScript = [[
    var calApp = Application("Calendar");
    var cals = calApp.calendars();
    var names = [];
    for (var i = 0; i < cals.length; i++) {
      names.push(cals[i].name());
    }
    JSON.stringify(names);
  ]]
  local ok, result = hs.osascript.javascript(testScript)
  if not ok then
    print("   ❌ FAILED — Hammerspoon likely doesn't have calendar access.")
    print("   Fix: System Settings → Privacy & Security → Calendars → enable Hammerspoon")
    print("   If Hammerspoon isn't listed, try toggling Full Disk Access for it.")
    return
  end

  local calendars = type(result) == "table" and result or (hs.json.decode(result) or {})
  print("   ✅ Found " .. #calendars .. " calendar(s):")
  for _, name in ipairs(calendars) do
    print("      • " .. name)
  end
  if #calendars == 0 then
    print("   ⚠ No calendars found! Is Google Calendar synced to Apple Calendar?")
    print("   Fix: System Settings → Internet Accounts → Google → enable Calendars")
  end
  print("")

  -- 2. Look for events in the next hour
  print("[2] Looking for ALL events in the next 60 minutes...")
  local evtScript = [[
    var calApp  = Application("Calendar");
    var now     = new Date();
    var horizon = new Date(now.getTime() + 3600000);

    var results = [];
    var calendars = calApp.calendars();
    for (var ci = 0; ci < calendars.length; ci++) {
      var cal = calendars[ci];
      var events;
      try {
        events = cal.events.whose({
          _and: [
            { startDate: { _greaterThan: new Date(now.getTime() - 60000) } },
            { startDate: { _lessThanEquals: horizon } }
          ]
        })();
      } catch(e) { continue; }
      for (var ei = 0; ei < events.length; ei++) {
        var evt = events[ei];
        try {
          results.push({
            title:    evt.summary()  || "(no title)",
            start:    evt.startDate().toISOString(),
            epoch:    Math.floor(evt.startDate().getTime() / 1000),
            location: (evt.location()    || "").substring(0, 100),
            url:      (evt.url()         || "").substring(0, 100),
            notes:    (evt.description() || "").substring(0, 100),
            calendar: cal.name()
          });
        } catch(e) {}
      }
    }
    results.sort(function(a, b) { return a.epoch - b.epoch; });
    JSON.stringify(results, null, 2);
  ]]

  local ok2, result2 = hs.osascript.javascript(evtScript)
  if not ok2 then
    print("   ❌ Event query failed: " .. tostring(result2))
    return
  end

  local events = type(result2) == "table" and result2 or (hs.json.decode(result2) or {})
  if #events == 0 then
    print("   ⚠ No events found in the next hour.")
    print("   → Open Calendar.app and verify your Google events appear there.")
    print("   → If they don't, re-check System Settings → Internet Accounts → Google")
  else
    print("   Found " .. #events .. " event(s):")
    for _, evt in ipairs(events) do
      local secsUntil = (evt.epoch or 0) - os.time()
      print(string.format('      • "%s" in %ds [%s] cal=%s',
        evt.title, secsUntil, evt.start, evt.calendar))
      if evt.location ~= "" then print("        location: " .. evt.location) end
      if evt.url      ~= "" then print("        url:      " .. evt.url) end
      if evt.notes    ~= "" then print("        notes:    " .. evt.notes) end

      local blob = ((evt.location or "") .. " " .. (evt.url or "") .. " " .. (evt.notes or "")):lower()
      local matched = false
      for _, kw in ipairs(config.meetingKeywords) do
        if blob:find(kw, 1, true) then matched = true; break end
      end
      if matched then
        print("        ✅ MATCHES meeting keywords → will trigger countdown")
      else
        print("        ❌ No keyword match → won't trigger countdown")
        print("        (keywords: " .. table.concat(config.meetingKeywords, ", ") .. ")")
        print("        Tip: set config.matchAllEvents = true to match everything")
      end
    end
  end
  print("")

  -- 3. Check sound
  print("[3] Checking sound file...")
  if hs.fs.attributes(config.soundPath) then
    local s = hs.sound.getByFile(config.soundPath)
    if s then
      print("   ✅ Sound loaded: " .. config.soundPath)
    else
      print("   ⚠ File exists but can't load as audio: " .. config.soundPath)
    end
  else
    print("   ⚠ Not found: " .. config.soundPath)
    print("   → Will fall back to system sound 'Submarine'")
  end

  print("")
  print("=== Done ===")
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

local function init()
  if hs.fs.attributes(config.soundPath) then
    countdownSound = hs.sound.getByFile(config.soundPath)
    if countdownSound then
      log("Loaded sound: " .. config.soundPath)
    else
      warn("Sound file exists but could not be loaded: " .. config.soundPath)
    end
  else
    warn("Sound file not found: " .. config.soundPath .. " (will use system sound)")
  end

  menubar = hs.menubar.new()
  menubar:setTitle(config.idleIcon)
  menubar:setTooltip("Zoom Countdown")
  updateMenubar(0)

  pollForMeetings()
  pollTimer = hs.timer.doEvery(config.pollInterval, pollForMeetings)

  log("Zoom countdown initialized")
end

init()

return {
  config = config,
  diagnose = diagnose,
  poll = pollForMeetings,
}