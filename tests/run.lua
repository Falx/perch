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

-- Visibility regressions: a bare Slider draws nothing and an EditBox without a
-- font never draws its text (the boxes looked empty in the client).
local editBoxes, sliders, emptyBoxes = 0, 0, 0
for _, frame in ipairs(Stub.frames) do
  if frame.kind == "EditBox" then
    editBoxes = editBoxes + 1
    check(frame:FontIsSet(), "every edit box has a font")
    if not frame:HasFocus() then
      equal(frame:GetCursorPosition(), 0, "an unfocused edit box shows the start of its text")
    end
  elseif frame.kind == "Slider" then
    sliders = sliders + 1
    check(frame:GetThumbTexture() ~= nil, "every slider has a visible thumb")
  end
end
check(editBoxes >= 7 and sliders >= 6, "options pages built their sliders and edit boxes")
for _, widget in ipairs(P.optionWidgets) do
  if widget.input and (widget.input.box:GetText() or "") == "" then
    emptyBoxes = emptyBoxes + 1
  end
end
equal(emptyBoxes, 0, "number boxes are initialised with their saved values")
equal(heightSlider.input.box:GetText(), tostring(PerchDB.bar.height), "height box shows the saved height")

-- Number boxes only take numbers, follow the slider live, and step on arrow/wheel.
local heightBox = heightSlider.input.box
heightBox:SetText("1a2b")
heightBox.scripts.OnTextChanged(heightBox, true)
equal(heightBox:GetText(), "12", "letters are stripped from a number box")
equal(PerchDB.bar.height, 22, "an out-of-range partial value is not applied while typing")
heightBox:SetText("1.5")
heightBox.scripts.OnTextChanged(heightBox, true)
equal(heightBox:GetText(), "15", "an integer box rejects a decimal point")
equal(PerchDB.bar.height, 15, "a valid in-range value applies while typing")
equal(heightSlider:GetValue(), 15, "the slider thumb follows the typed value")
heightBox:SetText("12")
heightBox.scripts.OnEnterPressed(heightBox)
equal(PerchDB.bar.height, 14, "Enter clamps a too-small value to the minimum")

heightBox.scripts.OnArrowPressed(heightBox, "UP")
equal(PerchDB.bar.height, 15, "Up arrow raises the value by one step")
heightBox.scripts.OnArrowPressed(heightBox, "DOWN")
equal(PerchDB.bar.height, 14, "Down arrow lowers the value by one step")
heightBox.scripts.OnArrowPressed(heightBox, "DOWN")
equal(PerchDB.bar.height, 14, "arrow keys stop at the minimum")
heightSlider.scripts.OnMouseWheel(heightSlider, 1)
equal(PerchDB.bar.height, 15, "mouse wheel up raises the value")
heightSlider.scripts.OnMouseWheel(heightSlider, -1)
equal(PerchDB.bar.height, 14, "mouse wheel down lowers the value")
heightBox:SetText("22")
heightBox.scripts.OnEnterPressed(heightBox)
equal(PerchDB.bar.height, 22, "height restored again")

-- Every Appearance slider has a Default button that resets it.
local defaultFor = {
  ["Scale"] = P.defaults.bar.scale,
  ["Font size"] = P.defaults.bar.font.size,
  ["Bar height"] = P.defaults.bar.height,
  ["Spacing"] = P.defaults.bar.spacing,
  ["Icon size"] = P.defaults.bar.iconSize,
  ["Background alpha"] = P.defaults.bar.background.color[4],
}
local sliderCount = 0
for _, widget in ipairs(P.optionWidgets) do
  if widget.input and widget.label and defaultFor[widget.label:GetText()] ~= nil then
    sliderCount = sliderCount + 1
    check(widget.defaultButton ~= nil, widget.label:GetText() .. " slider has a Default button")
    equal(widget.defaultButton.text, "Default", widget.label:GetText() .. " reset button is labelled Default")
  end
end
check(sliderCount >= 6, "all six Appearance sliders were checked")

local defaultHeight = heightSlider.defaultButton
check(not defaultHeight:IsEnabled(), "Default is disabled while the value already is the default")
heightBox:SetText("30")
heightBox.scripts.OnEnterPressed(heightBox)
equal(PerchDB.bar.height, 30, "height changed")
check(defaultHeight:IsEnabled(), "Default is enabled once the value differs")
defaultHeight.scripts.OnClick(defaultHeight)
equal(PerchDB.bar.height, P.defaults.bar.height, "Default resets the value")
equal(heightBox:GetText(), tostring(P.defaults.bar.height), "Default updates the number box")
equal(heightSlider:GetValue(), P.defaults.bar.height, "Default moves the slider")
check(not defaultHeight:IsEnabled(), "Default is disabled again after resetting")

heightBox:SetText("25")
heightBox.scripts.OnTextChanged(heightBox, true)
check(defaultHeight:IsEnabled(), "typing a different value enables Default live")
defaultHeight.scripts.OnClick(defaultHeight)

local alphaSlider
for _, widget in ipairs(P.optionWidgets) do
  if widget.label and widget.input and widget.label:GetText() == "Background alpha" then
    alphaSlider = widget
  end
end
PerchDB.bar.background.color[4] = 0.9
alphaSlider.refresh()
alphaSlider.defaultButton.scripts.OnClick(alphaSlider.defaultButton)
equal(PerchDB.bar.background.color[4], P.defaults.bar.background.color[4], "alpha Default restores the shipped alpha")

local scaleSlider
for _, widget in ipairs(P.optionWidgets) do
  if widget.label and widget.input and widget.label:GetText() == "Scale" then
    scaleSlider = widget
  end
end
local scaleBox = scaleSlider.input.box
scaleBox:SetText("-1.2.5x")
scaleBox.scripts.OnTextChanged(scaleBox, true)
equal(scaleBox:GetText(), "1.25", "a decimal box keeps one decimal point and drops other characters")
equal(PerchDB.bar.scale, 1.25, "decimal values apply while typing")
scaleBox:SetText("1")
scaleBox.scripts.OnEnterPressed(scaleBox)
equal(PerchDB.bar.scale, 1, "scale restored")

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

-- Right-click on a built-in opens its settings; left-click leaves the options alone.
local clockCell = P.brokerElements["Perch_Clock"]
equal(clockCell.clicks and clockCell.clicks[1], "AnyUp", "broker cells register for right-clicks too")
P.selectedElement = goldKey
Stub.openedCategory = nil
clockCell.scripts.OnClick(clockCell, "LeftButton")
equal(Stub.openedCategory, nil, "left-clicking a built-in does not open the options")
clockCell.scripts.OnClick(clockCell, "RightButton")
equal(P.selectedElement, "Perch_Clock", "right-click selects the clicked element")
equal(Stub.openedCategory, "Elements", "right-click opens the Elements page")

local clock24 = findCheckbox("24-hour clock")
local clockLocal = findCheckbox("Use local time")
check(clock24 ~= nil and clockLocal ~= nil, "clock settings exist on the Elements page")
check(clock24:IsShown() and clockLocal:IsShown(), "clock settings show while the clock is selected")
equal(clockCell.text:GetText(), "2:32", "clock starts in 12-hour mode")
clock24:SetChecked(true)
clock24.scripts.OnClick(clock24)
equal(PerchDB.settings.clock24, true, "24-hour toggle writes the setting")
equal(clockCell.text:GetText(), "14:32", "the clock re-renders immediately")
clock24:SetChecked(false)
clock24.scripts.OnClick(clock24)
equal(clockCell.text:GetText(), "2:32", "back to 12-hour")

local decimalsDropdown
for _, widget in ipairs(P.optionWidgets) do
  if widget.button and widget.label and widget.label:GetText() == "Coordinate decimals" then
    decimalsDropdown = widget
  end
end
check(decimalsDropdown ~= nil, "coordinate settings exist on the Elements page")
check(not decimalsDropdown.button:IsShown(), "coordinate settings are hidden while the clock is selected")
check(not decimalsDropdown.label:IsShown(), "the coordinate label is hidden too")

local coordsCell = P.brokerElements["Perch_Coords"]
coordsCell.scripts.OnClick(coordsCell, "RightButton")
equal(P.selectedElement, "Perch_Coords", "right-clicking coordinates selects them")
check(decimalsDropdown.button:IsShown(), "coordinate settings show for the coordinates element")
check(not clock24:IsShown(), "clock settings hide for other elements")
decimalsDropdown.button.scripts.OnClick(decimalsDropdown.button)
local twoRow
for _, row in ipairs(P.UI.GetPicker().rows) do
  if row:IsShown() and row.item.value == 2 then
    twoRow = row
  end
end
twoRow.scripts.OnClick(twoRow)
equal(PerchDB.settings.coordDecimals, 2, "decimals dropdown writes the setting")
PerchDB.settings.coordDecimals = 1
P:RefreshBuiltin("Perch_Coords")
P.selectedElement = goldKey
P:RefreshOptions()

-- Built-in formats, bags and durability.
section("built-in settings")

local codes = P:FormatCodes("#g g #s s", { g = 12, s = 34 })
equal(codes, "12 g 34 s", "format codes expand")
equal(P:FormatCodes("##g #z", { g = 1 }), "#g #z", "## is a literal # and unknown codes stay as typed")
equal(P:FormatCodes("#gi #g", { g = "G", gi = "ICON" }), "ICON G", "the longest code wins")

