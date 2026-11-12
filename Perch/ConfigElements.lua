local ADDON, P = ...
P = _G.Perch

local UI = P.UI

local ROW_HEIGHT = 22
local LIST_WIDTH, LIST_HEIGHT = 250, 520
local DETAIL_X = 300

local function selectedKey()
  local key = P.selectedElement
  if key and P:GetCell(key) then
    return key
  end
  key = P:AllKeys()[1]
  P.selectedElement = key
  return key
end

-- Every element Perch knows about, in bar order, hidden ones included. Picking
-- one shows its options on the right. New LDB plugins appear automatically.
local function elementList(parent, x, y)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  scroll:SetSize(LIST_WIDTH, LIST_HEIGHT)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_WIDTH - 26, 1)
  scroll:SetScrollChild(child)

  local widget = { rows = {}, child = child }

  function widget.refresh()
    local keys = P:AllKeys()
    local current = selectedKey()
    for index, key in ipairs(keys) do
      local row = widget.rows[index]
      if not row then
        row = CreateFrame("Button", nil, child)
        row:SetSize(LIST_WIDTH - 26, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints(row)
        row.selection:SetColorTexture(0.2, 0.45, 0.85, 0.35)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(1, 1, 1, 0.1)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
        row:SetScript("OnClick", function(self)
          P.selectedElement = self.elementKey
          P:RefreshOptions()
        end)
        widget.rows[index] = row
      end
      row.elementKey = key
      row.label:SetText(string.format("%s (%s)", P:ElementTitle(key), P:ElementKind(key)))
      if P:IsEnabled(key) then
        row.label:SetTextColor(1, 1, 1, 1)
      else
        row.label:SetTextColor(0.55, 0.55, 0.55, 1)
      end
      row.selection:SetShown(key == current)
      row:Show()
    end
    for index = #keys + 1, #widget.rows do
      widget.rows[index]:Hide()
    end
    child:SetHeight(math.max(#keys * ROW_HEIGHT, 1))
  end

  return widget
end

-- A checkbox bound to one option of the selected element.
local function flag(parent, text, y, getter, setter, applicable)
  local widget = UI.checkbox(parent, text, DETAIL_X, y, function()
    return selectedKey() ~= nil and getter(selectedKey())
  end, function(value)
    local key = selectedKey()
    if key then
      setter(key, value)
    end
  end)
  local base = widget.refresh
  widget.refresh = function()
    base()
    local key = selectedKey()
    widget:SetEnabled(key ~= nil and (applicable == nil or applicable(key)))
  end
  return widget
end

local function isBroker(key)
  local cell = P:GetCell(key)
  return cell ~= nil and not cell.isCommand
end

P:RegisterPage({
  id = "elements",
  title = "Elements",
  build = function(content, track)
    UI.label(content, "Pick an element to change how it appears.", 16, -40, "GameFontHighlightSmall")
    track(elementList(content, 16, -64))

    local header = UI.label(content, "", DETAIL_X, -48, "GameFontNormal")
    track({
      refresh = function()
        local key = selectedKey()
        if key then
          header:SetText(string.format("%s (%s)", P:ElementTitle(key), P:ElementKind(key)))
        else
          header:SetText("No elements yet")
        end
      end,
    })

    track(flag(content, "Show on the bar", -84, function(key)
      return P:IsEnabled(key)
    end, function(key, value)
      P:SetElementEnabled(key, value)
    end))

    track(flag(content, "Icon", -114, function(key)
      return P:ElementOption(key, "showIcon")
    end, function(key, value)
      P:SetElementOption(key, "showIcon", value)
    end))

    track(flag(content, "Label", -144, function(key)
      return P:ElementOption(key, "showLabel")
    end, function(key, value)
      P:SetElementOption(key, "showLabel", value)
    end))

    track(flag(content, "Value", -174, function(key)
      return P:ElementOption(key, "showValue")
    end, function(key, value)
      P:SetElementOption(key, "showValue", value)
    end, isBroker))

    UI.label(content, "Custom label", DETAIL_X, -214, "GameFontHighlight")
    local labelBox = track(UI.editbox(content, DETAIL_X + 6, -234, 220, function()
      local key = selectedKey()
      return key and P:ElementOption(key, "label") or ""
    end, function(text)
      local key = selectedKey()
      if key then
        P:SetElementOption(key, "label", text)
      end
    end, true))
    P.elementLabelBox = labelBox
    UI.label(content, "Shown when Label is ticked. Empty uses the default.", DETAIL_X, -262, "GameFontDisableSmall")

    local up = UI.button(content, "Move up", DETAIL_X, -300, function()
      local key = selectedKey()
      if key then
        P:MoveElement(key, -1)
      end
    end, 105)
    local down = UI.button(content, "Move down", DETAIL_X + 115, -300, function()
      local key = selectedKey()
      if key then
        P:MoveElement(key, 1)
      end
    end, 105)
    track({
      refresh = function()
        local key = selectedKey()
        local keys = P:AllKeys()
        local index
        for position, candidate in ipairs(keys) do
          if candidate == key then
            index = position
          end
        end
        up:SetEnabled(index ~= nil and index > 1)
        down:SetEnabled(index ~= nil and index < #keys)
      end,
    })
  end,
})
