local ADDON, P = ...
P = _G.Perch

-- Bar border and end caps.
--
-- Both are drawn from plain colour textures so they always match the bar's own
-- colour, alpha and border colour. Nothing overlaps: translucent colours would
-- double up where textures stack, so the background is inset by the border and
-- every cap row is split into a fill part and a border part.

P.CAP_STYLES = {
  { id = "none", label = "Flat" },
  { id = "triangle", label = "Triangle" },
  { id = "curved1", label = "Curved 1" },
  { id = "curved2", label = "Curved 2" },
  { id = "curved3", label = "Curved 3" },
}

-- Textures that are one flat colour, so caps can match them.
local SOLID_TEXTURES = {
  ["interface\\chatframe\\chatframebackground"] = true,
  ["interface\\buttons\\white8x8"] = true,
}

function P:IsSolidBackground()
  local texture = self.db.bar.background.texture
  return type(texture) == "string" and SOLID_TEXTURES[texture:lower()] == true
end

-- Width of a cap row as a share of the cap's width. t runs 0 (top of the bar,
-- the screen edge) to 1 (bottom). Every cap is widest at the top and meets the
-- bar's bottom corner; left and right ends are mirror images.
local PROFILES = {
  -- A right triangle: the flat side against the bar, the long side along the
  -- top, the slanted side coming down at 45 degrees (the width is the height).
  triangle = function(t)
    return 1 - t
  end,
  -- A semi-ellipse bulging out of the bar.
  curved1 = function(t)
    local u = 2 * t - 1
    return math.sqrt(math.max(0, 1 - u * u))
  end,
  -- A quarter circle centred on the bar's top corner: one radius along the top
  -- edge, the other against the bar, the arc coming down to the bottom.
  curved2 = function(t)
    return math.sqrt(math.max(0, 1 - t * t))
  end,
  -- An S-curve like a cube-root plot: shallow (nearly horizontal) where it
  -- leaves the top and where it lands on the bottom corner, and straight down
  -- through the middle. Width = (1 + (1 - 2t)^3) / 2.
  curved3 = function(t)
    local u = 1 - 2 * t
    return 0.5 * (1 + u * u * u)
  end,
}

-- Caps whose proportions are fixed by their shape: as wide as the bar is high.
local SQUARE_STYLES = { triangle = true, curved2 = true }

-- Caps that are stretched out sideways: the S-curve needs a long run to look
-- gentle, so it is this many times as wide as the width setting.
local STRETCH = { curved3 = 4.5 }

-- The style a side really gets: caps need a solid background to match.
function P:EffectiveCapStyle(side)
  local db = self.db.bar
  if db.background.enabled == false or not self:IsSolidBackground() then
    return "none"
  end
  local style = db.caps[side]
  if PROFILES[style] then
    return style
  end
  return "none"
end

local function colorOf(color, defaultAlpha)
  color = color or {}
  return color[1] or 0, color[2] or 0, color[3] or 0, color[4] or defaultAlpha
end

local function texture(self, key, layer, level)
  local decor = self.decor
  local piece = decor[key]
  if not piece then
    piece = self.bar:CreateTexture(nil, layer, nil, level or 0)
    decor[key] = piece
  end
  return piece
end

-- Pixel widths of every row of one cap.
local function rowWidths(style, side, height, width)
  if SQUARE_STYLES[style] then
    width = height
  else
    width = width * (STRETCH[style] or 1)
  end
  local widths = {}
  for row = 1, height do
    if style == "triangle" then
      -- Exactly one pixel narrower per row: a 45 degree slope.
      widths[row] = height - row + 1
    else
      local share = PROFILES[style]((row - 0.5) / height, side)
      widths[row] = math.floor(width * share + 0.5 + 1e-9)
    end
  end
  return widths
end

