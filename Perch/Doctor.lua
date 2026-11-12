local ADDON, P = ...
P = _G.Perch

local function probeGlobal(name)
  if type(_G[name]) == "function" then
    return "ok"
  end
  return "MISSING"
end

local function probeTable(tableName, key)
  local namespace = _G[tableName]
  if type(namespace) ~= "table" then
    return "MISSING"
  end
  if type(namespace[key]) == "function" then
    return "ok"
  end
  return "MISSING"
end

local function probeFont(path)
  local probe = UIParent:CreateFontString(nil, "OVERLAY")
  local ok = probe:SetFont(path, 12, "")
  probe:Hide()
  return ok and "ok" or "FAILED"
end

function P:Doctor()
  local lines = {}
  local function add(format, ...)
    lines[#lines + 1] = string.format(format, ...)
  end

  add("Perch %s (build %s)", self.version or "?", self.build or "?")

  local version, build, _, toc = GetBuildInfo()
  add("client %s build %s toc %s", tostring(version), tostring(build), tostring(toc))

  local ldb = self.GetLDB()
  if ldb then
    local names = {}
    for name in ldb:DataObjectIterator() do
      names[#names + 1] = name
    end
    table.sort(names)
    add("LibDataBroker: ok (%d data objects)", #names)
    if #names > 0 then
      add("  %s", table.concat(names, ", "))
    end
  else
    add("LibDataBroker: MISSING")
  end

  add("LDB callbacks hooked: %s", self.brokerCallbacksHooked and "yes" or "no")

  local bar = self.bar
  if bar then
    local point, _, relativePoint, x, y = bar:GetPoint()
    add("bar: %s %dx%d at %s/%s (%s, %s)",
      bar:IsShown() and "shown" or "hidden",
      math.floor((bar:GetWidth() or 0) + 0.5),
      math.floor((bar:GetHeight() or 0) + 0.5),
      tostring(point), tostring(relativePoint), tostring(x), tostring(y))
  else
    add("bar: MISSING")
  end

  local cellCount = 0
  for _ in pairs(self.brokerElements or {}) do
    cellCount = cellCount + 1
  end
  add("broker cells: %d (order %d, enabled %d)", cellCount, #self.db.order, #self:OrderedKeys())

  -- Command cells are the part most likely to fail silently: a secure button
  -- with no registered click, a stale macrotext or a cell hidden since combat
  -- still looks like a working cell in the bar.
  local commandCount = 0
  for _ in pairs(self.commandCells or {}) do
    commandCount = commandCount + 1
  end
  add("command cells: %d (clicks recorded %d)", commandCount, self.commandClicks or 0)
  local commandKeys = {}
  for key in pairs(self.commandCells or {}) do
    commandKeys[#commandKeys + 1] = key
  end
  table.sort(commandKeys)
  for _, key in ipairs(commandKeys) do
    local cell = self.commandCells[key]
    local command = cell.command
    local parent = cell:GetParent()
    local parentName = "none"
    if parent == UIParent then
      parentName = "UIParent"
    elseif parent then
      parentName = tostring(parent)
    end
    add("  %s: %s, clicks %d, parent %s",
      key,
      cell:IsShown() and "shown" or "hidden",
      cell.commandClicks or 0,
      parentName)
    local macrotext = command and command.macrotext
    if macrotext == nil and cell.GetAttribute then
      macrotext = cell:GetAttribute("macrotext")
    end
    add("    type=%s macro=%s",
      tostring(cell.GetAttribute and cell:GetAttribute("type")),
      tostring(macrotext))
  end
  if self.commandRebuildPending then
    add("  rebuild pending (combat)")
  end

  local failed = {}
  for name, err in pairs(self.brokerErrors or {}) do
    failed[#failed + 1] = string.format("%s: %s", name, tostring(err):gsub("\n", " | "))
  end
  table.sort(failed)
  add("broker errors: %d", #failed)
  for _, line in ipairs(failed) do
    add("  %s", line)
  end

  if self.layoutError then
    add("layout error: %s", tostring(self.layoutError):gsub("\n", " | "))
  end

  add("Settings API: %s", (Settings and Settings.RegisterVerticalLayoutCategory) and "ok" or "MISSING")
  add("  RegisterCanvasLayoutCategory: %s", probeTable("Settings", "RegisterCanvasLayoutCategory"))
  add("  RegisterAddOnCategory: %s", probeTable("Settings", "RegisterAddOnCategory"))
  add("  CreateCheckbox: %s", probeTable("Settings", "CreateCheckbox"))
  add("  CreateSlider: %s", probeTable("Settings", "CreateSlider"))
  add("  CreateSliderOptions: %s", probeTable("Settings", "CreateSliderOptions"))

  add("SecureCmdOptionParse: %s", probeGlobal("SecureCmdOptionParse"))
  add("InCombatLockdown: %s", probeGlobal("InCombatLockdown"))
  add("C_Container: %s", type(C_Container) == "table" and "ok" or "MISSING")
  add("  GetContainerNumFreeSlots: %s", probeTable("C_Container", "GetContainerNumFreeSlots"))
  add("  GetContainerNumSlots: %s", probeTable("C_Container", "GetContainerNumSlots"))
  add("GetInventoryItemDurability: %s", probeGlobal("GetInventoryItemDurability"))
  add("C_Map.GetPlayerMapPosition: %s", probeTable("C_Map", "GetPlayerMapPosition"))
  add("C_DateAndTime.GetCurrentCalendarTime: %s", probeTable("C_DateAndTime", "GetCurrentCalendarTime"))
  add("GetGameTime: %s", probeGlobal("GetGameTime"))
  add("GetFPS: %s", probeGlobal("GetFPS"))
  add("GetFramerate: %s", probeGlobal("GetFramerate"))
  add("GetMoney: %s", probeGlobal("GetMoney"))

  add("font FRIZQT__: %s", probeFont("Fonts\\FRIZQT__.TTF"))
  add("font ARIALN: %s", probeFont("Fonts\\ARIALN.TTF"))

  add("errors captured: %d", self.errorCount or 0)
  if self.lastError then
    add("last error: %s", tostring(self.lastError):gsub("\n", " | "))
  end

  if self.optionsCategory then
    add("options category: registered (id %s)", tostring(self:OptionsCategoryID()))
  elseif self.optionsError then
    add("options category: FAILED (%s)", tostring(self.optionsError))
  else
    add("options category: standalone frame only")
  end

  for _, line in ipairs(lines) do
    self:Print(line)
  end
end
