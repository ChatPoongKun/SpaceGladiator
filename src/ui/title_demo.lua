-- Live AI battle showcase running on the title screen.
-- Pilots the player's currently assembled Armory ship around the arena,
-- periodically spawns hostiles, fights them silently (SFX muted), and exposes
-- the ship's current pose so "Start Game" warps seamlessly in that direction.

local Arena = require("src.core.arena")
local Camera = require("src.core.camera")
local Display = require("src.core.display")
local Ship = require("src.combat.ship")
local Turret = require("src.combat.turret")
local Enemies = require("src.combat.enemies")
local Inventory = require("src.progression.inventory")
local Sfx = require("src.audio.sfx")

local TitleDemo = {}
TitleDemo.__index = TitleDemo

local tau = math.pi * 2

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function shortestAngleDiff(from, to)
    return (to - from + math.pi) % tau - math.pi
end

function TitleDemo.new(armoryInventory)
    local ship = Ship.new(Arena.width, Arena.height)
    ship.x = Arena.width * 0.67
    ship.y = Arena.height * 0.52
    ship.angle = math.rad(28)
    ship.vx = math.sin(ship.angle) * 140
    ship.vy = -math.cos(ship.angle) * 140

    local camera = Camera.new(ship.x, ship.y, { disableEffects = true })
    camera:update(0, ship, Display.VIRTUAL_WIDTH, Display.VIRTUAL_HEIGHT)

    local turret = Turret.new(ship.angle)
    local enemies = Enemies.new(nil, nil)
    enemies.spawnRate = 0
    enemies.maxCount = 4

    local self = setmetatable({
        ship = ship,
        camera = camera,
        turret = turret,
        enemies = enemies,
        build = nil,
        time = 0,
        patrolPhase = 0.6,
        spawnTimer = 1.6,
        boostCooldown = 1.5,
    }, TitleDemo)

    self:syncBuild(armoryInventory)
    return self
end

function TitleDemo:syncBuild(armoryInventory)
    local inv = armoryInventory
    if not inv or (inv.chassis and inv.chassis.locked) then
        inv = Inventory.newStarter()
    end
    local valid = inv:validateLoadout(false)
    if not valid then
        inv = Inventory.newStarter()
    end
    self.build = inv:computeBuild(false)
    self.ship:applyBuild(self.build, { resetVitals = true })
    if self.ship:speed() < 60 then
        local spd = math.min(140, self.ship.maxSpeed * 0.6)
        self.ship.vx = math.sin(self.ship.angle) * spd
        self.ship.vy = -math.cos(self.ship.angle) * spd
    end
end

