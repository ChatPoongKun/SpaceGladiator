local Arena = require("arena")
local Sfx = require("sfx")
local Ship = {}
Ship.__index = Ship

Ship.thrust = 315
Ship.brake = 2.0
Ship.maxSpeed = 180
Ship.turnSpeed = 2.8
Ship.radius = 23
Ship.shieldMargin = 1.3
Ship.destructionDuration = 0.7
Ship.driftThreshold = 50
Ship.driftDeceleration = 50
Ship.naturalDrag = 0.5
Ship.boostSpeed = 420
Ship.boostHold = 0.24
Ship.boostFalloff = 0.24
Ship.boostCost = 25
Ship.batteryRecharge = 12
Ship.wrapBonusSpeed = 110
Ship.combatPower = 100

function Ship.new(width, height)
    return setmetatable({
        x = width / 2, y = height / 2,
        vx = 0, vy = 0, angle = 0,
        wrapVx = 0, wrapVy = 0,
        accelerating = false, braking = false,
        boostRemaining = 0, boostLevel = 0,
        boostX = 0, boostY = -1,
        shield = 100, maxShield = 100,
        armor = 100, maxArmor = 100,
        hull = 3, maxHull = 3,
        battery = 100, maxBattery = 100,
        baseMaxShield = 100, baseMaxArmor = 100, baseMaxBattery = 100,
        baseBatteryRecharge = Ship.batteryRecharge,
        baseMaxSpeed = Ship.maxSpeed, baseBoostSpeed = Ship.boostSpeed,
        baseBoostCost = Ship.boostCost, baseWrapBonusSpeed = Ship.wrapBonusSpeed,
        wrapBonusSpeed = Ship.wrapBonusSpeed,
        wrapInvulnDuration = 0, invulnTimer = 0, wrapEvents = 0,
        combatPower = Ship.combatPower,
        damageCount = 0,
        shieldDamageTaken = 0,
        armorDamageTaken = 0,
    }, Ship)
end

function Ship:speed()
    return math.sqrt(self.vx * self.vx + self.vy * self.vy)
end

-- The wrap bonus is part of world motion and is kept separate from flight speed.
function Ship:worldVelocity()
    return self.vx + self.wrapVx, self.vy + self.wrapVy
end

function Ship:hasShield()
    return self.maxShield > 0 and self.shield > 0
end

function Ship:hitRadius()
    return self:hasShield() and self.radius * self.shieldMargin or self.radius
end

function Ship:isDestroyed()
    return self.hull <= 0
end

function Ship:applyBuild(build)
    if not build then return end
    local prevMaxShield, prevMaxArmor, prevMaxBattery = self.maxShield, self.maxArmor, self.maxBattery
    self.maxShield = build.noShield and 0 or (self.baseMaxShield + (build.maxShieldBonus or 0))
    self.maxArmor = self.baseMaxArmor + (build.maxArmorBonus or 0)
    self.maxBattery = self.baseMaxBattery + (build.maxBatteryBonus or 0)
    self.batteryRecharge = (self.baseBatteryRecharge + (build.batteryRechargeBonus or 0)) * (build.batteryRechargeMult or 1)
    self.maxSpeed = self.baseMaxSpeed + (build.maxSpeedBonus or 0)
    self.boostSpeed = self.baseBoostSpeed + (build.boostSpeedBonus or 0)
    self.boostCost = math.max(5, self.baseBoostCost + (build.boostCostBonus or 0))
    self.wrapBonusSpeed = (self.baseWrapBonusSpeed + (build.wrapBonusSpeedAdd or 0)) * (build.wrapSpeedMult or 1)
    self.wrapInvulnDuration = build.wrapInvulnDuration or 0

    if self.maxShield > prevMaxShield then
        self.shield = self.shield + (self.maxShield - prevMaxShield)
    end
    self.shield = math.min(self.maxShield, self.shield)
    if self.maxArmor > prevMaxArmor then
        self.armor = self.armor + (self.maxArmor - prevMaxArmor)
    end
    self.armor = math.min(self.maxArmor, self.armor)
    if self.maxBattery > prevMaxBattery then
        self.battery = self.battery + (self.maxBattery - prevMaxBattery)
    end
    self.battery = math.min(self.maxBattery, self.battery)
