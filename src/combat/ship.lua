local Arena = require("src.core.arena")
local Sfx = require("src.audio.sfx")
local Ship = {}
Ship.__index = Ship

Ship.thrust = 350
Ship.brake = 2.5
Ship.maxSpeed = 250
Ship.turnSpeed = 4.5
Ship.radius = 23
Ship.shieldMargin = 1.3
Ship.destructionDuration = 0.7
Ship.hitInvulnDuration = 0.5
Ship.invulnBlinkInterval = 0.05
Ship.driftThreshold = 50
Ship.driftDeceleration = 50
Ship.naturalDrag = 0.5
Ship.boostSpeed = 450
Ship.boostThrust = 1800
Ship.boostHold = 0.24
Ship.boostFalloff = 0.24
Ship.boostCost = 25
Ship.batteryRecharge = 12
Ship.shieldRegen = 0
Ship.shieldRegenBatteryCost = 0
Ship.shieldRegenDelay = 2.0
Ship.wrapBonusSpeed = 110
Ship.combatPower = 100
Ship.hitKnockbackSpeed = 190
Ship.hullKnockbackSpeed = 270
Ship.knockbackDecay = 14
Ship.mass = 1.6
Ship.massWeightScale = 60
Ship.minMass = 0.5
Ship.pushDecay = 8
Ship.maxPushSpeed = 260

function Ship.massFromWeight(weight)
    if not weight or weight <= 0 then
        return Ship.mass
    end
    return math.max(Ship.minMass or 0.5, weight / (Ship.massWeightScale or 60))
end

function Ship.new(width, height)
    return setmetatable({
        x = width / 2, y = height / 2,
        vx = 0, vy = 0, angle = 0,
        wrapVx = 0, wrapVy = 0,
        knockVx = 0, knockVy = 0,
        pushVx = 0, pushVy = 0,
        mass = Ship.mass,
        accelerating = false, braking = false,
        boostRemaining = 0, boostLevel = 0,
        boostX = 0, boostY = -1,
        shield = 100, maxShield = 100,
        shieldRegen = 0, shieldRegenBatteryCost = 0,
        shieldRegenDelay = Ship.shieldRegenDelay, shieldRegenTimer = 0,
        armor = 100, maxArmor = 100,
        hull = 3, maxHull = 3,
        battery = 100, maxBattery = 100,
        baseMaxShield = 100, baseMaxArmor = 100, baseMaxBattery = 100,
        baseShieldRegen = 0, baseShieldRegenBatteryCost = 0,
        baseBatteryRecharge = Ship.batteryRecharge,
        baseMaxSpeed = Ship.maxSpeed, baseBoostSpeed = Ship.boostSpeed,
        baseBoostThrust = Ship.boostThrust,
        baseBoostCost = Ship.boostCost, baseThrustBatteryCost = 0,
        thrustBatteryCost = 0,
        baseWrapBonusSpeed = Ship.wrapBonusSpeed,
        wrapBonusSpeed = Ship.wrapBonusSpeed,
        totalWeight = 0,
        wrapInvulnDuration = 0, invulnTimer = 0, invulnDuration = 0, wrapEvents = 0,
        combatPower = Ship.combatPower,
        damageCount = 0,
        hullDamageCount = 0,
        lastHitLayer = nil,
        shieldDamageTaken = 0,
        armorDamageTaken = 0,
    }, Ship)
end

function Ship:speed()
    return math.sqrt(self.vx * self.vx + self.vy * self.vy)
end

-- The wrap bonus is part of world motion and is kept separate from flight speed.
function Ship:worldVelocity()
    return self.vx + self.wrapVx + (self.knockVx or 0), self.vy + self.wrapVy + (self.knockVy or 0)
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

