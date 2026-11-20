local Camera = {}
Camera.__index = Camera

Camera.lagBelow = 180
Camera.leadAbove = 550
Camera.lagSeconds = 0.24
Camera.leadSeconds = 0.15
Camera.response = 6.5
Camera.velocityLeadFraction = 0.26
Camera.mouseLeadFraction = 0.10
Camera.mouseDeadZone = 0.10
Camera.mouseDistanceForMax = 0.30
Camera.mouseLeadTime = 1.5
Camera.zoomOutStart = 420
Camera.zoomOutFull = 700
Camera.minZoom = 0.85
Camera.zoomResponse = 2.5

local function clampOffset(x, y, limitX, limitY)
    local length = math.sqrt((x / limitX) ^ 2 + (y / limitY) ^ 2)
    if length > 1 then return x / length, y / length end
    return x, y
end

function Camera.new(x, y)
    return setmetatable({
        x = x, y = y, zoom = 1, offsetX = 0, offsetY = 0,
        velocityOffsetX = 0, velocityOffsetY = 0,
        mouseOffsetX = 0, mouseOffsetY = 0,
    }, Camera)
end

function Camera:update(dt, ship, width, height, mouseX, mouseY)
    local speed = ship:speed()
    local zoomBlend = math.max(0, math.min(1,
        (speed - self.zoomOutStart) / (self.zoomOutFull - self.zoomOutStart)))
    zoomBlend = zoomBlend * zoomBlend * (3 - 2 * zoomBlend)
    local targetZoom = 1 + (self.minZoom - 1) * zoomBlend
    self.zoom = self.zoom + (targetZoom - self.zoom) * (1 - math.exp(-self.zoomResponse * dt))

    local blend = math.max(0, math.min(1,
        (speed - self.lagBelow) / (self.leadAbove - self.lagBelow)))
    blend = blend * blend * (3 - 2 * blend)
    local seconds = -self.lagSeconds + (self.lagSeconds + self.leadSeconds) * blend
    local limit = math.min(width, height) * self.velocityLeadFraction / self.zoom
    local targetX, targetY = clampOffset(ship.vx * seconds, ship.vy * seconds, limit, limit)
    local smoothing = 1 - math.exp(-self.response * dt)
    self.velocityOffsetX = self.velocityOffsetX + (targetX - self.velocityOffsetX) * smoothing
    self.velocityOffsetY = self.velocityOffsetY + (targetY - self.velocityOffsetY) * smoothing
    self.velocityOffsetX, self.velocityOffsetY = clampOffset(
        self.velocityOffsetX, self.velocityOffsetY, limit, limit)

    -- Use the ship's visible position, including both offsets and the current zoom.
    local playerX = width / 2 - (self.velocityOffsetX + self.mouseOffsetX) * self.zoom
    local playerY = height / 2 - (self.velocityOffsetY + self.mouseOffsetY) * self.zoom
    targetX, targetY = mouseX - playerX, mouseY - playerY
    local distance = math.sqrt(targetX * targetX + targetY * targetY)
    local fraction = math.max(0, math.min(1,
        (distance / width - self.mouseDeadZone) / (self.mouseDistanceForMax - self.mouseDeadZone)))
    local mouseLimit = width * self.mouseLeadFraction / self.zoom
    if distance > 0 then
        local scale = mouseLimit * fraction / distance
        targetX, targetY = targetX * scale, targetY * scale
    end
    -- The mouse contribution reaches about 95% of its target in mouseLeadTime seconds.
    smoothing = 1 - math.exp(-3 * dt / self.mouseLeadTime)
    self.mouseOffsetX = self.mouseOffsetX + (targetX - self.mouseOffsetX) * smoothing
    self.mouseOffsetY = self.mouseOffsetY + (targetY - self.mouseOffsetY) * smoothing
    self.mouseOffsetX, self.mouseOffsetY = clampOffset(self.mouseOffsetX, self.mouseOffsetY,
        mouseLimit, mouseLimit)

    self.offsetX = self.velocityOffsetX + self.mouseOffsetX
    self.offsetY = self.velocityOffsetY + self.mouseOffsetY
    self.x, self.y = ship.x + self.offsetX, ship.y + self.offsetY
end

function Camera:screenToWorld(x, y, width, height)
    return (x - width / 2) / self.zoom + self.x, (y - height / 2) / self.zoom + self.y
end

function Camera:worldToScreen(x, y, width, height)
    return (x - self.x) * self.zoom + width / 2, (y - self.y) * self.zoom + height / 2
end

local function axisInterval(origin, direction, size)
    if direction == 0 then
        if origin < 0 or origin > size then return math.huge, -math.huge end
        return -math.huge, math.huge
    end
    local a, b = -origin / direction, (size - origin) / direction
    return math.min(a, b), math.max(a, b)
end

function Camera:clipRay(x, y, dx, dy, width, height)
    local sx, sy = self:worldToScreen(x, y, width, height)
    local nearX, farX = axisInterval(sx, dx, width)
    local nearY, farY = axisInterval(sy, dy, height)
    local entry, exit = math.max(0, nearX, nearY), math.min(farX, farY)
    if entry < exit then return entry / self.zoom, exit / self.zoom end
end

return Camera
