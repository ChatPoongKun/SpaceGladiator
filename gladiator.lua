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
Gladiator.popupDuration = 1.05
Gladiator.popupRise = 26
Gladiator.hitLockoutDuration = 0.6
Gladiator.missileSettleDuration = 0.25

local categoryInfo = {
    destroy = { label = "DESTROY", color = { 1.0, 0.58, 0.32 } },
    missileDodge = { marginKey = "missileMargin", label = "MISSILE DODGE", color = { 0.42, 0.90, 1.0 } },
    aerobatics = { marginKey = "aerobaticsMargin", label = "AEROBATICS", color = { 1.0, 0.85, 0.38 } },
}

function Gladiator.new()
    return setmetatable({
        total = 0,
        destroy = { points = 0, count = 0 },
        missileDodge = { points = 0, count = 0 },
        aerobatics = { points = 0, count = 0 },
        lastEvent = nil,
        popups = {},
        damageEpoch = 0,
        lastDamageCount = nil,
        evasionLockout = 0,
        missileSituation = nil,
        pendingEvasions = nil,
        batchEpoch = nil,
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

function Gladiator:spawnPopup(category, points, x, y)
    if not x or not y or not points or points <= 0 then return end
    local px, py = x, y
    for _, existing in ipairs(self.popups) do
        if existing.age < 0.45 and math.abs(existing.x - px) < 42 and math.abs(existing.y - py) < 22 then
            py = existing.y - 22
        end
    end
    self.popups[#self.popups + 1] = {
        category = category,
        points = points,
        x = px,
        y = py,
        age = 0,
        duration = self.popupDuration,
    }
end

function Gladiator:award(category, points, label, x, y)
    if not points or points <= 0 then return 0 end
    local bucket = self[category]
    bucket.points = bucket.points + points
    bucket.count = bucket.count + 1
    self.total = self.total + points
    self.lastEvent = { category = category, points = points, label = label, age = 0 }
    self:spawnPopup(category, points, x, y)
    return points
end

function Gladiator:recordDestroy(enemyPower, playerPower, x, y)
    local points = Gladiator.killPoints(enemyPower, playerPower)
    return self:award("destroy", points, "DESTROY", x, y)
end

function Gladiator:recordMissileDodge(clearance, relativeSpeed, x, y)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.missileMargin, relativeSpeed)
    return self:award("missileDodge", points, "MISSILE DODGE", x, y)
end

function Gladiator:recordAerobatics(clearance, relativeSpeed, x, y)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.aerobaticsMargin, relativeSpeed)
    return self:award("aerobatics", points, "AEROBATICS", x, y)
end

function Gladiator:onPlayerDamaged()
    self.damageEpoch = self.damageEpoch + 1
    self.evasionLockout = math.max(self.evasionLockout, self.hitLockoutDuration)
    self.missileSituation = nil
    if self.pendingEvasions then
        self.pendingEvasions = {}
    end
end

function Gladiator:syncPlayerDamage(ship)
    if not ship then return end
    local count = ship.damageCount or 0
    if self.lastDamageCount == nil then
        self.lastDamageCount = count
    elseif count > self.lastDamageCount then
        self.lastDamageCount = count
        self:onPlayerDamaged()
    end
end

function Gladiator:observeMissileThreat(clearance, relativeSpeed, x, y)
    if self.evasionLockout > 0 then
        self.missileSituation = nil
        return false
    end
    if not clearance or clearance <= 0 or clearance > self.missileMargin then
        return false
    end
    local speed = relativeSpeed or 0
    if speed < self.minRelativeSpeed then
        if self.missileSituation then self.missileSituation.quietTime = 0 end
        return true
    end
    local sit = self.missileSituation
    if not sit or sit.epoch ~= self.damageEpoch then
        self.missileSituation = {
            minClearance = clearance,
            relativeSpeed = speed,
            x = x,
            y = y,
            epoch = self.damageEpoch,
            quietTime = 0,
        }
    else
        sit.quietTime = 0
        if clearance < sit.minClearance
            or (clearance == sit.minClearance and speed > sit.relativeSpeed) then
            sit.minClearance = clearance
            sit.relativeSpeed = speed
            sit.x, sit.y = x, y
        end
    end
    return true
