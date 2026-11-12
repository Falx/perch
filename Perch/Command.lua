local ADDON, P = ...
P = _G.Perch

local DEFAULT_COMMAND_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local MAX_COMMAND_NAME = 24

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown()
end

function P:FindCommand(name)
  name = trim(name)
  for index, command in ipairs(self.db.commands) do
    if command.name == name then
      return command, index
    end
  end
end

function P:AddCommand(name, macrotext)
  name = trim(name)
  macrotext = trim(macrotext)
  if name == "" or macrotext == "" then
    return false
  end
  if #name > MAX_COMMAND_NAME then
    self:Print("Command name is too long (max " .. MAX_COMMAND_NAME .. ").")
    return false
  end
  if self:FindCommand(name) then
    self:Print("A command named '" .. name .. "' already exists.")
    return false
  end
  self.db.commands[#self.db.commands + 1] = {
    name = name,
    macrotext = macrotext,
    icon = DEFAULT_COMMAND_ICON,
  }
  self:RebuildCommands()
  self:Print("Added command '" .. name .. "'.")
  return true
end

function P:RemoveCommand(name)
  local command, index = self:FindCommand(name)
  if not command then
    self:Print("No command named '" .. trim(name) .. "'.")
    return false
  end
  table.remove(self.db.commands, index)
  local key = "cmd:" .. command.name
  for orderIndex, ordered in ipairs(self.db.order) do
    if ordered == key then
      table.remove(self.db.order, orderIndex)
      break
    end
  end
  self.db.elements[key] = nil
  -- RebuildCommands owns the cell teardown: doing it here would touch a
  -- secure frame, which is protected during combat.
  self:RebuildCommands()
  self:Print("Removed command '" .. command.name .. "'.")
  return true
end

function P:ShowCommandTooltip(cell)
  GameTooltip:SetOwner(cell, "ANCHOR_BOTTOM")
  GameTooltip:ClearLines()
  local command = cell.command
  GameTooltip:SetText((command and command.name) or "Command", 1, 1, 1)
  local macro = command and command.macrotext
  if macro and macro ~= "" then
    GameTooltip:AddLine(macro, 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end

-- Command cells are secure buttons. On 16001 a secure button anchored to a
-- normal frame makes that frame protected too, and every SetWidth on a
-- protected frame is blocked in combat. Keep them on UIParent and place them
-- by screen position in Layout instead of anchoring them into the bar chain.
function P:CreateCommandCell(command, key)
  local bar = self.bar
  local cell = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
  cell.isCommand = true
  cell.commandKey = key
  cell.command = command
  cell:SetFrameStrata((bar and bar:GetFrameStrata()) or "LOW")
  cell:SetFrameLevel(((bar and bar:GetFrameLevel()) or 1) + 5)
  cell:SetScale((self.db.bar and self.db.bar.scale) or 1)
  cell:EnableMouse(true)
  cell:RegisterForClicks("AnyUp")
  cell:SetAttribute("useOnKeyDown", false)
  cell:SetAttribute("type", "macro")
  cell:SetAttribute("type1", "macro")
  cell:SetAttribute("macrotext", command.macrotext or "")
  cell:SetAttribute("macrotext1", command.macrotext or "")

  cell.text = cell:CreateFontString(nil, "OVERLAY")
  self:ApplyCellFont(cell)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
  cell.highlight:SetAllPoints(cell)
  cell.highlight:SetColorTexture(1, 1, 1, 0.15)

  cell.icon:SetTexture(command.icon or DEFAULT_COMMAND_ICON)
  cell.iconVisible = self.db.bar.showIcons ~= false
  cell.icon:SetShown(cell.iconVisible)
  self:ApplyCellFont(cell)
  cell.text:SetText(command.name or "Command")
  cell.lastText = command.name or "Command"

  cell:SetScript("OnEnter", function(frame)
    P:ShowCommandTooltip(frame)
  end)
  cell:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  -- Diagnostics only: the secure template owns OnClick. PostClick still fires
  -- after the secure action, so /perch doctor can tell a click apart from a
  -- button that was never hit.
  cell:HookScript("PostClick", function(frame)
    frame.commandClicks = (frame.commandClicks or 0) + 1
    P.commandClicks = (P.commandClicks or 0) + 1
  end)

  function cell:ContentLabel()
    return self.command and self.command.name or "Command"
  end

  return cell
end

-- Applies the per-element options (label, icon) to a command cell. Out of
-- combat only: callers check, and SizeCell guards its own resize.
function P:RefreshCommandCell(cell)
  local command = cell.command
  local key = cell.commandKey
  local text = ""
  if self:ElementOption(key, "showLabel") then
    text = self:ElementOption(key, "label") or command.name or "Command"
  end
  self:ApplyCellFont(cell)
  if cell.lastText ~= text then
    cell.text:SetText(text)
    cell.lastText = text
  end
  cell.iconVisible = (self.db.bar.showIcons ~= false and self:ElementOption(key, "showIcon")) and true or false
  cell.icon:SetShown(cell.iconVisible)
  self:SizeCell(cell)
end

function P:RebuildCommands()
  if inCombat() then
    self.commandRebuildPending = true
    return
  end
  self.commandRebuildPending = false

  for _, cell in pairs(self.commandCells or {}) do
    cell:Hide()
    cell:SetParent(nil)
  end
  self.commandCells = {}

  for _, command in ipairs(self.db.commands) do
    local key = "cmd:" .. command.name
    local ok, cell = pcall(self.CreateCommandCell, self, command, key)
    if ok and cell then
      self.commandCells[key] = cell
      self:EnsureOrder(key)
      self:RefreshCommandCell(cell)
    else
      self:RecordBrokerError(key, cell)
    end
  end

  self:RequestLayout()
end
