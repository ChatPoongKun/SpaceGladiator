local Arena = require("src.core.arena")
local Ship = require("src.combat.ship")
local Collision = require("src.core.collision")
local EnemyFire = require("src.combat.enemy_fire")
local Sfx = require("src.audio.sfx")
local Enemies = {}
Enemies.__index = Enemies
local tau = 2 * math.pi
local exitMargin = 155
local collisionIterations = 4
local enemyPushBase = 80
local playerPushBase = 110
local collisionRestitution = 0.30
local enemyMaxPushSpeed = 240
local playerMaxPushSpeed = 260

Enemies.spawnRate = 1 / 4
Enemies.maxCount = 15
Enemies.patrolDuration = math.huge
Enemies.flybyPatrolDuration = 10
Enemies.warpDuration = 0.90
Enemies.edgeWarningDuration = 0.60
Enemies.flybyEntrySpeed = 280
Enemies.collisionMinSpeed = 60
Enemies.collisionRefSpeed = 300
Enemies.collisionSpeedExponent = 1.25
Enemies.collisionMaxSpeedFactor = 2.6
Enemies.collisionMomentumBaseSpeed = 120
Enemies.collisionRefMass = 100 / 60
Enemies.collisionEnemyDamageScale = 14
Enemies.collisionPlayerDamageScale = 18
Enemies.collisionCooldown = 0.30
Enemies.collisionRamKillKnockMult = 0.40
Enemies.wedgeTelegraphDuration = 0.45
Enemies.wedgeDiveDuration = 0.72
Enemies.wedgeRecoverDuration = 0.75
Enemies.laserTrackDuration = 0.65
Enemies.laserLockDuration = 0.25
Enemies.laserRecoilDuration = 0.30
Enemies.laserRecoilSpeed = 95
Enemies.obtuseCurtainTelegraph = 0.38
Enemies.spinnerSpiralTelegraph = 0.45
Enemies.spinnerRingTelegraph = 0.50
Enemies.maxConcurrentLasers = 2
Enemies.maxConcurrentDives = 2
Enemies.obtuseAttackGap = 1.2
Enemies.spinnerAttackGap = 1.1
Enemies.wrapGraceDuration = 0.35
Enemies.types = {
    {
        name = "WEDGE", vertices = {0, -15, 10, 10, 0, 5, -10, 10},
        radius = 16, mass = 1.0, evadeSpeed = 94, turnSpeed = 3.0,
        thrust = 285, brake = 5.0, maxSpeed = 500,
        patrolMin = 55, patrolMax = 110, arrivalRadius = 32,
        combatPower = 40, maxHp = 10,
    },
    {
        name = "EQUILATERAL", vertices = {0, -24, -12 * math.sqrt(3), 12, 12 * math.sqrt(3), 12},
        radius = 24, mass = 1.8, evadeSpeed = 78,
        turnSpeed = 3.5, thrust = 255, brake = 2.5, maxSpeed = 320,
        patrolMin = 120, patrolMax = 185, arrivalRadius = 40,
        combatPower = 70, maxHp = 20,
    },
    {
        name = "OBTUSE", vertices = {0, -12, -26, 10, 26, 10},
        radius = 28, mass = 3.0, evadeSpeed = 62, turnSpeed = 2.5, thrust = 218, brake = 4.0, maxSpeed = 200,
        patrolMin = 195, patrolMax = 290, arrivalRadius = 48,
        combatPower = 100, maxHp = 50,
    },
    {
        name = "SPINNER", vertices = {0, -22, 16, -6, 22, 0, 16, 6, 0, 22, -16, 6, -22, 0, -16, -6},
        radius = 22, mass = 2.0, evadeSpeed = 0, turnSpeed = 2.8, thrust = 180, brake = 3.0, maxSpeed = 160,
        patrolMin = 170, patrolMax = 280, arrivalRadius = 40,
        combatPower = 85, maxHp = 35,
    },
}

local escortSpread, escortTrail = 82, 34
local wingSpread, wingTrail = 114, 62
local entryMargin, entrySpeed = 44, 120
local entryAngles = {math.pi / 2, math.pi * 1.5, math.pi, 0}
local departureAngles = {math.pi * 1.5, math.pi / 2, 0, math.pi}
local formation = {
    { kind = 2, slot = -1, right = -escortSpread, forward = -escortTrail },
    { kind = 2, slot = 1, right = escortSpread, forward = -escortTrail },
    { kind = 1, slot = -1, right = -wingSpread, forward = -wingTrail },
    { kind = 1, slot = 1, right = wingSpread, forward = -wingTrail },
}
local squadSize = #formation + 1

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function limitVector(x, y, maxLen)
    local len = math.sqrt(x * x + y * y)
    if len > maxLen and len > 0 then
        return x * maxLen / len, y * maxLen / len
    end
    return x, y
end

function Enemies.new(rng, gladiator)
    return setmetatable({
        items = {}, kills = 0, killsByKind = {},
        spawnAccumulator = 0.5, rng = rng or math.random,
        view = {left = 0, top = 0, right = Arena.width, bottom = Arena.height},
        fire = EnemyFire.new(),
        gladiator = gladiator,
        playerCombatPower = Ship.combatPower,
        deathParticles = {},
        deathBursts = {},
        waveIndex = 0,
        stageNumber = 1,
        director = {
            obtuseCooldown = 0,
            spinnerCooldown = 0,
            wrapGrace = 0,
            lastWrapEvents = nil,
        },
    }, Enemies)
end

function Enemies.isIntangible(enemy)
    return enemy ~= nil and (enemy.phase == "warping" or enemy.phase == "edge_warning")
end

function Enemies:countActiveLasers()
    local n = 0
    for _, enemy in ipairs(self.items) do
        if enemy.kind == 2 and not enemy.dead and enemy.ai
            and (enemy.ai.state == "track" or enemy.ai.state == "lock") then
            n = n + 1
        end
    end
    return n
end

function Enemies:countActiveDives()
    local n = 0
    for _, enemy in ipairs(self.items) do
        if enemy.kind == 1 and not enemy.dead and enemy.ai
            and (enemy.ai.state == "telegraph" or enemy.ai.state == "dive") then
            n = n + 1
        end
    end
    return n
end

function Enemies:canStartAttack(enemy)
    local d = self.director
    if d and (d.wrapGrace or 0) > 0 then
        return false
    end
    if not enemy then return true end
    if enemy.kind == 1 then
        return self:countActiveDives() < self.maxConcurrentDives
    elseif enemy.kind == 2 then
        return self:countActiveLasers() < self.maxConcurrentLasers
    elseif enemy.kind == 3 then
        return not d or (d.obtuseCooldown or 0) <= 0
    elseif enemy.kind == 4 then
        return not d or (d.spinnerCooldown or 0) <= 0
    end
    return true
end

function Enemies:notifyAttackStarted(enemy)
    local d = self.director
    if not d or not enemy then return end
    if enemy.kind == 3 then
        d.obtuseCooldown = math.max(d.obtuseCooldown or 0, self.obtuseAttackGap)
    elseif enemy.kind == 4 then
        d.spinnerCooldown = math.max(d.spinnerCooldown or 0, self.spinnerAttackGap)
    end
end

local function formationPosition(x, y, angle, right, forward)
    local fx, fy = math.sin(angle), -math.cos(angle)
    return x - fy * right + fx * forward, y + fx * right + fy * forward
end

local function spawnPoint(rng, ship)
    local edge = math.min(4, 1 + math.floor(rng() * 4))
    local t = 0.24 + rng() * 0.52
    local x, y = t * Arena.width, t * Arena.height
    if edge == 1 then x = 124
    elseif edge == 2 then x = Arena.width - 124
    elseif edge == 3 then y = 98
    else y = Arena.height - 98 end
    if (x - ship.x) ^ 2 + (y - ship.y) ^ 2 < 260 ^ 2 then
        x = ship.x < Arena.width / 2 and Arena.width - 124 or 124
    end
    return x, y, edge
end