end

function Ship:rechargeBattery(amount)
    if not amount or amount <= 0 then return end
    self.battery = math.min(self.maxBattery, self.battery + amount)
end

function Ship:takeDamage(amount)
    if amount <= 0 or self:isDestroyed() or (self.invulnTimer or 0) > 0 then return end
    self.damageCount = (self.damageCount or 0) + 1
    Sfx.play("player_hit")
    if self:hasShield() then
        local absorbed = math.min(self.shield, amount)
        self.shield = self.shield - absorbed
        self.shieldDamageTaken = (self.shieldDamageTaken or 0) + absorbed
        amount = amount - absorbed
    end
    local absorbed = math.min(self.armor, amount)
    self.armor = self.armor - absorbed
    self.armorDamageTaken = (self.armorDamageTaken or 0) + absorbed
    if amount <= absorbed then return end

    self.hull = math.max(0, self.hull - 1)
    if self:isDestroyed() then
        Sfx.play("ship_destroy")
        self.destructionAge = 0
        self.vx, self.vy, self.wrapVx, self.wrapVy = 0, 0, 0, 0
        self.accelerating, self.braking = false, false
        self.boostRemaining, self.boostLevel = 0, 0
    end
end

local function crossEdge(position, oldVelocity, velocity, bonus, extent, margin, dt, wrapBonusSpeed)
    local started = false
    if bonus == 0 then
        local travel = (oldVelocity + velocity) * 0.5 * dt
        local nextPosition = position + travel
        if nextPosition < margin or nextPosition > extent - margin then
            local direction = travel > 0 and 1 or -1
            if travel == 0 and nextPosition > extent - margin then direction = 1 end
            bonus = direction * (wrapBonusSpeed or Ship.wrapBonusSpeed)
            started = true
        end
    end

    -- Keep the crossing direction until the hull clears the edge.
    if oldVelocity * bonus < 0 then oldVelocity = 0 end
    if velocity * bonus < 0 then velocity = 0 end
    position = (position + ((oldVelocity + velocity) * 0.5 + bonus) * dt) % extent
    if position >= margin and position <= extent - margin then bonus = 0 end
    return position, velocity, bonus, started
end

function Ship:turn(dt, direction)
    self.angle = (self.angle + direction * self.turnSpeed * dt) % (2 * math.pi)
end

function Ship:updateVelocity(dt, thrust, brake, cap, coastDt)
    self.accelerating = thrust and not brake
    self.braking = brake
    local oldVx, oldVy = self.vx, self.vy
    if self.braking then
        local damping = math.exp(-self.brake * dt)
        self.vx, self.vy = self.vx * damping, self.vy * damping
        if self:speed() < 0.5 then self.vx, self.vy = 0, 0 end
    elseif self.accelerating then
        self.vx = self.vx + math.sin(self.angle) * self.thrust * dt
        self.vy = self.vy - math.cos(self.angle) * self.thrust * dt
    end

    local speed = self:speed()
    if speed > cap then
        self.vx, self.vy = self.vx * cap / speed, self.vy * cap / speed
        speed = cap
    end

    local dragTime = coastDt == nil and dt or coastDt
    if not self.braking and not self.accelerating and dragTime > 0 and speed > 0 then
        local dragRate = (self.naturalDrag or 0) > 0 and -math.log(1 - self.naturalDrag) or 0
        local remaining = speed
        local t = dragTime
        if dragRate > 0 then
            if remaining >= self.driftThreshold and self.driftThreshold > 0 and self.driftDeceleration > 0 then
                local toThreshold = math.log(remaining / self.driftThreshold) / dragRate
                if t <= toThreshold then
                    remaining = remaining * math.exp(-dragRate * t)
                    t = 0
                else
                    remaining = self.driftThreshold
                    t = t - toThreshold
                end
            end
            if t > 0 then
                if self.driftDeceleration > 0 and remaining <= self.driftThreshold then
                    local offset = self.driftDeceleration / dragRate
                    remaining = math.max(0, (remaining + offset) * math.exp(-dragRate * t) - offset)
                else
                    remaining = remaining * math.exp(-dragRate * t)
                end
            end
        elseif remaining < self.driftThreshold then
            remaining = math.max(0, remaining - self.driftDeceleration * t)
        end
        self.vx, self.vy = self.vx * remaining / speed, self.vy * remaining / speed
    elseif speed > 0 and speed < self.driftThreshold then
        local remaining = math.max(0, speed - self.driftDeceleration * dt)
        self.vx, self.vy = self.vx * remaining / speed, self.vy * remaining / speed
    end
    return oldVx, oldVy
