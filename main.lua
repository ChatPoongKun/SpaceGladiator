local Ship = require("ship")
local Arena = require("arena")
local Starfield = require("starfield")
local Camera = require("camera")
local Turret = require("turret")
local Enemies = require("enemies")
local Hud = require("hud")

local ship, stars, fonts, camera, turret, enemies, hud
local width, height, time = 1280, 800, 0
local paused, focused = false, true
local input = { turn = 0, thrust = false, brake = false, boost = false }
local testMode = false
local testCompact, testDamaged = false, false
local captureRequested = false
local mouseX, mouseY, firing = 0, 0, false
local weaponNames = { "PROJECTILE", "MISSILE", "LASER" }
local defaultErrorHandler = love.errorhandler

function love.errorhandler(message)
    if not testMode then return defaultErrorHandler(message) end
    print(debug.traceback("FAIL: " .. tostring(message), 2))
    return function() return 1 end
end

local function reset()
    ship = Ship.new(Arena.width, Arena.height)
    camera = Camera.new(ship.x, ship.y)
    camera:update(0, ship, width, height)
    turret = Turret.new(ship.angle)
    enemies = Enemies.new()
    input.turn, input.thrust, input.brake, input.boost = 0, false, false, false
    firing = false
    paused = false
end

function love.load(args)
    for _, arg in ipairs(args or {}) do
        if arg == "--test" then testMode = true end
        if arg == "--test-compact" then testMode, testCompact = true, true end
        if arg == "--test-damaged" then testMode, testDamaged = true, true end
    end
    love.graphics.setBackgroundColor(0.018, 0.028, 0.055)
    love.graphics.setLineStyle("smooth")
    love.mouse.setVisible(false)
    width, height = love.graphics.getDimensions()
    fonts = {
        small = love.graphics.newFont(11),
        body = love.graphics.newFont(13),
        title = love.graphics.newFont(30),
    }
    hud = Hud.new()
    stars = Starfield.new(width, height)
    reset()
    if testCompact then
        love.window.updateMode(800, 600)
        love.resize(800, 600)
    end
    if testMode then
        require("tests.check")(Ship, Starfield, Camera, Turret, Enemies, Hud)
        -- Exercise the real input, update, and draw callbacks in the arena.
        for frame = 1, 900 do
            if frame == 120 then love.keypressed("space") end
            love.update(1 / 60)
            if frame == 120 then assert(ship.battery == ship.maxBattery - ship.boostCost) end
        end
        if testDamaged then ship.shield, ship.armor, ship.hull, ship.battery = 27, 68, 2, 42 end
    end
end

function love.update(dt)
    if paused or (not focused and not testMode) then return end
    dt = math.min(dt, 1 / 20)
    if dt <= 0 then return end
    time = time + dt
    input.turn = (love.keyboard.isDown("d") and 1 or 0)
        - (love.keyboard.isDown("a") and 1 or 0)
    input.thrust = love.keyboard.isDown("w")
    input.brake = love.keyboard.isDown("s")
    mouseX, mouseY = love.mouse.getPosition()
    firing = love.mouse.isDown(1)
    if testMode then
        input.turn, input.thrust, input.brake = 0.55, true, false
        mouseX, mouseY, firing = width * 0.60, height * 0.24, true
    end
    if ship:isDestroyed() then input.turn, input.thrust, input.brake, input.boost = 0, false, false, false end
    ship:update(dt, input)
    input.boost = false
    camera:update(dt, ship, width, height)
    local surge = 1050 * ship.boostLevel
    stars:update(dt, 120 + ship.vx * 2.8 + ship.boostX * surge,
        -290 + ship.vy * 2.8 + ship.boostY * surge,
        ship.accelerating and 1 or 0, width, height, ship.boostLevel)
    local worldX, worldY = camera:screenToWorld(mouseX, mouseY, width, height)
    enemies:update(dt, ship, turret.angle, camera, width, height)
    firing = firing and not ship:isDestroyed()
    turret:update(dt, ship, worldX, worldY, firing, enemies, camera, width, height)
end

local function label(text, x, y, alpha)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.53, 0.65, 0.75, alpha or 1)
    love.graphics.print(text, x, y)
end

local function keycap(key, text, x, y, active)
    local g = love.graphics
    local keyWidth = key == "SPACE" and 48 or 27
    g.setColor(0.10, 0.19, 0.24, active and 0.95 or 0.45)
    g.rectangle("fill", x, y, keyWidth, 27, 5, 5)
    g.setColor(0.34, 0.70, 0.76, active and 0.9 or 0.24)
    g.rectangle("line", x, y, keyWidth, 27, 5, 5)
    g.setFont(fonts.body)
    g.setColor(0.75, 0.91, 0.96, 1)
    g.printf(key, x, y + 6, keyWidth, "center")
    g.setColor(0.53, 0.65, 0.75, 1)
    g.print(text, x + keyWidth + 9, y + 6)
end

