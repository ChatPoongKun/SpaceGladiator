local Hud = {}
Hud.__index = Hud
local pi = math.pi
local tau = pi * 2
local cyan = {0.43, 0.87, 0.95}
local dim = {0.56, 0.77, 0.82}
local amber = {1.00, 0.72, 0.30}
local amberCore = {1.00, 0.90, 0.62}
local white = {1, 1, 1}

-- HUD 불투명도 및 근접 페이드 설정 (필요 시 수치 조정)
Hud.BASE_ALPHA = 0.80            -- 기본 불투명도 (80%)
Hud.PROXIMITY_ALPHA = 0.10       -- 개체 근접 시 최소 불투명도 (10%)
Hud.RADIUS = 86                  -- 원형 HUD 외곽 반지름 (px, 점선 테두리 포함)
Hud.BOTTOM_OFFSET = 105          -- 화면 하단에서 HUD 중심까지 거리 (px)
Hud.PROXIMITY_INNER_MARGIN = 18  -- HUD 외곽에서 이 거리 이내면 최소 불투명도 도달 (px)
Hud.PROXIMITY_OUTER_MARGIN = 96  -- HUD 외곽에서 이 거리부터 서서히 투명화 시작 (px)
Hud.FADE_SPEED = 12              -- 불투명도 전환 속도

-- 글래스 비네트 배경 (A안): 중심은 투명, 가장자리만 어둡게
Hud.VIGNETTE_RADIUS = 90

-- 바깥 테두리 (D안): 점선 링 + 상단 얇은 아크 + 포인터
Hud.BORDER_DOT_RADIUS = 84
Hud.BORDER_DOT_SPACING = 2.6      -- 점선 간격 (px)
Hud.BORDER_ARC_RADIUS = 80

-- 상단 체력 원형 아크 (A안, 외곽 -> 내부: 실드 / 장갑 / 선체)
Hud.RING_OUTER_RADIUS = 72
Hud.RING_STEP = 10
Hud.HULL_RING_EXTRA_STEP = 2      -- 아머와 헐 사이 추가 간격 (px)
Hud.RING_THICKNESS = 5.0          -- 실드 / 장갑 칸 두께 (px)
Hud.HULL_RING_THICKNESS = 7.0     -- 선체(헐) 칸 두께 (실드/장갑보다 두껍게)
Hud.RING_CORNER_RADIUS = 1.0      -- 실드 / 장갑 칸 모서리 라운딩 반지름 (px)
Hud.HULL_CORNER_RADIUS = 1.2      -- 선체(헐) 칸 모서리 라운딩 반지름 (px)
Hud.RING_GAP = math.rad(3.5)      -- 실드 / 장갑 세그먼트 간 간격
Hud.HULL_RING_GAP = math.rad(9.0) -- 선체(헐) 세그먼트 간 간격 (눈에 잘 띄게)
Hud.TRACK_ALPHA = 0.16            -- 빈 세그먼트 트랙 불투명도
Hud.NEON_BLOOM_SIZE = 5.5         -- 기본 셀 외곽 빛번짐 확산 거리 (px)
Hud.NEON_BLOOM_ALPHA = 0.36       -- 기본 셀 외곽 빛번짐 강도
Hud.SHIELD_OUTWARD_BLOOM = 15.5   -- 실드 외부 방향 추가 빛번짐 확산 거리 (px)
Hud.SHIELD_OUTWARD_ALPHA = 0.56   -- 실드 외부 방향 빛번짐 강도

-- 하단 속도 눈금 스케일 (A안, 좌 -> 우)
Hud.VELOCITY_TICKS = 25
Hud.VELOCITY_TICK_OUTER = 79

-- 중앙 커패시터 도트 매트릭스 (D안)
Hud.CAPACITOR_COLUMNS = 24                 -- 360도 방사형 컬럼 수
Hud.CAPACITOR_ROW_RADII = {21, 27, 33}     -- 안쪽 -> 바깥 도트 행 반지름
Hud.CAPACITOR_DOT_RADII = {1.3, 1.6, 1.9}  -- 행별 도트 크기
Hud.CAPACITOR_ROWS = #Hud.CAPACITOR_ROW_RADII
Hud.CAPACITOR_INNER_RADIUS = Hud.CAPACITOR_ROW_RADII[1]
Hud.CAPACITOR_HUB_RADIUS = 14

