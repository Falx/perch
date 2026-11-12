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

-- How a button's picture is extracted. Buttons are built in many ways, so each
-- element can pick the style that looks right.
P.MINIMAP_ICON_SOURCES = {
  { id = "auto", label = "Automatic" },
  { id = "first", label = "First texture" },
  { id = "last", label = "Top texture" },
  { id = "largest", label = "Largest texture" },
  { id = "normal", label = "Button texture" },
  { id = "layers", label = "All layers" },
}

P.MINIMAP_ICON_CROPS = {
  { id = "source", label = "Original crop" },
  { id = "full", label = "Whole texture" },
  { id = "trimmed", label = "Trimmed edges" },
}

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
  if type(texture) ~= "table" or not texture.GetTexture then
    return false
  end
  if texture.GetAtlas and texture:GetAtlas() then
    return true
  end
  return texture:GetTexture() ~= nil
end

--
-- Picking the picture
--

-- Every texture that is part of the picture, in draw order.
local function pictureRegions(button)
  local list = {}
  if button.GetRegions then
    for _, region in ipairs({ button:GetRegions() }) do
      if region.IsObjectType and region:IsObjectType("Texture") and not isDecoration(region) and hasPicture(region) then
        list[#list + 1] = region
      end
    end
  end
  return list
end

local function normalTexture(button)
  local texture = button.GetNormalTexture and button:GetNormalTexture()
  if hasPicture(texture) then
    return texture
  end
end

-- A named field, the conventional <name>Icon region, the button texture, or the
-- first texture that is not a border or highlight.
local function automatic(button)
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
    if hasPicture(candidate) then
      return candidate
    end
  end
  return normalTexture(button) or pictureRegions(button)[1]
end

local function area(region)
  return (region:GetWidth() or 0) * (region:GetHeight() or 0)
end

-- The textures to copy, as a list: one for most styles, all of them for layers.
local function pickSources(button, mode)
  if mode == "layers" then
    local list = pictureRegions(button)
    local normal = normalTexture(button)
    if normal then
      local present = false
      for _, region in ipairs(list) do
        if region == normal then
          present = true
        end
      end
      if not present then
        table.insert(list, 1, normal)
      end
    end
    if #list > 0 then
      return list
    end
  elseif mode == "normal" then
    local normal = normalTexture(button)
    if normal then
      return { normal }
    end
  elseif mode == "first" or mode == "last" or mode == "largest" then
    local list = pictureRegions(button)
    if #list > 0 then
      if mode == "first" then
        return { list[1] }
      elseif mode == "last" then
        return { list[#list] }
      end
      local largest = list[1]
      for _, region in ipairs(list) do
        if area(region) > area(largest) then
          largest = region
        end
      end
      return { largest }
    end
  end
  -- Automatic, and the fallback when the chosen style finds nothing.
  local picked = automatic(button)
  return picked and { picked } or {}
end

-- Everything needed to draw a copy of a texture.
local function readTexture(region)
  local data = {
    atlas = region.GetAtlas and region:GetAtlas() or nil,
    texture = region:GetTexture(),
    r = 1,
    g = 1,
    b = 1,
    a = 1,
    desaturated = false,
  }
  if not data.atlas and region.GetTexCoord then
    local ok, coords = pcall(function()
      return { region:GetTexCoord() }
    end)
    if ok and #coords >= 4 then
      data.coords = coords
    end
  end
  if region.GetVertexColor then
    local r, g, b, a = region:GetVertexColor()
    data.r, data.g, data.b, data.a = r or 1, g or 1, b or 1, a or 1
  end
  if region.IsDesaturated then
    data.desaturated = region:IsDesaturated() and true or false
  end
  return data
end

local function signature(data)
  local coords = {}
  for _, value in ipairs(data.coords or {}) do
    coords[#coords + 1] = string.format("%.3f", value)
  end
  return table.concat({
    tostring(data.atlas),
    tostring(data.texture),
    table.concat(coords, ","),
    string.format("%.2f,%.2f,%.2f,%.2f", data.r, data.g, data.b, data.a),
    tostring(data.desaturated),
  }, "|")
end

local function drawTexture(texture, data, crop)
  if data.atlas then
    texture:SetAtlas(data.atlas)
  else
    texture:SetTexture(data.texture)
    if crop == "full" or (crop == "source" and not data.coords) then
      texture:SetTexCoord(0, 1, 0, 1)
    elseif crop == "trimmed" then
      texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
      pcall(texture.SetTexCoord, texture, unpack(data.coords))
    end
  end
  texture:SetVertexColor(data.r, data.g, data.b, data.a)
  if texture.SetDesaturated then
    texture:SetDesaturated(data.desaturated)
  end
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

-- Addons with their own hover panels (not GameTooltip) place them next to the
-- button by reading its screen rectangle. While the mouse is over the bar cell
-- the button reports the cell's geometry instead, so those panels appear at the
-- bar. It is given back on leave or when the cell hides.
local BORROWED = {
  "GetLeft",
  "GetRight",
  "GetTop",
  "GetBottom",
  "GetCenter",
  "GetRect",
  "GetWidth",
  "GetHeight",
  "GetSize",
  "GetEffectiveScale",
}

local function lendGeometry(cell)
  local button = cell.sourceButton
  if not button or cell.lentGeometry then
    return
  end
  local saved = {}
  for _, name in ipairs(BORROWED) do
    saved[name] = rawget(button, name) or false
    local method = cell[name]
    if type(method) == "function" then
      button[name] = function(_, ...)
        return method(cell, ...)
      end
    end
  end
  cell.lentGeometry = saved
end

local function returnGeometry(cell)
  local saved = cell.lentGeometry
  if not saved then
    return
  end
  local button = cell.sourceButton
  for name, original in pairs(saved) do
    button[name] = original or nil
  end
  cell.lentGeometry = nil
end

-- Menus and panels that a button opens are often anchored straight to it
-- (SetPoint(..., button, ...)), which would put them at the minimap. After a
-- forwarded click, anything newly shown and anchored to the button is anchored to
-- the bar cell instead. Frames that were already there (and the button's own
-- children) are left alone.
local function framesAnchoredTo(button, cell)
  local found = {}
  if not EnumerateFrames then
    return found
  end
  local frame = EnumerateFrames()
  while frame do
    if frame ~= cell and frame ~= button and frame.GetNumPoints and frame:GetParent() ~= button then
      for index = 1, frame:GetNumPoints() do
        local _, relativeTo = frame:GetPoint(index)
        if relativeTo == button then
          found[#found + 1] = frame
          break
        end
      end
    end
    frame = EnumerateFrames(frame)
  end
  return found
end

local function anchorToCell(frame, button, cell)
  local points = {}
  for index = 1, frame:GetNumPoints() do
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
    if relativeTo == button then
      relativeTo = cell
    end
    points[index] = { point, relativeTo, relativePoint, x, y }
  end
  pcall(function()
    frame:ClearAllPoints()
    for _, spec in ipairs(points) do
      frame:SetPoint(spec[1], spec[2], spec[3], spec[4], spec[5])
    end
  end)
end

local function withReanchor(cell, fn)
  local button = cell.sourceButton
  -- Protected frames cannot be re-anchored in combat.
  if not button or not EnumerateFrames or (InCombatLockdown and InCombatLockdown()) then
    return fn()
  end
  local before = {}
  for _, frame in ipairs(framesAnchoredTo(button, cell)) do
    before[frame] = frame:IsShown() and true or false
  end
  local ok, err = fn()
  for _, frame in ipairs(framesAnchoredTo(button, cell)) do
    if frame:IsShown() and before[frame] ~= true then
      anchorToCell(frame, button, cell)
    end
  end
  return ok, err
end

-- Scripts that may open a menu on the button.
local OPENS_MENUS = { OnMouseUp = true, OnDoubleClick = true }

function P:ForwardMinimapScript(cell, scriptName, ...)
  local button = cell.sourceButton
  if not button or not hasScript(button, scriptName) then
    return false
  end
  local args = { ... }
  local run = function()
    return withTooltipOnCell(button, cell, button:GetScript(scriptName), button, unpack(args))
  end
  local ok, err
  if OPENS_MENUS[scriptName] then
    ok, err = withReanchor(cell, run)
  else
    ok, err = run()
  end
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
  local ok, err = withReanchor(cell, function()
    return withTooltipOnCell(button, cell, button.Click, button, mouseButton)
  end)
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
  cell.layers = {}
  cell.layerSpecs = {}

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
    lendGeometry(frame)
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
    returnGeometry(frame)
  end)
  cell:SetScript("OnHide", function(frame)
    returnGeometry(frame)
  end)

  function cell:ContentLabel()
    return P:MinimapLabel(self)
  end

  return cell
end

-- Stacked copies of every texture the button is made of. They are anchored to
-- the cell's own icon, so they move and scale with it.
local function layerFor(cell, index)
  local layer = cell.layers[index]
  if not layer then
    layer = cell:CreateTexture(nil, "ARTWORK", nil, math.min(index, 7))
    cell.layers[index] = layer
  end
  return layer
end

local function placeLayers(cell)
  local iconSize = P.db.bar.iconSize
  for index, spec in ipairs(cell.layerSpecs) do
    local layer = cell.layers[index]
    layer:ClearAllPoints()
    layer:SetSize(iconSize * spec.ratio, iconSize * spec.ratio)
    layer:SetPoint("CENTER", cell.icon, "CENTER", spec.dx * iconSize, spec.dy * iconSize)
  end
end

local function buildLayers(cell, button, sources, datas, crop)
  cell.layerSpecs = {}
  local bw, bh = button:GetWidth(), button:GetHeight()
  local bx, by
  if button.GetCenter then
    bx, by = button:GetCenter()
  end
  for index, source in ipairs(sources) do
    local layer = layerFor(cell, index)
    drawTexture(layer, datas[index], crop)
    local rw = source:GetWidth()
    local ratio = (bw and bw > 0 and rw and rw > 0) and rw / bw or 1
    ratio = math.max(0.2, math.min(2, ratio))
    local dx, dy = 0, 0
    if bx and by and bw and bw > 0 and bh and bh > 0 and source.GetCenter then
      local rx, ry = source:GetCenter()
      if rx and ry then
        dx, dy = (rx - bx) / bw, (ry - by) / bh
      end
    end
    cell.layerSpecs[index] = { ratio = ratio, dx = dx, dy = dy }
  end
  -- The cell's own icon only anchors the layers.
  cell.icon:SetTexture(nil)
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
  local mode = self:ElementOption(key, "iconSource")
  local crop = self:ElementOption(key, "iconCrop")
  local sources = button and pickSources(button, mode) or {}
  local datas, parts = {}, { mode, crop }
  for index, source in ipairs(sources) do
    datas[index] = readTexture(source)
    parts[#parts + 1] = signature(datas[index])
  end

  -- Redraw only when the picture or the chosen style changed.
  local signatureText = table.concat(parts, "#")
  if cell.iconSignature ~= signatureText then
    cell.iconSignature = signatureText
    if #sources > 0 and mode == "layers" then
      buildLayers(cell, button, sources, datas, crop)
    else
      cell.layerSpecs = {}
      if datas[1] then
        drawTexture(cell.icon, datas[1], crop)
      end
    end
  end

  -- A button with no recognisable picture can only be shown by its name.
  local hasPictureSource = #sources > 0
  local showIcon = hasPictureSource and self.db.bar.showIcons ~= false and self:ElementOption(key, "showIcon")
  local showLabel = self:ElementOption(key, "showLabel") or not hasPictureSource
  local text = showLabel and self:MinimapLabel(cell) or ""

  self:ApplyCellFont(cell)
  if cell.lastText ~= text then
    cell.text:SetText(text)
    cell.lastText = text
  end
  cell.iconVisible = showIcon and true or false
  cell.icon:SetShown(cell.iconVisible and #cell.layerSpecs == 0)
  self:SizeCell(cell)
  -- SizeCell shows the icon when it has one; the layered style shows the layers.
  cell.icon:SetShown(cell.iconVisible and #cell.layerSpecs == 0)
  placeLayers(cell)
  for index, layer in ipairs(cell.layers) do
    layer:SetShown(cell.iconVisible and index <= #cell.layerSpecs)
  end

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
  local candidates = { [1] = Minimap, [2] = MinimapBackdrop, [3] = MinimapCluster }
  for index = 1, 3 do
    local parent = candidates[index]
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
