local ADDON, P = ...
P = _G.Perch

local UI = P.UI

local TOGGLES = {
  { "Lock the bar (unlock it to drag)", "locked", false },
  { "Enable icons", "showIcons", true },
  { "Hide bar when empty", "hideWhenEmpty", true },
  { "Fade until mouseover", "mouseoverFade", true },
  { "Hide in combat", "hideInCombat", true },
  { "Click-through (the mouse passes through the bar)", "clickThrough", true },
}

P:RegisterPage({
  id = "general",
  title = "General",
  build = function(content, track)
    local y = -48
    for _, toggle in ipairs(TOGGLES) do
      local key, apply = toggle[2], toggle[3]
      track(UI.checkbox(content, toggle[1], 24, y, function()
        return P.db.bar[key]
      end, function(value)
        P.db.bar[key] = value
        if apply then
          P:ApplyAll()
        end
      end))
      y = y - 30
    end

    track(UI.dropdown(content, "Font", 24, y - 14, 280, function()
      return P:FontItems()
    end, function()
      return P.db.bar.font.name
    end, function(path)
      P.db.bar.font.name = path
      P:ApplyAll()
    end))
  end,
})
