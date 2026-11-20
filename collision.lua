local Collision = {}

function Collision.circleEntry(rx, ry, vx, vy, radius)
    local c = rx * rx + ry * ry - radius * radius
    if c <= 0 then return 0 end

    local a, b = vx * vx + vy * vy, rx * vx + ry * vy
    local discriminant = b * b - a * c
    if a > 0 and b < 0 and discriminant >= 0 then
        -- This form of the entry root stays stable close to the hull.
        local t = c / (-b + math.sqrt(discriminant))
        if t <= 1 then return t end
    end
end

local function axisInterval(origin, direction, size)
    if direction == 0 then
        if origin < 0 or origin > size then return math.huge, -math.huge end
        return -math.huge, math.huge
    end
    local a, b = -origin / direction, (size - origin) / direction
    return math.min(a, b), math.max(a, b)
end

function Collision.rectangleInterval(x, y, dx, dy, width, height)
    local nearX, farX = axisInterval(x, dx, width)
    local nearY, farY = axisInterval(y, dy, height)
    return math.max(nearX, nearY), math.min(farX, farY)
end

return Collision
