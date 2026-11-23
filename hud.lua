local Hud = {}
Hud.__index = Hud
local pi = math.pi
local tau = pi * 2
local cyan = {0.43, 0.87, 0.95}
local amber = {1.00, 0.72, 0.30}
local amberCore = {1.00, 0.90, 0.62}

-- HUD 불투명도 및 근접 페이드 설정 (필요 시 수치 조정)
Hud.BASE_ALPHA = 0.80            -- 기본 불투명도 (80%)
Hud.PROXIMITY_ALPHA = 0.10       -- 개체 근접 시 최소 불투명도 (10%)
Hud.RADIUS = 82                  -- 원형 HUD 외곽 반지름 (px)
Hud.BOTTOM_OFFSET = 105          -- 화면 하단에서 HUD 중심까지 거리 (px)
Hud.PROXIMITY_INNER_MARGIN = 18  -- HUD 외곽에서 이 거리 이내면 최소 불투명도 도달 (px)
Hud.PROXIMITY_OUTER_MARGIN = 96  -- HUD 외곽에서 이 거리부터 서서히 투명화 시작 (px)
Hud.FADE_SPEED = 12              -- 불투명도 전환 속도

-- 상단 체력 원형 아크 배치 (외곽 -> 내부: 실드 / 장갑 / 선체)
Hud.RING_OUTER_RADIUS = 70
Hud.RING_STEP = 11
Hud.RING_THICKNESS = 5
Hud.INNER_RADIUS = 39
Hud.VELOCITY_ARC_RADIUS = 70

-- EVE 온라인 스타일 중앙 커패시터(배터리) 설정
Hud.CAPACITOR_COLUMNS = 20       -- 360도 방사형 컬럼 수 (컬럼당 5%)
Hud.CAPACITOR_ROWS = 4           -- 반지름 방향 셀 층 수
Hud.CAPACITOR_INNER_RADIUS = 16  -- 가장 안쪽 셀 중심 반지름
Hud.CAPACITOR_ROW_STEP = 5.5     -- 셀 층 간격
Hud.CAPACITOR_CELL_THICKNESS = 4 -- 셀 반지름 두께
Hud.CAPACITOR_HUB_RADIUS = 11    -- 중앙 허브 반지름

local resources = {
    {"shield", "maxShield", "SHIELD", cyan, 10},
    {"armor", "maxArmor", "ARMOR", {0.91, 0.83, 0.64}, 10},
    {"hull", "maxHull", "HULL", {0.95, 0.54, 0.43}, 1},
}

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

local function fraction(value, maximum)
    if not maximum or maximum <= 0 then return 0 end
    return clamp((value or 0) / maximum, 0, 1)
end

local function arc(g, x, y, radius, start, sweep, value, color, thickness, alphaScale)
    g.setLineWidth(thickness)
    g.setColor(color[1], color[2], color[3], 0.15 * alphaScale)
    g.arc("line", "open", x, y, radius, start, start + sweep)
    -- LÖVE cannot draw an arc whose start and end angles are equal.
    if value > 0 then
        g.setColor(color[1], color[2], color[3], 0.96 * alphaScale)
        g.arc("line", "open", x, y, radius, start, start + sweep * value)
    end
end