function Enemies:spawn(ship, kindIndex, options)
    if #self.items >= self.maxCount then return nil end
    local kind = kindIndex or math.min(#self.types, 1 + math.floor(self.rng() * #self.types))
    local definition = self.types[kind]
    local enemy = Ship.new(Arena.width, Arena.height)
    if options and options.x and options.y then
        enemy.x, enemy.y = options.x, options.y
    else
        enemy.x, enemy.y = spawnPoint(self.rng, ship)
    end
    enemy.kind, enemy.radius = kind, definition.radius
    enemy.mass = definition.mass or 1.0
    enemy.combatPower = definition.combatPower
    enemy.maxHp = (options and options.maxHp) or definition.maxHp or 10
    enemy.hp = (options and options.hp) or enemy.maxHp
    enemy.hitFlash = 0
    enemy.maxSpeed, enemy.thrust, enemy.turnSpeed = definition.maxSpeed, definition.thrust, definition.turnSpeed
    enemy.brake = definition.brake
    -- Give lighter thrust the same time to build momentum out of low-speed drag.
    local thrustRatio = enemy.thrust / Ship.thrust
    enemy.driftThreshold = Ship.driftThreshold * thrustRatio
    enemy.driftDeceleration = Ship.driftDeceleration * thrustRatio
    enemy.vx, enemy.vy = limitVector(options and options.vx or 0, options and options.vy or 0, enemy.maxSpeed)
    enemy.pushVx, enemy.pushVy = 0, 0
    enemy.prevX, enemy.prevY = enemy.x, enemy.y
    enemy.angle = (options and options.angle or math.atan2(ship.x - enemy.x, enemy.y - ship.y)) % tau
    enemy.wave = options and options.wave or {}
    enemy.slot = options and options.slot or (self.rng() < 0.5 and -1 or 1)
    enemy.evadeTime, enemy.evadeCooldown = 0, 0
    enemy.sepX, enemy.sepY = 0, 0
    enemy.aimed = false
    enemy.diving = false
    enemy.telegraph = nil
    enemy.ai = nil
    enemy.aiDelay = options and options.aiDelay or 0
    enemy.collisionCooldown = 0
    enemy.patrolDuration = options and options.patrolDuration or nil
    enemy.entrySpeed = options and options.entrySpeed or entrySpeed
    local warpTime = options and options.warpTime
    local edgeWarningTime = options and options.edgeWarningTime
    local entryTime = options and options.entryTime
    if warpTime and warpTime > 0 then
        enemy.phase = "warping"
        enemy.phaseRemaining = warpTime
        enemy.warpDuration = warpTime
        enemy.vx, enemy.vy = 0, 0
    elseif edgeWarningTime and edgeWarningTime > 0 then
        enemy.phase = "edge_warning"
        enemy.phaseRemaining = edgeWarningTime
        enemy.edgeWarningDuration = edgeWarningTime
        enemy.entryDuration = entryTime or 0.75
        enemy.entryEdge = options and options.edge
        enemy.vx, enemy.vy = 0, 0
    elseif entryTime then
        enemy.phase = "entering"
        enemy.phaseRemaining = entryTime
    else
        enemy.phase = "patrol"
        enemy.phaseRemaining = enemy.patrolDuration or self.patrolDuration
    end

    self.items[#self.items + 1] = enemy
    return enemy
end

local function safeWarpPoint(group, ship, anchorX, anchorY, occupied)
    local margin = 95
    local minX, maxX = margin, Arena.width - margin
    local minY, maxY = margin, Arena.height - margin
    local function isClear(px, py)
        if (px - ship.x) ^ 2 + (py - ship.y) ^ 2 < 280 ^ 2 then return false end
        for _, pt in ipairs(occupied or {}) do
            if (px - pt.x) ^ 2 + (py - pt.y) ^ 2 < 90 ^ 2 then return false end
        end
        return true
    end
    if anchorX and anchorY then
        local cx, cy = clamp(anchorX, minX, maxX), clamp(anchorY, minY, maxY)
        if isClear(cx, cy) then return cx, cy end
    end
    local baseAngle = math.atan2(Arena.height * 0.5 - ship.y, Arena.width * 0.5 - ship.x) + (group.rng() - 0.5) * 0.7
    local bestX, bestY, bestScore = clamp(Arena.width - ship.x, minX, maxX), clamp(Arena.height - ship.y, minY, maxY), -1
    for attempt = 0, 11 do
        local a = baseAngle + attempt * tau / 12
        local dist = 310 + (attempt % 3) * 35
        local px = clamp(ship.x + math.cos(a) * dist, minX, maxX)
        local py = clamp(ship.y + math.sin(a) * dist, minY, maxY)
        if isClear(px, py) then return px, py end
        local minD = (px - ship.x) ^ 2 + (py - ship.y) ^ 2
        for _, pt in ipairs(occupied or {}) do
            minD = math.min(minD, (px - pt.x) ^ 2 + (py - pt.y) ^ 2)
        end
        if minD > bestScore then
            bestX, bestY, bestScore = px, py, minD
        end
    end
    return bestX, bestY
end

local function edgeStagingPose(group, edge, tAlong, speed, extraDist)
    local view = group.view
    local margin = entryMargin + (extraDist or 0)
    local t = clamp(tAlong, 0.14, 0.86)
    local x, y
    if edge == 1 then
        x, y = view.left - margin, view.top + t * (view.bottom - view.top)
    elseif edge == 2 then
        x, y = view.right + margin, view.top + t * (view.bottom - view.top)
    elseif edge == 3 then
        x, y = view.left + t * (view.right - view.left), view.top - margin
    else
        x, y = view.left + t * (view.right - view.left), view.bottom + margin
    end
    local angle = entryAngles[edge]
    local entryTime = (margin + 56) / speed
    return x, y, angle, entryTime
end

Enemies.waveThemes = {
    bulwark_escort = true,
    interceptor_pack = true,
    crossfire_line = true,
    spiral_siege = true,
    pincer_assault = true,
    classic = true,
}

local stage1Deck = { "bulwark_escort", "interceptor_pack", "crossfire_line" }
local stage2Deck = { "bulwark_escort", "spiral_siege", "crossfire_line", "interceptor_pack", "pincer_assault" }

local function spawnClassicSquad(self, ship)
    local lx, ly, edge = spawnPoint(self.rng, ship)
    local view = self.view
    if edge == 1 then lx = view.left - entryMargin
    elseif edge == 2 then lx = view.right + entryMargin
    elseif edge == 3 then ly = view.top - entryMargin
    else ly = view.bottom + entryMargin end
    local angle = entryAngles[edge]
    local fx, fy = math.sin(angle), -math.cos(angle)
    local vx, vy = fx * entrySpeed, fy * entrySpeed
    local entryTime = (entryMargin + wingTrail + self.types[3].radius) / entrySpeed
    local wave = { entryAngle = angle, theme = "classic" }
    local leader = self:spawn(ship, 3, {
        x = lx, y = ly, vx = vx, vy = vy, angle = angle, entryTime = entryTime, wave = wave,
    })
    wave.leader = leader
    local squad = { leader }
    for _, member in ipairs(formation) do
        local x, y = formationPosition(lx, ly, angle, member.right, member.forward)
        local aiDelay = member.slot == 1 and (member.kind == 1 and 0.55 or 0.35) or 0
        squad[#squad + 1] = self:spawn(ship, member.kind, {
            x = x, y = y, vx = vx, vy = vy, angle = angle, entryTime = entryTime, wave = wave,
            slot = member.slot, aiDelay = aiDelay,
        })
    end
    return squad
end

function Enemies:spawnSquad(ship, themeName)
    if #self.items + squadSize > self.maxCount then return {} end
    self.waveIndex = (self.waveIndex or 0) + 1
    if themeName == "classic" then
        return spawnClassicSquad(self, ship)
    end
    local deck = (self.stageNumber or 1) >= 2 and stage2Deck or stage1Deck
    local theme = themeName
    if not theme or not Enemies.waveThemes[theme] then
        theme = deck[((self.waveIndex - 1) % #deck) + 1]
    end

    local wave = { theme = theme }
    local squad = {}
    local occupied = {}
    local _, _, primaryEdge = spawnPoint(self.rng, ship)
    local oppEdge = primaryEdge == 1 and 2 or (primaryEdge == 2 and 1 or (primaryEdge == 3 and 4 or 3))

    local function addWarp(kind, ax, ay, slot, aiDelay)
        local wx, wy = safeWarpPoint(self, ship, ax, ay, occupied)
        occupied[#occupied + 1] = { x = wx, y = wy }
        local e = self:spawn(ship, kind, {
            x = wx, y = wy, warpTime = Enemies.warpDuration, wave = wave, slot = slot, aiDelay = aiDelay,
        })
        squad[#squad + 1] = e
        return e
    end

    local function addEdge(kind, edge, tAlong, speed, extraDist, slot, aiDelay)
        local ex, ey, angle, entryTime = edgeStagingPose(self, edge, tAlong, speed, extraDist)
        local e = self:spawn(ship, kind, {
            x = ex, y = ey, angle = angle, entrySpeed = speed, entryTime = entryTime,
            edgeWarningTime = Enemies.edgeWarningDuration, edge = edge,
            wave = wave, slot = slot, aiDelay = aiDelay,
        })
        squad[#squad + 1] = e
        return e
    end

    if theme == "interceptor_pack" then
        local baseT = 0.28 + self.rng() * 0.44
        local offsets = {
            { dt = 0, extra = 0, slot = 1, delay = 0 },
            { dt = -0.14, extra = 34, slot = -1, delay = 0.25 },
            { dt = 0.14, extra = 34, slot = 1, delay = 0.45 },
            { dt = -0.24, extra = 68, slot = -1, delay = 0.65 },
            { dt = 0.24, extra = 68, slot = 1, delay = 0.85 },
        }
        for _, spec in ipairs(offsets) do
            addEdge(1, primaryEdge, baseT + spec.dt, Enemies.flybyEntrySpeed, spec.extra, spec.slot, spec.delay)
        end
    elseif theme == "crossfire_line" then
        addWarp(2, Arena.width * 0.24, Arena.height * 0.26, -1, 0)
        addWarp(2, Arena.width * 0.76, Arena.height * 0.28, 1, 0.35)
        addWarp(2, Arena.width * 0.50, Arena.height * 0.76, -1, 0.65)
        addEdge(1, primaryEdge, 0.32, 260, 0, -1, 0.15)
        addEdge(1, oppEdge, 0.68, 260, 0, 1, 0.50)
    elseif theme == "spiral_siege" then
        addWarp(4, Arena.width * 0.26, Arena.height * 0.30, -1, 0)
        addWarp(4, Arena.width * 0.74, Arena.height * 0.70, 1, 0.45)
        addWarp(2, Arena.width * 0.50, Arena.height * 0.26, 1, 0.35)
        addEdge(1, primaryEdge, 0.35, 260, 0, -1, 0.15)
        addEdge(1, oppEdge, 0.65, 260, 0, 1, 0.55)
    elseif theme == "pincer_assault" then
        addWarp(3, Arena.width * 0.25, Arena.height * 0.50, -1, 0)
        addWarp(4, Arena.width * 0.75, Arena.height * 0.30, 1, 0.35)
        addWarp(2, Arena.width * 0.72, Arena.height * 0.72, -1, 0.60)
        addEdge(1, 3, 0.38, 260, 0, -1, 0.20)
        addEdge(1, 4, 0.62, 260, 0, 1, 0.55)
    else
        -- bulwark_escort
        addWarp(3, Arena.width * 0.50, Arena.height * 0.44, 1, 0)
        addWarp(2, Arena.width * 0.28, Arena.height * 0.34, -1, 0.30)
        addEdge(1, primaryEdge, 0.28, 260, 0, -1, 0.10)
        addEdge(1, primaryEdge, 0.50, 260, 28, 1, 0.40)
        addEdge(1, primaryEdge, 0.72, 260, 56, -1, 0.70)
    end

    wave.leader = squad[1]
    wave.entryAngle = squad[1] and squad[1].angle or entryAngles[primaryEdge]
    return squad
end

local function aimEvasion(enemy, ship, aimAngle, step)
    enemy.evadeTime = math.max(0, enemy.evadeTime - step)
    enemy.evadeCooldown = math.max(0, enemy.evadeCooldown - step)
    if aimAngle then
        local aimX, aimY = math.sin(aimAngle), -math.cos(aimAngle)
        local dx, dy = enemy.x - ship.x, enemy.y - ship.y
        local along = dx * aimX + dy * aimY
        local across = dy * aimX - dx * aimY
        if enemy.evadeCooldown == 0 and along > 0 and along < 700 and math.abs(across) < 48 + enemy.radius then
            local side = math.abs(across) < 4 and enemy.slot or (across >= 0 and 1 or -1)
            enemy.evadeX, enemy.evadeY = -aimY * side, aimX * side
            enemy.evadeTime, enemy.evadeCooldown = 0.45, 1.8
        end
    end
    enemy.aimed = enemy.evadeTime > 0
    if enemy.aimed then return enemy.evadeX, enemy.evadeY end
    return 0, 0
end

local function turnError(enemy, angle)
    return (angle - enemy.angle + math.pi) % tau - math.pi
end

local function pilot(enemy, dt, targetVx, targetVy, angle, brakeOverride)
    local targetSpeed = math.sqrt(targetVx * targetVx + targetVy * targetVy)
    local speed = enemy:speed()
    local brake = brakeOverride
    if brake == nil then brake = speed > targetSpeed + 6 end
    local thrust = false
    if targetSpeed > 9 then
        local forwardSpeed = (enemy.vx * targetVx + enemy.vy * targetVy) / targetSpeed
        if brakeOverride == nil and speed > 18 and forwardSpeed < speed * 0.35 then brake = true end
        if brake then
            angle = math.atan2(targetVx, -targetVy)
        else
            -- Point into the turn to correct sideways drift with forward thrust.
            angle = math.atan2(targetVx - enemy.vx * 0.65, enemy.vy * 0.65 - targetVy)
            thrust = forwardSpeed < targetSpeed - 4
        end
    end

    local error = turnError(enemy, angle)
    enemy:turn(dt, clamp(error / (enemy.turnSpeed * dt), -1, 1))
    local oldVx, oldVy = enemy:updateVelocity(dt, thrust and math.abs(error) < 0.6, brake, enemy.maxSpeed)
    enemy.x = enemy.x + (oldVx + enemy.vx) * 0.5 * dt
    enemy.y = enemy.y + (oldVy + enemy.vy) * 0.5 * dt
end

local function flyTo(enemy, dt, x, y, speed, steerX, steerY, brakeOverride)
    local dx, dy = x - enemy.x, y - enemy.y
    local response = brakeOverride ~= nil and speed / math.max(math.sqrt(dx * dx + dy * dy), 1) or 2.6
    local vx, vy = limitVector(dx * response, dy * response, speed)
    vx, vy = limitVector(vx + steerX, vy + steerY, speed)
    pilot(enemy, dt, vx, vy, math.atan2(dx, -dy), brakeOverride)
end

local function patrolBounds(group, enemy)
    local view = group.view
    local margin = enemy.radius + 2
    return math.max(0, view.left) + margin, math.min(Arena.width, view.right) - margin,
        math.max(0, view.top) + margin, math.min(Arena.height, view.bottom) - margin
end

local addEntityPush

local function clampToBounds(group, enemy, x, y)
    local left, right, top, bottom = patrolBounds(group, enemy)
    if left > right then left, right = right, left end
    if top > bottom then top, bottom = bottom, top end
    return clamp(x, left, right), clamp(y, top, bottom)
end

local function isInsideBounds(group, enemy)
    local left, right, top, bottom = patrolBounds(group, enemy)
    return enemy.x >= left and enemy.x <= right and enemy.y >= top and enemy.y <= bottom
end

local function angleToShip(enemy, ship)
    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    if dx * dx + dy * dy < 1e-12 then return enemy.angle end
    return math.atan2(dx, -dy) % tau
end



local function patrolWedge(group, enemy, dt, ship, aimAngle, definition)
    local evadeX, evadeY = aimEvasion(enemy, ship, aimAngle, dt)
    local ai = enemy.ai
    if not ai then
        ai = {
            state = "orbit",
            timer = 0.7 + group.rng() * 0.75 + (enemy.aiDelay or 0),
            orbitRadius = 210 + group.rng() * 55,
            side = enemy.slot or 1,
        }
        enemy.ai = ai
    end

    local steerX = enemy.sepX + evadeX * definition.evadeSpeed
    local steerY = enemy.sepY + evadeY * definition.evadeSpeed

    if ai.state == "orbit" then
        enemy.diving = false
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local dx, dy = enemy.x - ship.x, enemy.y - ship.y
        local distSq = dx * dx + dy * dy
        local baseBearing = distSq > 1e-4 and math.atan2(dy, dx) or (enemy.angle - math.pi / 2)
        local orbitAngle = baseBearing + ai.side * math.rad(42)
        local tx, ty = clampToBounds(group, enemy,
            ship.x + math.cos(orbitAngle) * ai.orbitRadius,
            ship.y + math.sin(orbitAngle) * ai.orbitRadius)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.64, steerX, steerY, false)
        if ai.timer <= 0 and isInsideBounds(group, enemy) and distSq <= 540 * 540 and group:canStartAttack(enemy) then
            ai.state = "telegraph"
            ai.timer = Enemies.wedgeTelegraphDuration
            local len = math.sqrt(distSq)
            if len > 1e-4 then
                ai.diveDirX, ai.diveDirY = -dx / len, -dy / len
            else
                ai.diveDirX, ai.diveDirY = math.sin(enemy.angle), -math.cos(enemy.angle)
            end
            enemy.telegraph = { kind = "dive", progress = 0, dirX = ai.diveDirX, dirY = ai.diveDirY }
        end
    elseif ai.state == "telegraph" then
        enemy.diving = false
        ai.timer = ai.timer - dt
        local svx = (ship.vx or 0) + (ship.wrapVx or 0)
        local svy = (ship.vy or 0) + (ship.wrapVy or 0)
        local dx, dy = (ship.x + svx * 0.22) - enemy.x, (ship.y + svy * 0.22) - enemy.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1e-4 then
            ai.diveDirX, ai.diveDirY = dx / len, dy / len
        else
            ai.diveDirX, ai.diveDirY = math.sin(enemy.angle), -math.cos(enemy.angle)
        end
        local progress = clamp(1 - ai.timer / Enemies.wedgeTelegraphDuration, 0, 1)
        enemy.telegraph = { kind = "dive", progress = progress, dirX = ai.diveDirX, dirY = ai.diveDirY }
        if ai.timer <= 0 then
            ai.state = "dive"
            ai.timer = Enemies.wedgeDiveDuration
            ai.fired = false
            enemy.telegraph = nil
            enemy.diving = true
            flyTo(enemy, dt, enemy.x + ai.diveDirX * 400, enemy.y + ai.diveDirY * 400,
                enemy.maxSpeed * 0.96, enemy.sepX, enemy.sepY, false)
        else
            flyTo(enemy, dt, enemy.x + ai.diveDirX * 260, enemy.y + ai.diveDirY * 260,
                enemy.maxSpeed * 0.44, steerX, steerY, false)
        end
    elseif ai.state == "dive" then
        enemy.diving = true
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local dirX, dirY = ai.diveDirX, ai.diveDirY
        flyTo(enemy, dt, enemy.x + dirX * 400, enemy.y + dirY * 400,
            enemy.maxSpeed * 0.96, enemy.sepX, enemy.sepY, false)
        local along = (ship.x - enemy.x) * dirX + (ship.y - enemy.y) * dirY
        if not ai.fired and (along <= 35 or ai.timer <= Enemies.wedgeDiveDuration * 0.5) then
            group.fire:shoot(enemy, ship)
            ai.fired = true
        end
        local left, right, top, bottom = patrolBounds(group, enemy)
        local outFar = enemy.x < left - 30 or enemy.x > right + 30 or enemy.y < top - 30 or enemy.y > bottom + 30
        if ai.timer <= 0 or (ai.fired and outFar) then
            ai.state = "recover"
            ai.timer = Enemies.wedgeRecoverDuration
            enemy.diving = false
        end
    else
        enemy.diving = false
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local dx, dy = enemy.x - ship.x, enemy.y - ship.y
        local baseBearing = (dx * dx + dy * dy > 1e-4) and math.atan2(dy, dx) or (enemy.angle - math.pi / 2)
        local recoverAngle = baseBearing + ai.side * math.rad(55)
        local tx, ty = clampToBounds(group, enemy,
            ship.x + math.cos(recoverAngle) * ai.orbitRadius,
            ship.y + math.sin(recoverAngle) * ai.orbitRadius)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.68, steerX, steerY, false)
        if ai.timer <= 0 then
            if group.rng() < 0.4 then ai.side = -ai.side end
            ai.state = "orbit"
            ai.timer = 1.0 + group.rng() * 0.8
        end
    end
end

local function equilateralStrafeTarget(group, enemy, ship, ai)
    local dx, dy = enemy.x - ship.x, enemy.y - ship.y
    local baseAngle = (dx * dx + dy * dy > 1e-4) and math.atan2(dy, dx) or (enemy.angle - math.pi / 2)
    local targetAngle = baseAngle + ai.strafeDir * math.rad(35)
    local tx, ty = clampToBounds(group, enemy,
        ship.x + math.cos(targetAngle) * ai.preferredDist,
        ship.y + math.sin(targetAngle) * ai.preferredDist)
    if (tx - ship.x) ^ 2 + (ty - ship.y) ^ 2 < 180 * 180 then
        local inAngle = math.atan2(Arena.height * 0.5 - ship.y, Arena.width * 0.5 - ship.x) + ai.strafeDir * math.rad(25)
        tx, ty = clampToBounds(group, enemy,
            ship.x + math.cos(inAngle) * ai.preferredDist,
            ship.y + math.sin(inAngle) * ai.preferredDist)
    end
    return tx, ty
end

local function patrolEquilateral(group, enemy, dt, ship)
    enemy.aimed = false
    enemy.diving = false
    local ai = enemy.ai
    if not ai then
        ai = {
            state = "reposition",
            timer = 0.85 + group.rng() * 0.8 + (enemy.aiDelay or 0),
            preferredDist = 285 + group.rng() * 115,
            strafeDir = enemy.slot or 1,
        }
        enemy.ai = ai
    end

    if ai.state == "reposition" then
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local tx, ty = equilateralStrafeTarget(group, enemy, ship, ai)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.62, enemy.sepX, enemy.sepY, false)
        if ai.timer <= 0 and isInsideBounds(group, enemy) and group:canStartAttack(enemy) then
            ai.state = "track"
            ai.timer = Enemies.laserTrackDuration
            ai.lockGrace = 0.35
            enemy.telegraph = { kind = "laser_track", progress = 0, angle = enemy.angle - math.pi / 2, locked = false }
        end
    elseif ai.state == "track" then
        ai.timer = ai.timer - dt
        local aimShipAngle = angleToShip(enemy, ship)
        pilot(enemy, dt, 0, 0, aimShipAngle, true)
        local progress = clamp(1 - ai.timer / Enemies.laserTrackDuration, 0, 1)
        enemy.telegraph = { kind = "laser_track", progress = progress, angle = enemy.angle - math.pi / 2, locked = false }
        if ai.timer <= 0 then
            if math.abs(turnError(enemy, aimShipAngle)) <= math.rad(10) or ai.lockGrace <= 0 then
                ai.lockAngle = enemy.angle - math.pi / 2
                ai.state = "lock"
                ai.timer = Enemies.laserLockDuration
                enemy.telegraph = { kind = "laser_lock", progress = 0, angle = ai.lockAngle, locked = true }
            else
                ai.lockGrace = ai.lockGrace - dt
            end
        end
    elseif ai.state == "lock" then
        ai.timer = ai.timer - dt
        pilot(enemy, dt, 0, 0, ai.lockAngle + math.pi / 2, true)
        local progress = clamp(1 - ai.timer / Enemies.laserLockDuration, 0, 1)
        enemy.telegraph = { kind = "laser_lock", progress = progress, angle = ai.lockAngle, locked = true }
        if ai.timer <= 0 then
            group.fire:shoot(enemy, ship, { angle = ai.lockAngle })
            addEntityPush(enemy, -math.cos(ai.lockAngle) * Enemies.laserRecoilSpeed,
                -math.sin(ai.lockAngle) * Enemies.laserRecoilSpeed, enemyMaxPushSpeed)
            enemy.telegraph = nil
            ai.state = "recoil"
            ai.timer = Enemies.laserRecoilDuration
        end
    else
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        pilot(enemy, dt, 0, 0, (ai.lockAngle or (enemy.angle - math.pi / 2)) + math.pi / 2, false)
        if ai.timer <= 0 then
            if group.rng() < 0.5 then ai.strafeDir = -ai.strafeDir end
            ai.state = "reposition"
            ai.timer = 1.2 + group.rng() * 0.8
        end
    end
end

local function obtuseVantage(group, enemy, ship, ai)
    local dx, dy = enemy.x - ship.x, enemy.y - ship.y
    local baseAngle = (dx * dx + dy * dy > 1e-4) and math.atan2(dy, dx) or (enemy.angle - math.pi / 2)
    local targetAngle = baseAngle + ai.strafeDir * math.rad(28)
    local ringDist = 285
    local rx = ship.x + math.cos(targetAngle) * ringDist
    local ry = ship.y + math.sin(targetAngle) * ringDist
    local vx = rx * 0.70 + (Arena.width * 0.5) * 0.30
    local vy = ry * 0.70 + (Arena.height * 0.5) * 0.30
    return clampToBounds(group, enemy, vx, vy)
end

local function patrolObtuse(group, enemy, dt, ship)
    enemy.aimed = false
    enemy.diving = false
    local ai = enemy.ai
    if not ai then
        ai = {
            state = "advance",
            timer = 1.0 + group.rng() * 0.5 + (enemy.aiDelay or 0),
            attackIndex = 0,
            strafeDir = enemy.slot or 1,
        }
        enemy.ai = ai
    end

    if ai.state == "advance" then
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local tx, ty = obtuseVantage(group, enemy, ship, ai)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.58, enemy.sepX, enemy.sepY, false)
        if ai.timer <= 0 and isInsideBounds(group, enemy) and group:canStartAttack(enemy) then
            group:notifyAttackStarted(enemy)
            ai.attackIndex = ai.attackIndex + 1
            ai.nextPattern = "curtain"
            ai.telegraphDuration = Enemies.obtuseCurtainTelegraph
            ai.state = "telegraph"
            ai.timer = ai.telegraphDuration
            enemy.telegraph = {
                kind = "curtain",
                progress = 0,
                angle = math.atan2(ship.y - enemy.y, ship.x - enemy.x),
            }
        end
    elseif ai.state == "telegraph" then
        ai.timer = ai.timer - dt
        local tx, ty = obtuseVantage(group, enemy, ship, ai)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.34, enemy.sepX, enemy.sepY, false)
        local progress = clamp(1 - ai.timer / ai.telegraphDuration, 0, 1)
        enemy.telegraph = {
            kind = "curtain",
            progress = progress,
            angle = math.atan2(ship.y - enemy.y, ship.x - enemy.x),
        }
        if ai.timer <= 0 then
            ai.burst = group.fire:shoot(enemy, ship, { pattern = ai.nextPattern })
            enemy.telegraph = nil
            ai.state = "firing"
            ai.timer = 1.1
        end
    else
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local tx, ty = obtuseVantage(group, enemy, ship, ai)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.40, enemy.sepX, enemy.sepY, false)
        if not ai.burst or (ai.burst.remaining or 0) <= 0 or ai.timer <= 0 then
            ai.burst = nil
            if group.rng() < 0.4 then ai.strafeDir = -ai.strafeDir end
            ai.state = "advance"
            ai.timer = 1.55 + group.rng() * 0.65
        end
    end
