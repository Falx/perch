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
  -- Not clamped: the bar can be moved partly or fully off the screen. The
  -- command buttons follow a copy of its position, which is never clamped, so a
  -- clamped bar would leave them behind. Reset position brings it back.
  bar:SetClampedToScreen(false)
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
    -- Secure command cells sit on UIParent, so they only follow the bar when
    -- the layout pass runs.
    P:RequestLayout()
  end)

  bar:SetScript("OnEnter", function(frame)
    if P.db.bar.mouseoverFade then
      frame:SetAlpha(1)
      P:SetCommandAlpha(1)
    end
  end)

  bar:SetScript("OnLeave", function(frame)
    if P.db.bar.mouseoverFade then
      frame:SetAlpha(0.35)
      P:SetCommandAlpha(0.35)
    end
  end)

  self.bar = bar
  self:ApplyBarStyle()
end

function P:SetCommandAlpha(alpha)
  for _, cell in pairs(self.commandCells or {}) do
    cell:SetAlpha(alpha)
  end
end

function P:ApplyBarStyle()
  local bar = self.bar
  if not bar then
    return
  end
  local db = self.db.bar
  local alpha = db.mouseoverFade and 0.35 or 1
  bar:SetScale(db.scale)
  bar:SetHeight(db.height)
  bar:EnableMouse(not db.clickThrough)
  bar:SetAlpha(alpha)
  -- Command cells live on UIParent and do not inherit the bar's scale/alpha.
  if not (InCombatLockdown and InCombatLockdown()) then
    for _, cell in pairs(self.commandCells or {}) do
      cell:SetScale(db.scale)
      cell:SetAlpha(alpha)
    end
  end

  local background = db.background
  bar.bg:SetShown(background.enabled ~= false)
  if background.texture then
    bar.bg:SetTexture(background.texture)
  end
  local color = background.color
  if color then
    -- A texture has its own colours; tinting it with the (by default black)
    -- background colour would just turn it black. The colour only tints a
    -- textured background when asked to; the alpha always applies.
    if self:IsSolidBackground() or background.tint then
      bar.bg:SetVertexColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 0.5)
    else
      bar.bg:SetVertexColor(1, 1, 1, color[4] or 0.5)
    end
  end
  if self.ApplyDecor then
    self:ApplyDecor()
  end
end

-- Where the bar sits on screen. Dragging it makes the position "custom".
local ALIGNMENTS = {
  TOPLEFT = 8,
  TOP = 0,
  TOPRIGHT = -8,
}

-- Moves the bar by an exact pixel offset from its anchor corner. Moving it
-- sideways off the preset margin makes the alignment custom.
function P:SetBarOffset(key, value)
  if (key ~= "x" and key ~= "y") or not self.bar then
    return nil
  end
  value = math.max(-5000, math.min(5000, math.floor(value + 0.5)))
  local db = self.db.bar
  db[key] = value
  if key == "x" and ALIGNMENTS[db.alignment] ~= value then
    db.alignment = "custom"
  end
  self:RestorePosition()
  self:RequestLayout()
  if self.RefreshOptions then
    self:RefreshOptions()
  end
  return value
end

function P:SetAlignment(id)
  local margin = ALIGNMENTS[id]
  if margin == nil or not self.bar then
    return false
  end
  local db = self.db.bar
  db.alignment = id
  db.point = id
  db.relativePoint = id
  db.x = margin
  self:RestorePosition()
  self:RequestLayout()
  if self.RefreshOptions then
    self:RefreshOptions()
  end
  return true
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
  db.alignment = "custom"
  -- The alignment selector shows "custom" if the options are open.
  if self.RefreshOptions then
    self:RefreshOptions()
  end
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
  return (self.commandCells and self.commandCells[key]) or (self.minimapCells and self.minimapCells[key])
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
  for key in pairs(self.minimapCells or {}) do
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
  local ordered = self:OrderedKeys()
  local enabled = {}
  for _, key in ipairs(ordered) do
    enabled[key] = true
  end

  -- Disabled cells keep their old anchors unless they are hidden, which made
  -- an unticked element draw over its neighbour. Hide every cell that is not
  -- in the enabled order before placing anything.
  for _, key in ipairs(self:AllKeys()) do
    if not enabled[key] then
      local cell = self:GetCell(key)
      if cell then
        cell:Hide()
      end
    end
  end

  local offset = db.padding
  local placed = 0
  local secureCells = {}

  for _, key in ipairs(ordered) do
    local cell = self:GetCell(key)
    if cell and cell.isCommand then
      -- Recorded now, positioned after the bar has its final width.
      secureCells[#secureCells + 1] = { cell = cell, offset = offset }
      offset = offset + (cell.width or 0) + db.spacing
      placed = placed + 1
    elseif cell and cell:IsShown() then
      -- Explicit offsets from the bar instead of chaining cell to cell, so a
      -- command cell between two broker cells does not leave a gap in the
      -- normal chain.
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", bar, "LEFT", offset, 0)
      offset = offset + (cell.width or 0) + db.spacing
      placed = placed + 1
    end
  end

  local width
  if placed > 0 then
    width = offset - db.spacing + db.padding
  else
    width = db.padding * 2
  end
  bar:SetWidth(math.max(width, 1))
  bar:SetHeight(db.height)

  -- Secure command cells must not be anchored to the bar or to a broker cell:
  -- on 16001 that makes the anchored-to frame protected, and every SetWidth on
  -- it is refused in combat (the original ADDON_ACTION_BLOCKED). This invisible
  -- frame mirrors the bar's point, size and scale, so the cells line up while
  -- only it ends up protected.
  if #secureCells > 0 then
    local anchor = self:SecureAnchor()
    local point, _, relativePoint, x, y = bar:GetPoint()
    anchor:ClearAllPoints()
    anchor:SetPoint(point or "TOP", UIParent, relativePoint or "TOP", x or 0, y or 0)
    anchor:SetSize(bar:GetWidth(), bar:GetHeight())
    anchor:SetScale(bar:GetScale() or 1)
    anchor:Show()
    for _, placement in ipairs(secureCells) do
      local cell = placement.cell
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", anchor, "LEFT", placement.offset, 0)
      cell:SetScale(bar:GetScale() or 1)
      cell:SetAlpha(bar:GetAlpha())
    end
  elseif self.secureAnchor then
    self.secureAnchor:Hide()
  end

  local showBar = placed > 0 or not db.hideWhenEmpty
  if db.hideInCombat and InCombatLockdown() then
    showBar = false
  end
  bar:SetShown(showBar)
  for _, placement in ipairs(secureCells) do
    placement.cell:SetShown(showBar)
  end
end

function P:SecureAnchor()
  if not self.secureAnchor then
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:Hide()
    self.secureAnchor = anchor
  end
  return self.secureAnchor
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
