-- ShareDND service: watches niri screencasts and toggles notification
-- Do Not Disturb while the screen is being shared.
--
-- Detection is event-driven: a persistent `niri msg -j event-stream` runs
-- under runStream, wrapped in a shell retry loop because the stream API has
-- no exit notification. Any Cast* event triggers a re-query of
-- `niri msg -j casts`, which is the authoritative state, so no per-event
-- bookkeeping is needed and reconnects re-sync for free (the stream sends
-- the full current state, including CastsChanged, on connect).

local function cfg(key)
  return noctalia.getConfig(key)
end

-- true while at least one screencast is believed to be running
local sharingActive = false
-- true when this plugin enabled DND (and therefore owns turning it off)
local dndSetByUs = false

local queryInFlight = false
local queryDirty = false

local function countCasts(json)
  local needle = cfg("only_active") and '"is_active":true' or '"session_id":'
  local n = 0
  local pos = 1
  while true do
    local s, e = json:find(needle, pos, true)
    if not s then
      break
    end
    n = n + 1
    pos = e + 1
  end
  return n
end

local function setDnd(on, cb)
  noctalia.runAsync("noctalia msg notification-dnd-set " .. (on and "on" or "off"), function(res)
    local ok = res ~= nil and res.exitCode == 0
    if not ok then
      noctalia.log("sharednd: notification-dnd-set failed")
    end
    if cb then
      cb(ok)
    end
  end)
end

local function onSharingStarted()
  noctalia.runAsync("noctalia msg notification-dnd-status", function(res)
    if not sharingActive then
      return -- sharing already ended while the status query was in flight
    end
    if res == nil or res.exitCode ~= 0 then
      noctalia.log("sharednd: notification-dnd-status failed")
      return
    end
    if (res.stdout or ""):match("^%s*on") then
      -- DND was already on (enabled manually) — don't take ownership.
      dndSetByUs = false
      noctalia.log("sharednd: sharing started, DND already on")
    else
      setDnd(true, function(ok)
        dndSetByUs = ok
        if ok then
          noctalia.log("sharednd: sharing started, DND enabled")
          if not sharingActive then
            -- sharing ended while the set was in flight — undo
            setDnd(false)
            dndSetByUs = false
          end
        end
      end)
    end
  end)
end

local function onSharingStopped()
  if dndSetByUs or cfg("always_off_after") then
    setDnd(false)
    noctalia.log("sharednd: sharing stopped, DND disabled")
  else
    noctalia.log("sharednd: sharing stopped, DND left as-is")
  end
  dndSetByUs = false
end

local function applyState(activeCount)
  local active = activeCount > 0
  if active == sharingActive then
    return
  end
  sharingActive = active
  if active then
    onSharingStarted()
  else
    onSharingStopped()
  end
end

local function queryCasts()
  if queryInFlight then
    queryDirty = true
    return
  end
  queryInFlight = true
  noctalia.runAsync("niri msg -j casts", function(res)
    queryInFlight = false
    if res ~= nil and res.exitCode == 0 and res.stdout ~= nil then
      applyState(countCasts(res.stdout))
    end
    if queryDirty then
      queryDirty = false
      queryCasts()
    end
  end)
end

local function onEventLine(line)
  -- Matches CastsChanged / CastStartedOrChanged / CastStopped. The casts
  -- query is authoritative, so a rare false positive (a window title
  -- containing '"Cast') only costs one extra query.
  if line:find('"Cast', 1, true) then
    queryCasts()
  end
end

-- Boot. The niri check is a user-facing warning only; the stream loop below
-- retries forever anyway, which also covers niri's socket coming up after
-- noctalia during session start.
noctalia.runAsync("niri msg version", function(res)
  if res == nil or res.exitCode ~= 0 then
    noctalia.notifyError(noctalia.tr("notify.no_niri_title"), noctalia.tr("notify.no_niri_body"))
    noctalia.log("sharednd: niri IPC not reachable at startup")
  end
end)

-- The process group is killed on plugin disable, taking the shell loop and
-- the stream down with it.
if not noctalia.runStream("while :; do niri msg -j event-stream 2>/dev/null; sleep 3; done", onEventLine) then
  noctalia.log("sharednd: failed to start niri event-stream")
end

-- Safety net in case the initial CastsChanged is ever missed.
queryCasts()
