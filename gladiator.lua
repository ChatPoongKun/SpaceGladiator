local Gladiator = {}
Gladiator.__index = Gladiator

Gladiator.killBase = 10
Gladiator.evasionBase = 10
Gladiator.missileMargin = 45
Gladiator.aerobaticsMargin = 55
Gladiator.exitHysteresis = 10
Gladiator.minRelativeSpeed = 20
Gladiator.referenceSpeed = 250
Gladiator.noticeDuration = 1.6

local categoryInfo = {
    missileDodge = { marginKey = "missileMargin", label = "MISSILE DODGE" },
    aerobatics = { marginKey = "aerobaticsMargin", label = "AEROBATICS" },
}

function Gladiator.new()
    return setmetatable({
        total = 0,
        destroy = { points = 0, count = 0 },
        missileDodge = { points = 0, count = 0 },
        aerobatics = { points = 0, count = 0 },
        lastEvent = nil,
    }, Gladiator)
end

function Gladiator.killPoints(enemyPower, playerPower)
    if not enemyPower or enemyPower <= 0 or not playerPower or playerPower <= 0 then
        return 0
    end
    return math.max(1, math.floor(Gladiator.killBase * (enemyPower / playerPower) + 0.5))
end

function Gladiator.evasionPoints(clearance, margin, relativeSpeed)
    if not clearance or not margin or margin <= 0 or clearance < 0 or clearance > margin then
        return 0
    end
    local closeness = math.max(0, math.min(1, 1 - clearance / margin))
    local speedRatio = math.max(0, (relativeSpeed or 0) / Gladiator.referenceSpeed)
    local multiplier = 1 + closeness * 0.8 + speedRatio * 0.4 + closeness * speedRatio * 0.8
    return math.max(Gladiator.evasionBase, math.floor(Gladiator.evasionBase * multiplier + 0.5))
end

function Gladiator:award(category, points, label)
    if not points or points <= 0 then return 0 end
    local bucket = self[category]
    bucket.points = bucket.points + points
    bucket.count = bucket.count + 1
    self.total = self.total + points
    self.lastEvent = { category = category, points = points, label = label, age = 0 }
    return points
end

function Gladiator:recordDestroy(enemyPower, playerPower)
    local points = Gladiator.killPoints(enemyPower, playerPower)
    return self:award("destroy", points, "DESTROY")
end

function Gladiator:recordMissileDodge(clearance, relativeSpeed)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.missileMargin, relativeSpeed)
    return self:award("missileDodge", points, "MISSILE DODGE")
end

function Gladiator:recordAerobatics(clearance, relativeSpeed)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.aerobaticsMargin, relativeSpeed)
    return self:award("aerobatics", points, "AEROBATICS")
end

function Gladiator:finishNearMiss(entity, category)
    local nearMiss = entity.nearMiss
    entity.nearMiss = nil
    if not nearMiss or nearMiss.collided then return 0 end
    if category == "missileDodge" then
        return self:recordMissileDodge(nearMiss.minClearance, nearMiss.relativeSpeed)
    end
    return self:recordAerobatics(nearMiss.minClearance, nearMiss.relativeSpeed)
end

function Gladiator:trackNearMiss(entity, minDistance, endDistance, hitRadius, relativeSpeed, category, collided)
    local info = categoryInfo[category]
    local margin = self[info.marginKey]
    local exitDistance = hitRadius + margin + self.exitHysteresis

    if collided then
        entity.nearMiss = endDistance > exitDistance and nil or { collided = true }
        return 0
    end

    local nearMiss = entity.nearMiss
    if nearMiss and nearMiss.collided then
        if endDistance > exitDistance then entity.nearMiss = nil end
        return 0
    end

    local clearance = minDistance - hitRadius
    if clearance > 0 and clearance <= margin then
        if not nearMiss then
            nearMiss = { minClearance = clearance, relativeSpeed = relativeSpeed or 0 }
            entity.nearMiss = nearMiss
        elseif clearance < nearMiss.minClearance then
            nearMiss.minClearance = clearance
            nearMiss.relativeSpeed = relativeSpeed or 0
        elseif clearance == nearMiss.minClearance and (relativeSpeed or 0) > nearMiss.relativeSpeed then
            nearMiss.relativeSpeed = relativeSpeed
        end
    end

    if nearMiss and endDistance > exitDistance then
        return self:finishNearMiss(entity, category)
    end
    return 0
end

function Gladiator:update(dt)
    if not self.lastEvent or dt <= 0 then return end
    self.lastEvent.age = self.lastEvent.age + dt
    if self.lastEvent.age >= self.noticeDuration then
        self.lastEvent = nil
    end
end

return Gladiator
