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

local ELEMENT_ROW_HEIGHT = 22

-- Every LDB object Perch knows about, including the ones that are off. This is
-- the "add a broker plugin to the bar" list: new plugins show up automatically.
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
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ELEMENT_ROW_HEIGHT)
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
    child:SetHeight(math.max(#keys * ELEMENT_ROW_HEIGHT, 1))
  end

  return widget
end

-- The controls themselves. Used twice: once as the Settings canvas, once inside
-- the standalone frame that /perch frame opens.
function P:CreateOptionsContent(parent)
  local content = CreateFrame("Frame", nil, parent)
  content:SetSize(620, 700)

  local widgets = {}
  local function track(widget)
    widgets[#widgets + 1] = widget
    -- Initialise immediately: the Settings canvas is created already shown, so
    -- OnShow never fires on the first open and every widget would read as
    -- unchecked/zero until the user touched it.
    if widget.refresh then
      widget.refresh()
    end
    return widget
  end

  local barDB = function()
    return P.db.bar
  end

  local y = -10
  local function nextRow(height)
    y = y - (height or 30)
    return y
  end

  track(checkbox(content, "Lock the bar", y, function()
    return barDB().locked
  end, function(value)
    barDB().locked = value
  end))

  track(checkbox(content, "Show icons", nextRow(), function()
    return barDB().showIcons
  end, function(value)
    barDB().showIcons = value
    P:ApplyAll()
  end))

  track(checkbox(content, "Hide bar when empty", nextRow(), function()
    return barDB().hideWhenEmpty
  end, function(value)
    barDB().hideWhenEmpty = value
    P:ApplyAll()
  end))

  track(checkbox(content, "Fade until mouseover", nextRow(), function()
    return barDB().mouseoverFade
  end, function(value)
    barDB().mouseoverFade = value
    P:ApplyAll()
  end))

  track(checkbox(content, "Hide in combat", nextRow(), function()
    return barDB().hideInCombat
  end, function(value)
    barDB().hideInCombat = value
    P:ApplyAll()
  end))

  track(checkbox(content, "Click-through bar background", nextRow(), function()
    return barDB().clickThrough
  end, function(value)
    barDB().clickThrough = value
    P:ApplyAll()
  end))

  track(checkbox(content, "Show background", nextRow(), function()
    return barDB().background.enabled
  end, function(value)
    barDB().background.enabled = value
    P:ApplyAll()
  end))

  y = nextRow(24)

  track(slider(content, "Scale", y, 0.5, 2.5, 0.05, function()
    return barDB().scale
  end, function(value)
    barDB().scale = value
    P:ApplyAll()
  end, "%.2f"))

  track(slider(content, "Font size", nextRow(44), 8, 24, 1, function()
    return barDB().font.size
  end, function(value)
    barDB().font.size = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(content, "Bar height", nextRow(44), 14, 40, 1, function()
    return barDB().height
  end, function(value)
    barDB().height = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(content, "Spacing", nextRow(44), 0, 24, 1, function()
    return barDB().spacing
  end, function(value)
    barDB().spacing = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(content, "Icon size", nextRow(44), 8, 32, 1, function()
    return barDB().iconSize
  end, function(value)
    barDB().iconSize = value
    P:ApplyAll()
  end, "%.0f"))

  track(slider(content, "Background alpha", nextRow(44), 0, 1, 0.05, function()
    return barDB().background.color[4] or 0.5
  end, function(value)
    barDB().background.color[4] = value
    P:ApplyAll()
  end, "%.2f"))

  -- Right column: element visibility.
  label(content, "Elements", 340, -10, "GameFontNormal")
  label(content, "Launchers start hidden; tick to show them.", 340, -28, "GameFontHighlightSmall")
  track(elementList(content, 340, -50, 260, 470))

  y = nextRow(52)

  button(content, "Reset position", 24, y, function()
    barDB().point, barDB().relativePoint, barDB().x, barDB().y = "TOP", "TOP", 0, -8
    P:RestorePosition()
    P:RequestLayout()
  end)

  button(content, "Reset settings", 176, y, function()
    PerchDB = nil
    P:EnsureDB()
    P:RestorePosition()
    P:RefreshOptions()
    P:ApplyAll()
    P:Print("Settings reset.")
  end)

  button(content, "Doctor report", 328, y, function()
    P:Doctor()
  end)

  y = nextRow(40)
  label(
    content,
    "Commands: /perch lock | unlock | scale <n> | enable <key> | disable <key> | cmd add <name> <macro>",
    24,
    y,
    "GameFontHighlightSmall"
  )

  content:SetScript("OnShow", function()
    P:RefreshOptions()
  end)
  -- The canvas can already be effectively visible when Settings embeds it, in
  -- which case OnShow does not fire. One update is enough to pick up the LDB
  -- objects that register after ADDON_LOADED (the element list).
  content:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    P:RefreshOptions()
  end)

  self.optionWidgets = self.optionWidgets or {}
  for _, widget in ipairs(widgets) do
    self.optionWidgets[#self.optionWidgets + 1] = widget
  end

  return content
end

-- Standalone, draggable frame for /perch frame. The Settings canvas gets its
-- own content copy, without chrome.
function P:CreateOptionsFrame()
  if self.optionsFrame then
    return self.optionsFrame
  end

  local frame = CreateFrame("Frame", "PerchOptionsFrame", UIParent)
  frame:SetSize(660, 760)
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

  frame.content = self:CreateOptionsContent(frame)
  frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -56)

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
  if not self.bar then
    return
  end
  self:ApplyBarStyle()
  for _, cell in pairs(self.brokerElements or {}) do
    self:UpdateBrokerCell(cell.brokerName)
  end
  -- Command cells are protected; resizing them in combat is blocked.
  if not (InCombatLockdown and InCombatLockdown()) then
    for _, cell in pairs(self.commandCells or {}) do
      self:SizeCell(cell)
    end
  end
  self:RequestLayout()
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
  local ok = pcall(Settings.OpenToCategory, id)
  if ok and C_Timer and C_Timer.After then
    -- Let the Settings system show the canvas, then fill in the widgets and
    -- the element list (which includes LDB objects registered after login).
    C_Timer.After(0, function()
      P:RefreshOptions()
    end)
  end
  return ok
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

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local canvas = self:CreateOptionsContent(nil)
    self.optionsCanvas = canvas
    local ok, category, assignedID = pcall(function()
      local created = Settings.RegisterCanvasLayoutCategory(canvas, "Perch")
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
