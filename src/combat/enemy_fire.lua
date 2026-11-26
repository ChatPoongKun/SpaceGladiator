local Arena = require("src.core.arena")
local Collision = require("src.core.collision")
local Sfx = require("src.audio.sfx")
local EnemyFire = {}
EnemyFire.__index = EnemyFire

local burstInterval = 0.12
local impactLifetime = 0.24
local missileAngles = {-60, -36, -12, 12, 36, 60}
local missileTurnRate = 3.35
local missileTurnRamp = 0.42
local tau = 2 * math.pi
local bullet = {speed = 440, lifetime = 1.65, radius = 3.5, damage = 6, trail = 15, color = {1, 0.45, 0.23}, replayKind = 1}
local laser = {speed = 1150, lifetime = 0.95, radius = 4.5, damage = 14, trail = 56, color = {1, 0.24, 0.65}, isLaser = true, replayKind = 2}
local missile = {radius = 5, damage = 8, trail = 24, color = {1, 0.28, 0.28}, isMissile = true, replayKind = 3}
local curtain = {speed = 255, lifetime = 3.8, radius = 5.0, damage = 7, trail = 10, color = {1.0, 0.78, 0.24}, isOrb = true, replayKind = 4}

EnemyFire.wedgeSpread = math.rad(16)
EnemyFire.railCount = 3
EnemyFire.railInterval = 0.055
EnemyFire.curtainWaveInterval = 0.34
EnemyFire.curtainOddAngles = {0, -18, 18, -36, 36}
EnemyFire.curtainEvenAngles = {-9, 9, -27, 27, -45, 45}
EnemyFire.missileStaggerInterval = 0.11
EnemyFire.missileStaggerOrder = {-58, 58, -34, 34, -12, 12}
EnemyFire.missileFlankOffsets = {-48, 48, -26, 26, -10, 10}

local wedgeFanOffsets = {0, -EnemyFire.wedgeSpread, EnemyFire.wedgeSpread}

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

local function launchAngle(fire, enemy, angle, profile, delay, sfxName, pitchScale)
    local shot = launch(fire, enemy, angle, profile, delay)
    shot.vx, shot.vy = shot.vx * profile.speed, shot.vy * profile.speed
    shot.lifetime = profile.lifetime
    if sfxName then
        Sfx.play(sfxName, pitchScale)
    end
    return shot
end

local function launchMissile(fire, enemy, targetX, targetY, baseAngle, distance, angleOffsetDeg, flankOffset, delay)
    local reach = math.max(34, math.min(135, distance * 0.46))
    local lifetime = math.max(0.6, distance / 375 + 0.15)
    local tx, ty = targetX, targetY
    if flankOffset and flankOffset ~= 0 then
        local perpX, perpY = -math.sin(baseAngle), math.cos(baseAngle)
        tx = math.max(20, math.min(Arena.width - 20, tx + perpX * flankOffset))
        ty = math.max(20, math.min(Arena.height - 20, ty + perpY * flankOffset))
    end
    local shot = launch(fire, enemy, baseAngle + math.rad(angleOffsetDeg), missile, delay)
    shot.startX, shot.startY = shot.x, shot.y
    shot.controlX, shot.controlY = shot.x + shot.vx * reach, shot.y + shot.vy * reach
    shot.targetX, shot.targetY = tx, ty
    shot.lifetime = lifetime
    shot.vx, shot.vy = shot.vx * 2 * reach / lifetime, shot.vy * 2 * reach / lifetime
    return shot
end

