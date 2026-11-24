local Sfx = require("src.audio.sfx")
local Gladiator = {}
Gladiator.__index = Gladiator

Gladiator.killBase = 10
Gladiator.evasionBase = 10
Gladiator.missileMargin = 45
Gladiator.aerobaticsMargin = 35
Gladiator.exitHysteresis = 10
Gladiator.minRelativeSpeed = 150
Gladiator.referenceSpeed = 250
Gladiator.noticeDuration = 1.6
Gladiator.popupDuration = 1.05
Gladiator.popupRise = 26
Gladiator.hitLockoutDuration = 0.3
Gladiator.missileSettleDuration = 0.2
Gladiator.feverWindow = 1.0
Gladiator.feverThreshold = 30
Gladiator.feverMinDuration = 5.0
Gladiator.feverSustainRate = 50
Gladiator.feverCooldownDuration = 5.0
Gladiator.feverMultiplier = 2
Gladiator.feverFlashDuration = 0.75

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
        elapsed = 0,
        recentGains = {},
        feverActive = false,
        feverDuration = 0,
        feverPoints = 0,
        feverCooldown = 0,
        feverTotalTime = 0,
        feverMaxDuration = 0,
        feverFlash = 0,
        feverAura = 0,
        feverBursts = {},
        feverSparks = {},
        sparkAccumulator = 0,
        sparkSeed = 0,
        scoreMultiplier = 1,
        evasionCount = 0,
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

function Gladiator:spawnPopup(category, points, x, y, fever)
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
        fever = fever or false,
    }
    return px, py
end

function Gladiator:pruneRecentGains()
    local cutoff = self.elapsed - self.feverWindow - 1e-9
    local write = 1
    for read = 1, #self.recentGains do
        local entry = self.recentGains[read]
        if entry.time >= cutoff then
            self.recentGains[write] = entry
            write = write + 1
        end
    end
    for i = write, #self.recentGains do
        self.recentGains[i] = nil
    end
end

function Gladiator:recentPoints()
    self:pruneRecentGains()
    local sum = 0
    for _, entry in ipairs(self.recentGains) do
        sum = sum + entry.points
    end
    return sum
end

function Gladiator:feverAverageRate()
    if not self.feverActive or self.feverDuration <= 0 then return 0 end
    return self.feverPoints / self.feverDuration
end

function Gladiator:spawnFeverSpark(x, y, vx, vy, duration, size, gold)
    self.feverSparks[#self.feverSparks + 1] = {
        x = x, y = y, vx = vx, vy = vy,
        age = 0, duration = duration, size = size, gold = gold,
    }
end

