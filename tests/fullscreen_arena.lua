-- Focused verification for full-screen arena expansion and off-screen enemy hit prevention.
local Arena = require("arena")
local Ship = require("ship")
local Camera = require("camera")
local Turret = require("turret")
local Enemies = require("enemies")

local checks = 0
local function check(cond, msg)
    assert(cond, msg)
    checks = checks + 1
end
local function near(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-5)
end
local function target(x, y, radius, prevX, prevY)
    return { x = x, y = y, radius = radius or 10, prevX = prevX or x, prevY = prevY or y }
end

-- 1. Full-screen battlefield expansion across multiple viewport aspect ratios
do
    local prevW, prevH = Arena.width, Arena.height
    for _, vp in ipairs({ {1280, 800}, {1920, 1080}, {2560, 1440}, {800, 600} }) do
        local w, h = vp[1], vp[2]
        Arena.resize(w, h)
        local ship = Ship.new(Arena.width, Arena.height)
        local cam = Camera.new(Arena.width / 2, Arena.height / 2)
        cam:update(0, ship, w, h)
        local left, top = cam:worldToScreen(0, 0, w, h)
        local right, bottom = cam:worldToScreen(Arena.width, Arena.height, w, h)
        check(near(left, 0) and near(top, 0) and near(right, w) and near(bottom, h),
            "Arena must fill the entire screen at " .. w .. "x" .. h)

        -- Boost pullback must keep all arena boundaries visible inside the viewport
        ship.angle = -math.pi / 4
        ship:update(1 / 60, { turn = 0, thrust = false, brake = false, boost = true })
        cam:update(1 / 60, ship, w, h)
        left, top = cam:worldToScreen(0, 0, w, h)
        right, bottom = cam:worldToScreen(Arena.width, Arena.height, w, h)
        check(left >= 0 and top >= 0 and right <= w and bottom <= h,
            "Boost pullback must stay inside viewport at " .. w .. "x" .. h)
    end
    Arena.width, Arena.height = prevW, prevH
end

-- 2. Off-screen enemies cannot be hit by Weapon 1 (projectiles), Weapon 2 (missile blast), Weapon 3 (laser), or homing/ricochet
do
    local w, h = 1280, 800
    Arena.resize(w, h)
    local ship = Ship.new(Arena.width, Arena.height)
    ship.x, ship.y = Arena.width - 40, Arena.height * 0.5
    local cam = Camera.new(Arena.width * 0.5, Arena.height * 0.5)
    cam:update(0, ship, w, h)

    -- 2a. Weapon 1 projectile flying past right screen edge
    local enemies = Enemies.new()
    enemies.items = { target(Arena.width + 12, ship.y, 24), target(Arena.width + 120, ship.y, 24) }
    local turret = Turret.new(math.pi / 2)
    turret.weapon = 1
    turret:fire(ship, Arena.width + 200, ship.y, enemies, 0, cam, w, h)
    for _ = 1, 30 do
        turret:update(1 / 60, ship, Arena.width + 200, ship.y, false, enemies, cam, w, h)
    end
    check(enemies.kills == 0 and #enemies.items == 2,
        "Weapon 1 projectiles must not hit off-screen enemies")

    -- 2b. Weapon 1 projectile still hits on-screen enemies
    local onScreen = target(Arena.width - 10, ship.y, 16)
    enemies.items = { onScreen, target(Arena.width + 30, ship.y, 24) }
    turret = Turret.new(math.pi / 2)
    turret.weapon = 1
    turret:fire(ship, Arena.width - 10, ship.y, enemies, 0, cam, w, h)
    for _ = 1, 10 do
        turret:update(1 / 60, ship, Arena.width - 10, ship.y, false, enemies, cam, w, h)
    end
    check(enemies.kills == 1 and #enemies.items == 1 and enemies.items[1].x == Arena.width + 30,
        "Weapon 1 must hit on-screen enemies while sparing off-screen enemies behind them")

    -- 2c. Weapon 2 missile blast near screen edge
    enemies = Enemies.new()
    local blastOn = target(Arena.width - 20, ship.y, 16)
    local blastOff = target(Arena.width + 15, ship.y, 24)
    enemies.items = { blastOn, blastOff }
    turret = Turret.new(math.pi / 2)
    turret.weapon = 2
    turret:update(0.01, ship, Arena.width - 10, ship.y, true, enemies, cam, w, h)
    for _ = 1, 60 do
        turret:update(1 / 60, ship, Arena.width - 10, ship.y, false, enemies, cam, w, h)
    end
    check(enemies.kills == 1 and #enemies.items == 1 and enemies.items[1] == blastOff,
        "Weapon 2 blast must hit on-screen enemy and spare off-screen enemy inside blast radius")

    -- 2d. Weapon 3 laser aimed at off-screen enemy overlapping screen edge + ricochet off-screen
    enemies = Enemies.new()
    enemies.items = { target(Arena.width + 8, ship.y, 24) }
    turret = Turret.new(math.pi / 2)
    turret.weapon = 3
    turret:update(0.01, ship, Arena.width + 8, ship.y, true, enemies, cam, w, h)
    check(enemies.kills == 0 and #enemies.items == 1,
        "Weapon 3 laser must not hit an enemy whose center is outside the screen")

    -- 2e. Laser ricochet must not bounce to an off-screen enemy
    enemies = Enemies.new()
    local firstOn = target(Arena.width - 12, ship.y, 12)
    local bounceOff = target(Arena.width + 20, ship.y + 40, 20)
    enemies.items = { firstOn, bounceOff }
    turret = Turret.new(math.pi / 2)
    turret.weapon = 3
    turret:fire(ship, Arena.width - 12, ship.y, enemies, 1, cam, w, h, { bounces = 1 })
    check(enemies.kills == 1 and #enemies.items == 1 and enemies.items[1] == bounceOff,
        "Laser ricochet must not hit an off-screen enemy")

    -- 2f. Homing projectile must ignore off-screen enemies
    enemies = Enemies.new()
    enemies.items = { target(Arena.width + 50, ship.y - 120, 20) }
    turret = Turret.new(math.pi / 2)
    turret.weapon = 1
    local homingShot = turret:fire(ship, Arena.width, ship.y, enemies, 0, cam, w, h, { homing = true, homingTurnRate = 10 })
    local initVy = homingShot.vy
    turret:update(0.05, ship, Arena.width, ship.y, false, enemies, cam, w, h)
    check(near(homingShot.vy, initVy),
        "Homing projectile must not steer toward off-screen enemies")
end

print(string.format("PASS: %d full-screen arena and off-screen hit prevention checks", checks))
