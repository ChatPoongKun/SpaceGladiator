local Ship = {}
Ship.__index = Ship

Ship.thrust = 350
Ship.brake = 2.8
Ship.maxSpeed = 700
Ship.turnSpeed = 2.8
Ship.radius = 23
Ship.driftThreshold = 150
Ship.driftDeceleration = 200

function Ship.new(width, height)
    return setmetatable({
        x = width / 2, y = height / 2,
        vx = 0, vy = 0, angle = 0,
        accelerating = false, braking = false,
        shield = 100, maxShield = 100,
        armor = 100, maxArmor = 100,
        hull = 100, maxHull = 100,
        battery = 100, maxBattery = 100,
    }, Ship)
end

function Ship:speed()
    return math.sqrt(self.vx * self.vx + self.vy * self.vy)
end

function Ship:update(dt, input)
    self.angle = (self.angle + input.turn * self.turnSpeed * dt) % (2 * math.pi)
    self.accelerating = input.thrust and not input.brake
    self.braking = input.brake

    local oldVx, oldVy = self.vx, self.vy
    if self.braking then
        local damping = math.exp(-self.brake * dt)
        self.vx, self.vy = self.vx * damping, self.vy * damping
        if self:speed() < 0.5 then self.vx, self.vy = 0, 0 end
    elseif self.accelerating then
        self.vx = self.vx + math.sin(self.angle) * self.thrust * dt
        self.vy = self.vy - math.cos(self.angle) * self.thrust * dt
        local speed = self:speed()
        if speed > self.maxSpeed then
            self.vx = self.vx * self.maxSpeed / speed
            self.vy = self.vy * self.maxSpeed / speed
        end
    end

    local speed = self:speed()
    if speed > 0 and speed < self.driftThreshold then
        local remaining = math.max(0, speed - self.driftDeceleration * dt)
        self.vx, self.vy = self.vx * remaining / speed, self.vy * remaining / speed
    end

    -- Average velocity keeps acceleration consistent at different frame rates.
    self.x = self.x + (oldVx + self.vx) * 0.5 * dt
    self.y = self.y + (oldVy + self.vy) * 0.5 * dt
end

function Ship:draw(time)
    local g = love.graphics
    local speed = self:speed()
    if speed > 4 then
        -- The small marker shows momentum, independently of the ship's nose.
        local dx, dy = self.vx / speed, self.vy / speed
        local length = 36 + speed / self.maxSpeed * 30
        local x, y = self.x + dx * length, self.y + dy * length
        g.setLineWidth(1)
        g.setColor(0.40, 0.85, 0.92, 0.23)
        g.line(self.x + dx * 29, self.y + dy * 29, x, y)
        g.circle("line", x, y, 3)
    end

    if self.braking and speed > 1 then
        local pulse = 0.22 + math.sin(time * 18) * 0.08
        g.setColor(0.35, 0.92, 0.91, pulse)
        g.setLineWidth(2)
        g.arc("line", "open", self.x, self.y, 30, time * 2, time * 2 + 4.5)
    end

    g.push()
    g.translate(self.x, self.y)
    g.rotate(self.angle)

    if self.accelerating then
        local flame = 27 + math.sin(time * 57) * 7 + math.sin(time * 31) * 3
        g.setColor(1, 0.40, 0.16, 0.08)
        g.ellipse("fill", 0, 23, 18, flame + 12)
        g.setColor(1, 0.46, 0.16, 0.8)
        g.polygon("fill", -7, 15, 0, 16 + flame, 7, 15)
        g.setColor(1, 0.85, 0.48, 1)
        g.polygon("fill", -4, 15, 0, 29 + flame * 0.3, 4, 15)
        g.setColor(0.92, 1, 1, 1)
        g.polygon("fill", -3, 15, 0, 27, 3, 15)
    end

    for scale = 3, 1, -1 do
        g.setColor(0.26, 0.78, 1, 0.025 * (4 - scale))
        g.push()
        g.scale(1 + scale * 0.12)
        g.polygon("fill", 0, -23, -15, 17, 15, 17)
        g.pop()
    end

    -- Symmetric silhouette: one tip, two equal sides, one flat base.
    g.setColor(0.075, 0.14, 0.20, 1)
    g.polygon("fill", 0, -23, -15, 17, 15, 17)
    g.setColor(0.46, 0.84, 0.91, 0.95)
    g.setLineWidth(1.6)
    g.polygon("line", 0, -23, -15, 17, 15, 17)
    g.setColor(0.75, 0.94, 1, 0.75)
    g.setLineWidth(1)
    g.line(0, -23, 0, 7, -15, 17)
    g.line(0, 7, 15, 17)
    g.setColor(0.36, 0.86, 1, 0.9)
    g.polygon("fill", 0, -11, -4, 1, 4, 1)
    g.setColor(0.58, 0.93, 1, 0.9)
    g.line(-6, 17, 6, 17)
    g.pop()
end

return Ship
