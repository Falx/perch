--[[
Perch headless test runner.

Run from the repository root:

    luajit tests/run.lua

Exits non-zero when any check fails.
]]

local Stub = dofile("tests/wow_stub.lua")

local passed, failed = 0, 0

local function check(condition, message)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL  ", message, "\n")
  end
end

local function equal(actual, expected, message)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL  ", message, " (expected ", tostring(expected), ", got ", tostring(actual), ")\n")
  end
end

local function section(name)
  io.write("\n", name, "\n")
end

--------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------

section("load")

local P = Stub.LoadAddon()
check(P ~= nil, "addon namespace exists")
equal(P and P.version, "0.1.0", "version comes from the TOC")

Stub.FireEvent("ADDON_LOADED", "Perch")
check(type(PerchDB) == "table", "saved variables created")
equal(PerchDB.version, 1, "schema version seeded")
equal(#PerchDB.order, 8, "default order has 8 built-in keys")
equal(#PerchDB.commands, 0, "no commands by default")
equal(PerchDB.bar.point, "TOP", "bar defaults to TOP")
check(P.bar ~= nil, "bar frame created")

Stub.FireEvent("PLAYER_LOGIN")

local ldb = P.GetLDB()
check(ldb ~= nil, "LDB library loaded")

local count = 0
if ldb then
  for _ in ldb:DataObjectIterator() do
    count = count + 1
  end
end
equal(count, 8, "8 built-in data objects registered")

local cells = 0
for _ in pairs(P.brokerElements) do
  cells = cells + 1
end
equal(cells, 8, "8 broker cells created")

check(P.bar:IsShown(), "bar visible when it has content")
check(P.bar:GetWidth() > 40, "bar has a non-trivial width")

--------------------------------------------------------------------------
-- Built-in content
--------------------------------------------------------------------------

section("built-ins")

local clockCell = P.brokerElements["Perch_Clock"]
check(clockCell ~= nil, "clock cell exists")
equal(clockCell and clockCell.text:GetText(), "2:32", "clock renders 12h time")

local goldCell = P.brokerElements["Perch_Gold"]
equal(goldCell and goldCell.text:GetText(), "123g 45s", "gold formats as g/s")

local coordsCell = P.brokerElements["Perch_Coords"]
equal(coordsCell and coordsCell.text:GetText(), "43.2, 71.8", "coordinates render with one decimal")

local bagsCell = P.brokerElements["Perch_Bags"]
equal(bagsCell and bagsCell.text:GetText(), "9/16", "bag slots render")

local durabilityCell = P.brokerElements["Perch_Durability"]
equal(durabilityCell and durabilityCell.text:GetText(), "80%", "durability takes the lowest slot")

-- 16001 raises "FontString:SetText(): Font not set" instead of drawing nothing.
check(clockCell.text.fontPath ~= nil, "cell font is set before the first SetText")

local fpsCell = P.brokerElements["Perch_FPS"]
local savedGetFPS = GetFPS
GetFPS = nil
Stub.Tick()
equal(fpsCell and fpsCell.text:GetText(), "60 fps", "fps falls back to GetFramerate")
GetFPS = savedGetFPS
Stub.Tick()
equal(fpsCell and fpsCell.text:GetText(), "61 fps", "fps prefers GetFPS when present")

--------------------------------------------------------------------------
-- Update strategy
--------------------------------------------------------------------------

section("update strategy")

local setTextBefore = clockCell.text.setTextCount or 0
Stub.Tick()
Stub.Tick()
equal(clockCell.text.setTextCount or 0, setTextBefore, "unchanged text is not re-set on poll")

local scratch = ldb:NewDataObject("Test_Scratch", {
  type = "data source",
  label = "Scratch",
  text = "one",
})

local scratchCell = P.brokerElements["Test_Scratch"]
check(scratchCell ~= nil, "late-registered data object gets a cell immediately")
equal(scratchCell and scratchCell.text:GetText(), "one", "late object renders its text")

scratch.text = "two"
equal(scratchCell and scratchCell.text:GetText(), "two", "attribute change updates the cell via callback")

local clicks = {}
local clickTarget
scratch.OnClick = function(target, button)
  clickTarget = target
  clicks[#clicks + 1] = button
end
scratchCell:GetScript("OnClick")(scratchCell, "RightButton")
equal(clicks[1], "RightButton", "click is forwarded with the button argument")
equal(clickTarget, scratchCell, "click forwards the cell, like LibDBIcon")

local launcher = ldb:NewDataObject("Test_Launcher", {
  type = "launcher",
  icon = "Interface\\Icons\\INV_Misc_QuestionMark",
})
check(P.brokerElements["Test_Launcher"] ~= nil, "launcher gets a cell")
check(not P:IsEnabled("Test_Launcher"), "launchers are hidden by default")
check(not tContains(P:OrderedKeys(), "Test_Launcher"), "hidden launcher stays out of the order")
P:SetElementEnabled("Test_Launcher", true)
check(P:IsEnabled("Test_Launcher"), "launcher can be enabled explicitly")
check(tContains(P:OrderedKeys(), "Test_Launcher"), "enabled launcher joins the order")
P:SetElementEnabled("Test_Launcher", false)
check(not P:IsEnabled("Test_Launcher"), "launcher can be disabled again")

scratch.OnTooltipShow = function(tooltip)
  tooltip:AddLine("custom tooltip")
end
GameTooltip:ClearLines()
scratchCell:GetScript("OnEnter")(scratchCell)
local tooltipText = GameTooltip.lines and GameTooltip.lines[1]
equal(tooltipText, "custom tooltip", "plugin tooltip is used when provided")

Stub.Tick()
equal(scratchCell.text:GetText(), "two", "poll fallback keeps content stable")

--------------------------------------------------------------------------
-- Resilience
--------------------------------------------------------------------------

section("resilience")

local realRefresh = P.RefreshBrokerCell
P.RefreshBrokerCell = function(self, cell, obj)
  if cell.brokerName == "Test_Explode" then
    error("boom")
  end
  return realRefresh(self, cell, obj)
end

local exploding = ldb:NewDataObject("Test_Explode", {
  type = "data source",
  text = "explode",
})
local survivor = ldb:NewDataObject("Test_Survivor", {
  type = "data source",
  text = "survivor",
})

P.RefreshBrokerCell = realRefresh

check(exploding ~= nil, "failing data object still registers with LDB")
check(P.brokerElements["Test_Explode"] ~= nil, "a cell is kept for the failing object")
check(P.brokerErrors["Test_Explode"] ~= nil, "the failure is recorded for /perch doctor")
check(P.brokerElements["Test_Survivor"] ~= nil, "later objects still register after a failure")
equal(P.brokerElements["Test_Survivor"].text:GetText(), "survivor", "later objects still render")

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

section("commands")

SlashCmdList["PERCH"]("cmd add Reload /reload")
check(P.commandCells["cmd:Reload"] ~= nil, "command cell created")
equal(P.commandCells["cmd:Reload"]:GetAttribute("macrotext"), "/reload", "macro text stored as an attribute")
equal(P.commandCells["cmd:Reload"]:GetAttribute("type"), "macro", "secure button type is macro")
equal(P.commandCells["cmd:Reload"].clicks and P.commandCells["cmd:Reload"].clicks[1], "AnyUp",
  "secure button registers clicks (otherwise the macro never fires)")
equal(P.commandCells["cmd:Reload"]:GetAttribute("type1"), "macro", "left-click type attribute is set")
equal(P.commandCells["cmd:Reload"]:GetAttribute("macrotext1"), "/reload", "left-click macrotext is set")
equal(P.commandCells["cmd:Reload"]:GetParent(), UIParent,
  "secure cells live on UIParent (anchoring them to the bar protects broker cells)")

SlashCmdList["PERCH"]("cmd add Reload /reload")
equal(#PerchDB.commands, 1, "duplicate command names are rejected")

SlashCmdList["PERCH"]("cmd del Reload")
check(P.commandCells["cmd:Reload"] == nil, "command removal deletes the cell")
equal(#PerchDB.commands, 0, "command removal updates saved data")

SlashCmdList["PERCH"]("cmd add Reload /reload")

--------------------------------------------------------------------------
-- Layout and enable/disable
--------------------------------------------------------------------------

section("layout")

local widthBefore = P.bar:GetWidth()
check(widthBefore > 0, "bar width before disabling is positive")

SlashCmdList["PERCH"]("disable Perch_FPS")
check(not P:IsEnabled("Perch_FPS"), "disable flag stored")
check(not tContains(P:OrderedKeys(), "Perch_FPS"), "disabled element leaves the order")
check(P.bar:GetWidth() < widthBefore, "bar shrinks when an element is disabled")

SlashCmdList["PERCH"]("enable Perch_FPS")
check(P:IsEnabled("Perch_FPS"), "enable flag stored")
equal(P.bar:GetWidth(), widthBefore, "bar returns to its previous width")

-- Disabled cells must actually disappear; the poller used to re-show them at
-- their old anchor, so they drew over the next element.
P:SetElementEnabled("Perch_Gold", false)
check(not goldCell:IsShown(), "disabled broker cell is hidden")
Stub.Tick()
check(not goldCell:IsShown(), "poll does not re-show a disabled cell")
P:SetElementEnabled("Perch_Gold", true)
check(goldCell:IsShown(), "re-enabling shows the broker cell again")

local ordered = P:OrderedKeys()
equal(ordered[1], "Perch_Clock", "built-ins keep their default order")
check(tContains(ordered, "cmd:Reload"), "commands participate in the order")

-- Command cells anchor to a mirror frame, never to the bar: on 16001 anchoring
-- a secure button to a normal frame protects it and blocks SetWidth in combat.
Stub.Tick()
local secureCell = P.commandCells["cmd:Reload"]
local _, secureRelativeTo = secureCell:GetPoint()
check(secureRelativeTo ~= nil and secureRelativeTo ~= P.bar,
  "secure cell is not anchored to the bar")
equal(secureRelativeTo, P.secureAnchor, "secure cell anchors to the mirror frame")
check(P.secureAnchor:IsShown(), "mirror frame is shown while command cells exist")

--------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------

section("diagnostics")

Stub.ResetMessages()
P:Doctor()
local report = table.concat(Stub.messages, "\n")
check(report:find("Perch 0.1.0", 1, true) ~= nil, "doctor reports the version")
check(report:find("LibDataBroker: ok", 1, true) ~= nil, "doctor reports LDB")
check(report:find("client 1.60.1", 1, true) ~= nil, "doctor reports the client build")
check(report:find("broker cells:", 1, true) ~= nil, "doctor reports the broker cell count")
check(report:find("broker errors:", 1, true) ~= nil, "doctor reports broker failures")
check(report:find("bar: shown", 1, true) ~= nil, "doctor reports the bar state")
check(report:find("command cells:", 1, true) ~= nil, "doctor reports the command cell count")
check(report:find("cmd:Reload:", 1, true) ~= nil, "doctor lists each command cell")
check(report:find("parent UIParent", 1, true) ~= nil, "doctor shows the command cell parent")

Stub.ResetMessages()
SlashCmdList["PERCH"]("dump")
check(#Stub.messages > 0, "dump prints saved variables")

Stub.ResetMessages()
SlashCmdList["PERCH"]("list")
check(#Stub.messages > 0, "list prints elements")

Stub.ResetMessages()
SlashCmdList["PERCH"]("bogus")
check(Stub.LastMessage():find("Commands:", 1, true) ~= nil, "unknown command prints help")

--------------------------------------------------------------------------
-- Combat and options
--------------------------------------------------------------------------

section("combat and options")

Stub.inCombat = true
P.layoutDeferred = nil
P:Layout()
check(P.layoutDeferred == true, "layout is deferred during combat")
Stub.inCombat = false
P:Layout()
check(P.layoutDeferred == nil, "layout runs again after combat")

Stub.inCombat = true
Stub.ResetMessages()
SlashCmdList["PERCH"]("cmd add Combat /say hi")
check(P.commandRebuildPending == true, "command rebuild defers while in combat")
Stub.inCombat = false
Stub.FireEvent("PLAYER_REGEN_ENABLED")
check(P.commandCells["cmd:Combat"] ~= nil, "deferred rebuild happens after combat")

-- Secure cells cannot be hidden once combat locks them, so they are hidden on
-- PLAYER_REGEN_DISABLED (the last safe moment) and synced again afterwards.
check(P.commandCells["cmd:Reload"]:IsShown(), "command cell is shown out of combat")
Stub.inCombat = true
Stub.FireEvent("PLAYER_REGEN_DISABLED")
check(not P.commandCells["cmd:Reload"]:IsShown(), "command cell hides when combat starts")
Stub.inCombat = false
Stub.FireEvent("PLAYER_REGEN_ENABLED")
check(P.commandCells["cmd:Reload"]:IsShown(), "command cell returns after combat")

check(P.optionsFrame == nil, "standalone frame is created lazily")
check(P.optionsCanvas ~= nil, "settings canvas content exists")
check(Stub.optionsCategory ~= nil, "options registered with the Settings API")
SlashCmdList["PERCH"]("config")
equal(Stub.openedCategory, "Perch", "config opens the Settings category")

-- Opening Options > AddOns > Perch directly never fires OnShow on the canvas,
-- so the widgets must already hold the saved values when they are built.
check(P.optionWidgets[1] ~= nil, "options widgets exist")
equal(P.optionWidgets[1]:GetChecked(), PerchDB.bar.locked,
  "options widgets are initialised when they are created")

local elementListWidget
for _, widget in ipairs(P.optionWidgets) do
  if widget.rows then
    elementListWidget = widget
  end
end
check(elementListWidget ~= nil, "element list widget exists")
P:RefreshOptions()
local listed = false
for _, row in ipairs(elementListWidget.rows) do
  if row.elementKey == "Test_Scratch" then
    listed = true
  end
end
check(listed, "element list picks up LDB objects registered after login")

check(P.optionsFrame == nil, "using Settings does not build the standalone frame")
SlashCmdList["PERCH"]("frame")
check(P.optionsFrame ~= nil and P.optionsFrame:IsShown(), "frame command opens the standalone options frame")
SlashCmdList["PERCH"]("frame")
check(not P.optionsFrame:IsShown(), "frame command toggles the standalone options frame")

P:RefreshOptions()
check(#P.optionWidgets > 0, "options widgets can be refreshed")

--------------------------------------------------------------------------
-- Settings pages
--------------------------------------------------------------------------

section("settings pages")

equal(#Stub.subcategories, 3, "General, Appearance and Elements register as subcategories")
equal(Stub.subcategories[1].name, "General", "first subcategory is General")
equal(Stub.subcategories[2].name, "Appearance", "second subcategory is Appearance")
equal(Stub.subcategories[3].name, "Elements", "third subcategory is Elements")

SlashCmdList["PERCH"]("config appearance")
equal(Stub.openedCategory, "Appearance", "config <page> opens that subcategory")
SlashCmdList["PERCH"]("config nonsense")
equal(Stub.openedCategory, "Perch", "an unknown page opens the main category")

local function findCheckbox(text)
  for _, widget in ipairs(P.optionWidgets) do
    if widget.label and widget.label.GetText and tostring(widget.label:GetText()):find(text, 1, true)
      and widget.SetChecked then
      return widget
    end
  end
end

local toggles = {
  { "Lock the bar", "locked" },
  { "Enable icons", "showIcons" },
  { "Hide bar when empty", "hideWhenEmpty" },
  { "Fade until mouseover", "mouseoverFade" },
  { "Hide in combat", "hideInCombat" },
  { "Click-through", "clickThrough" },
}
for _, toggle in ipairs(toggles) do
  local widget = findCheckbox(toggle[1])
  check(widget ~= nil, "general page has the '" .. toggle[1] .. "' toggle")
  if widget then
    local before = PerchDB.bar[toggle[2]]
    widget:SetChecked(not before)
    widget.scripts.OnClick(widget)
    equal(PerchDB.bar[toggle[2]], not before, toggle[1] .. " toggle writes the setting")
    widget:SetChecked(before)
    widget.scripts.OnClick(widget)
  end
end

check(P.GetLSM() ~= nil, "LibSharedMedia is embedded and loads")
local fontNames = {}
for _, entry in ipairs(P:MediaList("font")) do
  fontNames[entry.name] = entry.path
end
equal(fontNames["Friz Quadrata TT"], "Fonts\\FRIZQT__.TTF", "font list includes the default font")
equal(fontNames["Arial Narrow"], "Fonts\\ARIALN.TTF", "font list includes Arial Narrow")

local fontDropdown
for _, widget in ipairs(P.optionWidgets) do
  if widget.button and widget.label and widget.label:GetText() == "Font" then
    fontDropdown = widget
  end
end
check(fontDropdown ~= nil, "appearance page has a font selector")
equal(fontDropdown.button.text, "Friz Quadrata TT", "font selector shows the current font by name")
fontDropdown.button.scripts.OnClick(fontDropdown.button)
local picker = P.UI.GetPicker()
check(picker ~= nil and picker.frame:IsShown(), "clicking the font selector opens the picker")
local arialRow
for _, row in ipairs(picker.rows) do
  if row:IsShown() and row.item.label == "Arial Narrow" then
    arialRow = row
  end
end
check(arialRow ~= nil, "picker lists Arial Narrow")
arialRow.scripts.OnClick(arialRow)
equal(PerchDB.bar.font.name, "Fonts\\ARIALN.TTF", "picking a font stores its path")
check(not picker.frame:IsShown(), "picking a font closes the picker")
equal(fontDropdown.button.text, "Arial Narrow", "font selector shows the new choice")
equal(P.brokerElements["Perch_Clock"].text.fontPath, "Fonts\\ARIALN.TTF", "cells use the chosen font")

PerchDB.bar.font.name = "Fonts\\Missing.ttf"
P:ApplyAll()
equal(P.brokerElements["Perch_Clock"].text.fontPath, P.DEFAULT_FONT,
  "an unresolvable font falls back to the default instead of leaving cells fontless")
PerchDB.bar.font.name = "Fonts\\FRIZQT__.TTF"
P:ApplyAll()

-- Sliders have a typeable number box next to them, not just a label.
local heightSlider
for _, widget in ipairs(P.optionWidgets) do
  if widget.label and widget.input and widget.label:GetText() == "Bar height" then
    heightSlider = widget
  end
end
check(heightSlider ~= nil and heightSlider.input ~= nil, "bar height slider has a number input")
equal(heightSlider.input.box:GetText(), tostring(PerchDB.bar.height), "number input shows the current value")
heightSlider.input.box:SetText("30")
heightSlider.input.box.scripts.OnEnterPressed(heightSlider.input.box)
equal(PerchDB.bar.height, 30, "typing a value applies it")
heightSlider.input.box:SetText("500")
heightSlider.input.box.scripts.OnEnterPressed(heightSlider.input.box)
equal(PerchDB.bar.height, 40, "typed values are clamped to the slider maximum")
heightSlider.input.box:SetText("abc")
heightSlider.input.box.scripts.OnEnterPressed(heightSlider.input.box)
equal(PerchDB.bar.height, 40, "a non-number is ignored")
equal(heightSlider.input.box:GetText(), "40", "the input reverts after a bad value")
heightSlider.input.box:SetText("22")
heightSlider.input.box.scripts.OnEnterPressed(heightSlider.input.box)
equal(PerchDB.bar.height, 22, "height restored")

-- Per-element options and ordering.
local goldKey = "Perch_Gold"
local plainValue = P:BrokerText(goldCell.obj)
equal(P:ElementOption(goldKey, "showIcon"), true, "icons default on for broker elements")
equal(P:ElementOption(goldKey, "showValue"), true, "values default on for broker elements")
equal(P:ElementOption(goldKey, "showLabel"), false, "labels default off for broker elements")
equal(P:ElementOption("cmd:Reload", "showLabel"), true, "labels default on for commands")
equal(goldCell.text:GetText(), plainValue, "default broker text is just the value")

P:SetElementOption(goldKey, "showLabel", true)
equal(goldCell.text:GetText(), "Gold: " .. plainValue, "label option prefixes the value")
P:SetElementOption(goldKey, "showValue", false)
equal(goldCell.text:GetText(), "Gold", "label alone when the value is off")
P:SetElementOption(goldKey, "label", "Money")
equal(goldCell.text:GetText(), "Money", "custom label replaces the plugin label")
P:SetElementOption(goldKey, "label", "   ")
equal(goldCell.text:GetText(), "Gold", "a blank custom label falls back to the default")
P:SetElementOption(goldKey, "showLabel", false)
check(goldCell.text:GetText() == "" , "nothing to show when label and value are both off")
P:SetElementOption(goldKey, "showValue", true)
equal(goldCell.text:GetText(), plainValue, "value restored")

P:SetElementOption(goldKey, "showIcon", false)
check(not goldCell.icon:IsShown(), "icon option hides the icon")
P:SetElementOption(goldKey, "showIcon", true)
check(goldCell.icon:IsShown(), "icon option shows the icon again")

local reloadCell = P.commandCells["cmd:Reload"]
equal(reloadCell.text:GetText(), "Reload", "command cell shows its name by default")
P:SetElementOption("cmd:Reload", "showLabel", false)
equal(reloadCell.text:GetText(), "", "command label can be turned off")
P:SetElementOption("cmd:Reload", "label", "RL")
P:SetElementOption("cmd:Reload", "showLabel", true)
equal(reloadCell.text:GetText(), "RL", "command shows its custom label")
P:SetElementOption("cmd:Reload", "label", "")

local orderBefore = P:AllKeys()
local firstKey, secondKey = orderBefore[1], orderBefore[2]
check(not P:MoveElement(firstKey, -1), "the first element cannot move up")
check(not P:MoveElement(orderBefore[#orderBefore], 1), "the last element cannot move down")
PerchDB.order[#PerchDB.order + 1] = "Ghost_Plugin"
check(P:MoveElement(firstKey, 1), "an element can move down")
equal(P:AllKeys()[1], secondKey, "moving down swaps with the next element")
equal(P:AllKeys()[2], firstKey, "the moved element takes the next place")
check(tContains(PerchDB.order, "Ghost_Plugin"), "order keeps entries for plugins that are not loaded")
check(P:MoveElement(firstKey, -1), "an element can move back up")
equal(P:AllKeys()[1], firstKey, "order restored")

-- Elements page: list, selection and detail options.
local listWidget
for _, widget in ipairs(P.optionWidgets) do
  if widget.rows and widget.child then
    listWidget = widget
  end
end
P:RefreshOptions()
local shownRows = 0
for _, row in ipairs(listWidget.rows) do
  if row:IsShown() then
    shownRows = shownRows + 1
  end
end
equal(shownRows, #P:AllKeys(), "the element list has one row per element, hidden ones included")

local goldRow, reloadRow
for _, row in ipairs(listWidget.rows) do
  if row.elementKey == goldKey then
    goldRow = row
  elseif row.elementKey == "cmd:Reload" then
    reloadRow = row
  end
end
goldRow.scripts.OnClick(goldRow)
equal(P.selectedElement, goldKey, "clicking a row selects that element")
check(goldRow.selection:IsShown(), "the selected row is highlighted")

local labelFlag = findCheckbox("Label")
local valueFlag = findCheckbox("Value")
check(labelFlag ~= nil and valueFlag ~= nil, "elements page has Label and Value checkboxes")
labelFlag:SetChecked(true)
labelFlag.scripts.OnClick(labelFlag)
equal(PerchDB.elements[goldKey].showLabel, true, "Label checkbox writes the selected element's option")
labelFlag:SetChecked(false)
labelFlag.scripts.OnClick(labelFlag)
check(valueFlag:IsEnabled(), "Value checkbox is enabled for a data source")

reloadRow.scripts.OnClick(reloadRow)
check(not valueFlag:IsEnabled(), "Value checkbox is disabled for a command")

goldRow.scripts.OnClick(goldRow)
local box = P.elementLabelBox.box
box:SetText("Money")
box.scripts.OnTextChanged(box, true)
equal(PerchDB.elements[goldKey].label, "Money", "typing in the label box stores the custom label live")
box:SetText("")
box.scripts.OnTextChanged(box, true)
equal(PerchDB.elements[goldKey].label, nil, "clearing the label box removes the custom label")

local showFlag = findCheckbox("Show on the bar")
showFlag:SetChecked(false)
showFlag.scripts.OnClick(showFlag)
check(not P:IsEnabled(goldKey), "Show checkbox hides the element")
showFlag:SetChecked(true)
showFlag.scripts.OnClick(showFlag)
check(P:IsEnabled(goldKey), "Show checkbox shows the element again")

-- Without the subcategory API every page sits behind tabs in one canvas.
local realSubcategory = Settings.RegisterCanvasLayoutSubcategory
Settings.RegisterCanvasLayoutSubcategory = nil
P.optionsRegistered = false
P:RegisterOptions()
check(P.optionsSubcategories == nil, "no subcategories without the API")
check(P.optionsCanvas.Select ~= nil, "fallback canvas has tabs")
SlashCmdList["PERCH"]("config elements")
check(P.optionsCanvas.contents[4]:IsShown() and not P.optionsCanvas.contents[1]:IsShown(),
  "config <page> selects the tab in the fallback")
Settings.RegisterCanvasLayoutSubcategory = realSubcategory

--------------------------------------------------------------------------
-- Barrier
--------------------------------------------------------------------------

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
