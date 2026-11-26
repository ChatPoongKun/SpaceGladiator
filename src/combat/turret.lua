local Arena = require("src.core.arena")
local Sfx = require("src.audio.sfx")
local ModulesData = require("src.data.modules_data")
local Turret = {}
Turret.__index = Turret
local tau = 2 * math.pi
local muzzleLength = 22
local rocketMaxBend = 38
local beamLifetime = 0.10
local beamImpactLifetime = 0.22
local explosionColors = { glow = { 0.141, 0.549, 1.0 }, ring = { 0.220, 0.863, 1.0 }, core = { 0.933, 0.984, 1.0 } }
local beamImpactColors = { glow = {0.12, 0.68, 1}, ring = {0.30, 0.92, 1}, core = {0.83, 0.98, 1} }
local aimGlowMesh, aimCoreMesh, aimMeshesTried = nil, nil, false

local salvoEmberColors = {
    { 0.933, 0.984, 1.0 },
    { 0.220, 0.863, 1.0 },
    { 0.36, 0.68, 1.0 },
}

local function emberHash(idx)
    local v = math.sin(idx * 12.9898 + 78.233) * 43758.5453
    return v - math.floor(v)
end

local function recordRocketTrail(missile)
    missile.trail = missile.trail or {}
    local trail = missile.trail
    local n = #trail
    if n == 0 then
        trail[1] = { x = missile.x, y = missile.y }
        return
    end
    local last = trail[n]
    local dx, dy = missile.x - last.x, missile.y - last.y
    if dx * dx + dy * dy >= 16 then
        trail[n + 1] = { x = missile.x, y = missile.y }
        if #trail > 16 then
            table.remove(trail, 1)
        end
    end
end