function Ship:applyBuild(build, opts)
    if not build then return end
    local prevMaxShield, prevMaxArmor, prevMaxBattery = self.maxShield, self.maxArmor, self.maxBattery
    local resetVitals = opts and opts.resetVitals == true

    if build.fromChassis then
        self.chassisId = build.chassisId or self.chassisId or "striker"
        self.maxShield = build.noShield and 0 or (build.maxShield or 0)
        self.shieldRegen = build.noShield and 0 or (build.shieldRegen or 0)
        self.shieldRegenBatteryCost = build.noShield and 0 or (build.shieldRegenBatteryCost or 0)
        self.shieldRegenDelay = build.shieldRegenDelay or Ship.shieldRegenDelay
        self.maxArmor = build.maxArmor or 0
        self.maxHull = build.maxHull or self.maxHull or 3
        self.maxBattery = build.maxBattery or 0
        self.batteryRecharge = build.batteryRecharge or 0
        self.totalWeight = build.totalWeight or 0
        self.mass = Ship.massFromWeight(self.totalWeight)
        self.maxSpeed = build.maxSpeed or 0
        self.thrust = build.thrust ~= nil and build.thrust or Ship.thrust
        self.boostSpeed = build.boostSpeed or 0
        self.boostThrust = build.boostThrust ~= nil and build.boostThrust or (self.boostSpeed > 0 and Ship.boostThrust or 0)
        self.boostCost = (build.boostCost and build.boostCost > 0) and build.boostCost or Ship.boostCost
        self.thrustBatteryCost = build.thrustBatteryCost or 0
        self.wrapBonusSpeed = build.wrapBonusSpeed or Ship.wrapBonusSpeed
        self.turnSpeed = build.turnSpeed or Ship.turnSpeed
        self.brake = build.brake or Ship.brake
        self.wrapInvulnDuration = build.wrapInvulnDuration or 0
    else
        self.maxShield = build.noShield and 0 or (self.baseMaxShield + (build.maxShieldBonus or 0))
        self.shieldRegen = build.noShield and 0 or ((self.baseShieldRegen or 0) + (build.shieldRegenBonus or 0))
        self.shieldRegenBatteryCost = build.noShield and 0 or ((self.baseShieldRegenBatteryCost or 0) + (build.shieldRegenBatteryCostBonus or 0))
        self.shieldRegenDelay = build.shieldRegenDelay or self.shieldRegenDelay or Ship.shieldRegenDelay
        self.maxArmor = self.baseMaxArmor + (build.maxArmorBonus or 0)
        self.maxBattery = self.baseMaxBattery + (build.maxBatteryBonus or 0)
        self.batteryRecharge = (self.baseBatteryRecharge + (build.batteryRechargeBonus or 0)) * (build.batteryRechargeMult or 1)
        self.maxSpeed = self.baseMaxSpeed + (build.maxSpeedBonus or 0)
        self.boostSpeed = self.baseBoostSpeed + (build.boostSpeedBonus or 0)
        self.boostThrust = (self.baseBoostThrust or Ship.boostThrust) + (build.boostThrustBonus or 0)
        self.boostCost = math.max(5, self.baseBoostCost + (build.boostCostBonus or 0))
        self.thrustBatteryCost = (self.baseThrustBatteryCost or 0) + (build.thrustBatteryCostBonus or 0)
        self.wrapBonusSpeed = (self.baseWrapBonusSpeed + (build.wrapBonusSpeedAdd or 0)) * (build.wrapSpeedMult or 1)
        self.wrapInvulnDuration = build.wrapInvulnDuration or 0
        if build.totalWeight and build.totalWeight > 0 then
            self.totalWeight = build.totalWeight
            self.mass = Ship.massFromWeight(self.totalWeight)
        end
    end

    if resetVitals then
        self.shield = self.maxShield
        self.shieldRegenTimer = 0
        self.armor = self.maxArmor
        self.hull = self.maxHull
        self.battery = self.maxBattery
    else
        if self.maxShield > prevMaxShield then
            self.shield = self.shield + (self.maxShield - prevMaxShield)
        end
        self.shield = math.min(self.maxShield, self.shield)
        if self.maxArmor > prevMaxArmor then
            self.armor = self.armor + (self.maxArmor - prevMaxArmor)
        end
        self.armor = math.min(self.maxArmor, self.armor)
        self.hull = math.min(self.maxHull, self.hull)
        if self.maxBattery > prevMaxBattery then
            self.battery = self.battery + (self.maxBattery - prevMaxBattery)
        end
        self.battery = math.min(self.maxBattery, self.battery)
    end
end

