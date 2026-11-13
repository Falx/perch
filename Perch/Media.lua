local ADDON, P = ...
P = _G.Perch

P.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

-- Used when LibSharedMedia is missing, and merged into its lists so the basics
-- are always there.
local FALLBACK = {
  font = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
  },
  background = {
    -- Named apart from LibSharedMedia's own "Solid" (a different file), so the
    -- texture Perch uses by default is always in the list.
    ["Default (solid)"] = "Interface\\ChatFrame\\ChatFrameBackground",
  },
}

local LSM

function P.GetLSM()
  if LSM then
    return LSM
  end
  if LibStub == nil then
    return nil
  end
  local ok, library = pcall(LibStub, "LibSharedMedia-3.0", true)
  if ok and library then
    LSM = library
  end
  return LSM
end

-- Sorted array of { name = ..., path = ... } for "font" or "background".
function P:MediaList(kind)
  local merged = {}
  for name, path in pairs(FALLBACK[kind] or {}) do
    merged[name] = path
  end
  local lsm = self.GetLSM()
  if lsm and type(lsm.HashTable) == "function" then
    local ok, hash = pcall(lsm.HashTable, lsm, kind)
    if ok and type(hash) == "table" then
      for name, path in pairs(hash) do
        merged[name] = path
      end
    end
  end
  local list = {}
  for name, path in pairs(merged) do
    list[#list + 1] = { name = name, path = path }
  end
  table.sort(list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return list
end

-- Items for the option picker: label, saved value (the path) and preview font.
function P:FontItems()
  local items = {}
  for _, entry in ipairs(self:MediaList("font")) do
    items[#items + 1] = { label = entry.name, value = entry.path, font = entry.path }
  end
  return items
end
