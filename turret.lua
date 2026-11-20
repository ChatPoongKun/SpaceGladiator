local Turret = {}
Turret.__index = Turret
local tau = 2 * math.pi
local muzzleLength = 22
local blastRadius = 90
local rocketAverageSpeed = 600
local rocketMaxBend = 38
local beamLifetime = 0.10
local beamImpactLifetime = 0.22
local explosionColors = { glow = {1, 0.38, 0.10}, ring = {1, 0.76, 0.32}, core = {1, 0.94, 0.66} }
local beamImpactColors = { glow = {0.12, 0.68, 1}, ring = {0.30, 0.92, 1}, core = {0.83, 0.98, 1} }

Turret.turnSpeed = tau
Turret.missileSpeed = 900
Turret.missileLifetime = 600 / 900
Turret.fireInterval = 0.18
Turret.explosionLifetime = 0.45

function Turret.new(initialAngle)
    return setmetatable({
        angle = (initialAngle or 0) % tau,
        weapon = 1, launchSide = 1, cooldown = 0, missiles = {}, explosions = {},
    }, Turret)
end

local function updateRocketPose(rocket)
    if rocket.lifetime == 0 then
        rocket.vx, rocket.vy, rocket.speed = 0, 0, 0
        return
    end
    local t = rocket.age / rocket.lifetime
    local dx, dy = rocket.targetX - rocket.startX, rocket.targetY - rocket.startY
    -- Quadratic forward travel builds speed while the sideways offset fades back to zero.
    local bend = math.sin(math.pi * t)
    rocket.x = rocket.startX + dx * t * t + rocket.bendX * bend
    rocket.y = rocket.startY + dy * t * t + rocket.bendY * bend
    local bendRate = math.pi * math.cos(math.pi * t)
    rocket.vx = (2 * t * dx + rocket.bendX * bendRate) / rocket.lifetime
    rocket.vy = (2 * t * dy + rocket.bendY * bendRate) / rocket.lifetime
    rocket.speed = math.sqrt(rocket.vx ^ 2 + rocket.vy ^ 2)
end