function Ship:rechargeBattery(amount)
    if not amount or amount <= 0 then return end
    self.battery = math.min(self.maxBattery, self.battery + amount)
end

function Ship:applyKnockback(dx, dy, speed)
    if not dx or not dy or not speed or speed <= 0 then return end
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1e-6 then
        self.knockVx = (dx / len) * speed
        self.knockVy = (dy / len) * speed
    end
end

function Ship:takeDamage(amount, knockX, knockY, knockMult)
    if amount <= 0 or self:isDestroyed() or self:isInvulnerable() then return nil end
    local kMult = knockMult ~= nil and math.max(0, knockMult) or 1
    self.shieldRegenTimer = self.shieldRegenDelay or Ship.shieldRegenDelay
    self.damageCount = (self.damageCount or 0) + 1
    local hitLayer = nil
    if self:hasShield() then
        local absorbed = math.min(self.shield, amount)
        self.shield = self.shield - absorbed
        self.shieldDamageTaken = (self.shieldDamageTaken or 0) + absorbed
        amount = amount - absorbed
        hitLayer = "shield"
    end
    if amount <= 0 then
        Sfx.play("player_hit_shield")
        self:applyKnockback(knockX, knockY, (self.hitKnockbackSpeed or Ship.hitKnockbackSpeed) * kMult)
        self.lastHitLayer = hitLayer
        return hitLayer
    end

    local absorbed = math.min(self.armor, amount)
    self.armor = self.armor - absorbed
    self.armorDamageTaken = (self.armorDamageTaken or 0) + absorbed
    hitLayer = "armor"
    if amount > absorbed then
        hitLayer = "hull"
        self.hull = math.max(0, self.hull - 1)
        self.hullDamageCount = (self.hullDamageCount or 0) + 1
        Sfx.play("player_hit_hull")
        if self:isDestroyed() then
            Sfx.play("ship_destroy")
            self.destructionAge = 0
            self.invulnTimer = 0
            self.invulnDuration = 0
            self.vx, self.vy, self.wrapVx, self.wrapVy = 0, 0, 0, 0
            self.knockVx, self.knockVy = 0, 0
            self.accelerating, self.braking = false, false
            self.boostRemaining, self.boostLevel = 0, 0
            self.lastHitLayer = hitLayer
            return hitLayer
        end
    else
        Sfx.play("player_hit_armor")
    end

    local kbSpeed = hitLayer == "hull" and (self.hullKnockbackSpeed or Ship.hullKnockbackSpeed)
        or (self.hitKnockbackSpeed or Ship.hitKnockbackSpeed)
    self:applyKnockback(knockX, knockY, kbSpeed * kMult)
    self.lastHitLayer = hitLayer
    self:grantInvulnerability(self.hitInvulnDuration)
    return hitLayer
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

local function boostImpulseIntegral(rem, falloffDuration)
    if rem <= 0 then return 0 end
    if falloffDuration <= 0 then return rem end
    if rem >= falloffDuration then
        return 0.5 * falloffDuration + (rem - falloffDuration)
    end
    local u = rem / falloffDuration
    return falloffDuration * (u * u * u - 0.5 * u * u * u * u)
end

function Ship:updateVelocity(dt, thrust, brake, cap, coastDt, boostImpulseTime)
    self.accelerating = thrust and not brake
    self.braking = brake
    local oldVx, oldVy = self.vx, self.vy
    if self.braking then
        local damping = math.exp(-self.brake * dt)
        self.vx, self.vy = self.vx * damping, self.vy * damping
        if self:speed() < 0.5 then self.vx, self.vy = 0, 0 end
    else
        local totalAccel = 0
        if self.accelerating then
            totalAccel = totalAccel + self.thrust * dt
        end
        if boostImpulseTime and boostImpulseTime > 0 then
            totalAccel = totalAccel + (self.boostThrust or Ship.boostThrust) * boostImpulseTime
        end
        if totalAccel > 0 then
            self.vx = self.vx + math.sin(self.angle) * totalAccel
            self.vy = self.vy - math.cos(self.angle) * totalAccel
        end
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

