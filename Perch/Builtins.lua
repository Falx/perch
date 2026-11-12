local ADDON, P = ...
P = _G.Perch

local objects = {}
P.builtinObjects = objects

local function newObject(key, label, icon, extra)
  local ldb = P.GetLDB()
  if not ldb then
    return nil
  end
  local fields = {
    type = "data source",
    label = label,
    icon = icon,
    text = "",
  }
  for name, value in pairs(extra or {}) do
    fields[name] = value
  end
  local object = ldb:NewDataObject(key, fields)
  object.__builtin = true
  objects[key] = object
  return object
end

-- Right-click opens this element's settings; plugin callbacks receive the
-- display cell first, then the mouse button. Extra handlers run on left-click.
local function clickHandler(key, onLeft)
  return function(_, button)
    if button == "RightButton" then
      P:OpenElementSettings(key)
    elseif onLeft then
      onLeft()
    end
  end
end

function P:SetBuiltinText(key, text, value)
  local object = objects[key]
  if not object then
    return
  end
  text = text or ""
  -- Assigning through the LDB proxy fires the attribute callbacks for us.
  object.text = text or ""
  object.value = value
end

--
-- Built-in data sources
--

local function updateClock()
  local hour, minute
  if P.db.settings.clock24 == nil then
    P.db.settings.clock24 = false
  end
  if P.db.settings.clockLocal then
    local now = date and date("*t")
    if now then
      hour, minute = now.hour, now.min
    end
  end
  if not hour then
    hour, minute = GetGameTime()
  end
  if not hour then
    return
  end
  local displayHour = hour
  if not P.db.settings.clock24 then
    displayHour = hour % 12
    if displayHour == 0 then
      displayHour = 12
    end
  end
  P:SetBuiltinText("Perch_Clock", string.format("%d:%02d", displayHour, minute or 0), hour * 60 + (minute or 0))
end

local function updateGold()
  local money = GetMoney and GetMoney() or 0
  P:SetBuiltinText("Perch_Gold", P:FormatMoneyDisplay(money), money)
end

local function updateFPS()
  -- GetFPS is absent on 16001; GetFramerate is the vanilla-era equivalent.
  local getter = GetFPS or GetFramerate
  if not getter then
    return
  end
  local fps = getter()
  if not fps then
    return
  end
  P:SetBuiltinText("Perch_FPS", string.format("%d fps", math.floor(fps + 0.5)), fps)
end

local function updateMemory()
  local kilobytes = collectgarbage("count")
  if not kilobytes then
    return
  end
  P:SetBuiltinText("Perch_Memory", string.format("%.0f MB", kilobytes / 1024), kilobytes)
end

local function updateDurability()
  local lowest
  if GetInventoryItemDurability then
    for slot = 1, 19 do
      local current, maximum = GetInventoryItemDurability(slot)
      if current and maximum and maximum > 0 then
        local percent = current / maximum * 100
        if not lowest or percent < lowest then
          lowest = percent
        end
      end
    end
  end
  if lowest then
    P:SetBuiltinText("Perch_Durability", string.format("%d%%", math.floor(lowest + 0.5)), lowest)
  else
    P:SetBuiltinText("Perch_Durability", "")
  end
end

local containerAPI = {
  slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots,
  free = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots,
}

local function updateBags()
  if not containerAPI.slots then
    return
  end
  local free, total = 0, 0
  for bag = 0, 4 do
    local slots = containerAPI.slots(bag)
    if slots and slots > 0 then
      total = total + slots
      free = free + ((containerAPI.free and containerAPI.free(bag)) or 0)
    end
  end
  if total > 0 then
    P:SetBuiltinText("Perch_Bags", string.format("%d/%d", free, total), free)
  else
    P:SetBuiltinText("Perch_Bags", "")
  end
end

local function updateCoords()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
    return
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then
    P:SetBuiltinText("Perch_Coords", "")
    return
  end
  local position = C_Map.GetPlayerMapPosition(mapID, "player")
  if not position then
    P:SetBuiltinText("Perch_Coords", "")
    return
  end
  local x, y = position:GetXY()
  if not x or not y or (x == 0 and y == 0) then
    P:SetBuiltinText("Perch_Coords", "")
    return
  end
  local decimals = P.db.settings.coordDecimals or 1
  local pattern = "%." .. decimals .. "f, %." .. decimals .. "f"
  P:SetBuiltinText("Perch_Coords", string.format(pattern, x * 100, y * 100), x * 100 + y)
end

local function updateXP()
  if not UnitXP or not UnitXPMax then
    return
  end
  local current, maximum = UnitXP("player"), UnitXPMax("player")
  if not current or not maximum or maximum <= 0 or current >= maximum then
    P:SetBuiltinText("Perch_XP", "")
    return
  end
  local percent = current / maximum * 100
  local text = P:FormatXP(current, maximum, GetXPExhaustion and GetXPExhaustion() or 0)
  P:SetBuiltinText("Perch_XP", text, percent)
