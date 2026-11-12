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
scratch.OnClick = function(_, button)
  clicks[#clicks + 1] = button
end
scratchCell:GetScript("OnClick")(scratchCell, "RightButton")
equal(clicks[1], "RightButton", "click is forwarded with the button argument")

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

local ordered = P:OrderedKeys()
equal(ordered[1], "Perch_Clock", "built-ins keep their default order")
check(tContains(ordered, "cmd:Reload"), "commands participate in the order")

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
Stub.ResetMessages()
SlashCmdList["PERCH"]("cmd add Combat /say hi")
check(P.commandRebuildPending == true, "command rebuild defers while in combat")
Stub.inCombat = false
Stub.FireEvent("PLAYER_REGEN_ENABLED")
check(P.commandCells["cmd:Combat"] ~= nil, "deferred rebuild happens after combat")

check(P.optionsFrame ~= nil, "standalone options frame exists")
check(Stub.optionsCategory ~= nil, "options registered with the Settings API")
SlashCmdList["PERCH"]("config")
equal(Stub.openedCategory, "Perch", "config opens the Settings category")

check(not P.optionsFrame:IsShown(), "standalone frame stays closed while Settings is used")
SlashCmdList["PERCH"]("frame")
check(P.optionsFrame:IsShown(), "frame command opens the standalone options frame")
SlashCmdList["PERCH"]("frame")
check(not P.optionsFrame:IsShown(), "frame command toggles the standalone options frame")

--------------------------------------------------------------------------
-- Barrier
--------------------------------------------------------------------------

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