function Ship:update(dt, input, options)
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
        self.boostOriginX, self.boostOriginY = self.x, self.y
        Sfx.play("boost")
    end

    local rechargeTime = math.max(0, dt - self.boostRemaining)
    local thrustDrain = self.thrustBatteryCost or 0
    local canThrust = input.thrust and not input.brake

    local regenDt = 0
    if self.maxShield > 0 and self.shield < self.maxShield and (self.shieldRegen or 0) > 0 then
        local timer = self.shieldRegenTimer or 0
        if timer > 0 then
            regenDt = math.max(0, dt - timer)
            timer = math.max(0, timer - dt)
            if timer <= 1e-9 then timer = 0 end
            self.shieldRegenTimer = timer
        else
            regenDt = dt
        end
    elseif (self.shieldRegenTimer or 0) > 0 then
        local timer = math.max(0, self.shieldRegenTimer - dt)
        self.shieldRegenTimer = timer <= 1e-9 and 0 or timer
    end

    local batteryPool = self.battery + rechargeTime * self.batteryRecharge
    if canThrust and thrustDrain > 0 and rechargeTime > 0 then
        local thrustCost = thrustDrain * rechargeTime
        if batteryPool >= thrustCost then
            batteryPool = batteryPool - thrustCost
        else
            canThrust = false
        end
    end

    if regenDt > 0 then
        local gain = math.min(self.maxShield - self.shield, self.shieldRegen * regenDt)
        if gain > 0 then
            local shieldCostRate = self.shieldRegenBatteryCost or 0
            if shieldCostRate > 0 then
                local activeTime = gain / self.shieldRegen
                local shieldCost = shieldCostRate * activeTime
                if batteryPool >= shieldCost then
                    batteryPool = batteryPool - shieldCost
                    self.shield = math.min(self.maxShield, self.shield + gain)
                elseif batteryPool > 0 then
                    local ratio = batteryPool / shieldCost
                    batteryPool = 0
                    self.shield = math.min(self.maxShield, self.shield + gain * ratio)
                end
            else
                self.shield = math.min(self.maxShield, self.shield + gain)
            end
        end
    end

    self.battery = math.min(self.maxBattery, math.max(0, batteryPool))
    local prevBoostRemaining = self.boostRemaining
    self.boostRemaining = math.max(0, prevBoostRemaining - dt)
    local boostImpulseTime = 0
    if prevBoostRemaining > 0 then
        self.boostX, self.boostY = math.sin(self.angle), -math.cos(self.angle)
        boostImpulseTime = boostImpulseIntegral(prevBoostRemaining, self.boostFalloff)
            - boostImpulseIntegral(self.boostRemaining, self.boostFalloff)
    end
    local falloff = math.min(1, self.boostRemaining / self.boostFalloff)
    self.boostLevel = falloff * falloff * (3 - 2 * falloff)
    local cap = self.maxSpeed + (self.boostSpeed - self.maxSpeed) * self.boostLevel
    local oldVx, oldVy = self:updateVelocity(dt, canThrust, input.brake, cap, rechargeTime, boostImpulseTime)

    if (self.invulnTimer or 0) > 0 then
        self.invulnTimer = math.max(0, self.invulnTimer - dt)
        if self.invulnTimer <= 1e-9 then
            self.invulnTimer = 0
            self.invulnDuration = 0
        end
    end
    local kOldX, kOldY = self.knockVx or 0, self.knockVy or 0
    if kOldX ~= 0 or kOldY ~= 0 then
        local kDecay = math.exp(-(self.knockbackDecay or Ship.knockbackDecay) * dt)
        self.knockVx = kOldX * kDecay
        self.knockVy = kOldY * kDecay
        if self.knockVx * self.knockVx + self.knockVy * self.knockVy < 4 then
            self.knockVx, self.knockVy = 0, 0
        end
    end
    local kNewX, kNewY = self.knockVx or 0, self.knockVy or 0

    local margin = self:hitRadius() + 1
    local detectWrap = not (options and options.disableWrapDetection)
    local wrapBonusSpeed = detectWrap and self.wrapBonusSpeed or Ship.wrapBonusSpeed
    local wrappedX, wrappedY
    self.x, _, self.wrapVx, wrappedX = crossEdge(self.x, oldVx + kOldX, self.vx + kNewX, self.wrapVx, Arena.width, margin, dt, wrapBonusSpeed)
    if self.vx * self.wrapVx < 0 then self.vx = 0 end
    self.y, _, self.wrapVy, wrappedY = crossEdge(self.y, oldVy + kOldY, self.vy + kNewY, self.wrapVy, Arena.height, margin, dt, wrapBonusSpeed)
    if self.vy * self.wrapVy < 0 then self.vy = 0 end
    if detectWrap and (wrappedX or wrappedY) then
        self.wrapEvents = (self.wrapEvents or 0) + 1
        if (self.wrapInvulnDuration or 0) > 0 then
            self:grantInvulnerability(self.wrapInvulnDuration)
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

