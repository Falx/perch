local ADDON, P = ...
P = _G.Perch

local UI = P.UI

local SLIDERS = {
  {
    "Scale",
    0.5,
    2.5,
    0.05,
    "%.2f",
    function()
      return P.db.bar.scale
    end,
    function(value)
      P.db.bar.scale = value
    end,
  },
  {
    "Font size",
    8,
    24,
    1,
    "%.0f",
    function()
      return P.db.bar.font.size
    end,
    function(value)
      P.db.bar.font.size = value
    end,
  },
  {
    "Bar height",
    14,
    40,
    1,
    "%.0f",
    function()
      return P.db.bar.height
    end,
    function(value)
      P.db.bar.height = value
    end,
  },
  {
    "Spacing",
    0,
    24,
    1,
    "%.0f",
    function()
      return P.db.bar.spacing
    end,
    function(value)
      P.db.bar.spacing = value
    end,
  },
  {
    "Icon size",
    8,
    32,
    1,
    "%.0f",
    function()
      return P.db.bar.iconSize
    end,
    function(value)
      P.db.bar.iconSize = value
    end,
  },
  {
    "Background alpha",
    0,
    1,
    0.05,
    "%.2f",
    function()
      return P.db.bar.background.color[4] or 0.5
    end,
    function(value)
      P.db.bar.background.color[4] = value
    end,
  },
}

-- Reset targets for the "Default" buttons, straight from the shipped defaults.
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
}

P:RegisterPage({
  id = "appearance",
  title = "Appearance",
  build = function(content, track)
    track(UI.dropdown(content, "Font", 24, -48, 280, function()
      return P:FontItems()
    end, function()
      return P.db.bar.font.name
    end, function(path)
      P.db.bar.font.name = path
      P:ApplyAll()
    end))

    track(UI.checkbox(content, "Show background", 24, -112, function()
      return P.db.bar.background.enabled
    end, function(value)
      P.db.bar.background.enabled = value
      P:ApplyAll()
    end))

    local y = -166
    for _, spec in ipairs(SLIDERS) do
      local setter = spec[7]
      track(UI.slider(content, spec[1], 24, y, spec[2], spec[3], spec[4], spec[6], function(value)
        setter(value)
        P:ApplyAll()
      end, spec[5], DEFAULTS[spec[1]]))
      y = y - 48
    end
  end,
})
