local Ship = require("ship")
local Arena = require("arena")
local Enemies = {}
Enemies.__index = Enemies
local tau = 2 * math.pi
local patrolRadiusMin, patrolRadiusMax = 195, 290
local arrivalRadius, minimumLeg, formationMargin = 48, 185, 155

Enemies.spawnRate = 1 / 4
Enemies.maxCount = 15
Enemies.patrolDuration = 10
Enemies.types = {
    {
        name = "WEDGE", vertices = {-2, -15, 2, -15, 10, 10, -10, 10},
        radius = 16, evadeSpeed = 94, turnSpeed = 3.2,
        thrust = 285, maxSpeed = 225,
    },
    {
        name = "EQUILATERAL", vertices = {0, -24, -12 * math.sqrt(3), 12, 12 * math.sqrt(3), 12},
        radius = 24, evadeSpeed = 78,
        turnSpeed = 2.8, thrust = 255, maxSpeed = 190,
    },
    {
        name = "OBTUSE", vertices = {0, -12, -26, 10, 26, 10},
        radius = 28, evadeSpeed = 62, turnSpeed = 1.4, thrust = 218, maxSpeed = 155,
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
    enemy.maxSpeed, enemy.thrust, enemy.turnSpeed = definition.maxSpeed, definition.thrust, definition.turnSpeed
    -- Give lighter thrust the same time to build momentum out of low-speed drag.
    local thrustRatio = enemy.thrust / Ship.thrust
    enemy.driftThreshold = Ship.driftThreshold * thrustRatio
    enemy.driftDeceleration = Ship.driftDeceleration * thrustRatio
    enemy.vx, enemy.vy = limitVector(options and options.vx or 0, options and options.vy or 0, enemy.maxSpeed)
    enemy.prevX, enemy.prevY = enemy.x, enemy.y
    enemy.angle = (options and options.angle or math.atan2(ship.x - enemy.x, enemy.y - ship.y)) % tau
    enemy.route = options and options.route or {waypoints = {}}
    enemy.waypointIndex = 1
    enemy.right = options and options.right or 0
    enemy.forward = options and options.forward or 0
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
    local route = {waypoints = {}}
    local leader = self:spawn(ship, 3, {
        x = lx, y = ly, vx = vx, vy = vy, angle = angle, entryTime = entryTime, route = route,
    })
    route.leader = leader
    local squad = {leader}

    for _, member in ipairs(formation) do
        local x, y = formationPosition(lx, ly, angle, member.right, member.forward)
        local shipMember = self:spawn(ship, member.kind, {
            x = x, y = y, vx = vx, vy = vy, angle = angle, entryTime = entryTime, route = route,
            slot = member.slot, right = member.right, forward = member.forward,
        })
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

local function pilot(enemy, dt, targetVx, targetVy, angle, flyThrough)
    local targetSpeed = math.sqrt(targetVx * targetVx + targetVy * targetVy)
    local speed = enemy:speed()
    local brake = not flyThrough and speed > targetSpeed + 6
    local thrust = false
    if targetSpeed > 9 then
        local forwardSpeed = (enemy.vx * targetVx + enemy.vy * targetVy) / targetSpeed
        brake = brake or (not flyThrough and speed > 18 and forwardSpeed < speed * 0.35)
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

local function flyTo(enemy, dt, x, y, speed, steerX, steerY, flyThrough)
    local dx, dy = x - enemy.x, y - enemy.y
    local response = flyThrough and speed / math.max(math.sqrt(dx * dx + dy * dy), 1) or 2.6
    local vx, vy = limitVector(dx * response, dy * response, speed)
    vx, vy = limitVector(vx + steerX, vy + steerY, speed)
    pilot(enemy, dt, vx, vy, math.atan2(dx, -dy), flyThrough)
end

local function addWaypoint(group, enemy, ship)
    local route, view = enemy.route, group.view
    local previous = route.waypoints[#route.waypoints]
    local reference = previous or route.leader or enemy
    local angle = group.rng() * tau
    if not previous then
        -- Bias the first approach toward the side the formation entered from.
        angle = math.atan2(reference.y - ship.y, reference.x - ship.x) + (angle - math.pi) * 0.45
    end
    local radius = patrolRadiusMin + group.rng() * (patrolRadiusMax - patrolRadiusMin)
    local x, y, bestDistance
    for attempt = 0, 11 do
        local bearing = angle + attempt * tau / 12
        local px, py = ship.x + math.cos(bearing) * radius, ship.y + math.sin(bearing) * radius
        if px >= view.left + formationMargin and px <= view.right - formationMargin
            and py >= view.top + formationMargin and py <= view.bottom - formationMargin then
            local distance = (px - reference.x) ^ 2 + (py - reference.y) ^ 2
            if not bestDistance or distance > bestDistance then x, y, bestDistance = px, py, distance end
            if not previous or distance >= minimumLeg ^ 2 then break end
        end
    end
    if not bestDistance then
        local inward = math.atan2(Arena.height / 2 - ship.y, Arena.width / 2 - ship.x)
        x, y = ship.x + math.cos(inward) * radius, ship.y + math.sin(inward) * radius
    end
    local point = {x = x, y = y, angle = math.atan2(x - reference.x, reference.y - y)}
    route.waypoints[#route.waypoints + 1] = point
    return point
end

local function assignWaypoint(group, enemy, ship)
    -- Each aircraft has its own cursor through the OBTUSE centerline.
    local point = enemy.route.waypoints[enemy.waypointIndex] or addWaypoint(group, enemy, ship)
    local x, y = formationPosition(point.x, point.y, point.angle, enemy.right, enemy.forward)
    enemy.goal = {x = x, y = y}
end

local function patrol(group, enemy, dt, ship, aimAngle, definition)
    if not enemy.goal then assignWaypoint(group, enemy, ship) end
    if (enemy.goal.x - enemy.x) ^ 2 + (enemy.goal.y - enemy.y) ^ 2 <= arrivalRadius ^ 2 then
        enemy.waypointIndex = enemy.waypointIndex + 1
        assignWaypoint(group, enemy, ship)
    end

    local evadeX, evadeY = aimEvasion(enemy, ship, aimAngle, dt)
    flyTo(enemy, dt, enemy.goal.x, enemy.goal.y, enemy.maxSpeed * 0.84,
        enemy.sepX + evadeX * definition.evadeSpeed, enemy.sepY + evadeY * definition.evadeSpeed, true)
end

local function departureGoal(enemy, view)
    local route = enemy.route
    if not route.exit then
        local leader = route.leader
        local reference = leader and not leader.dead and leader or enemy
        local distances = {reference.x - view.left, view.right - reference.x,
            reference.y - view.top, view.bottom - reference.y}
        local bestCost, bestEdge = math.huge, 1
        for edge, angle in ipairs(departureAngles) do
            local turn = math.abs((angle - reference.angle + math.pi) % tau - math.pi)
            local cost = distances[edge] + turn * reference.maxSpeed / reference.turnSpeed
            if cost < bestCost then bestCost, bestEdge = cost, edge end
        end
        route.exit = {
            edge = bestEdge,
            x = clamp(reference.x, view.left, view.right),
            y = clamp(reference.y, view.top, view.bottom),
        }
    end

    -- If the viewport expands, extend the same exit so all ships can still clear it.
    local exit = route.exit
    if exit.edge == 1 then exit.x = math.min(exit.x, view.left - formationMargin)
    elseif exit.edge == 2 then exit.x = math.max(exit.x, view.right + formationMargin)
    elseif exit.edge == 3 then exit.y = math.min(exit.y, view.top - formationMargin)
    else exit.y = math.max(exit.y, view.bottom + formationMargin) end
    return exit
end

local function clearedExit(enemy, view, edge)
    local radius = enemy.radius + 2
    if edge == 1 then return enemy.x + radius < view.left end
    if edge == 2 then return enemy.x - radius > view.right end
    if edge == 3 then return enemy.y + radius < view.top end
    return enemy.y - radius > view.bottom
end

local function move(group, enemy, dt, ship, aimAngle)
    local definition = group.types[enemy.kind]
    local view = group.view
    while dt > 0 do
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
        dt = dt - step
    end
    return enemy.phase == "departing" and clearedExit(enemy, view, enemy.route.exit.edge)
end

local function advance(group, first, dt, ship, aimAngle)
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
        g.push()
        g.translate(enemy.x, enemy.y)
        g.rotate(enemy.angle)
        g.setColor(0.72, 0.06, 0.09, 1)
        g.polygon("fill", vertices)
        if enemy.kind == 3 then
            g.setColor(1, 0.68, 0.24, 1)
        elseif enemy.aimed then
            g.setColor(1, 0.56, 0.42, 1)
        else
            g.setColor(1, 0.24, 0.25, 1)
        end
        g.polygon("line", vertices)
        if enemy.kind == 3 then
            g.setColor(1, 0.80, 0.34, 0.9)
            g.polygon("fill", 0, -5, -5, 4, 5, 4)
        end
        g.pop()
    end
    g.pop()
end

return Enemies
