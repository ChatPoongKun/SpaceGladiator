local Arena = require("arena")
local Collision = require("collision")
local EnemyFire = {}
EnemyFire.__index = EnemyFire

local burstInterval = 0.12
local impactLifetime = 0.24
local missileAngles = {-60, -36, -12, 12, 36, 60}
local bullet = {speed = 540, lifetime = 1.4, radius = 3, damage = 6, trail = 13, color = {1, 0.45, 0.23}}
local laser = {speed = 1400, lifetime = 0.7, radius = 4, damage = 14, trail = 48, color = {1, 0.24, 0.65}}
local missile = {radius = 5, damage = 8, trail = 24, color = {1, 0.28, 0.28}}

function EnemyFire.new()
    return setmetatable({shots = {}, bursts = {}, impacts = {}}, EnemyFire)
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

local function launchLinear(fire, enemy, targetX, targetY, profile, delay)
    local angle = bearing(enemy, targetX, targetY)
    local shot = launch(fire, enemy, angle, profile, delay)
    shot.vx, shot.vy = shot.vx * profile.speed, shot.vy * profile.speed
    shot.lifetime = profile.lifetime
end

function EnemyFire:shoot(enemy, ship)
    if ship:isDestroyed() then return end
    local targetX, targetY = ship.x, ship.y
    if enemy.kind == 1 then
        launchLinear(self, enemy, targetX, targetY, bullet, 0)
        self.bursts[#self.bursts + 1] = {
            enemy = enemy, targetX = targetX, targetY = targetY, remaining = 2, delay = burstInterval,
        }
    elseif enemy.kind == 2 then
        launchLinear(self, enemy, targetX, targetY, laser, 0)
    else
        local angle, distance = bearing(enemy, targetX, targetY)
        local reach = math.max(34, math.min(135, distance * 0.46))
        local lifetime = math.max(0.6, distance / 375 + 0.15)
        for _, offset in ipairs(missileAngles) do
            local shot = launch(self, enemy, angle + math.rad(offset), missile, 0)
            shot.startX, shot.startY = shot.x, shot.y
            shot.controlX, shot.controlY = shot.x + shot.vx * reach, shot.y + shot.vy * reach
            shot.targetX, shot.targetY = targetX, targetY
            shot.lifetime = lifetime
            shot.vx, shot.vy = shot.vx * 2 * reach / lifetime, shot.vy * 2 * reach / lifetime
        end
    end
end

local function wrappedDelta(start, finish, extent)
    return (finish - start + extent / 2) % extent - extent / 2
end

local function playerHit(shot, motion, x, y, elapsed, step, radius)
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
    local t = Collision.circleEntry(rx, ry, vx, vy, radius + shot.profile.radius)
    if t then return px + dx * span * t, py + dy * span * t, start + step * span * t end
end

local function moveShot(shot, step)
    shot.age = shot.age + step
    if shot.profile == missile then
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

local function stepShots(fire, ship, motion, elapsed, finish)
    local contacts = {}
    local hitRadius = ship:hitRadius()
    for _, shot in ipairs(fire.shots) do
        local start = math.max(elapsed, shot.delay)
        local step = math.min(finish - start, shot.lifetime - shot.age)
        if step > 0 then
            local oldX, oldY = shot.x, shot.y
            moveShot(shot, step)
            if not ship:isDestroyed() then
                local x, y, at = playerHit(shot, motion, oldX, oldY, start, step, hitRadius)
                if x then
                    contacts[#contacts + 1] = {shot = shot, x = x, y = y, at = at,
                        oldX = oldX, oldY = oldY, start = start, step = step}
                end
            end
        end
    end

    while #contacts > 0 and not ship:isDestroyed() do
        local first = 1
        for i = 2, #contacts do
            if contacts[i].at < contacts[first].at then first = i end
        end
        local hit = table.remove(contacts, first)
        impact(fire, hit.shot, hit.x, hit.y, ship:hasShield())
        ship:takeDamage(hit.shot.profile.damage)
        hit.shot.spent = true

        -- A broken shield exposes the smaller hull to the remaining shots in this step.
        if ship:hitRadius() ~= hitRadius then
            hitRadius = ship:hitRadius()
            for i = #contacts, 1, -1 do
                local contact = contacts[i]
                contact.x, contact.y, contact.at = playerHit(contact.shot, motion, contact.oldX,
                    contact.oldY, contact.start, contact.step, hitRadius)
                if not contact.x then table.remove(contacts, i) end
            end
        end
    end

    for i = #fire.shots, 1, -1 do
        local shot = fire.shots[i]
        if shot.spent then
            table.remove(fire.shots, i)
        elseif shot.age >= shot.lifetime - 1e-9 then
            if shot.profile == missile then impact(fire, shot, shot.x, shot.y) end
            table.remove(fire.shots, i)
        end
    end
end

function EnemyFire:update(dt, ship)
    for i = #self.impacts, 1, -1 do
        local effect = self.impacts[i]
        effect.age = effect.age + dt
        if effect.age >= impactLifetime then table.remove(self.impacts, i) end
    end
    for i = #self.bursts, 1, -1 do
        local burst = self.bursts[i]
        if not burst.enemy.dead then
            while burst.remaining > 0 and burst.delay <= dt + 1e-9 do
                launchLinear(self, burst.enemy, burst.targetX, burst.targetY, bullet, math.min(dt, burst.delay))
                burst.remaining, burst.delay = burst.remaining - 1, burst.delay + burstInterval
            end
            burst.delay = burst.delay - dt
        end
        if burst.enemy.dead or burst.remaining == 0 then table.remove(self.bursts, i) end
    end

    local x, y = ship.prevX or ship.x, ship.prevY or ship.y
    local motion = {x = x, y = y,
        vx = wrappedDelta(x, ship.x, Arena.width) / dt, vy = wrappedDelta(y, ship.y, Arena.height) / dt}
    local elapsed = 0
    while elapsed < dt and #self.shots > 0 do
        local finish = math.min(dt, elapsed + 1 / 60)
        stepShots(self, ship, motion, elapsed, finish)
        elapsed = finish
    end
    for _, shot in ipairs(self.shots) do shot.delay = 0 end
end

function EnemyFire:draw()
    local g = love.graphics
    g.push("all")
    for _, shot in ipairs(self.shots) do
        local profile = shot.profile
        local r, green, b = unpack(profile.color)
        local length = math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy)
        local dx, dy = 0, 0
        if length > 0 then dx, dy = shot.vx / length, shot.vy / length end
        local trail = math.min(profile.trail, profile.radius + length * shot.age)
        local tailX, tailY = shot.x - dx * trail, shot.y - dy * trail
        g.setLineWidth(profile.radius * 1.8)
        g.setColor(r, green, b, 0.25)
        g.line(tailX, tailY, shot.x, shot.y)
        g.setLineWidth(profile == laser and 3 or 1.5)
        g.setColor(r, green, b, 0.9)
        g.line(tailX, tailY, shot.x, shot.y)
        g.setColor(1, 0.85, 0.75, 1)
        g.circle("fill", shot.x, shot.y, profile.radius * 0.55)
    end
    for _, effect in ipairs(self.impacts) do
        local progress = effect.age / impactLifetime
        local r, green, b = unpack(effect.profile.color)
        if effect.shield then r, green, b = 0.30, 0.70, 1 end
        g.setLineWidth(1.5)
        g.setColor(r, green, b, 0.8 * (1 - progress))
        g.circle("line", effect.x, effect.y, 4 + progress * effect.profile.radius * 4)
    end
    g.pop()
end

return EnemyFire