end

local function spinnerAnchor(group, enemy, ship, ai)
    local left, right, top, bottom = patrolBounds(group, enemy)
    local minX = math.max(left, math.min(right, 175))
    local maxX = math.max(minX, math.min(right, Arena.width - 175))
    local minY = math.max(top, math.min(bottom, 150))
    local maxY = math.max(minY, math.min(bottom, Arena.height - 150))
    local ax = clamp(ai.anchorX or enemy.x, minX, maxX)
    local ay = clamp(ai.anchorY or enemy.y, minY, maxY)
    local dx, dy = ax - ship.x, ay - ship.y
    local distSq = dx * dx + dy * dy
    if distSq < 160 * 160 then
        local oppX = ship.x < Arena.width * 0.5 and (Arena.width * 0.72) or (Arena.width * 0.28)
        local oppY = ship.y < Arena.height * 0.5 and (Arena.height * 0.72) or (Arena.height * 0.28)
        ax = clamp(oppX + ai.spinDir * 45, minX, maxX)
        ay = clamp(oppY - ai.spinDir * 35, minY, maxY)
        ai.anchorX, ai.anchorY = ax, ay
    end
    return ax, ay
end

local function patrolSpinner(group, enemy, dt, ship)
    enemy.aimed = false
    enemy.diving = false
    local ai = enemy.ai
    if not ai then
        local ax = clamp(enemy.x, 175, Arena.width - 175)
        local ay = clamp(enemy.y, 150, Arena.height - 150)
        ai = {
            state = "drift",
            timer = 0.8 + group.rng() * 0.6 + (enemy.aiDelay or 0),
            attackIndex = 0,
            spinDir = enemy.slot or 1,
            anchorX = ax,
            anchorY = ay,
        }
        enemy.ai = ai
    end

    if ai.state == "drift" then
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        local tx, ty = spinnerAnchor(group, enemy, ship, ai)
        flyTo(enemy, dt, tx, ty, enemy.maxSpeed * 0.62, enemy.sepX, enemy.sepY, false)
        if ai.timer <= 0 and isInsideBounds(group, enemy) and group:canStartAttack(enemy) then
            group:notifyAttackStarted(enemy)
            ai.attackIndex = ai.attackIndex + 1
            ai.nextPattern = (ai.attackIndex % 2 == 1) and "spiral" or "ring"
            ai.telegraphDuration = (ai.nextPattern == "spiral")
                and Enemies.spinnerSpiralTelegraph or Enemies.spinnerRingTelegraph
            ai.state = "telegraph"
            ai.timer = ai.telegraphDuration
            enemy.telegraph = {
                kind = ai.nextPattern,
                progress = 0,
                angle = enemy.angle - math.pi / 2,
            }
        end
    elseif ai.state == "telegraph" then
        ai.timer = ai.timer - dt
        pilot(enemy, dt, 0, 0, enemy.angle + ai.spinDir * 0.45, false)
        local progress = clamp(1 - ai.timer / ai.telegraphDuration, 0, 1)
        enemy.telegraph = {
            kind = ai.nextPattern,
            progress = progress,
            angle = enemy.angle - math.pi / 2,
        }
        if ai.timer <= 0 then
            ai.burst = group.fire:shoot(enemy, ship, {
                pattern = ai.nextPattern,
                angle = enemy.angle - math.pi / 2,
            })
            enemy.telegraph = nil
            ai.state = "firing"
            ai.timer = 1.05
        end
    else
        enemy.telegraph = nil
        ai.timer = ai.timer - dt
        pilot(enemy, dt, 0, 0, enemy.angle + ai.spinDir * 0.45, false)
        if not ai.burst or (ai.burst.remaining or 0) <= 0 or ai.timer <= 0 then
            ai.burst = nil
            if group.rng() < 0.4 then ai.spinDir = -ai.spinDir end
            ai.state = "drift"
            ai.timer = 1.35 + group.rng() * 0.65
        end
    end
end

local function patrol(group, enemy, dt, ship, aimAngle, definition)
    if enemy.kind == 1 then
        patrolWedge(group, enemy, dt, ship, aimAngle, definition)
    elseif enemy.kind == 2 then
        patrolEquilateral(group, enemy, dt, ship)
    elseif enemy.kind == 3 then
        patrolObtuse(group, enemy, dt, ship)
    else
        patrolSpinner(group, enemy, dt, ship)
    end
end

local function departureGoal(enemy, view)
    local wave = enemy.wave
    if not wave.exit then
        local leader = wave.leader
        local reference = leader and not leader.dead and leader or enemy
        local distances = {reference.x - view.left, view.right - reference.x,
            reference.y - view.top, view.bottom - reference.y}
        local bestCost, bestEdge = math.huge, 1
        for edge, angle in ipairs(departureAngles) do
            local turn = math.abs((angle - reference.angle + math.pi) % tau - math.pi)
            local cost = distances[edge] + turn * reference.maxSpeed / reference.turnSpeed
            if cost < bestCost then bestCost, bestEdge = cost, edge end
        end
        wave.exit = {
            edge = bestEdge,
            x = clamp(reference.x, view.left, view.right),
            y = clamp(reference.y, view.top, view.bottom),
        }
    end

    -- If the viewport expands, extend the same exit so all ships can still clear it.
    local exit = wave.exit
    if exit.edge == 1 then exit.x = math.min(exit.x, view.left - exitMargin)
    elseif exit.edge == 2 then exit.x = math.max(exit.x, view.right + exitMargin)
    elseif exit.edge == 3 then exit.y = math.min(exit.y, view.top - exitMargin)
    else exit.y = math.max(exit.y, view.bottom + exitMargin) end
    return exit
end

local function clearedExit(enemy, view, edge)
    local radius = enemy.radius + 2
    if edge == 1 then return enemy.x + radius < view.left end
    if edge == 2 then return enemy.x - radius > view.right end
    if edge == 3 then return enemy.y + radius < view.top end
    return enemy.y - radius > view.bottom
end

local function wrappedDelta(distance, extent)
    return (distance + extent / 2) % extent - extent / 2
end

function Enemies.computeCollisionDamage(ship, enemy, shipVx, shipVy, enemyVx, enemyVy, nx, ny)
    local nLenSq = (nx or 0) * (nx or 0) + (ny or 0) * (ny or 0)
    if nLenSq <= 1e-8 then return 0, 0, 0 end
    if math.abs(nLenSq - 1) > 1e-6 then
        local nLen = math.sqrt(nLenSq)
        nx, ny = nx / nLen, ny / nLen
    end
    local svx, svy = shipVx or 0, shipVy or 0
    local evx, evy = enemyVx or 0, enemyVy or 0
    local closingSpeed = math.max(0, -((svx - evx) * nx + (svy - evy) * ny))
    if closingSpeed < Enemies.collisionMinSpeed then
        return 0, 0, closingSpeed
    end
    local speedFactor = math.min(Enemies.collisionMaxSpeedFactor,
        ((closingSpeed - Enemies.collisionMinSpeed) / Enemies.collisionRefSpeed) ^ Enemies.collisionSpeedExponent)
    local playerIn = math.max(0, -(svx * nx + svy * ny))
    local enemyIn = math.max(0, evx * nx + evy * ny)
    local playerMass = math.max(Ship.minMass or 0.5, (ship and ship.mass) or Ship.mass)
    local enemyMass = math.max(0.1, (enemy and enemy.mass) or 1.0)
    local v0 = Enemies.collisionMomentumBaseSpeed
    local pPlayer = playerMass * (v0 + playerIn)
    local pEnemy = enemyMass * (v0 + enemyIn)
    local pSum = pPlayer + pEnemy
    local ratioToEnemy = pSum > 0 and (2 * pPlayer / pSum) or 1
    local ratioToPlayer = pSum > 0 and (2 * pEnemy / pSum) or 1
    local mRef = Enemies.collisionRefMass
    local rawEnemyDmg = Enemies.collisionEnemyDamageScale * speedFactor * math.sqrt(playerMass / mRef) * ratioToEnemy
    local rawPlayerDmg = Enemies.collisionPlayerDamageScale * speedFactor * math.sqrt(enemyMass / mRef) * ratioToPlayer
    local enemyDmg = rawEnemyDmg > 0 and math.max(1, math.floor(rawEnemyDmg + 0.5)) or 0
    local playerDmg = rawPlayerDmg > 0 and math.max(1, math.floor(rawPlayerDmg + 0.5)) or 0
    return playerDmg, enemyDmg, closingSpeed
end

