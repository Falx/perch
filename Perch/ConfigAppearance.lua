local ADDON, P = ...
P = _G.Perch

local UI = P.UI

-- Keeps an optional leading minus and the digits: typed text that cannot be a
-- whole number is dropped.
local function signedWholeNumber(text)
  local sign = text:sub(1, 1) == "-" and "-" or ""
  return sign .. (text:gsub("[^%d]", ""))
end

local ALIGNMENT_ITEMS = {
  { label = "Top left", value = "TOPLEFT" },
  { label = "Top center", value = "TOP" },
  { label = "Top right", value = "TOPRIGHT" },
  { label = "Custom (dragged)", value = "custom" },
}

-- A slider's reset target, straight from the shipped defaults.
local DEFAULTS = {
  ["Scale"] = function()
    return P.defaults.bar.scale
  end,
  ["Font size"] = function()
    return P.defaults.bar.font.size
  end,
  ["Bar height"] = function()
    return P.defaults.bar.height
  end,
  ["Spacing"] = function()
    return P.defaults.bar.spacing
  end,
  ["Icon size"] = function()
    return P.defaults.bar.iconSize
  end,
  ["Background alpha"] = function()
    return P.defaults.bar.background.color[4]
  end,
  ["Border alpha"] = function()
    return P.defaults.bar.border.color[4]
  end,
  ["Border size"] = function()
    return P.defaults.bar.border.size
  end,
  ["End cap width"] = function()
    return P.defaults.bar.caps.width
  end,
}

-- { label, min, max, step, format, getter, setter }
local function sliderSpec(label, minimum, maximum, step, format, getter, setter)
  return { label, minimum, maximum, step, format, getter, setter }
end

local function barValue(key)
  return function()
    return P.db.bar[key]
  end, function(value)
    P.db.bar[key] = value
  end
end