function TitleDemo:spawnHostile()
    local enemies = self.enemies
    if not enemies or #enemies.items >= 3 then return end
    local count = (#enemies.items == 0 and math.random() < 0.55) and 2 or 1
    for i = 1, count do
        if #enemies.items >= 3 then break end
        local kind = math.random() < 0.68 and 1 or 2
        local edge = math.random(1, 3)
        local sx, sy
        if edge == 1 then
            sx = Arena.width + 44
            sy = Arena.height * (0.20 + math.random() * 0.60)
        elseif edge == 2 then
            sx = Arena.width * (0.45 + math.random() * 0.45)
            sy = -44
        else
            sx = Arena.width * (0.45 + math.random() * 0.45)
            sy = Arena.height + 44
        end
        local ang = math.atan2(self.ship.x - sx, -(self.ship.y - sy))
        enemies:spawn(self.ship, kind, {
            x = sx,
            y = sy,
            vx = math.sin(ang) * 110,
            vy = -math.cos(ang) * 110,
            angle = ang,
            entryTime = 0.75,
        })
    end
end

function TitleDemo:_nearestEnemy()
    local best, bestDistSq = nil, math.huge
    for _, e in ipairs(self.enemies.items) do
        local dx, dy = e.x - self.ship.x, e.y - self.ship.y
        local dSq = dx * dx + dy * dy
        if dSq < bestDistSq then
            best, bestDistSq = e, dSq
        end
    end
    return best, math.sqrt(bestDistSq)
end

function TitleDemo:_updateSimulation(dt, width, height)
    local ship = self.ship
    local turret = self.turret
    local enemies = self.enemies
    local camera = self.camera

    self.time = self.time + dt
    self.patrolPhase = self.patrolPhase + dt * 0.44
    self.boostCooldown = math.max(0, self.boostCooldown - dt)

    -- Keep showcase ship alive & regenerate vitals between engagements
    if ship.hull < (ship.maxHull or 3) then
        ship.hull = ship.maxHull or 3
    end
    if ship.maxArmor > 0 and ship.armor < math.max(12, ship.maxArmor * 0.25) then
        ship.armor = math.max(12, ship.maxArmor * 0.35)
    end
    if #enemies.items == 0 then
        if ship.maxShield > 0 then
            ship.shield = math.min(ship.maxShield, ship.shield + 18 * dt)
        end
        if ship.maxArmor > 0 then
            ship.armor = math.min(ship.maxArmor, ship.armor + 12 * dt)
        end
    end

    -- Periodic enemy spawns
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer <= 0 then
        if #enemies.items < 3 then
            self:spawnHostile()
        end
        self.spawnTimer = 4.2 + math.random() * 2.2
    end

    -- AI Flight steering
    local targetEnemy, enemyDist = self:_nearestEnemy()
    local goalX, goalY
    if targetEnemy then
        local awayAngle = math.atan2(ship.y - targetEnemy.y, ship.x - targetEnemy.x)
        local orbitAngle = awayAngle + 0.85
        local orbitDist = 230
        goalX = clamp(targetEnemy.x + math.cos(orbitAngle) * orbitDist, 430, Arena.width - 110)
        goalY = clamp(targetEnemy.y + math.sin(orbitAngle) * orbitDist, 100, Arena.height - 100)
    else
        goalX = 820 + math.cos(self.patrolPhase) * 290
        goalY = 375 + math.sin(self.patrolPhase * 2) * 165
    end

    local desiredAngle = math.atan2(goalX - ship.x, -(goalY - ship.y))
    local angleErr = shortestAngleDiff(ship.angle, desiredAngle)
    local turnCmd = clamp(angleErr / 0.45, -1, 1)
    local speed = ship:speed()
    local thrustCmd = (math.abs(angleErr) < math.rad(78)) or (speed < (ship.maxSpeed or 250) * 0.45)
    local boostCmd = false
    if targetEnemy and enemyDist < 175 and self.boostCooldown <= 0
        and ship.boostRemaining == 0 and ship.battery >= (ship.boostCost or 25) * 1.4 then
        boostCmd = true
        self.boostCooldown = 2.6
    end

    ship:update(dt, {
        turn = turnCmd,
        thrust = thrustCmd,
        brake = false,
        boost = boostCmd,
    })
    camera:update(dt, ship, width, height)

    -- AI Turret aiming & firing
    local aimX, aimY
    local shouldFire = false
    if targetEnemy then
        aimX = targetEnemy.x + (targetEnemy.vx or 0) * 0.14
        aimY = targetEnemy.y + (targetEnemy.vy or 0) * 0.14
        local desiredTurret = math.atan2(aimX - ship.x, -(aimY - ship.y))
        local aimErr = math.abs(shortestAngleDiff(turret.angle, desiredTurret))
        shouldFire = aimErr <= math.rad(18)
    else
        aimX = ship.x + math.sin(ship.angle) * 240
        aimY = ship.y - math.cos(ship.angle) * 240
    end

    local activeWeapons = self.build and self.build.weaponModules or {}
    turret:update(dt, ship, aimX, aimY, shouldFire, enemies, camera, width, height, activeWeapons)
    enemies:update(dt, ship, turret.angle, camera, width, height)
end

function TitleDemo:update(dt, width, height)
    if not dt or dt <= 0 then return end
    local wasMuted = Sfx.isMuted and Sfx.isMuted() or false
    if Sfx.setMuted then Sfx.setMuted(true) end
    local ok, err = pcall(self._updateSimulation, self, dt, width or Display.VIRTUAL_WIDTH, height or Display.VIRTUAL_HEIGHT)
    if Sfx.setMuted then Sfx.setMuted(wasMuted) end
    if not ok then
        error(err)
    end
end

function TitleDemo:draw(time, width, height)
    if not (love and love.graphics) then return end
    local g = love.graphics
    local t = time or self.time or 0
    local camera = self.camera
    local ship = self.ship
    local turret = self.turret
    local enemies = self.enemies
    local originX, originY = camera:worldToScreen(0, 0, width, height)

    g.push("all")
    g.translate(originX, originY)
    g.scale(camera.zoom)

    enemies:draw(t)

    g.push("all")
    ship:drawBoostPulse()
    turret:drawMount(ship, t, width)
    ship:draw(t)
    g.pop()

    turret:drawEffects(camera, width, height)
    g.pop()
end

function TitleDemo:getShipPose()
    local s = self.ship
    if not s then return nil end
    return {
        x = s.x,
        y = s.y,
        angle = s.angle,
        vx = s.vx,
        vy = s.vy,
        turretAngle = self.turret and self.turret.angle or s.angle,
    }
end

return TitleDemo
