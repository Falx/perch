local ADDON, P = ...
P = _G.Perch

local function label(parent, text, x, y, template)
  local fontString = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fontString:SetText(text)
  return fontString
end

local function checkbox(parent, text, y, getter, setter)
  local widget = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  widget:SetSize(24, 24)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)

  widget.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  widget.label:SetPoint("LEFT", widget, "RIGHT", 6, 0)
  widget.label:SetText(text)

  widget:SetScript("OnClick", function(self)
    setter(self:GetChecked() and true or false)
  end)

  widget.refresh = function()
    widget:SetChecked(getter() and true or false)
  end

  return widget
end

local function slider(parent, text, y, minimum, maximum, step, getter, setter, format)
  local widget = CreateFrame("Slider", nil, parent)
  widget:SetOrientation("HORIZONTAL")
  widget:SetSize(280, 16)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)
  widget:SetMinMaxValues(minimum, maximum)
  widget:SetValueStep(step)
  widget:SetObeyStepOnDrag(true)

  widget.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  widget.label:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 2)
  widget.label:SetText(text)

  widget.valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  widget.valueText:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT", 0, 2)

  local pattern = format or "%.2f"

  local function display(value)
    widget.valueText:SetText(string.format(pattern, value))
  end

  widget:SetScript("OnValueChanged", function(self, value)
    if self.updating then
      return
    end
    value = math.floor(value / step + 0.5) * step
    setter(value)
    display(value)
  end)

  widget.refresh = function()
    local value = getter()
    widget.updating = true
    widget:SetValue(value)
    widget.updating = false
    display(value)
  end

  return widget
end

local function button(parent, text, x, y, onClick)
  local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  widget:SetSize(140, 22)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  widget:SetText(text)
  widget:SetScript("OnClick", onClick)
  return widget
end

