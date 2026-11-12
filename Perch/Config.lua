local ADDON, P = ...
P = _G.Perch

-- Shared widget helpers and the page framework. The pages themselves live in
-- ConfigGeneral/ConfigAppearance/ConfigElements and register through
-- P:RegisterPage.

local UI = {}
P.UI = UI

local PAGE_WIDTH, PAGE_HEIGHT = 620, 660

function UI.label(parent, text, x, y, template)
  local fontString = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fontString:SetText(text)
  return fontString
end

function UI.checkbox(parent, text, x, y, getter, setter)
  local widget = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  widget:SetSize(24, 24)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

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

-- Single-line text input. Non-live inputs apply on Enter or when focus is lost
-- (Escape reverts); live inputs apply on every keystroke. setter(text).
function UI.editbox(parent, x, y, width, getter, setter, live)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  box:SetAutoFocus(false)

  local widget = { box = box }

  widget.refresh = function()
    if not box:HasFocus() then
      box:SetText(tostring(getter() or ""))
    end
  end

  local function commit()
    if widget.cancelled then
      widget.cancelled = false
      return
    end
    setter(box:GetText())
  end

  box:SetScript("OnEscapePressed", function(self)
    widget.cancelled = true
    self:ClearFocus()
    widget.cancelled = false
    widget.refresh()
  end)
  if live then
    box:SetScript("OnTextChanged", function(self, userInput)
      if userInput then
        setter(self:GetText())
      end
    end)
    box:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
    end)
  else
    box:SetScript("OnEnterPressed", function(self)
      commit()
      self:ClearFocus()
      widget.refresh()
    end)
    box:SetScript("OnEditFocusLost", function()
      commit()
      widget.refresh()
    end)
  end

  return widget
end

function UI.slider(parent, text, x, y, minimum, maximum, step, getter, setter, format)
  local widget = CreateFrame("Slider", nil, parent)
  widget:SetOrientation("HORIZONTAL")
  widget:SetSize(280, 16)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  widget:SetMinMaxValues(minimum, maximum)
  widget:SetValueStep(step)
  widget:SetObeyStepOnDrag(true)

  widget.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  widget.label:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 2)
  widget.label:SetText(text)

  local pattern = format or "%.2f"

  -- Typed values are clamped and snapped to the slider's step.
  local input = UI.editbox(parent, x + 296, y + 2, 56, function()
    return string.format(pattern, getter())
  end, function(typed)
    local number = tonumber(typed)
    if not number then
      widget.refresh()
      return
    end
    number = math.floor(number / step + 0.5) * step
    number = math.max(minimum, math.min(maximum, number))
    setter(number)
    widget.refresh()
  end)
  widget.input = input

  local function display(value)
    if not input.box:HasFocus() then
      input.box:SetText(string.format(pattern, value))
    end
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

function UI.button(parent, text, x, y, onClick, width)
  local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  widget:SetSize(width or 140, 22)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  widget:SetText(text)
  widget:SetScript("OnClick", onClick)
  return widget
end

--
-- Picker: one shared scrolling list popup used by every dropdown. It avoids the
-- UIDropDownMenu/Dropdown templates, whose behaviour differs between clients.
--

local PICKER_ROWS, PICKER_ROW_HEIGHT, PICKER_WIDTH = 10, 20, 280
local picker

local function buildPicker()
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetFrameLevel(1)
  catcher:Hide()
  catcher:SetScript("OnClick", function()
    UI.HidePicker()
  end)

  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(10)
  frame:SetSize(PICKER_WIDTH, PICKER_ROWS * PICKER_ROW_HEIGHT + 8)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:Hide()

  frame.background = frame:CreateTexture(nil, "BACKGROUND")
  frame.background:SetAllPoints(frame)
  frame.background:SetColorTexture(0.05, 0.05, 0.05, 0.97)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 4)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(PICKER_WIDTH - 34, 1)
  scroll:SetScrollChild(child)

  picker = { frame = frame, catcher = catcher, scroll = scroll, child = child, rows = {} }
  return picker
end

function UI.GetPicker()
  return picker
end

function UI.HidePicker()
  if picker then
    picker.frame:Hide()
    picker.catcher:Hide()
  end
end