local function checkContact(group, enemy, enemyIndex, ship, x, y, motion, elapsed, step, gladiator)
    if ship:isDestroyed() then return false end
    if Enemies.isIntangible(enemy) or ship:isInvulnerable() then
        enemy.contactRadius = nil
        enemy.nearMiss = nil
        return false
    end
    local dx, dy = enemy.x - x, enemy.y - y
    local margin = enemy.radius
    -- An enemy moving outside the arena can only hit the player if its hitbox reaches inside.
    local near, far = Collision.rectangleInterval(x + margin, y + margin, dx, dy,
        Arena.width + 2 * margin, Arena.height + 2 * margin)
    local first, last = math.max(0, near), math.min(1, far)
    if first > last then
        enemy.contactRadius = nil
        if gladiator then gladiator:finishNearMiss(enemy, "aerobatics", ship.x, ship.y - ship:hitRadius() - 8) end
        return false
    end

    local shipX, shipY = motion.x + motion.vx * elapsed, motion.y + motion.vy * elapsed
    local vx, vy = dx - motion.vx * step, dy - motion.vy * step
    local middle = (first + last) * 0.5
    local rx = wrappedDelta(x - shipX + vx * middle, Arena.width) - vx * middle
    local ry = wrappedDelta(y - shipY + vy * middle, Arena.height) - vy * middle
    local radius = enemy.contactRadius or ship:hitRadius() + margin
    local span = last - first
    local startRx, startRy = rx + vx * first, ry + vy * first
    local segVx, segVy = vx * span, vy * span
    local collided = enemy.contactRadius ~= nil
    local contactT = not enemy.contactRadius and Collision.circleEntry(startRx, startRy, segVx, segVy, radius)
    if contactT then
        collided = true
        if not ship:hasShield() and not ship:isInvulnerable() and (enemy.collisionCooldown or 0) <= 0 then
            local svx, svy = motion.vx or 0, motion.vy or 0
            if svx * svx + svy * svy < 1e-6 then
                svx, svy = ship:worldVelocity()
            end
            local evx = step > 0 and (dx / step) or 0
            local evy = step > 0 and (dy / step) or 0
            if evx * evx + evy * evy < 1e-6 then
                evx = (enemy.vx or 0) + (enemy.pushVx or 0)
                evy = (enemy.vy or 0) + (enemy.pushVy or 0)
            end
            local knockX = -(startRx + segVx * contactT)
            local knockY = -(startRy + segVy * contactT)
            local nLenSq = knockX * knockX + knockY * knockY
            local nx, ny
            if nLenSq > 1e-8 then
                local nLen = math.sqrt(nLenSq)
                nx, ny = knockX / nLen, knockY / nLen
            else
                local rvx, rvy = -(svx - evx), -(svy - evy)
                local rLenSq = rvx * rvx + rvy * rvy
                if rLenSq > 1e-8 then
                    local rLen = math.sqrt(rLenSq)
                    nx, ny = rvx / rLen, rvy / rLen
                else
                    nx, ny = 1, 0
                end
            end
            knockX, knockY = nx, ny

            local playerDmg, enemyDmg = Enemies.computeCollisionDamage(ship, enemy, svx, svy, evx, evy, nx, ny)
            if enemyDmg > 0 or playerDmg > 0 then
                enemy.collisionCooldown = Enemies.collisionCooldown
                local idx = (group.items[enemyIndex] == enemy) and enemyIndex or nil
                if not idx then
                    for k = 1, #group.items do
                        if group.items[k] == enemy then
                            idx = k
                            break
                        end
                    end
                end
                local destroyed = false
                if enemyDmg > 0 and idx then
                    _, destroyed = group:damage(idx, enemyDmg)
                    if not destroyed then
                        Sfx.play("impact")
                    end
                end
                if playerDmg > 0 then
                    local knockMult = destroyed and Enemies.collisionRamKillKnockMult or 1
                    ship:takeDamage(playerDmg, knockX, knockY, knockMult)
                    if gladiator then gladiator:syncPlayerDamage(ship) end
                end
                if destroyed then
                    return true
                end
            end
        end
    end

    -- Keep the contact latched until separation, even if the shield broke on impact.
    local endX, endY = rx + vx, ry + vy
    local endDistSq = endX * endX + endY * endY
    enemy.contactRadius = (not ship:isInvulnerable()) and last == 1 and endDistSq <= radius * radius and radius or nil
    if gladiator and not ship:isDestroyed() then
        local minDist, minT = Collision.closestDistance(startRx, startRy, segVx, segVy)
        local endDist = math.sqrt(endDistSq)
        local relativeSpeed = step > 0 and math.sqrt(vx * vx + vy * vy) / step or 0
        local at = elapsed + step * (first + span * minT)
        local px = (motion.x + motion.vx * at) % Arena.width
        local py = (motion.y + motion.vy * at) % Arena.height
        local grazeX = px + (startRx + segVx * minT) * 0.5
        local grazeY = py + (startRy + segVy * minT) * 0.5
        gladiator:trackNearMiss(enemy, minDist, endDist, radius, relativeSpeed, "aerobatics", collided,
            grazeX, grazeY)
    end
    return false
end

function addEntityPush(entity, dvx, dvy, maxSpeed)
    if not dvx or not dvy then return end
    if entity.addPush then
        entity:addPush(dvx, dvy, maxSpeed)
        return
    end
    local vx = (entity.pushVx or 0) + dvx
    local vy = (entity.pushVy or 0) + dvy
    local cap = maxSpeed or entity.maxPushSpeed or Ship.maxPushSpeed
    if cap and cap > 0 then
        local lenSq = vx * vx + vy * vy
        if lenSq > cap * cap then
            local scale = cap / math.sqrt(lenSq)
            vx, vy = vx * scale, vy * scale
        end
    end
    entity.pushVx, entity.pushVy = vx, vy
end

local function integrateEnemyPush(enemy, dt)
    local pOldX, pOldY = enemy.pushVx or 0, enemy.pushVy or 0
    if pOldX == 0 and pOldY == 0 then return end
    local pDecay = math.exp(-(enemy.pushDecay or Ship.pushDecay) * dt)
    local pNewX, pNewY = pOldX * pDecay, pOldY * pDecay
    if pNewX * pNewX + pNewY * pNewY < 4 then
        pNewX, pNewY = 0, 0
    end
    enemy.pushVx, enemy.pushVy = pNewX, pNewY
    enemy.x = enemy.x + (pOldX + pNewX) * 0.5 * dt
    enemy.y = enemy.y + (pOldY + pNewY) * 0.5 * dt
end

local function resolveEnemyEnemy(items, contacted)
    local count = #items
    local moved = false
    for i = 1, count - 1 do
        local a = items[i]
        if not Enemies.isIntangible(a) then
            for j = i + 1, count do
                local b = items[j]
                if not Enemies.isIntangible(b) then
                    local minDist = (a.radius or 0) + (b.radius or 0)
                    local dx, dy = a.x - b.x, a.y - b.y
                    local distSq = dx * dx + dy * dy
                    if distSq < minDist * minDist then
                        local dist = math.sqrt(distSq)
                        local nx, ny
                        if dist > 1e-6 then
                            nx, ny = dx / dist, dy / dist
                        else
                            local fallback = (i * 1.7 + j * 2.3) % tau
                            nx, ny = math.cos(fallback), math.sin(fallback)
                        end
                        local overlap = minDist - dist
                        local invA, invB = 1 / (a.mass or 1), 1 / (b.mass or 1)
                        local invSum = invA + invB
                        local shareA, shareB = invA / invSum, invB / invSum
                        a.x = a.x + nx * overlap * shareA
                        a.y = a.y + ny * overlap * shareA
                        b.x = b.x - nx * overlap * shareB
                        b.y = b.y - ny * overlap * shareB

                        local pairKey = i * (count + 1) + j
                        if not contacted[pairKey] then
                            contacted[pairKey] = true
                            local avx, avy = (a.vx or 0) + (a.pushVx or 0), (a.vy or 0) + (a.pushVy or 0)
                            local bvx, bvy = (b.vx or 0) + (b.pushVx or 0), (b.vy or 0) + (b.pushVy or 0)
                            local relVn = (avx - bvx) * nx + (avy - bvy) * ny
                            local targetSep = math.min(enemyMaxPushSpeed,
                                enemyPushBase + math.max(0, -relVn) * collisionRestitution)
                            if relVn < targetSep then
                                local impulse = targetSep - relVn
                                addEntityPush(a, nx * impulse * shareA, ny * impulse * shareA, enemyMaxPushSpeed)
                                addEntityPush(b, -nx * impulse * shareB, -ny * impulse * shareB, enemyMaxPushSpeed)
                            end
                        end
                        moved = true
                    end
                end
            end
        end
    end
    return moved
end

local function resolvePlayerEnemy(items, ship, contacted)
    if not ship or ship:isDestroyed() then return false end
    local shipRadius = ship:hitRadius()
    local invShip = 1 / (ship.mass or Ship.mass)
    local moved = false
    for i = 1, #items do
        local enemy = items[i]
        local er = enemy.radius or 0
        if not Enemies.isIntangible(enemy)
            and enemy.x + er >= 0 and enemy.x - er <= Arena.width
            and enemy.y + er >= 0 and enemy.y - er <= Arena.height then
            local minDist = shipRadius + er
            local dx = wrappedDelta(ship.x - enemy.x, Arena.width)
            local dy = wrappedDelta(ship.y - enemy.y, Arena.height)
            local distSq = dx * dx + dy * dy
            if distSq < minDist * minDist then
                local dist = math.sqrt(distSq)
                local nx, ny
                if dist > 1e-6 then
                    nx, ny = dx / dist, dy / dist
                else
                    nx, ny = 1, 0
                end
                local overlap = minDist - dist
                local invEnemy = 1 / (enemy.mass or 1)
                local invSum = invShip + invEnemy
                local shareShip, shareEnemy = invShip / invSum, invEnemy / invSum
                ship.x = (ship.x + nx * overlap * shareShip) % Arena.width
                ship.y = (ship.y + ny * overlap * shareShip) % Arena.height
                enemy.x = enemy.x - nx * overlap * shareEnemy
                enemy.y = enemy.y - ny * overlap * shareEnemy

                local pairKey = -i
                if not contacted[pairKey] then
                    contacted[pairKey] = true
                    local svxNoKnock = (ship.vx or 0) + (ship.wrapVx or 0) + (ship.pushVx or 0)
                    local svyNoKnock = (ship.vy or 0) + (ship.wrapVy or 0) + (ship.pushVy or 0)
                    local svxFull, svyFull = svxNoKnock + (ship.knockVx or 0), svyNoKnock + (ship.knockVy or 0)
                    local evx, evy = (enemy.vx or 0) + (enemy.pushVx or 0), (enemy.vy or 0) + (enemy.pushVy or 0)
                    local relVnNoKnock = (svxNoKnock - evx) * nx + (svyNoKnock - evy) * ny
                    local relVnFull = (svxFull - evx) * nx + (svyFull - evy) * ny
                    local targetSep = math.min(playerMaxPushSpeed,
                        playerPushBase + math.max(0, -relVnNoKnock) * collisionRestitution)

                    local enemyImpulse = math.max(playerPushBase * shareEnemy,
                        (targetSep - relVnNoKnock) * shareEnemy)
                    addEntityPush(enemy, -nx * enemyImpulse, -ny * enemyImpulse, enemyMaxPushSpeed)

                    if relVnFull < targetSep then
                        local playerImpulse = (targetSep - relVnFull) * shareShip
                        addEntityPush(ship, nx * playerImpulse, ny * playerImpulse, playerMaxPushSpeed)
                    end
                end
                moved = true
            end
        end
    end
    return moved
end

local function resolveCollisions(items, ship, includePlayer)
    if #items == 0 then return end
    local contacted = {}
    for _ = 1, collisionIterations do
        local moved = resolveEnemyEnemy(items, contacted)
        if includePlayer and resolvePlayerEnemy(items, ship, contacted) then
            moved = true
        end
        if not moved then break end
    end
end

local deathPalettes = {
    [1] = { { 1.0, 0.588, 0.471 }, { 1.0, 0.910, 0.820 }, { 0.729, 0.176, 0.275 } },
    [2] = { { 1.0, 0.24, 0.62 }, { 1.0, 0.78, 0.92 }, { 0.68, 0.22, 0.36 } },
    [3] = { { 1.0, 0.78, 0.28 }, { 1.0, 0.96, 0.74 }, { 1.0, 0.36, 0.22 } },
    [4] = { { 0.84, 0.36, 1.0 }, { 0.96, 0.88, 1.0 }, { 0.48, 0.14, 0.68 } },
}

local function moveEnemyStep(group, enemy, enemyIndex, dt, ship, aimAngle, motion, elapsed)
    local definition = group.types[enemy.kind]
    local view = group.view
    local remaining = dt
    local localElapsed = elapsed
    while remaining > 1e-9 do
        local x, y = enemy.x, enemy.y
        local step = remaining
        if enemy.phase == "departing" then
            local exit = departureGoal(enemy, view)
            if clearedExit(enemy, view, exit.edge) then return true end
            flyTo(enemy, step, exit.x, exit.y, enemy.maxSpeed, 0, 0)
            integrateEnemyPush(enemy, step)
        elseif enemy.phase == "warping" then
            step = math.min(remaining, enemy.phaseRemaining)
            enemy.vx, enemy.vy = 0, 0
            enemy.accelerating, enemy.braking = false, false
            enemy.phaseRemaining = enemy.phaseRemaining - step
            if enemy.phaseRemaining <= 1e-9 then
                enemy.phase = "patrol"
                enemy.phaseRemaining = enemy.patrolDuration or group.patrolDuration
                enemy.angle = angleToShip(enemy, ship)
                group.deathBursts = group.deathBursts or {}
                local palette = deathPalettes[enemy.kind] or deathPalettes[1]
                group.deathBursts[#group.deathBursts + 1] = {
                    x = enemy.x, y = enemy.y, maxRadius = (enemy.radius or 20) * 2.1,
                    age = 0, duration = 0.28, color = palette[1],
                }
                Sfx.play("warp_arrive", 1.15)
            end
        elseif enemy.phase == "edge_warning" then
            step = math.min(remaining, enemy.phaseRemaining)
            enemy.vx, enemy.vy = 0, 0
            enemy.accelerating, enemy.braking = false, false
            enemy.phaseRemaining = enemy.phaseRemaining - step
            if enemy.phaseRemaining <= 1e-9 then
                enemy.phase = "entering"
                enemy.phaseRemaining = enemy.entryDuration or 0.75
                local spd = enemy.entrySpeed or entrySpeed
                enemy.vx = math.sin(enemy.angle) * spd
                enemy.vy = -math.cos(enemy.angle) * spd
            end
        elseif enemy.phase == "entering" then
            step = math.min(remaining, enemy.phaseRemaining)
            if step > 0 then
                local angle = enemy.angle
                local spd = enemy.entrySpeed or entrySpeed
                pilot(enemy, step, math.sin(angle) * spd, -math.cos(angle) * spd, angle)
                integrateEnemyPush(enemy, step)
            end
            enemy.phaseRemaining = enemy.phaseRemaining - step
            if enemy.phaseRemaining <= 1e-9 then
                enemy.phase, enemy.phaseRemaining = "patrol", enemy.patrolDuration or group.patrolDuration
            end
        else
            if enemy.phaseRemaining == math.huge then
                patrol(group, enemy, step, ship, aimAngle, definition)
                integrateEnemyPush(enemy, step)
            else
                step = math.min(remaining, enemy.phaseRemaining)
                if step > 0 then
                    patrol(group, enemy, step, ship, aimAngle, definition)
                    integrateEnemyPush(enemy, step)
                end
                enemy.phaseRemaining = enemy.phaseRemaining - step
                if enemy.phaseRemaining <= 1e-9 then
                    enemy.phase, enemy.goal, enemy.aimed = "departing", nil, false
                    enemy.telegraph, enemy.diving, enemy.ai = nil, false, nil
                    departureGoal(enemy, view)
                end
            end
        end
        if step > 0 then
            enemy.collisionCooldown = math.max(0, (enemy.collisionCooldown or 0) - step)
            if checkContact(group, enemy, enemyIndex, ship, x, y, motion, localElapsed, step, group.gladiator) or enemy.dead then
                return false
            end
        end
        localElapsed = localElapsed + step
        remaining = remaining - step
    end
    return enemy.phase == "departing" and clearedExit(enemy, view, enemy.wave.exit.edge)
end

local function advance(group, first, totalDt, ship, aimAngle, motion)
    for i = first, #group.items do
        local enemy = group.items[i]
        enemy.prevX, enemy.prevY = enemy.x, enemy.y
    end
    local remaining = totalDt
    local elapsed = motion.duration - totalDt
    while remaining > 1e-9 do
        local substep = math.min(remaining, 1 / 60)
        for i = #group.items, first, -1 do
            local enemy = group.items[i]
            if moveEnemyStep(group, enemy, i, substep, ship, aimAngle, motion, elapsed) then
                enemy.dead = true
                table.remove(group.items, i)
            end
        end
        resolveCollisions(group.items, ship, false)
        elapsed = elapsed + substep
        remaining = remaining - substep
    end
    resolveCollisions(group.items, ship, true)
