--- zoom_countdown.lua
--- Hammerspoon module: menubar countdown + sound before Zoom meetings
--- Drop this file into ~/.hammerspoon/ and require it from init.lua:
---   require("zoom_countdown")
---
--- Prerequisites:
---   1. Sync Google Calendar → Apple Calendar (System Settings → Internet Accounts → Google)
---   2. Place your countdown sound file at the configured path below
---   3. Grant Hammerspoon calendar access if prompted

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
  soundPath = os.getenv("HOME") .. "/.hammerspoon/sounds/countdown.ogg",

  -- How often (seconds) to poll the calendar for upcoming events
  pollInterval = 60,

  -- How many seconds ahead to look for events when polling
  lookAheadSecs = 10 * 60, -- 10 minutes

  -- Keywords in the event location/notes/URL that indicate a Zoom meeting
  meetingKeywords = { "zoom.us", "zoom.co", "zoommtg://", "teams.microsoft", "meet.google" },

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

local function formatTime(totalSecs)
  if totalSecs < 0 then totalSecs = 0 end
  local mins = math.floor(totalSecs / 60)
  local secs = totalSecs % 60
  return string.format("%d:%02d", mins, secs)
end

--- Extract a joinable meeting URL from event location, url, or notes.
local function extractMeetingURL(location, url, notes)
  local candidates = { location or "", url or "", notes or "" }
  for _, text in ipairs(candidates) do
    -- Zoom personal/scheduled links
    local zoomLink = text:match("(https://[%w%-%.]*zoom%.us/j/%S+)")
                  or text:match("(https://[%w%-%.]*zoom%.us/my/%S+)")
    if zoomLink then return zoomLink end
    -- Google Meet
    local meetLink = text:match("(https://meet%.google%.com/%S+)")
    if meetLink then return meetLink end
    -- Teams
    local teamsLink = text:match("(https://teams%.microsoft%.com/%S+)")
    if teamsLink then return teamsLink end
  end
  return nil
end

--- Check whether any keyword matches in the combined text of the event.
local function isMeetingEvent(location, url, notes)
  local blob = ((location or "") .. " " .. (url or "") .. " " .. (notes or "")):lower()
  for _, kw in ipairs(config.meetingKeywords) do
    if blob:find(kw, 1, true) then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- CALENDAR QUERY (via AppleScript → Calendar.app)
--------------------------------------------------------------------------------