end

function Gladiator:advanceMissileSituation(dt, ship, threatened)
    self:syncPlayerDamage(ship)
    local sit = self.missileSituation
    if not sit then return 0 end
    if (ship and ship:isDestroyed()) or sit.epoch ~= self.damageEpoch or self.evasionLockout > 0 then
        self.missileSituation = nil
        return 0
    end
    if threatened then
        sit.quietTime = 0
        return 0
    end
    sit.quietTime = sit.quietTime + math.max(0, dt)
    if sit.quietTime < self.missileSettleDuration then
        return 0
    end
    self.missileSituation = nil
    if self.pendingEvasions then
        self.pendingEvasions[#self.pendingEvasions + 1] = {
            category = "missileDodge",
            clearance = sit.minClearance,
            relativeSpeed = sit.relativeSpeed,
            x = sit.x,
            y = sit.y,
        }
        return 0
    end
    return self:recordMissileDodge(sit.minClearance, sit.relativeSpeed, sit.x, sit.y)
end

function Gladiator:beginEvasionBatch(ship)
    self:syncPlayerDamage(ship)
    self.pendingEvasions = {}
    self.batchEpoch = self.damageEpoch
end

function Gladiator:endEvasionBatch(ship)
    self:syncPlayerDamage(ship)
    local pending = self.pendingEvasions
    local batchEpoch = self.batchEpoch
    self.pendingEvasions = nil
    self.batchEpoch = nil
    if not pending or #pending == 0 then return end
    if (ship and ship:isDestroyed()) or self.damageEpoch ~= batchEpoch or self.evasionLockout > 0 then
        return
    end
    for _, item in ipairs(pending) do
        if item.category == "missileDodge" then
            self:recordMissileDodge(item.clearance, item.relativeSpeed, item.x, item.y)
        else
            self:recordAerobatics(item.clearance, item.relativeSpeed, item.x, item.y)
        end
    end
end

function Gladiator:finishNearMiss(entity, category, x, y)
    local nearMiss = entity.nearMiss
    entity.nearMiss = nil
    if not nearMiss or nearMiss.collided then return 0 end
    if nearMiss.epoch ~= self.damageEpoch or self.evasionLockout > 0 then return 0 end
    local px, py = nearMiss.x or x, nearMiss.y or y
    if self.pendingEvasions then
        self.pendingEvasions[#self.pendingEvasions + 1] = {
            category = category,
            clearance = nearMiss.minClearance,
            relativeSpeed = nearMiss.relativeSpeed,
            x = px,
            y = py,
        }
        return 0
    end
    if category == "missileDodge" then
        return self:recordMissileDodge(nearMiss.minClearance, nearMiss.relativeSpeed, px, py)
    end
    return self:recordAerobatics(nearMiss.minClearance, nearMiss.relativeSpeed, px, py)
end

function Gladiator:trackNearMiss(entity, minDistance, endDistance, hitRadius, relativeSpeed, category, collided, x, y)
    local info = categoryInfo[category]
    local margin = self[info.marginKey]
    local exitDistance = hitRadius + margin + self.exitHysteresis

    if collided or minDistance <= hitRadius + 1e-6 or self.evasionLockout > 0 then
        entity.nearMiss = endDistance > exitDistance and nil or { collided = true }
        return 0
    end

    local nearMiss = entity.nearMiss
    if nearMiss and (nearMiss.collided or nearMiss.epoch ~= self.damageEpoch) then
        if endDistance > exitDistance then
            entity.nearMiss = nil
        else
            entity.nearMiss = { collided = true }
        end
        return 0
    end

    local clearance = minDistance - hitRadius
    if clearance > 0 and clearance <= margin then
        if not nearMiss then
            nearMiss = {
                minClearance = clearance,
                relativeSpeed = relativeSpeed or 0,
                x = x,
                y = y,
                epoch = self.damageEpoch,
            }
            entity.nearMiss = nearMiss
        elseif clearance < nearMiss.minClearance then
            nearMiss.minClearance = clearance
            nearMiss.relativeSpeed = relativeSpeed or 0
            nearMiss.x, nearMiss.y = x, y
        elseif clearance == nearMiss.minClearance and (relativeSpeed or 0) > nearMiss.relativeSpeed then
            nearMiss.relativeSpeed = relativeSpeed
            nearMiss.x, nearMiss.y = x, y
        end
    end

    if nearMiss and endDistance > exitDistance then
        return self:finishNearMiss(entity, category, x, y)
    end
    return 0