local resources = {
    {"shield", "maxShield", "S", cyan, 10},
    {"armor", "maxArmor", "A", {0.91, 0.83, 0.64}, 10},
    {"hull", "maxHull", "H", {0.95, 0.54, 0.43}, 1},
}

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

local function fraction(value, maximum)
    if not maximum or maximum <= 0 then return 0 end
    return clamp((value or 0) / maximum, 0, 1)
end

local function setColor(g, color, a)
    g.setColor(color[1], color[2], color[3], a)
end

local function setBrightColor(g, color, whiteMix, a)
    local r = color[1] + (1 - color[1]) * whiteMix
    local gr = color[2] + (1 - color[2]) * whiteMix
    local b = color[3] + (1 - color[3]) * whiteMix
    g.setColor(r, gr, b, a)
end

local function radialLine(g, x, y, r0, r1, angle)
    local c, s = math.cos(angle), math.sin(angle)
    g.line(x + c * r0, y + s * r0, x + c * r1, y + s * r1)
end

-- Build outer/inner boundary samples and closed perimeter for a curved rounded-rectangle cell.
local function buildRoundedArcCell(x, y, radius, a0, a1, thickness, cornerRadius, outwardExtra)
    local span = a1 - a0
    if span <= 1e-4 or thickness <= 0 or radius <= 0 then return nil end
    local halfT = thickness * 0.5
    local arcLen = span * radius
    local cr = clamp(cornerRadius or (halfT * 0.85), 0.05, math.min(halfT * 0.92, arcLen * 0.44))
    local capAngle = cr / radius
    local capSteps = 5
    local midSteps = 10
    local outExtra = outwardExtra or 0

    local ox, oy, ix, iy, capWeight = {}, {}, {}, {}, {}
    local n = 0
    local function addSample(a, h, w)
        n = n + 1
        local c, s = math.cos(a), math.sin(a)
        local rOut = radius + h + outExtra * (0.28 + 0.72 * w)
        local rIn = math.max(1, radius - h)
        ox[n], oy[n] = x + c * rOut, y + s * rOut
        ix[n], iy[n] = x + c * rIn, y + s * rIn
        capWeight[n] = w
    end

    local flatHalf = halfT - cr
    for s = 0, capSteps do
        local theta = (s / capSteps) * (pi * 0.5)
        local u = cr * (1 - math.cos(theta))
        local w = math.sin(theta)
        local h = flatHalf + cr * w
        addSample(a0 + u / radius, h, w)
    end
    local midA0 = a0 + capAngle
    local midA1 = a1 - capAngle
    local midSpan = math.max(0, midA1 - midA0)
    for s = 1, midSteps - 1 do
        addSample(midA0 + midSpan * (s / midSteps), halfT, 1)
    end
    for s = 0, capSteps do
        local theta = (s / capSteps) * (pi * 0.5)
        local u = cr * (1 - math.sin(theta))
        local w = math.cos(theta)
        local h = flatHalf + cr * w
        addSample(a1 - u / radius, h, w)
    end

    local contour = {}
    for k = 1, n do
        contour[#contour + 1] = ox[k]
        contour[#contour + 1] = oy[k]
    end
    for k = n, 1, -1 do
        contour[#contour + 1] = ix[k]
        contour[#contour + 1] = iy[k]
    end
    contour[#contour + 1] = ox[1]
    contour[#contour + 1] = oy[1]
    if n >= 2 then
        contour[#contour + 1] = ox[2]
        contour[#contour + 1] = oy[2]
    end
    return { n = n, ox = ox, oy = oy, ix = ix, iy = iy, capWeight = capWeight, contour = contour }
end

local cellMesh = nil
local cellMeshCapacity = 0
local cellMeshVertices = {}

local function ensureCellMesh(g, count)
    if not cellMesh or count > cellMeshCapacity then
        cellMeshCapacity = math.max(128, count)
        cellMesh = g.newMesh(cellMeshCapacity, "strip", "stream")
    end
end

local function setMeshVertex(index, vx, vy, r, gr, b, a)
    local v = cellMeshVertices[index]
    if not v then
        v = { 0, 0, 0, 0, 1, 1, 1, 1 }
        cellMeshVertices[index] = v
    end
    v[1], v[2] = vx, vy
    v[5], v[6], v[7], v[8] = r, gr, b, a
end

local function drawCellMesh(g, count)
    ensureCellMesh(g, count)
    for k = count + 1, #cellMeshVertices do
        cellMeshVertices[k] = nil
    end
    cellMesh:setVertices(cellMeshVertices, 1, count)
    cellMesh:setDrawRange(1, count)
    g.draw(cellMesh)
end

local function fillRoundedArcCell(g, cell)
    if not cell or cell.n < 2 then return end
    local count = cell.n * 2
    local ox, oy, ix, iy = cell.ox, cell.oy, cell.ix, cell.iy
    for k = 1, cell.n do
        setMeshVertex(k * 2 - 1, ox[k], oy[k], 1, 1, 1, 1)
        setMeshVertex(k * 2, ix[k], iy[k], 1, 1, 1, 1)
    end
    drawCellMesh(g, count)
end

-- Draw a smooth hardware-interpolated gradient ring between two concentric cell contours.
local function drawBloomBand(g, innerCell, outerCell, color, whiteMix, inAlphaOut, inAlphaIn, outAlphaOut, outAlphaIn)
    if not innerCell or not outerCell or innerCell.n ~= outerCell.n or innerCell.n < 2 then return end
    local r = color[1] + (1 - color[1]) * whiteMix
    local gr = color[2] + (1 - color[2]) * whiteMix
    local b = color[3] + (1 - color[3]) * whiteMix
    local n = innerCell.n
    local idx = 0

    local function pushPair(x1, y1, a1, x2, y2, a2)
        idx = idx + 1
        setMeshVertex(idx, x1, y1, r, gr, b, a1)
        idx = idx + 1
        setMeshVertex(idx, x2, y2, r, gr, b, a2)
    end

    -- Outer arc (k = 1 .. n): faces outward away from HUD center
    for k = 1, n do
        local w = innerCell.capWeight[k] or 1
        local ia = inAlphaIn + (inAlphaOut - inAlphaIn) * (0.35 + 0.65 * w)
        local oa = outAlphaIn + (outAlphaOut - outAlphaIn) * (0.35 + 0.65 * w)
        pushPair(innerCell.ox[k], innerCell.oy[k], ia, outerCell.ox[k], outerCell.oy[k], oa)
    end
    -- Inner arc (k = n .. 1): faces inward toward HUD center
    for k = n, 1, -1 do
        pushPair(innerCell.ix[k], innerCell.iy[k], inAlphaIn, outerCell.ix[k], outerCell.iy[k], outAlphaIn)
    end
    -- Close loop back to ox[1], oy[1]
    local w1 = innerCell.capWeight[1] or 0
    local ia1 = inAlphaIn + (inAlphaOut - inAlphaIn) * (0.35 + 0.65 * w1)
    local oa1 = outAlphaIn + (outAlphaOut - outAlphaIn) * (0.35 + 0.65 * w1)
    pushPair(innerCell.ox[1], innerCell.oy[1], ia1, outerCell.ox[1], outerCell.oy[1], oa1)

    g.setColor(1, 1, 1, 1)
    drawCellMesh(g, idx)
end

local function strokeRoundedArcCell(g, cell, lineWidth)
    if not cell or #cell.contour < 6 then return end
    g.setLineWidth(lineWidth)
    g.line(cell.contour)
end

-- Empty cell slot with dark glass fill, center guide arc, and rounded border.
local function drawTrackCell(g, x, y, radius, a0, a1, color, thickness, cornerRadius, alpha)
    local cell = buildRoundedArcCell(x, y, radius, a0, a1, thickness, cornerRadius)
    if not cell then return end
    g.setColor(color[1] * 0.14, color[2] * 0.14, color[3] * 0.14, 0.30 * alpha)
    fillRoundedArcCell(g, cell)
    g.setLineWidth(0.9)
    setColor(g, color, Hud.TRACK_ALPHA * alpha)
    g.arc("line", "open", x, y, radius, a0, a1)
    setColor(g, color, (Hud.TRACK_ALPHA + 0.08) * alpha)
    strokeRoundedArcCell(g, cell, 1.05)
end

-- Lit cell with outward-bleeding neon sign bloom, rounded border, and hot inner filament.
local function drawNeonCell(g, x, y, radius, a0, a1, color, thickness, cornerRadius, alpha, kind)
    if a1 - a0 <= 1e-4 then return end
    local isHull = kind == "hull"
    local isShield = kind == "shield"
    local cell = buildRoundedArcCell(x, y, radius, a0, a1, thickness, cornerRadius, 0)
    if not cell then return end

    local baseBloom = (Hud.NEON_BLOOM_SIZE or 5.5) * (isHull and 1.15 or 1.0)
    local outwardExtra = isShield and (Hud.SHIELD_OUTWARD_BLOOM or 15.5) or (isHull and 1.8 or 1.2)
    local inPeak = (Hud.NEON_BLOOM_ALPHA or 0.36) * (isHull and 1.12 or 1.0) * alpha
    local outPeak = (isShield and (Hud.SHIELD_OUTWARD_ALPHA or 0.56) or ((Hud.NEON_BLOOM_ALPHA or 0.36) * 1.15)) * alpha

    local pad1 = baseBloom * 0.28
    local pad2 = baseBloom * 0.62
    local pad3 = baseBloom
    local angSpread = isShield and 1.35 or 1.0
    local aPad1 = (pad1 * angSpread) / radius
    local aPad2 = (pad2 * angSpread) / radius
    local aPad3 = (pad3 * angSpread) / radius

    local bloom1 = buildRoundedArcCell(
        x, y, radius, a0 - aPad1, a1 + aPad1,
        thickness + pad1 * 2, cornerRadius + pad1 * 0.9, outwardExtra * 0.24
    )
    local bloom2 = buildRoundedArcCell(
        x, y, radius, a0 - aPad2, a1 + aPad2,
        thickness + pad2 * 2, cornerRadius + pad2 * 0.9, outwardExtra * 0.58
    )
    local bloom3 = buildRoundedArcCell(
        x, y, radius, a0 - aPad3, a1 + aPad3,
        thickness + pad3 * 2, cornerRadius + pad3 * 0.9, outwardExtra
    )

    -- 1. Outward-bleeding neon sign bloom (3-stage smooth vertex-alpha gradient)
    local prevBlend, prevAlphaMode = g.getBlendMode()
    g.setBlendMode("add")
    drawBloomBand(g, cell, bloom1, color, 0.22, outPeak, inPeak, outPeak * 0.52, inPeak * 0.42)
    drawBloomBand(g, bloom1, bloom2, color, 0.10, outPeak * 0.52, inPeak * 0.42, outPeak * 0.18, inPeak * 0.12)
    drawBloomBand(g, bloom2, bloom3, color, 0.0, outPeak * 0.18, inPeak * 0.12, 0, 0)
    g.setBlendMode(prevBlend, prevAlphaMode)

    -- 2. Main colored cell body
    setColor(g, color, (isHull and 0.84 or 0.78) * alpha)
    fillRoundedArcCell(g, cell)

    -- 3. Hot inner neon core filament
    local coreInset = math.min(thickness * 0.27, 1.8)
    local coreA = coreInset / radius
    if a1 - a0 > coreA * 2.2 then
        local coreCell = buildRoundedArcCell(
            x, y, radius,
            a0 + coreA, a1 - coreA,
            math.max(1.2, thickness - coreInset * 2.1),
            math.max(0.4, cornerRadius - coreInset * 0.7)
        )
        if coreCell then
            setBrightColor(g, color, 0.62, (isHull and 0.65 or 0.54) * alpha)
            fillRoundedArcCell(g, coreCell)
        end
    end

    -- 4. Glowing rounded neon tube border
    g.setBlendMode("add")
    setBrightColor(g, color, 0.30, (isShield and 0.36 or (isHull and 0.32 or 0.26)) * alpha)
    strokeRoundedArcCell(g, cell, isHull and 2.8 or 2.4)
    g.setBlendMode(prevBlend, prevAlphaMode)

    setBrightColor(g, color, 0.50, 0.97 * alpha)
    strokeRoundedArcCell(g, cell, isHull and 1.45 or 1.2)
end

local function glowLine(g, x, y, r0, r1, angle, color, width, alpha)
    g.setLineWidth(width * 3)
    setColor(g, color, 0.18 * alpha)
    radialLine(g, x, y, r0, r1, angle)
    g.setLineWidth(width)
    setColor(g, color, alpha)
    radialLine(g, x, y, r0, r1, angle)
end

-- Radial vignette mesh: transparent glass core darkening toward the rim, fading out past it.
local function buildVignette(g, radius)
    local stops = {{0, 0.15}, {0.35, 0.15}, {0.8, 0.7}, {1, 0}}
    local cr, cg, cb = 0.016, 0.063, 0.11
    local segments = 64
    local vertices = {}
    for s = 1, #stops - 1 do
        local r0, a0 = stops[s][1] * radius, stops[s][2]
        local r1, a1 = stops[s + 1][1] * radius, stops[s + 1][2]
        for i = 0, segments - 1 do
            local t0, t1 = tau * i / segments, tau * (i + 1) / segments
            local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
            local p00 = {c0 * r0, s0 * r0, 0, 0, cr, cg, cb, a0}
            local p01 = {c1 * r0, s1 * r0, 0, 0, cr, cg, cb, a0}
            local p10 = {c0 * r1, s0 * r1, 0, 0, cr, cg, cb, a1}
            local p11 = {c1 * r1, s1 * r1, 0, 0, cr, cg, cb, a1}
            vertices[#vertices + 1] = p00
            vertices[#vertices + 1] = p10
            vertices[#vertices + 1] = p11
            vertices[#vertices + 1] = p00
            vertices[#vertices + 1] = p11
            vertices[#vertices + 1] = p01
        end
    end
    return g.newMesh(vertices, "triangles", "static")
end

-- D안 바깥 테두리: 점선 링, 상단 얇은 아크와 양끝 점, 12시 방향 포인터.
local function drawBorder(g, x, y, alpha)
    local dotR = Hud.BORDER_DOT_RADIUS
    local count = math.floor(tau * dotR / Hud.BORDER_DOT_SPACING)
    setColor(g, cyan, 0.55 * alpha)
    for i = 0, count - 1 do
        local a = tau * i / count
        g.circle("fill", x + math.cos(a) * dotR, y + math.sin(a) * dotR, 0.5, 6)
    end

    local arcR = Hud.BORDER_ARC_RADIUS
    g.setLineWidth(0.6)
    setColor(g, dim, 0.35 * alpha)
    g.arc("line", "open", x, y, arcR, math.rad(160), math.rad(380))
    setColor(g, cyan, alpha)
    for _, deg in ipairs({210, 330}) do
        local a = math.rad(deg)
        g.circle("fill", x + math.cos(a) * arcR, y + math.sin(a) * arcR, 1, 8)
    end

    -- Downward-pointing triangle at 12 o'clock (a 3-segment circle rotated to aim inward).
    g.push()
    g.translate(x, y - 82.2)
    g.rotate(pi / 2)
    setColor(g, cyan, 0.9 * alpha)
    g.circle("fill", 0, 0, 2.8, 3)
    g.pop()
end

-- D안 커패시터: 컬럼 x 행 도트 매트릭스. 12시부터 시계방향으로 소등된다.
local function drawCapacitor(g, x, y, batteryFraction, alpha, destroyed, font)
    local cols = Hud.CAPACITOR_COLUMNS
    local stepAngle = tau / cols
    local depletedCols = (1 - batteryFraction) * cols

    for col = 0, cols - 1 do
        local angle = -pi / 2 + (col + 0.5) * stepAngle
        local c, s = math.cos(angle), math.sin(angle)
        local charge = destroyed and 0 or clamp((col + 1) - depletedCols, 0, 1)
        for row = 1, Hud.CAPACITOR_ROWS do
            local r = Hud.CAPACITOR_ROW_RADII[row]
            local dot = Hud.CAPACITOR_DOT_RADII[row]
            local px, py = x + c * r, y + s * r
            if charge > 0.001 then
                setColor(g, amber, 0.25 * charge * alpha)
                g.circle("fill", px, py, dot + 1.2)
                setColor(g, amber, (0.35 + 0.65 * charge) * alpha)
                g.circle("fill", px, py, dot)
            else
                g.setLineWidth(0.5)
                setColor(g, amber, 0.25 * alpha)
                g.circle("line", px, py, dot)
            end
        end
    end

    -- Hub with crosshair ticks and percentage readout.
    local hub = Hud.CAPACITOR_HUB_RADIUS
    g.setColor(0.012, 0.031, 0.055, 0.9 * alpha)
    g.circle("fill", x, y, hub)
    g.setLineWidth(0.6)
    setColor(g, amber, 0.45 * alpha)
    g.circle("line", x, y, hub)
    setColor(g, amber, 0.6 * alpha)
    for i = 0, 3 do
        radialLine(g, x, y, hub, hub + 2.5, i * pi / 2)
    end
    g.setFont(font)
    setColor(g, amberCore, alpha)
    local percent = destroyed and 0 or math.floor(batteryFraction * 100 + 0.5)
    g.printf(tostring(percent), x - hub, y - font:getHeight() / 2, hub * 2, "center")
end

function Hud.new(fontDpiScale)
    local g = love.graphics
    local self = setmetatable({
        fontDpiScale = nil,
        vignette = buildVignette(g, Hud.VIGNETTE_RADIUS),
        alpha = Hud.BASE_ALPHA,
    }, Hud)
    self:setFontScale(fontDpiScale or 1)
    return self
end

function Hud:setFontScale(dpiScale)
    local scale = math.max(1, dpiScale or 1)
    if self.fontDpiScale == scale and self.tiny and self.cap and self.velocity then return end
    local g = love.graphics
    self.fontDpiScale = scale
    self.tiny = g.newFont(7, "normal", scale)
    self.cap = g.newFont(10, "normal", scale)
    self.velocity = g.newFont(15, "normal", scale)
end

function Hud:reset()
    self.alpha = Hud.BASE_ALPHA
end

function Hud:center(width, height)
    return math.floor(width / 2), height - Hud.BOTTOM_OFFSET
end

function Hud:computeTargetAlpha(context, width, height)
    if not context or not width or not height then return Hud.BASE_ALPHA end
    local hx, hy = self:center(width, height)
    local hudRadius = Hud.RADIUS
    local inner = Hud.PROXIMITY_INNER_MARGIN
    local outer = math.max(inner + 1e-4, Hud.PROXIMITY_OUTER_MARGIN)
    local camera = context.camera
    local zoom = (camera and camera.zoom) or 1
    local proximity = 0

    local function toScreen(wx, wy)
        if camera and camera.worldToScreen then
            return camera:worldToScreen(wx, wy, width, height)
        end
        return wx, wy
    end

    local function considerCircle(sx, sy, radius)
        if proximity >= 1 then return end
        local dx, dy = sx - hx, sy - hy
        local dist = math.sqrt(dx * dx + dy * dy)
        local gap = dist - (hudRadius + (radius or 0))
        if gap <= inner then
            proximity = 1
        elseif gap < outer then
            local factor = 1 - (gap - inner) / (outer - inner)
            if factor > proximity then proximity = factor end
        end
    end

    local function considerWorldCircle(wx, wy, worldRadius)
        local sx, sy = toScreen(wx, wy)
        considerCircle(sx, sy, (worldRadius or 0) * zoom)
    end

    local function considerWorldRect(wx, wy, rw, rh)
        local sx, sy = toScreen(wx, wy)
        local halfW, halfH = rw * 0.5 * zoom, rh * 0.5 * zoom
        local cx = clamp(hx, sx - halfW, sx + halfW)
        local cy = clamp(hy, sy - halfH, sy + halfH)
        considerCircle(cx, cy, 0)
    end

    -- 1. Player ship (including wrapped ghost near the bottom edge)
    local ship = context.ship
    if ship and (not ship.isDestroyed or not ship:isDestroyed()) then
        local shipRadius = ship.hitRadius and ship:hitRadius() or (ship.radius or 23)
        considerWorldCircle(ship.x, ship.y, shipRadius)
        local arenaH = context.arenaHeight
        if arenaH and ship.y < 80 then
            considerWorldCircle(ship.x, ship.y + arenaH, shipRadius)
        end
    end

    -- 2. Enemies and enemy projectiles
    local enemies = context.enemies
    if enemies then
        if enemies.items then
            for _, enemy in ipairs(enemies.items) do
                considerWorldCircle(enemy.x, enemy.y, enemy.radius or 20)
                if proximity >= 1 then break end
            end
        end
        if proximity < 1 and enemies.fire and enemies.fire.shots then
            for _, shot in ipairs(enemies.fire.shots) do
                local profile = shot.profile
                local r = (profile and profile.radius or 4) + 6
                considerWorldCircle(shot.x, shot.y, r)
                if proximity < 1 and profile and profile.trail and shot.vx and shot.vy then
                    local speed = math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy)
                    if speed > 1e-4 then
                        local trail = math.min(profile.trail, profile.radius + speed * (shot.age or 0))
                        local tailX = shot.x - (shot.vx / speed) * trail
                        local tailY = shot.y - (shot.vy / speed) * trail
                        considerWorldCircle(tailX, tailY, r * 0.6)
                    end
                end
                if proximity >= 1 then break end
            end
        end
    end

    -- 3. Player projectiles / missiles and blasts
    local turret = context.turret
    if proximity < 1 and turret then
        if turret.missiles then
            for _, m in ipairs(turret.missiles) do
                considerWorldCircle(m.x, m.y, 10)
                if proximity >= 1 then break end
            end
        end
        if proximity < 1 and turret.explosions then
            for _, exp in ipairs(turret.explosions) do
                considerWorldCircle(exp.x, exp.y, exp.radius or 24)
                if proximity >= 1 then break end
            end
        end
    end

    -- 4. Stage transition warp gates & reward cards
    local warpGates = context.warpGates
    if proximity < 1 and warpGates and warpGates.gates then
        local w = warpGates.arenaW or context.arenaWidth or width
        local h = warpGates.arenaH or context.arenaHeight or height
        local cardW, cardH = 196, 62
        for _, gate in ipairs(warpGates.gates) do
            considerWorldCircle(gate.x, gate.y, (gate.width or 116) * 0.5)
            local horizontal = (gate.edge == "top" or gate.edge == "bottom")
            local anchorDistX = horizontal and 0 or 118
            local anchorDistY = horizontal and 66 or 0
            local cardCx = clamp(gate.x - (gate.dirX or 0) * anchorDistX, cardW * 0.5 + 14, w - cardW * 0.5 - 14)
            local cardCy = clamp(gate.y - (gate.dirY or 0) * anchorDistY, cardH * 0.5 + 12, h - cardH * 0.5 - 12)
            considerWorldRect(cardCx, cardCy, cardW, cardH)
            if proximity >= 1 then break end
        end
    end

    local eased = proximity * proximity * (3 - 2 * proximity)
    return Hud.BASE_ALPHA + (Hud.PROXIMITY_ALPHA - Hud.BASE_ALPHA) * eased
end

function Hud:update(dt, context, width, height)
    local target = self:computeTargetAlpha(context, width, height)
    if not dt or dt <= 0 or self.alpha == nil then
        self.alpha = target
        return self.alpha
    end
    local blend = 1 - math.exp(-Hud.FADE_SPEED * dt)
    self.alpha = self.alpha + (target - self.alpha) * blend
    return self.alpha
end

function Hud:draw(ship, width, height, time)
    local g = love.graphics
    local x, y = self:center(width, height)
    local alpha = clamp(self.alpha or Hud.BASE_ALPHA, 0, 1)
    local speed = math.max(0, ship:speed())
    local velocity = fraction(speed, ship.maxSpeed)
    local battery = fraction(ship.battery, ship.maxBattery)
    local destroyed = ship.isDestroyed and ship:isDestroyed() or false
    g.push("all")
    g.setShader()
    g.setScissor()
    g.setBlendMode("alpha")
    g.setLineStyle("smooth")
    g.setLineWidth(1)

    -- Glass vignette backdrop + hairline housing ring.
    g.setColor(1, 1, 1, alpha)
    g.draw(self.vignette, x, y)
    g.setLineWidth(0.6)
    setColor(g, dim, 0.28 * alpha)
    g.circle("line", x, y, 82)

    drawBorder(g, x, y, alpha)

    -- Upper rounded segmented arcs (shield -> armor -> hull) with neon sign bloom.
    local healthStart, healthSweep = pi * 5 / 6, pi * 4 / 3
    local first = (ship.maxShield or 0) > 0 and 1 or 2
    g.setFont(self.tiny)
    for i = first, #resources do
        local resource = resources[i]
        local isHull = resource[1] == "hull"
        local thickness = isHull and Hud.HULL_RING_THICKNESS or Hud.RING_THICKNESS
        local cornerRadius = isHull and Hud.HULL_CORNER_RADIUS or Hud.RING_CORNER_RADIUS
        local baseGap = isHull and Hud.HULL_RING_GAP or Hud.RING_GAP
        local radius = Hud.RING_OUTER_RADIUS - (i - first) * Hud.RING_STEP - (isHull and (Hud.HULL_RING_EXTRA_STEP or 0) or 0)

        local maximum, unit = ship[resource[2]] or 0, resource[5]
        local value = maximum > 0 and clamp(ship[resource[1]] or 0, 0, maximum) or 0
        local color = resource[4]
        local segments = math.ceil(maximum / unit)
        if segments > 0 then
            local sweep = healthSweep / segments
            local gap = math.min(baseGap, sweep * 0.35)
            for segment = 0, segments - 1 do
                local a0 = healthStart + segment * sweep + gap / 2
                local a1 = a0 + sweep - gap
                local used = segment * unit
                local fill = fraction(value - used, math.min(unit, maximum - used))
                drawTrackCell(g, x, y, radius, a0, a1, color, thickness, cornerRadius, alpha)
                if fill > 0 then
                    drawNeonCell(g, x, y, radius, a0, a0 + (a1 - a0) * fill, color, thickness, cornerRadius, alpha, resource[1])
                end
            end
            local total = value / maximum
            if not isHull and total > 0 and total < 1 then
                local markerHalf = thickness * 0.5 + 1.2
                g.setLineWidth(0.9)
                setColor(g, white, alpha)
                radialLine(g, x, y, radius - markerHalf, radius + markerHalf, healthStart + healthSweep * total)
            end
        end
        -- Resource initial just past the right end of its arc.
        local la = math.rad(33)
        setColor(g, color, 0.88 * alpha)
        g.print(resource[3], x + math.cos(la) * radius + 3, y + math.sin(la) * radius - self.tiny:getHeight() / 2)
    end

    -- Center core: dot-matrix capacitor (depletes clockwise from 12 o'clock).
    drawCapacitor(g, x, y, battery, alpha, destroyed, self.cap)

    -- Lower opening: left-to-right velocity tick scale + readout.
    local ticks = Hud.VELOCITY_TICKS
    local litTicks = math.floor(velocity * (ticks - 1) + 0.5)
    local outer = Hud.VELOCITY_TICK_OUTER
    for k = 0, ticks - 1 do
        local angle = math.rad(140 - k * 100 / (ticks - 1))
        local major = k % 6 == 0
        local inner = major and outer - 6 or outer - 4
        if k <= litTicks and velocity > 0 then
            glowLine(g, x, y, inner, outer, angle, cyan, major and 1.1 or 0.8, alpha)
        else
            g.setLineWidth(0.7)
            setColor(g, dim, 0.25 * alpha)
            radialLine(g, x, y, inner, outer, angle)
        end
    end
    g.setFont(self.velocity)
    if (ship.boostLevel or 0) > 0 then
        g.setColor(0.62, 0.98, 1.00, alpha)
    else
        g.setColor(0.90, 0.98, 1.00, alpha)
    end
    g.printf(tostring(math.floor(speed + 0.5)), x - 40, y + 43, 80, "center")
    g.setFont(self.tiny)
    setColor(g, cyan, 0.95 * alpha)
    g.printf("PX/S", x - 36, y + 61, 72, "center")

    g.pop()
end

return Hud