function EnemyFire:shoot(enemy, ship, opts)
    if not ship or ship:isDestroyed() then return nil end
    opts = opts or {}
    local targetX, targetY = ship.x, ship.y
    if enemy.kind == 1 then
        local baseAngle = opts.angle or bearing(enemy, targetX, targetY)
        for _, offset in ipairs(wedgeFanOffsets) do
            launchAngle(self, enemy, baseAngle + offset, bullet, 0)
        end
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
    else
        local baseAngle, distance = bearing(enemy, targetX, targetY)
        if opts.pattern == "curtain" then
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
        elseif opts.pattern == "missile_stagger" then
            launchMissile(self, enemy, targetX, targetY, baseAngle, distance,
                EnemyFire.missileStaggerOrder[1], EnemyFire.missileFlankOffsets[1], 0)
            Sfx.play("enemyMissile")
            local burst = {
                kind = "missile_stagger",
                enemy = enemy,
                index = 2,
                count = #EnemyFire.missileStaggerOrder,
                remaining = #EnemyFire.missileStaggerOrder - 1,
                delay = EnemyFire.missileStaggerInterval,
            }
            self.bursts[#self.bursts + 1] = burst
            return burst
        else
            for _, offsetDeg in ipairs(missileAngles) do
                launchMissile(self, enemy, targetX, targetY, baseAngle, distance, offsetDeg, 0, 0)
            end
            Sfx.play("enemyMissile")
            return nil
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

local function offsetPoint(x, y, heading, forward, sideways)
    local dx, dy = math.cos(heading), math.sin(heading)
    return x + dx * forward - dy * sideways, y + dy * forward + dx * sideways
end

-- Distance is in turn radii. This integrates a constant-speed ramp with a linearly rising turn rate.
local function rampPose(distance, ramp)
    if ramp == 0 then return 0, 0, 0 end
    local angle = distance * distance / (2 * ramp)
    local square = angle * angle
    local forward = distance * (1 - square / 10 + square * square / 216)
    local sideways = distance * angle * (1 / 3 - square / 42 + square * square / 1320)
    return forward, sideways, angle
end

local function planBank(x, y, heading, radius, targetX, targetY, ramp)
    local forward, sideways, entryAngle = rampPose(ramp, ramp)
    local tangentRadius = math.cos(entryAngle) + sideways
    local exitAdvance = forward - math.sin(entryAngle)
    local samePoint = (targetX - x) ^ 2 + (targetY - y) ^ 2 < 1e-12
    if samePoint and ramp > 0 then return end
    local best
    for direction = -1, 1, 2 do
        local entryHeading = heading + direction * entryAngle
        local px, py = offsetPoint(x, y, heading, radius * forward, direction * radius * sideways)
        local cx, cy = offsetPoint(px, py, entryHeading, 0, direction * radius)
        local dx, dy = (targetX - cx) / radius, (targetY - cy) / radius
        local distanceSquared = dx * dx + dy * dy
        if distanceSquared >= tangentRadius ^ 2 or samePoint then
            local sweep, straight = tau, 0
            if not samePoint then
                straight = math.sqrt(math.max(0, distanceSquared - tangentRadius ^ 2)) - exitAdvance
                local finalHeading = math.atan2(dy, dx) + direction * math.asin(math.min(1, tangentRadius / math.sqrt(distanceSquared)))
                sweep = ((finalHeading - entryHeading) * direction - entryAngle) % tau
                if sweep > tau - 1e-9 then sweep = 0 end
            end
            if straight >= -1e-9 then
                local length = 2 * ramp + sweep + math.max(0, straight)
                if not best or length < best.length then
                    local exitHeading = heading + direction * (sweep + ramp)
                    local exitX, exitY = offsetPoint(cx, cy, exitHeading, radius * exitAdvance,
                        -direction * radius * tangentRadius)
                    best = {direction = direction, cx = cx, cy = cy, radial = entryHeading - direction * math.pi / 2,
                        sweep = sweep, ramp = ramp, length = length, exitHeading = exitHeading, exitX = exitX, exitY = exitY}
                end
            end
        end
    end
    return best
end

local function beginSecondLeg(shot, targetX, targetY)
    local speed = math.sqrt(shot.vx ^ 2 + shot.vy ^ 2)
    local heading = math.atan2(shot.vy, shot.vx)
    local radius = speed / missileTurnRate
    local direct = planBank(shot.x, shot.y, heading, radius, targetX, targetY, 0)
    local leg = direct
    local ramp = math.min(missileTurnRamp, direct.sweep * 0.5)
    -- Shallow or very short approaches may need a shorter ramp to avoid another orbit.
    while ramp >= 1e-4 do
        local bank = planBank(shot.x, shot.y, heading, radius, targetX, targetY, ramp)
        if bank and bank.length < direct.length + math.pi / 2 then
            leg = bank
            break
        end
        ramp = ramp * 0.5
    end

    leg.startX, leg.startY, leg.heading = shot.x, shot.y, heading
    leg.radius, leg.speed, leg.started, leg.x, leg.y = radius, speed, shot.age, targetX, targetY
    shot.secondLeg = leg
    shot.lifetime = shot.age + leg.length / missileTurnRate
end

local function secondLegPose(leg, distance)
    local direction, radius = leg.direction, leg.radius
    local ramp = leg.ramp
    if distance < ramp then
        local forward, sideways, angle = rampPose(distance, ramp)
        local x, y = offsetPoint(leg.startX, leg.startY, leg.heading, radius * forward, direction * radius * sideways)
        return x, y, leg.heading + direction * angle
    end
    distance = distance - ramp
    if distance < leg.sweep then
        local radial = leg.radial + direction * distance
        return leg.cx + math.cos(radial) * radius, leg.cy + math.sin(radial) * radius, radial + direction * math.pi / 2
    end
    distance = distance - leg.sweep
    if distance < ramp then
        local forward, sideways, angle = rampPose(ramp - distance, ramp)
        local x, y = offsetPoint(leg.exitX, leg.exitY, leg.exitHeading, -radius * forward, direction * radius * sideways)
        return x, y, leg.exitHeading - direction * angle
    end
    local x, y = offsetPoint(leg.exitX, leg.exitY, leg.exitHeading, radius * (distance - ramp), 0)
    return x, y, leg.exitHeading
end

local function moveShot(shot, step)
    shot.age = shot.age + step
    local leg = shot.secondLeg
    if leg then
        local distance = (shot.age - leg.started) * missileTurnRate
        local x, y, heading = secondLegPose(leg, distance)
        shot.x, shot.y = x, y
        shot.vx, shot.vy = math.cos(heading) * leg.speed, math.sin(heading) * leg.speed
        if shot.age >= shot.lifetime - 1e-9 then shot.x, shot.y = leg.x, leg.y end
    elseif shot.profile == missile then
        local t = math.min(1, shot.age / shot.lifetime)
        local u = 1 - t
        -- Each curve leaves along its own launch angle and ends at the locked aim point.
        shot.x = u * u * shot.startX + 2 * u * t * shot.controlX + t * t * shot.targetX
        shot.y = u * u * shot.startY + 2 * u * t * shot.controlY + t * t * shot.targetY
        shot.vx = 2 * (u * (shot.controlX - shot.startX) + t * (shot.targetX - shot.controlX)) / shot.lifetime
        shot.vy = 2 * (u * (shot.controlY - shot.startY) + t * (shot.targetY - shot.controlY)) / shot.lifetime
    else
        shot.x, shot.y = shot.x + shot.vx * step, shot.y + shot.vy * step
    end
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
            if missileSteps and shot.profile == missile then
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
                        if gladiator:observeMissileThreat(clearance, relativeSpeed, grazeX, grazeY) then
                            missileThreatened = true
                        end
                    end
                end
            end
        end
    end

    for i = #fire.shots, 1, -1 do
        local shot = fire.shots[i]
        if shot.spent then
            table.remove(fire.shots, i)
        elseif shot.age >= shot.lifetime - 1e-9 then
            if shot.profile == missile and not shot.secondLeg then
                local x = (motion.x + motion.vx * finish) % Arena.width
                local y = (motion.y + motion.vy * finish) % Arena.height
                beginSecondLeg(shot, x, y)
            else
                if shot.profile == missile then impact(fire, shot, shot.x, shot.y) end
                table.remove(fire.shots, i)
            end
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
                elseif burst.kind == "missile_stagger" then
                    local baseAngle, distance = bearing(burst.enemy, ship.x, ship.y)
                    launchMissile(self, burst.enemy, ship.x, ship.y, baseAngle, distance,
                        EnemyFire.missileStaggerOrder[burst.index],
                        EnemyFire.missileFlankOffsets[burst.index], shotDelay)
                    Sfx.play("enemyMissile", 0.94 + (burst.index % 2) * 0.12)
                    burst.index = burst.index + 1
                    burst.remaining = burst.remaining - 1
                    burst.delay = burst.delay + EnemyFire.missileStaggerInterval
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
        for _, shot in ipairs(self.shots) do
            if shot.profile == missile and not shot.secondLeg then
                local arrival = math.max(elapsed, shot.delay) + (shot.lifetime - shot.age)
                -- Sample the player at the waypoint event, then use the rest of the frame for the turn.
                if arrival > elapsed then finish = math.min(finish, arrival) end
            end
        end
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

local function drawMissileBurst(g, effect, progress)
    local radius = 4 + progress * 20
    local alpha = 1 - progress
    local glowR, glowG, glowB = 1.0, 0.28, 0.24
    local ringR, ringG, ringB = 1.0, 0.54, 0.32
    local coreR, coreG, coreB = 1.0, 0.88, 0.72
    if effect.shield then
        glowR, glowG, glowB = 0.20, 0.58, 1.0
        ringR, ringG, ringB = 0.35, 0.78, 1.0
        coreR, coreG, coreB = 0.82, 0.95, 1.0
    end
    g.setColor(glowR, glowG, glowB, alpha * 0.28)
    g.circle("fill", effect.x, effect.y, radius)
    g.setLineWidth(1.8 * alpha + 0.5)
    g.setColor(ringR, ringG, ringB, alpha * 0.9)
    g.circle("line", effect.x, effect.y, radius)
    g.setColor(coreR, coreG, coreB, alpha * 0.95)
    g.circle("fill", effect.x, effect.y, 5.5 * alpha)
    g.setLineWidth(1.2)
    g.setColor(ringR, ringG, ringB, alpha * 0.85)
    for i = 1, 6 do
        local angle = i * tau / 6
        local dx, dy = math.cos(angle), math.sin(angle)
        g.line(effect.x + dx * radius * 0.65, effect.y + dy * radius * 0.65,
            effect.x + dx * (radius + 4), effect.y + dy * (radius + 4))
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
        local trail = math.min(profile.trail, profile.radius + length * shot.age)
        local tailX, tailY = shot.x - dx * trail, shot.y - dy * trail
        if profile.isOrb then
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
        elseif profile == bullet then
            -- VE1B: Plasma Comet Orb (coral halo + amber orb + cream-white core + additive wake)
            local orbTrail = math.min(16, profile.radius + length * shot.age)
            local otX, otY = shot.x - dx * orbTrail, shot.y - dy * orbTrail
            g.setBlendMode("add")
            g.setLineWidth(5.2)
            g.setColor(r, green, b, 0.28 * fade)
            g.line(otX, otY, shot.x, shot.y)
            g.setLineWidth(2.2)
            g.setColor(1.0, 0.68, 0.36, 0.62 * fade)
            g.line(otX, otY, shot.x, shot.y)
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
        if effect.profile == missile and not effect.dissipate then
            drawMissileBurst(g, effect, progress)
        else
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
    end
    g.pop()
end

return EnemyFire