local function drawCap(self, side, style, height, capWidth, borderSize, fill, border)
  local bar = self.bar
  local rows = self.decor.rows[side]
  if not rows then
    rows = { fills = {}, borders = {} }
    self.decor.rows[side] = rows
  end

  local widths = style ~= "none" and rowWidths(style, side, height, capWidth) or {}
  -- The inner corner is the bar's own edge; the cap grows outwards.
  local innerPoint = side == "left" and "TOPRIGHT" or "TOPLEFT"
  local barPoint = side == "left" and "TOPLEFT" or "TOPRIGHT"
  local direction = side == "left" and -1 or 1

  for row = 1, math.max(height, #rows.fills) do
    local fillTexture, borderTexture = rows.fills[row], rows.borders[row]
    local total = widths[row]
    if not total or total <= 0 or row > height then
      if fillTexture then
        fillTexture:Hide()
      end
      if borderTexture then
        borderTexture:Hide()
      end
    else
      -- The border has to cover the step to the neighbouring rows, or a shallow
      -- slope would show gaps. The cap's top and bottom edges are border all the
      -- way across, like the bar's own top and bottom lines. Only the side that
      -- touches the bar has none.
      local borderWidth = 0
      if borderSize > 0 then
        if row <= borderSize or row > height - borderSize then
          borderWidth = total
        else
          local step = math.max(math.abs(total - (widths[row - 1] or total)), math.abs(total - (widths[row + 1] or total)))
          borderWidth = math.max(1, math.min(total, math.max(borderSize, step)))
        end
      end
      local fillWidth = total - borderWidth
      local y = -(row - 1)

      fillTexture = fillTexture or self.bar:CreateTexture(nil, "BACKGROUND", nil, 0)
      rows.fills[row] = fillTexture
      fillTexture:ClearAllPoints()
      fillTexture:SetPoint(innerPoint, bar, barPoint, 0, y)
      fillTexture:SetSize(math.max(fillWidth, 0), 1)
      fillTexture:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
      fillTexture:SetShown(fillWidth > 0)

      borderTexture = borderTexture or self.bar:CreateTexture(nil, "BORDER", nil, 0)
      rows.borders[row] = borderTexture
      borderTexture:ClearAllPoints()
      borderTexture:SetPoint(innerPoint, bar, barPoint, direction * fillWidth, y)
      borderTexture:SetSize(math.max(borderWidth, 0), 1)
      borderTexture:SetColorTexture(border[1], border[2], border[3], border[4])
      borderTexture:SetShown(borderWidth > 0)
    end
  end
end

function P:ApplyDecor()
  local bar = self.bar
  if not bar then
    return
  end
  self.decor = self.decor or { rows = {} }

  local db = self.db.bar
  local borderDB = db.border
  local size = borderDB.enabled and math.max(0, math.floor((borderDB.size or 1) + 0.5)) or 0
  local height = math.max(1, math.floor((db.height or 22) + 0.5))
  local capWidth = math.max(0, math.floor((db.caps.width or 10) + 0.5))

  local left, right = self:EffectiveCapStyle("left"), self:EffectiveCapStyle("right")
  local br, bg, bb, ba = colorOf(borderDB.color, 1)
  local fr, fg, fb, fa = colorOf(db.background.color, 0.5)

  -- Background: inset by the border so the two never overlap. A side with a cap
  -- has no straight edge to border, the cap carries it.
  local leftInset = (size > 0 and left == "none") and size or 0
  local rightInset = (size > 0 and right == "none") and size or 0
  bar.bg:ClearAllPoints()
  bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", leftInset, -size)
  bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -rightInset, size)

  local top = texture(self, "top", "BORDER")
  local bottom = texture(self, "bottom", "BORDER")
  local leftEdge = texture(self, "left", "BORDER")
  local rightEdge = texture(self, "right", "BORDER")
  for _, line in ipairs({ top, bottom, leftEdge, rightEdge }) do
    line:SetColorTexture(br, bg, bb, ba)
    line:ClearAllPoints()
  end
  top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  top:SetHeight(math.max(size, 1))
  bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(math.max(size, 1))
  -- The side lines sit between the top and bottom lines.
  leftEdge:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -size)
  leftEdge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, size)
  leftEdge:SetWidth(math.max(size, 1))
  rightEdge:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -size)
  rightEdge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, size)
  rightEdge:SetWidth(math.max(size, 1))
  top:SetShown(size > 0)
  bottom:SetShown(size > 0)
  leftEdge:SetShown(size > 0 and left == "none")
  rightEdge:SetShown(size > 0 and right == "none")

  drawCap(self, "left", left, height, capWidth, size, { fr, fg, fb, fa }, { br, bg, bb, ba })
  drawCap(self, "right", right, height, capWidth, size, { fr, fg, fb, fa }, { br, bg, bb, ba })
end
