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
  -- top, narrowing to the bar's bottom corner. It is a 45 degree slope when the
  -- cap is as wide as the bar is high (the default width).
  triangle = function(t)
    return 1 - t
  end,
  -- A semi-ellipse bulging out of the bar.
  curved1 = function(t)
    local u = 2 * t - 1
    return math.sqrt(math.max(0, 1 - u * u))
  end,
  -- A quarter circle centred on the bar's top corner: one radius along the top
  -- edge, the other against the bar, the arc coming down to the bottom (a
  -- circle when the width equals the bar height, otherwise a quarter ellipse).
  curved2 = function(t)
    return math.sqrt(math.max(0, 1 - t * t))
  end,
  -- A sine half-wave, exaggerated: horizontal where it leaves the top and where
  -- it lands on the bottom corner, and steep through the middle. The row position
  -- across the cap follows an even mix of one sine pass and a sine of that sine;
  -- the width at each row is found by inverting it.
  curved3 = function(t)
    return P.CurvedThree(t)
  end,
}

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

-- The exaggerated sine for Curved 3. forward(u) is the row position (0 top .. 1
-- bottom) reached at a share u across the cap from its outer end; it mixes a
-- sine S-curve with a sine of that curve, which flattens the ends and steepens
-- the middle. Returns the width share at row position t by inverting it.
local EXAGGERATION = 0.5

local function sineStep(u)
  return (1 - math.cos(math.pi * u)) / 2
end

function P.CurvedThreeForward(u)
  local once = sineStep(u)
  return (1 - EXAGGERATION) * once + EXAGGERATION * sineStep(once)
end

function P.CurvedThree(t)
  local low, high = 0, 1
  for _ = 1, 40 do
    local middle = (low + high) / 2
    if P.CurvedThreeForward(middle) < t then
      low = middle
    else
      high = middle
    end
  end
  return 1 - (low + high) / 2
end

-- Exact (fractional) widths of every row of one cap, sampled at the row centres.
-- Rounding them would give stair steps; the fraction is drawn as a partly
-- transparent pixel instead.
local function rowLengths(style, side, height, width)
  local lengths = {}
  for row = 1, height do
    lengths[row] = width * PROFILES[style]((row - 0.5) / height, side)
  end
  return lengths
end

local function pieceFor(rows, kind, row, bar, layer)
  local list = rows[kind]
  local piece = list[row]
  if not piece then
    piece = bar:CreateTexture(nil, layer, nil, 0)
    list[row] = piece
  end
  return piece
end

local function place(piece, innerPoint, bar, barPoint, x, y, width, color, alpha)
  piece:ClearAllPoints()
  piece:SetPoint(innerPoint, bar, barPoint, x, y)
  piece:SetSize(width, 1)
  piece:SetColorTexture(color[1], color[2], color[3], alpha)
  piece:Show()
end

-- One row is up to three pieces side by side, from the bar outwards: the fill, the
-- border, and one antialiasing pixel whose alpha is how much of it the edge
-- covers. Nothing overlaps, so translucent colours never double up.
local function drawCap(self, side, style, height, capWidth, borderSize, fill, border)
  local bar = self.bar
  local rows = self.decor.rows[side]
  if not rows then
    rows = { fills = {}, borders = {}, edges = {} }
    self.decor.rows[side] = rows
  end

  local lengths = style ~= "none" and rowLengths(style, side, height, capWidth) or {}
  -- The inner corner is the bar's own edge; the cap grows outwards.
  local innerPoint = side == "left" and "TOPRIGHT" or "TOPLEFT"
  local barPoint = side == "left" and "TOPLEFT" or "TOPRIGHT"
  local direction = side == "left" and -1 or 1
  local outer = borderSize > 0 and border or fill

  for row = 1, math.max(height, #rows.fills, #rows.edges) do
    local exact = lengths[row]
    local fillPiece = pieceFor(rows, "fills", row, bar, "BACKGROUND")
    local borderPiece = pieceFor(rows, "borders", row, bar, "BORDER")
    local edgePiece = pieceFor(rows, "edges", row, bar, "BORDER")

    if not exact or exact <= 0.02 or row > height then
      fillPiece:Hide()
      borderPiece:Hide()
      edgePiece:Hide()
    else
      local whole = math.floor(exact + 1e-9)
      local fraction = exact - whole

      -- The border has to cover the step to the neighbouring rows, or a shallow
      -- slope would show gaps. The cap's top and bottom edges are border all the
      -- way across, like the bar's own top and bottom lines. Only the side that
      -- touches the bar has none.
      local borderWidth = 0
      if borderSize > 0 then
        if row <= borderSize or row > height - borderSize then
          borderWidth = whole
        else
          local step = math.max(math.abs(exact - (lengths[row - 1] or exact)), math.abs(exact - (lengths[row + 1] or exact)))
          borderWidth = math.min(whole, math.max(borderSize, math.ceil(step - 1e-9)))
        end
      end
      local fillWidth = whole - borderWidth
      local y = -(row - 1)

      place(fillPiece, innerPoint, bar, barPoint, 0, y, math.max(fillWidth, 0), fill, fill[4])
      fillPiece:SetShown(fillWidth > 0)

      place(borderPiece, innerPoint, bar, barPoint, direction * fillWidth, y, math.max(borderWidth, 0), border, border[4])
      borderPiece:SetShown(borderWidth > 0)

      place(edgePiece, innerPoint, bar, barPoint, direction * whole, y, 1, outer, outer[4] * fraction)
      edgePiece.coverage = fraction
      edgePiece:SetShown(fraction > 0.004)
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
