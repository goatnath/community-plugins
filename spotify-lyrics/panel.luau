--!nonstrict
-- Spotify Lyrics Panel – 3-line synced lyrics view.
--
-- Reads state from ~/.cache/noctalia/lyrics/current.json (written by the daemon)
-- and renders prev / current / next lyric lines. Panel height dynamically
-- expands when lyrics wrap to multiple lines, preventing text overflow.

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
-- Height estimation
--
-- The old per-character width table consistently underestimated real rendered
-- widths, causing getLinesCount to return too few lines.  We now use a dead-
-- simple heuristic: divide #text (byte length) by a conservative chars-per-
-- line estimate.  For ASCII lyrics the byte count equals char count; for any
-- multibyte chars it *overestimates*, which is the safe direction.
--------------------------------------------------------------------------------

--- Estimate how many visual lines `text` occupies at `fontSize` inside INNER_WIDTH.
local function estimateLines(text, fontSize)
  if not text or text == "" then return 0 end
  -- Each character is roughly 0.60 × fontSize pixels wide on average.
  -- This intentionally overestimates character width, producing fewer
  -- chars-per-line → more estimated lines → more allocated height.
  local charsPerLine = math.max(1, math.floor(INNER_WIDTH / (fontSize * 0.60)))
  return math.max(1, math.ceil(#text / charsPerLine))
end

--- Compute total pixel height the panel content will need.
local function estimateContentHeight(state)
  local h = PANEL_PADDING * 2  -- top + bottom padding

  -- Header: music icon + title text + divider
  if state.title and state.artist then
    h = h + 14                                                           -- icon
    h = h + 4                                                            -- gap in header column
    h = h + estimateLines(state.title .. " • " .. state.artist, 12) * 18 -- title
    h = h + 8 + 1 + 8                                                   -- gap, divider, gap
  end

  -- Previous lyric (fontSize 14, ~20px line height)
  if (state.prev or "") ~= "" then
    h = h + estimateLines(state.prev, 14) * 20
  else
    h = h + 16
  end
  h = h + 8  -- gap

  -- Current lyric (fontSize 18 bold, ~26px line height)
  h = h + estimateLines(state.current or "...", 18) * 26
  h = h + 8  -- gap

  -- Next lyric (fontSize 14, ~20px line height)
  if (state.next or "") ~= "" then
    h = h + estimateLines(state.next, 14) * 20
  else
    h = h + 16
  end

  h = h + 24  -- safety buffer for font rendering variance
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

  -- Previous lyric (faded)
  if (state.prev or "") ~= "" then
    table.insert(rows, ui.label({
      text = state.prev,
      fontSize = 14, fontWeight = "medium",
      color = "on_surface/0.4", textAlign = "center", wrap = true,
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  -- Current lyric (bold, prominent)
  table.insert(rows, ui.label({
    text = state.current or "...",
    fontSize = 18, fontWeight = "bold",
    color = "on_surface/0.95", textAlign = "center", wrap = true,
  }))

  -- Next lyric (faded)
  if (state.next or "") ~= "" then
    table.insert(rows, ui.label({
      text = state.next,
      fontSize = 14, fontWeight = "medium",
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
  noctalia.setUpdateInterval(100)  -- 10 FPS: smooth enough for lyrics sync

  local now = os.clock()
  local delta = lastClock > 0 and now - lastClock or 0
  lastClock = now

  -- Read state (daemon writes at ~3 Hz, so 10 Hz reads is plenty)
  lastState = readState() or lastState

  -- Determine target height
  local targetHeight = MIN_HEIGHT
  if lastState and lastState.status == "Playing" then
    targetHeight = estimateContentHeight(lastState)
  end

  -- Height grows INSTANTLY (prevents any spill frames), shrinks smoothly
  if targetHeight > currentHeight then
    currentHeight = targetHeight
  else
    currentHeight = currentHeight + (targetHeight - currentHeight) * math.min(1, delta * 4)
  end

  render(lastState)
end
