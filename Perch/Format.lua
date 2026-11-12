local ADDON, P = ...
P = _G.Perch

-- Format codes
--
-- Custom formats are templates with #codes, e.g. "#g g #s s" for gold. A code is
-- one or two lowercase letters; the longest known code wins ("#gi" is the gold
-- icon, "#g" the gold amount). "##" is a literal "#". Unknown codes stay as
-- typed.

function P:FormatCodes(template, tokens)
  template = tostring(template or "")
  local out = {}
  local index, length = 1, #template
  while index <= length do
    local char = template:sub(index, index)
    if char ~= "#" then
      out[#out + 1] = char
      index = index + 1
    elseif template:sub(index + 1, index + 1) == "#" then
      out[#out + 1] = "#"
      index = index + 2
    else
      local two = template:sub(index + 1, index + 2)
      local one = template:sub(index + 1, index + 1)
      if #two == 2 and tokens[two] ~= nil then
        out[#out + 1] = tostring(tokens[two])
        index = index + 3
      elseif tokens[one] ~= nil then
        out[#out + 1] = tostring(tokens[one])
        index = index + 2
      else
        out[#out + 1] = "#"
        index = index + 1
      end
    end
  end
  return table.concat(out)
end

local function whole(number)
  number = math.floor((number or 0) + 0.5)
  if BreakUpLargeNumbers then
    return BreakUpLargeNumbers(number)
  end
  return tostring(number)
end

--
-- Gold
--

local COIN = "|T%s:0:0:2:0|t"

P.GOLD_PRESETS = {
  { id = "default", label = "Default (12g 34s)" },
  { id = "letters", label = "12g 34s 56c", template = "#gg #ss #cc" },
  { id = "icons", label = "Coin icons", template = "#g#gi #s#si #c#ci" },
  { id = "gold", label = "Gold only", template = "#gg" },
  { id = "custom", label = "Custom" },
}

P.GOLD_CODES = "#g gold, #s silver, #c copper, #gi #si #ci coin icons, ## a literal #"

-- The original layout: gold and silver, or silver and copper below one gold.
function P:FormatMoney(copper)
  copper = copper or 0
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local remainder = copper % 100
  if gold > 0 then
    return string.format("%dg %ds", gold, silver)
  end
  if silver > 0 then
    return string.format("%ds %dc", silver, remainder)
  end
  return string.format("%dc", remainder)
end

local function presetTemplate(presets, id, custom)
  if id == "custom" then
    return custom
  end
  for _, preset in ipairs(presets) do
    if preset.id == id then
      return preset.template
    end
  end
end

function P:FormatMoneyDisplay(copper)
  local settings = self.db.settings
  local template = presetTemplate(self.GOLD_PRESETS, settings.goldFormat, settings.goldCustom)
  if not template or template == "" then
    return self:FormatMoney(copper)
  end
  copper = copper or 0
  return self:FormatCodes(template, {
    g = whole(math.floor(copper / 10000)),
    s = math.floor((copper % 10000) / 100),
    c = copper % 100,
    gi = COIN:format("Interface\\MoneyFrame\\UI-GoldIcon"),
    si = COIN:format("Interface\\MoneyFrame\\UI-SilverIcon"),
    ci = COIN:format("Interface\\MoneyFrame\\UI-CopperIcon"),
  })
end

--
-- Experience
--

P.XP_PRESETS = {
  { id = "percent", label = "Current %", template = "#p%" },
  { id = "percentRested", label = "Current % + rested %", template = "#p%+#rp%" },
  { id = "fraction", label = "Current / max", template = "#c/#m" },
  { id = "fractionRested", label = "Current + rested / max", template = "#c+#r/#m" },
  { id = "missing", label = "Missing (-xp)", template = "-#x" },
  { id = "custom", label = "Custom" },
}

P.XP_CODES = "#c current, #m max, #r rested, #x missing, #p current %, #rp rested %, #xp missing %"

function P:FormatXP(current, maximum, rested)
  local settings = self.db.settings
  local template = presetTemplate(self.XP_PRESETS, settings.xpFormat, settings.xpCustom)
  if not template or template == "" then
    template = "#p%"
  end
  rested = rested or 0
  local percent = maximum > 0 and current / maximum * 100 or 0
  return self:FormatCodes(template, {
    c = whole(current),
    m = whole(maximum),
    r = whole(rested),
    x = whole(maximum - current),
    p = string.format("%.0f", percent),
    rp = string.format("%.0f", maximum > 0 and rested / maximum * 100 or 0),
    xp = string.format("%.0f", 100 - percent),
  }), percent
end

-- { label, value } items for the option dropdowns.
function P:PresetItems(presets)
  local items = {}
  for _, preset in ipairs(presets) do
    items[#items + 1] = { label = preset.label, value = preset.id }
  end
  return items
end
