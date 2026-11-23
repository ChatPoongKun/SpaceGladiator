local Ship = require("ship")
local Arena = require("arena")
local Collision = require("collision")
local EnemyFire = require("enemy_fire")
local Enemies = {}
Enemies.__index = Enemies
local tau = 2 * math.pi
local exitMargin = 155
local wingAlignment = math.rad(6)
local attackAlignment = math.rad(6)
local contactDamage = 20

Enemies.spawnRate = 1 / 4
Enemies.maxCount = 15
Enemies.patrolDuration = 10
Enemies.types = {
    {
        name = "WEDGE", vertices = {0, -15, 10, 10, 0, 5, -10, 10},
        radius = 16, evadeSpeed = 94, turnSpeed = 3.0,
        thrust = 285, brake = 5.0, maxSpeed = 500,
        patrolMin = 55, patrolMax = 110, arrivalRadius = 32,
        combatPower = 40,
    },
    {
        name = "EQUILATERAL", vertices = {0, -24, -12 * math.sqrt(3), 12, 12 * math.sqrt(3), 12},
        radius = 24, evadeSpeed = 78,
        turnSpeed = 3.5, thrust = 255, brake = 2.5, maxSpeed = 320,
        patrolMin = 120, patrolMax = 185, arrivalRadius = 40,
        combatPower = 70,
    },
    {
        name = "OBTUSE", vertices = {0, -12, -26, 10, 26, 10},
        radius = 28, evadeSpeed = 62, turnSpeed = 2.5, thrust = 218, brake = 4.0, maxSpeed = 200,
        patrolMin = 195, patrolMax = 290, arrivalRadius = 48,
        combatPower = 100,
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
    }, Enemies)
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
    enemy.combatPower = definition.combatPower
    enemy.maxSpeed, enemy.thrust, enemy.turnSpeed = definition.maxSpeed, definition.thrust, definition.turnSpeed
    enemy.brake = definition.brake
    -- Give lighter thrust the same time to build momentum out of low-speed drag.
    local thrustRatio = enemy.thrust / Ship.thrust
    enemy.driftThreshold = Ship.driftThreshold * thrustRatio
    enemy.driftDeceleration = Ship.driftDeceleration * thrustRatio
    enemy.vx, enemy.vy = limitVector(options and options.vx or 0, options and options.vy or 0, enemy.maxSpeed)
    enemy.prevX, enemy.prevY = enemy.x, enemy.y
    enemy.angle = (options and options.angle or math.atan2(ship.x - enemy.x, enemy.y - ship.y)) % tau
    enemy.wave = options and options.wave or {}
    enemy.slot = options and options.slot or (self.rng() < 0.5 and -1 or 1)
    enemy.evadeTime, enemy.evadeCooldown = 0, 0
    enemy.sepX, enemy.sepY = 0, 0
    enemy.aimed = false
    local entryTime = options and options.entryTime
    enemy.phase = entryTime and "entering" or "patrol"
    enemy.phaseRemaining = entryTime or self.patrolDuration

    self.items[#self.items + 1] = enemy
    return enemy
end

function Enemies:spawnSquad(ship)
    if #self.items + squadSize > self.maxCount then return {} end
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
    local wave = {entryAngle = angle}
    local leader = self:spawn(ship, 3, {
        x = lx, y = ly, vx = vx, vy = vy, angle = angle, entryTime = entryTime, wave = wave,
    })
    wave.leader = leader
    local squad = {leader}

    for _, member in ipairs(formation) do
        local x, y = formationPosition(lx, ly, angle, member.right, member.forward)
        local shipMember = self:spawn(ship, member.kind, {
            x = x, y = y, vx = vx, vy = vy, angle = angle, entryTime = entryTime, wave = wave, slot = member.slot,
        })
        if member.kind == 1 then
            if wave.attacker then
                shipMember.wingman, wave.attacker.wingman = wave.attacker, shipMember
            else
                wave.attacker = shipMember
            end
        end
        squad[#squad + 1] = shipMember
    end
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
            enemy.evadeTime, enemy.evadeCooldown = 0.55, 1.3
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

local function chooseWaypoint(group, enemy, ship, definition, angle, radius)
    local left, right, top, bottom = patrolBounds(group, enemy)
    local reference = enemy.goal or enemy
    if not angle then
        angle = group.rng() * tau
        if not enemy.goal then
            -- Favor the side this aircraft is approaching from on its first leg.
            angle = math.atan2(reference.y - ship.y, reference.x - ship.x) + (angle - math.pi) * 0.45
        end
    end
    radius = radius or definition.patrolMin + group.rng() * (definition.patrolMax - definition.patrolMin)
    local minimumLeg = enemy.goal and math.max(definition.arrivalRadius * 2, radius * 0.65)
        or definition.arrivalRadius + 1
    local x, y, bestDistance
    for attempt = 0, 11 do
        local bearing = angle + attempt * tau / 12
        local px, py = ship.x + math.cos(bearing) * radius, ship.y + math.sin(bearing) * radius
        if px >= left and px <= right and py >= top and py <= bottom then
            local distance = (px - reference.x) ^ 2 + (py - reference.y) ^ 2
            if not bestDistance or distance > bestDistance then x, y, bestDistance = px, py, distance end
            if distance >= minimumLeg ^ 2 then break end
        end
    end
    if not bestDistance then
        local cornerX = ship.x < (left + right) / 2 and right or left
        local cornerY = ship.y < (top + bottom) / 2 and bottom or top
        local dx, dy = limitVector(cornerX - ship.x, cornerY - ship.y, radius)
        x, y = clamp(ship.x + dx, left, right), clamp(ship.y + dy, top, bottom)
    end
    return {x = x, y = y}
end

local function atWaypoint(enemy, definition)
    return (enemy.goal.x - enemy.x) ^ 2 + (enemy.goal.y - enemy.y) ^ 2 <= definition.arrivalRadius ^ 2
end

local function wingWaypoint(group, enemy, ship, attacking)
    local definition = group.types[enemy.kind]
    local vx, vy = ship:worldVelocity()
    local moving = vx * vx + vy * vy > 1
    if attacking and moving then
        local distance = math.sqrt((enemy.x - ship.x) ^ 2 + (enemy.y - ship.y) ^ 2)
        local lead = math.min(2.5, 0.6 + math.sqrt(2 * distance / enemy.thrust))
        local left, right, top, bottom = patrolBounds(group, enemy)
        local _, edge = Collision.rectangleInterval(ship.x - left, ship.y - top, vx, vy, right - left, bottom - top)
        lead = clamp(edge, 0, lead)
        return {x = clamp(ship.x + vx * lead, left, right), y = clamp(ship.y + vy * lead, top, bottom)}
    end
    local heading = moving and math.atan2(vy, vx) or enemy.wave.entryAngle - math.pi / 2
    return chooseWaypoint(group, enemy, ship, definition, heading + enemy.slot * math.pi / 2,
        attacking and definition.patrolMin or wingSpread + wingTrail)
end

local function angleToShip(enemy, ship)
    local dx, dy = ship.x - enemy.x, enemy.y - ship.y
    if dx * dx + dy * dy < 1e-12 then return enemy.angle end
    return math.atan2(dx, dy)
end

local function prepareWingPass(group, enemy, dt, ship, definition)
    local wave = enemy.wave
    local attacking = wave.attacker == enemy
    if not enemy.goal then
        enemy.goal = wingWaypoint(group, enemy, ship, attacking)
    end
    if enemy.goal.state == "holding" or (enemy.goal.state == "flying" and atWaypoint(enemy, definition)) then
        local wingman = enemy.wingman
        if attacking and wingman.goal and wingman.goal.state == "holding" then
            wave.burst = group.fire:shoot(enemy, ship)
            wave.attacker = wingman
            -- The first round fixes the next intercept. The last round clears both ships to move.
            wingman.goal = wingWaypoint(group, wingman, ship, true)
            enemy.goal = wingWaypoint(group, enemy, ship, false)
        else
            enemy.goal.state = "holding"
            local aim = attacking and angleToShip(enemy, ship) or enemy.angle
            pilot(enemy, dt, 0, 0, aim, true)
            return false
        end
    end
    local goal = enemy.goal
    if goal.state ~= "flying" then
        local bearing = math.atan2(goal.x - enemy.x, enemy.y - goal.y)
        if wave.burst or math.abs(turnError(enemy, bearing)) > wingAlignment then
            pilot(enemy, dt, 0, 0, bearing, true)
            return false
        end
        goal.state = "flying"
    end
    return true
end

local function patrol(group, enemy, dt, ship, aimAngle, definition)
    local evadeX, evadeY = aimEvasion(enemy, ship, aimAngle, dt)
    if enemy.wingman then
        if not prepareWingPass(group, enemy, dt, ship, definition) then return end
    else
        if not enemy.goal then
            enemy.goal = chooseWaypoint(group, enemy, ship, definition)
        elseif enemy.kind == 1 then
            if atWaypoint(enemy, definition) then
                group.fire:shoot(enemy, ship)
                enemy.goal = chooseWaypoint(group, enemy, ship, definition)
            end
        else
            if enemy.goal.state ~= "aiming" and enemy.goal.state ~= "firing" and atWaypoint(enemy, definition) then
                enemy.goal.state = "aiming"
            end

            if enemy.goal.state == "aiming" then
                local aim = angleToShip(enemy, ship)
                local ready = math.abs(turnError(enemy, aim)) <= attackAlignment
                    and (enemy.kind ~= 3 or enemy:speed() == 0)
                if ready then
                    local burst = group.fire:shoot(enemy, ship)
                    if burst and burst.remaining > 0 then
                        enemy.goal.state = "firing"
                        enemy.goal.burst = burst
                        enemy.goal.aimAngle = aim
                        pilot(enemy, dt, 0, 0, aim, true)
                        return
                    end
                    enemy.goal = chooseWaypoint(group, enemy, ship, definition)
                else
                    pilot(enemy, dt, 0, 0, aim, true)
                    return
                end
            elseif enemy.goal.state == "firing" then
                if enemy.goal.burst and enemy.goal.burst.remaining > 0 then
                    pilot(enemy, dt, 0, 0, enemy.goal.aimAngle or angleToShip(enemy, ship), true)
                    return
                end
                enemy.goal = chooseWaypoint(group, enemy, ship, definition)
            end
        end
    end

    local steerX = enemy.sepX + evadeX * definition.evadeSpeed
    local steerY = enemy.sepY + evadeY * definition.evadeSpeed
    local speed = enemy.maxSpeed * 0.84
    flyTo(enemy, dt, enemy.goal.x, enemy.goal.y, speed, steerX, steerY, false)
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

local function checkContact(enemy, ship, x, y, motion, elapsed, step, gladiator)
    if ship:isDestroyed() then return end
    if ship:isInvulnerable() then
        enemy.contactRadius = nil
        enemy.nearMiss = nil
        return
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
        return
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
    if not enemy.contactRadius and Collision.circleEntry(startRx, startRy, segVx, segVy, radius) then
        ship:takeDamage(contactDamage)
        if gladiator then gladiator:syncPlayerDamage(ship) end
        collided = true
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
end

local function move(group, enemy, dt, ship, aimAngle, motion)
    local definition = group.types[enemy.kind]
    local view = group.view
    while dt > 1e-9 do
        local x, y = enemy.x, enemy.y
        local step = math.min(dt, 1 / 60)
        if enemy.phase == "departing" then
            local exit = departureGoal(enemy, view)
            if clearedExit(enemy, view, exit.edge) then return true end
            flyTo(enemy, step, exit.x, exit.y, enemy.maxSpeed, 0, 0)
        else
            step = math.min(step, enemy.phaseRemaining)
            if step > 0 then
                if enemy.phase == "patrol" then
                    patrol(group, enemy, step, ship, aimAngle, definition)
                else
                    local angle = enemy.angle
                    pilot(enemy, step, math.sin(angle) * entrySpeed, -math.cos(angle) * entrySpeed, angle)
                end
            end
            enemy.phaseRemaining = enemy.phaseRemaining - step
            if enemy.phaseRemaining <= 1e-9 then
                if enemy.phase == "entering" then
                    enemy.phase, enemy.phaseRemaining = "patrol", group.patrolDuration
                else
                    enemy.phase, enemy.goal, enemy.aimed = "departing", nil, false
                    departureGoal(enemy, view)
                end
            end
        end
        if step > 0 then checkContact(enemy, ship, x, y, motion, motion.duration - dt, step, group.gladiator) end
        dt = dt - step
    end
    return enemy.phase == "departing" and clearedExit(enemy, view, enemy.wave.exit.edge)
end

local function advance(group, first, dt, ship, aimAngle, motion)
    for i = #group.items, first, -1 do
        local enemy = group.items[i]
        enemy.prevX, enemy.prevY = enemy.x, enemy.y
        if move(group, enemy, dt, ship, aimAngle, motion) then
            enemy.dead = true
            table.remove(group.items, i)
        end
    end
end

local function computeSeparation(items)
    local count = #items
    for i = 1, count do
        items[i].sepX, items[i].sepY = 0, 0
    end
    for i = 1, count - 1 do
        local a = items[i]
        for j = i + 1, count do
            local b = items[j]
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

function Enemies:update(dt, ship, aimAngle, camera, width, height)
    if dt <= 0 then return end
    if camera then
        self.view.left, self.view.top = camera:screenToWorld(0, 0, width, height)
        self.view.right, self.view.bottom = camera:screenToWorld(width, height, width, height)
    end
    -- A final round partway through this frame clears the wings for the next movement frame.
    for _, enemy in ipairs(self.items) do
        local wave = enemy.wave
        if enemy.wingman and wave.burst and wave.burst.remaining == 0 then wave.burst = nil end
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

function Enemies:destroy(index)
    local enemy = self.items[index]
    if not enemy then return end
    enemy.dead = true
    enemy.nearMiss = nil
    if enemy.wingman then
        enemy.wingman.wingman, enemy.wingman.goal = nil, nil
        enemy.wave.attacker, enemy.wave.burst = nil, nil
    end
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

function Enemies:hitArea(x, y, radius, fraction, viewOrCamera, width, height)
    local left, top, right, bottom = resolveView(self, viewOrCamera, width, height)
    local eps = 1e-6
    local hit = false
    for i = #self.items, 1, -1 do
        local enemy = self.items[i]
        local ex, ey = positionAt(enemy, fraction or 1)
        if ex >= left - eps and ex <= right + eps and ey >= top - eps and ey <= bottom + eps
            and (ex - x) ^ 2 + (ey - y) ^ 2 <= (radius + enemy.radius) ^ 2 then
            self:destroy(i)
            hit = true
        end
    end
    return hit
end

function Enemies:hitSegment(x1, y1, x2, y2, startFraction, endFraction, viewOrCamera, width, height)
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
    if hitIndex then
        self:destroy(hitIndex)
        return x1 + dx * nearest, y1 + dy * nearest, nearest
    end
end

-- Opaque vertex-colored gradient meshes for enemy hulls (cached lazily on first draw).
local hullMeshes

local function vtx(x, y, c)
    return { x, y, 0, 0, c[1], c[2], c[3], 1 }
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

local function getHullMeshes(g)
    if hullMeshes then return hullMeshes end
    if not g.newMesh then return nil end

    -- Kind 1: WEDGE (TRACER)
    local wDark = { 0.085, 0.028, 0.055 }
    local wWarm = { 0.44, 0.14, 0.08 }
    local wCoreRim = { 1, 0.42, 0.16 }
    local wCoreMid = { 1, 0.94, 0.72 }
    local wLHi, wLLo = { 0.30, 0.12, 0.18 }, { 0.15, 0.055, 0.095 }
    local wRHi, wRLo = { 0.46, 0.16, 0.23 }, { 0.25, 0.085, 0.135 }

    -- Kind 2: EQUILATERAL (BEAMCASTER)
    local eDark = { 0.085, 0.032, 0.075 }
    local eGlow = { 0.48, 0.10, 0.28 }
    local eLHi, eLLo = { 0.30, 0.11, 0.19 }, { 0.15, 0.055, 0.105 }
    local eRHi, eRLo = { 0.45, 0.15, 0.23 }, { 0.24, 0.08, 0.14 }

    -- Kind 3: OBTUSE (BULWARK-PRIME)
    local oDark = { 0.09, 0.035, 0.065 }
    local oAmber = { 0.52, 0.24, 0.09 }
    local oLHi, oLLo = { 0.32, 0.13, 0.18 }, { 0.16, 0.065, 0.105 }
    local oRHi, oRLo = { 0.45, 0.17, 0.23 }, { 0.25, 0.09, 0.135 }
    local oCitHi, oCitLo = { 0.34, 0.14, 0.19 }, { 0.15, 0.06, 0.10 }

    hullMeshes = {
        [1] = {
            underframe = fanMesh(g, 0, -1, wWarm, { 0, -12, -9, 9, 0, 6, 9, 9 }, wDark),
            core = fanMesh(g, 0, -2, wCoreMid, { 0, -9, -2.5, 0, 0, 5, 2.5, 0 }, wCoreRim),
            leftMain = gradPolyMesh(g, { { -2.2, -16.5, wLHi }, { -11.5, 10, wLLo }, { -7.5, 11, wLLo }, { -4.2, 4.5, wLHi } }),
            leftInner = gradPolyMesh(g, { { -2.2, -16.5, wLHi }, { -4.2, 4.5, wLLo }, { -2.4, -4, wLHi } }),
            rightMain = gradPolyMesh(g, { { 2.2, -16.5, wRHi }, { 11.5, 10, wRLo }, { 7.5, 11, wRLo }, { 4.2, 4.5, wRHi } }),
            rightInner = gradPolyMesh(g, { { 2.2, -16.5, wRHi }, { 4.2, 4.5, wRLo }, { 2.4, -4, wRHi } }),
        },
        [2] = {
            underframe = fanMesh(g, 0, -8, eGlow, { 0, -14, -16, 9, 16, 9 }, eDark),
            orb = circleMesh(g, 0, -10, 3.4, 18, { 1, 1, 1 }, { 1, 0.20, 0.58 }),
            leftRail = gradPolyMesh(g, { { -4, -23.5, eLHi }, { -9.5, -6, eLLo }, { -8, 13, eLLo }, { -4.5, 14, eLHi } }),
            leftRailIn = gradPolyMesh(g, { { -4, -23.5, eLHi }, { -4.5, 14, eLLo }, { -3.2, -13, eLHi } }),
            rightRail = gradPolyMesh(g, { { 4, -23.5, eRHi }, { 9.5, -6, eRLo }, { 8, 13, eRLo }, { 4.5, 14, eRHi } }),
            rightRailIn = gradPolyMesh(g, { { 4, -23.5, eRHi }, { 4.5, 14, eRLo }, { 3.2, -13, eRHi } }),
            leftWing = gradPolyMesh(g, { { -11.5, -3, eLHi }, { -21.5, 10.5, eLLo }, { -17.5, 14, eLLo }, { -10, 9.5, eLHi } }),
            rightWing = gradPolyMesh(g, { { 11.5, -3, eRHi }, { 21.5, 10.5, eRLo }, { 17.5, 14, eRLo }, { 10, 9.5, eRHi } }),
            bridge = gradPolyMesh(g, { { -4.5, 2, eLHi }, { 4.5, 2, eRHi }, { 3.5, 11, eRLo }, { -3.5, 11, eLLo } }),
        },
        [3] = {
            underframe = fanMesh(g, 0, 3, oAmber, { 0, -13, -26, 8, 0, 13, 26, 8 }, oDark),
            leftWing = gradPolyMesh(g, { { -13, -7, oLHi }, { -28.5, 6.5, oLLo }, { -24, 12.5, oLLo }, { -14, 9, oLHi }, { -11, -1, oLHi } }),
            rightWing = gradPolyMesh(g, { { 13, -7, oRHi }, { 28.5, 6.5, oRLo }, { 24, 12.5, oRLo }, { 14, 9, oRHi }, { 11, -1, oRHi } }),
            citadel = fanMesh(g, 0, 2, oCitHi, { 0, -16, -11, -8, -9.5, 11.5, -3.5, 13.5, 3.5, 13.5, 9.5, 11.5, 11, -8 }, oCitLo),
            browLeft = gradPolyMesh(g, { { 0, -15.5, { 0.96, 0.76, 0.34 } }, { -9, -8, { 0.72, 0.48, 0.16 } }, { -6.5, -4.5, { 0.78, 0.54, 0.18 } }, { 0, -9.5, { 0.92, 0.68, 0.26 } } }),
            browRight = gradPolyMesh(g, { { 0, -15.5, { 1, 0.92, 0.60 } }, { 9, -8, { 0.88, 0.64, 0.24 } }, { 6.5, -4.5, { 0.94, 0.72, 0.30 } }, { 0, -9.5, { 1, 0.86, 0.46 } } }),
            core = fanMesh(g, 0, 2, { 1, 0.98, 0.88 }, { 0, -4.5, -4.2, 2, 0, 8, 4.2, 2 }, { 1, 0.68, 0.18 }),
        },
    }
    return hullMeshes
end

-- Nova Assault enemy hull renderer (Option 1: TRACER, BEAMCASTER, BULWARK-PRIME).
-- Drawn in local space centered at (0, 0), nose pointing up (-Y).
function Enemies.drawHull(kind, aimed, time, opts)
    local g = love.graphics
    local t = time or 0
    local pulse = 0.86 + 0.14 * math.sin(t * 7.2)
    local thrust = opts and opts.thrust or 0
    local flicker = 1 + math.sin(t * 48) * 0.14
    local meshes = getHullMeshes(g)

    if kind == 1 then
        -- WEDGE: TRACER (split obsidian pincer interceptor + opaque gradient core)
        if thrust > 0.05 then
            local len = (9 + 6 * thrust) * flicker
            g.setColor(1, 0.42, 0.18, 0.72 * thrust)
            g.polygon("fill", -3.4, 6, 0, 6 + len, 3.4, 6)
            g.setColor(1, 0.95, 0.78, 0.92 * thrust)
            g.polygon("fill", -1.4, 6, 0, 6 + len * 0.55, 1.4, 6)
        end

        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[1].underframe)
            g.setColor(1, aimed and 1 or (0.88 + 0.12 * pulse), aimed and 0.92 or 1, 1)
            g.draw(meshes[1].core)
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[1].leftMain)
            g.draw(meshes[1].leftInner)
            g.draw(meshes[1].rightMain)
            g.draw(meshes[1].rightInner)
        else
            g.setColor(0.18, 0.06, 0.07, 1)
            g.polygon("fill", 0, -12, -9, 9, 0, 6)
            g.polygon("fill", 0, -12, 0, 6, 9, 9)
            g.setColor(1, aimed and 0.72 or 0.58, aimed and 0.44 or 0.26, 1)
            g.polygon("fill", 0, -9, -2.5, 0, 0, 5, 2.5, 0)
            g.setColor(0.22, 0.09, 0.14, 1)
            g.polygon("fill", -2.2, -16.5, -11.5, 10, -7.5, 11, -4.2, 4.5)
            g.polygon("fill", -2.2, -16.5, -4.2, 4.5, -2.4, -4)
            g.setColor(0.37, 0.12, 0.18, 1)
            g.polygon("fill", 2.2, -16.5, 11.5, 10, 7.5, 11, 4.2, 4.5)
            g.polygon("fill", 2.2, -16.5, 4.2, 4.5, 2.4, -4)
        end
        g.setColor(1, 0.97, 0.84, 1)
        g.circle("fill", 0, -2, 1.5)

        -- Crisp vermilion/coral outlines & leading-edge speculars
        g.setLineWidth(1.1)
        if aimed then
            g.setColor(1, 0.66, 0.48, 1)
        else
            g.setColor(1, 0.30, 0.32, 1)
        end
        g.line(-2.2, -16.5, -11.5, 10, -7.5, 11, -4.2, 4.5, -2.4, -4, -2.2, -16.5)
        if aimed then
            g.setColor(1, 0.78, 0.58, 1)
        else
            g.setColor(1, 0.42, 0.39, 1)
        end
        g.line(2.2, -16.5, 11.5, 10, 7.5, 11, 4.2, 4.5, 2.4, -4, 2.2, -16.5)
        g.setLineWidth(0.75)
        g.setColor(1, 0.72, 0.64, 0.82)
        g.line(-2.2, -15.5, -10.5, 9)
        g.line(2.2, -15.5, 10.5, 9)

    elseif kind == 2 then
        -- EQUILATERAL: BEAMCASTER (tuning-fork emitter rails + opaque gradient laser orb)
        if thrust > 0.05 then
            local len = (8 + 6 * thrust) * flicker
            for _, side in ipairs({ -1, 1 }) do
                local nx = side * 7.5
                g.setColor(1, 0.32, 0.54, 0.72 * thrust)
                g.polygon("fill", nx - 3.0, 11, nx, 11 + len, nx + 3.0, 11)
                g.setColor(1, 0.88, 0.95, 0.90 * thrust)
                g.polygon("fill", nx - 1.2, 11, nx, 11 + len * 0.55, nx + 1.2, 11)
            end
        end

        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[2].underframe)
            g.setLineWidth(0.9)
            g.setColor(0.26, 0.08, 0.15, 1)
            g.polygon("line", 0, -14, -16, 9, 16, 9)
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[2].orb)
            g.draw(meshes[2].leftRail)
            g.draw(meshes[2].leftRailIn)
            g.draw(meshes[2].rightRail)
            g.draw(meshes[2].rightRailIn)
            g.draw(meshes[2].leftWing)
            g.draw(meshes[2].rightWing)
            g.draw(meshes[2].bridge)
        else
            g.setColor(0.16, 0.05, 0.12, 1)
            g.polygon("fill", 0, -14, -16, 9, 16, 9)
            g.setLineWidth(0.9)
            g.setColor(0.26, 0.08, 0.15, 1)
            g.polygon("line", 0, -14, -16, 9, 16, 9)
            g.setColor(1, 0.23, 0.63, 1)
            g.circle("fill", 0, -10, 3.4)
            g.setColor(0.22, 0.085, 0.145, 1)
            g.polygon("fill", -4, -23.5, -9.5, -6, -8, 13, -4.5, 14)
            g.polygon("fill", -4, -23.5, -4.5, 14, -3.2, -13)
            g.setColor(0.36, 0.11, 0.18, 1)
            g.polygon("fill", 4, -23.5, 9.5, -6, 8, 13, 4.5, 14)
            g.polygon("fill", 4, -23.5, 4.5, 14, 3.2, -13)
            g.setColor(0.20, 0.08, 0.135, 1)
            g.polygon("fill", -11.5, -3, -21.5, 10.5, -17.5, 14, -10, 9.5)
            g.setColor(0.35, 0.11, 0.175, 1)
            g.polygon("fill", 11.5, -3, 21.5, 10.5, 17.5, 14, 10, 9.5)
            g.setColor(0.165, 0.05, 0.11, 1)
            g.polygon("fill", -4.5, 2, 4.5, 2, 3.5, 11, -3.5, 11)
        end

        g.setLineWidth(0.85)
        g.setColor(1, 0.84, 0.94, 1)
        g.circle("line", 0, -10, 3.4)
        g.setColor(1, 1, 1, 1)
        g.circle("fill", 0, -10, 1.5)
        g.setLineWidth(1.2)
        g.setColor(1, 0.55, 0.82, 0.92 * pulse)
        g.line(0, -21, 0, -13)

        -- Crisp crimson/coral outlines
        g.setLineWidth(1.1)
        if aimed then
            g.setColor(1, 0.62, 0.50, 1)
        else
            g.setColor(1, 0.27, 0.40, 1)
        end
        g.line(-4, -23.5, -9.5, -6, -8, 13, -4.5, 14, -3.2, -13, -4, -23.5)
        g.polygon("line", -11.5, -3, -21.5, 10.5, -17.5, 14, -10, 9.5)
        if aimed then
            g.setColor(1, 0.72, 0.62, 1)
        else
            g.setColor(1, 0.37, 0.50, 1)
        end
        g.line(4, -23.5, 9.5, -6, 8, 13, 4.5, 14, 3.2, -13, 4, -23.5)
        g.polygon("line", 11.5, -3, 21.5, 10.5, 17.5, 14, 10, 9.5)
        g.setLineWidth(0.85)
        g.setColor(1, 0.44, 0.72, 0.9)
        g.polygon("line", -4.5, 2, 4.5, 2, 3.5, 11, -3.5, 11)

    else
        -- OBTUSE: BULWARK-PRIME (obsidian + ceremonial gold command flying wing + opaque gradients)
        if thrust > 0.05 then
            local len = (9 + 6 * thrust) * flicker
            for _, spec in ipairs({ { -11, 9, 0.75 }, { 0, 11, 1.0 }, { 11, 9, 0.75 } }) do
                local nx, ny, s = spec[1], spec[2], spec[3]
                g.setColor(1, 0.72, 0.24, 0.72 * s * thrust)
                g.polygon("fill", nx - 3.6 * s, ny, nx, ny + len * s, nx + 3.6 * s, ny)
                g.setColor(1, 0.97, 0.85, 0.92 * s * thrust)
                g.polygon("fill", nx - 1.5 * s, ny, nx, ny + len * 0.55 * s, nx + 1.5 * s, ny)
            end
        end

        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[3].underframe)
            g.draw(meshes[3].leftWing)
            g.draw(meshes[3].rightWing)
        else
            g.setColor(0.18, 0.08, 0.08, 1)
            g.polygon("fill", 0, -13, -26, 8, 0, 13, 26, 8)
            g.setColor(0.24, 0.10, 0.145, 1)
            g.polygon("fill", -13, -7, -28.5, 6.5, -24, 12.5, -14, 9, -11, -1)
            g.setColor(0.36, 0.13, 0.18, 1)
            g.polygon("fill", 13, -7, 28.5, 6.5, 24, 12.5, 14, 9, 11, -1)
        end

        g.setLineWidth(1.2)
        g.setColor(1, aimed and 0.74 or 0.60, aimed and 0.42 or 0.24, 1)
        g.polygon("line", -13, -7, -28.5, 6.5, -24, 12.5, -14, 9, -11, -1)
        g.setColor(1, aimed and 0.82 or 0.72, aimed and 0.52 or 0.33, 1)
        g.polygon("line", 13, -7, 28.5, 6.5, 24, 12.5, 14, 9, 11, -1)

        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[3].citadel)
        else
            g.setColor(0.22, 0.095, 0.14, 1)
            g.polygon("fill", 0, -16, -11, -8, -9.5, 11.5, -3.5, 13.5, 3.5, 13.5, 9.5, 11.5, 11, -8)
        end
        g.setLineWidth(1.3)
        g.setColor(1, 0.82, 0.44, 1)
        g.polygon("line", 0, -16, -11, -8, -9.5, 11.5, -3.5, 13.5, 3.5, 13.5, 9.5, 11.5, 11, -8)

        -- Sculpted ceremonial gold brow chevron (opaque gradient)
        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[3].browLeft)
            g.draw(meshes[3].browRight)
        else
            g.setColor(0.86, 0.62, 0.22, 1)
            g.polygon("fill", 0, -15.5, -9, -8, -6.5, -4.5, 0, -9.5)
            g.setColor(1, 0.84, 0.44, 1)
            g.polygon("fill", 0, -15.5, 9, -8, 6.5, -4.5, 0, -9.5)
        end
        g.setLineWidth(0.7)
        g.setColor(1, 0.96, 0.80, 0.9)
        g.line(-9, -8, 0, -15.5, 9, -8)

        -- 6 recessed crimson missile bay blisters (3 per wing, opaque)
        local pods = {
            { -21.5, 5.2, -0.24 }, { -17.0, 3.2, -0.17 }, { -12.5, 1.7, -0.10 },
            { 12.5, 1.7, 0.10 }, { 17.0, 3.2, 0.17 }, { 21.5, 5.2, 0.24 },
        }
        g.setLineWidth(0.7)
        for _, pod in ipairs(pods) do
            g.push()
            g.translate(pod[1], pod[2])
            g.rotate(pod[3])
            g.setColor(0.95, 0.22, 0.24, 1)
            g.rectangle("fill", -1.5, -2.2, 3.0, 4.4, 0.7, 0.7)
            g.setColor(1, 0.84, 0.48, 0.95)
            g.rectangle("line", -1.5, -2.2, 3.0, 4.4, 0.7, 0.7)
            g.pop()
        end

        -- Burning solar-gold reactor core (opaque gradient)
        if meshes then
            g.setColor(1, 1, 1, 1)
            g.draw(meshes[3].core)
        else
            g.setColor(1, 0.83, 0.36, 1)
            g.polygon("fill", 0, -4.5, -4.2, 2, 0, 8, 4.2, 2)
        end
        g.setLineWidth(0.8)
        g.setColor(1, 1, 1, 1)
        g.polygon("line", 0, -4.5, -4.2, 2, 0, 8, 4.2, 2)
        g.circle("fill", 0, 2, 1.8)
    end
end

function Enemies:draw(time)
    local g = love.graphics
    g.push("all")
    for _, enemy in ipairs(self.items) do
        local thrust = 0
        if enemy.accelerating then
            thrust = 1
        elseif enemy.speed then
            local spd = enemy:speed()
            if spd > 18 then thrust = math.min(0.6, spd / math.max(1, enemy.maxSpeed or 200)) end
        end
        g.push()
        g.translate(enemy.x, enemy.y)
        g.rotate(enemy.angle)
        Enemies.drawHull(enemy.kind, enemy.aimed, time, { thrust = thrust })
        g.pop()
    end
    g.pop()
    self.fire:draw()
end

return Enemies
