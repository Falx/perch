local ADDON, P = ...
_G.Perch = P

P.name = ADDON
P.build = "dev"

-- Built-in data source keys, in default display order.
P.builtinOrder = {
  "Perch_Clock",
  "Perch_Gold",
  "Perch_FPS",
  "Perch_Memory",
  "Perch_Durability",
  "Perch_Bags",
  "Perch_Coords",
  "Perch_XP",
}

local defaults = {
  version = 1,
  bar = {
    point = "TOP",
    relativePoint = "TOP",
    x = 0,
    y = -8,
    locked = true,
    height = 22,
    padding = 6,
    spacing = 8,
    scale = 1,
    hideWhenEmpty = true,
    mouseoverFade = false,
    hideInCombat = false,
    clickThrough = false,
    background = {
      enabled = true,
      texture = "Interface\\ChatFrame\\ChatFrameBackground",
      color = { 0, 0, 0, 0.5 },
    },
    font = {
      name = "Fonts\\FRIZQT__.TTF",
      size = 12,
      color = { 1, 1, 1, 1 },
      outline = "",
    },
    iconSize = 14,
    showIcons = true,
  },
  elements = {},
  order = {},
  commands = {},
  settings = {
    clock24 = false,
    clockLocal = false,
    coordDecimals = 1,
  },
}

P.defaults = defaults

local function mergeDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = {}
      end
      mergeDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function metadata(key)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON, key)
    if ok and value then
      return value
    end
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, key)
  end
end

P.version = metadata("Version") or "0.0.0"

local PREFIX = "|cff6fd3ffPerch|r"

