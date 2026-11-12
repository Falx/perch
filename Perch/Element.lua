local ADDON, P = ...
P = _G.Perch

local ICON_TEXT_PADDING = 4

function P:CreateBrokerCell(name, obj)
  local cell = CreateFrame("Button", nil, self.bar)
  cell.brokerName = name
  cell.obj = obj

  cell.text = cell:CreateFontString(nil, "OVERLAY")
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cell.icon:Hide()

  cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
  cell.highlight:SetAllPoints(cell)
  cell.highlight:SetColorTexture(1, 1, 1, 0.15)

  cell:SetScript("OnClick", function(_, button)
    local data = cell.obj
    if data and type(data.OnClick) == "function" then
      data.OnClick(data, button)
    end
  end)

  cell:SetScript("OnMouseDown", function(_, button)
    local data = cell.obj
    if data and type(data.OnMouseDown) == "function" then
      data.OnMouseDown(data, button)
    end
  end)

  cell:SetScript("OnMouseUp", function(_, button)
    local data = cell.obj
    if data and type(data.OnMouseUp) == "function" then
      data.OnMouseUp(data, button)
    end
  end)

  cell:SetScript("OnEnter", function(frame)
    P:ShowBrokerTooltip(frame)
  end)

  cell:SetScript("OnLeave", function()
    GameTooltip:Hide()
    local data = cell.obj
    if data and type(data.OnLeave) == "function" then
      data.OnLeave(data)
    end
  end)

  function cell:ContentLabel()
    local data = self.obj
    if not data then
      return self.brokerName or "?"
    end
    local text = P:BrokerText(data)
    if text ~= "" then
      return text
    end
    return data.label or self.brokerName or "?"
  end

  return cell
end

function P:BrokerText(obj)
  if not obj then
    return ""
  end
  if obj.type == "launcher" then
    return obj.text or ""
  end
  local text = obj.text
  if text == nil then
    text = obj.value
  end
  if text == nil then
    return ""
  end
  return tostring(text)
end

function P:RefreshBrokerCell(cell, obj)
  if not cell then
    return
  end
  local barDB = self.db.bar
  local text = self:BrokerText(obj)
  local hasIcon = (obj.icon ~= nil and barDB.showIcons ~= false) and true or false

  if cell.lastText ~= text then
    cell.text:SetText(text)
    cell.lastText = text
  end

  if cell.lastIcon ~= obj.icon then
    if obj.icon then
      cell.icon:SetTexture(obj.icon)
    end
    cell.lastIcon = obj.icon
  end

  cell.iconVisible = hasIcon
  cell.icon:SetShown(hasIcon)

  self:SizeCell(cell)

  if text == "" and not hasIcon then
    cell:Hide()
  else
    cell:Show()
  end

  self:RequestLayout()
end

function P:SizeCell(cell)
  local db = self.db.bar
  local font = db.font

  cell.text:SetFont(font.name, font.size, font.outline or "")
  if font.color then
    cell.text:SetTextColor(font.color[1] or 1, font.color[2] or 1, font.color[3] or 1, font.color[4] or 1)
  end

  local offset = 0
  if cell.iconVisible then
    offset = db.iconSize + ICON_TEXT_PADDING
    cell.icon:ClearAllPoints()
    cell.icon:SetSize(db.iconSize, db.iconSize)
    cell.icon:SetPoint("LEFT", cell, "LEFT", 0, 0)
  end

  cell.text:ClearAllPoints()
  cell.text:SetPoint("LEFT", cell, "LEFT", offset, 0)

  local textWidth = cell.text:GetStringWidth() or 0
  cell.width = offset + textWidth
  cell:SetWidth(math.max(cell.width, 1))
  cell:SetHeight(db.height)
end

function P:ShowBrokerTooltip(cell)
  local obj = cell.obj
  GameTooltip:SetOwner(cell, "ANCHOR_BOTTOM")
  GameTooltip:ClearLines()

  if obj and type(obj.OnEnter) == "function" then
    obj.OnEnter(obj)
  end

  if obj and type(obj.OnTooltipShow) == "function" then
    obj.OnTooltipShow(GameTooltip)
  else
    local title = (obj and obj.label) or cell.brokerName or "Perch"
    GameTooltip:SetText(tostring(title), 1, 1, 1)
    local value = self:BrokerText(obj)
    if value ~= "" then
      GameTooltip:AddLine(value, 0.8, 0.8, 0.8)
    end
  end

  GameTooltip:Show()
end
