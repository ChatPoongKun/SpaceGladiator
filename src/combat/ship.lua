local Arena = require("src.core.arena")
local Sfx = require("src.audio.sfx")
local Ship = {}
Ship.__index = Ship

Ship.thrust = 315
Ship.brake = 2.0
Ship.maxSpeed = 180
Ship.turnSpeed = 3.5
Ship.radius = 23
Ship.shieldMargin = 1.3
Ship.destructionDuration = 0.7
Ship.hitInvulnDuration = 0.5
Ship.invulnBlinkInterval = 0.05
Ship.driftThreshold = 50
Ship.driftDeceleration = 50
Ship.naturalDrag = 0.5
Ship.boostSpeed = 420
Ship.boostHold = 0.24
Ship.boostFalloff = 0.24
Ship.boostCost = 20
Ship.thrustBatteryCost = 1
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
        hasThruster = true,
        thrust = Ship.thrust,
        brake = Ship.brake,
        maxSpeed = Ship.maxSpeed,
        turnSpeed = Ship.turnSpeed,
        boostSpeed = Ship.boostSpeed,
        boostHold = Ship.boostHold,
        boostFalloff = Ship.boostFalloff,
        boostCost = Ship.boostCost,
        thrustBatteryCost = Ship.thrustBatteryCost,
        wrapBonusSpeed = Ship.wrapBonusSpeed,
        wrapInvulnDuration = 0, invulnTimer = 0, invulnDuration = 0, wrapEvents = 0,
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

function Ship:isInvulnerable()
    return (self.invulnTimer or 0) > 0
end

function Ship:invulnBlinkAlpha()
    if not self:isInvulnerable() then return 1, 0 end
    local duration = math.max(self.invulnDuration or self.hitInvulnDuration, self.invulnTimer)
    local elapsed = math.max(0, duration - self.invulnTimer)
    local cycle = math.floor((elapsed + 1e-9) / self.invulnBlinkInterval) % 2
    if cycle == 0 then
        return 1, 0.85
    end
    return 0.22, 0
end

function Ship:grantInvulnerability(duration)
    if not duration or duration <= 0 then return end
    if duration > (self.invulnTimer or 0) then
        self.invulnTimer = duration
        self.invulnDuration = duration
    end
end

function Ship:applyBuild(build)
    if not build then return end
    local prevMaxShield, prevMaxArmor, prevMaxBattery = self.maxShield, self.maxArmor, self.maxBattery
    self.maxShield = build.noShield and 0 or (self.baseMaxShield + (build.maxShieldBonus or 0))
    self.maxArmor = self.baseMaxArmor + (build.maxArmorBonus or 0)
    self.maxBattery = self.baseMaxBattery + (build.maxBatteryBonus or 0)
    self.batteryRecharge = (self.baseBatteryRecharge + (build.batteryRechargeBonus or 0)) * (build.batteryRechargeMult or 1)
    if build.hasThruster ~= nil then
        if build.hasThruster then
            self.hasThruster = true
            self.thrust = build.thrust or 0
            self.brake = build.brake or 0
            self.maxSpeed = build.maxSpeed or 0
            self.turnSpeed = build.turnSpeed or 0
            self.boostSpeed = build.boostSpeed or 0
            self.boostHold = build.boostHold or 0
            self.boostFalloff = build.boostFalloff or 0
            self.boostCost = math.max(0, (build.boostCost or 0) + (build.boostCostBonus or 0))
            self.thrustBatteryCost = math.max(0, build.thrustBatteryCost or 0)
            self.wrapBonusSpeed = (build.wrapBonusSpeed or 0) * (build.wrapSpeedMult or 1)
        else
            self.hasThruster = false
            self.thrust = 0
            self.brake = 0
            self.maxSpeed = 0
            self.turnSpeed = 0
            self.boostSpeed = 0
            self.boostHold = 0
            self.boostFalloff = 0
            self.boostCost = 0
            self.thrustBatteryCost = 0
            self.wrapBonusSpeed = 0
            self.boostRemaining = 0
            self.boostLevel = 0
            self.accelerating = false
            self.braking = false
        end
    else
        self.maxSpeed = self.baseMaxSpeed + (build.maxSpeedBonus or 0)
        self.boostSpeed = self.baseBoostSpeed + (build.boostSpeedBonus or 0)
        self.boostCost = math.max(5, self.baseBoostCost + (build.boostCostBonus or 0))
        self.wrapBonusSpeed = (self.baseWrapBonusSpeed + (build.wrapBonusSpeedAdd or 0)) * (build.wrapSpeedMult or 1)
    end
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
    if amount <= 0 or self:isDestroyed() or self:isInvulnerable() then return end
    self.damageCount = (self.damageCount or 0) + 1
    Sfx.play("player_hit")
    if self:hasShield() then
        local absorbed = math.min(self.shield, amount)
        self.shield = self.shield - absorbed
        self.shieldDamageTaken = (self.shieldDamageTaken or 0) + absorbed
        amount = amount - absorbed
    end
    if amount <= 0 then return end

    local absorbed = math.min(self.armor, amount)
    self.armor = self.armor - absorbed
    self.armorDamageTaken = (self.armorDamageTaken or 0) + absorbed
    if amount > absorbed then
        self.hull = math.max(0, self.hull - 1)
        if self:isDestroyed() then
            Sfx.play("ship_destroy")
            self.destructionAge = 0
            self.invulnTimer = 0
            self.invulnDuration = 0
            self.vx, self.vy, self.wrapVx, self.wrapVy = 0, 0, 0, 0
            self.accelerating, self.braking = false, false
            self.boostRemaining, self.boostLevel = 0, 0
            return
        end
    end

    self:grantInvulnerability(self.hitInvulnDuration)
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
    if not self.turnSpeed or self.turnSpeed <= 0 then return end
    self.angle = (self.angle + direction * self.turnSpeed * dt) % (2 * math.pi)
