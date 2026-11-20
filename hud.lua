local Hud = {}
Hud.__index = Hud
local pi = math.pi
local cyan = {0.43, 0.87, 0.95}
local amber = {1.00, 0.72, 0.35}
local resources = {
    {"shield", "maxShield", "SHIELD", cyan, 70},
    {"armor", "maxArmor", "ARMOR", {0.91, 0.83, 0.64}, 59},
    {"hull", "maxHull", "HULL", {0.95, 0.54, 0.43}, 48},
}

local function fraction(value, maximum)
    if not maximum or maximum <= 0 then return 0 end
    return math.max(0, math.min(1, (value or 0) / maximum))
end

local function percent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

local function arc(g, x, y, radius, start, sweep, value, color, thickness)
    g.setLineWidth(thickness)
    g.setColor(color[1], color[2], color[3], 0.15)
    g.arc("line", "open", x, y, radius, start, start + sweep)
    -- LÖVE cannot draw an arc whose start and end angles are equal.
    if value > 0 then
        g.setColor(color[1], color[2], color[3], 0.96)
        g.arc("line", "open", x, y, radius, start, start + sweep * value)
    end
end

function Hud.new()
    local g = love.graphics
    return setmetatable({
        small = g.newFont(9), label = g.newFont(11),
        value = g.newFont(17), speed = g.newFont(30),
    }, Hud)
end

function Hud:draw(ship, width, height, time)
    local g = love.graphics
    local x, y = math.floor(width / 2), height - 105
    local speed = math.max(0, ship:speed())
    local velocity = fraction(speed, ship.maxSpeed)
    local battery = fraction(ship.battery, ship.maxBattery)
    g.push("all")
    g.origin()
    g.setShader()
    g.setScissor()
    g.setBlendMode("alpha")
    g.setLineStyle("smooth")
    g.setLineWidth(1)

    -- Clipped wings leave room for the parent's controls and flight status.
    for _, side in ipairs({-1, 1}) do
        local points = {
            x + side * 72, y - 62, x + side * 175, y - 62,
            x + side * 189, y - 48, x + side * 189, y + 48,
            x + side * 175, y + 62, x + side * 72, y + 62,
        }
        g.setColor(0.025, 0.047, 0.074, 0.94)
        g.polygon("fill", points)
        g.setColor(0.32, 0.56, 0.67, 0.30)
        g.polygon("line", points)
    end
    g.setColor(0.018, 0.035, 0.059, 0.97)
    g.circle("fill", x, y, 82)
    g.setColor(0.32, 0.56, 0.67, 0.38)
    g.circle("line", x, y, 82)

    -- Fine ticks frame the upper health arcs; the lower opening is velocity.
    for i = 0, 24 do
        local angle = pi * 5 / 6 + pi * 4 / 3 * i / 24
        local inner = i % 4 == 0 and 74 or 76
        g.setColor(0.53, 0.72, 0.80, i % 4 == 0 and 0.55 or 0.24)
        g.line(x + math.cos(angle) * inner, y + math.sin(angle) * inner,
            x + math.cos(angle) * 79, y + math.sin(angle) * 79)
    end
    for i, resource in ipairs(resources) do
        local value = fraction(ship[resource[1]], ship[resource[2]])
        local color, row = resource[4], y - 54 + (i - 1) * 38
        arc(g, x, y, resource[5], pi * 5 / 6, pi * 4 / 3, value, color, 5)
        g.setColor(color[1], color[2], color[3], 1)
        g.rectangle("fill", x - 176, row + 4, 2, 7)
        g.setFont(self.label)
        g.print(resource[3], x - 168, row)
        g.setFont(self.value)
        g.setColor(0.89, 0.95, 0.98, 1)
        g.print(percent(value), x - 168, row + 12)
    end

    -- World velocity is read directly; camera zoom never changes the readout.
    g.setLineWidth(1)
    g.setColor(0.034, 0.067, 0.095, 1)
    g.circle("fill", x, y, 39)
    g.setColor(0.39, 0.68, 0.76, 0.20)
    g.circle("line", x, y, 39)
    g.setFont(self.small)
    g.setColor(0.57, 0.73, 0.81, 1)
    g.printf("VELOCITY", x - 38, y - 31, 76, "center")
    g.setFont(self.speed)
    g.setColor(0.85, 0.97, 1, 1)
    g.printf(tostring(math.floor(speed + 0.5)), x - 47, y - 24, 94, "center")
    g.setFont(self.label)
    g.setColor(cyan[1], cyan[2], cyan[3], 1)
    g.printf("PX/S", x - 38, y + 12, 76, "center")
    arc(g, x, y, 66, pi / 6, pi * 2 / 3, velocity, cyan, 4)
    g.setFont(self.small)
    g.setColor(0.66, 0.82, 0.88, 1)
    g.printf(ship.boostLevel > 0 and "BOOST" or percent(velocity) .. " MAX", x - 38, y + 45, 76, "center")

    -- A separate segmented capacitor keeps energy distinct from defenses.
    local bx, by = x + 136, y + 13
    g.setFont(self.label)
    g.setColor(amber[1], amber[2], amber[3], 1)
    g.printf("BATTERY", x + 88, y - 51, 96, "center")
    g.setFont(self.small)
    g.setColor(0.64, 0.73, 0.78, 1)
    local batteryStatus = ship.boostLevel > 0 and "DISCHARGING"
        or ship.battery >= ship.boostCost and "BOOST READY" or "RECHARGING"
    g.printf(batteryStatus, x + 88, y - 35, 96, "center")
    for i = 0, 23 do
        local start = pi * 3 / 4 + i * pi / 16
        local charge = math.max(0, math.min(1, battery * 24 - i))
        arc(g, bx, by, 29, start, pi / 16 - 0.045, charge, amber, 5)
    end
    g.setFont(self.value)
    g.setColor(1, 0.87, 0.64, 1)
    g.printf(percent(battery), bx - 31, by - 10, 62, "center")
    g.setLineWidth(1)
    g.setColor(0.42, 0.65, 0.73, 0.3)
    g.line(bx - 21, by + 40, bx + 21, by + 40)
    g.setColor(amber[1], amber[2], amber[3], 0.65 + math.sin((time or 0) * 2) * 0.12)
    g.circle("fill", bx, by + 40, 2)
    g.pop()
end

return Hud
