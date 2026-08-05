--!nonstrict
-- Spotify Lyrics Desktop Widget – floating overlay version.
--
-- Same data source as panel.luau but rendered via desktopWidget.render()
-- with larger font sizes for desktop readability.
-- Long lyrics are dynamically scaled to smaller fonts to prevent overflow.

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------
local WIDGET_WIDTH   = 400
local WIDGET_PADDING = 10
local INNER_WIDTH    = WIDGET_WIDTH - WIDGET_PADDING * 2  -- 380px usable
local MIN_HEIGHT     = 160

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------
local currentHeight = MIN_HEIGHT
local lastState     = nil
local lastClock     = os.clock()

--------------------------------------------------------------------------------
-- Dynamic font sizing (see panel.luau for rationale)
--------------------------------------------------------------------------------

local function fitFontSize(text, defaultSize)
  if not text or text == "" then return defaultSize end
  local len = #text
  if len <= 40 then return defaultSize end
  local reduction = math.floor((len - 40) / 15) * 2
  return math.max(11, defaultSize - reduction)
end

--------------------------------------------------------------------------------
-- Height estimation
--------------------------------------------------------------------------------

local function estimateLines(text, fontSize)
  if not text or text == "" then return 0 end
  local charsPerLine = math.max(1, math.floor(INNER_WIDTH / (fontSize * 0.60)))
  return math.max(1, math.ceil(#text / charsPerLine))
end

local function estimateContentHeight(state)
  local h = WIDGET_PADDING * 2

  if state.title and state.artist then
    h = h + 12 + 6 + estimateLines(state.title .. " — " .. state.artist, 11) * 16
    h = h + 10 + 1 + 10
  end

  local prevSize = fitFontSize(state.prev, 18)
  if (state.prev or "") ~= "" then
    h = h + estimateLines(state.prev, prevSize) * math.ceil(prevSize * 1.4)
  else
    h = h + 18
  end
  h = h + 10

  local currentSize = fitFontSize(state.current, 26)
  h = h + estimateLines(state.current or "...", currentSize) * math.ceil(currentSize * 1.4)
  h = h + 10

  local nextSize = fitFontSize(state.next, 18)
  if (state.next or "") ~= "" then
    h = h + estimateLines(state.next, nextSize) * math.ceil(nextSize * 1.4)
  else
    h = h + 18
  end

  h = h + 24
  return math.max(MIN_HEIGHT, h)
end

--------------------------------------------------------------------------------
-- State I/O
--------------------------------------------------------------------------------

local function readState()
  local content = noctalia.readFile("~/.cache/noctalia/lyrics/current.json")
  if not content then return nil end
  local state, _ = noctalia.json.decode(content)
  return state
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function renderEmpty()
  desktopWidget.render(ui.column({
    gap = 8, align = "center", justify = "center",
    minWidth = WIDGET_WIDTH, minHeight = currentHeight,
  }, {
    ui.glyph({ name = "music", size = 28, color = "on_surface/0.3" }),
    ui.label({
      text = "No music playing",
      fontSize = 16, fontWeight = "medium", color = "on_surface/0.3",
    }),
  }))
end

local function renderPaused(state)
  desktopWidget.render(ui.column({
    gap = 8, align = "center", justify = "center",
    minWidth = WIDGET_WIDTH, minHeight = currentHeight,
  }, {
    ui.glyph({ name = "player-pause", size = 22, color = "on_surface/0.4" }),
    ui.label({
      text = state.current or "Paused",
      fontSize = 22, fontWeight = "bold",
      color = "on_surface/0.5", wrap = true, textAlign = "center",
    }),
  }))
end

local function renderPlaying(state)
  local rows = {}

  -- Track header
  if state.title and state.artist then
    table.insert(rows, ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "music", size = 12, color = "primary/0.7" }),
      ui.label({
        text = state.title .. " — " .. state.artist,
        fontSize = 11, fontWeight = "medium",
        color = "primary/0.6", wrap = true,
      }),
    }))
    table.insert(rows, ui.box({ height = 1, fill = "on_surface/0.08" }))
  end

  -- Previous lyric (dynamically scaled)
  local prevText = state.prev or ""
  if prevText ~= "" then
    table.insert(rows, ui.label({
      text = prevText,
      fontSize = fitFontSize(prevText, 18), fontWeight = "normal",
      color = "on_surface/0.3", textAlign = "center", wrap = true,
    }))
  else
    table.insert(rows, ui.box({ height = 18 }))
  end

  -- Current lyric (dynamically scaled)
  local currentText = state.current or "..."
  table.insert(rows, ui.label({
    text = currentText,
    fontSize = fitFontSize(currentText, 26), fontWeight = "bold",
    color = "on_surface", textAlign = "center", wrap = true,
  }))

  -- Next lyric (dynamically scaled)
  local nextText = state.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = nextText,
      fontSize = fitFontSize(nextText, 18), fontWeight = "normal",
      color = "on_surface/0.3", textAlign = "center", wrap = true,
    }))
  else
    table.insert(rows, ui.box({ height = 18 }))
  end

  desktopWidget.render(ui.column({
    gap = 10, align = "center", justify = "center",
    minWidth = WIDGET_WIDTH, minHeight = currentHeight,
  }, rows))
end

local function render(state)
  if not state or state.status == "Stopped" or state.status == "" then
    renderEmpty()
  elseif state.status == "Paused" then
    renderPaused(state)
  else
    renderPlaying(state)
  end
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

function update()
  noctalia.setUpdateInterval(100)

  local now = os.clock()
  local delta = lastClock > 0 and now - lastClock or 0
  lastClock = now

  lastState = readState() or lastState

  local targetHeight = MIN_HEIGHT
  if lastState and lastState.status == "Playing" then
    targetHeight = estimateContentHeight(lastState)
  end

  if targetHeight > currentHeight then
    currentHeight = targetHeight
  else
    currentHeight = currentHeight + (targetHeight - currentHeight) * math.min(1, delta * 4)
  end

  render(lastState)
end
