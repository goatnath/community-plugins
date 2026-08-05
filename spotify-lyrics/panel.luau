--!nonstrict
-- Lyrics panel: 3-line synced view (prev / current / next).

local BASE_WIDTH = 460
local BASE_HEIGHT = 160

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
  local charWidth = fontSize * 0.70 
  return units * charWidth
end

local function getDynamicFontSize(text, defaultSize, maxWidth)
  if not text or text == "" then return defaultSize end
  local width = getLineWidth(text, defaultSize)
  if width <= maxWidth then return defaultSize end
  
  -- Scale down font size so it attempts to fit on 1-2 lines without massive vertical growth
  local scale = maxWidth / width
  -- If it's extremely long, we allow it to wrap by capping the minimum font size.
  -- A smaller font size wrapping to 2 lines takes up the same height as a large font on 1 line!
  local minSize = math.max(10, math.floor(defaultSize * 0.6))
  local newSize = math.floor(defaultSize * scale)
  
  return math.max(minSize, newSize)
end

local function readState()
  local content = noctalia.readFile("~/.cache/noctalia/lyrics/current.json")
  if not content then return nil end
  local state, _ = noctalia.json.decode(content)
  return state
end

local function render(state)
  if not state or state.status == "Stopped" or state.status == "" then
    panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = BASE_HEIGHT }, {
      ui.row({ justify = "center" }, { ui.glyph({ name = "music", size = 28, color = "on_surface/0.2" }) }),
      ui.label({ text = "No music playing", fontSize = 14, fontWeight = "medium", color = "on_surface/0.25", textAlign = "center" }),
    }))
    return
  end

  if state.status == "Paused" then
    panel.render(ui.column({ flexGrow = 1, gap = 6, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = BASE_HEIGHT }, {
      ui.row({ gap = 6, justify = "center", align = "center" }, {
        ui.glyph({ name = "player-pause", size = 16, color = "on_surface/0.3" }),
        ui.label({
          text = (state.title or "Paused") .. " • " .. (state.artist or ""),
          fontSize = 12,
          fontWeight = "medium",
          color = "on_surface/0.4",
          textAlign = "center",
          wrap = true,
        }),
      }),
      ui.label({
        text = state.current or "Paused",
        fontSize = 18,
        fontWeight = "bold",
        color = "on_surface/0.6",
        textAlign = "center",
        wrap = true,
      }),
    }))
    return
  end

  local innerW = BASE_WIDTH - 32
  local rows = {}

  if state.title and state.artist then
    table.insert(rows, ui.column({ gap = 4, align = "stretch" }, {
      ui.row({ justify = "center" }, { ui.glyph({ name = "music", size = 14, color = "primary/0.7" }) }),
      ui.label({
        text = state.title .. " • " .. state.artist,
        fontSize = 12,
        fontWeight = "medium",
        color = "primary/0.7",
        textAlign = "center",
        wrap = true,
      }),
    }))
    table.insert(rows, ui.box({ height = 1, fill = "on_surface/0.06" }))
  end

  local prevText = state.prev or ""
  if prevText ~= "" then
    table.insert(rows, ui.label({
      text = prevText,
      fontSize = getDynamicFontSize(prevText, 14, innerW),
      fontWeight = "medium",
      color = "on_surface/0.4",
      wrap = true,
      textAlign = "center",
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  local currentText = state.current or "..."
  table.insert(rows, ui.label({
    text = currentText,
    fontSize = getDynamicFontSize(currentText, 18, innerW),
    fontWeight = "bold",
    color = "on_surface/0.95",
    wrap = true,
    textAlign = "center",
  }))

  local nextText = state.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = nextText,
      fontSize = getDynamicFontSize(nextText, 14, innerW),
      fontWeight = "medium",
      color = "on_surface/0.4",
      wrap = true,
      textAlign = "center",
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = BASE_HEIGHT }, rows))
end

local lastState = nil
local fileCheckTimer = 0

function update()
  noctalia.setUpdateInterval(100)
  
  local now = os.clock()
  local delta = 0.1
  
  fileCheckTimer = fileCheckTimer + delta
  if fileCheckTimer >= 0.2 then
    fileCheckTimer = 0
    lastState = readState() or lastState
  end
  
  render(lastState)
end