end

local function computeSeparation(items)
    local count = #items
    for i = 1, count do
        items[i].sepX, items[i].sepY = 0, 0
    end
    for i = 1, count - 1 do
        local a = items[i]
        if not Enemies.isIntangible(a) then
            for j = i + 1, count do
                local b = items[j]
                if not Enemies.isIntangible(b) then
                    local dx, dy = a.x - b.x, a.y - b.y
                    local minDist = a.radius + b.radius + 26
                    local distSq = dx * dx + dy * dy
                    if distSq < minDist * minDist then
                        local dist = math.sqrt(distSq)
                        local ux, uy
                        if dist > 1e-4 then
                            ux, uy = dx / dist, dy / dist
                        else
                            local fallback = (i * 1.7 + j * 2.3) % tau
                            ux, uy = math.cos(fallback), math.sin(fallback)
                        end
                        local push = (minDist - dist) / minDist * 86
                        a.sepX, a.sepY = a.sepX + ux * push, a.sepY + uy * push
                        b.sepX, b.sepY = b.sepX - ux * push, b.sepY - uy * push
                    end
                end
            end
        end
    end
end

function Enemies:update(dt, ship, aimAngle, camera, width, height)
    if dt <= 0 then return end
    self:updateEffects(dt)
    if self.director then
        local d = self.director
        d.obtuseCooldown = math.max(0, (d.obtuseCooldown or 0) - dt)
        d.spinnerCooldown = math.max(0, (d.spinnerCooldown or 0) - dt)
        d.wrapGrace = math.max(0, (d.wrapGrace or 0) - dt)
        local wrapCount = (ship and ship.wrapEvents) or 0
        if d.lastWrapEvents == nil then
            d.lastWrapEvents = wrapCount
        elseif wrapCount > d.lastWrapEvents then
            d.lastWrapEvents = wrapCount
            d.wrapGrace = math.max(d.wrapGrace, self.wrapGraceDuration)
        end
    end
    if camera then
        self.view.left, self.view.top = camera:screenToWorld(0, 0, width, height)
        self.view.right, self.view.bottom = camera:screenToWorld(width, height, width, height)
    end
    for _, enemy in ipairs(self.items) do
        if (enemy.hitFlash or 0) > 0 then
            enemy.hitFlash = math.max(0, enemy.hitFlash - dt)
        end
    end
    self.playerCombatPower = ship.combatPower or Ship.combatPower
    if self.gladiator then self.gladiator:beginEvasionBatch(ship) end
    self.fire:update(dt, ship, self.gladiator)
    computeSeparation(self.items)
    local x, y = ship.prevX or ship.x, ship.prevY or ship.y
    local motion = {x = x, y = y, duration = dt,
        vx = wrappedDelta(ship.x - x, Arena.width) / dt, vy = wrappedDelta(ship.y - y, Arena.height) / dt}
    advance(self, 1, dt, ship, aimAngle, motion)

    if self.squadsRemaining ~= nil and self.squadsRemaining <= 0 then
        self.spawnAccumulator = 0
        if self.gladiator then self.gladiator:endEvasionBatch(ship) end
        return
    end
    if #self.items + squadSize > self.maxCount then
        self.spawnAccumulator = 0
        if self.gladiator then self.gladiator:endEvasionBatch(ship) end
        return
    end
    self.spawnAccumulator = self.spawnAccumulator + dt * self.spawnRate
    local count = math.floor(self.spawnAccumulator + 1e-9)
    self.spawnAccumulator = math.max(0, self.spawnAccumulator - count)
    for i = 1, count do
        if #self.items + squadSize > self.maxCount then break end
        if self.squadsRemaining ~= nil and self.squadsRemaining <= 0 then break end
        local first = #self.items + 1
        self:spawnSquad(ship)
        if self.squadsRemaining ~= nil then
            self.squadsRemaining = math.max(0, self.squadsRemaining - 1)
        end
        local slice = (count - i + self.spawnAccumulator) / self.spawnRate
        -- A new arrival moves only for the portion of the frame after its birth.
        advance(self, first, slice, ship, aimAngle, motion)
    end
    if self.gladiator then self.gladiator:endEvasionBatch(ship) end
end

local function positionAt(enemy, fraction)
    local x, y = enemy.prevX or enemy.x, enemy.prevY or enemy.y
    return x + (enemy.x - x) * fraction, y + (enemy.y - y) * fraction
end

