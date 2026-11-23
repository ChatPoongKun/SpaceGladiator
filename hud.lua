local Hud = {}
Hud.__index = Hud
local pi = math.pi
local cyan = {0.43, 0.87, 0.95}
local amber = {1.00, 0.72, 0.35}

-- HUD 불투명도 및 근접 페이드 설정 (필요 시 수치 조정)
Hud.BASE_ALPHA = 0.80            -- 기본 불투명도 (80%)
Hud.PROXIMITY_ALPHA = 0.10       -- 개체 근접 시 최소 불투명도 (10%)
Hud.RADIUS = 82                  -- 원형 HUD 외곽 반지름 (px)
Hud.BOTTOM_OFFSET = 105          -- 화면 하단에서 HUD 중심까지 거리 (px)
Hud.PROXIMITY_INNER_MARGIN = 18  -- HUD 외곽에서 이 거리 이내면 최소 불투명도 도달 (px)
Hud.PROXIMITY_OUTER_MARGIN = 96  -- HUD 외곽에서 이 거리부터 서서히 투명화 시작 (px)
Hud.FADE_SPEED = 12              -- 불투명도 전환 속도

-- 원형 게이지 링 배치 (외곽 -> 내부)
Hud.RING_OUTER_RADIUS = 71
Hud.RING_STEP = 9
Hud.RING_THICKNESS = 4.5
Hud.INNER_RADIUS = 37
Hud.VELOCITY_ARC_RADIUS = 71

local resources = {
    {"shield", "maxShield", "SHIELD", cyan, 10},
    {"armor", "maxArmor", "ARMOR", {0.91, 0.83, 0.64}, 10},
    {"hull", "maxHull", "HULL", {0.95, 0.54, 0.43}, 1},
    {"battery", "maxBattery", "BATTERY", amber, 10},
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

function Hud.new()
    local g = love.graphics
    return setmetatable({
        small = g.newFont(9),
        label = g.newFont(11),
        velocity = g.newFont(15),
        battery = g.newFont(28),
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
    local maxBattery = ship.maxBattery or 0
    local batteryValue = maxBattery > 0 and clamp(ship.battery or 0, 0, maxBattery) or 0
    g.push("all")
    g.origin()
    g.setShader()
    g.setScissor()
    g.setBlendMode("alpha")
    g.setLineStyle("smooth")
    g.setLineWidth(1)

    -- Circular HUD housing only (left numeric panel and right battery wing removed).
    g.setColor(0.018, 0.035, 0.059, 0.96 * alpha)
    g.circle("fill", x, y, Hud.RADIUS)
    g.setColor(0.32, 0.56, 0.67, 0.42 * alpha)
    g.circle("line", x, y, Hud.RADIUS)

    -- Fine ticks frame the upper resource arcs; the lower opening displays velocity.
    for i = 0, 24 do
        local angle = pi * 5 / 6 + pi * 4 / 3 * i / 24
        local inner = i % 4 == 0 and 75 or 77
        g.setColor(0.53, 0.72, 0.80, (i % 4 == 0 and 0.55 or 0.24) * alpha)
        g.line(x + math.cos(angle) * inner, y + math.sin(angle) * inner,
            x + math.cos(angle) * 80, y + math.sin(angle) * 80)
    end

    -- Concentric segmented arcs (shield -> armor -> hull -> battery).
    -- All arcs sweep clockwise from 8 o'clock to 4 o'clock so consumption drains counter-clockwise.
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

    -- Center readout: remaining battery in MJ.
    g.setLineWidth(1)
    g.setColor(0.055, 0.105, 0.145, 0.24 * alpha)
    g.circle("fill", x, y, Hud.INNER_RADIUS)
    g.setColor(0.39, 0.68, 0.76, 0.26 * alpha)
    g.circle("line", x, y, Hud.INNER_RADIUS)

    g.setFont(self.small)
    g.setColor(amber[1], amber[2], amber[3], 0.88 * alpha)
    g.printf("BATTERY", x - 36, y - 29, 72, "center")
    g.setFont(self.battery)
    if ship.isDestroyed and ship:isDestroyed() then
        g.setColor(0.56, 0.64, 0.70, 0.80 * alpha)
    else
        g.setColor(1.00, 0.90, 0.68, alpha)
    end
    g.printf(tostring(math.floor(batteryValue + 0.5)), x - 44, y - 20, 88, "center")
    g.setFont(self.label)
    g.setColor(amber[1], amber[2], amber[3], alpha)
    g.printf("MJ", x - 36, y + 12, 72, "center")

    -- Lower opening: velocity readout (replaces the old "% MAX" text) + velocity arc.
    local velArcInset = 0.08
    arc(g, x, y, Hud.VELOCITY_ARC_RADIUS, pi / 6 + velArcInset, pi * 2 / 3 - velArcInset * 2, velocity, cyan, 4, alpha)
    g.setFont(self.velocity)
    if (ship.boostLevel or 0) > 0 then
        g.setColor(0.62, 0.98, 1.00, alpha)
    else
        g.setColor(0.85, 0.97, 1.00, alpha)
    end
    g.printf(tostring(math.floor(speed + 0.5)), x - 40, y + 39, 80, "center")
    g.setFont(self.small)
    g.setColor(cyan[1], cyan[2], cyan[3], 0.95 * alpha)
    g.printf("PX/S", x - 36, y + 56, 72, "center")

    g.pop()
end

return Hud
