local ADDON, P = ...
P = _G.Perch

function P:CreateBar()
  if self.bar then
    return
  end
  local db = self.db.bar
  local bar = CreateFrame("Frame", "PerchBar", UIParent)
  bar:SetSize(1, db.height)
  bar:SetPoint(db.point or "TOP", UIParent, db.relativePoint or "TOP", db.x or 0, db.y or -8)
  bar:SetFrameStrata("LOW")
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  bar:EnableMouse(not db.clickThrough)
  bar:RegisterForDrag("LeftButton")

  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(bar)

  bar:SetScript("OnDragStart", function(frame)
    if not P.db.bar.locked then
      frame:StartMoving()
    end
  end)

  bar:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    P:SavePosition()
  end)

  bar:SetScript("OnEnter", function(frame)
    if P.db.bar.mouseoverFade then
      frame:SetAlpha(1)
    end
  end)

  bar:SetScript("OnLeave", function(frame)
    if P.db.bar.mouseoverFade then
      frame:SetAlpha(0.35)
    end
  end)

  self.bar = bar
  self:ApplyBarStyle()
end

function P:ApplyBarStyle()
  local bar = self.bar
  if not bar then
    return
  end
  local db = self.db.bar
  bar:SetScale(db.scale)
  bar:SetHeight(db.height)
  bar:EnableMouse(not db.clickThrough)
  bar:SetAlpha(db.mouseoverFade and 0.35 or 1)

  local background = db.background
  bar.bg:SetShown(background.enabled ~= false)
  if background.texture then
    bar.bg:SetTexture(background.texture)
  end
  local color = background.color
  if color then
    bar.bg:SetVertexColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 0.5)
  end
end

function P:SavePosition()
  if not self.bar or not self.db then
    return
  end
  local point, _, relativePoint, x, y = self.bar:GetPoint()
  local db = self.db.bar
  db.point = point
  db.relativePoint = relativePoint
  db.x = x
  db.y = y
end

function P:RestorePosition()
  if not self.bar then
    return
  end
  local db = self.db.bar
  self.bar:ClearAllPoints()
  self.bar:SetPoint(db.point or "TOP", UIParent, db.relativePoint or "TOP", db.x or 0, db.y or -8)
end

function P:GetCell(key)
  if not key then
    return nil
  end
  local broker = self.brokerElements and self.brokerElements[key]
  if broker then
    return broker
  end
  return self.commandCells and self.commandCells[key]
end

function P:AllKeys()
  local keys, seen = {}, {}

  for _, key in ipairs(self.db.order) do
    if not seen[key] and self:GetCell(key) then
      keys[#keys + 1] = key
      seen[key] = true
    end
  end

  local extra = {}
  for key in pairs(self.brokerElements or {}) do
    if not seen[key] then
      extra[#extra + 1] = key
    end
  end
  for key in pairs(self.commandCells or {}) do
    if not seen[key] then
      extra[#extra + 1] = key
    end
  end
  table.sort(extra)
  for _, key in ipairs(extra) do
    keys[#keys + 1] = key
  end

  return keys
end

function P:OrderedKeys()
  local keys = {}
  for _, key in ipairs(self:AllKeys()) do
    if self:IsEnabled(key) then
      keys[#keys + 1] = key
    end
  end
  return keys
end

function P:RequestLayout()
  if self.layoutPending then
    return
  end
  self.layoutPending = true
  C_Timer.After(0, function()
    P.layoutPending = false
    local ok, err = pcall(P.Layout, P)
    if not ok then
      P.layoutError = tostring(err)
    end
  end)
end

function P:Layout()
  local bar = self.bar
  if not bar then
    return
  end
  -- Command cells are secure buttons: ClearAllPoints/SetPoint on them is
  -- blocked in combat. Skip the pass and let PLAYER_REGEN_ENABLED retry.
  if InCombatLockdown and InCombatLockdown() then
    self.layoutDeferred = true
    return
  end
  self.layoutDeferred = nil
  local db = self.db.bar
  local previous
  local width = db.padding * 2

  for _, key in ipairs(self:OrderedKeys()) do
    local cell = self:GetCell(key)
    if cell and cell:IsShown() then
      cell:ClearAllPoints()
      if previous then
        cell:SetPoint("LEFT", previous, "RIGHT", db.spacing, 0)
        width = width + db.spacing
      else
        cell:SetPoint("LEFT", bar, "LEFT", db.padding, 0)
      end
      width = width + (cell.width or 0)
      previous = cell
    end
  end

  bar:SetWidth(math.max(width, 1))
  bar:SetHeight(db.height)

  local showBar = (width > db.padding * 2 + 1) or not db.hideWhenEmpty
  if db.hideInCombat and InCombatLockdown() then
    showBar = false
  end
  bar:SetShown(showBar)
end

function P:ListElements()
  local keys = self:AllKeys()
  if #keys == 0 then
    self:Print("No elements available yet.")
    return
  end
  self:Print("Elements ([off] = hidden, configure with /perch enable|disable):")
  for index, key in ipairs(keys) do
    local cell = self:GetCell(key)
    local label = cell and cell:ContentLabel() or key
    self:Print(string.format("  %2d. %s%s  (%s)", index, self:IsEnabled(key) and "" or "[off] ", key, label))
  end
end

function P:ResolveKey(fragment)
  fragment = (fragment or ""):lower()
  if fragment == "" then
    return nil
  end
  for _, key in ipairs(self:AllKeys()) do
    if key:lower() == fragment then
      return key
    end
  end
  for _, key in ipairs(self:AllKeys()) do
    if key:lower():find(fragment, 1, true) then
      return key
    end
  end
  return nil
end