function P:Print(msg)
  local line = PREFIX .. " " .. tostring(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

function P:EnsureDB()
  if type(PerchDB) ~= "table" then
    PerchDB = {}
  end
  mergeDefaults(PerchDB, defaults)
  if type(PerchDB.bar) ~= "table" then
    PerchDB.bar = {}
    mergeDefaults(PerchDB.bar, defaults.bar)
  end
  if type(PerchDB.elements) ~= "table" then
    PerchDB.elements = {}
  end
  if type(PerchDB.order) ~= "table" then
    PerchDB.order = {}
  end
  if type(PerchDB.commands) ~= "table" then
    PerchDB.commands = {}
  end
  if type(PerchDB.settings) ~= "table" then
    PerchDB.settings = {}
    mergeDefaults(PerchDB.settings, defaults.settings)
  end
  self.db = PerchDB
  for _, key in ipairs(self.builtinOrder) do
    self:EnsureOrder(key)
  end
end

function P:EnsureOrder(key)
  if not key then
    return
  end
  for _, existing in ipairs(self.db.order) do
    if existing == key then
      return
    end
  end
  self.db.order[#self.db.order + 1] = key
end

function P:ElementDB(key)
  local element = self.db.elements[key]
  if type(element) ~= "table" then
    element = {}
    self.db.elements[key] = element
  end
  return element
end

function P:IsEnabled(key)
  local element = self.db.elements[key]
  if element and element.enabled ~= nil then
    return element.enabled ~= false
  end
  -- Launcher objects are opt-in: the Forever LDB ecosystem is full of
  -- icon-only minimap launchers that would otherwise flood the bar.
  local cell = self:GetCell(key)
  if cell and cell.obj and cell.obj.type == "launcher" then
    return false
  end
  return true
end

function P:SetElementEnabled(key, enabled)
  if not key then
    return
  end
  self:ElementDB(key).enabled = enabled and true or false
  local cell = self:GetCell(key)
  if cell then
    if cell.isCommand then
      -- Secure button: Show/Hide is protected in combat.
      if not (InCombatLockdown and InCombatLockdown()) then
        cell:SetShown(enabled)
      end
    else
      -- Re-read the cell so an enabled element is shown again and a disabled
      -- one is hidden immediately.
      self:UpdateBrokerCell(key)
    end
  end
  self:RequestLayout()
  self:RefreshOptions()
end

function P:ElementKind(key)
  local cell = self:GetCell(key)
  if cell and cell.isCommand then
    return "command"
  end
  local kind = cell and cell.obj and cell.obj.type
  if kind == "launcher" then
    return "launcher"
  end
  return "data source"
end

function P:InstallErrorHook()
  if self.errorHooked then
    return
  end
  self.errorHooked = true
  self.errorCount = self.errorCount or 0
  if geterrorhandler and seterrorhandler then
    local previous = geterrorhandler()
    if previous then
      seterrorhandler(function(msg)
        P.errorCount = (P.errorCount or 0) + 1
        P.lastError = tostring(msg)
        return previous(msg)
      end)
    end
  end
end

--
-- Events
--

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    P:EnsureDB()
    P:InstallErrorHook()
    P:CreateBar()
    P:RegisterOptions()
  elseif event == "PLAYER_LOGIN" then
    P:InitBuiltins()
    P:InitBroker()
    P:RebuildCommands()
    P:RequestLayout()
  elseif event == "PLAYER_ENTERING_WORLD" then
    if InCombatLockdown() then
      for _, cell in pairs(P.commandCells or {}) do
        cell:Hide()
      end
    end
    if P.db.bar.hideInCombat and InCombatLockdown() then
      P:RequestLayout()
    end
    P:ScanBrokers()
    P:RequestLayout()
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    if event == "PLAYER_REGEN_DISABLED" then
      -- Last safe moment: secure cells cannot be hidden once combat locks them.
      for _, cell in pairs(P.commandCells or {}) do
        cell:Hide()
      end
      if P.db.bar.hideInCombat and P.bar then
        P.bar:Hide()
      end
    else
      if P.commandRebuildPending then
        P:RebuildCommands()
      end
      -- Re-sizes cells that were skipped in combat and re-shows/repositions
      -- the secure command cells.
      P:ApplyAll()
    end
  end
end)

--
-- Slash command
--

local function dumpValue(value, indent, depth, out)
  indent = indent or ""
  depth = depth or 0
  out = out or {}
  if type(value) ~= "table" then
    out[#out + 1] = indent .. tostring(value)
    return out
  end
  if depth >= 3 then
    out[#out + 1] = indent .. "{...}"
    return out
  end
  out[#out + 1] = indent .. "{"
  for key, child in pairs(value) do
    out[#out + 1] = indent .. "  " .. tostring(key) .. " = " .. (type(child) == "table" and "" or tostring(child))
    if type(child) == "table" then
      dumpValue(child, indent .. "  ", depth + 1, out)
    end
  end
  out[#out + 1] = indent .. "}"
  return out
end

function P:HandleCommand(cmd, rest)
  cmd = (cmd or ""):lower()
  local db = self.db.bar

  if cmd == "" or cmd == "config" or cmd == "options" then
    self:ToggleOptions()
  elseif cmd == "frame" then
    self:ShowOptionsFrame()
  elseif cmd == "lock" then
    db.locked = true
    self:Print("Bar locked.")
  elseif cmd == "unlock" then
    db.locked = false
    self:Print("Bar unlocked - drag it into place, then /perch lock.")
  elseif cmd == "scale" then
    local value = tonumber(rest)
    if value and value > 0.1 and value < 4 then
      db.scale = value
      self:ApplyBarStyle()
      self:RequestLayout()
      self:Print("Scale set to " .. value .. ".")
    else
      self:Print("Usage: /perch scale <0.1-4>")
    end
  elseif cmd == "reset" then
    PerchDB = nil
    self:EnsureDB()
    self:Print("Settings reset. /reload to rebuild the bar.")
  elseif cmd == "doctor" then
    self:Doctor()
  elseif cmd == "dump" then
    local lines = dumpValue(PerchDB)
    for _, line in ipairs(lines) do
      self:Print(line)
    end
  elseif cmd == "list" then
    self:ListElements()
  elseif cmd == "enable" or cmd == "disable" then
    local key = self:ResolveKey(rest)
    if not key then
      self:Print("Unknown element: " .. tostring(rest))
    else
      self:SetElementEnabled(key, cmd == "enable")
      self:Print((cmd == "enable" and "Enabled " or "Disabled ") .. key)
    end
  elseif cmd == "cmd" then
    local action, name, macro = (rest or ""):match("^(%S*)%s*(%S*)%s*(.*)$")
    action = (action or ""):lower()
    if action == "add" then
      if name == "" or macro == "" then
        self:Print("Usage: /perch cmd add <name> <macro text>")
      else
        self:AddCommand(name, macro)
      end
    elseif action == "del" then
      self:RemoveCommand(name)
    else
      self:Print("Usage: /perch cmd add <name> <macro> | /perch cmd del <name>")
    end
  else
    self:Print("Commands: config, frame, lock, unlock, scale <n>, reset, doctor, dump, list, enable <key>, disable <key>, cmd add|del")
  end
end

SLASH_PERCH1 = "/perch"
SlashCmdList["PERCH"] = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  P:HandleCommand(cmd, rest)
end