local copper = 123 * 10000 + 45 * 100 + 67
equal(P:FormatMoneyDisplay(copper), "123g 45s", "default gold format is unchanged")
PerchDB.settings.goldFormat = "letters"
equal(P:FormatMoneyDisplay(copper), "123g 45s 67c", "letters preset shows gold, silver and copper")
PerchDB.settings.goldFormat = "gold"
equal(P:FormatMoneyDisplay(copper), "123g", "gold-only preset")
PerchDB.settings.goldFormat = "icons"
local iconText = P:FormatMoneyDisplay(copper)
check(iconText:find("UI-GoldIcon", 1, true) and iconText:find("UI-SilverIcon", 1, true)
  and iconText:find("UI-CopperIcon", 1, true), "icons preset uses the three coin icons")
PerchDB.settings.goldFormat = "custom"
PerchDB.settings.goldCustom = "#g/#s/#c"
equal(P:FormatMoneyDisplay(copper), "123/45/67", "custom gold format uses the codes")
PerchDB.settings.goldCustom = ""
equal(P:FormatMoneyDisplay(copper), "123g 45s", "an empty custom gold format falls back to the default")
PerchDB.settings.goldFormat = "letters"
P:RefreshBuiltin("Perch_Gold")
equal(P.brokerElements["Perch_Gold"].text:GetText(), "123g 45s 67c", "changing the gold format re-renders the bar")
PerchDB.settings.goldFormat = "default"
P:RefreshBuiltin("Perch_Gold")

local xpCases = {
  { "percent", 0, "50%" },
  { "percentRested", 250, "50%+25%" },
  { "fraction", 0, "500/1000" },
  { "fractionRested", 250, "500+250/1000" },
  { "missing", 0, "-500" },
  { "custom", 250, "50% (500/1000)" },
}
for _, case in ipairs(xpCases) do
  PerchDB.settings.xpFormat = case[1]
  Stub.rested = case[2]
  P:RefreshBuiltin("Perch_XP")
  equal(P.brokerElements["Perch_XP"].text:GetText(), case[3], "XP format '" .. case[1] .. "'")
end
PerchDB.settings.xpCustom = "#xp% left, #r rested"
Stub.rested = 100
P:RefreshBuiltin("Perch_XP")
equal(P.brokerElements["Perch_XP"].text:GetText(), "50% left, 100 rested", "custom XP codes")
PerchDB.settings.xpFormat = "percent"
Stub.rested = 0
P:RefreshBuiltin("Perch_XP")

local bagsCell = P.brokerElements["Perch_Bags"]
equal(bagsCell.text:GetText(), "9/16", "bags show free/total")
Stub.bagData[1] = { slots = 8, free = 3 }
P:RefreshBuiltin("Perch_Bags")
equal(bagsCell.text:GetText(), "12/24", "bags add up across all bags")
Stub.bagData[1] = nil
P:RefreshBuiltin("Perch_Bags")

Stub.openedCategory = nil
bagsCell.scripts.OnClick(bagsCell, "LeftButton")
equal(Stub.bagsToggled, 1, "left-clicking bags toggles the bags")
equal(Stub.openedCategory, nil, "left-clicking bags does not open the options")
bagsCell.scripts.OnClick(bagsCell, "RightButton")
equal(Stub.bagsToggled, 1, "right-clicking bags does not toggle them")
equal(Stub.openedCategory, nil, "bags have no settings, so right-click does nothing")

local durabilityCell = P.brokerElements["Perch_Durability"]
Stub.openedCategory = nil
durabilityCell.scripts.OnClick(durabilityCell, "RightButton")
equal(Stub.openedCategory, nil, "durability has no right-click settings")
GameTooltip.lines = {}
P:ShowBrokerTooltip(durabilityCell)
local tooltip = table.concat(GameTooltip.lines, "\n")
check(tooltip:find("Head 80%", 1, true) ~= nil, "durability tooltip lists the head slot")
check(tooltip:find("Chest 80%", 1, true) ~= nil, "durability tooltip lists the chest slot")

-- Settings UI for these elements.
local function pickItem(dropdown, value)
  dropdown.button.scripts.OnClick(dropdown.button)
  for _, row in ipairs(P.UI.GetPicker().rows) do
    if row:IsShown() and row.item.value == value then
      row.scripts.OnClick(row)
      return true
    end
  end
  return false
end

local function findDropdown(label)
  for _, widget in ipairs(P.optionWidgets) do
    if widget.button and widget.label and widget.label:GetText() == label then
      return widget
    end
  end
end

