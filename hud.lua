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
Hud.RING_STEP = 8
Hud.RING_THICKNESS = 2.6
Hud.RING_GAP = math.rad(1.6)      -- 세그먼트 간 간격
Hud.TRACK_ALPHA = 0.13            -- 빈 세그먼트 트랙 불투명도

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

local function radialLine(g, x, y, r0, r1, angle)
    local c, s = math.cos(angle), math.sin(angle)
    g.line(x + c * r0, y + s * r0, x + c * r1, y + s * r1)
end

-- Soft glow: a wide faint pass under the crisp core stroke.
local function glowArc(g, x, y, radius, a0, a1, color, width, alpha)
    -- LÖVE cannot draw an arc whose start and end angles are equal.
    if a1 - a0 <= 1e-4 then return end
    g.setLineWidth(width * 2.6)
    setColor(g, color, 0.18 * alpha)
    g.arc("line", "open", x, y, radius, a0, a1)
    g.setLineWidth(width)
    setColor(g, color, alpha)
    g.arc("line", "open", x, y, radius, a0, a1)
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

function Hud.new()
    local g = love.graphics
    return setmetatable({
        tiny = g.newFont(7),
        cap = g.newFont(10),
        velocity = g.newFont(15),
        vignette = buildVignette(g, Hud.VIGNETTE_RADIUS),
        alpha = Hud.BASE_ALPHA,
    }, Hud)
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
    g.origin()
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

    -- Upper hairline segmented arcs (shield -> armor -> hull) with glow and a white position marker.
    local healthStart, healthSweep = pi * 5 / 6, pi * 4 / 3
    local first = (ship.maxShield or 0) > 0 and 1 or 2
    g.setFont(self.tiny)
    for i = first, #resources do
        local resource = resources[i]
        local maximum, unit = ship[resource[2]] or 0, resource[5]
        local value = maximum > 0 and clamp(ship[resource[1]] or 0, 0, maximum) or 0
        local color = resource[4]
        local segments = math.ceil(maximum / unit)
        local radius = Hud.RING_OUTER_RADIUS - (i - first) * Hud.RING_STEP
        if segments > 0 then
            local sweep = healthSweep / segments
            local gap = math.min(Hud.RING_GAP, sweep * 0.3)
            for segment = 0, segments - 1 do
                local a0 = healthStart + segment * sweep + gap / 2
                local a1 = a0 + sweep - gap
                local used = segment * unit
                local fill = fraction(value - used, math.min(unit, maximum - used))
                g.setLineWidth(Hud.RING_THICKNESS)
                setColor(g, color, Hud.TRACK_ALPHA * alpha)
                g.arc("line", "open", x, y, radius, a0, a1)
                if fill > 0 then
                    glowArc(g, x, y, radius, a0, a0 + (a1 - a0) * fill, color, Hud.RING_THICKNESS, alpha)
                end
            end
            local total = value / maximum
            if total > 0 and total < 1 then
                g.setLineWidth(0.9)
                setColor(g, white, alpha)
                radialLine(g, x, y, radius - 3, radius + 3, healthStart + healthSweep * total)
            end
        end
        -- Resource initial just past the right end of its arc.
        local la = math.rad(33)
        setColor(g, color, 0.85 * alpha)
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
