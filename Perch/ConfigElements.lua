local ADDON, P = ...
P = _G.Perch

local UI = P.UI

local ROW_HEIGHT = 22

-- Every element Perch knows about, including the ones that are off. New LDB
-- plugins show up here automatically.
local function elementList(parent, x, y, width, height)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  scroll:SetSize(width, height)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width - 26, 1)
  scroll:SetScrollChild(child)

  local widget = { rows = {}, child = child }

  function widget.refresh()
    local keys = P:AllKeys()
    for index, key in ipairs(keys) do
      local row = widget.rows[index]
      if not row then
        row = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
        row:SetSize(20, 20)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row.label = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row:SetScript("OnClick", function(self)
          P:SetElementEnabled(self.elementKey, self:GetChecked() and true or false)
        end)
        widget.rows[index] = row
      end
      row.elementKey = key
      row.label:SetText(string.format("%s (%s)", key, P:ElementKind(key)))
      row:SetChecked(P:IsEnabled(key))
      row:Show()
    end
    for index = #keys + 1, #widget.rows do
      widget.rows[index]:Hide()
    end
    child:SetHeight(math.max(#keys * ROW_HEIGHT, 1))
  end

  return widget
end

P:RegisterPage({
  id = "elements",
  title = "Elements",
  build = function(content, track)
    UI.label(content, "Launchers start hidden; tick an element to show it.", 16, -40, "GameFontHighlightSmall")
    track(elementList(content, 16, -64, 330, 500))
  end,
})
