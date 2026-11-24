local Arena = require("src.core.arena")
local Collision = require("src.core.collision")
local Camera = {}
Camera.__index = Camera

function Camera.new(x, y)
    return setmetatable({x = x, y = y, zoom = 1, screenOffsetY = 0, pullback = 0}, Camera)
end

function Camera:update(dt, ship, width, height)
    local fit = math.min(width / Arena.width, height / Arena.height)
    self.screenOffsetY = 0
    local easing = 1 - math.exp(-22 * dt)
    local targetBoost = (type(ship.boostLevel) == "number" and ship.boostLevel == ship.boostLevel) and ship.boostLevel or 0
    if self.pullback ~= self.pullback then self.pullback = 0 end
    self.pullback = self.pullback + (targetBoost - self.pullback) * easing
    self.zoom = fit * (1 - 0.12 * self.pullback)

    local age = ship.boostHold + ship.boostFalloff - ship.boostRemaining
    local shake = math.sin(age * 95) * math.max(0, 1 - age / 0.16) * 5
    self.x = Arena.width / 2 + ship.boostX * self.pullback * 13 - ship.boostY * shake
    self.y = Arena.height / 2 + ship.boostY * self.pullback * 13 + ship.boostX * shake
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