end

function Gladiator:update(dt)
    if dt <= 0 then return end
    if self.evasionLockout > 0 then
        self.evasionLockout = math.max(0, self.evasionLockout - dt)
    end
    if self.lastEvent then
        self.lastEvent.age = self.lastEvent.age + dt
        if self.lastEvent.age >= self.noticeDuration then
            self.lastEvent = nil
        end
    end
    for i = #self.popups, 1, -1 do
        local popup = self.popups[i]
        popup.age = popup.age + dt
        if popup.age >= popup.duration then
            table.remove(self.popups, i)
        end
    end
end

local function drawPopupIcon(g, category, cx, cy, color, alpha)
    local r, gr, b = color[1], color[2], color[3]
    if category == "destroy" then
        g.setColor(r, gr, b, alpha)
        g.setLineWidth(1.2)
        g.circle("line", cx, cy, 3.5)
        g.line(cx - 5.2, cy, cx - 2.3, cy)
        g.line(cx + 2.3, cy, cx + 5.2, cy)
        g.line(cx, cy - 5.2, cx, cy - 2.3)
        g.line(cx, cy + 2.3, cx, cy + 5.2)
    elseif category == "missileDodge" then
        g.setColor(1.0, 0.42, 0.36, alpha)
        g.polygon("fill", cx + 4.4, cy - 4.0, cx - 2.4, cy - 1.0, cx + 0.6, cy + 2.0)
        g.setColor(r, gr, b, alpha)
        g.setLineWidth(1.3)
        g.arc("line", "open", cx - 0.8, cy + 0.8, 4.9, math.pi * 0.15, math.pi * 1.15)
    else
        g.setColor(r, gr, b, alpha)
        g.setLineWidth(1.4)
        g.line(cx - 4.5, cy + 0.6, cx, cy - 4.0, cx + 4.5, cy + 0.6)
        g.setLineWidth(1.1)
        g.line(cx - 3.3, cy + 4.0, cx, cy + 0.2, cx + 3.3, cy + 4.0)
    end
end

function Gladiator:drawPopups(camera, width, height, font)
    if #self.popups == 0 then return end
    local g = love.graphics
    g.push("all")
    g.origin()
    g.setLineStyle("smooth")
    if font then g.setFont(font) end
    local activeFont = g.getFont()
    local textH = activeFont:getHeight()
    local iconSize, gap = 10, 4

    for _, popup in ipairs(self.popups) do
        local t = math.max(0, math.min(1, popup.age / popup.duration))
        local alpha = t < 0.12 and (t / 0.12) or (t > 0.62 and (1 - t) / 0.38 or 1)
        local rise = self.popupRise * (1 - (1 - t) * (1 - t))
        local sx, sy = popup.x, popup.y
        if camera then
            sx, sy = camera:worldToScreen(popup.x, popup.y, width, height)
        end
        sy = sy - rise

        local info = categoryInfo[popup.category] or categoryInfo.aerobatics
        local color = info.color
        local text = "+" .. tostring(popup.points)
        local textW = activeFont:getWidth(text)
        local totalW = iconSize + gap + textW
        local left = math.floor(sx - totalW * 0.5)
        local centerY = math.floor(sy)
        local iconX = left + iconSize * 0.5
        local textX = left + iconSize + gap
        local textY = math.floor(centerY - textH * 0.5)

        -- Subtle drop shadow keeps floating numbers legible over explosions and bright lines.
        drawPopupIcon(g, popup.category, iconX + 1, centerY + 1, { 0.02, 0.03, 0.06 }, alpha * 0.7)
        drawPopupIcon(g, popup.category, iconX, centerY, color, alpha)

        g.setColor(0.02, 0.03, 0.06, alpha * 0.8)
        g.print(text, textX + 1, textY + 1)
        g.setColor(color[1], color[2], color[3], alpha)
        g.print(text, textX, textY)
    end
    g.pop()
end

return Gladiator