end

function Ship:updateVelocity(dt, thrust, brake, cap, coastDt, thrustDt)
    self.accelerating = thrust and not brake and (self.thrust or 0) > 0
    self.braking = brake and (self.brake or 0) > 0
    local oldVx, oldVy = self.vx, self.vy
    if self.braking then
        local damping = math.exp(-self.brake * dt)
        self.vx, self.vy = self.vx * damping, self.vy * damping
        if self:speed() < 0.5 then self.vx, self.vy = 0, 0 end
    elseif self.accelerating then
        local accelDt = thrustDt or dt
        self.vx = self.vx + math.sin(self.angle) * self.thrust * accelDt
        self.vy = self.vy - math.cos(self.angle) * self.thrust * accelDt
    end

    local speed = self:speed()
    if cap > 0 and speed > cap then
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

function Ship:update(dt, input, options)
    if dt <= 0 then return end
    self.prevX, self.prevY = self.x, self.y
    if self:isDestroyed() then
        self.destructionAge = (self.destructionAge or 0) + dt
        return
    end
    self:turn(dt, input.turn)

    local totalBoost = (self.boostHold or 0) + (self.boostFalloff or 0)
    if input.boost and not input.brake and self.hasThruster ~= false and totalBoost > 0
        and (self.boostSpeed or 0) > 0 and self.boostRemaining == 0 and self.battery >= self.boostCost then
        self.battery = self.battery - self.boostCost
        self.boostRemaining = totalBoost
        self.boostX, self.boostY = math.sin(self.angle), -math.cos(self.angle)
        self.vx, self.vy = self.boostX * self.boostSpeed, self.boostY * self.boostSpeed
        self.boostOriginX, self.boostOriginY = self.x, self.y
        Sfx.play("boost")
    end

    local rechargeTime = math.max(0, dt - self.boostRemaining)
    local rechargeAmount = rechargeTime * self.batteryRecharge
    local available = self.battery + rechargeAmount
    local thrustActive = input.thrust and not input.brake and (self.thrust or 0) > 0
    local thrustDt = 0
    if thrustActive then
        local costRate = self.thrustBatteryCost or 0
        if costRate > 0 then
            if available <= 1e-9 then
                thrustActive = false
                self.battery = math.min(self.maxBattery, math.max(0, available))
            elseif available >= costRate * dt then
                thrustDt = dt
                self.battery = math.min(self.maxBattery, available - costRate * dt)
            else
                thrustDt = available / costRate
                self.battery = 0
            end
        else
            thrustDt = dt
            self.battery = math.min(self.maxBattery, available)
        end
    else
        self.battery = math.min(self.maxBattery, available)
    end

    self.boostRemaining = math.max(0, self.boostRemaining - dt)
    local falloff = (self.boostFalloff and self.boostFalloff > 0 and self.boostRemaining > 0)
        and math.min(1, self.boostRemaining / self.boostFalloff) or 0
    self.boostLevel = falloff * falloff * (3 - 2 * falloff)
    local cap = self.maxSpeed + math.max(0, self.boostSpeed - self.maxSpeed) * self.boostLevel
    local oldVx, oldVy = self:updateVelocity(dt, thrustActive, input.brake, cap, rechargeTime, thrustDt)

    if (self.invulnTimer or 0) > 0 then
        self.invulnTimer = math.max(0, self.invulnTimer - dt)
        if self.invulnTimer <= 1e-9 then
            self.invulnTimer = 0
            self.invulnDuration = 0
        end
    end
    local margin = self:hitRadius() + 1
    local detectWrap = not (options and options.disableWrapDetection)
    local wrapBonusSpeed = (detectWrap and (self.wrapBonusSpeed or 0) > 0) and self.wrapBonusSpeed or Ship.wrapBonusSpeed
    local wrappedX, wrappedY
    self.x, self.vx, self.wrapVx, wrappedX = crossEdge(self.x, oldVx, self.vx, self.wrapVx, Arena.width, margin, dt, wrapBonusSpeed)
    self.y, self.vy, self.wrapVy, wrappedY = crossEdge(self.y, oldVy, self.vy, self.wrapVy, Arena.height, margin, dt, wrapBonusSpeed)
    if detectWrap and (wrappedX or wrappedY) then
        self.wrapEvents = (self.wrapEvents or 0) + 1
        if (self.wrapInvulnDuration or 0) > 0 then
            self:grantInvulnerability(self.wrapInvulnDuration)
        end
    end
