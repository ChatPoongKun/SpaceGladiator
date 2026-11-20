local Ship = require("ship")
local Enemies = {}
Enemies.__index = Enemies
local tau = 2 * math.pi

Enemies.spawnRate = 1 / 4
Enemies.maxCount = 15
Enemies.types = {
    {
        name = "WEDGE", vertices = {-2, -15, 2, -15, 10, 10, -10, 10},
        radius = 16, cruiseSpeed = 540, chargeSpeed = 620, evadeSpeed = 320,
        passOffset = 75, runout = 260, turnSpeed = 3.2, bankSpeed = 340,
        thrust = 520, maxSpeed = 1350,
    },
    {
        name = "EQUILATERAL", vertices = {0, -24, -12 * math.sqrt(3), 12, 12 * math.sqrt(3), 12},
        radius = 24, cruiseSpeed = 360, chargeSpeed = 470, evadeSpeed = 250,
        turnSpeed = 2.8, thrust = 440, maxSpeed = 1250,
    },
    {
        name = "OBTUSE", vertices = {0, -12, -26, 10, 26, 10},
        radius = 28, cruiseSpeed = 230, pursuitSpeed = 340, holdRange = 315,
        pressRange = 230, evadeSpeed = 185, turnSpeed = 1.4, thrust = 350, maxSpeed = 1150,
    },
}