function Turret:fire(ship, targetX, targetY, enemies, frameFraction, camera, width, height)
    local dx, dy = math.sin(self.angle), -math.cos(self.angle)
    local x, y = ship.x + dx * muzzleLength, ship.y + dy * muzzleLength
    if self.weapon == 3 then
        local hitX, hitY
        if enemies then
            local entry, exit = camera:clipRay(x, y, dx, dy, width, height)
            if exit then
                -- Freeze enemies at the shot time while tracing the visible segment.
                local t = frameFraction or 1
                hitX, hitY = enemies:hitSegment(x + dx * entry, y + dy * entry,
                    x + dx * exit, y + dy * exit, t, t)
            end
        end
        if hitX then
            self.explosions[#self.explosions + 1] = {
                x = hitX, y = hitY, radius = 28, age = 0, lifetime = beamImpactLifetime,
                colors = beamImpactColors,
            }
        end
        self.beam = { x = x, y = y, dx = dx, dy = dy, hitX = hitX, hitY = hitY, age = 0 }
        return self.beam
    end

    local missile = {
        x = x, y = y, startX = x, startY = y,
        owner = ship, angle = self.angle, distance = 0, age = 0,
    }
    if self.weapon == 2 then
        local distance = math.sqrt((targetX - x) ^ 2 + (targetY - y) ^ 2)
        local bend = self.launchSide * math.min(rocketMaxBend, distance * 0.18)
        self.launchSide = -self.launchSide
        missile.bendX, missile.bendY = -dy * bend, dx * bend
        missile.targetX, missile.targetY = targetX, targetY
        missile.lifetime = distance / rocketAverageSpeed
        updateRocketPose(missile)
    else
        missile.vx, missile.vy = dx * self.missileSpeed + ship.vx, dy * self.missileSpeed + ship.vy
        missile.speed = math.sqrt(missile.vx ^ 2 + missile.vy ^ 2)
        missile.lifetime = self.missileLifetime
    end
    self.missiles[#self.missiles + 1] = missile
    return missile
end

function Turret:update(dt, ship, mouseWorldX, mouseWorldY, firing, enemies, camera, width, height)
    dt = math.max(0, dt)
    local dx, dy = mouseWorldX - ship.x, mouseWorldY - ship.y
    if dx ~= 0 or dy ~= 0 then
        local target = math.atan2(dx, -dy)
        if self.weapon == 1 then
            local delta = (target - self.angle + math.pi) % tau - math.pi
            local limit = self.turnSpeed * dt
            self.angle = (self.angle + math.max(-limit, math.min(limit, delta))) % tau
        else
            self.angle = target % tau
        end
    end

    -- Split at shot times so held fire keeps its cadence at any frame rate.
    local remaining = dt
    repeat
        local step = firing and math.min(remaining, self.cooldown) or remaining
        if self.beam then
            self.beam.age = self.beam.age + step
            if self.beam.age >= beamLifetime then self.beam = nil end
        end
        for i = #self.explosions, 1, -1 do
            local explosion = self.explosions[i]
            explosion.age = explosion.age + step
            if explosion.age >= explosion.lifetime then
                table.remove(self.explosions, i)
            end
        end
        for i = #self.missiles, 1, -1 do
            local missile = self.missiles[i]
            local oldX, oldY = missile.x, missile.y
            local flightTime = math.min(step, missile.lifetime - missile.age)
            local elapsed = missile.age + step
            missile.age = math.min(missile.lifetime, elapsed)
            if missile.targetX then
                updateRocketPose(missile)
            else
                missile.distance = missile.speed * missile.age
                missile.x = missile.startX + missile.vx * missile.age
                missile.y = missile.startY + missile.vy * missile.age
            end
            local hitX, hitY, hitTime
            if enemies and not missile.targetX then
                local frameStart = dt > 0 and (dt - remaining) / dt or 0
                local frameEnd = dt > 0 and (dt - remaining + flightTime) / dt or 0
                hitX, hitY, hitTime = enemies:hitSegment(oldX, oldY, missile.x, missile.y, frameStart, frameEnd)
            end
            if hitX or elapsed >= missile.lifetime then
                local age = hitX and step - flightTime * hitTime or elapsed - missile.lifetime
                local x, y = missile.targetX or hitX or missile.x, missile.targetY or hitY or missile.y
                if enemies and missile.targetX then
                    local fraction = dt > 0 and (dt - remaining + flightTime) / dt or 0
                    enemies:hitArea(x, y, blastRadius, fraction)
                end
                if age < self.explosionLifetime then
                    self.explosions[#self.explosions + 1] = {
                        x = x, y = y, radius = missile.targetX and blastRadius,
                        age = age, lifetime = self.explosionLifetime,
                    }
                end
                table.remove(self.missiles, i)
            end
        end
        remaining = remaining - step
        self.cooldown = math.max(0, self.cooldown - step)
        if firing and self.cooldown == 0 then
            self:fire(ship, mouseWorldX, mouseWorldY, enemies, dt > 0 and (dt - remaining) / dt or 0,
                camera, width, height)
            self.cooldown = self.fireInterval
        end
    until remaining <= 0
end

function Turret:draw(ship, time, camera, width, height)
    local g = love.graphics
    g.push("all")
    for _, missile in ipairs(self.missiles) do
        local speed = missile.speed > 0 and missile.speed or 1
        local dx, dy = missile.vx / speed, missile.vy / speed
        g.setLineWidth(3)
        g.setColor(1, 0.42, 0.12, 0.45)
        if missile.targetX then
            local trail = math.min(32, missile.speed * math.min(0.03, missile.age))
            if trail > 0 then
                g.line(missile.x, missile.y, missile.x - dx * trail, missile.y - dy * trail)
            end
        else
            local tailX, tailY = missile.owner.x - missile.x, missile.owner.y - missile.y
            local distance = math.sqrt(tailX * tailX + tailY * tailY)
            if distance > 0 then
                local trail = math.min(24, missile.distance, distance)
                g.line(missile.x, missile.y,
                    missile.x + tailX / distance * trail, missile.y + tailY / distance * trail)
            end
        end
        g.setLineWidth(2)
        g.setColor(1, 0.87, 0.46, 1)
        g.line(missile.x - dx * 6, missile.y - dy * 6, missile.x, missile.y)
        if missile.targetX then
            g.setColor(1, 0.34, 0.20, 1)
            g.polygon("fill", missile.x + dx * 7, missile.y + dy * 7,
                missile.x - dx * 5 - dy * 4, missile.y - dy * 5 + dx * 4,
                missile.x - dx * 5 + dy * 4, missile.y - dy * 5 - dx * 4)
        else
            g.circle("fill", missile.x, missile.y, 2)
        end
    end
    local beam = self.beam
    if beam then
        local x, y = beam.hitX, beam.hitY
        if not x then
            -- Recalculate the endpoint as the viewport pans, zooms or resizes.
            local _, exit = camera:clipRay(beam.x, beam.y, beam.dx, beam.dy, width, height)
            if exit then x, y = beam.x + beam.dx * exit, beam.y + beam.dy * exit end
        end
        if x then
            local alpha = 1 - beam.age / beamLifetime
            g.setColor(0.12, 0.82, 1, alpha * 0.4)
            g.setLineWidth(6)
            g.line(beam.x, beam.y, x, y)
            g.setColor(0.76, 0.98, 1, alpha)
            g.setLineWidth(2)
            g.line(beam.x, beam.y, x, y)
        end
    end
    for _, explosion in ipairs(self.explosions) do
        local progress = explosion.age / explosion.lifetime
        local radius, alpha = 5 + progress * ((explosion.radius or 41) - 5), 1 - progress
        local colors = explosion.colors or explosionColors
        local glow, ring, core = colors.glow, colors.ring, colors.core
        g.setColor(glow[1], glow[2], glow[3], alpha * 0.25)
        g.circle("fill", explosion.x, explosion.y, radius)
        g.setColor(ring[1], ring[2], ring[3], alpha)
        g.setLineWidth(2 * alpha + 0.5)
        g.circle("line", explosion.x, explosion.y, radius)
        g.setColor(core[1], core[2], core[3], alpha)
        g.circle("fill", explosion.x, explosion.y, 8 * alpha)
        for i = 1, 8 do
            local dx, dy = math.sin(i * tau / 8), -math.cos(i * tau / 8)
            g.line(explosion.x + dx * radius * 0.7, explosion.y + dy * radius * 0.7,
                explosion.x + dx * (radius + 5), explosion.y + dy * (radius + 5))
        end
    end

    g.push()
    g.translate(ship.x, ship.y)
    g.rotate(self.angle)
    g.setColor(0.06, 0.11, 0.16, 1)
    g.circle("fill", 0, 0, 8)
    g.setColor(0.92, 0.69, 0.30, 1)
    g.setLineWidth(1.2)
    g.circle("line", 0, 0, 7)
    g.setColor(0.14, 0.22, 0.27, 1)
    g.rectangle("fill", -2.5, -muzzleLength, 5, muzzleLength)
    g.setColor(1, 0.82, 0.44, 1)
    g.rectangle("line", -2.5, -muzzleLength, 5, muzzleLength)
    g.setColor(1, 0.90, 0.59, 0.8 + math.sin((time or 0) * 7) * 0.15)
    g.circle("fill", 0, 0, 3)
    g.pop()
    g.pop()
end

return Turret