local function blendWhite(r, g, b, amount)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function setBlendedColor(g, r, gg, b, a, flash, alpha)
    local br, bg, bb = blendWhite(r, gg, b, flash)
    g.setColor(br, bg, bb, a * alpha)
end

local SERAPH_CENTER_OUTLINE = {
    0, -24.5, 3.4, -22.5, 7.6, -3.5, 4.6, 4.5, 4.2, 16.5, 1.8, 17.5,
    0, 15.2, -1.8, 17.5, -4.2, 16.5, -4.6, 4.5, -7.6, -3.5, -3.4, -22.5,
}
local SERAPH_CENTER_FILLS = {
    { 0, -24.5, 3.4, -22.5, 7.6, -3.5, 4.6, 4.5, -4.6, 4.5, -7.6, -3.5, -3.4, -22.5 },
    { -4.6, 4.5, 4.6, 4.5, 4.2, 15.2, -4.2, 15.2 },
    { 0, 15.2, 4.2, 15.2, 4.2, 16.5, 1.8, 17.5 },
    { -4.2, 15.2, 0, 15.2, -1.8, 17.5, -4.2, 16.5 },
}
local SERAPH_WING_RIGHT = { 9.8, -1.8, 22.5, 11.8, 20.2, 15.5, 7.0, 13.0, 6.4, 5.2 }
local SERAPH_WING_LEFT = { -9.8, -1.8, -6.4, 5.2, -7.0, 13.0, -20.2, 15.5, -22.5, 11.8 }

local function drawSeraphPlates(g, mode)
    if mode == "fill" then
        for _, part in ipairs(SERAPH_CENTER_FILLS) do
            g.polygon("fill", part)
        end
    else
        g.polygon("line", SERAPH_CENTER_OUTLINE)
    end
    g.polygon(mode, SERAPH_WING_LEFT)
    g.polygon(mode, SERAPH_WING_RIGHT)
end