P:RegisterPage({
  id = "appearance",
  title = "Appearance",
  scrollHeight = 1200,
  build = function(content, track)
    local y = -8

    local function section(title)
      UI.label(content, title, 16, y, "GameFontNormal")
      y = y - 28
    end

    local function addSlider(spec)
      local setter = spec[7]
      track(UI.slider(content, spec[1], 24, y - 14, spec[2], spec[3], spec[4], spec[6], function(value)
        setter(value)
        P:ApplyAll()
      end, spec[5], DEFAULTS[spec[1]]))
      y = y - 52
    end

    local function addCheckbox(text, getter, setter)
      track(UI.checkbox(content, text, 24, y, getter, function(value)
        setter(value)
        P:ApplyAll()
        P:RefreshOptions()
      end))
      y = y - 30
    end

    --
    -- Position and text
    --
    section("Position")
    track(UI.dropdown(content, "Alignment", 24, y, 220, function()
      return ALIGNMENT_ITEMS
    end, function()
      return P.db.bar.alignment
    end, function(value)
      P:SetAlignment(value)
    end))
    y = y - 56

    -- Pixel offsets from the anchor corner, filled in with where the bar is now
    -- (dragging updates them), for fine tuning.
    -- The screen counts Y downwards here (like a web page), so a negative Y moves
    -- the bar up. The game's own offset counts upwards, hence the sign.
    local function offsetBox(title, x, key, sign)
      UI.label(content, title, x, y, "GameFontHighlight")
      local box
      box = UI.editbox(content, x + 6, y - 20, 90, function()
        return tostring(math.floor(sign * (P.db.bar[key] or 0) + 0.5))
      end, function(text)
        local number = tonumber(text)
        if number then
          P:SetBarOffset(key, sign * number)
        end
      end, {
        live = true,
        maxLetters = 6,
        filter = signedWholeNumber,
        onArrow = function(direction)
          local typed = tonumber(box.box:GetText())
          local shown = typed or (sign * (P.db.bar[key] or 0))
          local value = P:SetBarOffset(key, sign * (shown + direction))
          box.setText(tostring(math.floor(sign * value + 0.5)))
        end,
      })
      P.offsetBoxes = P.offsetBoxes or {}
      P.offsetBoxes[key] = box
      return track(box)
    end
    offsetBox("X offset (px)", 24, "x", 1)
    offsetBox("Y offset (px)", 150, "y", -1)
    y = y - 54
    local offsetNote = UI.label(content, "Measured from the anchor corner. A negative Y moves the bar up, even off the screen.", 24, y, "GameFontDisableSmall")
    offsetNote:SetWidth(380)
    offsetNote:SetJustifyH("LEFT")
    y = y - 26

    track(UI.dropdown(content, "Font", 24, y, 280, function()
      return P:FontItems()
    end, function()
      return P.db.bar.font.name
    end, function(path)
      P.db.bar.font.name = path
      P:ApplyAll()
    end))
    y = y - 56

    --
    -- Background
    --
    section("Background")
    track(UI.dropdown(content, "Texture", 24, y, 280, function()
      local items = {}
      for _, entry in ipairs(P:MediaList("background")) do
        items[#items + 1] = { label = entry.name, value = entry.path, preview = entry.path }
      end
      return items
    end, function()
      return P.db.bar.background.texture
    end, function(path)
      P.db.bar.background.texture = path
      P:ApplyAll()
      P:RefreshOptions()
    end))
    y = y - 56

    addCheckbox("Show background", function()
      return P.db.bar.background.enabled
    end, function(value)
      P.db.bar.background.enabled = value
    end)

    track(UI.color(content, "Colour", 24, y, function()
      local color = P.db.bar.background.color
      return color[1], color[2], color[3]
    end, function(r, g, b)
      local color = P.db.bar.background.color
      color[1], color[2], color[3] = r, g, b
      P:ApplyAll()
    end))
    y = y - 52

    addCheckbox("Tint a textured background with the colour", function()
      return P.db.bar.background.tint
    end, function(value)
      P.db.bar.background.tint = value
    end)

    addSlider(sliderSpec("Background alpha", 0, 1, 0.05, "%.2f", function()
      return P.db.bar.background.color[4] or 0.5
    end, function(value)
      P.db.bar.background.color[4] = value
    end))

    --
    -- Border
    --
    section("Border")
    addCheckbox("Show border", function()
      return P.db.bar.border.enabled
    end, function(value)
      P.db.bar.border.enabled = value
    end)

    track(UI.color(content, "Colour", 24, y, function()
      local color = P.db.bar.border.color
      return color[1], color[2], color[3]
    end, function(r, g, b)
      local color = P.db.bar.border.color
      color[1], color[2], color[3] = r, g, b
      P:ApplyAll()
    end))
    y = y - 52

    addSlider(sliderSpec("Border alpha", 0, 1, 0.05, "%.2f", function()
      return P.db.bar.border.color[4] or 1
    end, function(value)
      P.db.bar.border.color[4] = value
    end))
    addSlider(sliderSpec("Border size", 1, 8, 1, "%.0f", function()
      return P.db.bar.border.size
    end, function(value)
      P.db.bar.border.size = value
    end))

    --
    -- End caps
    --
    section("End caps")
    local function capDropdown(title, x, side)
      local dropdown = UI.dropdown(content, title, x, y, 160, function()
        return P:PresetItems(P.CAP_STYLES)
      end, function()
        return P.db.bar.caps[side]
      end, function(value)
        P.db.bar.caps[side] = value
        P:ApplyAll()
      end)
      -- Caps are drawn in the background's flat colour, so a textured
      -- background switches them off (the choice is kept for later).
      local base = dropdown.refresh
      dropdown.refresh = function()
        base()
        dropdown.setEnabled(P:IsSolidBackground() and P.db.bar.background.enabled ~= false)
      end
      return track(dropdown)
    end
    capDropdown("Left end", 24, "left")
    capDropdown("Right end", 200, "right")
    y = y - 56

    local capNote = UI.label(content, "End caps need a solid background colour (no texture).", 24, y, "GameFontDisableSmall")
    track({
      refresh = function()
        capNote:SetShown(not (P:IsSolidBackground() and P.db.bar.background.enabled ~= false))
      end,
    })
    y = y - 22

    addSlider(sliderSpec("End cap width", 2, 30, 1, "%.0f", function()
      return P.db.bar.caps.width
    end, function(value)
      P.db.bar.caps.width = value
    end))
    local widthNote = UI.label(content, "Applies to Curved 1 and Curved 3 (Curved 3 is 4.5 times as wide as this). Triangle and Curved 2 are as wide as the bar is high.", 24, y + 6, "GameFontDisableSmall")
    widthNote:SetWidth(520)
    widthNote:SetJustifyH("LEFT")
    y = y - 22

    --
    -- Size and text
    --
    section("Size and text")
    addSlider(sliderSpec("Scale", 0.5, 2.5, 0.05, "%.2f", barValue("scale")))
    addSlider(sliderSpec("Font size", 8, 24, 1, "%.0f", function()
      return P.db.bar.font.size
    end, function(value)
      P.db.bar.font.size = value
    end))
    addSlider(sliderSpec("Bar height", 14, 40, 1, "%.0f", barValue("height")))
    addSlider(sliderSpec("Spacing", 0, 24, 1, "%.0f", barValue("spacing")))
    addSlider(sliderSpec("Icon size", 8, 32, 1, "%.0f", barValue("iconSize")))
  end,
})
