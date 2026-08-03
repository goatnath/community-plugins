--!nonstrict
-- Spotify Lyrics desktop widget.

local BASE_WIDTH = 400
local BASE_HEIGHT = 160
local currentPanelWidth = 400
local currentPanelHeight = 160
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
  local charWidth = fontSize * 0.65 
  return units * charWidth
end

local function getLinesCount(text, fontSize, maxWidth)
  if not text or text == "" then return 0 end
  local w = getLineWidth(text, fontSize)
  return math.max(1, math.ceil(w / maxWidth))
end

local function readState()
  local content = noctalia.readFile("~/.cache/noctalia/lyrics/current.json")
  if not content then return nil end
  local state, _ = noctalia.json.decode(content)
  return state
end

local function render(lyricsState)
  if not lyricsState or lyricsState.status == "Stopped" or lyricsState.status == "" then
    desktopWidget.render(ui.column({ gap = 8, align = "center", minWidth = currentPanelWidth, minHeight = currentPanelHeight }, {
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
    desktopWidget.render(ui.column({ gap = 8, align = "center", minWidth = currentPanelWidth, minHeight = currentPanelHeight }, {
      ui.glyph({ name = "player-pause", size = 22, color = "on_surface/0.4" }),
      ui.label({
        text = lyricsState.current or "Paused",
        fontSize = 22,
        fontWeight = "bold",
        color = "on_surface/0.5",
        wrap = true,
      }),
    }))
    return
  end

  local rows = {}

  if lyricsState.title and lyricsState.artist then
    table.insert(rows, ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "music", size = 12, color = "primary/0.7" }),
      ui.label({
        text = lyricsState.title .. " — " .. lyricsState.artist,
        fontSize = 11,
        fontWeight = "medium",
        color = "primary/0.6",
        wrap = true,
      }),
    }))
  end

  table.insert(rows, ui.box({ height = 1, fill = "on_surface/0.08" }))

  local prevText = lyricsState.prev or ""
  if prevText ~= "" then
    table.insert(rows, ui.label({
      text = prevText,
      fontSize = 18,
      fontWeight = "normal",
      color = "on_surface/0.3",
      wrap = true,
      textAlign = "center",
    }))
  else
    table.insert(rows, ui.box({ height = 18 }))
  end

  local currentText = lyricsState.current or "..."
  table.insert(rows, ui.label({
    text = currentText,
    fontSize = 26,
    fontWeight = "bold",
    color = "on_surface",
    wrap = true,
    textAlign = "center",
  }))

  local nextText = lyricsState.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = nextText,
      fontSize = 18,
      fontWeight = "normal",
      color = "on_surface/0.3",
      wrap = true,
      textAlign = "center",
    }))
  else
    table.insert(rows, ui.box({ height = 18 })) 
  end

  desktopWidget.render(ui.column({ gap = 10, align = "center", minWidth = currentPanelWidth, minHeight = currentPanelHeight }, rows))
end

function update()
  noctalia.setUpdateInterval(33)
  
  local now = os.clock()
  local delta = lastClock > 0 and now - lastClock or 0
  lastClock = now
  
  local state = readState()
  local targetWidth = BASE_WIDTH
  local targetHeight = BASE_HEIGHT
  
  if state and state.status == "Playing" then
    local titleText = (state.title or "") .. " — " .. (state.artist or "")
    targetWidth = math.max(targetWidth, getLineWidth(titleText, 11) + 18)
    targetWidth = math.max(targetWidth, getLineWidth(state.prev or "", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.current or "...", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.next or "", 26))
    targetWidth = math.max(targetWidth, getLineWidth(state.next_next or "", 26))
    targetWidth = targetWidth + 16

    targetWidth = math.min(targetWidth, 1000)
    
    targetHeight = 20 + 20 
    if state.title then targetHeight = targetHeight + 16 + 1 end
    
    targetHeight = targetHeight + (state.prev ~= "" and getLinesCount(state.prev, 18, targetWidth) * 26 or 18)
    targetHeight = targetHeight + getLinesCount(state.current or "...", 26, targetWidth) * 36
    targetHeight = targetHeight + (state.next ~= "" and getLinesCount(state.next, 18, targetWidth) * 26 or 18)
  end
  
  currentPanelWidth = currentPanelWidth + (targetWidth - currentPanelWidth) * math.min(1, delta * 6)
  currentPanelHeight = currentPanelHeight + (targetHeight - currentPanelHeight) * math.min(1, delta * 6)
  
  render(state)
end
