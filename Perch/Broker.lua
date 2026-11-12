local ADDON, P = ...
P = _G.Perch

local LDB

function P.GetLDB()
  if LDB then
    return LDB
  end
  if LibStub == nil then
    return nil
  end
  local ok, library = pcall(LibStub, "LibDataBroker-1.1", true)
  if ok and library then
    LDB = library
  end
  return LDB
end

function P:InitBroker()
  self.brokerElements = self.brokerElements or {}
  local ldb = self.GetLDB()

  if ldb and not self.brokerCallbacksHooked then
    self.brokerCallbacksHooked = true
    -- LibDataBroker registers its callback API on the library object itself.
    local registrar = ldb
    if type(registrar.RegisterCallback) ~= "function" then
      registrar = ldb.callbacks
    end
    if registrar and type(registrar.RegisterCallback) == "function" then
      -- Late registration: DataObjectCreated fires for every new data object.
      registrar:RegisterCallback("LibDataBroker_DataObjectCreated", function(_, name, object)
        P:RegisterBroker(name, object)
      end)
      -- Any attribute change on any object; re-read the whole cell.
      registrar:RegisterCallback("LibDataBroker_AttributeChanged", function(_, name)
        P:UpdateBrokerCell(name)
      end)
    end
  end

  self:ScanBrokers()

  if not self.pollTicker then
    self.pollTicker = C_Timer.NewTicker(1, function()
      P:PollBrokers()
    end)
  end
end

function P:ScanBrokers()
  local ldb = self.GetLDB()
  if not ldb then
    return
  end
  self.brokerElements = self.brokerElements or {}
  for name, object in ldb:DataObjectIterator() do
    if not self.brokerElements[name] then
      self:RegisterBroker(name, object)
    end
  end
end

function P:RegisterBroker(name, object)
  if not name or not object then
    return
  end
  if not self.brokerElements then
    self.brokerElements = {}
  end
  if self.brokerElements[name] then
    self:UpdateBrokerCell(name)
    return
  end

  local cell = self:CreateBrokerCell(name, object)
  self.brokerElements[name] = cell
  self:EnsureOrder(name)
  self:UpdateBrokerCell(name)
end

function P:UpdateBrokerCell(name)
  local cell = self.brokerElements and self.brokerElements[name]
  if cell then
    self:RefreshBrokerCell(cell, cell.obj)
  end
end

-- Fallback for plugins that mutate their data without going through the LDB
-- proxy (rare, but it happens).
function P:PollBrokers()
  self:ScanBrokers()

  for _, cell in pairs(self.brokerElements or {}) do
    local object = cell.obj
    if object then
      local text = self:BrokerText(object)
      if text ~= cell.lastText
        or object.icon ~= cell.lastIcon
        or tostring(object.value) ~= tostring(cell.lastValue)
      then
        cell.lastValue = object.value
        self:RefreshBrokerCell(cell, object)
      end
    end
  end
end
