local Arena = require("src.core.arena")
local Collision = require("src.core.collision")
local Sfx = require("src.audio.sfx")
local EnemyFire = {}
EnemyFire.__index = EnemyFire

local impactLifetime = 0.24
local tau = 2 * math.pi
local bullet = {id = "bullet", speed = 440, lifetime = 1.65, radius = 3.5, damage = 6, trail = 15, color = {1, 0.45, 0.23}, replayKind = 1}
local laser = {id = "laser", speed = 1150, lifetime = 0.95, radius = 4.5, damage = 14, trail = 56, color = {1, 0.24, 0.65}, isLaser = true, grazable = true, replayKind = 2}
local curtain = {id = "curtain", speed = 255, lifetime = 3.8, radius = 5.0, damage = 7, trail = 10, color = {1.0, 0.78, 0.24}, isOrb = true, grazable = true, replayKind = 4}
local spiral = {id = "spiral", speed = 210, lifetime = 4.2, radius = 5.0, damage = 6, trail = 10, color = {0.82, 0.34, 1.0}, isOrb = true, grazable = true, replayKind = 5}

EnemyFire.impactLifetime = impactLifetime
EnemyFire.profiles = {
    bullet = bullet,
    laser = laser,
    curtain = curtain,
    spiral = spiral,
}
EnemyFire.shotRenderers = {}

function EnemyFire.registerProfile(id, profile)
    if not id or type(profile) ~= "table" then return profile end
    profile.id = id
    EnemyFire.profiles[id] = profile
    return profile
end

function EnemyFire.getProfile(id)
    return id and EnemyFire.profiles[id] or nil
end

EnemyFire.railCount = 3
EnemyFire.railInterval = 0.055
EnemyFire.curtainWaveInterval = 0.34
EnemyFire.curtainOddAngles = {0, -18, 18, -36, 36}
EnemyFire.curtainEvenAngles = {-9, 9, -27, 27, -45, 45}
EnemyFire.spiralArms = 4
EnemyFire.spiralWaves = 5
EnemyFire.spiralInterval = 0.15
EnemyFire.spiralStepRad = math.rad(18)
EnemyFire.ringCount = 10
EnemyFire.ringWaves = 2
EnemyFire.ringInterval = 0.32
EnemyFire.ringSpeed = 225

function EnemyFire.new()
    return setmetatable({shots = {}, bursts = {}, impacts = {}}, EnemyFire)
end

function EnemyFire:clear()
    self.shots = {}
    self.bursts = {}
    self.impacts = {}
end

local function bearing(enemy, targetX, targetY)
    local dx, dy = targetX - enemy.x, targetY - enemy.y
    if dx == 0 and dy == 0 then return enemy.angle - math.pi / 2, 0 end
    return math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
end