end

function Ship:drawBoostPulse()
    local totalBoost = (self.boostHold or 0) + (self.boostFalloff or 0)
    if totalBoost <= 0 or not self.boostOriginX then return end
    local age = totalBoost - self.boostRemaining
    if age >= 0 and age < 0.20 then
        local g = love.graphics
        local flash = 1 - age / 0.20
        g.setColor(0.38, 0.83, 1, flash * 0.55)
        g.setLineWidth(1 + flash * 2)
        g.circle("line", self.boostOriginX, self.boostOriginY, 22 + age * 260)
    end
end

local function blendWhite(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function setBlendedColor(g, r, gg, b, a, flash, alpha)
    local br, bg, bb = blendWhite(r, gg, b, flash)
    g.setColor(br, bg, bb, a * alpha)
end

function Ship:draw(time)
    local g = love.graphics
    local t = time or 0
    local speed = self:speed()
    local boost = self.boostLevel
    local blinkAlpha, blinkFlash = self:invulnBlinkAlpha()
    local pulse = 0.86 + 0.14 * math.sin(t * 6.5)

    g.push("all")
    if self:hasShield() then
        local radius = self:hitRadius()
        g.setColor(0.16, 0.56, 1, 0.09 * blinkAlpha)
        g.circle("fill", self.x, self.y, radius)
        g.setLineWidth(3.4)
        g.setColor(0.28, 0.72, 1, 0.22 * blinkAlpha)
        g.circle("line", self.x, self.y, radius)
        g.setLineWidth(1.2)
        g.setColor(0.51, 0.88, 1, 0.84 * blinkAlpha)
        g.circle("line", self.x, self.y, radius)
        g.setLineWidth(1.4)
        g.setColor(0.85, 0.98, 1, 0.45 * blinkAlpha)
        g.arc("line", "open", self.x, self.y, radius, self.angle - math.pi * 0.75, self.angle - math.pi * 0.25)
    end
    if speed > 4 then
        -- The small marker shows momentum, independently of the ship's nose.
        local dx, dy = self.vx / speed, self.vy / speed
        local speedRatio = (self.maxSpeed and self.maxSpeed > 0) and (speed / self.maxSpeed) or 0
        local length = 36 + speedRatio * 30
        local x, y = self.x + dx * length, self.y + dy * length
        g.setLineWidth(1)
        g.setColor(0.40, 0.85, 0.92, 0.23 * blinkAlpha)
        g.line(self.x + dx * 29, self.y + dy * 29, x, y)
        g.circle("line", x, y, 3)
    end

    if self.braking and speed > 1 then
        local brakingPulse = 0.22 + math.sin(t * 18) * 0.08
        g.setColor(0.35, 0.92, 0.91, brakingPulse * blinkAlpha)
        g.setLineWidth(2)
        g.arc("line", "open", self.x, self.y, 30, t * 2, t * 2 + 4.5)
    end

    g.push()
    g.translate(self.x, self.y)
    g.rotate(self.angle)

    -- Twin thrusters aligned with the Option A exhaust ports (x = +-3.2, y = 17).
    if boost > 0 then
        local trail = (86 + math.sin(t * 96) * 14) * boost
        g.setColor(0.14, 0.57, 1, boost * 0.20 * blinkAlpha)
        g.ellipse("fill", 0, 22 + trail * 0.30, 15, 13 + trail * 0.62)
        for _, side in ipairs({ -1, 1 }) do
            local nx = side * 3.2
            g.setColor(0.20, 0.72, 1, boost * 0.88 * blinkAlpha)
            g.polygon("fill", nx - 3.6, 16.5, nx, 22 + trail, nx + 3.6, 16.5)
            g.setColor(0.82, 0.99, 1, boost * blinkAlpha)
            g.polygon("fill", nx - 1.8, 16.5, nx, 19 + trail * 0.56, nx + 1.8, 16.5)
            g.setColor(0.48, 0.90, 1, boost * 0.65 * blinkAlpha)
            g.setLineWidth(1.6)
            g.line(side * 10, 18, side * 11, 25 + trail * 0.66)
        end
    elseif self.accelerating then
        local flame = 23 + math.sin(t * 57) * 5 + math.sin(t * 31) * 3
        g.setColor(0.18, 0.74, 1, 0.14 * blinkAlpha)
        g.ellipse("fill", 0, 22 + flame * 0.25, 12, flame * 0.75 + 7)
        for _, side in ipairs({ -1, 1 }) do
            local nx = side * 3.2
            g.setColor(0.16, 0.62, 1, 0.78 * blinkAlpha)
            g.polygon("fill", nx - 2.6, 16.5, nx, 17 + flame, nx + 2.6, 16.5)
            g.setColor(0.48, 0.96, 1, 0.92 * blinkAlpha)
            g.polygon("fill", nx - 1.7, 16.5, nx, 17 + flame * 0.68, nx + 1.7, 16.5)
            g.setColor(0.96, 1, 1, blinkAlpha)
            g.polygon("fill", nx - 1.0, 16.5, nx, 16 + flame * 0.42, nx + 1.0, 16.5)
        end
    end

    -- Soft cyan ambient aura behind the Option A Solid Silhouette hull.
    for scale = 2, 1, -1 do
        local glowAlpha = (0.04 + 0.065 * blinkFlash) * (3 - scale) * blinkAlpha
        setBlendedColor(g, 0.50, 0.91, 1, glowAlpha, blinkFlash, 1)
        g.push()
        g.scale(1 + scale * 0.08)
        g.polygon("fill", 0, -26, 5, -13, 7, -3, 20, 9, 20, 14, 8, 12, 5, 17, 0, 17)
        g.polygon("fill", 0, -26, 0, 17, -5, 17, -8, 12, -20, 14, -20, 9, -7, -3, -5, -13)
        g.pop()
    end

    -- 1. Main hull (two-tone directional shading: lit right ice-white, shaded left cool-steel).
    setBlendedColor(g, 0.894, 0.933, 0.969, 1, blinkFlash * 0.72, blinkAlpha)
    g.polygon("fill", 0, -26, 5, -13, 7, -3, 8, 12, 5, 17, 0, 17)
    g.polygon("fill", 7, -3, 20, 9, 20, 14, 8, 12)

    setBlendedColor(g, 0.624, 0.702, 0.780, 1, blinkFlash * 0.72, blinkAlpha)
    g.polygon("fill", 0, -26, 0, 17, -5, 17, -8, 12, -7, -3, -5, -13)
    g.polygon("fill", -7, -3, -8, 12, -20, 14, -20, 9)

    -- 2. Wing cyan energy stripes & center spine seam.
    g.setLineWidth(1.6)
    setBlendedColor(g, 0.173, 0.812, 1, 0.95, blinkFlash, blinkAlpha)
    g.line(-8, 3, -17.5, 11)
    g.line(8, 3, 17.5, 11)

    g.setLineWidth(0.75)
    setBlendedColor(g, 0.424, 0.506, 0.592, 0.9, blinkFlash, blinkAlpha)
    g.line(0, -2, 0, 14)

    -- 3. Cockpit canopy & glowing visor glint.
    setBlendedColor(g, 0.051, 0.106, 0.173, 1, blinkFlash * 0.72, blinkAlpha)
    g.polygon("fill", 0, -18, 3, -10, 2, -4, -2, -4, -3, -10)
    setBlendedColor(g, 0.561, 0.953, 1, 0.95 * pulse, blinkFlash, blinkAlpha)
    g.polygon("fill", 0, -16.5, 1.6, -10.5, 0, -8.5)

    -- 4. Twin plasma exhaust bars & wingtip emitter dots.
    setBlendedColor(g, 0.435, 0.941, 1, 0.84 + 0.16 * pulse, blinkFlash, blinkAlpha)
    g.rectangle("fill", -5.2, 15.6, 4, 2.6, 0.6, 0.6)
    g.rectangle("fill", 1.2, 15.6, 4, 2.6, 0.6, 0.6)
    g.circle("fill", -20, 11.5, 1.5)
    g.circle("fill", 20, 11.5, 1.5)

    -- 5. Crisp outer silhouette outline.
    g.setLineWidth(0.8 + blinkFlash * 0.6)
    setBlendedColor(g, 1, 1, 1, 0.85, blinkFlash, blinkAlpha)
    g.polygon("line", 0, -26, 5, -13, 7, -3, 20, 9, 20, 14, 8, 12, 5, 17, -5, 17, -8, 12, -20, 14, -20, 9, -7, -3, -5, -13)

    g.pop()
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