function Enemies:spawnDeathEffect(enemy)
    if not enemy then return end
    local rng = self.rng or math.random
    local palette = deathPalettes[enemy.kind] or deathPalettes[1]
    self.deathBursts = self.deathBursts or {}
    self.deathParticles = self.deathParticles or {}

    self.deathBursts[#self.deathBursts + 1] = {
        x = enemy.x or 0,
        y = enemy.y or 0,
        maxRadius = (enemy.radius or 20) * 2.3,
        age = 0,
        duration = 0.28,
        color = palette[1],
    }

    local count = enemy.kind == 3 and 30 or (enemy.kind == 4 and 24 or (enemy.kind == 2 and 20 or 14))
    local speedScale = enemy.kind == 3 and 1.2 or 1.0
    local evx, evy = (enemy.vx or 0) * 0.3, (enemy.vy or 0) * 0.3
    local ex, ey = enemy.x or 0, enemy.y or 0
    for i = 1, count do
        local angle = (i / count) * tau + (rng() - 0.5) * 0.45
        local speed = (85 + rng() * 195) * speedScale
        local shape = (i % 3 == 0) and "shard" or "spark"
        local color = palette[((i - 1) % #palette) + 1]
        self.deathParticles[#self.deathParticles + 1] = {
            x = ex + math.cos(angle) * (rng() * (enemy.radius or 16) * 0.45),
            y = ey + math.sin(angle) * (rng() * (enemy.radius or 16) * 0.45),
            vx = math.cos(angle) * speed + evx,
            vy = math.sin(angle) * speed + evy,
            drag = 2.4 + rng() * 1.4,
            age = 0,
            lifetime = 0.38 + rng() * 0.40,
            size = shape == "shard" and (3.2 + rng() * 2.3) or (2.2 + rng() * 2.0),
            shape = shape,
            angle = rng() * tau,
            spin = (rng() - 0.5) * 14,
            r = color[1],
            g = color[2],
            b = color[3],
        }
    end
end

function Enemies:updateEffects(dt)
    if not dt or dt <= 0 then return end
    if self.deathBursts then
        for i = #self.deathBursts, 1, -1 do
            local burst = self.deathBursts[i]
            burst.age = burst.age + dt
            if burst.age >= burst.duration then
                table.remove(self.deathBursts, i)
            end
        end
    end
    if self.deathParticles then
        for i = #self.deathParticles, 1, -1 do
            local p = self.deathParticles[i]
            p.age = p.age + dt
            if p.age >= p.lifetime then
                table.remove(self.deathParticles, i)
            else
                local damp = math.exp(-p.drag * dt)
                p.vx = p.vx * damp
                p.vy = p.vy * damp
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.angle = p.angle + p.spin * dt
            end
        end
    end
end

function Enemies:clearEffects()
    self.deathParticles = {}
    self.deathBursts = {}
end

function Enemies:destroy(index)
    local enemy = self.items[index]
    if not enemy then return end
    enemy.dead = true
    enemy.nearMiss = nil
    enemy.telegraph = nil
    enemy.diving = false
    self:spawnDeathEffect(enemy)
    local pitchScale = enemy.kind == 1 and 1.14 or (enemy.kind == 3 and 0.80 or (enemy.kind == 4 and 0.92 or 1.0))
    Sfx.play("enemy_destroy", pitchScale)
    table.remove(self.items, index)
    self.kills = self.kills + 1
    if enemy.kind then
        self.killsByKind[enemy.kind] = (self.killsByKind[enemy.kind] or 0) + 1
    end
    if self.gladiator then
        local enemyPower = enemy.combatPower
            or (enemy.kind and self.types[enemy.kind] and self.types[enemy.kind].combatPower)
            or Ship.combatPower
        self.gladiator:recordDestroy(enemyPower, self.playerCombatPower or Ship.combatPower, enemy.x, enemy.y)
    end
end

function Enemies:damage(index, amount)
    local enemy = self.items[index]
    if not enemy then return false, false end
    if enemy.hp == nil or amount == nil then
        self:destroy(index)
        return true, true
    end
    enemy.hp = enemy.hp - math.max(0, amount)
    if enemy.hp <= 0 then
        self:destroy(index)
        return true, true
    end
    enemy.hitFlash = 0.09
    return true, false
end

local function resolveView(group, viewOrCamera, width, height)
    if viewOrCamera then
        if viewOrCamera.screenToWorld and width and height then
            local left, top = viewOrCamera:screenToWorld(0, 0, width, height)
            local right, bottom = viewOrCamera:screenToWorld(width, height, width, height)
            return left, top, right, bottom
        elseif viewOrCamera.left then
            return viewOrCamera.left, viewOrCamera.top, viewOrCamera.right, viewOrCamera.bottom
        end
    end
    local view = group.view
    return view.left, view.top, view.right, view.bottom
end

function Enemies:isOnScreen(x, y, viewOrCamera, width, height)
    local left, top, right, bottom = resolveView(self, viewOrCamera, width, height)
    local eps = 1e-6
    return x >= left - eps and x <= right + eps and y >= top - eps and y <= bottom + eps
end

function Enemies:hitArea(x, y, radius, fraction, viewOrCamera, width, height, damage)
    local left, top, right, bottom = resolveView(self, viewOrCamera, width, height)
    local eps = 1e-6
    local hit = false
    for i = #self.items, 1, -1 do
        local enemy = self.items[i]
        if not Enemies.isIntangible(enemy) then
            local ex, ey = positionAt(enemy, fraction or 1)
            if ex >= left - eps and ex <= right + eps and ey >= top - eps and ey <= bottom + eps
                and (ex - x) ^ 2 + (ey - y) ^ 2 <= (radius + enemy.radius) ^ 2 then
                self:damage(i, damage)
                hit = true
            end
        end
    end
    return hit
end

function Enemies:hitSegment(x1, y1, x2, y2, startFraction, endFraction, viewOrCamera, width, height, damage, excludeEnemy)
    startFraction, endFraction = startFraction or 0, endFraction or 1
    local left, top, right, bottom = resolveView(self, viewOrCamera, width, height)
    local eps = 1e-6
    local dx, dy = x2 - x1, y2 - y1
    local near, far = Collision.rectangleInterval(
        x1 - (left - eps), y1 - (top - eps), dx, dy,
        (right - left) + 2 * eps, (bottom - top) + 2 * eps)
    local segStart, segEnd = math.max(0, near), math.min(1, far)
    if segStart > segEnd then return nil end

    local cx1, cy1 = x1 + dx * segStart, y1 + dy * segStart
    local span = segEnd - segStart
    local cdx, cdy = dx * span, dy * span
    local fStart = startFraction + (endFraction - startFraction) * segStart
    local fEnd = startFraction + (endFraction - startFraction) * segEnd

    local nearest, hitIndex = math.huge, nil
    for i, enemy in ipairs(self.items) do
        if enemy ~= excludeEnemy and not Enemies.isIntangible(enemy) then
            local startX, startY = positionAt(enemy, fStart)
            local endX, endY = positionAt(enemy, fEnd)
            local rx, ry = cx1 - startX, cy1 - startY
            local vx, vy = cdx - (endX - startX), cdy - (endY - startY)
            local localT = Collision.circleEntry(rx, ry, vx, vy, enemy.radius + 2)
            if localT then
                local t = segStart + span * localT
                if t < nearest then
                    local ex = startX + (endX - startX) * localT
                    local ey = startY + (endY - startY) * localT
                    if ex >= left - eps and ex <= right + eps and ey >= top - eps and ey <= bottom + eps then
                        nearest, hitIndex = t, i
                    end
                end
            end
        end
    end
    if hitIndex then
        local hitEnemy = self.items[hitIndex]
        local _, destroyed = self:damage(hitIndex, damage)
        return x1 + dx * nearest, y1 + dy * nearest, nearest, hitEnemy, destroyed
    end
end

-- Opaque vertex-colored gradient meshes for enemy hulls (cached lazily on first draw).
local hullMeshes
local enemyAimGlowMesh, enemyAimCoreMesh, enemyAimMeshesTried
local spearScale = 0.28

local function addAimQuad(verts, v1, v2, v3, v4)
    verts[#verts + 1] = v1
    verts[#verts + 1] = v2
    verts[#verts + 1] = v3
    verts[#verts + 1] = v1
    verts[#verts + 1] = v3
    verts[#verts + 1] = v4
end

local function buildFeatheredAimLineMesh(coreHalfFrac, taper, fadePower, segments)
    if not (love and love.graphics and love.graphics.newMesh) then return nil end
    local verts = {}
    for i = 0, segments - 1 do
        local t0 = i / segments
        local t1 = (i + 1) / segments
        local w0 = 1 - taper * t0
        local w1 = 1 - taper * t1
        local a0 = (1 - t0) ^ fadePower
        local a1 = (1 - t1) ^ fadePower

        if coreHalfFrac <= 0 then
            local t0Top = { t0, -w0, t0, 0, 1, 1, 1, 0 }
            local t0Mid = { t0, 0, t0, 0.5, 1, 1, 1, a0 }
            local t0Bot = { t0, w0, t0, 1, 1, 1, 1, 0 }
            local t1Top = { t1, -w1, t1, 0, 1, 1, 1, 0 }
            local t1Mid = { t1, 0, t1, 0.5, 1, 1, 1, a1 }
            local t1Bot = { t1, w1, t1, 1, 1, 1, 1, 0 }
            addAimQuad(verts, t0Top, t0Mid, t1Mid, t1Top)
            addAimQuad(verts, t0Mid, t0Bot, t1Bot, t1Mid)
        else
            local cw0, cw1 = w0 * coreHalfFrac, w1 * coreHalfFrac
            local ot0 = { t0, -w0, t0, 0, 1, 1, 1, 0 }
            local it0 = { t0, -cw0, t0, 0.35, 1, 1, 1, a0 }
            local ib0 = { t0, cw0, t0, 0.65, 1, 1, 1, a0 }
            local ob0 = { t0, w0, t0, 1, 1, 1, 1, 0 }
            local ot1 = { t1, -w1, t1, 0, 1, 1, 1, 0 }
            local it1 = { t1, -cw1, t1, 0.35, 1, 1, 1, a1 }
            local ib1 = { t1, cw1, t1, 0.65, 1, 1, 1, a1 }
            local ob1 = { t1, w1, t1, 1, 1, 1, 1, 0 }
            addAimQuad(verts, ot0, it0, it1, ot1)
            addAimQuad(verts, it0, ib0, ib1, it1)
            addAimQuad(verts, ib0, ob0, ob1, ib1)
        end
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function getEnemyAimMeshes()
    if not enemyAimMeshesTried then
        enemyAimMeshesTried = true
        enemyAimGlowMesh = buildFeatheredAimLineMesh(0, 0.35, 1.45, 16)
        enemyAimCoreMesh = buildFeatheredAimLineMesh(0.45, 0.45, 1.35, 16)
    end
    return enemyAimGlowMesh, enemyAimCoreMesh
end

local function drawGradientAimLine(g, sx, sy, angle, length, glowWidth, coreWidth, glowColor, coreColor, glowAlpha, coreAlpha)
    local glowMesh, coreMesh = getEnemyAimMeshes()
    g.push("all")
    g.translate(sx, sy)
    g.rotate(angle)
    if glowMesh and coreMesh then
        g.setBlendMode("add")
        g.setColor(glowColor[1], glowColor[2], glowColor[3], glowAlpha)
        g.draw(glowMesh, 0, 0, 0, length, glowWidth)
        g.setBlendMode("alpha")
        g.setColor(coreColor[1], coreColor[2], coreColor[3], coreAlpha)
        g.draw(coreMesh, 0, 0, 0, length, coreWidth)
    else
        local segments = 16
        for i = 0, segments - 1 do
            local t0 = i / segments
            local t1 = (i + 1) / segments
            local fade = (1 - (t0 + t1) * 0.5) ^ 1.4
            local x0, x1 = length * t0, length * t1
            g.setBlendMode("add")
            g.setLineWidth(glowWidth)
            g.setColor(glowColor[1], glowColor[2], glowColor[3], glowAlpha * fade)
            g.line(x0, 0, x1, 0)
            g.setBlendMode("alpha")
            g.setLineWidth(coreWidth)
            g.setColor(coreColor[1], coreColor[2], coreColor[3], coreAlpha * fade)
            g.line(x0, 0, x1, 0)
        end
    end
    g.pop()
end

local function vtx(x, y, c)
    return { x, y, 0, 0, c[1], c[2], c[3], 1 }
end

local function vtxA(x, y, c)
    return { x, y, 0, 0, c[1], c[2], c[3], c[4] == nil and 1 or c[4] }
end

local function fanMesh(g, cx, cy, cc, rim, rc)
    local verts = { vtx(cx, cy, cc) }
    for i = 1, #rim, 2 do
        verts[#verts + 1] = vtx(rim[i], rim[i + 1], rc)
    end
    verts[#verts + 1] = vtx(rim[1], rim[2], rc)
    return g.newMesh(verts, "fan", "static")
end

local function circleMesh(g, cx, cy, r, segments, cc, rc)
    local verts = { vtx(cx, cy, cc) }
    local step = 2 * math.pi / segments
    for i = 0, segments do
        local a = i * step
        verts[#verts + 1] = vtx(cx + math.cos(a) * r, cy + math.sin(a) * r, rc)
    end
    return g.newMesh(verts, "fan", "static")
end

local function radialGlowMesh(g, cx, cy, r, segments, cc, rc)
    local verts = { vtxA(cx, cy, cc) }
    local step = 2 * math.pi / segments
    for i = 0, segments do
        local a = i * step
        verts[#verts + 1] = vtxA(cx + math.cos(a) * r, cy + math.sin(a) * r, rc)
    end
    return g.newMesh(verts, "fan", "static")
end

local function gradPolyMesh(g, pointsAndColors)
    local verts = {}
    local cx, cy, cr, cg, cb = 0, 0, 0, 0, 0
    local n = #pointsAndColors
    for i = 1, n do
        local p = pointsAndColors[i]
        cx, cy = cx + p[1], cy + p[2]
        cr, cg, cb = cr + p[3][1], cg + p[3][2], cb + p[3][3]
    end
    verts[1] = { cx / n, cy / n, 0, 0, cr / n, cg / n, cb / n, 1 }
    for i = 1, n do
        local p = pointsAndColors[i]
        verts[#verts + 1] = vtx(p[1], p[2], p[3])
    end
    verts[#verts + 1] = vtx(pointsAndColors[1][1], pointsAndColors[1][2], pointsAndColors[1][3])
    return g.newMesh(verts, "fan", "static")
end

local function pushTri(verts, p1, c1, p2, c2, p3, c3)
    verts[#verts + 1] = vtxA(p1[1], p1[2], c1)
    verts[#verts + 1] = vtxA(p2[1], p2[2], c2)
    verts[#verts + 1] = vtxA(p3[1], p3[2], c3)
end

local function pushQuad(verts, p1, c1, p2, c2, p3, c3, p4, c4)
    pushTri(verts, p1, c1, p2, c2, p3, c3)
    pushTri(verts, p1, c1, p3, c3, p4, c4)
end

local function buildSpearMesh(g, p0y, p1x, p1y, p2x, p2y, p3x, p3y, notchR, notchY, colorAtY)
    local function evalCubic(t, a, b, c, d)
        local u = 1 - t
        return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
    end

    local function bezierXAtY(targetY)
        if targetY <= p0y then return 0 end
        if targetY >= p3y then return p3x end
        local lo, hi = 0, 1
        for _ = 1, 12 do
            local mid = (lo + hi) * 0.5
            if evalCubic(mid, p0y, p1y, p2y, p3y) < targetY then
                lo = mid
            else
                hi = mid
            end
        end
        return evalCubic((lo + hi) * 0.5, 0, p1x, p2x, p3x)
    end

    local verts = {}
    local notchTop = notchY - notchR
    local upperSlices, notchSlices, tailSlices = 8, 6, 3

    for side = -1, 1, 2 do
        -- 1. Upper concave blade (y: p0y -> notchTop)
        for i = 0, upperSlices - 1 do
            local y0 = p0y + (notchTop - p0y) * (i / upperSlices)
            local y1 = p0y + (notchTop - p0y) * ((i + 1) / upperSlices)
            local x0, x1 = bezierXAtY(y0) * side, bezierXAtY(y1) * side
            local c0, c1 = colorAtY(y0), colorAtY(y1)
            pushQuad(verts, { 0, y0 }, c0, { x0, y0 }, c0, { x1, y1 }, c1, { 0, y1 }, c1)
        end

        -- 2. Rear crescent notch flank (a: -pi/2 -> 0)
        for i = 0, notchSlices - 1 do
            local a0 = -math.pi * 0.5 + (math.pi * 0.5) * (i / notchSlices)
            local a1 = -math.pi * 0.5 + (math.pi * 0.5) * ((i + 1) / notchSlices)
            local ax0, ay0 = notchR * math.cos(a0) * side, notchY + notchR * math.sin(a0)
            local ax1, ay1 = notchR * math.cos(a1) * side, notchY + notchR * math.sin(a1)
            local bx0, bx1 = bezierXAtY(ay0) * side, bezierXAtY(ay1) * side
            local c0, c1 = colorAtY(ay0), colorAtY(ay1)
            pushQuad(verts, { ax0, ay0 }, c0, { bx0, ay0 }, c0, { bx1, ay1 }, c1, { ax1, ay1 }, c1)
        end

        -- 3. Wingtip tail (y: notchY -> p3y)
        local corner = { notchR * side, notchY }
        local cc = colorAtY(notchY)
        for i = 0, tailSlices - 1 do
            local y0 = notchY + (p3y - notchY) * (i / tailSlices)
            local y1 = notchY + (p3y - notchY) * ((i + 1) / tailSlices)
            local x0, x1 = bezierXAtY(y0) * side, bezierXAtY(y1) * side
            pushTri(verts, corner, cc, { x0, y0 }, colorAtY(y0), { x1, y1 }, colorAtY(y1))
        end
    end

    return g.newMesh(verts, "triangles", "static")
end

local function buildSpearTrailMesh(g)
    local topColor = { 1.0, 0.471, 0.278, 0.82 }
    local botColor = { 0.851, 0.149, 0.306, 0.0 }
    local verts = {}
    pushQuad(verts, { -0.5, 0 }, topColor, { 0.5, 0 }, topColor, { 0.5, 1 }, botColor, { -0.5, 1 }, botColor)
    return g.newMesh(verts, "triangles", "static")
end

local function buildSpearPlumeMesh(g)
    local cTop = { 1.0, 0.969, 0.839, 0.95 }
    local cMid = { 1.0, 0.431, 0.251, 0.65 }
    local cTip = { 1.0, 0.165, 0.333, 0.0 }
    local verts = {}
    pushQuad(verts, { -1, 0 }, cTop, { 1, 0 }, cTop, { 0.55, 0.45 }, cMid, { -0.55, 0.45 }, cMid)
    pushTri(verts, { -0.55, 0.45 }, cMid, { 0.55, 0.45 }, cMid, { 0, 1 }, cTip)
    return g.newMesh(verts, "triangles", "static")
end

local function getHullMeshes(g)
    if hullMeshes then return hullMeshes end
    if not g.newMesh then return nil end

    -- Kind 1: WEDGE (SPEAR — Nova Drift flat-gradient concave spearhead)
    local s = spearScale
    local backingColor = { 0.729, 0.176, 0.275, 0.88 }
    local function spearBodyColor(y)
        local t = math.max(0, math.min(1, (y - (-68 * s)) / (104 * s)))
        if t <= 0.48 then
            local k = t / 0.48
            return { 1.0, 1.0 - 0.090 * k, 1.0 - 0.180 * k, 1.0 }
        end
        local k = (t - 0.48) / 0.52
        return { 1.0, 0.910 - 0.322 * k, 0.820 - 0.349 * k, 1.0 }
    end

    -- Kind 2: EQUILATERAL (BOLTTHROWER — Nova Drift orchid-pink serrated pincer-jaws)
    -- Kind 3: OBTUSE (RAZOR SPECTRE — flat sleek crimson Spectre Lance)

    hullMeshes = {
        [1] = {
            bloom = radialGlowMesh(g, 0, -0.5, 22, 24, { 1.0, 0.420, 0.290, 0.22 }, { 1.0, 0.420, 0.290, 0.0 }),
            backing = buildSpearMesh(g, -73 * s, 11 * s, -30 * s, 24 * s, 4 * s, 37 * s, 39 * s, 15 * s, 29 * s,
                function() return backingColor end),
            body = buildSpearMesh(g, -68 * s, 10 * s, -27 * s, 22 * s, 5 * s, 33.5 * s, 36 * s, 15 * s, 26.5 * s,
                spearBodyColor),
            orbHalo = radialGlowMesh(g, 0, 31 * s, 7.5 * s, 18, { 1.0, 0.439, 0.302, 0.62 }, { 1.0, 0.439, 0.302, 0.0 }),
            orb = circleMesh(g, 0, 31 * s, 5.0 * s, 16, { 1.0, 0.992, 0.961 }, { 1.0, 0.955, 0.895 }),
            trailUnit = buildSpearTrailMesh(g),
            plumeUnit = buildSpearPlumeMesh(g),
        },
        [2] = {
            bloom = radialGlowMesh(g, 0, -2, 30, 24, { 1.0, 0.294, 0.596, 0.24 }, { 1.0, 0.294, 0.596, 0.0 }),
        },
        [3] = {
            bloom = radialGlowMesh(g, 0, 0, 38, 28, { 1.0, 0.169, 0.227, 0.26 }, { 1.0, 0.169, 0.227, 0.0 }),
        },
        [4] = {
            bloom = radialGlowMesh(g, 0, 0, 34, 24, { 0.82, 0.34, 1.0, 0.24 }, { 0.82, 0.34, 1.0, 0.0 }),
        },
    }
    return hullMeshes
end

local BOLT_JAW_RIGHT_RAIL = { 4.4, -23.5, 7.4, -19.8, 8.4, 6.0, 4.4, 9.0 }
local BOLT_JAW_LEFT_RAIL = { -4.4, -23.5, -4.4, 9.0, -8.4, 6.0, -7.4, -19.8 }
local BOLT_JAW_RIGHT_TEETH = {
    { 4.6, -22.2, 4.6, -18.0, 2.6, -19.0, 2.6, -21.2 },
    { 4.6, -15.6, 4.6, -11.4, 2.4, -12.4, 2.4, -14.6 },
    { 4.6, -9.0, 4.6, -4.8, 2.4, -5.8, 2.4, -8.0 },
    { 4.6, -2.4, 4.6, 1.8, 2.4, 0.8, 2.4, -1.4 },
}
local BOLT_JAW_LEFT_TEETH = {
    { -4.6, -22.2, -2.6, -21.2, -2.6, -19.0, -4.6, -18.0 },
    { -4.6, -15.6, -2.4, -14.6, -2.4, -12.4, -4.6, -11.4 },
    { -4.6, -9.0, -2.4, -8.0, -2.4, -5.8, -4.6, -4.8 },
    { -4.6, -2.4, -2.4, -1.4, -2.4, 0.8, -4.6, 1.8 },
}
local BOLT_JAW_RIGHT_OUTLINE = {
    4.4, -23.5, 7.4, -19.8, 8.4, 6.0, 4.4, 9.0,
    4.4, 1.8, 2.4, 0.8, 2.4, -1.4, 4.4, -2.4,
    4.4, -4.8, 2.4, -5.8, 2.4, -8.0, 4.4, -9.0,
    4.4, -11.4, 2.4, -12.4, 2.4, -14.6, 4.4, -15.6,
    4.4, -18.0, 2.6, -19.0, 2.6, -21.2, 4.4, -22.2,
}
local BOLT_JAW_LEFT_OUTLINE = {
    -4.4, -23.5, -4.4, -22.2, -2.6, -21.2, -2.6, -19.0,
    -4.4, -18.0, -4.4, -15.6, -2.4, -14.6, -2.4, -12.4,
    -4.4, -11.4, -4.4, -9.0, -2.4, -8.0, -2.4, -5.8,
    -4.4, -4.8, -4.4, -2.4, -2.4, -1.4, -2.4, 0.8,
    -4.4, 1.8, -4.4, 9.0, -8.4, 6.0, -7.4, -19.8,
}
local BOLT_TAIL_RIGHT = { 9.6, 3.8, 19.0, 15.6, 14.0, 22.0, 7.0, 17.8, 5.2, 10.6 }
local BOLT_TAIL_LEFT = { -9.6, 3.8, -5.2, 10.6, -7.0, 17.8, -14.0, 22.0, -19.0, 15.6 }
local BOLT_BRIDGE = { -2.8, 11.0, 2.8, 11.0, 4.6, 19.6, -4.6, 19.6 }

local function drawBoltthrowerPlates(g, mode)
    if mode == "fill" then
        g.polygon("fill", BOLT_JAW_LEFT_RAIL)
        for _, tooth in ipairs(BOLT_JAW_LEFT_TEETH) do
            g.polygon("fill", tooth)
        end
        g.polygon("fill", BOLT_JAW_RIGHT_RAIL)
        for _, tooth in ipairs(BOLT_JAW_RIGHT_TEETH) do
            g.polygon("fill", tooth)
        end
    else
        g.polygon("line", BOLT_JAW_LEFT_OUTLINE)
        g.polygon("line", BOLT_JAW_RIGHT_OUTLINE)
    end
    g.polygon(mode, BOLT_TAIL_LEFT)
    g.polygon(mode, BOLT_TAIL_RIGHT)
    g.polygon(mode, BOLT_BRIDGE)
end

local OBTUSE_CORE_OUTLINE = {
    0, -7.4, 9.2, -0.6, 8.4, 4.2, 3.8, 9.0,
    0, 6.6, -3.8, 9.0, -8.4, 4.2, -9.2, -0.6,
}
local OBTUSE_CORE_FILLS = {
    { 0, -7.4, 9.2, -0.6, 8.4, 4.2, 6.1, 6.6, -6.1, 6.6, -8.4, 4.2, -9.2, -0.6 },
    { 0, 6.6, 6.1, 6.6, 3.8, 9.0 },
    { -6.1, 6.6, 0, 6.6, -3.8, 9.0 },
}
local OBTUSE_COWL_RIGHT_OUTLINE = { 1.5, -12.5, 7.2, -10.8, 33.5, 4.8, 24.2, 9.6, 11.8, 5.8, 11.4, -1.0, 1.5, -9.4 }
local OBTUSE_COWL_RIGHT_FILLS = {
    { 1.5, -12.5, 7.2, -10.8, 20.35, -3.0, 11.4, -1.0, 1.5, -9.4 },
    { 20.35, -3.0, 33.5, 4.8, 24.2, 9.6, 11.8, 5.8, 11.4, -1.0 },
}
local OBTUSE_COWL_LEFT_OUTLINE = { -1.5, -12.5, -1.5, -9.4, -11.4, -1.0, -11.8, 5.8, -24.2, 9.6, -33.5, 4.8, -7.2, -10.8 }
local OBTUSE_COWL_LEFT_FILLS = {
    { -1.5, -12.5, -1.5, -9.4, -11.4, -1.0, -20.35, -3.0, -7.2, -10.8 },
    { -20.35, -3.0, -11.4, -1.0, -11.8, 5.8, -24.2, 9.6, -33.5, 4.8 },
}

local function drawObtuseSpectrePlates(g, mode)
    if mode == "fill" then
        for _, part in ipairs(OBTUSE_CORE_FILLS) do
            g.polygon("fill", part)
        end
        for _, part in ipairs(OBTUSE_COWL_LEFT_FILLS) do
            g.polygon("fill", part)
        end
        for _, part in ipairs(OBTUSE_COWL_RIGHT_FILLS) do
            g.polygon("fill", part)
        end
    else
        g.polygon("line", OBTUSE_CORE_OUTLINE)
        g.polygon("line", OBTUSE_COWL_LEFT_OUTLINE)
        g.polygon("line", OBTUSE_COWL_RIGHT_OUTLINE)
    end
end

-- Nova Drift enemy hull renderer (SPEAR, BOLTTHROWER, CRIMSON SPECTRE).
-- Drawn in local space centered at (0, 0), nose pointing up (-Y).
function Enemies.drawHull(kind, aimed, time, opts)
    local g = love.graphics
    local t = time or 0
    local pulse = 0.86 + 0.14 * math.sin(t * 7.2)
    local thrust = opts and opts.thrust or 0
    local flicker = 1 + math.sin(t * 48) * 0.14
    local meshes = getHullMeshes(g)

    if kind == 1 then
        -- WEDGE: SPEAR (Nova Drift flat-gradient concave spearhead + rear notch core orb)
        local s = spearScale
        local bloomPulse = aimed and 1.15 or (0.85 + 0.15 * pulse)
        if meshes then
            g.setColor(1, 1, 1, bloomPulse)
            g.draw(meshes[1].bloom)
        else
            g.setColor(1, 0.420, 0.290, 0.14 * bloomPulse)
            g.circle("fill", 0, -0.5, 19)
        end

        if thrust > 0.05 then
            local len = (9 + 11 * thrust) * flicker
            if meshes then
                g.setColor(1, 1, 1, thrust)
                g.draw(meshes[1].trailUnit, -33 * s, 34 * s, 0, 3 * s, len)
                g.draw(meshes[1].trailUnit, 33 * s, 34 * s, 0, 3 * s, len)
                g.draw(meshes[1].plumeUnit, 0, 28 * s, 0, 7 * s, len)
            else
                g.setColor(1, 0.471, 0.278, 0.65 * thrust)
                g.rectangle("fill", -34.5 * s, 34 * s, 3 * s, len * 0.7)
                g.rectangle("fill", 31.5 * s, 34 * s, 3 * s, len * 0.7)
                g.setColor(1, 0.431, 0.251, 0.72 * thrust)
                g.polygon("fill", -7 * s, 28 * s, 0, 28 * s + len, 7 * s, 28 * s)
                g.setColor(1, 0.969, 0.839, 0.92 * thrust)
                g.polygon("fill", -3 * s, 28 * s, 0, 28 * s + len * 0.5, 3 * s, 28 * s)
            end
        end

        if meshes then
            g.setColor(1, aimed and 1.15 or 1, aimed and 1.15 or 1, 1)
            g.draw(meshes[1].backing)
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[1].body)
            g.setColor(1, 1, 1, aimed and 1 or (0.75 + 0.25 * pulse))
            g.draw(meshes[1].orbHalo)
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[1].orb)
        else
            g.setColor(0.729, 0.176, 0.275, 0.88)
            g.polygon("fill", 0, -73 * s, 37 * s, 39 * s, 15 * s, 29 * s, 0, 14 * s, -15 * s, 29 * s, -37 * s, 39 * s)
            g.setColor(1, 0.86, 0.76, 1)
            g.polygon("fill", 0, -68 * s, 18 * s, 12 * s, -18 * s, 12 * s)
            g.polygon("fill", -18 * s, 12 * s, -33.5 * s, 36 * s, -15 * s, 26.5 * s, 0, 11.5 * s)
            g.polygon("fill", 18 * s, 12 * s, 33.5 * s, 36 * s, 15 * s, 26.5 * s, 0, 11.5 * s)
            g.setColor(1, 0.439, 0.302, 0.55)
            g.circle("fill", 0, 31 * s, 7.5 * s)
            g.setColor(1, 0.992, 0.961, 1)
            g.circle("fill", 0, 31 * s, 5.0 * s)
        end

    elseif kind == 2 then
        -- EQUILATERAL: BOLTTHROWER (serrated orchid-pink pincer-jaws + swept tail stabilizers)
        g.push("all")

        if thrust > 0.05 then
            local len = (8 + 6 * thrust) * flicker
            for _, side in ipairs({ -1, 1 }) do
                local nx = side * 4.8
                g.setColor(1.0, 0.294, 0.596, 0.72 * thrust)
                g.polygon("fill", nx - 2.6, 18.5, nx, 18.5 + len, nx + 2.6, 18.5)
                g.setColor(1.0, 0.90, 0.98, 0.92 * thrust)
                g.polygon("fill", nx - 1.1, 18.5, nx, 18.5 + len * 0.55, nx + 1.1, 18.5)
            end
        end

        -- 1. Soft additive outer magenta-pink bloom (#ff4b98).
        local bloomPulse = aimed and 1.18 or (0.88 + 0.12 * pulse)
        if meshes and meshes[2] and meshes[2].bloom then
            g.setColor(1, 1, 1, bloomPulse)
            g.draw(meshes[2].bloom)
        else
            g.setColor(1.0, 0.294, 0.596, 0.18 * bloomPulse)
            g.circle("fill", 0, -2, 26)
        end

        g.setBlendMode("add")
        g.setLineJoin("bevel")
        local br, bg, bb = 1.0, aimed and 0.42 or 0.294, aimed and 0.52 or 0.596
        for _, layer in ipairs({
            { width = 7.5, alpha = 0.08 },
            { width = 4.2, alpha = 0.16 },
            { width = 2.0, alpha = 0.28 },
        }) do
            g.setColor(br, bg, bb, layer.alpha * bloomPulse)
            g.setLineWidth(layer.width)
            drawBoltthrowerPlates(g, "line")
        end

        -- Subtle pulsing laser charge filament down the open serrated jaw channel.
        g.setLineWidth(1.4)
        g.setColor(1.0, 0.65, 0.92, (aimed and 0.55 or 0.32) * pulse)
        g.line(0, -19, 0, 3)
        g.setBlendMode("alpha")

        -- 2. Luminous pastel orchid-pink / rose solid plates.
        g.setColor(0.961, 0.839, 1.0, 1)
        g.polygon("fill", BOLT_JAW_LEFT_RAIL)
        for _, tooth in ipairs(BOLT_JAW_LEFT_TEETH) do
            g.polygon("fill", tooth)
        end
        g.polygon("fill", BOLT_JAW_RIGHT_RAIL)
        for _, tooth in ipairs(BOLT_JAW_RIGHT_TEETH) do
            g.polygon("fill", tooth)
        end

        g.setColor(1.0, 0.863, 0.961, 1)
        g.polygon("fill", BOLT_TAIL_LEFT)
        g.polygon("fill", BOLT_TAIL_RIGHT)
        g.polygon("fill", BOLT_BRIDGE)

        -- 3. Crisp anti-aliased edge highlight.
        g.setLineWidth(0.75)
        g.setColor(1.0, 0.96, 1.0, aimed and 0.95 or 0.78)
        drawBoltthrowerPlates(g, "line")

        g.pop()

    elseif kind == 3 then
        -- OBTUSE: RAZOR SPECTRE (flat sleek crimson Spectre Lance in Nova Drift tone)
        g.push("all")

        if thrust > 0.05 then
            local len = (9 + 6 * thrust) * flicker
            for _, spec in ipairs({ { -14.0, 6.8, 0.72 }, { 0, 7.8, 1.0 }, { 14.0, 6.8, 0.72 } }) do
                local nx, ny, s = spec[1], spec[2], spec[3]
                g.setColor(1.0, 0.24, 0.26, 0.74 * s * thrust)
                g.polygon("fill", nx - 3.4 * s, ny, nx, ny + len * s, nx + 3.4 * s, ny)
                g.setColor(1.0, 0.90, 0.88, 0.92 * s * thrust)
                g.polygon("fill", nx - 1.4 * s, ny, nx, ny + len * 0.55 * s, nx + 1.4 * s, ny)
            end
        end

        -- 1. Soft additive crimson-red outer bloom (#ff2b3a).
        local bloomPulse = aimed and 1.18 or (0.88 + 0.12 * pulse)
        if meshes and meshes[3] and meshes[3].bloom then
            g.setColor(1, 1, 1, bloomPulse)
            g.draw(meshes[3].bloom)
        else
            g.setColor(1.0, 0.169, 0.227, 0.20 * bloomPulse)
            g.circle("fill", 0, 0, 32)
        end

        g.setBlendMode("add")
        g.setLineJoin("bevel")
        local br, bg, bb = 1.0, aimed and 0.30 or 0.169, aimed and 0.26 or 0.227
        for _, layer in ipairs({
            { width = 8.5, alpha = 0.09 },
            { width = 4.8, alpha = 0.18 },
            { width = 2.2, alpha = 0.32 },
        }) do
            g.setColor(br, bg, bb, layer.alpha * bloomPulse)
            g.setLineWidth(layer.width)
            drawObtuseSpectrePlates(g, "line")
        end

        g.push()
        g.scale(1.04)
        g.setColor(br, bg, bb, 0.06 * bloomPulse)
        drawObtuseSpectrePlates(g, "fill")
        g.pop()
        g.setBlendMode("alpha")

        -- 2. Luminous red-tone solid plates: wide cowls (#ff9c98) + faceted center core (#ffcdc9).
        g.setColor(1.0, 0.612, 0.596, 1)
        for _, part in ipairs(OBTUSE_COWL_LEFT_FILLS) do
            g.polygon("fill", part)
        end
        for _, part in ipairs(OBTUSE_COWL_RIGHT_FILLS) do
            g.polygon("fill", part)
        end

        g.setColor(1.0, 0.804, 0.788, 1)
        for _, part in ipairs(OBTUSE_CORE_FILLS) do
            g.polygon("fill", part)
        end

        -- 3. Crisp anti-aliased edge highlight.
        g.setLineWidth(0.8)
        g.setColor(1.0, 0.910, 0.902, aimed and 0.96 or 0.84)
        drawObtuseSpectrePlates(g, "line")

        g.pop()
    else
        -- SPINNER: VIOLET GYRE (dark amethyst octagon + 4 rotating crimson-violet diamond petals + bright core)
        local bloomPulse = 0.86 + 0.14 * pulse
        if meshes and meshes[4] then
            g.setColor(1, 1, 1, bloomPulse)
            g.draw(meshes[4].bloom)
        else
            g.setColor(0.82, 0.34, 1.0, 0.16 * bloomPulse)
            g.circle("fill", 0, 0, 28)
        end

        g.push("all")
        g.setLineJoin("bevel")
        local spin = t * 1.6
        g.rotate(spin)

        g.setBlendMode("add")
        for _, layer in ipairs({
            { width = 6.5, alpha = 0.10 },
            { width = 3.2, alpha = 0.22 },
        }) do
            g.setColor(0.86, 0.34, 1.0, layer.alpha * bloomPulse)
            g.setLineWidth(layer.width)
            for petal = 0, 3 do
                g.push()
                g.rotate(petal * math.pi * 0.5)
                g.polygon("line", 0, -22, 6.2, -9.5, 0, -5.2, -6.2, -9.5)
                g.pop()
            end
        end
        g.setBlendMode("alpha")

        -- Dark amethyst octagonal core chassis
        g.setColor(0.20, 0.08, 0.30, 1)
        g.polygon("fill", 0, -13, 9.2, -9.2, 13, 0, 9.2, 9.2, 0, 13, -9.2, 9.2, -13, 0, -9.2, -9.2)
        g.setLineWidth(1.0)
        g.setColor(0.92, 0.56, 1.0, 0.9)
        g.polygon("line", 0, -13, 9.2, -9.2, 13, 0, 9.2, 9.2, 0, 13, -9.2, 9.2, -13, 0, -9.2, -9.2)

        -- 4 crimson-violet petals
        for petal = 0, 3 do
            g.push()
            g.rotate(petal * math.pi * 0.5)
            g.setColor(0.86, 0.32, 0.92, 1)
            g.polygon("fill", 0, -22, 6.2, -9.5, 0, -5.2, -6.2, -9.5)
            g.setLineWidth(0.9)
            g.setColor(1.0, 0.84, 0.98, 0.92)
            g.polygon("line", 0, -22, 6.2, -9.5, 0, -5.2, -6.2, -9.5)
            g.pop()
        end

        -- Inner coral-magenta emitter ring and white-lavender core
        g.setLineWidth(1.4)
        g.setColor(1.0, 0.44, 0.86, 0.92 * pulse)
        g.circle("line", 0, 0, 7.2)
        g.setColor(0.98, 0.92, 1.0, 1)
        g.circle("fill", 0, 0, 3.6)

        g.pop()
    end
end

local function chargeNoise(idx, tick)
    local v = math.sin(idx * 12.9898 + tick * 78.233) * 43758.5453
    return (v - math.floor(v)) * 2 - 1
end

local function drawBoltthrowerLaserCharge(g, tel, time, seedOffset)
    local isLock = tel.kind == "laser_lock"
    local p = math.max(0, math.min(1, tel.progress or 0))
    local intensity = isLock and (0.82 + 0.18 * p) or (0.30 + 0.50 * p)
    local rate = isLock and 38 or 24
    local tick = math.floor((time or 0) * rate) + (seedOffset or 0) * 13

    g.push("all")
    g.setBlendMode("add")
    g.setLineJoin("bevel")

    -- 1. Central core buildup inside Boltthrower's serrated jaw channel (0, -7).
    local coreY = -7
    g.setColor(1.0, 0.26, 0.62, 0.30 * intensity)
    g.circle("fill", 0, coreY, 6.0 + 6.0 * intensity)
    g.setColor(1.0, 0.58, 0.86, 0.78 * intensity)
    g.circle("fill", 0, coreY, 2.8 + 2.6 * intensity)
    local coreR = 1.4 + 1.6 * intensity + chargeNoise(1, tick) * 0.35
    g.setColor(1.0, 0.97, 1.0, 0.98)
    g.circle("fill", 0, coreY, math.max(1.0, coreR))

    -- 2. Crackling center rail bolt (6-segment jagged arc from y=5 to y=-22.5).
    local amp = 1.6 + 2.4 * intensity
    local railPts = { 0, 5 }
    for s = 1, 5 do
        local fy = 5 + (-27.5) * (s / 6)
        local fx = chargeNoise(10 + s, tick) * amp
        railPts[#railPts + 1] = fx
        railPts[#railPts + 1] = fy
    end
    railPts[#railPts + 1] = chargeNoise(19, tick) * 0.8
    railPts[#railPts + 1] = -22.5
    g.setLineWidth(3.2)
    g.setColor(1.0, 0.28, 0.64, 0.48 * intensity)
    g.line(railPts)
    g.setLineWidth(1.2)
    g.setColor(1.0, 0.96, 1.0, 0.95 * intensity)
    g.line(railPts)

    -- 3. Cross-jaw crackling sparks snapping from teeth into center channel.
    local jawYs = { -18, -12, -5, 1 }
    for idx, jy in ipairs(jawYs) do
        local side = ((idx + tick) % 2 == 0) and 1 or -1
        local startX = side * 3.8
        local midX = startX * 0.45 + chargeNoise(30 + idx, tick) * 1.4
        local midY = jy + chargeNoise(40 + idx, tick) * 1.8
        local endX = chargeNoise(50 + idx, tick) * 1.2
        local endY = coreY + (jy - coreY) * 0.35
        g.setLineWidth(2.0)
        g.setColor(1.0, 0.32, 0.68, 0.42 * intensity)
        g.line(startX, jy, midX, midY, endX, endY)
        g.setLineWidth(0.9)
        g.setColor(1.0, 0.95, 1.0, 0.88 * intensity)
        g.line(startX, jy, midX, midY, endX, endY)
    end

    if isLock then
        for a = 1, 2 do
            local side = a == 1 and -1 or 1
            local mx1 = side * (1.5 + math.abs(chargeNoise(60 + a, tick)) * 2.5)
            local mx2 = chargeNoise(70 + a, tick) * 3.4
            g.setLineWidth(2.4)
            g.setColor(1.0, 0.30, 0.68, 0.55)
            g.line(0, -18, mx1, -23.5, mx2, -29.0)
            g.setLineWidth(1.0)
            g.setColor(1.0, 0.98, 1.0, 0.95)
            g.line(0, -18, mx1, -23.5, mx2, -29.0)
        end
    end

    -- 4. Collapsing charge ring centered in the channel.
    local ringR = 14.0 - 10.0 * p
    g.setLineWidth(1.1)
    g.setColor(1.0, 0.72, 0.94, (0.35 + 0.55 * p))
    g.circle("line", 0, coreY, ringR)

    g.pop()
end

local function drawTelegraph(g, enemy, time)
    local tel = enemy.telegraph
    if not tel then return end
    local p = tel.progress or 0
    local t = time or 0
    if tel.kind == "laser_track" or tel.kind == "laser_lock" then
        local angle = tel.angle or (enemy.angle - math.pi / 2)
        local dx, dy = math.cos(angle), math.sin(angle)
        local muzzle = (enemy.radius or 24) * 0.72
        local sx, sy = enemy.x + dx * muzzle, enemy.y + dy * muzzle
        local charge = tel.kind == "laser_track"
            and clamp(p, 0, 1) * 0.65
            or (0.65 + clamp(p, 0, 1) * 0.35)
        local strength = charge ^ 1.25
        drawGradientAimLine(g, sx, sy, angle, 720,
            3.2 + 3.6 * charge, 1.0 + 0.75 * charge,
            { 1.0, 0.24, 0.62 },
            { 1.0, 0.54 + 0.42 * charge, 0.78 + 0.20 * charge },
            0.06 + 0.40 * strength,
            0.10 + 0.85 * strength)
    elseif tel.kind == "dive" then
        local dx, dy = tel.dirX or math.sin(enemy.angle), tel.dirY or -math.cos(enemy.angle)
        local offset = (enemy.radius or 16) + 2
        local sx, sy = enemy.x + dx * offset, enemy.y + dy * offset
        local intensity = 0.25 + 0.75 * clamp(p, 0, 1)
        drawGradientAimLine(g, sx, sy, math.atan2(dy, dx), 260,
            3.2, 1.1,
            { 1.0, 0.44, 0.24 }, { 1.0, 0.72, 0.48 },
            0.24 * intensity, 0.58 * intensity)
    elseif tel.kind == "curtain" then
        local ringR = 26 - 16 * p
        g.setLineWidth(1.8)
        g.setColor(1.0, 0.80, 0.26, 0.55 + 0.35 * p)
        g.circle("line", enemy.x, enemy.y, ringR)
        local aim = tel.angle or (enemy.angle - math.pi / 2)
        g.setLineWidth(1.4)
        g.setColor(1.0, 0.78, 0.24, 0.28 + 0.32 * p)
        g.arc("line", "open", enemy.x, enemy.y, (enemy.radius or 28) + 14, aim - math.rad(36), aim + math.rad(36))
    elseif tel.kind == "spiral" then
        local baseA = (tel.angle or 0) + (time or 0) * 4.5
        local r1, r2 = (enemy.radius or 22) * 0.6, (enemy.radius or 22) + 16 - 6 * p
        g.setLineWidth(1.6)
        g.setColor(0.86, 0.42, 1.0, 0.48 + 0.42 * p)
        for arm = 0, 3 do
            local a = baseA + arm * (math.pi * 0.5)
            g.line(enemy.x + math.cos(a) * r1, enemy.y + math.sin(a) * r1,
                enemy.x + math.cos(a) * r2, enemy.y + math.sin(a) * r2)
        end
    elseif tel.kind == "ring" then
        local r = (enemy.radius or 22) + 18 - 10 * p
        g.setLineWidth(1.5)
        g.setColor(0.86, 0.42, 1.0, 0.45 + 0.45 * p)
        for seg = 0, 7 do
            local a0 = (time or 0) * 2.5 + seg * (tau / 8)
            g.arc("line", "open", enemy.x, enemy.y, r, a0, a0 + tau / 14)
        end
    end
end

function Enemies:draw(time)
    local g = love.graphics
    g.push("all")
    for _, burst in ipairs(self.deathBursts or {}) do
        local p = math.max(0, math.min(1, burst.age / burst.duration))
        local fade = 1 - p
        local radius = 6 + burst.maxRadius * (1 - fade * fade)
        local c = burst.color
        g.setColor(c[1], c[2], c[3], 0.28 * fade)
        g.circle("fill", burst.x, burst.y, radius * 0.72)
        g.setColor(1, 0.96, 0.86, 0.85 * fade * fade)
        g.circle("fill", burst.x, burst.y, math.max(2, burst.maxRadius * 0.28 * fade))
        g.setLineWidth(2.4 * fade + 0.6)
        g.setColor(c[1], c[2], c[3], 0.92 * fade)
        g.circle("line", burst.x, burst.y, radius)
    end
    for _, pt in ipairs(self.deathParticles or {}) do
        local p = math.max(0, math.min(1, pt.age / pt.lifetime))
        local alpha = 1 - p * p
        local s = pt.size * (1 - 0.45 * p)
        if pt.shape == "shard" then
            g.push()
            g.translate(pt.x, pt.y)
            g.rotate(pt.angle)
            g.setColor(pt.r, pt.g, pt.b, 0.92 * alpha)
            g.polygon("fill", -s, -s * 0.55, s * 1.15, 0, -s * 0.45, s * 0.85)
            g.setColor(1, 0.95, 0.84, 0.65 * alpha)
            g.setLineWidth(0.8)
            g.polygon("line", -s, -s * 0.55, s * 1.15, 0, -s * 0.45, s * 0.85)
            g.pop()
        else
            local spd = math.sqrt(pt.vx * pt.vx + pt.vy * pt.vy)
            local tail = math.min(14, 3 + spd * 0.045)
            local dx, dy = spd > 1e-4 and pt.vx / spd or 1, spd > 1e-4 and pt.vy / spd or 0
            g.setLineWidth(math.max(1.1, s * 0.75))
            g.setColor(pt.r, pt.g, pt.b, 0.95 * alpha)
            g.line(pt.x, pt.y, pt.x - dx * tail, pt.y - dy * tail)
            g.setColor(1, 0.97, 0.88, 0.9 * alpha)
            g.circle("fill", pt.x, pt.y, math.max(1, s * 0.42))
        end
    end
    for _, enemy in ipairs(self.items) do
        if not Enemies.isIntangible(enemy) then
            drawTelegraph(g, enemy, time)
        end
    end
    for idx, enemy in ipairs(self.items) do
        if enemy.phase == "warping" then
            local dur = enemy.warpDuration or Enemies.warpDuration
            local p = clamp(1 - (enemy.phaseRemaining or 0) / math.max(1e-4, dur), 0, 1)
            local palette = deathPalettes[enemy.kind] or deathPalettes[1]
            local c = palette[1]
            local ringR = 58 - (58 - (enemy.radius or 20)) * p
            g.setLineWidth(1.6 + 1.4 * p)
            g.setColor(c[1], c[2], c[3], 0.35 + 0.55 * p)
            for seg = 0, 3 do
                local a0 = (time or 0) * 3.8 + seg * (math.pi * 0.5)
                g.arc("line", "open", enemy.x, enemy.y, ringR, a0, a0 + math.pi * 0.34)
            end
            local dR = ringR * 0.72
            g.push()
            g.translate(enemy.x, enemy.y)
            g.rotate(-(time or 0) * 2.4)
            g.setLineWidth(1.1)
            g.setColor(1, 0.92, 0.96, 0.30 + 0.55 * p)
            g.polygon("line", 0, -dR, dR, 0, 0, dR, -dR, 0)
            g.pop()

            local def = Enemies.types[enemy.kind]
            if def and def.vertices then
                local sc = 0.45 + 0.55 * p
                g.push()
                g.translate(enemy.x, enemy.y)
                g.rotate(enemy.angle)
                g.scale(sc, sc)
                g.setColor(c[1], c[2], c[3], 0.14 + 0.28 * p)
                g.polygon("fill", def.vertices)
                g.setLineWidth(1.3)
                g.setColor(1, 0.95, 0.92, 0.38 + 0.55 * p)
                g.polygon("line", def.vertices)
                g.pop()
            end
            if p > 0.70 then
                local flash = (p - 0.70) / 0.30
                g.setColor(1, 0.96, 0.92, 0.75 * flash)
                g.circle("fill", enemy.x, enemy.y, 4 + 10 * flash)
            end
        elseif enemy.phase == "edge_warning" then
            local view = self.view
            local ix = clamp(enemy.x, view.left + 22, view.right - 22)
            local iy = clamp(enemy.y, view.top + 22, view.bottom - 22)
            local dx, dy = math.sin(enemy.angle), -math.cos(enemy.angle)
            local px, py = -dy, dx
            local dur = enemy.edgeWarningDuration or Enemies.edgeWarningDuration
            local p = clamp(1 - (enemy.phaseRemaining or 0) / math.max(1e-4, dur), 0, 1)
            local pulse = 0.55 + 0.45 * math.sin((time or 0) * 24)
            g.setLineWidth(1.3)
            g.setColor(1.0, 0.34, 0.24, (0.30 + 0.30 * p) * pulse)
            for d = 14, 74, 20 do
                g.line(ix + dx * d, iy + dy * d, ix + dx * (d + 11), iy + dy * (d + 11))
            end
            local tipX, tipY = ix + dx * 10, iy + dy * 10
            g.setLineWidth(2.2)
            g.setColor(1.0, 0.48, 0.28, (0.65 + 0.35 * p) * pulse)
            g.line(tipX - dx * 12 + px * 9, tipY - dy * 12 + py * 9, tipX, tipY, tipX - dx * 12 - px * 9, tipY - dy * 12 - py * 9)
            local backX, backY = ix - dx * 2, iy - dy * 2
            g.setLineWidth(1.5)
            g.setColor(1.0, 0.85, 0.55, 0.70 * pulse)
            g.line(backX - dx * 8 + px * 6, backY - dy * 8 + py * 6, backX, backY, backX - dx * 8 - px * 6, backY - dy * 8 - py * 6)
        else
            local thrust = 0
            if enemy.diving then
                thrust = 1.45
            elseif enemy.accelerating then
                thrust = 1
            elseif enemy.speed then
                local spd = enemy:speed()
                if spd > 18 then thrust = math.min(0.6, spd / math.max(1, enemy.maxSpeed or 200)) end
            end
            g.push()
            g.translate(enemy.x, enemy.y)
            g.rotate(enemy.angle)
            Enemies.drawHull(enemy.kind, enemy.aimed, time, { thrust = thrust })
            if enemy.kind == 2 and enemy.telegraph
                and (enemy.telegraph.kind == "laser_track" or enemy.telegraph.kind == "laser_lock") then
                drawBoltthrowerLaserCharge(g, enemy.telegraph, time, idx)
            end
            if (enemy.hitFlash or 0) > 0 then
                local flashAlpha = math.min(1, enemy.hitFlash / 0.09)
                local r = (enemy.radius or 20) * 1.15
                g.setColor(1, 0.96, 0.88, 0.42 * flashAlpha)
                g.circle("fill", 0, 0, r * 0.85)
                g.setLineWidth(2.0)
                g.setColor(1, 1, 1, 0.85 * flashAlpha)
                g.circle("line", 0, 0, r)
            end
            g.pop()
            if enemy.hp and enemy.maxHp and enemy.hp > 0 and enemy.hp < enemy.maxHp then
                local ratio = math.max(0, math.min(1, enemy.hp / enemy.maxHp))
                local bw = enemy.kind == 3 and 44 or ((enemy.kind == 2 or enemy.kind == 4) and 32 or 24)
                local bh = 3.5
                local bx = enemy.x - bw * 0.5
                local by = enemy.y - (enemy.radius or 20) - 10
                g.setColor(0.03, 0.04, 0.08, 0.82)
                g.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2, 1.5, 1.5)
                if enemy.kind == 4 then
                    g.setColor(0.84, 0.34 + 0.30 * ratio, 1.0, 0.95)
                else
                    local fillG = enemy.kind == 3 and (0.45 + 0.35 * ratio) or (0.24 + 0.36 * ratio)
                    local fillB = enemy.kind == 3 and 0.20 or 0.28
                    g.setColor(1.0, fillG, fillB, 0.95)
                end
                g.rectangle("fill", bx, by, math.max(2, bw * ratio), bh, 1, 1)
                g.setColor(1, 1, 1, 0.25)
                g.setLineWidth(0.7)
                g.rectangle("line", bx - 1, by - 1, bw + 2, bh + 2, 1.5, 1.5)
            end
        end
    end
    g.pop()
    self.fire:draw()
end

return Enemies