-- items: array of { label, value, font? }. onPick(value) runs on selection.
function UI.ShowPicker(owner, items, current, onPick)
  local p = picker or buildPicker()

  for index, item in ipairs(items) do
    local row = p.rows[index]
    if not row then
      row = CreateFrame("Button", nil, p.child)
      row:SetSize(PICKER_WIDTH - 34, PICKER_ROW_HEIGHT)
      row:SetPoint("TOPLEFT", p.child, "TOPLEFT", 0, -(index - 1) * PICKER_ROW_HEIGHT)
      row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
      row.highlight:SetAllPoints(row)
      row.highlight:SetColorTexture(1, 1, 1, 0.12)
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
      row:SetScript("OnClick", function(self)
        local handler = p.onPick
        UI.HidePicker()
        if handler then
          handler(self.item.value)
        end
      end)
      p.rows[index] = row
    end
    row.item = item
    -- A preview font that fails to load keeps the template font.
    local ok, applied = pcall(row.text.SetFont, row.text, item.font or P.DEFAULT_FONT, 12, "")
    if not (ok and applied) then
      pcall(row.text.SetFont, row.text, P.DEFAULT_FONT, 12, "")
    end
    row.text:SetText(item.label)
    if item.value == current then
      row.text:SetTextColor(1, 0.82, 0, 1)
    else
      row.text:SetTextColor(1, 1, 1, 1)
    end
    row:Show()
  end
  for index = #items + 1, #p.rows do
    p.rows[index]:Hide()
  end

  p.onPick = onPick
  p.child:SetHeight(math.max(#items * PICKER_ROW_HEIGHT, 1))
  p.frame:SetHeight(math.min(#items, PICKER_ROWS) * PICKER_ROW_HEIGHT + 8)
  p.frame:ClearAllPoints()
  p.frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  p.catcher:Show()
  p.frame:Show()
end

-- Label above a button showing the current choice; clicking opens the picker.
-- getItems() -> { label, value, font? }[]; getter() -> value; setter(value).
function UI.dropdown(parent, text, x, y, width, getItems, getter, setter)
  local widget = {}

  widget.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  widget.label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  widget.label:SetText(text)

  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
  widget.button = button

  widget.refresh = function()
    local current = getter()
    local shown = tostring(current)
    for _, item in ipairs(getItems()) do
      if item.value == current then
        shown = item.label
        break
      end
    end
    button:SetText(shown)
  end

  button:SetScript("OnClick", function()
    UI.ShowPicker(button, getItems(), getter(), function(value)
      setter(value)
      widget.refresh()
    end)
  end)

  return widget
end

--
-- Pages
--

P.pages = {}

-- page = { id, title, build = function(content, track) }
function P:RegisterPage(page)
  self.pages[#self.pages + 1] = page
end

function P:PageIndex(id)
  for index, page in ipairs(self.pages) do
    if page.id == id then
      return index
    end
  end
end

-- Builds one page frame. Used for the Settings subcategories, the tabbed
-- fallback and the standalone frame.
function P:CreatePage(page, parent)
  local content = CreateFrame("Frame", nil, parent)
  content:SetSize(PAGE_WIDTH, PAGE_HEIGHT)

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

  UI.label(content, page.title, 16, -12, "GameFontNormalLarge")
  page.build(content, track)

  content:SetScript("OnShow", function()
    P:RefreshOptions()
  end)
  content:SetScript("OnHide", function()
    UI.HidePicker()
  end)
  -- The canvas can already be effectively visible when Settings embeds it, in
  -- which case OnShow does not fire. One update picks up LDB objects that
  -- registered after ADDON_LOADED.
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

-- All pages behind a row of tabs: the fallback when the client has no
-- subcategory API, and the content of the standalone frame.
function P:CreateTabbedContent(parent)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(PAGE_WIDTH, PAGE_HEIGHT + 40)
  holder.contents = {}

  function holder.Select(index)
    for contentIndex, content in ipairs(holder.contents) do
      content:SetShown(contentIndex == index)
    end
    UI.HidePicker()
  end

  local x = 16
  for index, page in ipairs(self.pages) do
    UI.button(holder, page.title, x, -8, function()
      holder.Select(index)
    end, 110)
    x = x + 116
    local content = self:CreatePage(page, holder)
    content:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -36)
    holder.contents[index] = content
  end
  holder.Select(1)
  return holder
end

-- Standalone, draggable frame for /perch frame.
function P:CreateOptionsFrame()
  if self.optionsFrame then
    return self.optionsFrame
  end

  local frame = CreateFrame("Frame", "PerchOptionsFrame", UIParent)
  frame:SetSize(660, 780)
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

  frame.title = UI.label(frame, "Perch - options", 24, -20, "GameFontNormalLarge")
  frame.version = UI.label(
    frame,
    string.format("v%s (build %s)", self.version or "?", self.build or "?"),
    24,
    -44,
    "GameFontHighlightSmall"
  )

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  frame.content = self:CreateTabbedContent(frame)
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
      self:RefreshCommandCell(cell)
    end
  end
  self:RequestLayout()
end

--
-- Settings registration
--

-- The category ID is assigned by the client when the category is registered.
-- Never overwrite category.ID: Settings.OpenToCategory expects the real ID.
local function resolveCategoryID(category)
  if type(category.GetID) == "function" then
    local ok, value = pcall(category.GetID, category)
    if ok and value ~= nil then
      return value
    end
  end
  return category.ID or category.name
end

function P:OptionsCategoryID()
  local category = self.optionsCategory
  if not category then
    return nil
  end
  if self.optionsCategoryID == nil then
    self.optionsCategoryID = resolveCategoryID(category)
  end
  return self.optionsCategoryID
end

function P:OpenSettingsCategory(pageId)
  if not self.optionsCategory or not Settings or type(Settings.OpenToCategory) ~= "function" then
    return false
  end

  local id
  local sub = pageId and self.optionsSubcategories and self.optionsSubcategories[pageId]
  if sub then
    id = resolveCategoryID(sub)
  else
    id = self:OptionsCategoryID()
  end
  if id == nil then
    return false
  end

  local ok = pcall(Settings.OpenToCategory, id)
  if ok and C_Timer and C_Timer.After then
    -- Let the Settings system show the canvas, then fill in the widgets and
    -- the element list (which includes LDB objects registered after login).
    C_Timer.After(0, function()
      P:RefreshOptions()
      -- Tabbed fallback: pick the requested tab.
      local index = pageId and self:PageIndex(pageId)
      if index and not sub and self.optionsCanvas and self.optionsCanvas.Select then
        self.optionsCanvas.Select(index)
      end
    end)
  end
  return ok
end

function P:ShowOptionsFrame(pageId)
  local frame = self.optionsFrame or self:CreateOptionsFrame()
  local index = pageId and self:PageIndex(pageId)
  if frame:IsShown() and not index then
    frame:Hide()
    return
  end
  if index then
    frame.content.Select(index)
  end
  self:RefreshOptions()
  frame:Show()
end

function P:ToggleOptions(pageId)
  if pageId and not self:PageIndex(pageId) then
    pageId = nil
  end
  if self:OpenSettingsCategory(pageId) then
    return
  end
  self:ShowOptionsFrame(pageId)
end

function P:RegisterOptions()
  if self.optionsRegistered then
    return
  end
  self.optionsRegistered = true

  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end

  local hasSubcategories = type(Settings.RegisterCanvasLayoutSubcategory) == "function"
  self.optionsSubcategories = nil

  local ok, category = pcall(function()
    local root
    if hasSubcategories then
      root = self:CreatePage(self.pages[1], nil)
    else
      root = self:CreateTabbedContent(nil)
    end
    self.optionsCanvas = root
    local created = Settings.RegisterCanvasLayoutCategory(root, "Perch")

    if hasSubcategories then
      self.optionsSubcategories = {}
      for index = 2, #self.pages do
        local page = self.pages[index]
        local canvas = self:CreatePage(page, nil)
        local subOk, sub = pcall(Settings.RegisterCanvasLayoutSubcategory, created, canvas, page.title)
        if subOk and type(sub) == "table" then
          self.optionsSubcategories[page.id] = sub
        else
          self.optionsError = tostring(sub)
        end
      end
    end

    self.optionsCategoryID = Settings.RegisterAddOnCategory(created)
    return created
  end)

  if ok and type(category) == "table" then
    self.optionsCategory = category
  else
    self.optionsError = tostring(category)
    self.optionsCategoryID = nil
  end
end

--
-- Landing page (the parent category): version, maintenance buttons, help.
--

P:RegisterPage({
  id = "about",
  title = "Perch",
  build = function(content)
    UI.label(
      content,
      string.format("Version %s (build %s)", P.version or "?", P.build or "?"),
      16,
      -40,
      "GameFontHighlightSmall"
    )
    UI.label(content, "Pick a page on the left: General, Appearance or Elements.", 16, -64, "GameFontHighlight")

    UI.button(content, "Reset position", 16, -110, function()
      local db = P.db.bar
      db.point, db.relativePoint, db.x, db.y = "TOP", "TOP", 0, -8
      P:RestorePosition()
      P:RequestLayout()
    end)

    UI.button(content, "Reset settings", 168, -110, function()
      PerchDB = nil
      P:EnsureDB()
      P:RestorePosition()
      P:RefreshOptions()
      P:ApplyAll()
      P:Print("Settings reset.")
    end)

    UI.button(content, "Doctor report", 320, -110, function()
      P:Doctor()
    end)

    UI.label(
      content,
      "Commands: /perch lock | unlock | scale <n> | enable <key> | disable <key> | cmd add <name> <macro>",
      16,
      -156,
      "GameFontHighlightSmall"
    )
  end,
})