end

function Ship:update(dt, input)
    if dt <= 0 then return end
    self.prevX, self.prevY = self.x, self.y
    if self:isDestroyed() then
        self.destructionAge = (self.destructionAge or 0) + dt
        return
    end
    self:turn(dt, input.turn)

    if input.boost and not input.brake and self.boostRemaining == 0 and self.battery >= self.boostCost then
        self.battery = self.battery - self.boostCost
        self.boostRemaining = self.boostHold + self.boostFalloff
        self.boostX, self.boostY = math.sin(self.angle), -math.cos(self.angle)
        self.vx, self.vy = self.boostX * self.boostSpeed, self.boostY * self.boostSpeed
        self.boostOriginX, self.boostOriginY = self.x, self.y
        Sfx.play("boost")
    end

    local rechargeTime = math.max(0, dt - self.boostRemaining)
    self.battery = math.min(self.maxBattery, self.battery + rechargeTime * self.batteryRecharge)
    self.boostRemaining = math.max(0, self.boostRemaining - dt)
    local falloff = math.min(1, self.boostRemaining / self.boostFalloff)
    self.boostLevel = falloff * falloff * (3 - 2 * falloff)
    local cap = self.maxSpeed + (self.boostSpeed - self.maxSpeed) * self.boostLevel
    local oldVx, oldVy = self:updateVelocity(dt, input.thrust, input.brake, cap, rechargeTime)

    self.invulnTimer = math.max(0, (self.invulnTimer or 0) - dt)
    local margin = self:hitRadius() + 1
    local wrappedX, wrappedY
    self.x, self.vx, self.wrapVx, wrappedX = crossEdge(self.x, oldVx, self.vx, self.wrapVx, Arena.width, margin, dt, self.wrapBonusSpeed)
    self.y, self.vy, self.wrapVy, wrappedY = crossEdge(self.y, oldVy, self.vy, self.wrapVy, Arena.height, margin, dt, self.wrapBonusSpeed)
    if wrappedX or wrappedY then
        self.wrapEvents = (self.wrapEvents or 0) + 1
        if (self.wrapInvulnDuration or 0) > 0 then
            self.invulnTimer = math.max(self.invulnTimer, self.wrapInvulnDuration)
        end
    end
end

function Ship:drawBoostPulse()
    local age = self.boostHold + self.boostFalloff - self.boostRemaining
    if age < 0.20 then
        local g = love.graphics
        local flash = 1 - age / 0.20
        g.setColor(0.38, 0.83, 1, flash * 0.55)
        g.setLineWidth(1 + flash * 2)
        g.circle("line", self.boostOriginX, self.boostOriginY, 22 + age * 260)
    end
end

