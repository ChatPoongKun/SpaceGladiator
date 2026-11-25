local Arena = require("src.core.arena")
local Collision = require("src.core.collision")
local Camera = {}
Camera.__index = Camera

function Camera.new(x, y)
    return setmetatable({
        x = x, y = y, zoom = 1, screenOffsetY = 0, pullback = 0,
        shakeAmp = 0, shakeTimer = 0, shakeDuration = 0, shakeTime = 0,
        shakeOffsetX = 0, shakeOffsetY = 0,
    }, Camera)
end

function Camera:addShake(amplitude, duration)
    local currentEffective = 0
    if (self.shakeDuration or 0) > 0 and (self.shakeTimer or 0) > 0 then
        local ratio = self.shakeTimer / self.shakeDuration
        currentEffective = (self.shakeAmp or 0) * ratio * ratio
    end
    self.shakeAmp = math.max(currentEffective, amplitude or 0)
    self.shakeDuration = math.max(duration or 0, self.shakeTimer or 0)
    self.shakeTimer = self.shakeDuration
end

function Camera:shakeIntensity()
    if (self.shakeDuration or 0) <= 0 or (self.shakeTimer or 0) <= 0 then
        return 0
    end
    local ratio = self.shakeTimer / self.shakeDuration
    return math.min(1, ((self.shakeAmp or 0) * ratio * ratio) / 16)
end

function Camera:updateShake(dt, freezeDecay)
    self.shakeTime = (self.shakeTime or 0) + math.max(0, dt or 0)
    if not freezeDecay and (self.shakeTimer or 0) > 0 then
        self.shakeTimer = math.max(0, self.shakeTimer - math.max(0, dt or 0))
    end
    if (self.shakeTimer or 0) <= 0 or (self.shakeDuration or 0) <= 0 or (self.shakeAmp or 0) <= 0 then
        self.shakeAmp, self.shakeOffsetX, self.shakeOffsetY = 0, 0, 0
        return 0, 0
    end
    local falloff = freezeDecay and 1 or (self.shakeTimer / self.shakeDuration) ^ 2
    local mag = self.shakeAmp * falloff
    local t = self.shakeTime
    self.shakeOffsetX = (math.sin(t * 73) * 0.65 + math.cos(t * 131) * 0.35) * mag
    self.shakeOffsetY = (math.cos(t * 89) * 0.65 + math.sin(t * 113) * 0.35) * mag
    return self.shakeOffsetX, self.shakeOffsetY
end

function Camera:update(dt, ship, width, height, opts)
    local fit = math.min(width / Arena.width, height / Arena.height)
    self.screenOffsetY = 0
    local easing = 1 - math.exp(-22 * dt)
    local targetBoost = (type(ship.boostLevel) == "number" and ship.boostLevel == ship.boostLevel) and ship.boostLevel or 0
    if self.pullback ~= self.pullback then self.pullback = 0 end
    self.pullback = self.pullback + (targetBoost - self.pullback) * easing
    self.zoom = fit * (1 - 0.12 * self.pullback)

    local age = ship.boostHold + ship.boostFalloff - ship.boostRemaining
    local shake = math.sin(age * 95) * math.max(0, 1 - age / 0.16) * 5
    local sx, sy = self:updateShake(dt, opts and opts.freezeDecay)
    self.x = Arena.width / 2 + ship.boostX * self.pullback * 13 - ship.boostY * shake + sx
    self.y = Arena.height / 2 + ship.boostY * self.pullback * 13 + ship.boostX * shake + sy
end

function Camera:screenToWorld(x, y, width, height)
    return (x - width / 2) / self.zoom + self.x,
        (y - height / 2 - self.screenOffsetY) / self.zoom + self.y
end

function Camera:worldToScreen(x, y, width, height)
    return (x - self.x) * self.zoom + width / 2,
        (y - self.y) * self.zoom + height / 2 + self.screenOffsetY
end

function Camera:clipRay(x, y, dx, dy, width, height)
    local sx, sy = self:worldToScreen(x, y, width, height)
    local near, exit = Collision.rectangleInterval(sx, sy, dx, dy, width, height)
    local entry = math.max(0, near)
    if entry < exit then return entry / self.zoom, exit / self.zoom end
end

return Camera