local function spawnSalvoEmber(turret, x, y, dx, dy, speed, isBurst)
    turret.salvoEmbers = turret.salvoEmbers or {}
    turret.emberSeq = (turret.emberSeq or 0) + 1
    local seq = turret.emberSeq
    local h1, h2, h3, h4 = emberHash(seq * 4 + 1), emberHash(seq * 4 + 2), emberHash(seq * 4 + 3), emberHash(seq * 4 + 4)
    local px, py = -dy, dx
    local sx, sy, vx, vy, life
    if isBurst then
        local ang = h1 * tau
        local spd = 45 + h2 * 85
        sx, sy = x + math.cos(ang) * (2 + h3 * 6), y + math.sin(ang) * (2 + h3 * 6)
        vx, vy = math.cos(ang) * spd, math.sin(ang) * spd
        life = 0.28 + h4 * 0.20
    else
        local side = (seq % 2 == 0) and 1 or -1
        local latOff = side * (2.0 + h1 * 5.0)
        local backOff = 5.0 + h2 * 8.0
        local latSpd = side * (20 + h3 * 38)
        local backSpd = (speed or 300) * (0.08 + h4 * 0.07)
        sx = x - dx * backOff + px * latOff
        sy = y - dy * backOff + py * latOff
        vx = px * latSpd - dx * backSpd
        vy = py * latSpd - dy * backSpd
        life = 0.24 + h3 * 0.22
    end
    local col = salvoEmberColors[((seq - 1) % #salvoEmberColors) + 1]
    turret.salvoEmbers[#turret.salvoEmbers + 1] = {
        x = sx, y = sy, vx = vx, vy = vy,
        drag = 3.2, age = 0, lifetime = life,
        size = 1.0 + h2 * 1.1,
        r = col[1], g = col[2], b = col[3],
    }
end

local function updateSalvoEmbers(turret, dt)
    local embers = turret.salvoEmbers
    if not embers or dt <= 0 then return end
    for i = #embers, 1, -1 do
        local e = embers[i]
        e.age = e.age + dt
        if e.age >= e.lifetime then
            table.remove(embers, i)
        else
            local damp = math.exp(-e.drag * dt)
            e.vx = e.vx * damp
            e.vy = e.vy * damp
            e.x = e.x + e.vx * dt
            e.y = e.y + e.vy * dt
        end
    end
end

local defaultProjectile = ModulesData.getByWeaponIndex(1) or {}
Turret.turnSpeed = tau
Turret.missileSpeed = defaultProjectile.projectileSpeed or 900
Turret.missileLifetime = (defaultProjectile.projectileRange or 600) / Turret.missileSpeed
Turret.fireInterval = defaultProjectile.fireInterval or 0.18
Turret.baseDamage = defaultProjectile.damage or 5
Turret.inaccuracyRefDeg = 90
Turret.aimLineWidthRatio = 0.30
Turret.explosionLifetime = 0.45

Turret.impactSpecs = {
    scatter_ring = { lifetime = nil, emitEmbers = false, isSalvo = false },
    salvo_spark = { lifetime = nil, emitEmbers = true, emberCount = 7, isSalvo = true },
    beam_impact = { lifetime = beamImpactLifetime, radius = 28, colors = beamImpactColors, emitEmbers = false, isSalvo = false },
}

function Turret.new(initialAngle)
    return setmetatable({
        angle = (initialAngle or 0) % tau,
        weapon = nil, launchSide = 1, cooldown = 0, weaponCooldowns = {},
        missiles = {}, explosions = {}, salvoEmbers = {}, emberSeq = 0,
        beams = {}, burstQueue = {},
        shotsFired = 0, shotsHit = 0,
    }, Turret)
end

local function buildOffsets(baseCount, extraCount, baseSpread, extraSpreadRad)
    local total = math.max(1, math.floor((baseCount or 1) + (extraCount or 0)))
    if total == 1 then return { 0 } end
    local step = (baseSpread or 0) + (extraSpreadRad or 0) * 0.25
    local offsets = {}
    if total % 2 == 1 then
        offsets[1] = 0
        for k = 1, (total - 1) / 2 do
            offsets[#offsets + 1] = -k * step
            offsets[#offsets + 1] = k * step
        end
    else
        local half = (total - 1) * 0.5
        for i = 0, total - 1 do
            offsets[#offsets + 1] = (i - half) * step
        end
    end
    return offsets
end

local function sampleAngleJitter(turret, angleInaccuracy)
    if not angleInaccuracy or angleInaccuracy <= 0 then return 0 end
    local rng = turret.rng or math.random
    local maxRad = math.rad(angleInaccuracy * (Turret.inaccuracyRefDeg or 90))
    return (rng() * 2 - 1) * maxRad
end

local function sampleTargetScatter(turret, radius)
    if not radius or radius <= 0 then return 0, 0 end
    local rng = turret.rng or math.random
    local r = radius * math.sqrt(rng())
    local theta = rng() * tau
    return math.cos(theta) * r, math.sin(theta) * r
end

local function nearestEnemy(enemies, x, y, excludeX, excludeY, camera, width, height, excludeEnemy)
    if not enemies or not enemies.items then return nil end
    local best, bestDistSq = nil, math.huge
    for _, enemy in ipairs(enemies.items) do
        local intangible = enemy.phase == "warping" or enemy.phase == "edge_warning"
        if enemy ~= excludeEnemy and not intangible and (not enemies.isOnScreen or enemies:isOnScreen(enemy.x, enemy.y, camera, width, height)) then
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

Turret.fireModes = {}

function Turret.fireModes.beam(turret, ship, targetX, targetY, enemies, frameFraction, camera, width, height, cfg, opts, spec)
    local offsets = buildOffsets(spec.baseShotCount, spec.extraCount, spec.baseSpreadRad, spec.extraSpreadRad)
    turret.beams = turret.beams or {}
    local primaryBeam = nil
    local anyHit = false
    local impactSpec = Turret.impactSpecs[spec.impactStyle] or Turret.impactSpecs.beam_impact
    for _, offset in ipairs(offsets) do
        local a = (spec.baseAngle + offset + sampleAngleJitter(turret, spec.angleInaccuracy)) % tau
        local bdx, bdy = math.sin(a), -math.cos(a)
        local bx, by = ship.x + bdx * muzzleLength, ship.y + bdy * muzzleLength
        local hitX, hitY, hitEnemy
        if enemies then
            local entry, exit = camera:clipRay(bx, by, bdx, bdy, width, height)
            if exit then
                local t = frameFraction or 1
                hitX, hitY, _, hitEnemy = enemies:hitSegment(bx + bdx * entry, by + bdy * entry,
                    bx + bdx * exit, by + bdy * exit, t, t, camera, width, height, spec.damage)
            end
        end
        if hitX then
            anyHit = true
            turret.explosions[#turret.explosions + 1] = {
                x = hitX, y = hitY,
                radius = (impactSpec.radius or 28) * spec.areaMult,
                age = 0,
                lifetime = impactSpec.lifetime or beamImpactLifetime,
                colors = impactSpec.colors or beamImpactColors,
                style = spec.impactStyle,
                isSalvo = impactSpec.isSalvo == true,
                sparkAngle = impactSpec.isSalvo and (math.random() * tau) or nil,
            }
            if spec.bounces > 0 and enemies then
                local nxt = nearestEnemy(enemies, hitX, hitY, hitX, hitY, camera, width, height, hitEnemy)
                if nxt then
                    local rdx, rdy = nxt.x - hitX, nxt.y - hitY
                    local rlen = math.sqrt(rdx * rdx + rdy * rdy)
                    if rlen > 0 then
                        local rhx, rhy = enemies:hitSegment(hitX, hitY, nxt.x, nxt.y,
                            frameFraction or 1, frameFraction or 1, camera, width, height, spec.damage, hitEnemy)
                        if rhx then
                            turret.beams[#turret.beams + 1] = {
                                x = hitX, y = hitY, dx = rdx / rlen, dy = rdy / rlen,
                                hitX = rhx, hitY = rhy, age = 0, style = spec.projectileStyle,
                            }
                        end
                    end
                end
            end
        end
        local bObj = {
            x = bx, y = by, dx = bdx, dy = bdy, hitX = hitX, hitY = hitY, age = 0,
            style = spec.projectileStyle,
        }
        turret.beams[#turret.beams + 1] = bObj
        if not primaryBeam then primaryBeam = bObj end
    end
    if spec.fireSfx ~= "" then Sfx.play(spec.fireSfx) end
    if anyHit then
        turret.shotsHit = turret.shotsHit + 1
        if spec.impactSfx ~= "" then Sfx.play(spec.impactSfx) end
    end
    turret.beam = primaryBeam
    return turret.beam
end

function Turret.fireModes.rocket(turret, ship, targetX, targetY, enemies, frameFraction, camera, width, height, cfg, opts, spec)
    local shot = { hit = false }
    local offsets = buildOffsets(spec.baseShotCount, spec.extraCount, spec.baseSpreadRad, spec.extraSpreadRad)
    local def = spec.def
    local baseBlastRadius = (cfg and cfg.blastRadius ~= nil) and cfg.blastRadius
        or (def and def.blastRadius)
        or 90
    local rocketSpeed = (cfg and cfg.projectileSpeed ~= nil) and cfg.projectileSpeed
        or (def and def.projectileSpeed)
        or 600
    local maxRange = (cfg and cfg.projectileRange ~= nil) and cfg.projectileRange
        or (def and def.projectileRange)
    local ejectAngles = (cfg and cfg.ejectAnglesDeg) or (def and def.ejectAnglesDeg)
    local maxBend = (cfg and cfg.ejectBend) or (def and def.ejectBend) or rocketMaxBend
    local firstMissile = nil
    local distance = math.sqrt((targetX - spec.x) ^ 2 + (targetY - spec.y) ^ 2)
    for offsetIdx, offset in ipairs(offsets) do
        local a = (spec.baseAngle + offset + (offset ~= 0 and sampleAngleJitter(turret, spec.angleInaccuracy) or 0)) % tau
        local rdx, rdy = math.sin(a), -math.cos(a)
        local tx = targetX
        local ty = targetY
        if offset ~= 0 then
            tx = spec.x + rdx * math.max(120, distance)
            ty = spec.y + rdy * math.max(120, distance)
        end
        local sx, sy = sampleTargetScatter(turret, spec.targetScatterRadius)
        tx = tx + sx
        ty = ty + sy
        local dist = math.sqrt((tx - spec.x) ^ 2 + (ty - spec.y) ^ 2)
        if maxRange and maxRange > 0 and dist > maxRange then
            local scale = maxRange / dist
            tx = spec.x + (tx - spec.x) * scale
            ty = spec.y + (ty - spec.y) * scale
            dist = maxRange
        end
        local missile = {
            x = spec.x, y = spec.y, startX = spec.x, startY = spec.y,
            owner = ship, angle = a, distance = 0, age = 0, shot = shot,
            blastRadius = baseBlastRadius * spec.areaMult,
            damage = spec.damage,
            fireMode = "rocket",
            style = spec.projectileStyle,
            impactStyle = spec.impactStyle,
            impactSfx = spec.impactSfx,
            emitTrailEmbers = (spec.projectileStyle == "salvo_lance"),
            targetOffsetX = sx,
            targetOffsetY = sy,
        }
        local bend = math.min(maxBend, dist * 0.18)
        if ejectAngles and #ejectAngles > 0 then
            local angleIdx = (((spec.burstIndex or 1) - 1 + offsetIdx - 1) % #ejectAngles) + 1
            local ejectDeg = ejectAngles[angleIdx]
            local phi = math.rad(ejectDeg)
            local fdx = dist > 1e-6 and ((tx - spec.x) / dist) or rdx
            local fdy = dist > 1e-6 and ((ty - spec.y) / dist) or rdy
            local rx, ry = -fdy, fdx
            local ex = fdx * math.cos(phi) + rx * math.sin(phi)
            local ey = fdy * math.cos(phi) + ry * math.sin(phi)
            missile.bendX, missile.bendY = ex * bend * camera.zoom, ey * bend * camera.zoom
            missile.ejectAngleDeg = ejectDeg
        else
            local signedBend = turret.launchSide * bend
            turret.launchSide = -turret.launchSide
            missile.bendX, missile.bendY = -rdy * signedBend * camera.zoom, rdx * signedBend * camera.zoom
            missile.ejectAngleDeg = signedBend >= 0 and 90 or -90
        end
        missile.startScreenX, missile.startScreenY = camera:worldToScreen(spec.x, spec.y, width, height)
        missile.targetScreenX, missile.targetScreenY = camera:worldToScreen(tx, ty, width, height)
        missile.lifetime = dist / rocketSpeed
        missile.trail = { { x = spec.x, y = spec.y } }
        missile.emberAcc = 0
        updateRocketPose(missile, camera, width, height)
        recordRocketTrail(missile)
        turret.missiles[#turret.missiles + 1] = missile
        if not firstMissile then firstMissile = missile end
    end
    if spec.fireSfx ~= "" then Sfx.play(spec.fireSfx) end
    return firstMissile
end

function Turret.fireModes.projectile(turret, ship, targetX, targetY, enemies, frameFraction, camera, width, height, cfg, opts, spec)
    local shot = { hit = false }
    local vx, vy = ship:worldVelocity()
    local first = #turret.missiles + 1
    local offsets = buildOffsets(spec.baseShotCount, spec.extraCount, spec.baseSpreadRad, spec.extraSpreadRad)
    local def = spec.def
    local projSpeed = (cfg and cfg.projectileSpeed ~= nil) and cfg.projectileSpeed
        or (def and def.projectileSpeed)
        or turret.missileSpeed
    local projRange = (cfg and cfg.projectileRange ~= nil) and cfg.projectileRange
        or (def and def.projectileRange)
    local projLifetime = (cfg and cfg.projectileLifetime ~= nil) and cfg.projectileLifetime
        or (projRange and projSpeed > 0 and (projRange / projSpeed))
        or turret.missileLifetime
    for _, offset in ipairs(offsets) do
        local angle = (spec.baseAngle + offset + sampleAngleJitter(turret, spec.angleInaccuracy)) % tau
        local shotVx = math.sin(angle) * projSpeed + vx
        local shotVy = -math.cos(angle) * projSpeed + vy
        turret.missiles[#turret.missiles + 1] = {
            x = spec.x, y = spec.y, startX = spec.x, startY = spec.y,
            owner = ship, angle = angle, distance = 0, age = 0, shot = shot,
            vx = shotVx, vy = shotVy, speed = math.sqrt(shotVx ^ 2 + shotVy ^ 2),
            lifetime = projLifetime,
            baseLifetime = projLifetime,
            homing = cfg and cfg.homing or false,
            homingTurnRate = cfg and cfg.homingTurnRate or 0,
            bounces = spec.bounces,
            damage = spec.damage,
            fireMode = "projectile",
            style = spec.projectileStyle,
            impactStyle = spec.impactStyle,
            impactSfx = spec.impactSfx,
            emitTrailEmbers = (spec.projectileStyle == "salvo_lance"),
        }
    end
    if spec.fireSfx ~= "" then Sfx.play(spec.fireSfx) end
    return turret.missiles[first]
end

function Turret:fire(ship, targetX, targetY, enemies, frameFraction, camera, width, height, weaponBuild, opts)
    opts = opts or {}
    local cfg = weaponBuild
    local weapon = opts.weapon or (cfg and cfg.weaponIndex) or self.weapon
    if not weapon and not (cfg and cfg.fireMode) then return nil end
    local baseAngle = opts.angle or self.angle
    local batteryCost = (cfg and not opts.free) and (cfg.batteryCost or 0) or 0
    if batteryCost > 0 then
        if (ship.battery or 0) < batteryCost then return nil end
        ship.battery = ship.battery - batteryCost
    end

    local def = weapon and ModulesData.getByWeaponIndex(weapon) or nil

    -- Queue module-defined salvo shots plus any burst support chip follow-ups.
    local baseBurstCount = math.max(1, math.floor((cfg and cfg.burstCount ~= nil) and cfg.burstCount
        or (def and def.burstCount)
        or 1))
    local extraBurst = (cfg and cfg.extraBurst) or 0
    local totalFollowUps = math.max(0, (baseBurstCount - 1) + extraBurst)
    local burstInterval = (cfg and cfg.burstInterval ~= nil) and cfg.burstInterval
        or (def and def.burstInterval)
        or 0.06
    if totalFollowUps > 0 and not opts.fromBurst then
        for b = 1, totalFollowUps do
            self.burstQueue[#self.burstQueue + 1] = {
                delay = b * burstInterval,
                weapon = weapon,
                angle = opts.angle,
                targetX = targetX,
                targetY = targetY,
                weaponBuild = cfg,
                free = true,
                burstIndex = b + 1,
            }
        end
    end

    self.shotsFired = self.shotsFired + 1
    local fireMode = (cfg and cfg.fireMode)
        or (def and def.fireMode)
        or (weapon == 3 and "beam" or (weapon == 2 and "rocket" or "projectile"))
    local projectileStyle = (cfg and cfg.projectileStyle)
        or (def and def.projectileStyle)
        or (fireMode == "beam" and "snap_beam" or (fireMode == "rocket" and "salvo_lance" or "twin_dart"))
    local impactStyle = (cfg and cfg.impactStyle)
        or (def and def.impactStyle)
        or (fireMode == "beam" and "beam_impact" or (fireMode == "rocket" and "salvo_spark" or "scatter_ring"))
    local fireSfx = (cfg and cfg.fireSfx ~= nil) and cfg.fireSfx
        or (def and def.fireSfx)
        or (fireMode == "beam" and "laser" or (fireMode == "rocket" and "missile" or "projectile"))
    local impactSfx = (cfg and cfg.impactSfx ~= nil) and cfg.impactSfx
        or (def and def.impactSfx)
        or "impact"

    local baseDamage = (cfg and cfg.damage ~= nil) and cfg.damage
        or (def and def.damage)
        or self.baseDamage
        or Turret.baseDamage
    local baseShotCount = (cfg and cfg.shotCount ~= nil) and cfg.shotCount
        or (def and def.shotCount)
        or 1
    local baseSpreadRad = math.rad((cfg and cfg.spreadDeg ~= nil) and cfg.spreadDeg
        or (def and def.spreadDeg)
        or 0)
    local angleInaccuracy = (cfg and cfg.angleInaccuracy ~= nil) and cfg.angleInaccuracy
        or (def and def.angleInaccuracy)
        or 0
    local targetScatterRadius = (cfg and cfg.targetScatterRadius ~= nil) and cfg.targetScatterRadius
        or (def and def.targetScatterRadius)
        or 0
    local dx, dy = math.sin(baseAngle), -math.cos(baseAngle)
    local spec = {
        weapon = weapon,
        def = def,
        fireMode = fireMode,
        projectileStyle = projectileStyle,
        impactStyle = impactStyle,
        fireSfx = fireSfx,
        impactSfx = impactSfx,
        baseAngle = baseAngle,
        x = ship.x + dx * muzzleLength,
        y = ship.y + dy * muzzleLength,
        extraCount = cfg and cfg.extraCount or 0,
        extraSpreadRad = cfg and math.rad(cfg.extraSpreadDeg or 0) or 0,
        areaMult = (cfg and cfg.areaMult or 1) * (opts.areaMult or 1),
        bounces = cfg and cfg.bounces or 0,
        damage = math.max(0.1, baseDamage * (cfg and cfg.damageMult or 1)),
        baseShotCount = baseShotCount,
        baseSpreadRad = baseSpreadRad,
        angleInaccuracy = angleInaccuracy,
        targetScatterRadius = targetScatterRadius,
        burstIndex = opts.burstIndex or 1,
    }
    local handler = Turret.fireModes[fireMode] or Turret.fireModes.projectile
    return handler(self, ship, targetX, targetY, enemies, frameFraction, camera, width, height, cfg, opts, spec)
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

local function getWeaponKey(wCfg, fallbackIdx)
    return wCfg.moduleId or wCfg.id or ("weapon_" .. tostring(wCfg.weaponIndex or fallbackIdx))
end

local function getWeaponInterval(turret, wCfg)
    local def = wCfg and wCfg.weaponIndex and ModulesData.getByWeaponIndex(wCfg.weaponIndex) or nil
    local base = (wCfg and wCfg.fireInterval)
        or (def and def.fireInterval)
        or turret.fireInterval
    local cdMult = wCfg and ((wCfg.cooldownMult or 1) * (wCfg.manualCooldownMult or 1)) or 1
    return math.max(0.02, base * cdMult)
end

local function canAffordWeapon(ship, wCfg)
    local cost = wCfg and wCfg.batteryCost or 0
    return cost <= 0 or (ship and (ship.battery or 0) >= cost)
end

local function resolveActiveWeapons(turret, weaponInput)
    if weaponInput == nil then
        if turret.weapon then
            return { { weaponIndex = turret.weapon } }
        end
        return {}
    end
    if type(weaponInput) ~= "table" then
        return {}
    end
    if weaponInput.weaponModules ~= nil then
        return weaponInput.weaponModules
    end
    if weaponInput.weaponIndex ~= nil or weaponInput.fireMode ~= nil then
        if weaponInput.installed == false or weaponInput.disabled then
            return {}
        end
        return { weaponInput }
    end
    return weaponInput
end

function Turret:update(dt, ship, mouseWorldX, mouseWorldY, firing, enemies, camera, width, height, weaponInput)
    dt = math.max(0, dt)
    local dx, dy = mouseWorldX - ship.x, mouseWorldY - ship.y
    if dx ~= 0 or dy ~= 0 then
        local target = math.atan2(dx, -dy)
        local delta = (target - self.angle + math.pi) % tau - math.pi
        local limit = self.turnSpeed * dt
        self.angle = (self.angle + math.max(-limit, math.min(limit, delta))) % tau
    end

    local activeWeapons = resolveActiveWeapons(self, weaponInput)
    self.weaponCooldowns = self.weaponCooldowns or {}
    local eps = 1e-9

    -- Split at per-weapon shot times so held fire keeps each weapon's independent cadence at any frame rate.
    local remaining = dt
    repeat
        local step = remaining
        if firing and #activeWeapons > 0 then
            for idx, wCfg in ipairs(activeWeapons) do
                if wCfg and (wCfg.weaponIndex or wCfg.fireMode) and canAffordWeapon(ship, wCfg) then
                    local key = getWeaponKey(wCfg, idx)
                    local cd = self.weaponCooldowns[key] or 0
                    if cd < step then
                        step = cd
                    end
                end
            end
        end
        if self.burstQueue and #self.burstQueue > 0 then
            for _, q in ipairs(self.burstQueue) do
                if q.delay <= eps then
                    step = 0
                elseif q.delay < step then
                    step = q.delay
                end
            end
        end
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
                if q.delay <= eps then
                    table.remove(self.burstQueue, qi)
                    self:fire(ship, mouseWorldX, mouseWorldY, enemies,
                        dt > 0 and (dt - remaining + step) / dt or 0, camera, width, height,
                        q.weaponBuild, { weapon = q.weapon, angle = q.angle, free = q.free, fromBurst = true, burstIndex = q.burstIndex })
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
        updateSalvoEmbers(self, step)
        for i = #self.missiles, 1, -1 do
            local missile = self.missiles[i]
            local isRocket = missile.fireMode == "rocket" or missile.targetScreenX ~= nil
            local oldX, oldY = missile.x, missile.y
            local flightTime = math.min(step, missile.lifetime - missile.age)
            local elapsed = missile.age + step
            missile.age = math.min(missile.lifetime, elapsed)
            if isRocket then
                updateRocketPose(missile, camera, width, height)
                recordRocketTrail(missile)
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
            if (missile.emitTrailEmbers or (missile.emitTrailEmbers == nil and isRocket)) and flightTime > 0 and (missile.speed or 0) > 10 then
                missile.emberAcc = (missile.emberAcc or 0) + flightTime
                local dx, dy = missile.vx / missile.speed, missile.vy / missile.speed
                while missile.emberAcc >= 0.016 do
                    missile.emberAcc = missile.emberAcc - 0.016
                    spawnSalvoEmber(self, missile.x, missile.y, dx, dy, missile.speed, false)
                end
            end
            local hitX, hitY, hitTime, hitEnemy
            if enemies then
                local frameStart = dt > 0 and (dt - remaining) / dt or 0
                local frameEnd = dt > 0 and (dt - remaining + flightTime) / dt or 0
                if isRocket then
                    if enemies.findSegmentHit then
                        hitX, hitY, hitTime, _, hitEnemy = enemies:findSegmentHit(oldX, oldY, missile.x, missile.y,
                            frameStart, frameEnd, camera, width, height, missile.lastHitEnemy)
                    end
                else
                    hitX, hitY, hitTime, hitEnemy = enemies:hitSegment(oldX, oldY, missile.x, missile.y,
                        frameStart, frameEnd, camera, width, height, missile.damage, missile.lastHitEnemy)
                end
            end
            if hitX or elapsed >= missile.lifetime then
                local age = hitX and step - flightTime * hitTime or elapsed - missile.lifetime
                local x, y = hitX or missile.x, hitY or missile.y
                local hit = hitX ~= nil
                local rRadius = missile.blastRadius
                    or (ModulesData.getByWeaponIndex(2) and ModulesData.getByWeaponIndex(2).blastRadius)
                    or 90
                if enemies and isRocket then
                    local hitOffset = hitX and (flightTime * hitTime) or flightTime
                    local fraction = dt > 0 and (dt - remaining + hitOffset) / dt or 0
                    hit = enemies:hitArea(x, y, rRadius, fraction, camera, width, height, missile.damage)
                end
                if hit and not missile.shot.hit then
                    missile.shot.hit = true
                    self.shotsHit = self.shotsHit + 1
                end
                local impactSfx = missile.impactSfx ~= nil and missile.impactSfx or "impact"
                if (hitX or isRocket) and impactSfx ~= "" then Sfx.play(impactSfx) end
                local impactStyle = missile.impactStyle or (isRocket and "salvo_spark" or "scatter_ring")
                local impactSpec = Turret.impactSpecs[impactStyle] or Turret.impactSpecs.scatter_ring
                if impactSpec.emitEmbers then
                    for _ = 1, (impactSpec.emberCount or 7) do
                        spawnSalvoEmber(self, x, y, 1, 0, 0, true)
                    end
                end
                if age < (impactSpec.lifetime or self.explosionLifetime) then
                    self.explosions[#self.explosions + 1] = {
                        x = x, y = y,
                        radius = isRocket and rRadius or impactSpec.radius,
                        age = age,
                        lifetime = impactSpec.lifetime or self.explosionLifetime,
                        colors = impactSpec.colors,
                        style = impactStyle,
                        isSalvo = impactSpec.isSalvo == true,
                        sparkAngle = impactSpec.isSalvo and (math.random() * tau) or nil,
                    }
                end
                if hitX and not isRocket and (missile.bounces or 0) > 0 and enemies then
                    local nxt = nearestEnemy(enemies, x, y, x, y, camera, width, height, hitEnemy)
                    if nxt then
                        local bdx, bdy = nxt.x - x, nxt.y - y
                        local blen = math.sqrt(bdx * bdx + bdy * bdy)
                        if blen > 0 then
                            missile.bounces = missile.bounces - 1
                            missile.lastHitEnemy = hitEnemy
                            missile.startX, missile.startY = x, y
                            missile.x, missile.y = x, y
                            missile.vx, missile.vy = (bdx / blen) * missile.speed, (bdy / blen) * missile.speed
                            missile.age = 0
                            missile.lifetime = (missile.baseLifetime or self.missileLifetime) * 0.7
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
        for key, cd in pairs(self.weaponCooldowns) do
            local nextCd = cd - step
            if nextCd <= eps then
                self.weaponCooldowns[key] = nil
            else
                self.weaponCooldowns[key] = nextCd
            end
        end
        if firing and #activeWeapons > 0 then
            local frameFraction = dt > 0 and (dt - remaining) / dt or 0
            for idx, wCfg in ipairs(activeWeapons) do
                if wCfg and (wCfg.weaponIndex or wCfg.fireMode) then
                    local key = getWeaponKey(wCfg, idx)
                    local cd = self.weaponCooldowns[key] or 0
                    if cd <= eps and canAffordWeapon(ship, wCfg) then
                        local fired = self:fire(ship, mouseWorldX, mouseWorldY, enemies,
                            frameFraction, camera, width, height, wCfg, { weapon = wCfg.weaponIndex })
                        if fired ~= nil then
                            self.weaponCooldowns[key] = getWeaponInterval(self, wCfg)
                        end
                    end
                end
            end
        end
    until remaining <= eps

    local minCd = math.huge
    for _, cd in pairs(self.weaponCooldowns) do
        if cd < minCd then minCd = cd end
    end
    self.cooldown = minCd < math.huge and minCd or 0
end

function Turret:clearEffects()
    self.missiles = {}
    self.explosions = {}
    self.beams = {}
    self.beam = nil
    self.burstQueue = {}
    self.weaponCooldowns = {}
    self.cooldown = 0
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
    if self.weaponCooldowns then
        for key, cd in pairs(self.weaponCooldowns) do
            local nextCd = cd - dt
            if nextCd <= 1e-9 then
                self.weaponCooldowns[key] = nil
            else
                self.weaponCooldowns[key] = nextCd
            end
        end
    end

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
    updateSalvoEmbers(self, dt)

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
                recordRocketTrail(missile)
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

Turret.projectileRenderers = {}

function Turret.projectileRenderers.salvo_lance(g, missile, dx, dy, fade)
    -- VE3D-inspired Player Salvo: cyan serrated lance-dart + gradient-fading wake + scattered dots
    local px, py = -dy, dx
    local mx, my = missile.x, missile.y
    local pts = {}
    if missile.trail and #missile.trail >= 2 then
        for ti = 1, #missile.trail do
            pts[ti] = missile.trail[ti]
        end
        pts[#pts + 1] = { x = mx, y = my }
    else
        local fallbackLen = math.min(34, missile.speed * math.min(0.055, missile.age or 0))
        if fallbackLen > 0 then
            for si = 5, 0, -1 do
                local d = fallbackLen * (si / 5)
                pts[#pts + 1] = { x = mx - dx * d, y = my - dy * d }
            end
        end
    end

    g.setBlendMode("add")
    if #pts >= 2 then
        local segCount = #pts - 1
        for si = 1, segCount do
            local p0, p1 = pts[si], pts[si + 1]
            local frac = si / segCount
            local gAlpha = (frac ^ 1.65) * fade
            g.setLineWidth(1.2 + 4.4 * frac)
            g.setColor(0.141, 0.549, 1.0, 0.34 * gAlpha)
            g.line(p0.x, p0.y, p1.x, p1.y)
            g.setLineWidth(0.6 + 2.0 * frac)
            g.setColor(0.220, 0.863, 1.0, 0.85 * gAlpha)
            g.line(p0.x, p0.y, p1.x, p1.y)
            if frac > 0.45 then
                local coreAlpha = ((frac - 0.45) / 0.55) * fade
                g.setLineWidth(0.9 * frac)
                g.setColor(0.933, 0.984, 1.0, 0.82 * coreAlpha)
                g.line(p0.x, p0.y, p1.x, p1.y)
            end
        end
        if not missile.trail or #missile.trail < 2 then
            for di = 1, 3 do
                local f = di / 4
                local side = (di % 2 == 0) and 1 or -1
                local sx = mx - dx * (30 * f) + px * (side * (3.5 + di))
                local sy = my - dy * (30 * f) + py * (side * (3.5 + di))
                g.setColor(0.220, 0.863, 1.0, 0.65 * (1 - f) * fade)
                g.circle("fill", sx, sy, 1.5)
            end
        end
    end

    g.setColor(0.220, 0.863, 1.0, 0.34 * fade)
    g.circle("fill", mx, my, 9.0)
    g.setColor(0.72, 0.96, 1.0, 0.65 * fade)
    g.circle("fill", mx - dx * 5.0, my - dy * 5.0, 4.0)
    g.setBlendMode("alpha")

    -- Serrated lance-dart warhead (split into 2 strictly convex triangles around rear notch)
    local tipX, tipY = mx + dx * 9.0, my + dy * 9.0
    local notchX, notchY = mx - dx * 5.0, my - dy * 5.0
    local wingLX, wingLY = mx - dx * 10.5 + px * 3.8, my - dy * 10.5 + py * 3.8
    local wingRX, wingRY = mx - dx * 10.5 - px * 3.8, my - dy * 10.5 - py * 3.8
    g.setColor(0.933, 0.984, 1.0, fade)
    g.polygon("fill", tipX, tipY, wingLX, wingLY, notchX, notchY)
    g.polygon("fill", tipX, tipY, notchX, notchY, wingRX, wingRY)
    g.setLineWidth(1.0)
    g.setColor(0.220, 0.863, 1.0, 0.95 * fade)
    g.polygon("line", tipX, tipY, wingLX, wingLY, notchX, notchY, wingRX, wingRY)
end

function Turret.projectileRenderers.twin_dart(g, missile, dx, dy, fade)
    -- VP1B: Electric Twin-Facet Dart (pure-white diamond core + electric-blue/cyan tapered wake)
    local px, py = -dy, dx
    local mx, my = missile.x, missile.y
    local trail = math.min(24, missile.distance or 0)
    g.setBlendMode("add")
    if trail > 0 then
        g.setColor(0.141, 0.549, 1.0, 0.34 * fade)
        g.polygon("fill",
            mx + dx * 6.5, my + dy * 6.5,
            mx + px * 3.8, my + py * 3.8,
            mx - dx * trail, my - dy * trail,
            mx - px * 3.8, my - py * 3.8)
        local innerTrail = trail * 0.72
        g.setColor(0.220, 0.863, 1.0, 0.78 * fade)
        g.polygon("fill",
            mx + dx * 6.5, my + dy * 6.5,
            mx + px * 2.1, my + py * 2.1,
            mx - dx * innerTrail, my - dy * innerTrail,
            mx - px * 2.1, my - py * 2.1)
        g.setLineWidth(1.5)
        g.setColor(0.220, 0.863, 1.0, 0.82 * fade)
        g.line(mx, my, mx - dx * trail, my - dy * trail)
    else
        g.setColor(0.141, 0.549, 1.0, 0.42 * fade)
        g.circle("fill", mx, my, 5.5)
    end
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, fade)
    g.polygon("fill",
        mx + dx * 6.8, my + dy * 6.8,
        mx + px * 2.3, my + py * 2.3,
        mx - dx * 4.5, my - dy * 4.5,
        mx - px * 2.3, my - py * 2.3)
    g.setLineWidth(1.2)
    g.line(mx - dx * 6, my - dy * 6, mx, my)
    g.setLineWidth(0.8)
    g.setColor(0.56, 0.96, 1.0, 0.85 * fade)
    g.polygon("line",
        mx + dx * 6.8, my + dy * 6.8,
        mx + px * 2.3, my + py * 2.3,
        mx - dx * 4.5, my - dy * 4.5,
        mx - px * 2.3, my - py * 2.3)
end

Turret.beamRenderers = {}

function Turret.beamRenderers.snap_beam(g, beam, x, y)
    -- VP3A: 3-Tier Snap-Taper Beam + Muzzle Ring + 4-Point Impact Starburst
    local alpha = math.max(0, 1 - beam.age / beamLifetime)
    local taper = 0.28 + 0.72 * (alpha ^ 0.75)
    g.setBlendMode("add")
    g.setColor(0.141, 0.549, 1.0, 0.30 * alpha)
    g.setLineWidth(14.0 * taper)
    g.line(beam.x, beam.y, x, y)
    g.setColor(0.220, 0.863, 1.0, 0.78 * alpha)
    g.setLineWidth(6.2 * taper)
    g.line(beam.x, beam.y, x, y)
    g.setColor(1.0, 1.0, 1.0, 0.98 * alpha)
    g.setLineWidth(2.4 * taper)
    g.line(beam.x, beam.y, x, y)

    -- Muzzle ring flash
    local muzzleR = 5.5 + (1 - alpha) * 9.0
    g.setLineWidth(math.max(0.7, 1.8 * alpha))
    g.setColor(0.220, 0.863, 1.0, 0.85 * alpha)
    g.circle("line", beam.x, beam.y, muzzleR)
    g.setColor(1.0, 1.0, 1.0, 0.92 * alpha)
    g.circle("fill", beam.x, beam.y, 3.5 * alpha)

    -- 4-point starburst impact flare when hitting an enemy
    if beam.hitX then
        local rLong = 24.0 * (0.40 + 0.60 * alpha)
        local rShort = math.max(0.8, 2.8 * alpha)
        local dLong = rLong * 0.7071
        local dShort = rShort * 0.7071
        local function drawStar(scale, r, green, b, a)
            local rl, rs = rLong * scale, rShort * scale
            local dl, ds = dLong * scale, dShort * scale
            g.setColor(r, green, b, a)
            -- 45-degree rotated crossed convex diamonds
            g.polygon("fill",
                x + dl, y + dl,
                x + ds, y - ds,
                x - dl, y - dl,
                x - ds, y + ds)
            g.polygon("fill",
                x + dl, y - dl,
                x + ds, y + ds,
                x - dl, y + dl,
                x - ds, y - ds)
        end
        drawStar(1.25, 0.220, 0.863, 1.0, 0.55 * alpha)
        drawStar(1.00, 0.93, 0.98, 1.0, 0.95 * alpha)
        g.setColor(1.0, 1.0, 1.0, alpha)
        g.circle("fill", x, y, 4.2 * alpha)
    end
    g.setBlendMode("alpha")
end

Turret.impactRenderers = {}

function Turret.impactRenderers.salvo_spark(g, explosion, radius, maxR, ease, alpha, glow, ring, core)
    local ringAlpha = alpha ^ 1.15
    local sparkAlpha = math.max(0, alpha ^ 1.35)
    g.setColor(glow[1], glow[2], glow[3], 0.16 * ringAlpha)
    g.circle("fill", explosion.x, explosion.y, radius * 0.92)
    g.setColor(ring[1], ring[2], ring[3], 0.92 * ringAlpha)
    g.setLineWidth(2.4 * ringAlpha + 0.5)
    g.circle("line", explosion.x, explosion.y, radius)
    g.setColor(core[1], core[2], core[3], 0.76 * ringAlpha)
    g.setLineWidth(1.4 * ringAlpha + 0.3)
    g.circle("line", explosion.x, explosion.y, radius * 0.62)

    local rLong = maxR * (0.45 + 0.70 * ease) * (0.35 + 0.65 * sparkAlpha)
    local rShort = math.max(0.7, maxR * 0.10 * sparkAlpha)
    local rLongOuter, rShortOuter = rLong * 1.22, rShort * 1.22
    g.push()
    g.translate(explosion.x, explosion.y)
    g.rotate(explosion.sparkAngle or 0)
    g.setColor(ring[1], ring[2], ring[3], 0.50 * sparkAlpha)
    g.polygon("fill", -rLongOuter, 0, 0, -rShortOuter, rLongOuter, 0, 0, rShortOuter)
    g.polygon("fill", 0, -rLongOuter, rShortOuter, 0, 0, rLongOuter, -rShortOuter, 0)
    g.setColor(core[1], core[2], core[3], 0.96 * sparkAlpha)
    g.polygon("fill", -rLong, 0, 0, -rShort, rLong, 0, 0, rShort)
    g.polygon("fill", 0, -rLong, rShort, 0, 0, rLong, -rShort, 0)
    g.setColor(1, 1, 1, 0.98 * sparkAlpha)
    g.circle("fill", 0, 0, math.max(1.5, maxR * 0.22 * sparkAlpha))
    g.pop()
end

function Turret.impactRenderers.scatter_ring(g, explosion, radius, maxR, ease, alpha, glow, ring, core)
    g.setColor(glow[1], glow[2], glow[3], alpha * 0.20)
    g.circle("fill", explosion.x, explosion.y, radius * 0.85)
    g.setColor(ring[1], ring[2], ring[3], alpha * 0.90)
    g.setLineWidth(2.0 * alpha + 0.5)
    g.circle("line", explosion.x, explosion.y, radius)
    g.setColor(core[1], core[2], core[3], alpha * 0.58)
    g.setLineWidth(1.0 * alpha + 0.3)
    g.circle("line", explosion.x, explosion.y, radius * 0.58)
    g.setColor(core[1], core[2], core[3], alpha * 0.92)
    g.circle("fill", explosion.x, explosion.y, 6.5 * alpha)
end

Turret.impactRenderers.beam_impact = Turret.impactRenderers.scatter_ring

function Turret:drawEffects(camera, width, height)
    local g = love.graphics
    g.push("all")
    if self.salvoEmbers and #self.salvoEmbers > 0 then
        g.setBlendMode("add")
        for _, e in ipairs(self.salvoEmbers) do
            local p = math.max(0, math.min(1, e.age / e.lifetime))
            local a = (1 - p) ^ 1.5
            local r = e.size * (1 - 0.35 * p)
            g.setColor(e.r, e.g, e.b, 0.32 * a)
            g.circle("fill", e.x, e.y, r * 2.1)
            g.setColor(e.r, e.g, e.b, 0.95 * a)
            g.circle("fill", e.x, e.y, r)
        end
        g.setBlendMode("alpha")
    end
    for _, missile in ipairs(self.missiles) do
        local fade = 1
        if missile.fading and missile.fadeEndAge then
            local span = math.max(1e-4, missile.fadeEndAge - (missile.fadeStartAge or 0))
            fade = math.max(0, math.min(1, (missile.fadeEndAge - missile.age) / span))
        end
        local speed = missile.speed > 0 and missile.speed or 1
        local dx, dy = missile.vx / speed, missile.vy / speed
        local style = missile.style or (missile.targetScreenX and "salvo_lance" or "twin_dart")
        local renderer = Turret.projectileRenderers[style] or Turret.projectileRenderers.twin_dart
        renderer(g, missile, dx, dy, fade)
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
            local renderer = Turret.beamRenderers[beam.style or "snap_beam"] or Turret.beamRenderers.snap_beam
            renderer(g, beam, x, y)
        end
    end
    for _, explosion in ipairs(self.explosions) do
        local progress = math.max(0, math.min(1, explosion.age / explosion.lifetime))
        local ease = 1 - (1 - progress) * (1 - progress)
        local maxR = explosion.radius or 41
        local radius = 6 + ease * (maxR - 6)
        local alpha = 1 - progress
        local colors = explosion.colors or explosionColors
        local glow, ring, core = colors.glow, colors.ring, colors.core
        local style = explosion.style or (explosion.isSalvo and "salvo_spark" or "scatter_ring")
        local renderer = Turret.impactRenderers[style] or Turret.impactRenderers.scatter_ring
        g.setBlendMode("add")
        renderer(g, explosion, radius, maxR, ease, alpha, glow, ring, core)
        g.setBlendMode("alpha")
    end
    g.pop()
end

local function blendWhite(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function addQuad(verts, v1, v2, v3, v4)
    verts[#verts + 1] = v1
    verts[#verts + 1] = v2
    verts[#verts + 1] = v3
    verts[#verts + 1] = v1
    verts[#verts + 1] = v3
    verts[#verts + 1] = v4
end

local function buildFeatheredAimMesh(coreHalfFrac, taper, fadePower, segments)
    if not (love and love.graphics and love.graphics.newMesh) then return nil end
    local verts = {}
    for i = 0, segments - 1 do
        local t0 = i / segments
        local t1 = (i + 1) / segments
        local y0, y1 = -t0, -t1
        local w0 = 1 - taper * t0
        local w1 = 1 - taper * t1
        local a0 = (1 - t0) ^ fadePower
        local a1 = (1 - t1) ^ fadePower

        if coreHalfFrac <= 0 then
            local l0 = { -w0, y0, 0, t0, 1, 1, 1, 0 }
            local c0 = { 0, y0, 0.5, t0, 1, 1, 1, a0 }
            local r0 = { w0, y0, 1, t0, 1, 1, 1, 0 }
            local l1 = { -w1, y1, 0, t1, 1, 1, 1, 0 }
            local c1 = { 0, y1, 0.5, t1, 1, 1, 1, a1 }
            local r1 = { w1, y1, 1, t1, 1, 1, 1, 0 }
            addQuad(verts, l0, c0, c1, l1)
            addQuad(verts, c0, r0, r1, c1)
        else
            local cw0, cw1 = w0 * coreHalfFrac, w1 * coreHalfFrac
            local ol0 = { -w0, y0, 0, t0, 1, 1, 1, 0 }
            local il0 = { -cw0, y0, 0.35, t0, 1, 1, 1, a0 }
            local ir0 = { cw0, y0, 0.65, t0, 1, 1, 1, a0 }
            local or0 = { w0, y0, 1, t0, 1, 1, 1, 0 }
            local ol1 = { -w1, y1, 0, t1, 1, 1, 1, 0 }
            local il1 = { -cw1, y1, 0.35, t1, 1, 1, 1, a1 }
            local ir1 = { cw1, y1, 0.65, t1, 1, 1, 1, a1 }
            local or1 = { w1, y1, 1, t1, 1, 1, 1, 0 }
            addQuad(verts, ol0, il0, il1, ol1)
            addQuad(verts, il0, ir0, ir1, il1)
            addQuad(verts, ir0, or0, or1, ir1)
        end
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function getAimMeshes()
    if not aimMeshesTried then
        aimMeshesTried = true
        aimGlowMesh = buildFeatheredAimMesh(0, 0.35, 1.45, 16)
        aimCoreMesh = buildFeatheredAimMesh(0.45, 0.45, 1.35, 16)
    end
    return aimGlowMesh, aimCoreMesh
end

function Turret:aimLineLength(screenWidth)
    local refWidth = screenWidth or Arena.width or 1280
    return refWidth * (self.aimLineWidthRatio or Turret.aimLineWidthRatio)
end

function Turret:drawMount(ship, time, screenWidth)
    local g = love.graphics
    local alpha, flash = 1, 0
    if ship and ship.invulnBlinkAlpha then
        alpha, flash = ship:invulnBlinkAlpha()
    end
    local pulse = 0.90 + math.sin((time or 0) * 6.5) * 0.10
    local aimLength = self:aimLineLength(screenWidth)
    local glowMesh, coreMesh = getAimMeshes()

    g.push("all")
    g.translate(ship.x, ship.y)
    g.rotate(self.angle)

    local outerR, outerG, outerB = blendWhite(0.18, 0.78, 1.0, flash * 0.6)
    local innerR, innerG, innerB = blendWhite(0.45, 0.92, 1.0, flash * 0.7)
    local coreR, coreG, coreB = blendWhite(0.78, 0.97, 1.0, flash * 0.85)

    if glowMesh and coreMesh then
        -- Soft layered additive glow ribbons fading smoothly to transparent toward the end.
        g.setBlendMode("add")
        g.setColor(outerR, outerG, outerB, 0.20 * pulse * alpha)
        g.draw(glowMesh, 0, 0, 0, 7.5, aimLength)

        g.setColor(innerR, innerG, innerB, 0.30 * pulse * alpha)
        g.draw(glowMesh, 0, 0, 0, 3.0, aimLength)

        -- Semi-transparent core aiming line extending from the ship center.
        g.setBlendMode("alpha")
        g.setColor(coreR, coreG, coreB, 0.50 * alpha)
        g.draw(coreMesh, 0, 0, 0, 1.35, aimLength)
    else
        local segments = 16
        for i = 0, segments - 1 do
            local t0 = i / segments
            local t1 = (i + 1) / segments
            local fade = (1 - (t0 + t1) * 0.5) ^ 1.4
            local y0, y1 = -aimLength * t0, -aimLength * t1
            g.setLineWidth(6.5)
            g.setColor(outerR, outerG, outerB, 0.14 * fade * pulse * alpha)
            g.line(0, y0, 0, y1)
            g.setLineWidth(3.0)
            g.setColor(innerR, innerG, innerB, 0.24 * fade * pulse * alpha)
            g.line(0, y0, 0, y1)
            g.setLineWidth(1.4)
            g.setColor(coreR, coreG, coreB, 0.50 * fade * alpha)
            g.line(0, y0, 0, y1)
        end
    end

    g.pop()
end

return Turret
