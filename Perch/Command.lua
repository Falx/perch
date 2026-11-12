local ADDON, P = ...
P = _G.Perch

local DEFAULT_COMMAND_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local MAX_COMMAND_NAME = 24

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
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
  local cell = self.commandCells and self.commandCells[key]
  if cell then
    cell:Hide()
    cell:SetParent(nil)
    self.commandCells[key] = nil
  end
  for orderIndex, ordered in ipairs(self.db.order) do
    if ordered == key then
      table.remove(self.db.order, orderIndex)
      break
    end
  end
  self.db.elements[key] = nil
  self:RebuildCommands()
  self:Print("Removed command '" .. command.name .. "'.")
  return true
end

function P:RebuildCommands()
  if InCombatLockdown and InCombatLockdown() then
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
    local cell = CreateFrame("Button", nil, self.bar, "SecureActionButtonTemplate")
    cell.isCommand = true
    cell.commandKey = key
    cell.command = command

    cell:SetAttribute("type", "macro")
    cell:SetAttribute("macrotext", command.macrotext or "")
    -- Without this the secure template never fires OnClick, so the macro
    -- silently does nothing.
    cell:RegisterForClicks("AnyUp")

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
    cell.text:SetText(command.name or "Command")

    function cell:ContentLabel()
      return self.command and self.command.name or "Command"
    end

    self.commandCells[key] = cell
    self:EnsureOrder(key)
    self:SizeCell(cell)
  end

  self:RequestLayout()
end
