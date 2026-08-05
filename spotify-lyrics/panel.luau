--!nonstrict
-- Lyrics panel: 3-line synced view (prev / current / next).

local BASE_WIDTH = 460
local BASE_HEIGHT = 160
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
  local charWidth = fontSize * 0.80 
  return units * charWidth
end

local function getLinesCount(text, fontSize, availableWidth)
  if not text or text == "" then return 0 end
  local textWidth = getLineWidth(text, fontSize)
  local safeWidth = availableWidth * 0.80 
  return math.max(1, math.ceil(textWidth / safeWidth))
end

local function readState()
  local content = noctalia.readFile("~/.cache/noctalia/lyrics/current.json")
  if not content then return nil end
  local state, _ = noctalia.json.decode(content)
  return state
end

local function render(state)
  if not state or state.status == "Stopped" or state.status == "" then
    panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = currentPanelHeight }, {
      ui.row({ justify = "center" }, { ui.glyph({ name = "music", size = 28, color = "on_surface/0.2" }) }),
      ui.label({ text = "No music playing", fontSize = 14, fontWeight = "medium", color = "on_surface/0.25", textAlign = "center" }),
    }))
    return
  end

  if state.status == "Paused" then
    panel.render(ui.column({ flexGrow = 1, gap = 6, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = currentPanelHeight }, {
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
      fontSize = 14,
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
    fontSize = 18,
    fontWeight = "bold",
    color = "on_surface/0.95",
    wrap = true,
    textAlign = "center",
  }))

  local nextText = state.next or ""
  if nextText ~= "" then
    table.insert(rows, ui.label({
      text = nextText,
      fontSize = 14,
      fontWeight = "medium",
      color = "on_surface/0.4",
      wrap = true,
      textAlign = "center",
    }))
  else
    table.insert(rows, ui.box({ height = 16 }))
  end

  panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch", justify = "center", padding = 16, minWidth = BASE_WIDTH, minHeight = currentPanelHeight }, rows))
end

local lastState = nil
local fileCheckTimer = 0

function update()
  noctalia.setUpdateInterval(33)
  
  local now = os.clock()
  local delta = lastClock > 0 and now - lastClock or 0
  lastClock = now
  
  fileCheckTimer = fileCheckTimer + delta
  if fileCheckTimer >= 0.2 then
    fileCheckTimer = 0
    lastState = readState() or lastState
  end
  
  local state = lastState
  local targetHeight = BASE_HEIGHT
  
  if state and state.status == "Playing" then
    local innerW = BASE_WIDTH - 32
    targetHeight = 32 + 24 -- padding + gaps
    if state.title then targetHeight = targetHeight + 18 + 1 end
    
    targetHeight = targetHeight + (state.prev ~= "" and getLinesCount(state.prev, 14, innerW) * 20 or 16)
    targetHeight = targetHeight + getLinesCount(state.current or "...", 18, innerW) * 26
    targetHeight = targetHeight + (state.next ~= "" and getLinesCount(state.next, 14, innerW) * 20 or 16)
    
    -- Massive safety padding at the bottom to guarantee NO CLIPPING whatsoever
    targetHeight = targetHeight + 42
  end
  
  -- Snap height instantly if it needs to grow, to prevent spilling during animation
  if targetHeight > currentPanelHeight then
    currentPanelHeight = targetHeight
  else
    currentPanelHeight = currentPanelHeight + (targetHeight - currentPanelHeight) * math.min(1, delta * 6)
  end
  
  render(state)
end
