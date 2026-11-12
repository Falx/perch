--[[
Headless World of Warcraft API stub for Perch.

Only implements what Perch touches. Unknown frame methods resolve to a no-op so
that a new API call fails loudly in the real client but not here; every method
Perch depends on is implemented explicitly below.
]]

local Stub = {
  frames = {},
  messages = {},
  tickers = {},
  after = {},
  metadata = {},
  inCombat = false,
}

_G.__PerchStub = Stub

--------------------------------------------------------------------------
-- WoW stdlib globals
--------------------------------------------------------------------------

strmatch = string.match
strfind = string.find
strsub = string.sub
strlower = string.lower
strupper = string.upper
strformat = string.format
strrep = string.rep

function strsplit(delimiter, text)
  local result = {}
  for part in string.gmatch(text, "([^" .. delimiter .. "]+)") do
    result[#result + 1] = part
  end
  return unpack(result)
end

function strjoin(delimiter, ...)
  return table.concat({ ... }, delimiter)
end

function wipe(tbl)
  for key in pairs(tbl) do
    tbl[key] = nil
  end
  return tbl
end

tinsert = table.insert
tremove = table.remove

function tContains(tbl, value)
  for _, entry in ipairs(tbl) do
    if entry == value then
      return true
    end
  end
  return false
end

date = os.date
time = os.time

function securecallfunction(fn, ...)
  return fn(...)
end

function hooksecurefunc()
end

local errorHandler = function(message)
  error(message, 2)
end

function geterrorhandler()
  return errorHandler
end

function seterrorhandler(handler)
  errorHandler = handler
end

function GetTime()
  return os.clock()
end

function GetLocale()
  return "enUS"
end

C_UIFileAsset = {
  IsKnownFile = function()
    return true
  end,
}

function GetCVar()
  return "1"
end

function GetScreenWidth()
  return 1920
end

function GetScreenHeight()
  return 1080
end

function InCombatLockdown()
  return Stub.inCombat
end

function GetBuildInfo()
  return "1.60.1", "60000", "Nov 4 2026", 16001
end

function GetAddOnMetadata(addon, key)
  return Stub.metadata[key]
end

function IsAddOnLoaded()
  return true
end

--------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------

local FrameMethods = {}
local FrameMeta = { __index = FrameMethods }

local function noop()
end

local function newFrame(kind, name, parent)
  local frame = {
    kind = kind,
    name = name,
    parent = parent,
    points = {},
    scripts = {},
    events = {},
    attributes = {},
    shown = true,
    width = 0,
    height = 0,
    alpha = 1,
    scale = 1,
  }
  setmetatable(frame, FrameMeta)

  function frame:SetSize(width, height)
    self.width = width
    self.height = height
  end

  function frame:SetWidth(width)
    self.width = width
  end

  function frame:SetHeight(height)
    self.height = height
  end

  function frame:GetWidth()
    return self.width
  end

  function frame:GetHeight()
    return self.height
  end

  function frame:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
  end

  function frame:ClearAllPoints()
    self.points = {}
  end

  function frame:GetPoint(index)
    local point = self.points[index or 1]
    if not point then
      if index and index > 1 then
        return nil
      end
      return "CENTER", nil, "CENTER", 0, 0
    end
    return point[1], point[2], point[3], point[4], point[5]
  end

  function frame:GetNumPoints()
    if self.restricted then
      error("Action[FrameMeasurement] failed because[Can't measure restricted regions]", 2)
    end
    return #self.points
  end

  function frame:IsProtected()
    return self.protectedFrame == true
  end

  function frame:IsForbidden()
    return self.forbiddenFrame == true
  end

  function frame:SetAllPoints()
  end

  function frame:SetParent(parentFrame)
    self.parent = parentFrame
  end

  function frame:GetParent()
    return self.parent
  end

  function frame:Show()
    self.shown = true
  end

  function frame:Hide()
    self.shown = false
  end

  function frame:SetShown(shown)
    self.shown = shown and true or false
  end

  function frame:IsShown()
    return self.shown
  end

  function frame:IsVisible()
    return self.shown
  end

  function frame:SetAlpha(alpha)
    self.alpha = alpha
  end

  function frame:GetAlpha()
    return self.alpha
  end

  function frame:SetScale(scale)
    self.scale = scale
  end

  function frame:GetScale()
    return self.scale
  end

  function frame:GetEffectiveScale()
    return self.scale
  end

  function frame:GetLeft()
    return self.left or 0
  end

  function frame:GetBottom()
    return self.bottom or 0
  end

  function frame:GetRight()
    return (self.left or 0) + (self.width or 0)
  end

  function frame:SetScript(name, handler)
    self.scripts[name] = handler
  end

  function frame:GetScript(name)
    return self.scripts[name]
  end

  function frame:HookScript(name, handler)
    local original = self.scripts[name]
    self.scripts[name] = function(...)
      if original then
        original(...)
      end
      handler(...)
    end
  end

  function frame:RegisterEvent(event)
    self.events[event] = true
  end

  function frame:UnregisterEvent(event)
    self.events[event] = nil
  end

  function frame:CreateTexture()
    return newFrame("texture", nil, self)
  end

  function frame:CreateFontString(name, layer, template)
    local fontString = newFrame("fontstring", name, self)
    fontString.text = ""
    fontString.fontSize = 12
    if template then
      -- Templates such as GameFontNormal carry their own font, so SetText is
      -- legal straight away. Only bare font strings need an explicit SetFont.
      fontString.fontPath = "Fonts\\FRIZQT__.TTF"
    end
    return fontString
  end

  function frame:SetTexture(texture)
    self.texture = texture
    self.atlas = nil
  end

  function frame:GetTexture()
    return self.texture
  end

  function frame:SetAtlas(atlas)
    self.atlas = atlas
  end

  function frame:GetAtlas()
    return self.atlas
  end

  function frame:SetColorTexture() end

  function frame:SetVertexColor(r, g, b, a)
    self.vertexColor = { r, g, b, a }
  end

  function frame:GetVertexColor()
    local color = self.vertexColor or { 1, 1, 1, 1 }
    return color[1], color[2], color[3], color[4]
  end

  function frame:SetDesaturated(desaturated)
    self.desaturated = desaturated and true or false
  end

  function frame:IsDesaturated()
    return self.desaturated or false
  end

  function frame:SetNormalTexture(texture)
    self.normalTexture = newFrame("texture", nil, self)
    self.normalTexture.drawLayer = "BACKGROUND"
    if type(texture) == "string" or type(texture) == "number" then
      self.normalTexture.texture = texture
    end
  end

  function frame:GetNormalTexture()
    return self.normalTexture
  end

  function frame:GetCenter()
    return (self.left or 0) + (self.width or 0) / 2, (self.bottom or 0) + (self.height or 0) / 2
  end

  function frame:SetTexCoord(...)
    self.texCoord = { ... }
  end

  function frame:GetTexCoord()
    local coord = self.texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return unpack(coord)
  end

  function frame:GetDrawLayer()
    return self.drawLayer or "ARTWORK"
  end

  function frame:GetName()
    return self.name
  end

  function frame:IsObjectType(objectType)
    return tostring(self.kind):lower() == tostring(objectType):lower()
  end

  local REGION_KINDS = { texture = true, fontstring = true }

  function frame:GetChildren()
    local children = {}
    for _, candidate in ipairs(Stub.frames) do
      if candidate.parent == self and not REGION_KINDS[candidate.kind] then
        children[#children + 1] = candidate
      end
    end
    return unpack(children)
  end

  function frame:GetRegions()
    local regions = {}
    for _, candidate in ipairs(Stub.frames) do
      if candidate.parent == self and REGION_KINDS[candidate.kind] then
        regions[#regions + 1] = candidate
      end
    end
    return unpack(regions)
  end

  function frame:Click(button)
    local handler = self.scripts.OnClick
    if handler then
      handler(self, button or "LeftButton", false)
    end
  end

  function frame:SetFont(path, size)
    -- A path that does not resolve fails the way the client does.
    if tostring(path):find("Missing", 1, true) then
      return false
    end
    self.fontPath = path
    self.fontSize = size or self.fontSize
    return true
  end

  function frame:GetFont()
    return self.fontPath, self.fontSize
  end

  function frame:SetFontObject()
    self.fontObjectSet = true
  end

  function frame:SetText(text)
    -- 16001 raises a real error here, not a warning: text before font kills the
    -- caller. Keep the stub strict so this can never regress. An EditBox without
    -- a font accepts the text but never draws it, which the tests check via
    -- FontIsSet.
    if self.kind == "fontstring" and not self.fontPath then
      error("FontString:SetText(): Font not set", 2)
    end
    self.text = text
    if self.kind == "EditBox" then
      -- The client leaves the cursor at the end; a narrow or unsized box then
      -- scrolls the start of the text out of view.
      self.cursor = #tostring(text)
    end
    self.setTextCount = (self.setTextCount or 0) + 1
  end

  function frame:SetCursorPosition(position)
    self.cursor = position
  end

  function frame:GetCursorPosition()
    return self.cursor or 0
  end

  function frame:FontIsSet()
    return (self.fontPath ~= nil) or self.fontObjectSet == true
  end

  function frame:SetThumbTexture(thumb)
    self.thumbTexture = thumb
  end

  function frame:GetThumbTexture()
    return self.thumbTexture
  end

  function frame:GetText()
    return self.text
  end

  function frame:GetStringWidth()
    if not self.text then
      return 0
    end
    return #self.text * (self.fontSize or 12) * 0.5
  end

  function frame:GetStringHeight()
    return self.fontSize or 12
  end

  function frame:RegisterForClicks(...)
    self.clicks = { ... }
  end

  function frame:SetScrollChild(child)
    self.scrollChild = child
  end

  function frame:GetScrollChild()
    return self.scrollChild
  end

  function frame:SetTextColor() end

  function frame:SetShadowColor() end

  function frame:SetJustifyH() end

  function frame:SetMinMaxValues(minimum, maximum)
    self.minimum = minimum
    self.maximum = maximum
  end

  function frame:SetValueStep(step)
    self.step = step
  end

  function frame:SetObeyStepOnDrag() end

  function frame:SetOrientation() end

  function frame:SetValue(value)
    if self.minimum and value < self.minimum then
      value = self.minimum
    end
    if self.maximum and value > self.maximum then
      value = self.maximum
    end
    self.value = value
    local handler = self.scripts.OnValueChanged
    if handler then
      handler(self, value)
    end
  end

  function frame:GetValue()
    return self.value
  end

  function frame:SetChecked(checked)
    self.checked = checked
  end

  function frame:GetChecked()
    return self.checked
  end

  function frame:SetAttribute(key, value)
    self.attributes[key] = value
  end

  function frame:GetAttribute(key)
    return self.attributes[key]
  end

  function frame:SetMovable() end

  function frame:SetClampedToScreen() end

  function frame:EnableMouse() end

  function frame:SetAutoFocus() end

  function frame:SetMaxLetters(count)
    self.maxLetters = count
  end

  function frame:EnableMouseWheel(enabled)
    self.mouseWheelEnabled = enabled and true or false
  end

  function frame:SetFocus()
    self.focused = true
  end

  function frame:ClearFocus()
    local hadFocus = self.focused
    self.focused = false
    local handler = self.scripts and self.scripts.OnEditFocusLost
    if hadFocus and handler then
      handler(self)
    end
  end

  function frame:HasFocus()
    return self.focused or false
  end

  function frame:SetEnabled(enabled)
    self.enabledState = enabled and true or false
  end

  function frame:IsEnabled()
    return self.enabledState ~= false
  end

  function frame:RegisterForDrag() end

  function frame:SetFrameStrata(strata)
    self.strata = strata
  end

  function frame:GetFrameStrata()
    return self.strata or "MEDIUM"
  end

  function frame:SetFrameLevel(level)
    self.level = level
  end

  function frame:GetFrameLevel()
    return self.level or 1
  end

  function frame:StartMoving() end

  function frame:StopMovingOrSizing() end

  function frame:SetHitRectInsets() end

  function frame:AddMessage(message)
    Stub.messages[#Stub.messages + 1] = message
  end

  function frame:AddLine(text)
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = text
  end

  function frame:SetOwner(owner, anchor)
    self.owner = owner
    self.ownerAnchor = anchor
  end

  function frame:ClearLines()
    self.lines = {}
  end

  function frame:SetMinimumWidth() end

  function frame:AddDoubleLine(left, right)
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = tostring(left) .. " " .. tostring(right)
  end

  Stub.frames[#Stub.frames + 1] = frame
  return frame
end

function CreateFrame(frametype, name, parent)
  local frame = newFrame(frametype, name, parent)
  if name then
    _G[name] = frame
  end
  return frame
end

-- Walks every frame (not textures or font strings), like the client's.
function EnumerateFrames(previous)
  local started = previous == nil
  for _, candidate in ipairs(Stub.frames) do
    if candidate.kind ~= "texture" and candidate.kind ~= "fontstring" and candidate.kind ~= "font" then
      if started then
        return candidate
      end
      if candidate == previous then
        started = true
      end
    end
  end
  return nil
end

function CreateFont(path)
  local font = newFrame("font", nil, nil)
  font.fontPath = path
  return font
end

UIParent = newFrame("frame", "UIParent", nil)
UIParent.width = 1920
UIParent.height = 1080

Minimap = newFrame("Frame", "Minimap", UIParent)

local function fontObject()
  local fontString = newFrame("fontstring", nil, nil)
  fontString.text = ""
  fontString.fontSize = 12
  return fontString
end

GameFontNormal = fontObject()
GameFontNormalLarge = fontObject()
GameFontHighlight = fontObject()
GameFontHighlightSmall = fontObject()
GameFontHighlightLarge = fontObject()
GameFontDisable = fontObject()
NumberFontNormal = fontObject()
ChatFontNormal = fontObject()

GameTooltip = newFrame("tooltip", "GameTooltip", UIParent)

DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, message)
    Stub.messages[#Stub.messages + 1] = message
  end,
}

--------------------------------------------------------------------------
-- C_Timer
--------------------------------------------------------------------------

C_Timer = {}

function C_Timer.After(_delay, callback)
  callback()
end

function C_Timer.NewTicker(_interval, callback)
  local ticker = { callback = callback, cancelled = false }
  function ticker:Cancel()
    self.cancelled = true
  end
  Stub.tickers[#Stub.tickers + 1] = ticker
  return ticker
end

function C_Timer.NewTimer(_delay, callback)
  callback()
  return { Cancel = noop }
end

--------------------------------------------------------------------------
-- Settings API
--------------------------------------------------------------------------

Settings = {}

local function settingObject()
  return {
    SetValue = noop,
    GetValue = noop,
    SetVariable = noop,
  }
end

function Settings.RegisterVerticalLayoutCategory(name)
  return { ID = name, name = name }
end

function Settings.RegisterCanvasLayoutCategory(frame, name)
  return { ID = name, name = name, frame = frame }
end

function Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
  local sub = { ID = name, name = name, frame = frame, parent = parent }
  Stub.subcategories = Stub.subcategories or {}
  Stub.subcategories[#Stub.subcategories + 1] = sub
  return sub
end

function Settings.RegisterAddOnCategory(category)
  Stub.optionsCategory = category
end

function Settings.OpenToCategory(id)
  Stub.openedCategory = id
end

function Settings.RegisterAddOnSetting()
  return settingObject()
end

function Settings.CreateCheckbox()
  return settingObject()
end

function Settings.CreateSliderOptions()
  return { SetLabelFormatter = noop }
end

function Settings.CreateSlider()
  return settingObject()
end

function Settings.CreateDropdownOptions()
  return { AddValue = noop }
end

function Settings.CreateDropdown()
  return settingObject()
end

--------------------------------------------------------------------------
-- Game systems
--------------------------------------------------------------------------

function GetMoney()
  return Stub.money or 1234567
end

function GetFPS()
  return 61.2
end

function GetFramerate()
  return 60.4
end

function GetGameTime()
  return 14, 32
end

function UnitXP()
  return 500
end

function UnitXPMax()
  return 1000
end

function UnitLevel()
  return 42
end

function GetXPExhaustion()
  return Stub.rested or 0
end

function GetInventoryItemDurability(slot)
  if slot == 1 or slot == 5 then
    return 80, 100
  end
  return nil, nil
end

Stub.bagData = { [0] = { slots = 16, free = 9 } }
Stub.bagsToggled = 0

function ToggleAllBags()
  Stub.bagsToggled = Stub.bagsToggled + 1
end

C_Container = {
  GetContainerNumSlots = function(bag)
    local data = Stub.bagData[bag]
    return data and data.slots or 0
  end,
  GetContainerNumFreeSlots = function(bag)
    local data = Stub.bagData[bag]
    return data and data.free or 0
  end,
}

C_Map = {
  GetBestMapForUnit = function()
    return 1
  end,
  GetPlayerMapPosition = function()
    return {
      GetXY = function()
        return 0.432, 0.718
      end,
    }
  end,
}

C_DateAndTime = {
  GetCurrentCalendarTime = function()
    return { hour = 14, minute = 32 }
  end,
}

C_AddOns = {
  GetAddOnMetadata = function(_, key)
    return Stub.metadata[key]
  end,
}

SlashCmdList = {}

--------------------------------------------------------------------------
-- Harness helpers
--------------------------------------------------------------------------

function Stub.LoadAddon(root)
  root = root or "Perch"
  local tocPath = root .. "/Perch.toc"
  local handle = assert(io.open(tocPath, "r"), "cannot open " .. tocPath)
  local files = {}

  for line in handle:lines() do
    line = line:gsub("\r", "")
    if line:sub(1, 2) == "##" then
      local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
      if key then
        Stub.metadata[key] = value
      end
    elseif line:sub(1, 1) ~= "#" and line:match("%S") then
      files[#files + 1] = line:match("^%s*(.-)%s*$")
    end
  end
  handle:close()

  for _, relative in ipairs(files) do
    local path = root .. "/" .. relative:gsub("\\", "/")
    local chunk = assert(loadfile(path), "cannot load " .. path)
    chunk("Perch", {})
  end

  return _G.Perch
end

function Stub.FireEvent(event, ...)
  for _, frame in ipairs(Stub.frames) do
    if frame.events and frame.events[event] then
      local handler = frame.scripts and frame.scripts.OnEvent
      if handler then
        handler(frame, event, ...)
      end
    end
  end
end

function Stub.Tick()
  for _, ticker in ipairs(Stub.tickers) do
    if not ticker.cancelled then
      ticker.callback()
    end
  end
end

function Stub.ResetMessages()
  Stub.messages = {}
end

function Stub.LastMessage()
  return Stub.messages[#Stub.messages]
end

-- Reset saved variables so each run starts clean.
PerchDB = nil

return Stub
