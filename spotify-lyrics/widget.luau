--!nonstrict
-- Spotify Lyrics desktop widget.
-- Reads current lyrics state written by the Python daemon.
-- Displays 3 lines: previous → current (highlighted) → next.

local BASE_WIDTH = 400
local currentPanelWidth = 400
local lastClock = os.clock()

local function charUnits(char)
  if char == " " or char == "\t" then return 0.35 end
  local byte = char:byte(1) or 0
  if byte < 0x80 then
    if char:match("[%.,:;!'|ilI%-%(%)]") then return 0.38 end
    if char:match("[MW@#%%&]") then return 0.85 end
    return 0.58
  end
  return 1
end

local function toChars(text)
  local chars = {}
  local i = 1
  while i <= #text do
    local byte = text:byte(i)
    local length = 1
    if byte >= 0xF0 then length = 4
    elseif byte >= 0xE0 then length = 3
    elseif byte >= 0xC0 then length = 2 end
    chars[#chars + 1] = text:sub(i, i + length - 1)
    i = i + length
  end
  return chars
end

local function getLineWidth(text, fontSize)
  if not text or text == "" then return 0 end
  local units = 0
  for _, char in ipairs(toChars(text)) do
    units = units + charUnits(char)
  end
  local charWidth = fontSize * 0.6
  return units * charWidth
end

local function truncateText(text, fontSize, maxWidth)
  local chars = toChars(text or "")
  local units = 0
  local charW = fontSize * 0.6
  local maxU = maxWidth / charW
  
  local last = 0
  for i, char in ipairs(chars) do
    local u = charUnits(char)
    if units + u > maxU + 0.01 then break end
    units = units + u
    last = i
  end
  
  local res = ""
  for i = 1, last do res = res .. chars[i] end
  return res
end

local function readState()
  local content = noctalia.readFile("~/.cache/noctalia/lyrics/current.json")
  if not content then return nil end
  local state, _ = noctalia.json.decode(content)
  return state
end

local function render(lyricsState)
  -- When idle or paused, show a minimal status indicator
  if not lyricsState or lyricsState.status == "Stopped" or lyricsState.status == "" then
    desktopWidget.render(ui.column({ gap = 8, align = "center", minWidth = currentPanelWidth }, {
      ui.glyph({ name = "music", size = 28, color = "on_surface/0.3" }),
      ui.label({
        text = "No music playing",
        fontSize = 16,
        fontWeight = "medium",
        color = "on_surface/0.3",
      }),
    }))
    return
  end

  if lyricsState.status == "Paused" then
    desktopWidget.render(ui.column({ gap = 8, align = "center", minWidth = currentPanelWidth }, {
      ui.glyph({ name = "player-pause", size = 22, color = "on_surface/0.4" }),
      ui.label({
        text = truncateText(lyricsState.current or "Paused", 22, currentPanelWidth),
        fontSize = 22,
        fontWeight = "bold",
        color = "on_surface/0.5",
        maxLines = 1,
      }),
    }))
    return
  end

  -- ── Playing: render 3-line synced lyrics ──

  local rows = {}

  -- Track info: small, subtle line at the top
  if lyricsState.title and lyricsState.artist then
    table.insert(rows, ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "music", size = 12, color = "primary/0.7" }),
      ui.label({
        text = truncateText(lyricsState.title .. " — " .. lyricsState.artist, 11, currentPanelWidth - 18),
        fontSize = 11,
        fontWeight = "medium",
        color = "primary/0.6",
        maxLines = 1,
      }),
    }))
  end

  -- Thin separator
  table.insert(rows, ui.box({ height = 1, fill = "on_surface/0.08" }))

  -- Previous line (dimmed)
  local prevText = lyricsState.prev or ""
  if prevText ~= "" then
    table.insert(rows, ui.label({
      text = truncateText(prevText, 18, currentPanelWidth),
      fontSize = 18,
      fontWeight = "normal",
      color = "on_surface/0.3",
      wrap = false,
    }))
  else
    table.insert(rows, ui.box({ height = 18 })) -- spacer to keep layout stable
  end

  -- Current line (bold, large, highlighted)
  local currentText = lyricsState.current or "..."
  table.insert(rows, ui.label({
    text = truncateText(currentText, 26, currentPanelWidth),
    fontSize = 26,
    fontWeight = "bold",
    color = "on_surface",
    wrap = false,
  }))

  -- Next line (dimmed)
  local nextText = lyricsState.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = truncateText(nextText, 18, currentPanelWidth),
      fontSize = 18,
      fontWeight = "normal",
      color = "on_surface/0.3",
      wrap = false,
    }))
  else
    table.insert(rows, ui.box({ height = 18 })) -- spacer
  end

  desktopWidget.render(ui.column({ gap = 10, align = "center", minWidth = currentPanelWidth }, rows))
end

function update()
  noctalia.setUpdateInterval(33)
  
  local now = os.clock()
  local delta = lastClock > 0 and now - lastClock or 0
  lastClock = now
  
  local state = readState()
  local targetWidth = BASE_WIDTH
  
  if state and state.status == "Playing" then
    local titleText = (state.title or "") .. " — " .. (state.artist or "")
    targetWidth = math.max(targetWidth, getLineWidth(titleText, 11) + 18)
    targetWidth = math.max(targetWidth, getLineWidth(state.prev or "", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.current or "...", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.next or "", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.next_next or "", 26))
    targetWidth = targetWidth + 16 -- Add extra safe buffer
  end
  
  currentPanelWidth = currentPanelWidth + (targetWidth - currentPanelWidth) * math.min(1, delta * 6)
  
  render(state)
end