local wingSpread, wingTrail = 165, 85
local formation = {
    { kind = 2, slot = -1, right = -115, forward = -45 },
    { kind = 2, slot = 1, right = 115, forward = -45 },
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
    enemy.passX = targetX + math.cos(angle) * offset
    enemy.passY = targetY + math.sin(angle) * offset
    enemy.courseAngle = math.atan2(enemy.passX - enemy.x, enemy.y - enemy.passY)
    enemy.courseX, enemy.courseY = math.sin(enemy.courseAngle), -math.cos(enemy.courseAngle)
    local vx, vy = ship.vx + ux * closingSpeed, ship.vy + uy * closingSpeed
    enemy.legSpeed = clamp(math.sqrt(vx * vx + vy * vy), baseSpeed, enemy.maxSpeed)
    enemy.state = "dive"
    enemy.bankProgress = nil
end

local function spawnPointOutside(rng, camera, width, height, margin, span)
    local edge = math.min(4, 1 + math.floor(rng() * 4))
    local t = span and (0.2 + rng() * 0.6) or rng()
    local x, y = t * width, t * height
    if edge == 1 then x = -margin
    elseif edge == 2 then x = width + margin
    elseif edge == 3 then y = -margin
    else y = height + margin end
    return camera:screenToWorld(x, y, width, height)
end

function Enemies:spawn(ship, camera, width, height, kindIndex, options)
    if #self.items >= self.maxCount then return nil end
    local kind = kindIndex or math.min(#self.types, 1 + math.floor(self.rng() * #self.types))
    local definition = self.types[kind]
    local enemy = Ship.new(width, height)
    if options and options.x and options.y then
        enemy.x, enemy.y = options.x, options.y
    else
        -- The entire bounding circle is at least 60 screen pixels outside the view.
        local margin = 60 + definition.radius * camera.zoom
        enemy.x, enemy.y = spawnPointOutside(self.rng, camera, width, height, margin, false)
    end
    enemy.prevX, enemy.prevY = enemy.x, enemy.y
    enemy.vx = options and options.vx or ship.vx
    enemy.vy = options and options.vy or ship.vy
    enemy.angle = (options and options.angle or math.atan2(ship.x - enemy.x, enemy.y - ship.y)) % tau
    enemy.kind, enemy.radius = kind, definition.radius
    enemy.maxSpeed = definition.maxSpeed or 1300
    enemy.thrustLimit = definition.thrust or Ship.thrust
    enemy.turnSpeed = definition.turnSpeed or Ship.turnSpeed
    enemy.leader = options and options.leader or nil
    enemy.slot = options and options.slot or (self.rng() < 0.5 and -1 or 1)
    enemy.evadeTime, enemy.evadeCooldown = 0, 0
    enemy.sepX, enemy.sepY = 0, 0
    enemy.aimed, enemy.blindside = false, false

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

function Enemies:spawnSquad(ship, camera, width, height)
    if #self.items + squadSize > self.maxCount then return {} end
    -- Place the leader far enough outside that all 5 formation hulls spawn off-screen.
    local margin = 60 + 210 * camera.zoom
    local lx, ly = spawnPointOutside(self.rng, camera, width, height, margin, true)
    local angle = math.atan2(ship.x - lx, ly - ship.y) % tau
    local fx, fy = math.sin(angle), -math.cos(angle)
    local rx, ry = -fy, fx
    local vx, vy = limitVector(ship.vx + fx * 160, ship.vy + fy * 160, self.types[3].maxSpeed)
    local squad = {}
    local leader = self:spawn(ship, camera, width, height, 3, {
        x = lx, y = ly, vx = vx, vy = vy, angle = angle,
    })
    if not leader then return squad end
    squad[#squad + 1] = leader

    for _, member in ipairs(formation) do
        local shipMember = self:spawn(ship, camera, width, height, member.kind, {
            x = lx + rx * member.right + fx * member.forward,
            y = ly + ry * member.right + fy * member.forward,
            vx = vx, vy = vy, angle = angle,
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
        if enemy.evadeCooldown == 0 and along > 0 and along < 950 and math.abs(across) < 65 + enemy.radius then
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
        if candidate.role == "leader" and not candidate.dead then
            local leftTaken, rightTaken = false, false
            for _, other in ipairs(items) do
                if other ~= escort and other.role == "escort" and other.leader == candidate and not other.dead then
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
        if not wing.dead then
            local x, y = wingPosition(leader, wing.slot)
            if wing.state ~= "form" or (wing.x - x) ^ 2 + (wing.y - y) ^ 2 > 95 ^ 2 then return false end
            hasWing = true
        end
    end
    return hasWing
end

local function leaderSteering(enemy, ship, definition, step, playerSlow, playerFast, visible)
    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dist > 1e-6 and dx / dist or 0, dist > 1e-6 and dy / dist or -1
    local angle = math.atan2(dx, -dy)

    -- Coordinate simultaneous flanker dives when the squad reaches attack range.
    enemy.diveTimer = enemy.diveTimer - step * (playerSlow and 2.0 or 1.0)
    if enemy.diveTimer <= 0 and visible and dist <= 620 and wingsReady(enemy) then
        enemy.diveSignal = enemy.diveSignal + 1
        enemy.diveTimer = 3.2
    end

    local desiredRange = (playerSlow or not visible) and definition.pressRange or definition.holdRange
    if enemy.blindside then desiredRange = math.max(180, desiredRange - 50) end
    local fleeing = playerFast and dist > desiredRange + 45 and dx * ship.vx + dy * ship.vy > 0
    if fleeing then
        local speed = definition.pursuitSpeed + (enemy.blindside and 60 or 0)
        return ship.vx + ux * speed, ship.vy + uy * speed, angle
    end
    local approach = definition.cruiseSpeed + (enemy.blindside and 65 or 0)
    local radial = clamp((dist - desiredRange) * 1.4, -140, approach)
    return ship.vx + ux * radial, ship.vy + uy * radial, angle
end

local function escortSteering(enemy, ship, definition, playerSlow, playerFast)
    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dist > 1e-6 and dx / dist or 0, dist > 1e-6 and dy / dist or -1
    local angle = math.atan2(dx, -dy)
    local leader = enemy.leader

    local vx, vy
    if leader and not leader.dead then
        local fx, fy = math.sin(leader.angle), -math.cos(leader.angle)
        local rx, ry = -fy, fx
        local forward = (playerSlow or enemy.blindside) and 35 or -45
        local slotX = leader.x + rx * (enemy.slot * 115) + fx * forward
        local slotY = leader.y + ry * (enemy.slot * 115) + fy * forward
        local maxRel = definition.cruiseSpeed + (playerFast and 140 or 0) + (enemy.blindside and 60 or 0)
        local relX, relY = limitVector((slotX - enemy.x) * 2.4, (slotY - enemy.y) * 2.4, maxRel)
        vx, vy = leader.vx + relX, leader.vy + relY
        angle = leader.angle
    else
        -- Without a leader to regroup with, charge aggressively at the player.
        local charge = definition.chargeSpeed + (enemy.blindside and 80 or 0)
        local desired = playerSlow and 110 or 160
        local radial = clamp((dist - desired) * 2.5, -140, charge)
        vx, vy = ship.vx + ux * radial, ship.vy + uy * radial
    end
    return vx, vy, angle
end

local function flankerSteering(enemy, ship, definition, step, playerSlow, playerFast)
    local leader = enemy.leader
    local leaderAlive = leader and not leader.dead
    local dx, dy = ship.x - enemy.x, ship.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dist > 1e-6 and dx / dist or 0, dist > 1e-6 and dy / dist or -1

    -- High-speed player getaway forces direct pursuit instead of slow looping.
    if playerFast and dist > 440 and dx * ship.vx + dy * ship.vy > 0 and enemy.state ~= "form" then
        local speed = definition.chargeSpeed + (enemy.blindside and 70 or 0)
        enemy.state = "pursuit"
        return ship.vx + ux * speed, ship.vy + uy * speed, math.atan2(dx, -dy)
    elseif enemy.state == "pursuit" then
        beginDive(enemy, ship, definition, not leaderAlive)
    end

    if enemy.state == "form" then
        if not leaderAlive then
            beginDive(enemy, ship, definition, true)
        else
            if enemy.lastDiveSignal ~= leader.diveSignal then
                enemy.lastDiveSignal = leader.diveSignal
                beginDive(enemy, ship, definition, false)
            else
                local slotX, slotY = wingPosition(leader, enemy.slot)
                local relX, relY = limitVector((slotX - enemy.x) * 2.5, (slotY - enemy.y) * 2.5, definition.cruiseSpeed)
                return leader.vx + relX, leader.vy + relY, leader.angle
            end
        end
    end

    if enemy.state == "recover" then
        enemy.bankProgress = math.min(math.pi * 0.85, enemy.bankProgress + enemy.turnSpeed * 0.7 * step)
        local angle = enemy.courseAngle - enemy.slot * enemy.bankProgress
        if enemy.bankProgress >= math.pi * 0.85 then
            enemy.bankProgress = nil
            if leaderAlive then
                enemy.state = "form"
                enemy.lastDiveSignal = leader.diveSignal
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

local function move(enemy, dt, ship, aimAngle, camera, width, height)
    local definition = Enemies.types[enemy.kind]
    local playerSpeed = ship:speed()
    local playerSlow = ship.braking or playerSpeed < 160
    local playerFast = playerSpeed > 420
    local visible
    if enemy.role == "leader" then
        local x, y = camera:worldToScreen(enemy.x, enemy.y, width, height)
        visible = x > 28 and x < width - 28 and y > 28 and y < height - 28
    end
    -- Small steering steps also keep long updates bounded without snapping velocity.
    while dt > 0 do
        local step = math.min(dt, 1 / 60)
        local evadeX, evadeY = aimEvasion(enemy, ship, aimAngle, step)
        local targetVx, targetVy, angle
        if enemy.role == "leader" then
            targetVx, targetVy, angle = leaderSteering(enemy, ship, definition, step, playerSlow, playerFast, visible)
        elseif enemy.role == "escort" then
            targetVx, targetVy, angle = escortSteering(enemy, ship, definition, playerSlow, playerFast)
        else
            targetVx, targetVy, angle = flankerSteering(enemy, ship, definition, step, playerSlow, playerFast)
        end
        targetVx, targetVy = limitVector(targetVx + enemy.sepX + evadeX * definition.evadeSpeed,
            targetVy + enemy.sepY + evadeY * definition.evadeSpeed, enemy.maxSpeed)
        local ax = (targetVx - enemy.vx) * 2.5
        local ay = (targetVy - enemy.vy) * 2.5
        local acceleration = math.sqrt(ax * ax + ay * ay)
        enemy.thrust = math.min(enemy.thrustLimit, acceleration)
        local scale = acceleration > 0 and enemy.thrust / acceleration or 0
        local oldVx, oldVy = enemy.vx, enemy.vy
        enemy.vx, enemy.vy = enemy.vx + ax * scale * step, enemy.vy + ay * scale * step
        enemy.vx, enemy.vy = limitVector(enemy.vx, enemy.vy, enemy.maxSpeed)
        enemy.x = enemy.x + (oldVx + enemy.vx) * 0.5 * step
        enemy.y = enemy.y + (oldVy + enemy.vy) * 0.5 * step
        local error = (angle - enemy.angle + math.pi) % tau - math.pi
        enemy.angle = (enemy.angle + clamp(error, -enemy.turnSpeed * step, enemy.turnSpeed * step)) % tau
        dt = dt - step
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
                local push = (minDist - dist) / minDist * 220
                a.sepX, a.sepY = a.sepX + ux * push, a.sepY + uy * push
                b.sepX, b.sepY = b.sepX - ux * push, b.sepY - uy * push
            end
        end
    end
end

function Enemies:update(dt, ship, camera, width, height, aimAngle)
    if dt <= 0 then return end
    local despawnDistance = math.max(6000, math.sqrt(width * width + height * height) / camera.zoom * 4)
    computeSeparation(self.items)
    for _, enemy in ipairs(self.items) do
        if enemy.role == "escort" and enemy.leader and enemy.leader.dead then
            reassignEscort(self.items, enemy)
        elseif enemy.role == "flanker" and enemy.leader and enemy.leader.dead then
            enemy.leader = nil
            beginDive(enemy, ship, self.types[enemy.kind], true)
        end
    end
    for i = #self.items, 1, -1 do
        local enemy = self.items[i]
        enemy.prevX, enemy.prevY = enemy.x, enemy.y
        move(enemy, dt, ship, aimAngle, camera, width, height)
        if (enemy.x - ship.x) ^ 2 + (enemy.y - ship.y) ^ 2 > despawnDistance ^ 2 then
            enemy.dead = true
            table.remove(self.items, i)
        end
    end

    if #self.items + squadSize > self.maxCount then
        self.spawnAccumulator = 0
        return
    end
    self.spawnAccumulator = self.spawnAccumulator + dt * self.spawnRate
    local count = math.floor(self.spawnAccumulator + 1e-9)
    self.spawnAccumulator = math.max(0, self.spawnAccumulator - count)
    for i = 1, count do
        if #self.items + squadSize > self.maxCount then break end
        local squad = self:spawnSquad(ship, camera, width, height)
        local slice = (count - i + self.spawnAccumulator) / self.spawnRate
        for _, enemy in ipairs(squad) do
            -- A new arrival moves only for the portion of the frame after its birth.
            move(enemy, slice, ship, aimAngle, camera, width, height)
        end
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