end

local updaters = {
  Perch_Clock = updateClock,
  Perch_Coords = updateCoords,
  Perch_Gold = updateGold,
  Perch_Bags = updateBags,
  Perch_XP = updateXP,
}

-- Re-renders one built-in right away, e.g. after its settings changed.
function P:RefreshBuiltin(key)
  local update = updaters[key]
  if update then
    update()
  end
end

local function updateAll()
  updateClock()
  updateGold()
  updateFPS()
  updateMemory()
  updateDurability()
  updateBags()
  updateCoords()
  updateXP()
end

-- Hover tooltip for Durability: every slot that has durability, with its percent.
local DURABILITY_SLOTS = {
  { 1, "Head" },
  { 3, "Shoulders" },
  { 5, "Chest" },
  { 6, "Waist" },
  { 7, "Legs" },
  { 8, "Feet" },
  { 9, "Wrists" },
  { 10, "Hands" },
  { 16, "Main hand" },
  { 17, "Off hand" },
  { 18, "Ranged" },
}

local function durabilityTooltip(tooltip)
  tooltip:SetText("Durability", 1, 1, 1)
  local listed = false
  if GetInventoryItemDurability then
    for _, slot in ipairs(DURABILITY_SLOTS) do
      local current, maximum = GetInventoryItemDurability(slot[1])
      if current and maximum and maximum > 0 then
        local percent = current / maximum * 100
        local red, green, blue = 1, 0.3, 0.3
        if percent >= 60 then
          red, green, blue = 0.3, 1, 0.3
        elseif percent >= 30 then
          red, green, blue = 1, 0.82, 0
        end
        tooltip:AddDoubleLine(slot[2], string.format("%d%%", math.floor(percent + 0.5)), 1, 1, 1, red, green, blue)
        listed = true
      end
    end
  end
  if not listed then
    tooltip:AddLine("No equipped item has durability.", 0.8, 0.8, 0.8)
  end
end

local function toggleBags()
  local toggle = ToggleAllBags or OpenAllBags
  if toggle then
    toggle()
  end
end

function P:InitBuiltins()
  if self.builtinsReady then
    return
  end
  self.builtinsReady = true
  if not self.GetLDB() then
    return
  end

  newObject("Perch_Clock", "Clock", "Interface\\Icons\\INV_Misc_PocketWatch_01", {
    OnClick = clickHandler("Perch_Clock"),
  })
  newObject("Perch_Gold", "Gold", "Interface\\Icons\\INV_Misc_Coin_01", {
    OnClick = clickHandler("Perch_Gold"),
  })
  newObject("Perch_FPS", "FPS", "Interface\\Icons\\INV_Misc_Gear_01", {
    OnClick = clickHandler("Perch_FPS"),
  })
  newObject("Perch_Memory", "Memory", "Interface\\Icons\\INV_Misc_Coin_02", {
    OnClick = clickHandler("Perch_Memory"),
  })
  -- No settings: the hover tooltip lists every slot instead.
  newObject("Perch_Durability", "Durability", "Interface\\Icons\\INV_Shield_06", {
    OnTooltipShow = durabilityTooltip,
  })
  -- No settings: left-click opens the bags.
  newObject("Perch_Bags", "Bags", "Interface\\Icons\\INV_Misc_Bag_08", {
    OnClick = function(_, button)
      if button == "LeftButton" then
        toggleBags()
      end
    end,
  })
  newObject("Perch_Coords", "Coords", "Interface\\Icons\\INV_Misc_Map_01", {
    OnClick = clickHandler("Perch_Coords"),
  })
  newObject("Perch_XP", "XP", "Interface\\Icons\\INV_Misc_Book_09", {
    OnClick = clickHandler("Perch_XP"),
  })

  updateAll()

  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_MONEY")
  events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
  events:RegisterEvent("BAG_UPDATE")
  events:RegisterEvent("PLAYER_XP_UPDATE")
  events:RegisterEvent("UPDATE_EXHAUSTION")
  events:RegisterEvent("PLAYER_LEVEL_UP")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MONEY" then
      updateGold()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
      updateDurability()
    elseif event == "BAG_UPDATE" then
      updateBags()
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
      updateXP()
    elseif event == "PLAYER_ENTERING_WORLD" then
      updateAll()
    end
  end)

  C_Timer.NewTicker(1, function()
    updateClock()
    updateFPS()
    updateMemory()
  end)

  local coords = CreateFrame("Frame")
  local elapsedSinceUpdate = 0
  coords:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + (elapsed or 0)
    if elapsedSinceUpdate < 0.2 then
      return
    end
    elapsedSinceUpdate = 0
    updateCoords()
  end)
  self.coordsFrame = coords
end
