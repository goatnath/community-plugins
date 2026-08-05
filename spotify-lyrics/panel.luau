--!nonstrict
-- Spotify Lyrics Panel – 3-line synced lyrics view.
--
-- Reads state from ~/.cache/noctalia/lyrics/current.json (written by the daemon)
-- and renders prev / current / next lyric lines.
--
-- Long lyrics are dynamically scaled to a smaller font size so they take up
-- less vertical space and never overflow the panel.

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------
local PANEL_WIDTH   = 460
local PANEL_PADDING = 16
local INNER_WIDTH   = PANEL_WIDTH - PANEL_PADDING * 2  -- 428px usable
local MIN_HEIGHT    = 160

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------
local currentHeight = MIN_HEIGHT
local lastState     = nil
local lastClock     = os.clock()

--------------------------------------------------------------------------------
-- Dynamic font sizing
--
-- Scale font size down for long lyrics to reduce wrapping.
-- Short text (<=40 chars) keeps the default size.
-- Every 15 chars beyond 40 reduces font by 2px, capped at a readable minimum.
--------------------------------------------------------------------------------

local function fitFontSize(text, defaultSize)
  if not text or text == "" then return defaultSize end
  local len = #text
  if len <= 40 then return defaultSize end
  local reduction = math.floor((len - 40) / 15) * 2
  return math.max(10, defaultSize - reduction)
end

--------------------------------------------------------------------------------
-- Height estimation (backup safety for minHeight)
--------------------------------------------------------------------------------

local function estimateLines(text, fontSize)
  if not text or text == "" then return 0 end
  local charsPerLine = math.max(1, math.floor(INNER_WIDTH / (fontSize * 0.60)))
  return math.max(1, math.ceil(#text / charsPerLine))
end

local function estimateContentHeight(state)
  local h = PANEL_PADDING * 2

  if state.title and state.artist then
    local titleSize = 12
    h = h + 14 + 4 + estimateLines(state.title .. " • " .. state.artist, titleSize) * 18
    h = h + 8 + 1 + 8
  end

  local prevSize = fitFontSize(state.prev, 14)
  if (state.prev or "") ~= "" then
    h = h + estimateLines(state.prev, prevSize) * math.ceil(prevSize * 1.4)
  else
    h = h + 16
  end
  h = h + 8

  local currentSize = fitFontSize(state.current, 18)
  h = h + estimateLines(state.current or "...", currentSize) * math.ceil(currentSize * 1.4)
  h = h + 8

  local nextSize = fitFontSize(state.next, 14)
  if (state.next or "") ~= "" then
    h = h + estimateLines(state.next, nextSize) * math.ceil(nextSize * 1.4)
  else
    h = h + 16
  end

  h = h + 24  -- safety buffer
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
  panel.render(ui.column({
    flexGrow = 1, gap = 8, align = "stretch", justify = "center",
    padding = PANEL_PADDING, minWidth = PANEL_WIDTH, minHeight = currentHeight,
  }, {
    ui.row({ justify = "center" }, {
      ui.glyph({ name = "music", size = 28, color = "on_surface/0.2" }),
    }),
    ui.label({
      text = "No music playing",
      fontSize = 14, fontWeight = "medium",
      color = "on_surface/0.25", textAlign = "center",
    }),
  }))
end

local function renderPaused(state)
  panel.render(ui.column({
    flexGrow = 1, gap = 6, align = "stretch", justify = "center",
    padding = PANEL_PADDING, minWidth = PANEL_WIDTH, minHeight = currentHeight,
  }, {
    ui.row({ gap = 6, justify = "center", align = "center" }, {
      ui.glyph({ name = "player-pause", size = 16, color = "on_surface/0.3" }),
      ui.label({
        text = (state.title or "Paused") .. " • " .. (state.artist or ""),
        fontSize = 12, fontWeight = "medium",
        color = "on_surface/0.4", textAlign = "center", wrap = true,
      }),
    }),
    ui.label({
      text = state.current or "Paused",
      fontSize = 18, fontWeight = "bold",
      color = "on_surface/0.6", textAlign = "center", wrap = true,
    }),
  }))
end

local function renderPlaying(state)
  local rows = {}

  -- Track header
  if state.title and state.artist then
    table.insert(rows, ui.column({ gap = 4, align = "stretch" }, {
      ui.row({ justify = "center" }, {
        ui.glyph({ name = "music", size = 14, color = "primary/0.7" }),
      }),
      ui.label({
        text = state.title .. " • " .. state.artist,
        fontSize = 12, fontWeight = "medium",
        color = "primary/0.7", textAlign = "center", wrap = true,
      }),
    }))
    table.insert(rows, ui.box({ height = 1, fill = "on_surface/0.06" }))
  end

  -- Previous lyric (dynamically scaled font)
  local prevText = state.prev or ""
  if prevText ~= "" then
    table.insert(rows, ui.label({
      text = prevText,
      fontSize = fitFontSize(prevText, 14), fontWeight = "medium",
      color = "on_surface/0.4", textAlign = "center", wrap = true,
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  -- Current lyric (dynamically scaled font)
  local currentText = state.current or "..."
  table.insert(rows, ui.label({
    text = currentText,
    fontSize = fitFontSize(currentText, 18), fontWeight = "bold",
    color = "on_surface/0.95", textAlign = "center", wrap = true,
  }))

  -- Next lyric (dynamically scaled font)
  local nextText = state.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = nextText,
      fontSize = fitFontSize(nextText, 14), fontWeight = "medium",
      color = "on_surface/0.4", textAlign = "center", wrap = true,
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  panel.render(ui.column({
    flexGrow = 1, gap = 8, align = "stretch", justify = "center",
    padding = PANEL_PADDING, minWidth = PANEL_WIDTH, minHeight = currentHeight,
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
