local Starfield = {}
Starfield.__index = Starfield
local tau = math.pi * 2

local function finite(value, fallback)
    if type(value) == "number" and value == value and math.abs(value) < math.huge then
        return value
    end
    return fallback
end

-- rng, when supplied, returns a uniform number in [0, 1].
function Starfield.new(width, height, rng)
    rng = rng or love.math.random
    local self = setmetatable({
        width = math.max(1, finite(width, 1)),
        height = math.max(1, finite(height, 1)),
        time = 0, vx = 0, vy = 0, thrust = 0,
        layers = {
            {count = 120, parallax = .10, size = .60, r = .48, g = .68, b = .92, alpha = .45, stars = {}},
            {count = 70, parallax = .28, size = .95, r = .73, g = .66, b = .96, alpha = .65, stars = {}},
            {count = 36, parallax = .60, size = 1.4, r = .70, g = .92, b = 1, alpha = .90, stars = {}}
        }
    }, Starfield)
    for i = 1, 3 do
        local layer = self.layers[i]
        for j = 1, layer.count do
            layer.stars[j] = {
                x = (rng() * self.width) % self.width,
                y = (rng() * self.height) % self.height,
                size = layer.size * (.75 + rng() * .5),
                phase = rng() * tau,
                rate = 1 + math.floor(rng() * 2)
            }
        end
    end
    return self
end

function Starfield:resize(width, height)
    width = math.max(1, finite(width, self.width))
    height = math.max(1, finite(height, self.height))
    if width == self.width and height == self.height then return end
    for i = 1, 3 do
        local stars = self.layers[i].stars
        for j = 1, #stars do
            local star = stars[j]
            star.x = (star.x / self.width * width) % width
            star.y = (star.y / self.height * height) % height
        end
    end
    self.width, self.height = width, height
end

-- Velocity is in px/s; positive thrust is normalized to [0, 1].
function Starfield:update(dt, vx, vy, acceleration, width, height)
    self:resize(width, height)
    dt = math.max(0, finite(dt, 0))
    self.vx, self.vy = finite(vx, 0), finite(vy, 0)
    self.thrust = math.max(0, math.min(1, finite(acceleration, 0)))
    self.time = (self.time + (dt % (tau / .8)) * .8) % tau
    local response = 1 + .12 * self.thrust
    for i = 1, 3 do
        local layer = self.layers[i]
        local dx = finite(self.vx * layer.parallax * response * dt, 0) % self.width
        local dy = finite(self.vy * layer.parallax * response * dt, 0) % self.height
        for j = 1, #layer.stars do
            local star = layer.stars[j]
            star.x = (star.x - dx) % self.width
            star.y = (star.y - dy) % self.height
        end
    end
end

function Starfield:draw()
    local g = love.graphics
    g.push("all")
    g.origin()
    g.setColor(.018, .025, .065, 1)
    g.rectangle("fill", 0, 0, self.width, self.height)
    g.setLineWidth(1)
    -- Scale before normalizing so zero and extreme velocities stay finite.
    local scale = math.max(1, math.abs(self.vx), math.abs(self.vy))
    local nx, ny = self.vx / scale, self.vy / scale
    local norm = math.sqrt(nx * nx + ny * ny)
    local ux, uy = 0, 0
    if norm > 0 then ux, uy = nx / norm, ny / norm end
    local speed = scale * norm
    for i = 1, 3 do
        local layer = self.layers[i]
        local length = math.min(18, speed * layer.parallax * .025 * (1 + .5 * self.thrust))
        local tx, ty = ux * length, uy * length
        for j = 1, #layer.stars do
            local star = layer.stars[j]
            local alpha = layer.alpha * (.7 + .3 * math.sin(self.time * star.rate + star.phase))
            if length > 1 then
                g.setColor(layer.r, layer.g, layer.b, alpha * .28)
                -- The tail points behind the star's opposite-velocity motion.
                g.line(star.x, star.y, star.x + tx, star.y + ty)
            end
            g.setColor(layer.r, layer.g, layer.b, alpha)
            g.circle("fill", star.x, star.y, star.size, 8)
        end
    end
    g.pop()
end

return Starfield