local function queryNextMeeting()
  -- AppleScript that finds the soonest event starting within the look-ahead window
  -- and returns tab-separated: title \t startDate (epoch) \t location \t url \t notes
  local script = string.format([[
    use scripting additions
    use framework "Foundation"

    set now to current date
    set horizon to now + %d

    set bestStart to missing value
    set bestTitle to ""
    set bestLocation to ""
    set bestURL to ""
    set bestNotes to ""

    tell application "Calendar"
      repeat with cal in calendars
        try
          set evts to (every event of cal whose start date ≥ now and start date ≤ horizon)
          repeat with evt in evts
            set s to start date of evt
            if bestStart is missing value or s < bestStart then
              set bestStart to s
              set bestTitle to summary of evt
              try
                set bestLocation to location of evt
              on error
                set bestLocation to ""
              end try
              try
                set bestURL to url of evt
              on error
                set bestURL to ""
              end try
              try
                set bestNotes to description of evt
              on error
                set bestNotes to ""
              end try
            end if
          end repeat
        end try
      end repeat
    end tell

    if bestStart is missing value then
      return "NONE"
    else
      -- Convert AppleScript date to epoch seconds
      set epoch to (bestStart - (current date's time zone offset)) -- not needed, use shell
      set epochStr to do shell script "date -j -f '%%A, %%B %%e, %%Y at %%I:%%M:%%S %%p' " & quoted form of (bestStart as string) & " +%%s 2>/dev/null || echo 0"
      return bestTitle & "\t" & epochStr & "\t" & bestLocation & "\t" & bestURL & "\t" & bestNotes
    end if
  ]], config.lookAheadSecs)

  local ok, result, _ = hs.osascript.applescript(script)

  if not ok then
    -- Fallback: try a simpler approach using icalBuddy or hs.task
    log("AppleScript query failed, trying icalBuddy fallback")
    return queryNextMeetingFallback()
  end

  if result == "NONE" then
    log("No upcoming events found")
    return nil
  end

  local parts = {}
  for part in (result .. "\t"):gmatch("(.-)\t") do
    table.insert(parts, part)
  end

  local title     = parts[1] or "Meeting"
  local startEpoch = tonumber(parts[2]) or 0
  local location  = parts[3] or ""
  local url       = parts[4] or ""
  local notes     = parts[5] or ""

  if startEpoch == 0 then
    log("Could not parse event start time")
    return nil
  end

  -- Check if this is actually a video meeting
  if not isMeetingEvent(location, url, notes) then
    log("Next event '" .. title .. "' doesn't look like a video meeting, skipping")
    return nil
  end

  local meetingURL = extractMeetingURL(location, url, notes)
  log("Found meeting: " .. title .. " at epoch " .. startEpoch)

  return {
    title = title,
    startTime = startEpoch,
    url = meetingURL,
  }
end

--- Fallback using the `icalBuddy` CLI tool (brew install ical-buddy)
function queryNextMeetingFallback()
  local lookAheadMins = math.ceil(config.lookAheadSecs / 60)
  local cmd = string.format(
    '/usr/local/bin/icalBuddy -n -ea -li 1 -nc -b "" -ps "|\\t|" -po "title,datetime,location,url,notes" -tf "%%s" -df "%%s" eventsFrom:now to:now+%dm 2>/dev/null',
    lookAheadMins
  )

  local output, status = hs.execute(cmd)
  if not status or not output or output == "" then
    log("icalBuddy returned nothing")
    return nil
  end

  -- icalBuddy output is messy; just try to extract what we can
  local title = output:match("^(.-)%s*\t") or "Meeting"
  local location = output:match("\tlocation:%s*(.-)%s*\t") or ""
  local url = output:match("\turl:%s*(.-)%s*\t") or ""
  local notes = output:match("\tnotes:%s*(.-)%s*$") or ""

  if not isMeetingEvent(location, url, notes) then
    return nil
  end

  -- Rough start time: this fallback is less precise, use the epoch from datetime
  local epochStr = output:match("\t(%d+)%s")
  local startEpoch = tonumber(epochStr) or (os.time() + 300)

  return {
    title = title,
    startTime = startEpoch,
    url = extractMeetingURL(location, url, notes),
  }
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
      countdownSound:stop() -- reset if somehow still playing
      countdownSound:play()
    else
      -- Fallback to system sound if custom file not found
      log("Sound file not found, using system sound")
      hs.sound.getByName("Submarine"):play()
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
  if tickTimer then return end -- already ticking
  tickTimer = hs.timer.doEvery(1, tick)
  log("Tick timer started")
end

--------------------------------------------------------------------------------
-- POLL (periodic calendar check)
--------------------------------------------------------------------------------

function pollForMeetings()
  local meeting = queryNextMeeting()

  if not meeting then
    -- Only clear if no active countdown
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

  -- If this is a different meeting than what we're tracking, reset
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
-- INIT
--------------------------------------------------------------------------------

local function init()
  -- Load sound
  if hs.fs.attributes(config.soundPath) then
    countdownSound = hs.sound.getByFile(config.soundPath)
    if countdownSound then
      log("Loaded sound: " .. config.soundPath)
    end
  else
    log("⚠ Sound file not found: " .. config.soundPath .. " (will use system sound)")
  end

  -- Create menubar item
  menubar = hs.menubar.new()
  menubar:setTitle(config.idleIcon)
  menubar:setTooltip("Zoom Countdown")
  updateMenubar(0)

  -- Start polling
  pollForMeetings()
  pollTimer = hs.timer.doEvery(config.pollInterval, pollForMeetings)

  log("Zoom countdown initialized")
  hs.notify.new({ title = "Zoom Countdown", informativeText = "Meeting countdown active" }):send()
end

init()

return config -- return config so init.lua can override settings if desired