P.selectedElement = "Perch_Gold"
P:RefreshOptions()
local goldDropdown = findDropdown("Gold format")
check(goldDropdown ~= nil and goldDropdown.button:IsShown(), "gold format selector shows for the gold element")
check(not findCheckbox("24-hour clock"):IsShown(), "clock settings hide for the gold element")
check(pickItem(goldDropdown, "custom"), "gold format can be set to custom")
equal(PerchDB.settings.goldFormat, "custom", "the preset choice is stored")
PerchDB.settings.goldCustom = "#g"
local customBoxes = {}
for _, frame in ipairs(Stub.frames) do
  if frame.kind == "EditBox" and frame.maxLetters == 60 then
    customBoxes[#customBoxes + 1] = frame
  end
end
check(#customBoxes >= 2, "gold and XP have custom format boxes")
local goldBox = customBoxes[1]
check(goldBox:IsShown(), "the custom gold box shows once Custom is chosen")
goldBox:SetText("#g only")
goldBox.scripts.OnTextChanged(goldBox, true)
equal(PerchDB.settings.goldCustom, "#g only", "typing a custom gold format stores it")
equal(P.brokerElements["Perch_Gold"].text:GetText(), "123 only", "the custom gold format applies live")
check(pickItem(goldDropdown, "default"), "gold format can go back to the default")
check(not goldBox:IsShown(), "the custom gold box hides for presets")

P.selectedElement = "Perch_XP"
P:RefreshOptions()
local xpDropdown = findDropdown("Experience format")
check(xpDropdown ~= nil and xpDropdown.button:IsShown(), "XP format selector shows for the XP element")
check(not goldDropdown.button:IsShown(), "gold format selector hides for the XP element")
check(pickItem(xpDropdown, "fraction"), "XP format can be changed")
equal(P.brokerElements["Perch_XP"].text:GetText(), "500/1000", "the XP format applies immediately")
check(pickItem(xpDropdown, "percent"), "XP format restored")

P.selectedElement = "Perch_Bags"
P:RefreshOptions()
check(not goldDropdown.button:IsShown() and not xpDropdown.button:IsShown(),
  "no format settings show for the bags element")
P.selectedElement = goldKey
P:RefreshOptions()

-- Commands: add, rename, change the macro, remove.
section("command editing")

local function findButton(text)
  for _, frame in ipairs(Stub.frames) do
    if frame.kind == "Button" and frame.text == text and frame.scripts and frame.scripts.OnClick then
      return frame
    end
  end
end

local function commit(editbox, text)
  editbox.box:SetText(text)
  editbox.box.scripts.OnEnterPressed(editbox.box)
end

equal(P:NewCommandName(), "Command", "the first new command is called Command")
local addButton = findButton("Add command")
check(addButton ~= nil, "the elements page has an Add command button")
local commandsBefore = #PerchDB.commands
addButton.scripts.OnClick(addButton)
equal(#PerchDB.commands, commandsBefore + 1, "Add command creates a command")
check(P.commandCells["cmd:Command"] ~= nil, "the new command has a cell on the bar")
equal(P.selectedElement, "cmd:Command", "the new command is selected for editing")
equal(P:NewCommandName(), "Command 2", "the next new command gets a free name")
addButton.scripts.OnClick(addButton)
check(P.commandCells["cmd:Command 2"] ~= nil, "a second command gets its own name")
P.selectedElement = "cmd:Command"
P:RefreshOptions()

local boxes = P.elementCommandBoxes
check(boxes.name.box:IsShown() and boxes.macro.box:IsShown(), "command fields show for a command")
equal(boxes.name.box:GetText(), "Command", "the name box shows the command name")
check(boxes.macro.box:GetText():find("Perch", 1, true) ~= nil, "the macro box shows the macro")

P:SetElementOption("cmd:Command", "showIcon", false)
table.insert(PerchDB.order, 1, "cmd:Command")
commit(boxes.name, "Renamed")
check(P:FindCommand("Renamed") ~= nil and P:FindCommand("Command") == nil, "renaming changes the command name")
check(P.commandCells["cmd:Renamed"] ~= nil and P.commandCells["cmd:Command"] == nil, "the cell follows the new key")
equal(P.selectedElement, "cmd:Renamed", "the selection follows the rename")
equal(PerchDB.elements["cmd:Renamed"] and PerchDB.elements["cmd:Renamed"].showIcon, false,
  "element options move to the new key")
check(PerchDB.elements["cmd:Command"] == nil, "the old key's options are gone")
check(tContains(PerchDB.order, "cmd:Renamed") and not tContains(PerchDB.order, "cmd:Command"),
  "the bar order uses the new key")
equal(boxes.name.box:GetText(), "Renamed", "the name box shows the new name")

commit(boxes.name, "Reload")
check(P:FindCommand("Renamed") ~= nil, "a duplicate name is refused")
equal(boxes.name.box:GetText(), "Renamed", "the name box reverts after a refused rename")
commit(boxes.name, "   ")
check(P:FindCommand("Renamed") ~= nil, "an empty name is refused")
commit(boxes.name, string.rep("x", 30))
check(P:FindCommand("Renamed") ~= nil, "a too long name is refused")

commit(boxes.macro, "/say hi")
equal(P:FindCommand("Renamed").macrotext, "/say hi", "editing the macro saves it")
equal(P.commandCells["cmd:Renamed"]:GetAttribute("macrotext"), "/say hi", "the secure button runs the new macro")
equal(P.commandCells["cmd:Renamed"]:GetAttribute("macrotext1"), "/say hi", "left-click macro is updated too")
commit(boxes.macro, "")
equal(P:FindCommand("Renamed").macrotext, "/say hi", "an empty macro is refused")
equal(boxes.macro.box:GetText(), "/say hi", "the macro box reverts after a refused edit")

Stub.inCombat = true
commit(boxes.macro, "/say later")
equal(P:FindCommand("Renamed").macrotext, "/say later", "the macro is saved in combat")
equal(P.commandCells["cmd:Renamed"]:GetAttribute("macrotext"), "/say hi", "the secure button is untouched in combat")
check(P.commandRebuildPending, "the change is applied after combat")
Stub.inCombat = false
Stub.FireEvent("PLAYER_REGEN_ENABLED")
equal(P.commandCells["cmd:Renamed"]:GetAttribute("macrotext"), "/say later", "the new macro applies after combat")

P.selectedElement = goldKey
P:RefreshOptions()
check(not boxes.name.box:IsShown() and not boxes.macro.box:IsShown(), "command fields hide for other elements")
check(not findButton("Remove command"):IsShown(), "the Remove button hides for other elements")

P.selectedElement = "cmd:Renamed"
P:RefreshOptions()
local removeButton = findButton("Remove command")
check(removeButton:IsShown(), "the Remove button shows for a command")
removeButton.scripts.OnClick(removeButton)
check(P:FindCommand("Renamed") ~= nil, "the first click only asks for confirmation")
equal(removeButton.text, "Click again to remove", "the button asks to click again")
P.selectedElement = goldKey
P:RefreshOptions()
P.selectedElement = "cmd:Renamed"
P:RefreshOptions()
equal(removeButton.text, "Remove command", "changing the selection cancels the confirmation")
removeButton.scripts.OnClick(removeButton)
removeButton.scripts.OnClick(removeButton)
check(P:FindCommand("Renamed") == nil, "the second click removes the command")
check(P.commandCells["cmd:Renamed"] == nil, "the cell is gone")
check(not tContains(PerchDB.order, "cmd:Renamed"), "the order entry is gone")
equal(removeButton.text, "Remove command", "the button resets after removing")
SlashCmdList["PERCH"]("cmd del Command 2")
P.selectedElement = goldKey
P:RefreshOptions()

-- Minimap buttons as elements.
section("minimap buttons")

local calls = {}
local function fakeMinimapButton(name, options)
  options = options or {}
  local button = CreateFrame(options.kind or "Button", name, Minimap)
  button:SetSize(options.size or 32, options.size or 32)
  if options.border then
    local border = button:CreateTexture()
    border.name = name .. "Border"
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  end
  if options.icon then
    local icon = button:CreateTexture()
    icon:SetTexture(options.icon)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
  end
  if not options.inert then
    for _, script in ipairs({ "OnClick", "OnMouseDown", "OnMouseUp", "OnDoubleClick", "OnMouseWheel", "OnLeave" }) do
      if script ~= "OnMouseWheel" or options.wheel then
        button:SetScript(script, function(self, ...)
          calls[#calls + 1] = { name, script, self, ... }
          if options.broken and script == "OnClick" then
            error("minimap button exploded")
          end
        end)
      end
    end
    if not options.noTip then
      button:SetScript("OnEnter", function(self)
        calls[#calls + 1] = { name, "OnEnter", self }
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("minimap tooltip")
      end)
    end
  end
  return button
end

local fakeIcon = "Interface\\Icons\\INV_Misc_Gear_01"
local fakeButton = fakeMinimapButton("FakeAddonMinimapButton", { border = true, icon = fakeIcon, wheel = true })
fakeMinimapButton("PlainMinimapButton", { noTip = true })
fakeMinimapButton("BrokenMinimapButton", { icon = fakeIcon, broken = true })
fakeMinimapButton("MiniMapTracking", { icon = fakeIcon })
fakeMinimapButton("HugeMinimapThing", { icon = fakeIcon, size = 120 })
fakeMinimapButton("InertMinimapThing", { icon = fakeIcon, inert = true })
fakeMinimapButton("NotAButtonFrame", { kind = "Frame", icon = fakeIcon })
fakeMinimapButton("LibDBIcon10_Test_Scratch", { icon = fakeIcon })
fakeMinimapButton("LibDBIcon10_NoSuchObject", { icon = fakeIcon })

P:ScanMinimapButtons()
local mm = P.minimapCells
check(mm["mm:FakeAddonMinimapButton"] ~= nil, "a minimap button becomes an element")
check(mm["mm:PlainMinimapButton"] ~= nil, "a button without a picture is found too")
check(mm["mm:BrokenMinimapButton"] ~= nil, "a misbehaving button is found")
check(mm["mm:LibDBIcon10_NoSuchObject"] ~= nil, "a LibDBIcon button without an LDB object is found")
check(mm["mm:MiniMapTracking"] == nil, "Blizzard's minimap buttons are skipped")
check(mm["mm:HugeMinimapThing"] == nil, "oversized frames are skipped")
check(mm["mm:InertMinimapThing"] == nil, "buttons that do nothing are skipped")
check(mm["mm:NotAButtonFrame"] == nil, "plain frames are skipped")
check(mm["mm:LibDBIcon10_Test_Scratch"] == nil, "a LibDBIcon button whose LDB object is listed is skipped")

local cell = mm["mm:FakeAddonMinimapButton"]
local key = "mm:FakeAddonMinimapButton"
equal(P:ElementKind(key), "minimap button", "minimap elements have their own kind")
equal(P:ElementTitle(key), "FakeAddonMinimapButton", "the list shows the button name")
check(tContains(P:AllKeys(), key), "minimap elements are in the element list")
check(not P:IsEnabled(key), "minimap buttons are off until enabled")
check(not cell:IsShown(), "a disabled minimap button is hidden on the bar")
equal(cell.clicks and cell.clicks[1], "AnyUp", "minimap cells receive every mouse button")

P:SetElementEnabled(key, true)
check(cell:IsShown(), "an enabled minimap button shows")
equal(cell.icon.texture, fakeIcon, "it shows the button's own picture, not its border")
equal(cell.icon.texCoord[1], 0.1, "the picture keeps its crop")
equal(cell.text:GetText(), "", "by default only the icon shows")
check(cell.icon:IsShown(), "the icon is visible")

P:SetElementOption(key, "showLabel", true)
equal(cell.text:GetText(), "FakeAddon", "the label is the button name without the Minimap/Button suffix")
P:SetElementOption(key, "label", "Fake")
equal(cell.text:GetText(), "Fake", "a custom label replaces it")
P:SetElementOption(key, "showIcon", false)
check(not cell.icon:IsShown(), "the icon can be switched off")
equal(cell.text:GetText(), "Fake", "leaving only the label")
P:SetElementOption(key, "showLabel", false)
check(not cell:IsShown(), "with neither icon nor label there is nothing to show")
P:SetElementOption(key, "showIcon", true)
P:SetElementOption(key, "label", "")
check(cell:IsShown(), "the icon returns")

local plain = mm["mm:PlainMinimapButton"]
P:SetElementEnabled("mm:PlainMinimapButton", true)
equal(plain.text:GetText(), "Plain", "a button with no picture falls back to its name")
check(plain:IsShown(), "and is shown")

-- Mouse input reaches the original button, with the real button as self.
calls = {}
cell.scripts.OnMouseDown(cell, "RightButton")
cell.scripts.OnMouseUp(cell, "RightButton")
cell.scripts.OnClick(cell, "RightButton")
equal(#calls, 3, "mouse down, up and click are forwarded")
equal(calls[1][2], "OnMouseDown", "mouse down is forwarded first")
equal(calls[2][2], "OnMouseUp", "then mouse up")
equal(calls[3][2], "OnClick", "then the click")
equal(calls[3][4], "RightButton", "the mouse button is passed on")
equal(calls[3][3], fakeButton, "the original button is the handler's self")
calls = {}
cell.scripts.OnClick(cell, "MiddleButton")
equal(calls[1][4], "MiddleButton", "middle-click is forwarded")
cell.scripts.OnDoubleClick(cell, "LeftButton")
equal(calls[2][2], "OnDoubleClick", "double-click is forwarded")

check(cell.mouseWheelEnabled, "the wheel is captured when the button uses it")
check(not plain.mouseWheelEnabled, "the wheel is left alone otherwise")
calls = {}
cell.scripts.OnMouseWheel(cell, 1)
equal(calls[1] and calls[1][2], "OnMouseWheel", "the mouse wheel is forwarded")

local setOwnerBefore = GameTooltip.SetOwner
calls = {}
cell.scripts.OnEnter(cell)
equal(calls[1][2], "OnEnter", "hovering runs the button's own OnEnter")
equal(GameTooltip.owner, cell, "its tooltip is anchored to the bar cell, not the minimap")
equal(GameTooltip.ownerAnchor, "ANCHOR_BOTTOM", "below the bar")
equal(GameTooltip.lines[1], "minimap tooltip", "with the button's own tooltip text")
equal(GameTooltip.SetOwner, setOwnerBefore, "the tooltip redirect is removed again")
GameTooltip.lines = { "x" }
cell.scripts.OnLeave(cell)
equal(calls[#calls][2], "OnLeave", "leaving runs the button's OnLeave")

plain.scripts.OnEnter(plain)
equal(GameTooltip.text, "PlainMinimapButton", "a button without a tooltip gets its name as one")

-- A button that errors cannot take the bar down.
local broken = mm["mm:BrokenMinimapButton"]
P:SetElementEnabled("mm:BrokenMinimapButton", true)
local okClick = pcall(broken.scripts.OnClick, broken, "LeftButton")
check(okClick, "an erroring button does not raise through the bar")
check(P.brokerErrors["BrokenMinimapButton"] ~= nil, "its error is recorded for /perch doctor")

-- Icon styles: different ways to copy the picture from a button.
local layered = CreateFrame("Button", "LayeredMinimapButton", Minimap)
layered:SetSize(32, 32)
layered:SetScript("OnClick", function() end)
local plate = layered:CreateTexture()
plate:SetTexture("plate")
plate:SetSize(20, 20)
local glyph = layered:CreateTexture()
glyph:SetTexture("glyph")
glyph:SetSize(30, 30)
glyph:SetTexCoord(0.2, 0.8, 0.2, 0.8)
glyph:SetVertexColor(1, 0.5, 0.25, 1)
glyph:SetDesaturated(true)
local badge = layered:CreateTexture()
badge:SetTexture("badge")
badge:SetSize(10, 10)
P:ScanMinimapButtons()
local layeredKey = "mm:LayeredMinimapButton"
local layeredCell = P.minimapCells[layeredKey]
check(layeredCell ~= nil, "a button made of several textures is found")
P:SetElementEnabled(layeredKey, true)

local function iconTexture()
  return layeredCell.icon.texture
end
equal(iconTexture(), "plate", "automatic takes the first picture texture")
local styles = {
  { "first", "plate" },
  { "last", "badge" },
  { "largest", "glyph" },
}
for _, style in ipairs(styles) do
  P:SetElementOption(layeredKey, "iconSource", style[1])
  equal(iconTexture(), style[2], "icon source '" .. style[1] .. "' picks " .. style[2])
end

equal(layeredCell.icon.vertexColor[2], 0.5, "the source tint is copied")
equal(layeredCell.icon.desaturated, true, "the source's desaturation is copied")
equal(layeredCell.icon.texCoord[1], 0.2, "the original crop is kept")
P:SetElementOption(layeredKey, "iconCrop", "full")
equal(layeredCell.icon.texCoord[1], 0, "whole texture ignores the source crop")
equal(layeredCell.icon.texCoord[2], 1, "and shows it all")
P:SetElementOption(layeredKey, "iconCrop", "trimmed")
equal(layeredCell.icon.texCoord[1], 0.08, "trimmed edges use the standard icon trim")
P:SetElementOption(layeredKey, "iconCrop", "source")

P:SetElementOption(layeredKey, "iconSource", "normal")
equal(iconTexture(), "plate", "button texture falls back to automatic when there is none")

local normalButton = CreateFrame("Button", "NormalMinimapButton", Minimap)
normalButton:SetSize(32, 32)
normalButton:SetScript("OnClick", function() end)
normalButton:SetNormalTexture("normal")
local sideTexture = normalButton:CreateTexture()
sideTexture:SetTexture("side")
P:ScanMinimapButtons()
local normalKey = "mm:NormalMinimapButton"
P:SetElementEnabled(normalKey, true)
P:SetElementOption(normalKey, "iconSource", "normal")
equal(P.minimapCells[normalKey].icon.texture, "normal", "button texture uses the button's normal texture")
P:SetElementOption(normalKey, "iconSource", "last")
equal(P.minimapCells[normalKey].icon.texture, "side", "other styles use the regions instead")
P:SetElementEnabled(normalKey, false)

P:SetElementOption(layeredKey, "iconSource", "layers")
equal(#layeredCell.layerSpecs, 3, "all layers copies every texture")
equal(layeredCell.layers[1].texture, "plate", "the bottom layer is the first texture")
equal(layeredCell.layers[2].texture, "glyph", "then the next")
equal(layeredCell.layers[3].texture, "badge", "and the top layer last")
equal(layeredCell.layers[2].vertexColor[2], 0.5, "each layer keeps its own tint")
check(layeredCell.layers[1]:IsShown() and layeredCell.layers[3]:IsShown(), "the layers are visible")
check(not layeredCell.icon:IsShown(), "the cell's own icon only anchors the layers")
check(math.abs(layeredCell.layers[1].width - P.db.bar.iconSize * 20 / 32) < 0.01,
  "layers keep their size relative to the button")
P:SetElementOption(layeredKey, "showIcon", false)
check(not layeredCell.layers[1]:IsShown(), "hiding the icon hides every layer")
P:SetElementOption(layeredKey, "showIcon", true)
P:SetElementOption(layeredKey, "iconSource", "first")
check(not layeredCell.layers[1]:IsShown(), "leaving the layered style hides the layers")
equal(layeredCell.icon.texture, "plate", "and the single icon is back")
equal(PerchDB.elements[layeredKey].iconSource, "first", "the chosen style is saved")

-- The style controls on the elements page.
P.selectedElement = layeredKey
P:RefreshOptions()
local sourceDropdown, cropDropdown = findDropdown("Icon source"), findDropdown("Icon crop")
check(sourceDropdown ~= nil and sourceDropdown.button:IsShown(), "icon source shows for a minimap button")
check(cropDropdown ~= nil and cropDropdown.button:IsShown(), "icon crop shows for a minimap button")
equal(sourceDropdown.button.text, "First texture", "the dropdown shows the current style")
check(pickItem(sourceDropdown, "largest"), "a style can be picked")
equal(layeredCell.icon.texture, "glyph", "picking a style redraws the icon")
check(pickItem(cropDropdown, "full"), "a crop can be picked")
equal(layeredCell.icon.texCoord[1], 0, "picking a crop redraws the icon")
P.selectedElement = goldKey
P:RefreshOptions()
check(not sourceDropdown.button:IsShown(), "icon style controls hide for other elements")

-- Panels that place themselves from the button's rectangle follow the bar cell.
fakeButton.left = 7
cell.left = 500
equal(fakeButton:GetLeft(), 7, "the button reports its own position at rest")
cell.scripts.OnEnter(cell)
equal(fakeButton:GetLeft(), 500, "while hovering the bar cell the button reports the cell's position")
equal(fakeButton:GetCenter(), cell:GetCenter(), "including its centre")
cell.scripts.OnLeave(cell)
equal(fakeButton:GetLeft(), 7, "the button's own position is given back on leave")
cell.scripts.OnEnter(cell)
cell.scripts.OnHide(cell)
equal(fakeButton:GetLeft(), 7, "and when the cell hides while hovered")

-- Menus anchored straight to the button follow the bar cell instead.
local menuFrame = CreateFrame("Frame", "ForwardedMenu", UIParent)
menuFrame:Hide()
local menuButton = CreateFrame("Button", "MenuMinimapButton", Minimap)
menuButton:SetSize(32, 32)
local standing = CreateFrame("Frame", "StandingNeighbour", UIParent)
standing:SetPoint("TOP", menuButton, "BOTTOM", 0, 0)
local child = CreateFrame("Frame", "ButtonChild", menuButton)
child:SetPoint("CENTER", menuButton, "CENTER", 0, 0)
local freshMenus = {}
menuButton:SetScript("OnClick", function(self, mouse)
  if mouse == "RightButton" then
    -- Reuses one menu frame and creates another, as menu code does.
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 4, 4)
    menuFrame:Show()
    local fresh = CreateFrame("Frame", nil, UIParent)
    fresh:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    fresh:SetPoint("RIGHT", self, "RIGHT", 0, 0)
    freshMenus[#freshMenus + 1] = fresh
  end
end)
P:ScanMinimapButtons()
local menuCell = P.minimapCells["mm:MenuMinimapButton"]
check(menuCell ~= nil, "a button that opens menus is found")
P:SetElementEnabled("mm:MenuMinimapButton", true)

local function relativeOf(frame, index)
  local _, relativeTo = frame:GetPoint(index or 1)
  return relativeTo
end
equal(relativeOf(standing), menuButton, "before any click a neighbour is anchored to the button")
menuCell.scripts.OnClick(menuCell, "LeftButton")
check(not menuFrame:IsShown(), "a left-click opens no menu")
menuCell.scripts.OnClick(menuCell, "RightButton")
check(menuFrame:IsShown(), "the right-click opened the menu")
equal(relativeOf(menuFrame), menuCell, "the reused menu frame is anchored to the bar cell")
equal(menuFrame:GetPoint(), "TOPRIGHT", "its anchor point is kept")
equal(select(5, menuFrame:GetPoint()), 4, "and its offset")
equal(relativeOf(freshMenus[1], 1), menuCell, "a menu created by the click is anchored to the bar cell")
equal(relativeOf(freshMenus[1], 2), menuCell, "every anchor of a new frame moves, not only the first")
equal(relativeOf(standing), menuButton, "a frame that was already shown stays anchored to the button")
equal(relativeOf(child), menuButton, "the button's own children stay anchored to it")

menuFrame:Hide()
menuCell.scripts.OnClick(menuCell, "RightButton")
equal(relativeOf(menuFrame), menuCell, "reopening the menu keeps it on the bar")

-- A menu that animates and re-applies its recorded anchor (the real button) on
-- every step, as Polestar's does, must still end up on the bar.
local animating = 0
local animator = CreateFrame("Frame", "MenuAnimator", UIParent)
animator:SetScript("OnUpdate", function()
  if animating > 0 then
    animating = animating - 1
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPRIGHT", menuButton, "BOTTOMLEFT", 4, 4)
  end
end)
menuFrame:Hide()
menuButton:SetScript("OnClick", function(self, mouse)
  if mouse == "RightButton" then
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 4, 4)
    menuFrame:Show()
    animating = 3
  end
end)
menuCell.scripts.OnClick(menuCell, "RightButton")
equal(relativeOf(menuFrame), menuCell, "the menu is on the bar right after the click")
for _ = 1, 5 do
  Stub.Update()
end
equal(animating, 0, "the menu's animation ran to its end")
equal(relativeOf(menuFrame), menuCell, "the menu is still on the bar after its animation re-anchored it")
menuFrame:Hide()
Stub.Update()
menuFrame:ClearAllPoints()
menuFrame:SetPoint("TOPRIGHT", menuButton, "BOTTOMLEFT", 4, 4)
menuFrame:Show()
Stub.Update()
equal(relativeOf(menuFrame), menuButton, "a hidden menu is no longer watched")

-- Frames that refuse to be measured must not break the click or the move.
local restricted = CreateFrame("Frame", "RestrictedNeighbour", UIParent)
restricted.restricted = true
local forbidden = CreateFrame("Frame", "ForbiddenNeighbour", UIParent)
forbidden.forbiddenFrame = true
local secure = CreateFrame("Frame", "SecureNeighbour", UIParent)
secure.protectedFrame = true
secure:SetPoint("TOP", menuButton, "BOTTOM", 0, 0)
secure:Hide()
menuFrame:Hide()
local clicked = pcall(menuCell.scripts.OnClick, menuCell, "RightButton")
check(clicked, "a restricted frame does not raise through the click")
check(menuFrame:IsShown(), "the click still opened the menu")
equal(relativeOf(menuFrame), menuCell, "and the menu still moved to the bar")
secure:Show()
menuCell.scripts.OnClick(menuCell, "RightButton")
equal(relativeOf(secure), menuButton, "protected frames are never re-anchored")
secure:Hide()
restricted.restricted = false
forbidden.forbiddenFrame = false

Stub.inCombat = true
menuFrame:Hide()
menuCell.scripts.OnClick(menuCell, "RightButton")
equal(relativeOf(menuFrame), menuButton, "nothing is re-anchored in combat")
Stub.inCombat = false
P:SetElementEnabled("mm:MenuMinimapButton", false)

-- Late buttons, the Rescan button and the doctor report.
fakeMinimapButton("LateMinimapButton", { icon = fakeIcon })
check(mm["mm:LateMinimapButton"] == nil, "a button created after the scan is not seen yet")
local rescan = findButton("Rescan minimap")
check(rescan ~= nil, "the elements page has a Rescan minimap button")
rescan.scripts.OnClick(rescan)
check(mm["mm:LateMinimapButton"] ~= nil, "Rescan picks up late buttons")

P.selectedElement = key
P:RefreshOptions()
check(not findCheckbox("Value"):IsEnabled(), "minimap buttons have no value option")
check(findCheckbox("Icon"):IsEnabled() and findCheckbox("Label"):IsEnabled(), "icon and label options apply")

Stub.ResetMessages()
P:Doctor()
check(table.concat(Stub.messages, "\n"):find("minimap buttons: 8 found", 1, true) ~= nil,
  "doctor reports the minimap buttons it found")
P.selectedElement = goldKey
P:RefreshOptions()

-- Appearance: alignment, colours, border and end caps.
section("appearance")

local function bg() return PerchDB.bar.background end

-- Alignment.
equal(PerchDB.bar.alignment, "TOP", "the default alignment is top centre")
check(P:SetAlignment("TOPLEFT"), "the bar can align top left")
local p1, _, rp1, x1, y1 = P.bar:GetPoint()
equal(p1, "TOPLEFT", "top left anchors the top left corner")
equal(rp1, "TOPLEFT", "to the top left of the screen")
equal(x1, 8, "with a small margin")
local yBefore = y1
check(P:SetAlignment("TOPRIGHT"), "the bar can align top right")
local p2, _, _, x2, y2 = P.bar:GetPoint()
equal(p2, "TOPRIGHT", "top right anchors the top right corner")
equal(x2, -8, "with the margin on the other side")
equal(y2, yBefore, "the vertical offset is kept")
check(P:SetAlignment("TOP"), "the bar can align top centre")
local p3, _, _, x3 = P.bar:GetPoint()
equal(p3, "TOP", "top centre anchors the top")
equal(x3, 0, "without a margin")
check(not P:SetAlignment("sideways"), "an unknown alignment is refused")
P:SavePosition()
equal(PerchDB.bar.alignment, "custom", "dragging the bar makes the alignment custom")

local alignment = findDropdown("Alignment")
check(alignment ~= nil, "appearance has an alignment selector")
equal(alignment.button.text, "Custom (dragged)", "the selector shows a dragged bar as custom")
check(pickItem(alignment, "TOPRIGHT"), "a preset can be picked")
equal(PerchDB.bar.point, "TOPRIGHT", "picking a preset moves the bar")
equal(alignment.button.text, "Top right", "and the selector shows it")
check(pickItem(alignment, "custom"), "custom can be clicked")
equal(PerchDB.bar.alignment, "TOPRIGHT", "but it changes nothing")
local resetPosition = findButton("Reset position")
resetPosition.scripts.OnClick(resetPosition)
equal(PerchDB.bar.alignment, "TOP", "Reset position goes back to top centre")

-- Bars saved before alignment existed.
PerchDB.bar.alignment = nil
PerchDB.bar.x = -16
P:EnsureDB()
equal(PerchDB.bar.alignment, "custom", "an old bar that was dragged becomes custom")
PerchDB.bar.alignment = nil
PerchDB.bar.x = 0
P:EnsureDB()
equal(PerchDB.bar.alignment, "TOP", "an old bar at the default spot is top centre")

-- Pixel offsets: boxes filled with the bar's position, typed values move it.
P:SetAlignment("TOPRIGHT")
local offsetX, offsetY = P.offsetBoxes.x, P.offsetBoxes.y
check(offsetX ~= nil and offsetY ~= nil, "appearance has X and Y offset boxes")
equal(offsetX.box:GetText(), "-8", "the X box shows the current offset")
equal(offsetY.box:GetText(), tostring(math.floor(-PerchDB.bar.y + 0.5)), "the Y box shows the current offset (counted downwards)")
offsetX.box:SetText("25")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(PerchDB.bar.x, 25, "typing an X offset moves the bar")
equal(select(4, P.bar:GetPoint()), 25, "straight away")
equal(PerchDB.bar.alignment, "custom", "an offset off the preset margin makes the alignment custom")
offsetX.box:SetText("-30")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(PerchDB.bar.x, -30, "offsets can be negative")
offsetX.box:SetText("12ab-3")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(offsetX.box:GetText(), "123", "only digits are kept (a minus only counts at the start)")
offsetX.box:SetText("-")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(PerchDB.bar.x, 123, "a lone minus is ignored while typing")
offsetX.box.scripts.OnEditFocusLost(offsetX.box)
equal(offsetX.box:GetText(), "123", "and the box reverts when focus is lost")
offsetX.box:SetText("99999")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(PerchDB.bar.x, 5000, "huge offsets are clamped")
offsetX.box.scripts.OnArrowPressed(offsetX.box, "DOWN")
equal(PerchDB.bar.x, 4999, "the arrow keys nudge by one pixel")
offsetX.box.scripts.OnArrowPressed(offsetX.box, "UP")
equal(PerchDB.bar.x, 5000, "in both directions")

P:SetAlignment("TOP")
offsetY.box:SetText("-40")
offsetY.box.scripts.OnTextChanged(offsetY.box, true)
equal(PerchDB.bar.y, 40, "a negative Y moves the bar up")
equal(select(5, P.bar:GetPoint()), 40, "the whole bar, in the game's upward offset")
offsetY.box:SetText("30")
offsetY.box.scripts.OnTextChanged(offsetY.box, true)
equal(PerchDB.bar.y, -30, "a positive Y moves it down")
equal(PerchDB.bar.alignment, "TOP", "the vertical offset keeps the alignment")
offsetY.box.scripts.OnArrowPressed(offsetY.box, "UP")
equal(PerchDB.bar.y, -31, "Up raises the shown number, which moves the bar down")

-- The bar can go off the screen, and everything follows it.
check(P.bar.clamped == false, "the bar is not clamped to the screen")
offsetY.box:SetText("-200")
offsetY.box.scripts.OnTextChanged(offsetY.box, true)
equal(PerchDB.bar.y, 200, "a large negative Y puts the bar above the screen edge")
equal(select(5, P.bar:GetPoint()), 200, "and the bar really is there")
check(P.secureAnchor ~= nil and P.secureAnchor.clamped ~= true, "the command buttons' anchor is not clamped either")
equal(select(5, P.secureAnchor:GetPoint()), 200, "so the command buttons are off the screen with it, not left behind")
offsetY.box:SetText("8")
offsetY.box.scripts.OnTextChanged(offsetY.box, true)
offsetX.box:SetText("0")
offsetX.box.scripts.OnTextChanged(offsetX.box, true)
equal(PerchDB.bar.alignment, "TOP", "an offset equal to the preset margin keeps it")

-- Dragging updates the boxes.
P.bar:ClearAllPoints()
P.bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -12)
P:SavePosition()
equal(offsetX.box:GetText(), "40", "dragging updates the X box")
equal(offsetY.box:GetText(), "12", "and the Y box (counted downwards)")
P:SetAlignment("TOP")
PerchDB.bar.y = -8
P:RestorePosition()
P:RefreshOptions()

-- Texture previews and showing a texture on the bar.
local textureDropdown = findDropdown("Texture")
check(textureDropdown ~= nil, "appearance has a texture selector")
check(textureDropdown.button.preview:IsShown(), "the closed selector shows a preview of the current texture")
equal(textureDropdown.button.preview.texture, PerchDB.bar.background.texture, "of the texture in use")
textureDropdown.button.scripts.OnClick(textureDropdown.button)
local firstRow = P.UI.GetPicker().rows[1]
check(firstRow.preview:IsShown() and firstRow.previewBack:IsShown(), "texture rows show a preview")
equal(firstRow.preview.texture, firstRow.item.value, "of their own texture")
P.UI.HidePicker()
local fontDropdownCheck = findDropdown("Font")
fontDropdownCheck.button.scripts.OnClick(fontDropdownCheck.button)
check(not P.UI.GetPicker().rows[1].preview:IsShown(), "rows without a texture show no preview")
P.UI.HidePicker()

local texturedPath
for _, entry in ipairs(P:MediaList("background")) do
  if type(entry.path) == "string" and not entry.path:lower():find("chatframebackground", 1, true)
    and not entry.path:lower():find("white8x8", 1, true) then
    texturedPath = entry.path
    break
  end
end
check(texturedPath ~= nil, "there is a textured background to pick")
local defaultTexture = PerchDB.bar.background.texture
check(pickItem(textureDropdown, texturedPath), "a texture can be picked")
equal(P.bar.bg.texture, texturedPath, "the bar background uses the picked texture")
equal(P.bar.bg.vertexColor[1], 1, "shown in its own colours, not tinted black by the background colour")
equal(P.bar.bg.vertexColor[3], 1, "(blue too)")
equal(P.bar.bg.vertexColor[4], 0.5, "while the alpha still applies")
PerchDB.bar.background.tint = true
P:ApplyAll()
equal(P.bar.bg.vertexColor[1], PerchDB.bar.background.color[1], "with the tint option the background colour tints it")
local tintBox = findCheckbox("Tint a textured background")
check(tintBox ~= nil, "appearance has the tint option")
tintBox:SetChecked(false)
tintBox.scripts.OnClick(tintBox)
equal(PerchDB.bar.background.tint, false, "the tint option can be switched off")
equal(P.bar.bg.vertexColor[1], 1, "and the texture is untinted again")
check(pickItem(textureDropdown, defaultTexture), "the solid texture can be picked again")
PerchDB.bar.background.color = { 0.2, 0.4, 0.6, 0.5 }
P:ApplyAll()
equal(P.bar.bg.vertexColor[2], 0.4, "a solid background is always tinted with the colour")
PerchDB.bar.background.color = { 0, 0, 0, 0.5 }
P:ApplyAll()

-- Border.
PerchDB.bar.border.enabled = true
PerchDB.bar.border.size = 2
PerchDB.bar.border.color = { 1, 0, 0, 0.5 }
P:ApplyAll()
local decor = P.decor
check(decor.top:IsShown() and decor.bottom:IsShown(), "the border lines show")
equal(decor.top.height, 2, "the border has the chosen thickness")
equal(decor.top.colorTexture[1], 1, "the border has the chosen colour")
equal(decor.top.colorTexture[4], 0.5, "and alpha")
check(decor.left:IsShown() and decor.right:IsShown(), "a flat end has its side line")
local bgPoint = P.bar.bg.points[1]
equal(bgPoint[4], 2, "the background is inset by the border on the left")
equal(bgPoint[5], -2, "and the top")
PerchDB.bar.border.enabled = false
P:ApplyAll()
check(not decor.top:IsShown() and not decor.left:IsShown(), "no border lines when it is off")
equal(P.bar.bg.points[1][4], 0, "and the background fills the bar")

local function near(actual, expected, message)
  -- 0.005: below that the antialiasing pixel is not drawn (less than one alpha step).
  check(math.abs(actual - expected) < 0.005, message .. " (expected " .. expected .. ", got " .. actual .. ")")
end
do
-- End caps.
local function rowsOf(side)
  return P.decor.rows[side]
end

-- How much of a row the cap covers, in pixels: the fill and border pieces plus
-- the antialiasing pixel at the edge, counted by its coverage.
local function coverage(side, row)
  local rows = rowsOf(side)
  local fill, border, edge = rows.fills[row], rows.borders[row], rows.edges[row]
  local total = 0
  if fill and fill:IsShown() then
    total = total + fill.width
  end
  if border and border:IsShown() then
    total = total + border.width
  end
  if edge and edge:IsShown() then
    total = total + edge.coverage
  end
  return total
end
local widthOfRow = coverage
local function coverages(side)
  local list = {}
  for row = 1, 22 do
    list[row] = coverage(side, row)
  end
  return list
end
local function setCaps(left, right, width)
  PerchDB.bar.caps.left = left
  PerchDB.bar.caps.right = right
  PerchDB.bar.caps.width = width
  P:ApplyAll()
end

local BAR_HEIGHT = 22
local SHAPES = {
  triangle = function(t)
    return 1 - t
  end,
  curved1 = function(t)
    local u = 2 * t - 1
    return math.sqrt(1 - u * u)
  end,
  curved2 = function(t)
    return math.sqrt(1 - t * t)
  end,
  -- Plain (not exaggerated) sine half-wave, to compare Curved 3 with.
  sine = function(t)
    return 1 - math.acos(1 - 2 * t) / math.pi
  end,
}
local function expected(shape, width, row)
  return width * SHAPES[shape]((row - 0.5) / BAR_HEIGHT)
end

equal(P.defaults.bar.caps.width, P.defaults.bar.height, "the default cap width is the default bar height")

-- Triangle: a right triangle, widest at the top (the screen edge) and meeting the
-- bar's bottom corner; a 45 degree slope when the width equals the height.
setCaps("triangle", "triangle", 22)
for row = 1, 22 do
  near(coverage("left", row), 22.5 - row, "triangle row " .. row .. " covers its exact width")
  near(coverage("right", row), 22.5 - row, "the right triangle mirrors it (row " .. row .. ")")
end
for row = 2, 22 do
  near(coverage("left", row - 1) - coverage("left", row), 1, "one pixel per row, a 45 degree slope (row " .. row .. ")")
end
setCaps("triangle", "triangle", 30)
near(coverage("left", 1), expected("triangle", 30, 1), "the cap width sets the triangle's width")
near(coverage("left", 22), expected("triangle", 30, 22), "which ends on the bar's bottom corner")
for row = 2, 22 do
  near(coverage("left", row - 1) - coverage("left", row), 30 / 22, "the slope is perfectly even, with no stair steps (row " .. row .. ")")
end
setCaps("triangle", "triangle", 11)
near(coverage("left", 1), expected("triangle", 11, 1), "a narrower triangle is steeper")

-- Antialiasing: the fraction of the last pixel is drawn as a partly transparent
-- pixel, in the background colour (no border), at the very edge of the row.
setCaps("triangle", "none", 22)
local row1 = rowsOf("left")
equal(row1.fills[1].width, 21, "a row 21.5 pixels wide has 21 full pixels")
check(row1.edges[1]:IsShown(), "and one antialiasing pixel")
near(row1.edges[1].coverage, 0.5, "covering half of it")
near(row1.edges[1].colorTexture[4], 0.25, "so it has half the background's alpha")
equal(row1.edges[1].colorTexture[1], bg().color[1], "in the background colour")
equal(row1.edges[1].width, 1, "one pixel wide")
equal(row1.edges[1].points[1][4], -21, "right at the end of the full pixels")
setCaps("triangle", "none", 30)
check(rowsOf("left").edges[1].coverage > 0.02 and rowsOf("left").edges[1].coverage < 1, "a fractional width gets a fractional pixel")
near(rowsOf("left").edges[1].colorTexture[4], 0.5 * rowsOf("left").edges[1].coverage, "with alpha in proportion")

-- Curved 1: a semi-ellipse bulging out of the bar.
setCaps("curved1", "none", 10)
for row = 1, 22 do
  near(coverage("left", row), expected("curved1", 10, row), "curved 1 follows an ellipse (row " .. row .. ")")
  near(coverage("left", row), coverage("left", 23 - row), "and is symmetric top to bottom (row " .. row .. ")")
end

-- Curved 2: a quarter circle centred on the bar's top corner (an ellipse when the
-- width differs from the height).
setCaps("curved2", "none", 22)
for row = 1, 22 do
  near(coverage("left", row), expected("curved2", 22, row), "curved 2 follows a circle (row " .. row .. ")")
end
for row = 2, 22 do
  check(coverage("left", row) <= coverage("left", row - 1) + 1e-9, "curved 2 never widens going down (row " .. row .. ")")
end
local circleCurve = coverages("left")
check(circleCurve[17] - circleCurve[22] > circleCurve[1] - circleCurve[6], "flat near the top, steep near the bottom, like a circle")
setCaps("curved2", "none", 12)
near(coverage("left", 1), expected("curved2", 12, 1), "the cap width sets curved 2's width too")
near(coverage("left", 11), expected("curved2", 12, 11), "scaling the circle into an ellipse")

-- Curved 3: an exaggerated sine half-wave, horizontal at both ends and steep in
-- the middle.
setCaps("curved3", "none", 40)
local curved3 = coverages("left")
for row = 1, 22 do
  near(curved3[row], 40 * P.CurvedThree((row - 0.5) / 22), "curved 3 follows its profile (row " .. row .. ")")
  near(curved3[row] + curved3[23 - row], 40, "and is point-symmetric like a sine wave (row " .. row .. ")")
end
for row = 2, 22 do
  check(curved3[row] <= curved3[row - 1] + 1e-9, "curved 3 never widens going down (row " .. row .. ")")
end
for _, t in ipairs({ 0.05, 0.2, 0.5, 0.8, 0.95 }) do
  near(P.CurvedThreeForward(1 - P.CurvedThree(t)), t, "the curve inverts exactly (t = " .. t .. ")")
end
local sineEnds = 40 * (SHAPES.sine(0.5 / 22) - SHAPES.sine(1.5 / 22))
local sineMiddle = 40 * (SHAPES.sine(9.5 / 22) - SHAPES.sine(12.5 / 22))
check(curved3[1] - curved3[2] > sineEnds, "the ends are flatter than a plain sine (more width change per row)")
check(curved3[10] - curved3[13] < sineMiddle, "and the middle is steeper than a plain sine")
check(curved3[1] > 30 and curved3[22] < 10, "while it still starts out wide at the top and ends narrow at the bottom corner")
setCaps("curved3", "none", 20)
check(coverage("left", 1) >= 16, "the cap width setting widens curved 3")

-- Old style names and the old default width carry over.
PerchDB.bar.caps.left = "curved"
PerchDB.bar.caps.right = "slant"
P:EnsureDB()
equal(PerchDB.bar.caps.left, "curved1", "the old 'curved' is Curved 1")
equal(PerchDB.bar.caps.right, "triangle", "the old slant became the triangle")
PerchDB.bar.caps.width = 10
PerchDB.bar.caps.widthMigrated = nil
P:EnsureDB()
equal(PerchDB.bar.caps.width, 22, "the old default width of 10 moves to the bar height")
PerchDB.bar.caps.width = 14
P:EnsureDB()
equal(PerchDB.bar.caps.width, 14, "a width chosen later is never changed")

setCaps("triangle", "curved3", 22)
local leftFill = rowsOf("left").fills[11]
local leftPoint = leftFill.points[1]
equal(leftPoint[1], "TOPRIGHT", "a left cap grows out of the bar's left edge")
equal(leftPoint[3], "TOPLEFT", "anchored to the bar's top left corner")
equal(leftPoint[5], -10, "one row per pixel of height")
local rightPoint = rowsOf("right").fills[11].points[1]
equal(rightPoint[1], "TOPLEFT", "a right cap grows out of the right edge")
equal(rightPoint[3], "TOPRIGHT", "anchored to the top right corner")
equal(leftFill.colorTexture[4], 0.5, "cap rows use the background's alpha")
equal(leftFill.colorTexture[1], bg().color[1], "and its colour")
check(not P.decor.left:IsShown() and not P.decor.right:IsShown(), "a capped end has no straight border line")

-- A border on a cap follows its edge without overlapping the fill.
PerchDB.bar.border.enabled = true
PerchDB.bar.border.size = 1
PerchDB.bar.border.color = { 0, 1, 0, 1 }
setCaps("triangle", "none", 22)
for row = 1, 22 do
  near(coverage("left", row), 22.5 - row, "the capped border keeps the triangle's shape (row " .. row .. ")")
end
local rows = rowsOf("left")
local capBorder = rows.borders[11]
check(capBorder:IsShown() and capBorder.width >= 1, "the cap has a border part")
equal(capBorder.colorTexture[2], 1, "in the border colour")
equal(rows.fills[11].colorTexture[2], 0, "next to a fill in the background colour")
equal(capBorder.points[1][4], -rows.fills[11].width, "the border part starts where the fill ends")
equal(rows.fills[11].points[1][4], 0, "and the fill starts at the bar")
equal(rows.edges[11].colorTexture[2], 1, "the antialiasing pixel is in the border colour")
near(rows.edges[11].colorTexture[4], 0.5, "with the border's alpha scaled by the coverage")

-- The cap's top and bottom edges carry the border all the way across; only the
-- side against the bar has none. Caps are as tall as the bar.
check(rows.borders[1]:IsShown() and rows.borders[1].width == 21, "the cap's top edge is border across its whole width")
check(not rows.fills[1]:IsShown(), "so the first row has no fill")
check(rows.edges[22]:IsShown() and rows.edges[22].colorTexture[2] == 1, "and the bottom row is border too")
check(rows.borders[11].width < rows.borders[1].width, "while the middle rows only have the slanted edge")
equal(rows.fills[11].points[1][4], 0, "nothing is drawn on the side touching the bar")
local shownRows = 0
for row = 1, 40 do
  local fill, border, edge = rows.fills[row], rows.borders[row], rows.edges[row]
  if (fill and fill:IsShown()) or (border and border:IsShown()) or (edge and edge:IsShown()) then
    shownRows = shownRows + 1
    check(row <= P.db.bar.height, "no cap row is below the bar")
  end
end
equal(shownRows, P.db.bar.height, "the cap is exactly as tall as the bar")

PerchDB.bar.border.size = 2
setCaps("curved1", "none", 10)
rows = rowsOf("left")
check(rows.borders[1].width == math.floor(expected("curved1", 10, 1) + 1e-9)
  and rows.borders[2].width == math.floor(expected("curved1", 10, 2) + 1e-9),
  "a thicker border covers as many top rows as it is thick")
check(rows.borders[21].width == math.floor(expected("curved1", 10, 21) + 1e-9)
  and rows.borders[22].width == math.floor(expected("curved1", 10, 22) + 1e-9),
  "and as many bottom rows")
PerchDB.bar.border.size = 1
PerchDB.bar.border.enabled = false

-- A textured background cannot be matched by the caps.
PerchDB.bar.caps.left = "triangle"
PerchDB.bar.caps.right = "triangle"
P:ApplyAll()
check(P:IsSolidBackground(), "the default background is solid")
check(widthOfRow("left", 11) > 0, "caps show on a solid background")
local leftEnd = findDropdown("Left end")
check(leftEnd.button:IsEnabled(), "the cap selector is enabled on a solid background")
bg().texture = "Interface\\Buttons\\SomeTexture"
P:ApplyAll()
P:RefreshOptions()
check(not P:IsSolidBackground(), "a textured background is not solid")
equal(widthOfRow("left", 11), 0, "a textured background switches the caps off")
check(not leftEnd.button:IsEnabled(), "and disables the cap selector")
equal(PerchDB.bar.caps.left, "triangle", "while keeping the choice")
bg().texture = "Interface\\ChatFrame\\ChatFrameBackground"
P:ApplyAll()
P:RefreshOptions()
check(widthOfRow("left", 11) > 0, "the caps come back with a solid background")
check(leftEnd.button:IsEnabled(), "and the selector is enabled again")
bg().enabled = false
P:ApplyAll()
equal(widthOfRow("left", 11), 0, "no background means no caps")
bg().enabled = true
PerchDB.bar.caps.width = 20
P:ApplyAll()
local wide = 0
for row = 1, 22 do
  wide = math.max(wide, widthOfRow("left", row))
end
check(wide >= 19, "the cap width setting widens the cap")
PerchDB.bar.caps.left, PerchDB.bar.caps.right, PerchDB.bar.caps.width = "none", "none", 10
P:ApplyAll()
equal(widthOfRow("left", 11), 0, "flat ends draw no cap")
check(P.decor.rows.left.fills[11] == nil or not P.decor.rows.left.fills[11]:IsShown(), "and no row textures show")

-- Colours: hex input and the game's picker.
local colorWidgets = {}
for _, widget in ipairs(P.optionWidgets) do
  if widget.hex and widget.swatch then
    colorWidgets[#colorWidgets + 1] = widget
  end
end
check(#colorWidgets >= 2, "appearance has background and border colour pickers")
local bgColor = colorWidgets[1]
equal(bgColor.hex.box:GetText(), "000000", "the hex box shows the current colour")
bgColor.hex.box:SetText("ff8000")
bgColor.hex.box.scripts.OnEnterPressed(bgColor.hex.box)
equal(bg().color[1], 1, "a typed hex colour sets red")
check(math.abs(bg().color[2] - 128 / 255) < 0.001, "green")
equal(bg().color[3], 0, "and blue")
equal(bg().color[4], 0.5, "while the alpha is kept")
equal(bgColor.hex.box:GetText(), "ff8000", "the box shows the new colour")
check(math.abs(P.bar.bg.vertexColor[2] - 128 / 255) < 0.001, "the bar background uses it straight away")
bgColor.hex.box:SetText("zz")
bgColor.hex.box.scripts.OnTextChanged(bgColor.hex.box, true)
equal(bgColor.hex.box:GetText(), "", "non-hex characters are stripped")
bgColor.hex.box:SetText("12")
bgColor.hex.box.scripts.OnEnterPressed(bgColor.hex.box)
equal(bg().color[1], 1, "an incomplete hex value is ignored")
equal(bgColor.hex.box:GetText(), "ff8000", "and the box reverts")

bgColor.swatch.scripts.OnClick(bgColor.swatch)
check(Stub.colorPicker ~= nil, "the swatch opens the game's colour picker")
equal(Stub.colorPicker.r, 1, "starting from the current colour")
Stub.colorPicker.swatchFunc()
equal(bg().color[2], 1, "picking a colour applies it")
equal(bg().color[1], 0, "(the picker's green)")
Stub.colorPicker.cancelFunc({ r = 0, g = 0, b = 0 })
equal(bg().color[2], 0, "cancelling restores the previous colour")
equal(bg().color[4], 0.5, "the alpha is untouched throughout")

local borderColor = colorWidgets[2]
borderColor.hex.box:SetText("00ff00")
borderColor.hex.box.scripts.OnEnterPressed(borderColor.hex.box)
equal(PerchDB.bar.border.color[2], 1, "the border colour has its own picker")
PerchDB.bar.border.color = { 0, 0, 0, 1 }
P:ApplyAll()
P:RefreshOptions()

check(Stub.subcategories[2].frame.scroll ~= nil, "the appearance page scrolls")
end

-- Vertical alignment and the "centre around" layout.
section("alignment and centred layout")
do

local function shownEntries()
  local list = {}
  for _, key in ipairs(P:OrderedKeys()) do
    local cell = P:GetCell(key)
    if cell and (cell.isCommand or cell:IsShown()) then
      list[#list + 1] = { key = key, cell = cell }
    end
  end
  return list
end
local function xOf(cell)
  return cell.points[1][4]
end

P:Layout()
local normalWidth = P.bar:GetWidth()
local entries = shownEntries()
check(#entries >= 5, "there are several elements to lay out")

-- Every icon and label sits on the bar's centre line.
for _, entry in ipairs(entries) do
  local cell = entry.cell
  local point = cell.points[1]
  equal(point[1], "LEFT", entry.key .. " is anchored by the middle of its left edge")
  equal(point[5], 0, entry.key .. " has no vertical offset")
  equal(cell.text.justifyV, "MIDDLE", entry.key .. "'s label is centred vertically")
  equal(cell.text.height, PerchDB.bar.height, entry.key .. "'s label is as tall as the bar")
  equal(cell.text.points[1][1], "LEFT", entry.key .. "'s label is anchored by its middle")
  equal(cell.text.points[1][5], 0, entry.key .. "'s label has no vertical offset")
  equal(cell.height, PerchDB.bar.height, entry.key .. " is as tall as the bar")
  if cell.iconVisible then
    equal(cell.icon.points[1][1], "LEFT", entry.key .. "'s icon is anchored by its middle")
    equal(cell.icon.points[1][5], 0, entry.key .. "'s icon has no vertical offset")
  end
end

local padding, spacing = PerchDB.bar.padding, PerchDB.bar.spacing
local function natural(list, first, last)
  local sum, count = 0, 0
  for index = first, last do
    sum = sum + list[index].cell.width
    count = count + 1
  end
  return sum + count * spacing, sum, count
end

-- Centred around the third element.
local middle = 3
PerchDB.bar.centerMode = true
PerchDB.bar.centerKey = entries[middle].key
P:Layout()
local width = P.bar:GetWidth()
local centered = entries[middle].cell
near(xOf(centered) + centered.width / 2, width / 2, "the chosen element is centred on the bar")

local leftNatural, leftSum = natural(entries, 1, middle - 1)
local rightNatural, rightSum, rightCount = natural(entries, middle + 1, #entries)
local span = math.max(leftNatural, rightNatural)
near(width, padding * 2 + span * 2 + centered.width, "the bar is wide enough for the larger side on both sides")
near(xOf(centered) - padding, span, "the left side has the larger side's width")
near(width - padding - (xOf(centered) + centered.width), span, "and so does the right side")
near(xOf(entries[1].cell), padding, "the first element is flush with the bar's left padding")
local last = entries[#entries].cell
near(xOf(last) + last.width, width - padding, "the last element is flush with the right padding")

local function gapsOf(first, last)
  local gaps = {}
  for index = first, last - 1 do
    gaps[#gaps + 1] = xOf(entries[index + 1].cell) - (xOf(entries[index].cell) + entries[index].cell.width)
  end
  return gaps
end
local leftGaps = gapsOf(1, middle)
for _, gap in ipairs(leftGaps) do
  near(gap, leftGaps[1], "elements are spread with equal gaps on the left")
end
local rightGaps = gapsOf(middle, #entries)
for _, gap in ipairs(rightGaps) do
  near(gap, rightGaps[1], "elements are spread with equal gaps on the right")
end
near((span - leftSum) / (middle - 1), leftGaps[1], "the left gap fills the available space")
near((span - rightSum) / rightCount, rightGaps[1], "the right gap fills the available space")
check(leftGaps[1] >= spacing - 1e-6 and rightGaps[1] >= spacing - 1e-6, "no side is tighter than the normal spacing")
check(math.abs(leftGaps[1] - spacing) < 1e-6 or math.abs(rightGaps[1] - spacing) < 1e-6,
  "the larger side keeps the normal spacing")

-- The first element: nothing on its left, everything on its right.
PerchDB.bar.centerKey = entries[1].key
P:Layout()
local firstNatural = natural(entries, 2, #entries)
near(P.bar:GetWidth(), padding * 2 + firstNatural * 2 + entries[1].cell.width, "an empty side still takes the larger side's width")
near(xOf(entries[1].cell) + entries[1].cell.width / 2, P.bar:GetWidth() / 2, "the first element is centred too")

-- The last element.
PerchDB.bar.centerKey = entries[#entries].key
P:Layout()
near(xOf(entries[#entries].cell) + entries[#entries].cell.width / 2, P.bar:GetWidth() / 2, "the last element can be centred")

-- Falling back to the normal layout.
PerchDB.bar.centerKey = "no such element"
P:Layout()
near(P.bar:GetWidth(), normalWidth, "an unknown element means the normal layout")
PerchDB.bar.centerKey = ""
P:Layout()
near(P.bar:GetWidth(), normalWidth, "and so does none")
PerchDB.bar.centerKey = entries[middle].key
PerchDB.bar.centerMode = false
P:Layout()
near(P.bar:GetWidth(), normalWidth, "switched off, the normal layout is back")

-- The Appearance controls.
local centerBox = findCheckbox("Center around an element")
local centerDropdown = findDropdown("Centered element")
check(centerBox ~= nil and centerDropdown ~= nil, "appearance has the centre around option and its selector")
check(not centerDropdown.button:IsEnabled(), "the selector is greyed out while the option is off")
PerchDB.bar.centerKey = ""
centerBox:SetChecked(true)
centerBox.scripts.OnClick(centerBox)
check(PerchDB.bar.centerMode, "the checkbox switches the mode on")
check(centerDropdown.button:IsEnabled(), "which enables the selector")
equal(PerchDB.bar.centerKey, entries[math.ceil(#entries / 2)].key, "starting from the middle element")
near(xOf(entries[math.ceil(#entries / 2)].cell) + entries[math.ceil(#entries / 2)].cell.width / 2,
  P.bar:GetWidth() / 2, "which is centred straight away")

centerDropdown.button.scripts.OnClick(centerDropdown.button)
local listed = 0
for _, row in ipairs(P.UI.GetPicker().rows) do
  if row:IsShown() then
    listed = listed + 1
  end
end
equal(listed, #shownEntries(), "the selector lists every element that is shown")
P.UI.HidePicker()
check(pickItem(centerDropdown, entries[2].key), "another element can be picked")
equal(PerchDB.bar.centerKey, entries[2].key, "the choice is stored")
near(xOf(entries[2].cell) + entries[2].cell.width / 2, P.bar:GetWidth() / 2, "and that element is centred")
equal(centerDropdown.button.text, P:ElementTitle(entries[2].key), "the selector shows its name")

-- A hidden element is not offered.
local hiddenKey = entries[#entries].key
P:SetElementEnabled(hiddenKey, false)
centerDropdown.button.scripts.OnClick(centerDropdown.button)
local offered = false
for _, row in ipairs(P.UI.GetPicker().rows) do
  if row:IsShown() and row.item.value == hiddenKey then
    offered = true
  end
end
check(not offered, "an element that is hidden is not offered")
P.UI.HidePicker()
P:SetElementEnabled(hiddenKey, true)

centerBox:SetChecked(false)
centerBox.scripts.OnClick(centerBox)
check(not centerDropdown.button:IsEnabled(), "switching it off greys the selector out again")
near(P.bar:GetWidth(), normalWidth, "and the bar goes back to the normal layout")
PerchDB.bar.centerKey = ""
P:Layout()
end

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
