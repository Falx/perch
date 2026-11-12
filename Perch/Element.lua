local ADDON, P = ...
P = _G.Perch

local ICON_TEXT_PADDING = 4

local function fontSignature(font)
  return string.format("%s|%s|%s", tostring(font.name), tostring(font.size), tostring(font.outline))
end

-- The client raises "FontString:SetText(): Font not set" when text is assigned
-- before a font exists, so every text write goes through this first.
function P:ApplyCellFont(cell)
  local font = self.db.bar.font
  local signature = fontSignature(font)
  if cell.fontSignature ~= signature then
    -- A font path that does not resolve leaves the string without a font, and
    -- the next SetText would raise. Fall back to the default in that case.
    local ok, applied = pcall(cell.text.SetFont, cell.text, font.name, font.size, font.outline or "")
    if not (ok and applied) then
      cell.text:SetFont(P.DEFAULT_FONT, font.size, font.outline or "")
    end
    cell.fontSignature = signature
  end
end

-- Plugin callbacks are third-party code: never let one break the bar or spam
-- errors. The first failure per object is reported through /perch doctor.
function P:CallBrokerHandler(cell, key, ...)
  local data = cell and cell.obj
  local handler = data and data[key]
  if type(handler) ~= "function" then
    return false
  end
  local ok, err = pcall(handler, cell, ...)
  if not ok then
    self:RecordBrokerError(cell.brokerName or "?", err)
  end
  return ok
end

function P:CreateBrokerCell(name, obj)
  local cell = CreateFrame("Button", nil, self.bar)
  cell.brokerName = name
  cell.obj = obj
  -- A Button only reports the left button by default; plugins (and the
  -- built-ins) also want right-clicks.
  cell:RegisterForClicks("AnyUp")

  cell.text = cell:CreateFontString(nil, "OVERLAY")
  self:ApplyCellFont(cell)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cell.icon:Hide()

  cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
  cell.highlight:SetAllPoints(cell)
  cell.highlight:SetColorTexture(1, 1, 1, 0.15)

  -- LibDBIcon passes the display button as the first argument, and plugins
  -- (HidingBar, EnhanceQoL, ...) rely on that: they call frame methods on it.
  cell:SetScript("OnClick", function(frame, button)
    P:CallBrokerHandler(frame, "OnClick", button)
  end)

  cell:SetScript("OnMouseDown", function(frame, button)
    P:CallBrokerHandler(frame, "OnMouseDown", button)
  end)

  cell:SetScript("OnMouseUp", function(frame, button)
    P:CallBrokerHandler(frame, "OnMouseUp", button)
  end)

  cell:SetScript("OnEnter", function(frame)
    P:CallBrokerHandler(frame, "OnEnter")
    P:ShowBrokerTooltip(frame)
  end)

  cell:SetScript("OnLeave", function(frame)
    GameTooltip:Hide()
    P:CallBrokerHandler(frame, "OnLeave")
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
  -- A plugin is free to put anything in text/value; never let it break a cell.
  local ok, rendered = pcall(tostring, text)
  return ok and rendered or ""
end

-- What a cell shows: the plugin's value, optionally prefixed by a label. The
-- label is the custom one if set, else the plugin's own label, else its name.
function P:DisplayLabel(key, obj)
  local custom = self:ElementOption(key, "label")
  if custom and custom ~= "" then
    return custom
  end
  local label = obj and obj.label
  if type(label) == "string" and label ~= "" then
    return label
  end
  return key
end

function P:ComposeText(key, obj)
  local value = self:BrokerText(obj)
  local showValue = self:ElementOption(key, "showValue")
  local showLabel = self:ElementOption(key, "showLabel")
  if showLabel then
    local label = self:DisplayLabel(key, obj)
    if showValue and value ~= "" then
      return label .. ": " .. value
    end
    return label
  end
  if showValue then
    return value
  end
  return ""
end

function P:RefreshBrokerCell(cell, obj)
  if not cell then
    return
  end
  -- An unticked element must stay hidden even when its plugin keeps pushing
  -- updates; otherwise the poller re-shows it at its stale anchor.
  if not self:IsEnabled(cell.brokerName) then
    cell:Hide()
    return
  end
  local barDB = self.db.bar
  local text = self:ComposeText(cell.brokerName, obj)
  local hasIcon = (obj.icon ~= nil and barDB.showIcons ~= false
    and self:ElementOption(cell.brokerName, "showIcon")) and true or false

  if cell.lastText ~= text then
    -- Font first: SetText without a font is a hard error on 16001.
    self:ApplyCellFont(cell)
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

  self:ApplyCellFont(cell)
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
  -- Resizing a protected frame is blocked in combat. Broker cells should stay
  -- unprotected now that command cells live on UIParent, but keep this guard so
  -- a stray secure child can never produce ADDON_ACTION_BLOCKED again.
  if InCombatLockdown and InCombatLockdown() then
    cell.sizePending = true
    return
  end
  cell.sizePending = nil
  cell:SetWidth(math.max(cell.width, 1))
  cell:SetHeight(db.height)
end

function P:ShowBrokerTooltip(cell)
  local obj = cell.obj
  GameTooltip:SetOwner(cell, "ANCHOR_BOTTOM")
  GameTooltip:ClearLines()

  if obj and type(obj.OnTooltipShow) == "function" then
    local ok, err = pcall(obj.OnTooltipShow, GameTooltip)
    if not ok then
      self:RecordBrokerError(cell.brokerName or "?", err)
    end
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
