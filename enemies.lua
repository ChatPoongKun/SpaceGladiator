local Ship = require("ship")
local Arena = require("arena")
local Enemies = {}
Enemies.__index = Enemies
local tau = 2 * math.pi
local goalIntervalMin, goalIntervalMax = 0.25, 1 / 3

Enemies.spawnRate = 1 / 4
Enemies.maxCount = 15
Enemies.patrolDuration = 10
Enemies.types = {
    {
        name = "WEDGE", vertices = {-2, -15, 2, -15, 10, 10, -10, 10},
        radius = 16, cruiseSpeed = 174, chargeSpeed = 205, evadeSpeed = 94,
        passOffset = 54, runout = 105, turnSpeed = 3.2, bankSpeed = 116,
        thrust = 285, maxSpeed = 225,
    },
    {
        name = "EQUILATERAL", vertices = {0, -24, -12 * math.sqrt(3), 12, 12 * math.sqrt(3), 12},
        radius = 24, cruiseSpeed = 123, chargeSpeed = 155, evadeSpeed = 78,
        turnSpeed = 2.8, thrust = 255, maxSpeed = 190,
    },
    {
        name = "OBTUSE", vertices = {0, -12, -26, 10, 26, 10},
        radius = 28, cruiseSpeed = 81, pursuitSpeed = 122, holdRange = 250,
        pressRange = 170, evadeSpeed = 62, turnSpeed = 1.4, thrust = 218, maxSpeed = 155,
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

function Enemies.new(rng)
    return setmetatable({
        items = {}, kills = 0, spawnAccumulator = 0.5, rng = rng or math.random,
        view = {left = 0, top = 0, right = Arena.width, bottom = Arena.height},
    }, Enemies)
end

local function beginDive(enemy, ship, definition, solo)
    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local baseSpeed = solo and definition.chargeSpeed or definition.cruiseSpeed
    local bearing = math.atan2(dx, -dy)
    local ux, uy = math.sin(bearing), -math.cos(bearing)
    local closingSpeed = baseSpeed + math.max(0, -ship.vx * ux - ship.vy * uy)
    local lead = clamp(dist / math.max(1, closingSpeed), 0, 1.4)
    local targetX, targetY = ship.x + ship.vx * lead, ship.y + ship.vy * lead
    local angle = math.atan2(targetX - enemy.x, enemy.y - targetY)
    local offset = enemy.slot * (solo and 45 or definition.passOffset)
    enemy.passX, enemy.passY = targetX + math.cos(angle) * offset, targetY + math.sin(angle) * offset
    enemy.courseAngle = math.atan2(enemy.passX - enemy.x, enemy.y - enemy.passY)
    enemy.courseX, enemy.courseY = math.sin(enemy.courseAngle), -math.cos(enemy.courseAngle)
    local vx, vy = ship.vx + ux * closingSpeed, ship.vy + uy * closingSpeed
    enemy.legSpeed = clamp(math.sqrt(vx * vx + vy * vy), baseSpeed, enemy.maxSpeed)
    enemy.state = "dive"
    enemy.bankProgress = nil
    enemy.goal = nil
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
    enemy.maxSpeed, enemy.thrust, enemy.turnSpeed = definition.maxSpeed, definition.thrust, definition.turnSpeed
    -- Give lighter thrust the same time to build momentum out of low-speed drag.
    local thrustRatio = enemy.thrust / Ship.thrust
    enemy.driftThreshold = Ship.driftThreshold * thrustRatio
    enemy.driftDeceleration = Ship.driftDeceleration * thrustRatio
    enemy.vx, enemy.vy = limitVector(options and options.vx or 0, options and options.vy or 0, enemy.maxSpeed)
    enemy.prevX, enemy.prevY = enemy.x, enemy.y
    enemy.angle = (options and options.angle or math.atan2(ship.x - enemy.x, enemy.y - ship.y)) % tau
    enemy.leader = options and options.leader or nil
    enemy.slot = options and options.slot or (self.rng() < 0.5 and -1 or 1)
    enemy.evadeTime, enemy.evadeCooldown = 0, 0
    enemy.goalDelay = 0
    enemy.sepX, enemy.sepY = 0, 0
    enemy.aimed, enemy.blindside = false, false
    local entryTime = options and options.entryTime
    enemy.phase = entryTime and "entering" or "patrol"
    enemy.phaseRemaining = entryTime or self.patrolDuration

    if kind == 3 then
        enemy.role = "leader"
        enemy.diveTimer = 1.4
        enemy.diveSignal = 0
        enemy.wings = {}
    elseif kind == 2 then
        enemy.role = "escort"
    else
        enemy.role = "flanker"
        enemy.runout = definition.runout
        enemy.lastDiveSignal = enemy.leader and enemy.leader.diveSignal or 0
        if enemy.leader then
            enemy.state = "form"
        else
            beginDive(enemy, ship, definition, true)
        end
    end
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
    local rx, ry = -fy, fx
    local vx, vy = fx * entrySpeed, fy * entrySpeed
    local entryTime = (entryMargin + wingTrail + self.types[3].radius) / entrySpeed
    local squad = {}
    local leader = self:spawn(ship, 3, {
        x = lx, y = ly, vx = vx, vy = vy, angle = angle, entryTime = entryTime,
    })
    if not leader then return squad end
    squad[#squad + 1] = leader

    for _, member in ipairs(formation) do
        local shipMember = self:spawn(ship, member.kind, {
            x = lx + rx * member.right + fx * member.forward,
            y = ly + ry * member.right + fy * member.forward,
            vx = vx, vy = vy, angle = angle, entryTime = entryTime,
            leader = leader, slot = member.slot,
        })
        squad[#squad + 1] = shipMember
        if member.kind == 1 then leader.wings[#leader.wings + 1] = shipMember end
    end
    return squad
end

local function aimEvasion(enemy, ship, aimAngle, step)
    enemy.evadeTime = math.max(0, enemy.evadeTime - step)
    enemy.evadeCooldown = math.max(0, enemy.evadeCooldown - step)
    enemy.blindside = false
    if aimAngle then
        local aimX, aimY = math.sin(aimAngle), -math.cos(aimAngle)
        local dx, dy = enemy.x - ship.x, enemy.y - ship.y
        local along = dx * aimX + dy * aimY
        local across = dy * aimX - dx * aimY
        enemy.blindside = along < 0 or math.abs(across) > along * 0.7
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

local function reassignEscort(items, escort)
    local bestLeader, bestSlot, bestDistSq = nil, nil, 1400 * 1400
    for _, candidate in ipairs(items) do
        if candidate.role == "leader" and not candidate.dead and candidate.phase ~= "departing" then
            local leftTaken, rightTaken = false, false
            for _, other in ipairs(items) do
                if other ~= escort and other.role == "escort" and other.leader == candidate
                    and not other.dead and other.phase ~= "departing" then
                    if other.slot < 0 then leftTaken = true else rightTaken = true end
                end
            end
            if not (leftTaken and rightTaken) then
                local dx, dy = candidate.x - escort.x, candidate.y - escort.y
                local distSq = dx * dx + dy * dy
                if distSq < bestDistSq then
                    bestDistSq = distSq
                    bestLeader = candidate
                    bestSlot = not leftTaken and -1 or 1
                end
            end
        end
    end
    escort.leader = bestLeader
    if bestLeader then escort.slot = bestSlot end
end

local function wingPosition(leader, slot)
    local fx, fy = math.sin(leader.angle), -math.cos(leader.angle)
    local spread = slot * wingSpread
    return leader.x - fy * spread - fx * wingTrail, leader.y + fx * spread - fy * wingTrail
end

local function wingsReady(leader)
    local hasWing = false
    for _, wing in ipairs(leader.wings) do
        if not wing.dead and wing.phase ~= "departing" then
            local x, y = wingPosition(leader, wing.slot)
            if wing.phase ~= "patrol" or wing.state ~= "form"
                or (wing.x - x) ^ 2 + (wing.y - y) ^ 2 > 72 ^ 2 then return false end
            hasWing = true
        end
    end
    return hasWing
end

local function pointGoal(x, y, reference, angle, response, speed)
    return {x = x, y = y, vx = reference.vx, vy = reference.vy, angle = angle, response = response, speed = speed}
end

local function chooseGoal(enemy, ship, definition, playerSlow, playerFast)
    local leader = enemy.leader
    if enemy.state == "form" then
        local x, y = wingPosition(leader, enemy.slot)
        return pointGoal(x, y, leader, leader.angle, 2.5, definition.cruiseSpeed)
    elseif enemy.role == "escort" and leader then
        local fx, fy = math.sin(leader.angle), -math.cos(leader.angle)
        local rx, ry = -fy, fx
        local forward = (playerSlow or enemy.blindside) and 26 or -escortTrail
        local spread = enemy.slot * escortSpread
        local slotX = leader.x + rx * spread + fx * forward
        local slotY = leader.y + ry * spread + fy * forward
        local maxRel = definition.cruiseSpeed + (playerFast and 41 or 0) + (enemy.blindside and 19 or 0)
        return pointGoal(slotX, slotY, leader, leader.angle, 2.4, maxRel)
    end

    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local angle = math.atan2(dx, -dy)
    local fleeing = playerFast and dx * ship.vx + dy * ship.vy > 0
    local range, response, speed
    if enemy.role == "leader" then
        if enemy.diveTimer <= 0 and dist <= 475 and wingsReady(enemy) then
            enemy.diveSignal = enemy.diveSignal + 1
            enemy.diveTimer = 3.2
        end
        range = playerSlow and definition.pressRange or definition.holdRange
        if enemy.blindside then range = range - 30 end
        if fleeing and dist > range + 45 then
            return pointGoal(ship.x, ship.y, ship, angle, 1.4,
                definition.pursuitSpeed + (enemy.blindside and 20 or 0))
        end
        response, speed = 1.4, definition.cruiseSpeed + (enemy.blindside and 21 or 0)
    elseif enemy.role == "escort" then
        range = playerSlow and 80 or 120
        response, speed = 2.5, definition.chargeSpeed + (enemy.blindside and 26 or 0)
    else
        if fleeing and dist > 350 then
            enemy.state = "pursuit"
            return pointGoal(ship.x, ship.y, ship, angle, 2.5,
                definition.chargeSpeed + (enemy.blindside and 20 or 0))
        elseif enemy.state == "pursuit" then
            beginDive(enemy, ship, definition, not leader)
        end
        return nil
    end

    local ux, uy = dist > 1e-6 and dx / dist or 0, dist > 1e-6 and dy / dist or -1
    return pointGoal(ship.x - ux * range, ship.y - uy * range, ship, angle, response, dist < range and 71 or speed)
end

local function flankerSteering(enemy, ship, definition, step, playerSlow)
    if enemy.state == "recover" then
        enemy.bankProgress = math.min(math.pi * 0.85, enemy.bankProgress + enemy.turnSpeed * 0.7 * step)
        local angle = enemy.courseAngle - enemy.slot * enemy.bankProgress
        if enemy.bankProgress >= math.pi * 0.85 then
            enemy.bankProgress = nil
            if enemy.leader then
                enemy.state = "form"
                enemy.lastDiveSignal = enemy.leader.diveSignal
                enemy.goalDelay = 0
            else
                beginDive(enemy, ship, definition, true)
            end
        end
        local speed = definition.bankSpeed
        local vx = ship.vx * 0.4 + math.sin(angle) * speed
        local vy = ship.vy * 0.4 - math.cos(angle) * speed
        return vx, vy, math.atan2(vx, -vy)
    end

    -- "dive": high-speed pincer run along the locked line, dodging if aimed at.
    local px, py = enemy.passX - enemy.x, enemy.passY - enemy.y
    local courseX, courseY = enemy.courseX, enemy.courseY
    if px * courseX + py * courseY <= -enemy.runout then
        enemy.state = "recover"
        enemy.bankProgress = 0
        local angle = enemy.courseAngle
        return math.sin(angle) * definition.bankSpeed, -math.cos(angle) * definition.bankSpeed, angle
    end
    local side = py * courseX - px * courseY
    local correction = clamp(side * 2, -enemy.legSpeed * 0.6, enemy.legSpeed * 0.6)
    local boost = (enemy.blindside or playerSlow) and 1.12 or 1.0
    local vx = courseX * enemy.legSpeed * boost - courseY * correction
    local vy = courseY * enemy.legSpeed * boost + courseX * correction
    return vx, vy, math.atan2(vx, -vy)
end

local function pilot(enemy, dt, targetVx, targetVy, angle)
    local targetSpeed = math.sqrt(targetVx * targetVx + targetVy * targetVy)
    local speed = enemy:speed()
    local brake = speed > targetSpeed + 6
    local thrust = false
    if targetSpeed > 9 then
        local forwardSpeed = (enemy.vx * targetVx + enemy.vy * targetVy) / targetSpeed
        brake = brake or (speed > 18 and forwardSpeed < speed * 0.35)
        if brake then
            angle = math.atan2(targetVx, -targetVy)
        else
            -- Point into the turn to correct sideways drift with forward thrust.
            angle = math.atan2(targetVx - enemy.vx * 0.65, enemy.vy * 0.65 - targetVy)
            thrust = forwardSpeed < targetSpeed - 4
        end
    end

    local error = (angle - enemy.angle + math.pi) % tau - math.pi
    enemy:turn(dt, clamp(error / (enemy.turnSpeed * dt), -1, 1))
    local oldVx, oldVy = enemy:updateVelocity(dt, thrust and math.abs(error) < 0.6, brake, enemy.maxSpeed)
    enemy.x = enemy.x + (oldVx + enemy.vx) * 0.5 * dt
    enemy.y = enemy.y + (oldVy + enemy.vy) * 0.5 * dt
end

local function patrol(enemy, step, ship, aimAngle, definition, playerSlow, playerFast, rng)
    local evadeX, evadeY = aimEvasion(enemy, ship, aimAngle, step)
    if enemy.role == "leader" then
        enemy.diveTimer = enemy.diveTimer - step * (playerSlow and 2 or 1)
    end
    if enemy.state == "form" and enemy.lastDiveSignal ~= enemy.leader.diveSignal then
        enemy.lastDiveSignal = enemy.leader.diveSignal
        beginDive(enemy, ship, definition, false)
    elseif enemy.goalDelay <= 1e-9 then
        enemy.goal = chooseGoal(enemy, ship, definition, playerSlow, playerFast)
        enemy.goalDelay = enemy.goalDelay + goalIntervalMin + rng() * (goalIntervalMax - goalIntervalMin)
    end
    enemy.goalDelay = enemy.goalDelay - step

    local targetVx, targetVy, angle
    local goal = enemy.goal
    if goal then
        local vx, vy = limitVector((goal.x - enemy.x) * goal.response, (goal.y - enemy.y) * goal.response, goal.speed)
        targetVx, targetVy, angle = goal.vx + vx, goal.vy + vy, goal.angle
    else
        targetVx, targetVy, angle = flankerSteering(enemy, ship, definition, step, playerSlow)
    end
    targetVx, targetVy = limitVector(targetVx + enemy.sepX + evadeX * definition.evadeSpeed,
        targetVy + enemy.sepY + evadeY * definition.evadeSpeed, enemy.maxSpeed)
    pilot(enemy, step, targetVx, targetVy, angle)
end

local function departureAngle(enemy, view)
    local distances = {enemy.x - view.left, view.right - enemy.x, enemy.y - view.top, view.bottom - enemy.y}
    local bestCost, bestAngle = math.huge, 0
    for edge, angle in ipairs(departureAngles) do
        local turn = math.abs((angle - enemy.angle + math.pi) % tau - math.pi)
        local cost = distances[edge] + turn * enemy.maxSpeed / enemy.turnSpeed
        if cost < bestCost then bestCost, bestAngle = cost, angle end
    end
    return bestAngle
end

local function outsideView(enemy, view)
    local radius = enemy.radius + 2
    return enemy.x + radius < view.left or enemy.x - radius > view.right
        or enemy.y + radius < view.top or enemy.y - radius > view.bottom
end

local function move(group, enemy, dt, ship, aimAngle)
    local definition = group.types[enemy.kind]
    local playerSpeed = ship:speed()
    local playerSlow = ship.braking or playerSpeed < ship.maxSpeed * 0.5
    local playerFast = playerSpeed > ship.maxSpeed * 0.8
    while dt > 0 do
        if enemy.phase == "departing" and outsideView(enemy, group.view) then return true end
        local step = math.min(dt, 1 / 60)
        if enemy.phase ~= "departing" then step = math.min(step, enemy.phaseRemaining) end

        if step > 0 then
            if enemy.phase == "patrol" then
                patrol(enemy, step, ship, aimAngle, definition, playerSlow, playerFast, group.rng)
            else
                local angle = enemy.exitAngle or enemy.angle
                local speed = enemy.phase == "entering" and entrySpeed or enemy.maxSpeed
                pilot(enemy, step, math.sin(angle) * speed, -math.cos(angle) * speed, angle)
            end
        end

        if enemy.phase ~= "departing" then
            enemy.phaseRemaining = enemy.phaseRemaining - step
            if enemy.phaseRemaining <= 1e-9 then
                if enemy.phase == "entering" then
                    enemy.phase, enemy.phaseRemaining = "patrol", group.patrolDuration
                else
                    enemy.phase, enemy.exitAngle = "departing", departureAngle(enemy, group.view)
                    enemy.goal, enemy.aimed = nil, false
                end
            end
        end
        dt = dt - step
    end
    return enemy.phase == "departing" and outsideView(enemy, group.view)
end

local function advance(group, first, dt, ship, aimAngle)
    -- Both wings see the same dive signal before the leader advances.
    for i = #group.items, first, -1 do
        local enemy = group.items[i]
        enemy.prevX, enemy.prevY = enemy.x, enemy.y
        if move(group, enemy, dt, ship, aimAngle) then
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
    computeSeparation(self.items)
    for _, enemy in ipairs(self.items) do
        local leader = enemy.leader
        if enemy.phase ~= "departing" and leader and (leader.dead or leader.phase == "departing") then
            if enemy.role == "escort" then
                reassignEscort(self.items, enemy)
                enemy.goalDelay = 0
            else
                enemy.leader = nil
                beginDive(enemy, ship, self.types[enemy.kind], true)
            end
        end
    end
    advance(self, 1, dt, ship, aimAngle)

    if #self.items + squadSize > self.maxCount then
        self.spawnAccumulator = 0
        return
    end
    self.spawnAccumulator = self.spawnAccumulator + dt * self.spawnRate
    local count = math.floor(self.spawnAccumulator + 1e-9)
    self.spawnAccumulator = math.max(0, self.spawnAccumulator - count)
    for i = 1, count do
        if #self.items + squadSize > self.maxCount then break end
        local first = #self.items + 1
        self:spawnSquad(ship)
        local slice = (count - i + self.spawnAccumulator) / self.spawnRate
        -- A new arrival moves only for the portion of the frame after its birth.
        advance(self, first, slice, ship, aimAngle)
    end
end

local function positionAt(enemy, fraction)
    local x, y = enemy.prevX or enemy.x, enemy.prevY or enemy.y
    return x + (enemy.x - x) * fraction, y + (enemy.y - y) * fraction
end

function Enemies:destroy(index)
    local enemy = self.items[index]
    if enemy then enemy.dead = true end
    table.remove(self.items, index)
    self.kills = self.kills + 1
end

function Enemies:hitArea(x, y, radius, fraction)
    for i = #self.items, 1, -1 do
        local enemy = self.items[i]
        local ex, ey = positionAt(enemy, fraction)
        if (ex - x) ^ 2 + (ey - y) ^ 2 <= (radius + enemy.radius) ^ 2 then
            self:destroy(i)
        end
    end
end

function Enemies:hitSegment(x1, y1, x2, y2, startFraction, endFraction)
    startFraction, endFraction = startFraction or 0, endFraction or 1
    local dx, dy = x2 - x1, y2 - y1
    local nearest, hitIndex = math.huge, nil
    for i, enemy in ipairs(self.items) do
        local startX, startY = positionAt(enemy, startFraction)
        local endX, endY = positionAt(enemy, endFraction)
        local rx, ry = x1 - startX, y1 - startY
        local vx, vy = dx - (endX - startX), dy - (endY - startY)
        local radius = enemy.radius + 2
        local c = rx * rx + ry * ry - radius * radius
        local t
        if c <= 0 then
            t = 0
        else
            local a, b = vx * vx + vy * vy, rx * vx + ry * vy
            local discriminant = b * b - a * c
            if a > 0 and b < 0 and discriminant >= 0 then
                -- Stable form of the entry root avoids cancellation near the hull.
                t = c / (-b + math.sqrt(discriminant))
                if t > 1 then t = nil end
            end
        end
        if t and t < nearest then nearest, hitIndex = t, i end
    end
    if hitIndex then
        self:destroy(hitIndex)
        return x1 + dx * nearest, y1 + dy * nearest, nearest
    end
end

function Enemies:draw(time)
    local g = love.graphics
    g.push("all")
    g.setLineWidth(1.5)
    for _, enemy in ipairs(self.items) do
        local vertices = self.types[enemy.kind].vertices
        local charging = (enemy.role == "flanker" and (enemy.state == "dive" or enemy.state == "pursuit"))
            or (enemy.role == "escort" and not enemy.leader)
        g.push()
        g.translate(enemy.x, enemy.y)
        g.rotate(enemy.angle)
        if charging then
            g.setColor(0.86, 0.14, 0.10, 1)
        else
            g.setColor(0.72, 0.06, 0.09, 1)
        end
        g.polygon("fill", vertices)
        if enemy.role == "leader" then
            g.setColor(1, 0.68, 0.24, 1)
        elseif enemy.aimed then
            g.setColor(1, 0.56, 0.42, 1)
        elseif charging then
            g.setColor(1, 0.44, 0.20, 1)
        else
            g.setColor(1, 0.24, 0.25, 1)
        end
        g.polygon("line", vertices)
        if enemy.role == "leader" then
            g.setColor(1, 0.80, 0.34, 0.9)
            g.polygon("fill", 0, -5, -5, 4, 5, 4)
        end
        g.pop()
    end
    g.pop()
end

return Enemies
