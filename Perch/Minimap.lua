local ADDON, P = ...
P = _G.Perch

-- Minimap buttons as bar elements.
--
-- Buttons that sit on the minimap (and are not an LDB launcher Perch already
-- shows) become opt-in elements, keyed "mm:<frame name>". They show their own
-- icon, or a label (their name, or a custom label). Mouse input is forwarded to
-- the original button, so clicks, hover tooltips and the mouse wheel behave as
-- they do on the minimap itself.

local MAX_BUTTON_SIZE = 60

-- Blizzard's own minimap furniture and buttons that belong to other bars.
local IGNORED_PREFIXES = {
  "Minimap",
  "MiniMap",
  "GameTime",
  "QueueStatus",
  "Garrison",
  "ExpansionLanding",
  "TimeManager",
  "HidingBar",
  "Perch",
}

local LIBDBICON_PREFIX = "LibDBIcon10_"

-- Texture parts that are decoration, not the picture on the button.
local DECORATION = { "border", "highlight", "background", "overlay", "shadow", "ring", "glow", "mask", "pushed" }

local function startsWith(text, prefix)
  return text:sub(1, #prefix) == prefix
end

local function ignored(name)
  for _, prefix in ipairs(IGNORED_PREFIXES) do
    if startsWith(name, prefix) then
      return true
    end
  end
  return false
end

local function hasScript(frame, name)
  return type(frame.GetScript) == "function" and type(frame:GetScript(name)) == "function"
end

local function isCandidate(frame)
  if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
    return false
  end
  local name = frame:GetName()
  if type(name) ~= "string" or name == "" or ignored(name) then
    return false
  end
  if not (frame.IsObjectType and (frame:IsObjectType("Button") or frame:IsObjectType("CheckButton"))) then
    return false
  end
  local width, height = frame:GetWidth(), frame:GetHeight()
  if (width and width > MAX_BUTTON_SIZE) or (height and height > MAX_BUTTON_SIZE) then
    return false
  end
  -- A button that does nothing is decoration.
  local acts = hasScript(frame, "OnClick") or hasScript(frame, "OnMouseUp") or hasScript(frame, "OnMouseDown")
  if not acts and frame.GetAttribute then
    acts = frame:GetAttribute("type") ~= nil
  end
  if not acts then
    return false
  end
  -- LibDBIcon buttons are the display of an LDB object Perch already lists.
  if startsWith(name, LIBDBICON_PREFIX) then
    local ldb = P.GetLDB()
    if ldb and ldb.GetDataObjectByName and ldb:GetDataObjectByName(name:sub(#LIBDBICON_PREFIX + 1)) then
      return false
    end
  end
  return true
end

local function isDecoration(region)
  local name = region.GetName and region:GetName()
  if type(name) == "string" then
    name = name:lower()
    for _, word in ipairs(DECORATION) do
      if name:find(word, 1, true) then
        return true
      end
    end
  end
  if region.GetDrawLayer and region:GetDrawLayer() == "HIGHLIGHT" then
    return true
  end
  return false
end

local function hasPicture(texture)
  if not texture or not texture.GetTexture then
    return false
  end
  if texture.GetAtlas and texture:GetAtlas() then
    return true
  end
  return texture:GetTexture() ~= nil
end

-- The texture that is the button's picture: a named field, the conventional
-- <name>Icon region, or the first texture that is not a border or highlight.
local function findIcon(button)
  local name = button:GetName()
  local named = {
    button.icon,
    button.Icon,
    button.texture,
    button.Texture,
    name and _G[name .. "Icon"],
    name and _G[name .. "Texture"],
  }
  for _, candidate in ipairs(named) do
    if type(candidate) == "table" and hasPicture(candidate) then
      return candidate
    end
  end
  if button.GetRegions then
    for _, region in ipairs({ button:GetRegions() }) do
      if region.IsObjectType and region:IsObjectType("Texture") and not isDecoration(region) and hasPicture(region) then
        return region
      end
    end
  end
  return nil
end

function P:MinimapLabel(cell)
  local custom = self:ElementOption(cell.minimapKey, "label")
  if custom and custom ~= "" then
    return custom
  end
  local label = cell.minimapName
  for _, pattern in ipairs({ "^" .. LIBDBICON_PREFIX, "MinimapButton$", "MinimapIcon$", "Minimap$", "Button$", "Icon$" }) do
    label = label:gsub(pattern, "")
  end
  if label == "" then
    label = cell.minimapName
  end
  return label
end

--
-- Forwarding to the real button
--

-- Scripts of the original button anchor their tooltip to it, which would put the
-- tooltip on the minimap. Point those SetOwner calls at the bar cell instead.
local function withTooltipOnCell(button, cell, fn, ...)
  local tooltip = GameTooltip
  local own = rawget(tooltip, "SetOwner")
  local original = tooltip.SetOwner
  tooltip.SetOwner = function(self, owner, anchor, ...)
    if owner == button then
      return original(self, cell, "ANCHOR_BOTTOM")
    end
    return original(self, owner, anchor, ...)
  end
  local ok, err = pcall(fn, ...)
  tooltip.SetOwner = own
  return ok, err
end

function P:ForwardMinimapScript(cell, scriptName, ...)
  local button = cell.sourceButton
  if not button or not hasScript(button, scriptName) then
    return false
  end
  local ok, err = withTooltipOnCell(button, cell, button:GetScript(scriptName), button, ...)
  if not ok then
    self:RecordBrokerError(cell.minimapName or "?", err)
  end
  return true
end

-- Button:Click runs PreClick, OnClick and PostClick, like a real click.
function P:ClickMinimapButton(cell, mouseButton)
  local button = cell.sourceButton
  if not button or type(button.Click) ~= "function" then
    return
  end
  local ok, err = withTooltipOnCell(button, cell, button.Click, button, mouseButton)
  if not ok then
    self:RecordBrokerError(cell.minimapName or "?", err)
  end
end

function P:CreateMinimapCell(name, button)
  local cell = self:CreateCellBase()
  cell.isMinimap = true
  cell.minimapName = name
  cell.minimapKey = "mm:" .. name
  cell.sourceButton = button

  cell:SetScript("OnMouseDown", function(frame, mouseButton)
    P:ForwardMinimapScript(frame, "OnMouseDown", mouseButton)
  end)
  cell:SetScript("OnMouseUp", function(frame, mouseButton)
    P:ForwardMinimapScript(frame, "OnMouseUp", mouseButton)
  end)
  cell:SetScript("OnClick", function(frame, mouseButton)
    P:ClickMinimapButton(frame, mouseButton)
  end)
  cell:SetScript("OnDoubleClick", function(frame, mouseButton)
    P:ForwardMinimapScript(frame, "OnDoubleClick", mouseButton)
  end)
  cell:SetScript("OnMouseWheel", function(frame, delta)
    P:ForwardMinimapScript(frame, "OnMouseWheel", delta)
  end)
  cell:SetScript("OnEnter", function(frame)
    if not P:ForwardMinimapScript(frame, "OnEnter") then
      GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
      GameTooltip:ClearLines()
      GameTooltip:SetText(frame.minimapName, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  cell:SetScript("OnLeave", function(frame)
    GameTooltip:Hide()
    P:ForwardMinimapScript(frame, "OnLeave")
  end)

  function cell:ContentLabel()
    return P:MinimapLabel(self)
  end

  return cell
end

function P:RefreshMinimapCell(cell)
  if not cell then
    return
  end
  local key = cell.minimapKey
  if not self:IsEnabled(key) then
    cell:Hide()
    return
  end

  local button = cell.sourceButton
  local source = button and findIcon(button)

  -- Copy the picture; skip the work when it has not changed.
  local atlas = source and source.GetAtlas and source:GetAtlas()
  local texture = source and source:GetTexture()
  local signature = tostring(atlas) .. "|" .. tostring(texture)
  if cell.iconSignature ~= signature then
    cell.iconSignature = signature
    if atlas then
      cell.icon:SetAtlas(atlas)
    elseif texture ~= nil then
      cell.icon:SetTexture(texture)
      if source.GetTexCoord then
        pcall(function()
          cell.icon:SetTexCoord(source:GetTexCoord())
        end)
      end
    end
  end

  -- A button with no recognisable picture can only be shown by its name.
  local hasPicture = source ~= nil
  local showIcon = hasPicture and self.db.bar.showIcons ~= false and self:ElementOption(key, "showIcon")
  local showLabel = self:ElementOption(key, "showLabel") or not hasPicture
  local text = showLabel and self:MinimapLabel(cell) or ""

  self:ApplyCellFont(cell)
  if cell.lastText ~= text then
    cell.text:SetText(text)
    cell.lastText = text
  end
  cell.iconVisible = showIcon and true or false
  cell.icon:SetShown(cell.iconVisible)
  self:SizeCell(cell)

  -- The mouse wheel is only captured when the button uses it.
  cell:EnableMouseWheel(button ~= nil and hasScript(button, "OnMouseWheel"))

  if text == "" and not cell.iconVisible then
    cell:Hide()
  else
    cell:Show()
  end
  self:RequestLayout()
end

--
-- Discovery
--

local function minimapParents()
  local parents = {}
  for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
    if type(parent) == "table" and parent.GetChildren then
      parents[#parents + 1] = parent
    end
  end
  return parents
end

function P:ScanMinimapButtons()
  self.minimapCells = self.minimapCells or {}
  for _, parent in ipairs(minimapParents()) do
    for _, child in ipairs({ parent:GetChildren() }) do
      local ok, candidate = pcall(isCandidate, child)
      if ok and candidate then
        local name = child:GetName()
        local key = "mm:" .. name
        local cell = self.minimapCells[key]
        if cell then
          cell.sourceButton = child
          self:RefreshMinimapCell(cell)
        else
          local created, newCell = pcall(self.CreateMinimapCell, self, name, child)
          if created then
            self.minimapCells[key] = newCell
            self:EnsureOrder(key)
            self:RefreshMinimapCell(newCell)
          else
            self:RecordBrokerError(key, newCell)
          end
        end
      end
    end
  end
end