function Ship.drawChassis(chassisId, x, y, angle, scale, time, opts)
    opts = opts or {}
    local g = love.graphics
    local t = time or 0
    local pulse = 0.86 + 0.14 * math.sin(t * 6.5)
    local blinkAlpha = opts.blinkAlpha or opts.alpha or 1
    local blinkFlash = opts.blinkFlash or 0
    local locked = opts.locked == true
    local drawScale = scale or 1

    g.push("all")
    g.translate(x, y)
    g.rotate(angle or 0)
    if drawScale ~= 1 then
        g.scale(drawScale, drawScale)
    end
    g.setLineJoin("bevel")

    if locked then
        -- Dark mystery silhouette for locked ??? chassis
        g.setColor(0.05, 0.08, 0.13, 0.92 * blinkAlpha)
        drawSeraphPlates(g, "fill")
        g.setLineWidth(1.2 / math.max(1, drawScale * 0.45))
        g.setColor(0.32, 0.56, 0.70, 0.72 * blinkAlpha)
        drawSeraphPlates(g, "line")
        g.pop()
        return
    end

    -- 1. Additive sky-cyan outer bloom (#38dcff) around the segmented plates.
    g.setBlendMode("add")
    local bloomPulse = 0.92 + 0.08 * pulse
    for _, layer in ipairs({
        { width = 9.0, alpha = 0.085 },
        { width = 5.0, alpha = 0.17 },
        { width = 2.3, alpha = 0.30 },
    }) do
        local layerAlpha = (layer.alpha * bloomPulse + 0.08 * blinkFlash) * blinkAlpha
        setBlendedColor(g, 0.220, 0.863, 1.0, layerAlpha, blinkFlash, 1)
        g.setLineWidth(layer.width)
        drawSeraphPlates(g, "line")
    end
    g.push()
    g.scale(1.05)
    setBlendedColor(g, 0.220, 0.863, 1.0, (0.06 + 0.06 * blinkFlash) * blinkAlpha, blinkFlash, 1)
    drawSeraphPlates(g, "fill")
    g.pop()
    g.setBlendMode("alpha")

    -- 2. Luminous solid plates: ice-white center spear (#edfaff) + pale-cyan delta wings (#d6f6ff).
    setBlendedColor(g, 0.929, 0.980, 1.0, 1, blinkFlash * 0.75, blinkAlpha)
    for _, part in ipairs(SERAPH_CENTER_FILLS) do
        g.polygon("fill", part)
    end
    setBlendedColor(g, 0.839, 0.965, 1.0, 1, blinkFlash * 0.75, blinkAlpha)
    g.polygon("fill", SERAPH_WING_LEFT)
    g.polygon("fill", SERAPH_WING_RIGHT)

    -- 3. Crisp anti-aliased edge highlight around all 3 plates.
    g.setLineWidth(0.75 + blinkFlash * 0.5)
    setBlendedColor(g, 1, 1, 1, 0.76, blinkFlash, blinkAlpha)
    drawSeraphPlates(g, "line")

    g.pop()
end

function Ship:draw(time)
    local g = love.graphics
    local t = time or 0
    local speed = self:speed()
    local boost = self.boostLevel
    local blinkAlpha, blinkFlash = self:invulnBlinkAlpha()

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
        local length = 36 + speed / math.max(1, self.maxSpeed) * 30
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

    -- Twin thrusters aligned with the Delta Seraph tail tabs (x = +-3.0, y = 16.8).
    if boost > 0 then
        local trail = (86 + math.sin(t * 96) * 14) * boost
        g.setColor(0.14, 0.57, 1, boost * 0.20 * blinkAlpha)
        g.ellipse("fill", 0, 22 + trail * 0.30, 15, 13 + trail * 0.62)
        for _, side in ipairs({ -1, 1 }) do
            local nx = side * 3.0
            g.setColor(0.20, 0.72, 1, boost * 0.88 * blinkAlpha)
            g.polygon("fill", nx - 3.6, 16.8, nx, 22 + trail, nx + 3.6, 16.8)
            g.setColor(0.82, 0.99, 1, boost * blinkAlpha)
            g.polygon("fill", nx - 1.8, 16.8, nx, 19 + trail * 0.56, nx + 1.8, 16.8)
            g.setColor(0.48, 0.90, 1, boost * 0.65 * blinkAlpha)
            g.setLineWidth(1.6)
            g.line(side * 10, 18, side * 11, 25 + trail * 0.66)
        end
    elseif self.accelerating then
        local flame = 23 + math.sin(t * 57) * 5 + math.sin(t * 31) * 3
        g.setColor(0.18, 0.74, 1, 0.14 * blinkAlpha)
        g.ellipse("fill", 0, 22 + flame * 0.25, 12, flame * 0.75 + 7)
        for _, side in ipairs({ -1, 1 }) do
            local nx = side * 3.0
            g.setColor(0.16, 0.62, 1, 0.78 * blinkAlpha)
            g.polygon("fill", nx - 2.6, 16.8, nx, 17 + flame, nx + 2.6, 16.8)
            g.setColor(0.48, 0.96, 1, 0.92 * blinkAlpha)
            g.polygon("fill", nx - 1.7, 16.8, nx, 17 + flame * 0.68, nx + 1.7, 16.8)
            g.setColor(0.96, 1, 1, blinkAlpha)
            g.polygon("fill", nx - 1.0, 16.8, nx, 16 + flame * 0.42, nx + 1.0, 16.8)
        end
    end
    g.pop()

    Ship.drawChassis(self.chassisId or "striker", self.x, self.y, self.angle, 1, t, {
        blinkAlpha = blinkAlpha,
        blinkFlash = blinkFlash,
    })

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