function P:CreateOptionsFrame()
  if self.optionsFrame then
    return self.optionsFrame
  end

  local frame = CreateFrame("Frame", "PerchOptionsFrame", UIParent)
  frame:SetSize(580, 640)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.background = frame:CreateTexture(nil, "BACKGROUND")
  frame.background:SetAllPoints(frame)
  frame.background:SetColorTexture(0.08, 0.08, 0.08, 0.95)

  frame.title = label(frame, "Perch - options", 24, -20, "GameFontNormalLarge")
  frame.version = label(
    frame,
    string.format("v%s (build %s)", self.version or "?", self.build or "?"),
    24,
    -44,
    "GameFontHighlightSmall"
  )

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  self.optionWidgets = {}
  local function track(widget)
    self.optionWidgets[#self.optionWidgets + 1] = widget
    return widget
  end

  local barDB = function()
    return P.db.bar
  end

  local y = -80
  local function nextRow(height)
    y = y - (height or 30)
    return y
  end

  track(checkbox(frame, "Lock the bar", y, function()
    return barDB().locked
  end, function(value)
    barDB().locked = value
  end))

  track(checkbox(frame, "Show icons", nextRow(), function()
    return barDB().showIcons
  end, function(value)
    barDB().showIcons = value
    P:ApplyAll()
  end))

  track(checkbox(frame, "Hide bar when empty", nextRow(), function()
    return barDB().hideWhenEmpty
  end, function(value)
    barDB().hideWhenEmpty = value
    P:ApplyAll()
  end))

  track(checkbox(frame, "Fade until mouseover", nextRow(), function()
    return barDB().mouseoverFade
  end, function(value)
    barDB().mouseoverFade = value
    P:ApplyAll()
  end))

  track(checkbox(frame, "Hide in combat", nextRow(), function()
    return barDB().hideInCombat
  end, function(value)
    barDB().hideInCombat = value
    P:ApplyAll()
  end))

  track(checkbox(frame, "Click-through bar background", nextRow(), function()
    return barDB().clickThrough
  end, function(value)
    barDB().clickThrough = value
    P:ApplyAll()
  end))

  track(checkbox(frame, "Show background", nextRow(), function()
    return barDB().background.enabled
  end, function(value)
    barDB().background.enabled = value
    P:ApplyAll()
  end))

  y = nextRow(24)

  track(slider(frame, "Scale", y, 0.5, 2.5, 0.05, function()
    return barDB().scale
  end, function(value)
    barDB().scale = value
    P:ApplyAll()
  end, "%.2f"))

  track(slider(frame, "Font size", nextRow(44), 8, 24, 1, function()
    return barDB().font.size
  end, function(value)
    barDB().font.size = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(frame, "Bar height", nextRow(44), 14, 40, 1, function()
    return barDB().height
  end, function(value)
    barDB().height = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(frame, "Spacing", nextRow(44), 0, 24, 1, function()
    return barDB().spacing
  end, function(value)
    barDB().spacing = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(frame, "Icon size", nextRow(44), 8, 32, 1, function()
    return barDB().iconSize
  end, function(value)
    barDB().iconSize = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(frame, "Background alpha", nextRow(44), 0, 1, 0.05, function()
    return barDB().background.color[4] or 0.5
  end, function(value)
    barDB().background.color[4] = value
    P:ApplyAll()
  end, "%.2f"))

  y = nextRow(52)

  button(frame, "Reset position", 24, y, function()
    barDB().point, barDB().relativePoint, barDB().x, barDB().y = "TOP", "TOP", 0, -8
    P:RestorePosition()
    P:RequestLayout()
  end)

  button(frame, "Reset settings", 176, y, function()
    PerchDB = nil
    P:EnsureDB()
    P:RestorePosition()
    P:RefreshOptions()
    P:ApplyAll()
    P:Print("Settings reset.")
  end)

  button(frame, "Copy doctor report", 328, y, function()
    P:Doctor()
  end)

  y = nextRow(40)
  frame.help = label(
    frame,
    "Commands: /perch lock | unlock | scale <n> | enable <key> | disable <key> | cmd add <name> <macro>",
    24,
    y,
    "GameFontHighlightSmall"
  )

  frame:SetScript("OnShow", function()
    P:RefreshOptions()
  end)

  self.optionsFrame = frame
  return frame
end

function P:RefreshOptions()
  for _, widget in ipairs(self.optionWidgets or {}) do
    if widget.refresh then
      widget.refresh()
    end
  end
end

function P:ApplyAll()
  if self.bar then
    self:ApplyBarStyle()
    for _, cell in pairs(self.brokerElements or {}) do
      self:RefreshBrokerCell(cell, cell.obj)
    end
    for _, cell in pairs(self.commandCells or {}) do
      self:SizeCell(cell)
    end
    self:RequestLayout()
  end
end

-- The category ID is assigned by the client when the category is registered.
-- Never overwrite category.ID: Settings.OpenToCategory expects the real ID.
function P:OptionsCategoryID()
  local category = self.optionsCategory
  if not category then
    return nil
  end
  if self.optionsCategoryID ~= nil then
    return self.optionsCategoryID
  end
  if type(category.GetID) == "function" then
    local ok, value = pcall(category.GetID, category)
    if ok and value ~= nil then
      self.optionsCategoryID = value
      return value
    end
  end
  self.optionsCategoryID = category.ID or category.name
  return self.optionsCategoryID
end

function P:OpenSettingsCategory()
  if not self.optionsCategory or not Settings or type(Settings.OpenToCategory) ~= "function" then
    return false
  end
  local id = self:OptionsCategoryID()
  if id == nil then
    return false
  end
  return (pcall(Settings.OpenToCategory, id))
end

function P:ShowOptionsFrame()
  local frame = self.optionsFrame or self:CreateOptionsFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    self:RefreshOptions()
    frame:Show()
  end
end

function P:ToggleOptions()
  if self:OpenSettingsCategory() then
    return
  end
  self:ShowOptionsFrame()
end

function P:RegisterOptions()
  if self.optionsRegistered then
    return
  end
  self.optionsRegistered = true

  local frame = self:CreateOptionsFrame()

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, category, assignedID = pcall(function()
      local created = Settings.RegisterCanvasLayoutCategory(frame, "Perch")
      local id = Settings.RegisterAddOnCategory(created)
      return created, id
    end)
    if ok and type(category) == "table" then
      self.optionsCategory = category
      self.optionsCategoryID = assignedID
    else
      self.optionsError = category
    end
  end
end