local function launch(fire, enemy, angle, profile, delay)
    local dx, dy = math.cos(angle), math.sin(angle)
    local muzzle = enemy.radius * 0.7
    local x, y = enemy.x + dx * muzzle, enemy.y + dy * muzzle
    local shot = {x = x, y = y, vx = dx, vy = dy, age = 0, profile = profile, delay = delay}
    fire.shots[#fire.shots + 1] = shot
    return shot
end

local function launchAngle(fire, enemy, angle, profile, delay, sfxName, pitchScale, speedOverride)
    local shot = launch(fire, enemy, angle, profile, delay)
    local spd = speedOverride or profile.speed
    shot.vx, shot.vy = shot.vx * spd, shot.vy * spd
    shot.lifetime = profile.lifetime
    if sfxName then
        Sfx.play(sfxName, pitchScale)
    end
    return shot
end

function EnemyFire:shoot(enemy, ship, opts)
    if not ship or ship:isDestroyed() then return nil end
    opts = opts or {}
    local targetX, targetY = ship.x, ship.y
    if enemy.kind == 1 then
        local baseAngle = opts.angle or bearing(enemy, targetX, targetY)
        launchAngle(self, enemy, baseAngle, bullet, 0)
        Sfx.play("enemyProjectile")
        return nil
    elseif enemy.kind == 2 then
        local fixedAngle = opts.angle or bearing(enemy, targetX, targetY)
        launchAngle(self, enemy, fixedAngle, laser, 0, "enemyLaser")
        if opts.single then return nil end
        local burst = {
            kind = "rail",
            enemy = enemy,
            angle = fixedAngle,
            remaining = EnemyFire.railCount - 1,
            delay = EnemyFire.railInterval,
        }
        self.bursts[#self.bursts + 1] = burst
        return burst
    elseif enemy.kind == 3 then
        local baseAngle = bearing(enemy, targetX, targetY)
        local aimAngle = opts.angle or baseAngle
        for _, offsetDeg in ipairs(EnemyFire.curtainOddAngles) do
            launchAngle(self, enemy, aimAngle + math.rad(offsetDeg), curtain, 0)
        end
        Sfx.play("enemyProjectile", 0.72)
        local burst = {
            kind = "curtain",
            enemy = enemy,
            baseAngle = aimAngle,
            wave = 2,
            maxWaves = 3,
            remaining = 2,
            delay = EnemyFire.curtainWaveInterval,
        }
        self.bursts[#self.bursts + 1] = burst
        return burst
    else
        local baseAngle = opts.angle or (enemy.angle - math.pi / 2)
        if opts.pattern == "ring" then
            for k = 0, EnemyFire.ringCount - 1 do
                local a = baseAngle + k * (tau / EnemyFire.ringCount)
                launchAngle(self, enemy, a, spiral, 0, nil, nil, EnemyFire.ringSpeed)
            end
            Sfx.play("enemyProjectile", 0.76)
            local burst = {
                kind = "ring",
                enemy = enemy,
                baseAngle = baseAngle + math.pi / EnemyFire.ringCount,
                remaining = EnemyFire.ringWaves - 1,
                delay = EnemyFire.ringInterval,
            }
            self.bursts[#self.bursts + 1] = burst
            return burst
        else
            for arm = 0, EnemyFire.spiralArms - 1 do
                local a = baseAngle + arm * (tau / EnemyFire.spiralArms)
                launchAngle(self, enemy, a, spiral, 0)
            end
            Sfx.play("enemyProjectile", 0.88)
            local burst = {
                kind = "spiral",
                enemy = enemy,
                baseAngle = baseAngle + EnemyFire.spiralStepRad,
                remaining = EnemyFire.spiralWaves - 1,
                delay = EnemyFire.spiralInterval,
            }
            self.bursts[#self.bursts + 1] = burst
            return burst
        end
    end
end

local function wrappedDelta(start, finish, extent)
    return (finish - start + extent / 2) % extent - extent / 2
end

local function playerRelativeSegment(shot, motion, x, y, elapsed, step)
    local dx, dy = shot.x - x, shot.y - y
    local near, far = Collision.rectangleInterval(x, y, dx, dy, Arena.width, Arena.height)
    local entry, leave = math.max(0, near), math.min(1, far)
    if entry > leave then return end

    -- Only the parts of the player drawn inside the arena can be hit at a seam.
    local start = elapsed + step * entry
    local span = leave - entry
    local px, py = x + dx * entry, y + dy * entry
    local rx, ry = px - motion.x - motion.vx * start, py - motion.y - motion.vy * start
    local vx, vy = (dx - motion.vx * step) * span, (dy - motion.vy * step) * span
    rx = rx - math.floor((rx + vx * 0.5) / Arena.width + 0.5) * Arena.width
    ry = ry - math.floor((ry + vy * 0.5) / Arena.height + 0.5) * Arena.height
    return rx, ry, vx, vy, px, py, dx, dy, start, span
end

local function playerHit(shot, motion, x, y, elapsed, step, radius)
    local rx, ry, vx, vy, px, py, dx, dy, start, span = playerRelativeSegment(shot, motion, x, y, elapsed, step)
    if not rx then return end
    local t = Collision.circleEntry(rx, ry, vx, vy, radius + shot.profile.radius)
    if t then return px + dx * span * t, py + dy * span * t, start + step * span * t end
end

local function moveShot(shot, step)
    shot.age = shot.age + step
    shot.x, shot.y = shot.x + shot.vx * step, shot.y + shot.vy * step
end

local function impact(fire, shot, x, y, shield)
    fire.impacts[#fire.impacts + 1] = {x = x, y = y, age = 0, profile = shot.profile, shield = shield}
end

local function stepShots(fire, ship, motion, elapsed, finish, gladiator)
    local contacts = {}
    local missileSteps = gladiator and {} or nil
    local hitRadius = ship:hitRadius()
    for _, shot in ipairs(fire.shots) do
        local start = math.max(elapsed, shot.delay)
        local step = math.min(finish - start, shot.lifetime - shot.age)
        if step > 0 then
            local oldX, oldY = shot.x, shot.y
            moveShot(shot, step)
            if missileSteps and shot.profile.grazable then
                missileSteps[#missileSteps + 1] = {shot = shot, oldX = oldX, oldY = oldY, start = start, step = step}
            end
            if not ship:isDestroyed() and not ship:isInvulnerable() then
                local x, y, at = playerHit(shot, motion, oldX, oldY, start, step, hitRadius)
                if x then
                    contacts[#contacts + 1] = {shot = shot, x = x, y = y, at = at,
                        oldX = oldX, oldY = oldY, start = start, step = step}
                end
            end
        end
    end

    while #contacts > 0 and not ship:isDestroyed() and not ship:isInvulnerable() do
        local first = 1
        for i = 2, #contacts do
            if contacts[i].at < contacts[first].at then first = i end
        end
        local hit = table.remove(contacts, first)
        impact(fire, hit.shot, hit.x, hit.y, ship:hasShield())
        local px = (motion.x + motion.vx * hit.at) % Arena.width
        local py = (motion.y + motion.vy * hit.at) % Arena.height
        local knockX = wrappedDelta(hit.x, px, Arena.width)
        local knockY = wrappedDelta(hit.y, py, Arena.height)
        if knockX * knockX + knockY * knockY < 1e-4 then
            knockX, knockY = hit.shot.vx, hit.shot.vy
        end
        ship:takeDamage(hit.shot.profile.damage, knockX, knockY)
        if gladiator then gladiator:syncPlayerDamage(ship) end
        hit.shot.spent = true

        -- A broken shield exposes the smaller hull to the remaining shots in this step.
        if not ship:isInvulnerable() and ship:hitRadius() ~= hitRadius then
            hitRadius = ship:hitRadius()
            for i = #contacts, 1, -1 do
                local contact = contacts[i]
                contact.x, contact.y, contact.at = playerHit(contact.shot, motion, contact.oldX,
                    contact.oldY, contact.start, contact.step, hitRadius)
                if not contact.x then table.remove(contacts, i) end
            end
        end
    end

    local missileThreatened = false
    if missileSteps and not ship:isDestroyed() and not ship:isInvulnerable() then
        for _, entry in ipairs(missileSteps) do
            local shot = entry.shot
            if not shot.spent then
                local rx, ry, vx, vy, _, _, _, _, start, span = playerRelativeSegment(
                    shot, motion, entry.oldX, entry.oldY, entry.start, entry.step)
                if rx then
                    local minDist, minT = Collision.closestDistance(rx, ry, vx, vy)
                    local clearance = minDist - (hitRadius + shot.profile.radius)
                    if clearance > 0 and clearance <= gladiator.missileMargin then
                        local spanStep = entry.step * span
                        local relativeSpeed = spanStep > 0 and math.sqrt(vx * vx + vy * vy) / spanStep or 0
                        local at = start + spanStep * minT
                        local px = (motion.x + motion.vx * at) % Arena.width
                        local py = (motion.y + motion.vy * at) % Arena.height
                        local grazeX = px + (rx + vx * minT) * 0.5
                        local grazeY = py + (ry + vy * minT) * 0.5
                        if gladiator:observeMissileThreat(clearance, relativeSpeed, grazeX, grazeY, "BULLET GRAZE") then
                            missileThreatened = true
                        end
                    end
                end
            end
        end
    end

    for i = #fire.shots, 1, -1 do
        local shot = fire.shots[i]
        if shot.spent or shot.age >= shot.lifetime - 1e-9 then
            table.remove(fire.shots, i)
        end
    end
    if gladiator then
        gladiator:advanceMissileSituation(finish - elapsed, ship, missileThreatened)
    end
end

function EnemyFire:update(dt, ship, gladiator)
    if gladiator then gladiator:syncPlayerDamage(ship) end
    for i = #self.impacts, 1, -1 do
        local effect = self.impacts[i]
        effect.age = effect.age + dt
        if effect.age >= impactLifetime then table.remove(self.impacts, i) end
    end
    for i = #self.bursts, 1, -1 do
        local burst = self.bursts[i]
        local cancelled = burst.enemy.dead or ship:isDestroyed()
        if not cancelled then
            while burst.remaining > 0 and burst.delay <= dt + 1e-9 do
                local shotDelay = math.min(dt, burst.delay)
                if burst.kind == "rail" then
                    launchAngle(self, burst.enemy, burst.angle, laser, shotDelay, "enemyLaser", 1.04)
                    burst.remaining = burst.remaining - 1
                    burst.delay = burst.delay + EnemyFire.railInterval
                elseif burst.kind == "curtain" then
                    local angles = (burst.wave % 2 == 0) and EnemyFire.curtainEvenAngles or EnemyFire.curtainOddAngles
                    for _, offsetDeg in ipairs(angles) do
                        launchAngle(self, burst.enemy, burst.baseAngle + math.rad(offsetDeg), curtain, shotDelay)
                    end
                    Sfx.play("enemyProjectile", burst.wave % 2 == 0 and 0.80 or 0.72)
                    burst.wave = burst.wave + 1
                    burst.remaining = burst.remaining - 1
                    burst.delay = burst.delay + EnemyFire.curtainWaveInterval
                elseif burst.kind == "spiral" then
                    for arm = 0, EnemyFire.spiralArms - 1 do
                        local a = burst.baseAngle + arm * (tau / EnemyFire.spiralArms)
                        launchAngle(self, burst.enemy, a, spiral, shotDelay)
                    end
                    Sfx.play("enemyProjectile", 0.88)
                    burst.baseAngle = burst.baseAngle + EnemyFire.spiralStepRad
                    burst.remaining = burst.remaining - 1
                    burst.delay = burst.delay + EnemyFire.spiralInterval
                elseif burst.kind == "ring" then
                    for k = 0, EnemyFire.ringCount - 1 do
                        local a = burst.baseAngle + k * (tau / EnemyFire.ringCount)
                        launchAngle(self, burst.enemy, a, spiral, shotDelay, nil, nil, EnemyFire.ringSpeed)
                    end
                    Sfx.play("enemyProjectile", 0.80)
                    burst.baseAngle = burst.baseAngle + math.pi / EnemyFire.ringCount
                    burst.remaining = burst.remaining - 1
                    burst.delay = burst.delay + EnemyFire.ringInterval
                else
                    burst.remaining = 0
                end
            end
            burst.delay = burst.delay - dt
        end
        if cancelled or burst.remaining == 0 then table.remove(self.bursts, i) end
    end

    local x, y = ship.prevX or ship.x, ship.prevY or ship.y
    local motion = {x = x, y = y,
        vx = wrappedDelta(x, ship.x, Arena.width) / dt, vy = wrappedDelta(y, ship.y, Arena.height) / dt}
    local elapsed = 0
    while elapsed < dt and #self.shots > 0 do
        local finish = math.min(dt, elapsed + 1 / 60)
        stepShots(self, ship, motion, elapsed, finish, gladiator)
        elapsed = finish
    end
    if gladiator and elapsed < dt then
        gladiator:advanceMissileSituation(dt - elapsed, ship, false)
    end
    for _, shot in ipairs(self.shots) do shot.delay = 0 end
end

-- Mark all remaining projectiles as harmless on stage clear and stagger their
-- expiration times so they visibly glide and dissipate sequentially without
-- ever dealing damage to the player.
function EnemyFire:beginHarmlessExpiry()
    self.bursts = {}
    local n = #self.shots
    if n == 0 then return end

    local ordered = {}
    for i = 1, n do ordered[i] = self.shots[i] end
    table.sort(ordered, function(a, b)
        return (a.lifetime - a.age) < (b.lifetime - b.age)
    end)

    local maxSpan = math.min(0.95, 0.12 + 0.09 * n)
    for i, shot in ipairs(ordered) do
        local frac = n > 1 and ((i - 1) / (n - 1)) or 0
        local delay = 0.12 + frac * math.max(0, maxSpan - 0.12)
        shot.harmless = true
        shot.harmlessStartAge = shot.age
        shot.harmlessExpireAt = math.min(shot.lifetime, shot.age + delay)
        shot.delay = 0
    end
end

-- Advance harmless projectiles during stage-clear hold: no player collision or
-- damage, no second-leg missile re-homing, and crisp sequential expiry rings.
function EnemyFire:updateHarmless(dt)
    if dt <= 0 then return end
    for i = #self.impacts, 1, -1 do
        local effect = self.impacts[i]
        effect.age = effect.age + dt
        if effect.age >= impactLifetime then table.remove(self.impacts, i) end
    end

    for i = #self.shots, 1, -1 do
        local shot = self.shots[i]
        local expireAt = shot.harmlessExpireAt or shot.lifetime
        local step = math.min(dt, math.max(0, expireAt - shot.age))
        if step > 0 then
            moveShot(shot, step)
        end
        if shot.age >= expireAt - 1e-9 then
            self.impacts[#self.impacts + 1] = {
                x = shot.x, y = shot.y, age = 0, profile = shot.profile, dissipate = true,
            }
            table.remove(self.shots, i)
        end
    end
end

function EnemyFire:draw()
    local g = love.graphics
    g.push("all")
    for _, shot in ipairs(self.shots) do
        local profile = shot.profile
        local r, green, b = unpack(profile.color)
        local fade = 1
        if shot.harmless and shot.harmlessExpireAt then
            local span = math.max(1e-4, shot.harmlessExpireAt - (shot.harmlessStartAge or 0))
            local left = math.max(0, (shot.harmlessExpireAt - shot.age) / span)
            fade = 0.25 + 0.55 * left
            -- Desaturate slightly toward cool neutral so deactivated shots look clearly harmless
            r = r * 0.65 + 0.22
            green = green * 0.65 + 0.30
            b = b * 0.65 + 0.34
        end
        local length = math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy)
        local dx, dy = 0, 0
        if length > 0 then dx, dy = shot.vx / length, shot.vy / length end
        local trail = math.min(profile.trail or 15, (profile.radius or 3.5) + length * shot.age)
        local tailX, tailY = shot.x - dx * trail, shot.y - dy * trail
        local custom = profile.renderer or (profile.style and EnemyFire.shotRenderers[profile.style])
        if custom then
            custom(g, shot, r, green, b, fade, dx, dy, tailX, tailY, length)
        elseif profile.isOrb then
            g.setLineWidth(profile.radius * 1.1)
            g.setColor(r, green, b, 0.20 * fade)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setColor(r, green, b, 0.24 * fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 2.1)
            g.setColor(r, green, b, 0.95 * fade)
            g.circle("fill", shot.x, shot.y, profile.radius)
            g.setLineWidth(1.0)
            g.setColor(1, 0.94, 0.72, 0.85 * fade)
            g.circle("line", shot.x, shot.y, profile.radius)
            g.setColor(1, 0.97, 0.85, fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 0.56)
        elseif profile == bullet or profile.id == "bullet" then
            -- VE1B Orb + VE1A Tapered Solar Needle Tail
            local px, py = -dy, dx
            local orbTrail = math.min(28, profile.radius + length * shot.age)
            local otX, otY = shot.x - dx * orbTrail, shot.y - dy * orbTrail
            g.setBlendMode("add")
            g.setColor(r, green, b, 0.30 * fade)
            g.polygon("fill", otX, otY, shot.x + px * 4.4, shot.y + py * 4.4, shot.x - px * 4.4, shot.y - py * 4.4)
            g.setColor(1.0, 0.62, 0.28, 0.78 * fade)
            g.polygon("fill", otX, otY, shot.x + px * 2.6, shot.y + py * 2.6, shot.x - px * 2.6, shot.y - py * 2.6)
            local coreLen = orbTrail * 0.62
            local ctX, ctY = shot.x - dx * coreLen, shot.y - dy * coreLen
            g.setColor(1.0, 0.94, 0.76, 0.88 * fade)
            g.polygon("fill", ctX, ctY, shot.x + px * 1.3, shot.y + py * 1.3, shot.x - px * 1.3, shot.y - py * 1.3)
            g.setColor(r, green, b, 0.32 * fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 2.15)
            g.setColor(1.0, 0.67, 0.36, 0.82 * fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 1.22)
            g.setBlendMode("alpha")
            g.setLineWidth(1.0)
            g.setColor(1.0, 0.62, 0.34, 0.85 * fade)
            g.circle("line", shot.x, shot.y, profile.radius * 1.15)
            g.setColor(1.0, 0.976, 0.902, fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 0.65)
        elseif profile.isLaser then
            -- VE2A Tapered Orchid-Magenta Lance Tail + VE2B Twin-Prong Diamond Bolt Head
            local px, py = -dy, dx
            local lanceTrail = math.min(profile.trail * 1.18, profile.radius + length * shot.age)
            local ltX, ltY = shot.x - dx * lanceTrail, shot.y - dy * lanceTrail
            g.setBlendMode("add")
            g.setColor(r, green, b, 0.30 * fade)
            g.polygon("fill", ltX, ltY, shot.x + px * 5.8, shot.y + py * 5.8, shot.x - px * 5.8, shot.y - py * 5.8)
            g.setColor(r, math.min(1, green + 0.14), math.min(1, b + 0.08), 0.80 * fade)
            g.polygon("fill", ltX, ltY, shot.x + px * 3.0, shot.y + py * 3.0, shot.x - px * 3.0, shot.y - py * 3.0)
            local filX, filY = shot.x - dx * (lanceTrail * 0.65), shot.y - dy * (lanceTrail * 0.65)
            g.setLineWidth(2.0)
            g.setColor(1.0, 0.94, 1.0, 0.90 * fade)
            g.line(filX, filY, shot.x, shot.y)
            g.setColor(r, green, b, 0.36 * fade)
            g.circle("fill", shot.x, shot.y, 8.5)
            g.setBlendMode("alpha")

            local tipX, tipY = shot.x + dx * 10.5, shot.y + dy * 10.5
            local notchX, notchY = shot.x - dx * 5.5, shot.y - dy * 5.5
            local shLX, shLY = shot.x - dx * 1.5 + px * 4.2, shot.y - dy * 1.5 + py * 4.2
            local shRX, shRY = shot.x - dx * 1.5 - px * 4.2, shot.y - dy * 1.5 - py * 4.2
            local prLX, prLY = shot.x - dx * 11.5 + px * 3.0, shot.y - dy * 11.5 + py * 3.0
            local prRX, prRY = shot.x - dx * 11.5 - px * 3.0, shot.y - dy * 11.5 - py * 3.0
            g.setColor(1.0, 0.97, 1.0, fade)
            g.polygon("fill", tipX, tipY, shLX, shLY, prLX, prLY, notchX, notchY)
            g.polygon("fill", tipX, tipY, notchX, notchY, prRX, prRY, shRX, shRY)
            g.setLineWidth(1.0)
            g.setColor(r, math.min(1, green + 0.12), math.min(1, b + 0.10), 0.92 * fade)
            g.polygon("line", tipX, tipY, shLX, shLY, prLX, prLY, notchX, notchY, prRX, prRY, shRX, shRY)
        else
            g.setLineWidth(profile.radius * 1.8)
            g.setColor(r, green, b, 0.25 * fade)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setLineWidth(1.5)
            g.setColor(r, green, b, 0.9 * fade)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setColor(1, 0.85, 0.75, fade)
            g.circle("fill", shot.x, shot.y, profile.radius * 0.55)
        end
    end
    for _, effect in ipairs(self.impacts) do
        local progress = effect.age / impactLifetime
        local r, green, b = unpack(effect.profile.color)
        if effect.shield then
            r, green, b = 0.30, 0.70, 1
        elseif effect.dissipate then
            r, green, b = 0.68, 0.90, 1.0
        end
        g.setLineWidth(1.5)
        g.setColor(r, green, b, 0.8 * (1 - progress))
        g.circle("line", effect.x, effect.y, 4 + progress * effect.profile.radius * 4)
    end
    g.pop()
end

function EnemyFire:captureReplayState(caps)
    local shotCap = (caps and caps.shots) or 512
    local impactCap = (caps and caps.impacts) or 128

    local shots = {}
    local sList = self.shots or {}
    local sCnt = math.min(#sList, shotCap)
    for i = 1, sCnt do
        local src = sList[i]
        shots[i] = {
            x = src.x or 0,
            y = src.y or 0,
            vx = src.vx or 0,
            vy = src.vy or 0,
            age = src.age or 0,
            lifetime = src.lifetime or (src.profile and src.profile.lifetime) or 1.65,
            profile = src.profile or bullet,
            harmless = src.harmless,
            harmlessStartAge = src.harmlessStartAge,
            harmlessExpireAt = src.harmlessExpireAt,
        }
    end

    local impacts = {}
    local imList = self.impacts or {}
    local imCnt = math.min(#imList, impactCap)
    for i = 1, imCnt do
        local src = imList[i]
        impacts[i] = {
            x = src.x or 0,
            y = src.y or 0,
            age = src.age or 0,
            profile = src.profile or bullet,
            shield = src.shield and true or false,
            dissipate = src.dissipate and true or false,
        }
    end

    return {
        shots = shots,
        impacts = impacts,
    }
end

function EnemyFire.buildReplayProxy(s0, s1, alpha, dt)
    if not s0 then
        return setmetatable({ shots = {}, bursts = {}, impacts = {} }, EnemyFire)
    end
    local step = math.max(0, dt or 0)
    local shots = {}
    for _, s in ipairs(s0.shots or {}) do
        local age = (s.age or 0) + step
        local maxLife = s.harmlessExpireAt or s.lifetime or (s.profile and s.profile.lifetime) or 1.65
        if age < maxLife then
            shots[#shots + 1] = {
                x = (s.x or 0) + (s.vx or 0) * step,
                y = (s.y or 0) + (s.vy or 0) * step,
                vx = s.vx or 0,
                vy = s.vy or 0,
                age = age,
                lifetime = s.lifetime or maxLife,
                profile = s.profile or bullet,
                harmless = s.harmless,
                harmlessStartAge = s.harmlessStartAge,
                harmlessExpireAt = s.harmlessExpireAt,
            }
        end
    end

    local impacts = {}
    for _, im in ipairs(s0.impacts or {}) do
        local age = (im.age or 0) + step
        if age < EnemyFire.impactLifetime then
            impacts[#impacts + 1] = {
                x = im.x or 0,
                y = im.y or 0,
                age = age,
                profile = im.profile or bullet,
                shield = im.shield == true,
                dissipate = im.dissipate == true,
            }
        end
    end

    return setmetatable({
        shots = shots,
        bursts = {},
        impacts = impacts,
    }, EnemyFire)
end

return EnemyFire