function Ship:draw(time)
    local g = love.graphics
    local speed = self:speed()
    local boost = self.boostLevel
    if self:hasShield() then
        local radius = self:hitRadius()
        g.setColor(0.12, 0.36, 0.95, 0.14)
        g.circle("fill", self.x, self.y, radius)
        g.setLineWidth(4)
        g.setColor(0.17, 0.44, 1, 0.21)
        g.circle("line", self.x, self.y, radius)
        g.setLineWidth(1.3)
        g.setColor(0.40, 0.76, 1, 0.90)
        g.circle("line", self.x, self.y, radius)
    end
    if speed > 4 then
        -- The small marker shows momentum, independently of the ship's nose.
        local dx, dy = self.vx / speed, self.vy / speed
        local length = 36 + speed / self.maxSpeed * 30
        local x, y = self.x + dx * length, self.y + dy * length
        g.setLineWidth(1)
        g.setColor(0.40, 0.85, 0.92, 0.23)
        g.line(self.x + dx * 29, self.y + dy * 29, x, y)
        g.circle("line", x, y, 3)
    end

    if self.braking and speed > 1 then
        local pulse = 0.22 + math.sin(time * 18) * 0.08
        g.setColor(0.35, 0.92, 0.91, pulse)
        g.setLineWidth(2)
        g.arc("line", "open", self.x, self.y, 30, time * 2, time * 2 + 4.5)
    end

    g.push()
    g.translate(self.x, self.y)
    g.rotate(self.angle)

    if boost > 0 then
        local trail = (92 + math.sin(time * 96) * 14) * boost
        g.setColor(0.14, 0.57, 1, boost * 0.20)
        g.ellipse("fill", 0, 21 + trail * 0.33, 17, 13 + trail * 0.68)
        g.setColor(0.23, 0.70, 1, boost * 0.9)
        g.polygon("fill", -10, 15, 0, 23 + trail, 10, 15)
        g.setColor(0.81, 0.99, 1, boost)
        g.polygon("fill", -5, 15, 0, 20 + trail * 0.56, 5, 15)
        g.setColor(0.48, 0.88, 1, boost * 0.68)
        g.setLineWidth(2)
        g.line(-12, 22, -13, 28 + trail * 0.72)
        g.line(12, 22, 13, 28 + trail * 0.72)
    elseif self.accelerating then
        local flame = 27 + math.sin(time * 57) * 7 + math.sin(time * 31) * 3
        g.setColor(1, 0.40, 0.16, 0.08)
        g.ellipse("fill", 0, 23, 18, flame + 12)
        g.setColor(1, 0.46, 0.16, 0.8)
        g.polygon("fill", -7, 15, 0, 16 + flame, 7, 15)
        g.setColor(1, 0.85, 0.48, 1)
        g.polygon("fill", -4, 15, 0, 29 + flame * 0.3, 4, 15)
        g.setColor(0.92, 1, 1, 1)
        g.polygon("fill", -3, 15, 0, 27, 3, 15)
    end

    for scale = 3, 1, -1 do
        g.setColor(0.26, 0.78, 1, 0.025 * (4 - scale))
        g.push()
        g.scale(1 + scale * 0.12)
        g.polygon("fill", 0, -23, -15, 17, 15, 17)
        g.pop()
    end

    -- Symmetric silhouette: one tip, two equal sides, one flat base.
    g.setColor(0.075, 0.14, 0.20, 1)
    g.polygon("fill", 0, -23, -15, 17, 15, 17)
    g.setColor(0.46, 0.84, 0.91, 0.95)
    g.setLineWidth(1.6)
    g.polygon("line", 0, -23, -15, 17, 15, 17)
    g.setColor(0.75, 0.94, 1, 0.75)
    g.setLineWidth(1)
    g.line(0, -23, 0, 7, -15, 17)
    g.line(0, 7, 15, 17)
    g.setColor(0.36, 0.86, 1, 0.9)
    g.polygon("fill", 0, -11, -4, 1, 4, 1)
    g.setColor(0.58, 0.93, 1, 0.9)
    g.line(-6, 17, 6, 17)
    g.pop()
end

function Ship:drawDestruction()
    local phase = (self.destructionAge or 0) / self.destructionDuration
    if phase >= 1 then return end
    local g = love.graphics
    local fade = 1 - phase
    local radius = 15 + 62 * phase
    g.setColor(1, 0.37, 0.14, fade * 0.24)
    g.circle("fill", self.x, self.y, radius * 0.6)
    g.setColor(1, 0.91, 0.73, fade * fade)
    g.circle("fill", self.x, self.y, 20 * fade)
    g.setColor(1, 0.59, 0.27, fade)
    g.setLineWidth(1.5 + 2 * fade)
    g.circle("line", self.x, self.y, radius)
    for i = 0, 11 do
        local angle = i * math.pi / 6
        local dx, dy = math.cos(angle), math.sin(angle)
        local reach = radius * (i % 2 == 0 and 0.84 or 1.06)
        g.line(self.x + dx * reach * 0.68, self.y + dy * reach * 0.68,
            self.x + dx * reach, self.y + dy * reach)
    end
end

return Ship