function Gladiator:startFever(x, y)
    self.feverActive = true
    Sfx.play("fever_start")
    self.feverDuration = 0
    self.feverPoints = 0
    self.recentGains = {}
    self.feverFlash = 1
    local bx, by = x, y
    if bx and by then
        self.feverBursts[#self.feverBursts + 1] = { x = bx, y = by, age = 0, duration = 0.85 }
        for i = 1, 18 do
            local angle = (i / 18) * math.pi * 2 + (i % 2) * 0.14
            local speed = 120 + (i % 3) * 75
            self:spawnFeverSpark(bx, by, math.cos(angle) * speed, math.sin(angle) * speed,
                0.45 + (i % 3) * 0.14, 2.5 + (i % 2) * 1.5, i % 3 ~= 0)
        end
    end
end

function Gladiator:endFever()
    if not self.feverActive then return end
    self.feverMaxDuration = math.max(self.feverMaxDuration, self.feverDuration)
    self.feverActive = false
    self.feverDuration = 0
    self.feverPoints = 0
    self.feverCooldown = self.feverCooldownDuration
    self.recentGains = {}
end

function Gladiator:clearFever()
    if self.feverActive then
        self.feverMaxDuration = math.max(self.feverMaxDuration, self.feverDuration)
    end
    self.feverActive = false
    self.feverDuration = 0
    self.feverPoints = 0
    self.feverCooldown = 0
    self.recentGains = {}
    self.feverFlash = 0
    self.feverAura = 0
    self.feverBursts = {}
    self.feverSparks = {}
    self.sparkAccumulator = 0
end

function Gladiator:award(category, points, label, x, y)
    if not points or points <= 0 then return 0 end
    local isFever = self.feverActive
    local scaled = (self.scoreMultiplier and self.scoreMultiplier ~= 1)
        and math.max(1, math.floor(points * self.scoreMultiplier + 0.5)) or points
    local awarded = isFever and (scaled * self.feverMultiplier) or scaled
    local bucket = self[category]
    bucket.points = bucket.points + awarded
    bucket.count = bucket.count + 1
    self.total = self.total + awarded
    self.lastEvent = { category = category, points = awarded, label = label, age = 0, fever = isFever }
    local px, py = self:spawnPopup(category, awarded, x, y, isFever)
    if self.onAward then
        self.onAward(category, awarded, px or x, py or y, isFever, points)
    end
    if isFever then
        self.feverPoints = self.feverPoints + awarded
    elseif self.feverCooldown <= 0 then
        self.recentGains[#self.recentGains + 1] = { time = self.elapsed, points = awarded }
        if self:recentPoints() >= self.feverThreshold then
            self:startFever(x, y)
        end
    end
    return awarded
end

function Gladiator:recordDestroy(enemyPower, playerPower, x, y)
    local points = Gladiator.killPoints(enemyPower, playerPower)
    return self:award("destroy", points, "DESTROY", x, y)
end

function Gladiator:recordMissileDodge(clearance, relativeSpeed, x, y)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.missileMargin, relativeSpeed)
    local awarded = self:award("missileDodge", points, "MISSILE DODGE", x, y)
    if awarded > 0 then self.evasionCount = (self.evasionCount or 0) + 1; Sfx.play("evasion") end
    return awarded
end

function Gladiator:recordAerobatics(clearance, relativeSpeed, x, y)
    if (relativeSpeed or 0) < self.minRelativeSpeed then return 0 end
    local points = Gladiator.evasionPoints(clearance, self.aerobaticsMargin, relativeSpeed)
    local awarded = self:award("aerobatics", points, "AEROBATICS", x, y)
    if awarded > 0 then self.evasionCount = (self.evasionCount or 0) + 1; Sfx.play("evasion") end
    return awarded
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

function Gladiator:update(dt, ship)
    if dt <= 0 then return end
    self.elapsed = self.elapsed + dt
    if self.evasionLockout > 0 then
        self.evasionLockout = math.max(0, self.evasionLockout - dt)
    end
    if self.feverActive then
        if ship and ship:isDestroyed() then
            self:endFever()
        else
            local endDuration = math.max(self.feverMinDuration, self.feverPoints / self.feverSustainRate)
            if self.feverDuration + dt <= endDuration + 1e-9 then
                self.feverDuration = self.feverDuration + dt
                self.feverTotalTime = self.feverTotalTime + dt
                self.feverMaxDuration = math.max(self.feverMaxDuration, self.feverDuration)
            else
                local activeStep = math.max(0, endDuration - self.feverDuration)
                local leftover = dt - activeStep
                self.feverDuration = self.feverDuration + activeStep
                self.feverTotalTime = self.feverTotalTime + activeStep
                self.feverMaxDuration = math.max(self.feverMaxDuration, self.feverDuration)
                self:endFever()
                self.feverCooldown = math.max(0, self.feverCooldown - leftover)
            end
        end
    elseif self.feverCooldown > 0 then
        self.feverCooldown = math.max(0, self.feverCooldown - dt)
    end
    self:pruneRecentGains()

    if self.feverFlash > 0 then
        self.feverFlash = math.max(0, self.feverFlash - dt / self.feverFlashDuration)
    end
    local targetAura = self.feverActive and 1 or 0
    local auraRate = self.feverActive and 6 or 3
    self.feverAura = self.feverAura + (targetAura - self.feverAura) * math.min(1, dt * auraRate)
    if not self.feverActive and self.feverAura < 0.005 then self.feverAura = 0 end

    if self.feverActive and ship and not ship:isDestroyed() then
        self.sparkAccumulator = self.sparkAccumulator + dt * 36
        while self.sparkAccumulator >= 1 do
            self.sparkAccumulator = self.sparkAccumulator - 1
            self.sparkSeed = self.sparkSeed + 1
            local angle = (self.sparkSeed * 2.399963) % (math.pi * 2)
            local radius = ship:hitRadius() * (0.75 + (self.sparkSeed % 4) * 0.12)
            local sx = ship.x + math.cos(angle) * radius
            local sy = ship.y + math.sin(angle) * radius
            local vx = -ship.vx * 0.35 + math.cos(angle) * 55
            local vy = -ship.vy * 0.35 + math.sin(angle) * 55
            self:spawnFeverSpark(sx, sy, vx, vy, 0.34 + (self.sparkSeed % 3) * 0.08,
                2.0 + (self.sparkSeed % 2), self.sparkSeed % 3 ~= 0)
        end
    else
        self.sparkAccumulator = 0
    end

    for i = #self.feverBursts, 1, -1 do
        local burst = self.feverBursts[i]
        burst.age = burst.age + dt
        if burst.age >= burst.duration then table.remove(self.feverBursts, i) end
    end
    for i = #self.feverSparks, 1, -1 do
        local spark = self.feverSparks[i]
        spark.age = spark.age + dt
        spark.x = spark.x + spark.vx * dt
        spark.y = spark.y + spark.vy * dt
        spark.vx = spark.vx * math.max(0, 1 - dt * 2.4)
        spark.vy = spark.vy * math.max(0, 1 - dt * 2.4)
        if spark.age >= spark.duration then table.remove(self.feverSparks, i) end
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

function Gladiator:updateVisuals(dt)
    if dt <= 0 then return end
    if self.feverFlash > 0 then
        self.feverFlash = math.max(0, self.feverFlash - dt / self.feverFlashDuration)
    end
    if self.feverAura > 0 then
        self.feverAura = self.feverAura * math.max(0, 1 - math.min(1, dt * 3))
        if self.feverAura < 0.005 then self.feverAura = 0 end
    end
    for i = #self.feverBursts, 1, -1 do
        local burst = self.feverBursts[i]
        burst.age = burst.age + dt
        if burst.age >= burst.duration then table.remove(self.feverBursts, i) end
    end
    for i = #self.feverSparks, 1, -1 do
        local spark = self.feverSparks[i]
        spark.age = spark.age + dt
        spark.x = spark.x + spark.vx * dt
        spark.y = spark.y + spark.vy * dt
        spark.vx = spark.vx * math.max(0, 1 - dt * 2.4)
        spark.vy = spark.vy * math.max(0, 1 - dt * 2.4)
        if spark.age >= spark.duration then table.remove(self.feverSparks, i) end
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
        local color = popup.fever and { 1.0, 0.90, 0.44 } or info.color
        local text = popup.fever and ("+" .. tostring(popup.points) .. " x2") or ("+" .. tostring(popup.points))
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

function Gladiator:drawFeverWorld(ship, time)
    if self.feverAura <= 0 and #self.feverBursts == 0 and #self.feverSparks == 0 then return end
    local g = love.graphics
    local t = time or self.elapsed
    g.push("all")
    g.setLineStyle("smooth")

    for _, burst in ipairs(self.feverBursts) do
        local p = math.min(1, burst.age / burst.duration)
        local fade = (1 - p) * (1 - p)
        local outerR = 24 + 210 * (1 - (1 - p) * (1 - p))
        local innerR = 14 + 135 * p
        g.setColor(1.0, 0.78, 0.25, 0.16 * fade)
        g.circle("fill", burst.x, burst.y, innerR * 0.65)
        g.setLineWidth(3.2 * fade + 0.8)
        g.setColor(1.0, 0.88, 0.38, 0.9 * fade)
        g.circle("line", burst.x, burst.y, outerR)
        g.setLineWidth(2.0 * fade + 0.5)
        g.setColor(1.0, 0.34, 0.64, 0.75 * fade)
        g.circle("line", burst.x, burst.y, innerR)
        for i = 0, 11 do
            local angle = i * math.pi / 6 + p * 0.6
            local r1 = innerR * 0.72
            local r2 = outerR * (i % 2 == 0 and 1.06 or 0.88)
            g.setColor(1.0, 0.94, 0.62, 0.75 * fade)
            g.setLineWidth(1.5)
            g.line(burst.x + math.cos(angle) * r1, burst.y + math.sin(angle) * r1,
                burst.x + math.cos(angle) * r2, burst.y + math.sin(angle) * r2)
        end
    end

    for _, spark in ipairs(self.feverSparks) do
        local fade = math.max(0, 1 - spark.age / spark.duration)
        local s = spark.size * (0.4 + 0.6 * fade)
        if spark.gold then
            g.setColor(1.0, 0.88, 0.38, 0.92 * fade)
        else
            g.setColor(1.0, 0.42, 0.72, 0.88 * fade)
        end
        g.polygon("fill",
            spark.x, spark.y - s * 1.4,
            spark.x + s, spark.y,
            spark.x, spark.y + s * 1.4,
            spark.x - s, spark.y)
    end

    if self.feverAura > 0 and ship and not ship:isDestroyed() then
        local aura = self.feverAura
        local pulse = 0.85 + math.sin(t * 14) * 0.15
        local baseR = ship:hitRadius() + 9 + math.sin(t * 10) * 2.5
        g.setColor(1.0, 0.72, 0.22, 0.10 * aura * pulse)
        g.circle("fill", ship.x, ship.y, baseR + 10)
        g.setLineWidth(2.0)
        for i = 0, 3 do
            local start = t * 3.4 + i * (math.pi * 0.5)
            g.setColor(1.0, 0.86, 0.34, 0.82 * aura)
            g.arc("line", "open", ship.x, ship.y, baseR, start, start + 0.95)
        end
        g.setLineWidth(1.4)
        for i = 0, 2 do
            local start = -t * 2.6 + i * (math.pi * 2 / 3)
            g.setColor(1.0, 0.38, 0.68, 0.68 * aura)
            g.arc("line", "open", ship.x, ship.y, baseR + 6, start, start + 1.1)
        end
    end
    g.pop()
end

function Gladiator:drawFeverOverlay(width, height, time)
    if self.feverAura <= 0 and self.feverFlash <= 0 then return end
    local g = love.graphics
    local t = time or self.elapsed
    g.push("all")
    g.setLineStyle("smooth")

    if self.feverFlash > 0 then
        local f = self.feverFlash * self.feverFlash
        g.setColor(1.0, 0.86, 0.36, 0.22 * f)
        g.rectangle("fill", 0, 0, width, height)
    end

    if self.feverAura > 0 then
        local aura = self.feverAura
        local pulse = 0.75 + 0.25 * math.sin(t * 10)
        -- Layered glowing vignette strips along screen edges.
        for band = 1, 3 do
            local thickness = band * 8
            local alpha = (0.14 / band) * aura * pulse
            g.setColor(1.0, 0.68 - band * 0.10, 0.24 + band * 0.12, alpha)
            g.rectangle("fill", 0, 0, width, thickness)
            g.rectangle("fill", 0, height - thickness, width, thickness)
            g.rectangle("fill", 0, thickness, thickness, height - thickness * 2)
            g.rectangle("fill", width - thickness, thickness, thickness, height - thickness * 2)
        end

        g.setLineWidth(2.5)
        g.setColor(1.0, 0.84, 0.34, 0.78 * aura * pulse)
        g.rectangle("line", 5, 5, width - 10, height - 10)
        g.setLineWidth(1.2)
        g.setColor(1.0, 0.38, 0.66, 0.55 * aura)
        g.rectangle("line", 10, 10, width - 20, height - 20)

        -- Animated corner brackets.
        local span = 34 + math.sin(t * 12) * 4
        g.setLineWidth(3)
        g.setColor(1.0, 0.92, 0.52, 0.92 * aura)
        for _, cx in ipairs({ 14, width - 14 }) do
            local sx = cx == 14 and 1 or -1
            for _, cy in ipairs({ 14, height - 14 }) do
                local sy = cy == 14 and 1 or -1
                g.line(cx + sx * span, cy, cx, cy, cx, cy + sy * span)
            end
        end
    end
    g.pop()
end

return Gladiator