local function drawEveCapacitor(g, x, y, batteryFraction, alpha, destroyed)
    -- Dark recessed capacitor housing
    g.setLineWidth(1)
    g.setColor(0.032, 0.056, 0.082, 0.34 * alpha)
    g.circle("fill", x, y, Hud.INNER_RADIUS)
    g.setColor(0.39, 0.68, 0.76, 0.30 * alpha)
    g.circle("line", x, y, Hud.INNER_RADIUS)

    local cols = Hud.CAPACITOR_COLUMNS
    local rows = Hud.CAPACITOR_ROWS
    local stepAngle = tau / cols
    local depletedCols = (1 - batteryFraction) * cols

    for col = 0, cols - 1 do
        -- Start at 12 o'clock (-pi/2) and step clockwise; depletion turns columns off clockwise from 12 o'clock.
        local baseStart = -pi / 2 + col * stepAngle
        local charge = destroyed and 0 or clamp((col + 1) - depletedCols, 0, 1)

        for row = 0, rows - 1 do
            local r = Hud.CAPACITOR_INNER_RADIUS + row * Hud.CAPACITOR_ROW_STEP
            -- Keep radial spoke gaps visually uniform across inner and outer rings.
            local pad = math.min(stepAngle * 0.28, 1.35 / r)
            local a0 = baseStart + pad
            local a1 = baseStart + stepAngle - pad
            if a1 > a0 then
                -- Unlit capacitor cell slot
                g.setLineWidth(Hud.CAPACITOR_CELL_THICKNESS)
                g.setColor(0.42, 0.31, 0.18, 0.22 * alpha)
                g.arc("line", "open", x, y, r, a0, a1)

                -- Lit golden-amber capacitor cell
                if charge > 0.001 then
                    local litAlpha = charge * alpha
                    g.setLineWidth(Hud.CAPACITOR_CELL_THICKNESS)
                    g.setColor(amber[1], amber[2], amber[3], 0.94 * litAlpha)
                    g.arc("line", "open", x, y, r, a0, a1)

                    g.setLineWidth(Hud.CAPACITOR_CELL_THICKNESS * 0.45)
                    g.setColor(amberCore[1], amberCore[2], amberCore[3], 0.78 * litAlpha)
                    g.arc("line", "open", x, y, r, a0, a1)
                end
            end
        end
    end

    -- Center mechanical hub (EVE-style recessed dark core)
    g.setLineWidth(1.2)
    g.setColor(0.022, 0.038, 0.058, 0.92 * alpha)
    g.circle("fill", x, y, Hud.CAPACITOR_HUB_RADIUS)
    g.setColor(0.62, 0.66, 0.68, 0.55 * alpha)
    g.circle("line", x, y, Hud.CAPACITOR_HUB_RADIUS)
    g.setLineWidth(1)
    g.setColor(0.32, 0.42, 0.48, 0.45 * alpha)
    g.circle("line", x, y, Hud.CAPACITOR_HUB_RADIUS - 3.5)
end

function Hud.new()
    local g = love.graphics
    return setmetatable({
        small = g.newFont(9),
        label = g.newFont(11),
        velocity = g.newFont(15),
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

    -- Circular HUD housing only.
    g.setColor(0.018, 0.035, 0.059, 0.96 * alpha)
    g.circle("fill", x, y, Hud.RADIUS)
    g.setColor(0.32, 0.56, 0.67, 0.42 * alpha)
    g.circle("line", x, y, Hud.RADIUS)

    -- Fine ticks frame the upper health arcs; the lower opening displays velocity.
    for i = 0, 24 do
        local angle = pi * 5 / 6 + pi * 4 / 3 * i / 24
        local inner = i % 4 == 0 and 74 or 76
        g.setColor(0.53, 0.72, 0.80, (i % 4 == 0 and 0.55 or 0.24) * alpha)
        g.line(x + math.cos(angle) * inner, y + math.sin(angle) * inner,
            x + math.cos(angle) * 79, y + math.sin(angle) * 79)
    end

    -- Upper concentric segmented arcs (shield -> armor -> hull).
    local first = (ship.maxShield or 0) > 0 and 1 or 2
    for i = first, #resources do
        local resource = resources[i]
        local maximum, unit = ship[resource[2]] or 0, resource[5]
        local value = maximum > 0 and clamp(ship[resource[1]] or 0, 0, maximum) or 0
        local color = resource[4]
        local segments = math.ceil(maximum / unit)
        if segments > 0 then
            local sweep = (pi * 4 / 3) / segments
            local gap = math.min(0.08, sweep * 0.18)
            local radius = Hud.RING_OUTER_RADIUS - (i - first) * Hud.RING_STEP
            for segment = 0, segments - 1 do
                local start = pi * 5 / 6 + segment * sweep + gap / 2
                local used = segment * unit
                local capacity = math.min(unit, maximum - used)
                arc(g, x, y, radius, start, sweep - gap, fraction(value - used, capacity), color, Hud.RING_THICKNESS, alpha)
            end
        end
    end

    -- Center core: EVE Online style 360-degree radial capacitor (depletes clockwise from 12 o'clock).
    drawEveCapacitor(g, x, y, battery, alpha, destroyed)

    -- Lower opening: velocity readout + velocity arc.
    local velArcInset = 0.08
    arc(g, x, y, Hud.VELOCITY_ARC_RADIUS, pi / 6 + velArcInset, pi * 2 / 3 - velArcInset * 2, velocity, cyan, 4, alpha)
    g.setFont(self.velocity)
    if (ship.boostLevel or 0) > 0 then
        g.setColor(0.62, 0.98, 1.00, alpha)
    else
        g.setColor(0.85, 0.97, 1.00, alpha)
    end
    g.printf(tostring(math.floor(speed + 0.5)), x - 40, y + 40, 80, "center")
    g.setFont(self.small)
    g.setColor(cyan[1], cyan[2], cyan[3], 0.95 * alpha)
    g.printf("PX/S", x - 36, y + 56, 72, "center")

    g.pop()
end

return Hud
