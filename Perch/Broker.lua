local ADDON, P = ...
P = _G.Perch

local LDB

local function safeTostring(value)
  local ok, text = pcall(tostring, value)
  return ok and text or ""
end

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

  -- Start the safety net before scanning: a broken plugin object must never be
  -- able to abort InitBroker and leave the bar without a poller.
  if not self.pollTicker then
    self.pollTicker = C_Timer.NewTicker(1, function()
      P:PollBrokers()
    end)
  end

  self:ScanBrokers()
end

-- One bad data object must not stop the rest of the bar from working.
function P:RecordBrokerError(name, err)
  self.brokerErrors = self.brokerErrors or {}
  name = tostring(name)
  if not self.brokerErrors[name] then
    self.brokerErrors[name] = tostring(err)
    self:Print(string.format("broker error (%s): %s", name, tostring(err)))
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
      local ok, err = pcall(self.RegisterBroker, self, name, object)
      if not ok then
        self:RecordBrokerError(name, err)
      end
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

  local ok, cell = pcall(self.CreateBrokerCell, self, name, object)
  if not ok then
    self:RecordBrokerError(name, cell)
    return
  end
  self.brokerElements[name] = cell
  self:EnsureOrder(name)
  self:UpdateBrokerCell(name)
end

function P:UpdateBrokerCell(name)
  local cell = self.brokerElements and self.brokerElements[name]
  if not cell then
    return
  end
  local ok, err = pcall(self.RefreshBrokerCell, self, cell, cell.obj)
  if not ok then
    self:RecordBrokerError(name, err)
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
        or safeTostring(object.value) ~= safeTostring(cell.lastValue)
      then
        cell.lastValue = object.value
        self:UpdateBrokerCell(cell.brokerName)
      end
    end
  end
end