local function drawHud()
    local g = love.graphics
    -- Keep telemetry legible when enemies or explosions pass behind it.
    g.setColor(0.018, 0.028, 0.055, 0.72)
    g.rectangle("fill", 0, 0, width, 104)
    g.setColor(0.25, 0.47, 0.58, 0.16)
    g.setLineWidth(1)
    g.line(32, 103, width - 32, 103)
    g.setFont(fonts.title)
    g.setColor(0.83, 0.93, 0.97, 1)
    g.print("D R I F T", 32, 25)
    label("04  /  TACTICAL FLIGHT", 34, 66)
    local sx = width - 232
    label("HOSTILES  /  DESTROYED", sx, 29)
    g.setFont(fonts.title)
    g.setColor(0.86, 0.91, 0.93, 1)
    g.print(string.format("%02d  /  %03d", #enemies.items, enemies.kills), sx, 46)

    hud:draw(ship, width, height, time)
    local y = height - 183
    label("FLIGHT CONTROLS", 24, y - 12)
    keycap("W", "THRUST", 24, y + 4, ship.accelerating)
    keycap("S", "BRAKE", 24, y + 33, ship.braking)
    keycap("A/D", "ROTATE", 24, y + 62, input.turn ~= 0)
    keycap("SPACE", "BOOST", 24, y + 91, ship.boostLevel > 0)
    keycap("1-3", turret.weapon .. " / " .. weaponNames[turret.weapon], 24, y + 120, true)
    keycap("LMB", "FIRE", 24, y + 149, firing)

    local mode = ship.braking and "BRAKING" or ship.accelerating and "THRUST" or "COAST"
    if ship.boostLevel > 0 then mode = "BOOST" end
    if paused or not focused then mode = "PAUSED" end
    if ship:isDestroyed() then mode = "DESTROYED" end
    local mx = width - 180
    g.setColor(0.38, 0.91, 0.78, 0.85)
    g.circle("fill", mx, y + 14, 3)
    label(mode, mx + 12, y + 8)
    label(string.format("ZOOM  %d%%", math.floor(camera.zoom * 100 + 0.5)), mx - 3, y + 59)
    label("R  RESET     P  PAUSE", mx - 3, height - 63)
    label("ESC  EXIT", mx - 3, height - 41)

    local showDestroyed = ship:isDestroyed() and (ship.destructionAge or 0) >= Ship.destructionDuration
    if showDestroyed or paused or (not focused and not testMode) then
        g.setColor(0.018, 0.028, 0.055, 0.7)
        g.rectangle("fill", 0, height / 2 - 48, width, 96)
        g.setFont(fonts.title)
        g.setColor(0.83, 0.93, 0.97, 1)
        g.printf(showDestroyed and "SHIP DESTROYED" or "PAUSED", 0, height / 2 - 29, width, "center")
        g.setFont(fonts.body)
        g.setColor(0.53, 0.65, 0.75, 1)
        local hint = focused and "Press P to resume flight" or "Return to the window to resume"
        if showDestroyed then hint = "Press R to restart" end
        g.printf(hint, 0, height / 2 + 12, width, "center")
    end
end

local function wrapOffsets(position, extent, reach)
    if position < reach then return {0, extent} end
    if position > extent - reach then return {0, -extent} end
    return {0}
end

local function drawPlayer(originX, originY)
    local g = love.graphics
    g.push("all")
    g.intersectScissor(originX, originY, Arena.width * camera.zoom, Arena.height * camera.zoom)
    local destroyed = ship:isDestroyed()
    if not destroyed then ship:drawBoostPulse() end
    -- Include the longer boost plume when deciding which copies can reach the arena.
    local reach = destroyed and 90 or 75 + 70 * ship.boostLevel
    local xOffsets = wrapOffsets(ship.x, Arena.width, reach)
    local yOffsets = wrapOffsets(ship.y, Arena.height, reach)
    for _, dx in ipairs(xOffsets) do
        for _, dy in ipairs(yOffsets) do
            g.push()
            g.translate(dx, dy)
            if destroyed then
                ship:drawDestruction()
            else
                ship:draw(time)
                turret:drawMount(ship, time)
            end
            g.pop()
        end
    end
    g.pop()
end

function love.draw()
    stars:draw()
    love.graphics.push()
    local originX, originY = camera:worldToScreen(0, 0, width, height)
    love.graphics.translate(originX, originY)
    love.graphics.scale(camera.zoom)
    Arena.draw(ship.boostLevel)
    enemies:draw(time)
    drawPlayer(originX, originY)
    turret:drawEffects(camera, width, height)
    love.graphics.pop()
    drawHud()
    if focused or testMode then
        local g = love.graphics
        local x, y = love.mouse.getPosition()
        if testMode then x, y = mouseX, mouseY end
        g.setLineWidth(1)
        if firing then g.setColor(1, 0.72, 0.36, 0.8)
        else g.setColor(0.48, 0.88, 0.94, 0.7) end
        g.circle("line", x, y, 7)
        g.line(x - 12, y, x - 9, y)
        g.line(x + 9, y, x + 12, y)
        g.line(x, y - 12, x, y - 9)
        g.line(x, y + 9, x, y + 12)
    end
    if testMode and not captureRequested then
        captureRequested = true
        love.graphics.captureScreenshot(function(data)
            local name = testCompact and "hud-compact-preview.png"
                or testDamaged and "hud-damaged-preview.png" or "flight-preview.png"
            local file = assert(io.open(love.filesystem.getSource() .. "/" .. name, "wb"))
            file:write(data:encode("png"):getString())
            file:close()
            print("PASS: update/draw smoke test; " .. name .. " saved")
            love.event.quit(0)
        end)
    end
end

function love.keypressed(key, _, isRepeat)
    if key == "escape" then love.event.quit()
    elseif key == "r" then reset()
    elseif key == "1" or key == "2" or key == "3" then turret.weapon = tonumber(key)
    elseif key == "space" and not isRepeat and not paused and (focused or testMode) and not ship:isDestroyed() then
        input.boost = true
    elseif key == "p" then
        paused = not paused
        input.boost = false
    end
end

function love.focus(hasFocus)
    focused = hasFocus
    if not focused then input.boost = false end
end

function love.resize(w, h)
    width, height = w, h
    stars:resize(w, h)
    camera:update(0, ship, w, h)
end
