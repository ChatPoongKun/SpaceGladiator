local Sfx = require("sfx")
local Turret = {}
Turret.__index = Turret
local tau = 2 * math.pi
local muzzleLength = 22
local blastRadius = 90
local rocketAverageSpeed = 600
local rocketMaxBend = 38
local beamLifetime = 0.10
local beamImpactLifetime = 0.22
local projectileSpread = math.rad(5)
local projectileOffsets = {0, -projectileSpread, projectileSpread}
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
        beams = {}, burstQueue = {},
        shotsFired = 0, shotsHit = 0,
    }, Turret)
end

local function buildOffsets(baseCount, extraCount, baseSpread, extraSpreadRad)
    local total = math.max(1, baseCount + (extraCount or 0))
    if total == 1 then return { 0 } end
    local step = baseSpread + (extraSpreadRad or 0) * 0.25
    local offsets = {}
    local half = (total - 1) * 0.5
    for i = 0, total - 1 do
        offsets[#offsets + 1] = (i - half) * step
    end
    return offsets
end

local function nearestEnemy(enemies, x, y, excludeX, excludeY, camera, width, height)
    if not enemies or not enemies.items then return nil end
    local best, bestDistSq = nil, math.huge
    for _, enemy in ipairs(enemies.items) do
        if not enemies.isOnScreen or enemies:isOnScreen(enemy.x, enemy.y, camera, width, height) then
            local dx, dy = enemy.x - x, enemy.y - y
            local dSq = dx * dx + dy * dy
            if dSq > 16 then
                if not excludeX or ((enemy.x - excludeX) ^ 2 + (enemy.y - excludeY) ^ 2) > 400 then
                    if dSq < bestDistSq then
                        best, bestDistSq = enemy, dSq
                    end
                end
            end
        end
    end
    return best
end

local function updateRocketPose(rocket, camera, width, height)
    if rocket.lifetime == 0 then
        rocket.x, rocket.y = camera:screenToWorld(rocket.targetScreenX, rocket.targetScreenY, width, height)
        rocket.vx, rocket.vy, rocket.speed = 0, 0, 0
        return
    end
    local t = rocket.age / rocket.lifetime
    local dx = rocket.targetScreenX - rocket.startScreenX
    local dy = rocket.targetScreenY - rocket.startScreenY
    -- Quadratic forward travel builds speed while the sideways offset fades back to zero.
    local bend = math.sin(math.pi * t)
    local x = rocket.startScreenX + dx * t * t + rocket.bendX * bend
    local y = rocket.startScreenY + dy * t * t + rocket.bendY * bend
    -- The camera follows the ship's integrated velocity and also accounts for lead and zoom.
    rocket.x, rocket.y = camera:screenToWorld(x, y, width, height)

    -- Draw the nose and exhaust along the motion the player sees on screen.
    local bendRate = math.pi * math.cos(math.pi * t)
    local worldDuration = rocket.lifetime * camera.zoom
    rocket.vx = (2 * t * dx + rocket.bendX * bendRate) / worldDuration
    rocket.vy = (2 * t * dy + rocket.bendY * bendRate) / worldDuration
    rocket.speed = math.sqrt(rocket.vx ^ 2 + rocket.vy ^ 2)
end

function Turret:fire(ship, targetX, targetY, enemies, frameFraction, camera, width, height, weaponBuild, opts)
    opts = opts or {}
    local weapon = opts.weapon or self.weapon
    local baseAngle = opts.angle or self.angle
    local cfg = weaponBuild
    local batteryCost = (cfg and not opts.free) and (cfg.batteryCost or 0) or 0
    if batteryCost > 0 then
        if (ship.battery or 0) < batteryCost then return nil end
        ship.battery = ship.battery - batteryCost
    end

    -- Queue burst follow-up shots for the burst support chip.
    if cfg and (cfg.extraBurst or 0) > 0 and not opts.fromBurst then
        for b = 1, cfg.extraBurst do
            self.burstQueue[#self.burstQueue + 1] = {
                delay = b * 0.06,
                weapon = weapon,
                angle = opts.angle,
                targetX = targetX,
                targetY = targetY,
                weaponBuild = cfg,
                free = true,
            }
        end
    end

    self.shotsFired = self.shotsFired + 1
    local extraCount = cfg and cfg.extraCount or 0
    local extraSpreadRad = cfg and math.rad(cfg.extraSpreadDeg or 0) or 0
    local areaMult = (cfg and cfg.areaMult or 1) * (opts.areaMult or 1)
    local bounces = cfg and cfg.bounces or 0
    local dx, dy = math.sin(baseAngle), -math.cos(baseAngle)
    local x, y = ship.x + dx * muzzleLength, ship.y + dy * muzzleLength

    if weapon == 3 then
        local offsets = buildOffsets(1, extraCount, math.rad(7), extraSpreadRad)
        self.beams = {}
        local primaryBeam = nil
        local anyHit = false
        for _, offset in ipairs(offsets) do
            local a = (baseAngle + offset) % tau
            local bdx, bdy = math.sin(a), -math.cos(a)
            local bx, by = ship.x + bdx * muzzleLength, ship.y + bdy * muzzleLength
            local hitX, hitY
            if enemies then
                local entry, exit = camera:clipRay(bx, by, bdx, bdy, width, height)
                if exit then
                    local t = frameFraction or 1
                    hitX, hitY = enemies:hitSegment(bx + bdx * entry, by + bdy * entry,
                        bx + bdx * exit, by + bdy * exit, t, t, camera, width, height)
                end
            end
            if hitX then
                anyHit = true
                self.explosions[#self.explosions + 1] = {
                    x = hitX, y = hitY, radius = 28 * areaMult, age = 0, lifetime = beamImpactLifetime,
                    colors = beamImpactColors,
                }
                if bounces > 0 and enemies then
                    local nxt = nearestEnemy(enemies, hitX, hitY, hitX, hitY, camera, width, height)
                    if nxt then
                        local rdx, rdy = nxt.x - hitX, nxt.y - hitY
                        local rlen = math.sqrt(rdx * rdx + rdy * rdy)
                        if rlen > 0 then
                            local rhx, rhy = enemies:hitSegment(hitX, hitY, nxt.x, nxt.y,
                                frameFraction or 1, frameFraction or 1, camera, width, height)
                            if rhx then
                                self.beams[#self.beams + 1] = {
                                    x = hitX, y = hitY, dx = rdx / rlen, dy = rdy / rlen,
                                    hitX = rhx, hitY = rhy, age = 0,
                                }
                            end
                        end
                    end
                end
            end
            local bObj = { x = bx, y = by, dx = bdx, dy = bdy, hitX = hitX, hitY = hitY, age = 0 }
            self.beams[#self.beams + 1] = bObj
            if not primaryBeam then primaryBeam = bObj end
        end
        Sfx.play("laser")
        if anyHit then
            self.shotsHit = self.shotsHit + 1
            Sfx.play("impact")
        end
        self.beam = primaryBeam
        return self.beam
    end

    local shot = { hit = false }
    if weapon == 2 then
        local offsets = buildOffsets(1, extraCount, math.rad(10), extraSpreadRad)
        local firstMissile = nil
        local distance = math.sqrt((targetX - x) ^ 2 + (targetY - y) ^ 2)
        for _, offset in ipairs(offsets) do
            local a = (baseAngle + offset) % tau
            local rdx, rdy = math.sin(a), -math.cos(a)
            local tx = targetX
            local ty = targetY
            if offset ~= 0 then
                tx = x + rdx * math.max(120, distance)
                ty = y + rdy * math.max(120, distance)
            end
            local missile = {
                x = x, y = y, startX = x, startY = y,
                owner = ship, angle = a, distance = 0, age = 0, shot = shot,
                blastRadius = blastRadius * areaMult,
            }
            local dist = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)
            local bend = self.launchSide * math.min(rocketMaxBend, dist * 0.18)
            self.launchSide = -self.launchSide
            missile.bendX, missile.bendY = -rdy * bend * camera.zoom, rdx * bend * camera.zoom
            missile.startScreenX, missile.startScreenY = camera:worldToScreen(x, y, width, height)
            missile.targetScreenX, missile.targetScreenY = camera:worldToScreen(tx, ty, width, height)
            missile.lifetime = dist / rocketAverageSpeed
            updateRocketPose(missile, camera, width, height)
            self.missiles[#self.missiles + 1] = missile
            if not firstMissile then firstMissile = missile end
        end
        Sfx.play("missile")
        return firstMissile
    end

    local vx, vy = ship:worldVelocity()
    local first = #self.missiles + 1
    local offsets = (extraCount == 0 and extraSpreadRad == 0)
        and projectileOffsets
        or buildOffsets(3, extraCount, projectileSpread, extraSpreadRad)
    for _, offset in ipairs(offsets) do
        local angle = (baseAngle + offset) % tau
        local shotVx = math.sin(angle) * self.missileSpeed + vx
        local shotVy = -math.cos(angle) * self.missileSpeed + vy
        self.missiles[#self.missiles + 1] = {
            x = x, y = y, startX = x, startY = y,
            owner = ship, angle = angle, distance = 0, age = 0, shot = shot,
            vx = shotVx, vy = shotVy, speed = math.sqrt(shotVx ^ 2 + shotVy ^ 2),
            lifetime = self.missileLifetime,
            homing = cfg and cfg.homing or false,
            homingTurnRate = cfg and cfg.homingTurnRate or 0,
            bounces = bounces,
        }
    end
    Sfx.play("projectile")
    return self.missiles[first]
end

function Turret:fireTriggered(weaponIndex, ship, targetX, targetY, enemies, camera, width, height, weaponBuild, opts)
    opts = opts or {}
    if opts.radialCount and opts.radialCount > 1 then
        local fired = nil
        for i = 0, opts.radialCount - 1 do
            local a = (i / opts.radialCount) * tau
            local tx = ship.x + math.sin(a) * 260
            local ty = ship.y - math.cos(a) * 260
            fired = self:fire(ship, tx, ty, enemies, 1, camera, width, height, weaponBuild, {
                weapon = weaponIndex, angle = a, free = true, fromBurst = true, areaMult = opts.areaMult,
            }) or fired
        end
        return fired
    end
    return self:fire(ship, targetX, targetY, enemies, 1, camera, width, height, weaponBuild, {
        weapon = weaponIndex, free = opts.free, areaMult = opts.areaMult,
    })
end

function Turret:update(dt, ship, mouseWorldX, mouseWorldY, firing, enemies, camera, width, height, weaponBuild)
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
        if self.beams then
            for bi = #self.beams, 1, -1 do
                self.beams[bi].age = self.beams[bi].age + step
                if self.beams[bi].age >= beamLifetime then table.remove(self.beams, bi) end
            end
        end
        if self.burstQueue then
            for qi = #self.burstQueue, 1, -1 do
                local q = self.burstQueue[qi]
                q.delay = q.delay - step
                if q.delay <= 0 then
                    table.remove(self.burstQueue, qi)
                    self:fire(ship, mouseWorldX, mouseWorldY, enemies,
                        dt > 0 and (dt - remaining) / dt or 0, camera, width, height,
                        q.weaponBuild, { weapon = q.weapon, angle = q.angle, free = q.free, fromBurst = true })
                end
            end
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
            local isRocket = missile.targetScreenX ~= nil
            local oldX, oldY = missile.x, missile.y
            local flightTime = math.min(step, missile.lifetime - missile.age)
            local elapsed = missile.age + step
            missile.age = math.min(missile.lifetime, elapsed)
            if isRocket then
                updateRocketPose(missile, camera, width, height)
            else
                if missile.homing and enemies then
                    local tgt = nearestEnemy(enemies, missile.x, missile.y, nil, nil, camera, width, height)
                    if tgt then
                        local desired = math.atan2(tgt.x - missile.x, -(tgt.y - missile.y))
                        local curAngle = math.atan2(missile.vx, -missile.vy)
                        local diff = (desired - curAngle + math.pi) % tau - math.pi
                        local maxTurn = (missile.homingTurnRate or 4.0) * flightTime
                        local newAngle = curAngle + math.max(-maxTurn, math.min(maxTurn, diff))
                        missile.vx = math.sin(newAngle) * missile.speed
                        missile.vy = -math.cos(newAngle) * missile.speed
                        missile.angle = newAngle
                        missile.x = missile.x + missile.vx * flightTime
                        missile.y = missile.y + missile.vy * flightTime
                        missile.distance = missile.distance + missile.speed * flightTime
                    else
                        missile.x = missile.x + missile.vx * flightTime
                        missile.y = missile.y + missile.vy * flightTime
                        missile.distance = missile.distance + missile.speed * flightTime
                    end
                else
                    missile.distance = missile.speed * missile.age
                    missile.x = missile.startX + missile.vx * missile.age
                    missile.y = missile.startY + missile.vy * missile.age
                end
            end
            local hitX, hitY, hitTime
            if enemies and not isRocket then
                local frameStart = dt > 0 and (dt - remaining) / dt or 0
                local frameEnd = dt > 0 and (dt - remaining + flightTime) / dt or 0
                hitX, hitY, hitTime = enemies:hitSegment(oldX, oldY, missile.x, missile.y, frameStart, frameEnd, camera, width, height)
            end
            if hitX or elapsed >= missile.lifetime then
                local age = hitX and step - flightTime * hitTime or elapsed - missile.lifetime
                local x, y = hitX or missile.x, hitY or missile.y
                local hit = hitX ~= nil
                local rRadius = missile.blastRadius or blastRadius
                if enemies and isRocket then
                    local fraction = dt > 0 and (dt - remaining + flightTime) / dt or 0
                    hit = enemies:hitArea(x, y, rRadius, fraction, camera, width, height)
                end
                if hit and not missile.shot.hit then
                    missile.shot.hit = true
                    self.shotsHit = self.shotsHit + 1
                end
                if hitX or isRocket then Sfx.play("impact") end
                if age < self.explosionLifetime then
                    self.explosions[#self.explosions + 1] = {
                        x = x, y = y, radius = isRocket and rRadius,
                        age = age, lifetime = self.explosionLifetime,
                    }
                end
                if hitX and not isRocket and (missile.bounces or 0) > 0 and enemies then
                    local nxt = nearestEnemy(enemies, x, y, x, y, camera, width, height)
                    if nxt then
                        local bdx, bdy = nxt.x - x, nxt.y - y
                        local blen = math.sqrt(bdx * bdx + bdy * bdy)
                        if blen > 0 then
                            missile.bounces = missile.bounces - 1
                            missile.startX, missile.startY = x, y
                            missile.x, missile.y = x, y
                            missile.vx, missile.vy = (bdx / blen) * missile.speed, (bdy / blen) * missile.speed
                            missile.age = 0
                            missile.lifetime = self.missileLifetime * 0.7
                        else
                            table.remove(self.missiles, i)
                        end
                    else
                        table.remove(self.missiles, i)
                    end
                else
                    table.remove(self.missiles, i)
                end
            end
        end
        remaining = remaining - step
        self.cooldown = math.max(0, self.cooldown - step)
        if firing and self.cooldown == 0 then
            local cdMult = weaponBuild and ((weaponBuild.cooldownMult or 1) * (weaponBuild.manualCooldownMult or 1)) or 1
            self:fire(ship, mouseWorldX, mouseWorldY, enemies, dt > 0 and (dt - remaining) / dt or 0,
                camera, width, height, weaponBuild)
            self.cooldown = self.fireInterval * cdMult
        end
    until remaining <= 0
end

function Turret:clearEffects()
    self.missiles = {}
    self.explosions = {}
    self.beams = {}
    self.beam = nil
    self.burstQueue = {}
end

function Turret:beginStageClear()
    self.burstQueue = {}
    for _, missile in ipairs(self.missiles) do
        if not missile.fading then
            local fadeSpan = missile.targetScreenX and 0.65 or 0.55
            missile.fading = true
            missile.fadeStartAge = missile.age
            missile.fadeEndAge = math.min(missile.lifetime, missile.age + fadeSpan)
        end
    end
end

function Turret:updateEffects(dt, camera, width, height)
    dt = math.max(0, dt or 0)
    if dt <= 0 then return end
    self.cooldown = math.max(0, self.cooldown - dt)

    local agedPrimary = false
    if self.beams then
        for bi = #self.beams, 1, -1 do
            local beam = self.beams[bi]
            if beam == self.beam then agedPrimary = true end
            beam.age = beam.age + dt
            if beam.age >= beamLifetime then
                if beam == self.beam then self.beam = nil end
                table.remove(self.beams, bi)
            end
        end
    end
    if self.beam and not agedPrimary then
        self.beam.age = self.beam.age + dt
        if self.beam.age >= beamLifetime then
            self.beam = nil
        end
    end

    for i = #self.explosions, 1, -1 do
        local explosion = self.explosions[i]
        explosion.age = explosion.age + dt
        if explosion.age >= explosion.lifetime then
            table.remove(self.explosions, i)
        end
    end

    for i = #self.missiles, 1, -1 do
        local missile = self.missiles[i]
        local isRocket = missile.targetScreenX ~= nil
        local expireAt = missile.fadeEndAge or missile.lifetime
        local flightTime = math.min(dt, math.max(0, expireAt - missile.age))
        local elapsed = missile.age + dt
        missile.age = math.min(expireAt, elapsed)
        if isRocket then
            if camera and width and height then
                updateRocketPose(missile, camera, width, height)
            end
        elseif flightTime > 0 then
            missile.x = missile.x + missile.vx * flightTime
            missile.y = missile.y + missile.vy * flightTime
            missile.distance = (missile.distance or 0) + (missile.speed or 0) * flightTime
        end
        if elapsed >= expireAt - 1e-9 then
            table.remove(self.missiles, i)
        end
    end
end

function Turret:drawEffects(camera, width, height)
    local g = love.graphics
    g.push("all")
    for _, missile in ipairs(self.missiles) do
        local fade = 1
        if missile.fading and missile.fadeEndAge then
            local span = math.max(1e-4, missile.fadeEndAge - (missile.fadeStartAge or 0))
            fade = math.max(0, math.min(1, (missile.fadeEndAge - missile.age) / span))
        end
        local speed = missile.speed > 0 and missile.speed or 1
        local dx, dy = missile.vx / speed, missile.vy / speed
        g.setLineWidth(3)
        g.setColor(1, 0.42, 0.12, 0.45 * fade)
        if missile.targetScreenX then
            local trail = math.min(32, missile.speed * math.min(0.03, missile.age))
            if trail > 0 then
                g.line(missile.x, missile.y, missile.x - dx * trail, missile.y - dy * trail)
            end
        else
            local trail = math.min(24, missile.distance or 0)
            if trail > 0 then
                g.line(missile.x, missile.y, missile.x - dx * trail, missile.y - dy * trail)
            end
        end
        g.setLineWidth(2)
        g.setColor(1, 0.87, 0.46, fade)
        g.line(missile.x - dx * 6, missile.y - dy * 6, missile.x, missile.y)
        if missile.targetScreenX then
            g.setColor(1, 0.34, 0.20, fade)
            g.polygon("fill", missile.x + dx * 7, missile.y + dy * 7,
                missile.x - dx * 5 - dy * 4, missile.y - dy * 5 + dx * 4,
                missile.x - dx * 5 + dy * 4, missile.y - dy * 5 - dx * 4)
        else
            g.circle("fill", missile.x, missile.y, 2)
        end
    end
    local beamList = (self.beams and #self.beams > 0) and self.beams or (self.beam and { self.beam } or {})
    for _, beam in ipairs(beamList) do
        local x, y = beam.hitX, beam.hitY
        if not x then
            -- Recalculate the endpoint as the viewport pans, zooms or resizes.
            local _, exit = camera:clipRay(beam.x, beam.y, beam.dx, beam.dy, width, height)
            if exit then x, y = beam.x + beam.dx * exit, beam.y + beam.dy * exit end
        end
        if x then
            local alpha = math.max(0, 1 - beam.age / beamLifetime)
            g.setColor(0.12, 0.82, 1, alpha * 0.4)
            g.setLineWidth(6)
            g.line(beam.x, beam.y, x, y)
            g.setColor(0.76, 0.98, 1, alpha)
            g.setLineWidth(2)
            g.line(beam.x, beam.y, x, y)
        end
    end
    for _, explosion in ipairs(self.explosions) do
        local progress = math.max(0, math.min(1, explosion.age / explosion.lifetime))
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
    g.pop()
end

local function blendWhite(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

function Turret:drawMount(ship, time)
    local g = love.graphics
    local alpha, flash = 1, 0
    if ship and ship.invulnBlinkAlpha then
        alpha, flash = ship:invulnBlinkAlpha()
    end
    local pulse = 0.84 + math.sin((time or 0) * 7) * 0.16
    g.push("all")
    g.translate(ship.x, ship.y)
    g.rotate(self.angle)

    -- Refined Nova Assault barrel
    local r, gg, b = blendWhite(0.09, 0.14, 0.20, flash * 0.72)
    g.setColor(r, gg, b, alpha)
    g.rectangle("fill", -2.2, -muzzleLength + 1, 4.4, muzzleLength - 2, 0.9, 0.9)
    r, gg, b = blendWhite(1, 0.84, 0.47, flash)
    g.setColor(r, gg, b, alpha)
    g.setLineWidth(1.05)
    g.rectangle("line", -2.2, -muzzleLength + 1, 4.4, muzzleLength - 2, 0.9, 0.9)
    r, gg, b = blendWhite(1, 0.96, 0.81, flash)
    g.setColor(r, gg, b, 0.75 * alpha)
    g.setLineWidth(0.8)
    g.line(0, -muzzleLength + 2.5, 0, -9)

    -- Turret housing & glowing golden core
    r, gg, b = blendWhite(0.07, 0.11, 0.16, flash * 0.72)
    g.setColor(r, gg, b, alpha)
    g.circle("fill", 0, 0, 7.1)
    r, gg, b = blendWhite(0.94, 0.70, 0.29, flash)
    g.setColor(r, gg, b, alpha)
    g.setLineWidth(1.2)
    g.circle("line", 0, 0, 6.8)
    r, gg, b = blendWhite(1, 0.84, 0.42, flash)
    g.setColor(r, gg, b, 0.30 * pulse * alpha)
    g.circle("fill", 0, 0, 4.8)
    r, gg, b = blendWhite(1, 0.92, 0.64, flash)
    g.setColor(r, gg, b, pulse * alpha)
    g.circle("fill", 0, 0, 2.7)
    g.pop()
end

return Turret
