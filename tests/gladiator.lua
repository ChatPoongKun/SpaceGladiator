return function(Ship, Enemies, Turret, Gladiator)
    local Arena = require("arena")
    local dt = 1 / 60
    local checks = 0
    local function check(condition, message)
        assert(condition, message)
        checks = checks + 1
    end

    -- 1. Formula checks: enemy destruction scales by enemyPower / playerPower from base 10.
    check(Gladiator.killPoints(100, 100) == 10, "Equal combat power must award the base 10 points")
    check(Gladiator.killPoints(40, 100) == 4, "Weaker WEDGE enemy must award proportionally fewer points")
    check(Gladiator.killPoints(70, 100) == 7, "Medium EQUILATERAL enemy must award 7 points against default player")
    check(Gladiator.killPoints(200, 100) == 20, "Stronger enemy must award more than 10 points")
    check(Gladiator.killPoints(40, 200) < Gladiator.killPoints(40, 100),
        "Increasing player combat power must reduce points gained from the same enemy")
    check(Enemies.types[1].combatPower < Enemies.types[2].combatPower
        and Enemies.types[2].combatPower < Enemies.types[3].combatPower,
        "Enemy types must have ascending combat power")

    -- 2. Formula checks: evasion starts at base 10 and increases with relative speed and closeness.
    local baseEdge = Gladiator.evasionPoints(Gladiator.missileMargin, Gladiator.missileMargin, 0)
    local closer = Gladiator.evasionPoints(5, Gladiator.missileMargin, 200)
    local wider = Gladiator.evasionPoints(35, Gladiator.missileMargin, 200)
    local faster = Gladiator.evasionPoints(15, Gladiator.missileMargin, 600)
    local slower = Gladiator.evasionPoints(15, Gladiator.missileMargin, 150)
    check(baseEdge == 10, "Outer edge at zero speed must equal base 10 points")
    check(closer > wider and wider >= 10, "Narrower collision avoidance must award higher points")
    check(faster > slower and slower >= 10, "Higher relative speed must award higher points")
    check(Gladiator.evasionPoints(Gladiator.missileMargin + 1, Gladiator.missileMargin, 500) == 0,
        "Clearance outside the margin must award zero points")

    -- 3. Integration: destroying enemies awards points by enemy combatPower / player combatPower.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        group:spawn(ship, 1, { x = 300, y = 270 })
        group:spawn(ship, 2, { x = 400, y = 270 })
        group:spawn(ship, 3, { x = 500, y = 270 })
        group:update(dt, ship)

        local before = gladiator.destroy.points
        group:destroy(1)
        local wedgePts = gladiator.destroy.points - before
        before = gladiator.destroy.points
        group:destroy(1)
        local eqPts = gladiator.destroy.points - before
        before = gladiator.destroy.points
        group:destroy(1)
        local obtusePts = gladiator.destroy.points - before

        check(wedgePts == 4 and eqPts == 7 and obtusePts == 10,
            "Destroying WEDGE, EQUILATERAL, and OBTUSE must award 4, 7, and 10 points respectively")
        check(gladiator.destroy.count == 3 and gladiator.total == 21,
            "Gladiator total and destroy count must reflect all kills")
    end

    -- Helper to simulate a single OBTUSE missile passing the player at a controlled clearance and relative speed.
    local function runMissilePass(clearance, shipVx, hit)
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local launcher = group:spawn(ship, 3, { x = 200, y = 270 })
        group.fire:shoot(launcher, ship)
        local rocket = group.fire.shots[1]
        group.fire.shots = { rocket }

        -- Configure a clean straight second-leg path past the player so clearance and speed are exact.
        local hitDist = ship:hitRadius() + rocket.profile.radius
        local offsetY = hit and 0 or (hitDist + clearance)
        local speed, turnRate = 350, 3.35
        local radius = speed / turnRate
        local startX, endX = ship.x - 100, ship.x + 420
        rocket.x, rocket.y = startX, ship.y + offsetY
        rocket.vx, rocket.vy = speed, 0
        rocket.age = 0
        rocket.secondLeg = {
            direction = 1, radius = radius, speed = speed, started = 0,
            ramp = 0, sweep = 0, length = (endX - startX) / radius,
            startX = startX, startY = ship.y + offsetY, heading = 0,
            cx = startX, cy = ship.y + offsetY, radial = 0,
            exitHeading = 0, exitX = startX, exitY = ship.y + offsetY,
            x = endX, y = ship.y + offsetY,
        }
        rocket.lifetime = (endX - startX) / speed

        local steps = math.ceil((rocket.lifetime + Gladiator.missileSettleDuration) / dt) + 2
        for _ = 1, steps do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = (ship.x + shipVx * dt) % Arena.width
            group.fire:update(dt, ship, gladiator)
        end
        return gladiator, ship
    end

    -- 4. Missile dodge: narrower clearance and faster relative speed yield more points; hits yield zero.
    do
        local closeG = runMissilePass(4, 0, false)
        local wideG = runMissilePass(36, 0, false)
        local fastG = runMissilePass(12, -260, false)
        local slowG = runMissilePass(12, 180, false)
        local hitG, hitShip = runMissilePass(0, 0, true)

        check(closeG.missileDodge.count == 1 and wideG.missileDodge.count == 1,
            "Each narrowly dodged missile must register once")
        check(closeG.missileDodge.points > wideG.missileDodge.points and wideG.missileDodge.points >= 10,
            "Closer missile dodge must award more points than a wider pass")
        check(fastG.missileDodge.points > slowG.missileDodge.points and slowG.missileDodge.points >= 10,
            "Faster relative speed during a missile dodge must award more points")
        check(hitG.missileDodge.count == 0 and hitG.missileDodge.points == 0
            and hitShip.shield < hitShip.maxShield,
            "A missile that hits the player must not award dodge points")
    end

    -- 5. Missile detonating right next to the player at end of its second leg without hitting still awards dodge points.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        local launcher = group:spawn(ship, 3, { x = 200, y = 270 })
        group.fire:shoot(launcher, ship)
        local rocket = group.fire.shots[1]
        group.fire.shots = { rocket }

        local hitDist = ship:hitRadius() + rocket.profile.radius
        local speed = 320
        local startX, endX = ship.x - 140, ship.x - hitDist - 6
        rocket.x, rocket.y = startX, ship.y
        rocket.vx, rocket.vy = speed, 0
        rocket.age = 0
        rocket.secondLeg = {
            direction = 1, radius = 100, speed = speed, started = 0,
            ramp = 0, sweep = 0, length = (endX - startX) / 100,
            startX = startX, startY = ship.y, heading = 0,
            cx = startX, cy = ship.y, radial = 0,
            exitHeading = 0, exitX = startX, exitY = ship.y,
            x = endX, y = ship.y,
        }
        rocket.lifetime = (endX - startX) / speed

        for _ = 1, math.ceil((rocket.lifetime + Gladiator.missileSettleDuration) / dt) + 2 do
            group.fire:update(dt, ship, gladiator)
        end
        check(gladiator.missileDodge.count == 1 and gladiator.missileDodge.points >= 10
            and ship.shield == ship.maxShield,
            "A missile expiring right outside the shield without hitting must award dodge points")
    end

    -- 6. Non-missile enemy shots (WEDGE bullets) must not award missile dodge points.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        local wedge = group:spawn(ship, 1, { x = 340, y = 270 + ship:hitRadius() + 12 })
        group.fire:shoot(wedge, { x = 740, y = wedge.y, isDestroyed = function() return false end })
        group.fire.bursts = {}
        for _ = 1, 60 do group.fire:update(dt, ship, gladiator) end
        check(gladiator.missileDodge.count == 0 and gladiator.missileDodge.points == 0,
            "Non-missile bullets passing close must not trigger missile dodge points")
    end

    -- Helper to fly the player past one or two stationary enemy ships at a given clearance and speed.
    local function runAerobaticPass(offsetsY, shipVx, stepDt)
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 320, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        for _, offsetY in ipairs(offsetsY) do
            local enemy = group:spawn(ship, 1, { x = 540, y = 270 + offsetY, entryTime = 10 })
            enemy.thrust, enemy.vx, enemy.vy = 0, 0, 0
            enemy.maxSpeed = 0
        end

        local simDt = stepDt or dt
        local duration = 440 / math.max(1, math.abs(shipVx))
        local steps = math.ceil(duration / simDt)
        for _ = 1, steps do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = ship.x + shipVx * simDt
            group:update(simDt, ship)
        end
        return gladiator, ship
    end

    -- 7. Aerobatics: close pass, speed scaling, threading between two enemies, and collision cancellation.
    do
        local hitDist = Ship.new(Arena.width, Arena.height):hitRadius() + Enemies.types[1].radius
        local closeG = runAerobaticPass({ hitDist + 5 }, 320)
        local wideG = runAerobaticPass({ hitDist + 42 }, 320)
        local fastG = runAerobaticPass({ hitDist + 12 }, 520)
        local slowG = runAerobaticPass({ hitDist + 12 }, 160)
        local threadG = runAerobaticPass({ hitDist + 10, -(hitDist + 10) }, 360)
        local crashG, crashShip = runAerobaticPass({ 0 }, 320)
        local fps30G = runAerobaticPass({ hitDist + 10 }, 360, 1 / 30)
        local fps144G = runAerobaticPass({ hitDist + 10 }, 360, 1 / 144)

        check(closeG.aerobatics.count == 1 and wideG.aerobatics.count == 1,
            "A single close pass past an enemy ship must award aerobatics once")
        check(closeG.aerobatics.points > wideG.aerobatics.points and wideG.aerobatics.points >= 10,
            "Closer aerobatic flyby must award higher points than a wider flyby")
        check(fastG.aerobatics.points > slowG.aerobatics.points and slowG.aerobatics.points >= 10,
            "Faster relative speed during aerobatic flyby must award higher points")
        check(threadG.aerobatics.count == 2 and threadG.aerobatics.points >= closeG.aerobatics.points,
            "Threading cleanly between two enemy ships must award aerobatics points for both")
        check(crashG.aerobatics.count == 0 and crashG.aerobatics.points == 0
            and crashShip.shield < crashShip.maxShield,
            "Colliding with an enemy ship and separating must not award aerobatics points")
        check(fps30G.aerobatics.count == 1 and fps144G.aerobatics.count == 1
            and math.abs(fps30G.aerobatics.points - fps144G.aerobatics.points) <= 1,
            "Aerobatics near-miss scoring must remain consistent across frame rates")
    end

    -- 8. Stationary ship next to a stationary enemy must not award aerobatics points.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local enemy = group:spawn(ship, 1, { x = 540, y = 270 + ship:hitRadius() + Enemies.types[1].radius + 10, entryTime = 10 })
        enemy.thrust, enemy.vx, enemy.vy, enemy.maxSpeed = 0, 0, 0, 0
        for _ = 1, 60 do group:update(dt, ship) end
        check(gladiator.aerobatics.count == 0 and gladiator.total == 0,
            "Stationary proximity must not award aerobatics points")
    end

    -- 9. Floating popups spawn at the exact event position, stack on overlap, render cleanly, and expire.
    do
        local Camera = require("camera")
        local gladiator = Gladiator.new()
        local p1 = gladiator:recordDestroy(40, 100, 310, 220)
        local p2 = gladiator:recordMissileDodge(10, 300, 310, 220)
        local p3 = gladiator:recordAerobatics(8, 400, 520, 180)
        check(gladiator.total == gladiator.destroy.points + gladiator.missileDodge.points + gladiator.aerobatics.points,
            "Total Gladiator Points must equal the sum of all category points")
        check(#gladiator.popups == 3, "Each scoring event with coordinates must spawn a floating popup")
        check(gladiator.popups[1].x == 310 and gladiator.popups[1].y == 220
            and gladiator.popups[2].y < gladiator.popups[1].y
            and gladiator.popups[3].x == 520 and gladiator.popups[3].y == 180,
            "Popups must appear at the earned world position and stagger when overlapping")

        local viewShip = Ship.new(Arena.width, Arena.height)
        local camera = Camera.new(viewShip.x, viewShip.y)
        camera:update(0, viewShip, 1280, 800)
        local font = love.graphics.newFont(11)
        local printed = {}
        local originalPrint = love.graphics.print
        love.graphics.print = function(text, ...)
            printed[text] = true
            return originalPrint(text, ...)
        end
        local ok, err = pcall(function() gladiator:drawPopups(camera, 1280, 800, font) end)
        love.graphics.print = originalPrint
        check(ok and printed["+" .. p1] and printed["+" .. p2] and printed["+" .. p3],
            "Drawing popups must render each category icon and earned point text: " .. tostring(err))

        gladiator:update(Gladiator.popupDuration)
        check(#gladiator.popups == 0, "Popups must expire after popupDuration")
        gladiator:update(Gladiator.noticeDuration)
        check(gladiator.lastEvent == nil, "HUD notice must expire after noticeDuration")
    end

    -- 10. Integration check: world popup coordinates match destroy, missile graze, and aerobatics graze positions.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 320, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local hitDist = ship:hitRadius() + Enemies.types[1].radius
        local enemyY = 270 + hitDist + 10
        local enemy = group:spawn(ship, 1, { x = 540, y = enemyY, entryTime = 10 })
        enemy.thrust, enemy.vx, enemy.vy, enemy.maxSpeed = 0, 0, 0, 0
        for _ = 1, 80 do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = ship.x + 360 * dt
            group:update(dt, ship)
        end
        check(#gladiator.popups == 1 and gladiator.popups[1].category == "aerobatics"
            and math.abs(gladiator.popups[1].x - 540) < 10
            and math.abs(gladiator.popups[1].y - (270 + enemyY) * 0.5) < 4,
            "Aerobatics popup must spawn right at the grazing midpoint between player and enemy")

        local target = group:spawn(ship, 2, { x = 760, y = 190 })
        group:destroy(#group.items)
        local killPopup = gladiator.popups[#gladiator.popups]
        check(killPopup and killPopup.category == "destroy"
            and killPopup.x == target.x and killPopup.y == target.y,
            "Destroy popup must spawn at the destroyed enemy's exact world position")
    end

    -- 11. Partial missile salvo hit (and shield break) must cancel dodge points for accompanying missiles.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        ship.shield = 1 -- First missile breaks shield, shrinking hitRadius for the second missile.
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local launcher = group:spawn(ship, 3, { x = 200, y = 270 })
        group.fire:shoot(launcher, ship)
        local hitter, grazer = group.fire.shots[1], group.fire.shots[2]
        group.fire.shots = { hitter, grazer }

        local speed, turnRate = 350, 3.35
        local radius = speed / turnRate
        local function setupStraight(rocket, yOffset)
            local startX, endX = ship.x - 100, ship.x + 220
            rocket.x, rocket.y = startX, ship.y + yOffset
            rocket.vx, rocket.vy = speed, 0
            rocket.age = 0
            rocket.secondLeg = {
                direction = 1, radius = radius, speed = speed, started = 0,
                ramp = 0, sweep = 0, length = (endX - startX) / radius,
                startX = startX, startY = ship.y + yOffset, heading = 0,
                cx = startX, cy = ship.y + yOffset, radial = 0,
                exitHeading = 0, exitX = startX, exitY = ship.y + yOffset,
                x = endX, y = ship.y + yOffset,
            }
            rocket.lifetime = (endX - startX) / speed
        end
        setupStraight(hitter, 0)
        -- Inside shield radius (29.9 + 5 = 34.9) but outside bare hull radius (23 + 5 = 28).
        setupStraight(grazer, ship.radius + grazer.profile.radius + 3)

        for _ = 1, 60 do
            group:update(dt, ship)
            gladiator:update(dt)
        end
        check(ship.shield == 0 and gladiator.missileDodge.count == 0 and gladiator.missileDodge.points == 0,
            "Getting hit by a missile must not award dodge points for companion missiles in the salvo")
    end

    -- 12. Getting hit by an enemy bullet while flying near an enemy ship must not award aerobatics points.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 320, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local hitDist = ship:hitRadius() + Enemies.types[1].radius
        local enemy = group:spawn(ship, 1, { x = 540, y = 270 + hitDist + 10, entryTime = 10 })
        enemy.thrust, enemy.vx, enemy.vy, enemy.maxSpeed = 0, 0, 0, 0

        local fired = false
        for _ = 1, 80 do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = ship.x + 360 * dt
            if not fired and ship.x >= 520 then
                fired = true
                group.fire:shoot(enemy, ship)
                group.fire.bursts = {}
            end
            group:update(dt, ship)
            gladiator:update(dt)
        end
        check(ship.shield < ship.maxShield and gladiator.aerobatics.count == 0 and gladiator.aerobatics.points == 0,
            "Taking enemy projectile damage during a close pass must cancel aerobatics points")
    end

    -- 13. Colliding with one enemy while grazing a second enemy must cancel aerobatics for both.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 320, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local hitDist = ship:hitRadius() + Enemies.types[1].radius
        local crashEnemy = group:spawn(ship, 1, { x = 540, y = 270, entryTime = 10 })
        local grazeEnemy = group:spawn(ship, 1, { x = 540, y = 270 + hitDist + 10, entryTime = 10 })
        crashEnemy.thrust, crashEnemy.vx, crashEnemy.vy, crashEnemy.maxSpeed = 0, 0, 0, 0
        grazeEnemy.thrust, grazeEnemy.vx, grazeEnemy.vy, grazeEnemy.maxSpeed = 0, 0, 0, 0

        for _ = 1, 80 do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = ship.x + 360 * dt
            group:update(dt, ship)
            gladiator:update(dt)
        end
        check(ship.shield < ship.maxShield and gladiator.aerobatics.count == 0 and gladiator.aerobatics.points == 0,
            "Colliding with an enemy ship must cancel aerobatics points from nearby enemies")

        -- After the post-hit lockout expires, a genuinely clean pass must award points again.
        gladiator:update(Gladiator.hitLockoutDuration + 0.1)
        ship.x, ship.y = 200, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        group.items = {}
        local cleanEnemy = group:spawn(ship, 1, { x = 420, y = 270 + hitDist + 10, entryTime = 10 })
        cleanEnemy.thrust, cleanEnemy.vx, cleanEnemy.vy, cleanEnemy.maxSpeed = 0, 0, 0, 0
        for _ = 1, 80 do
            ship.prevX, ship.prevY = ship.x, ship.y
            ship.x = ship.x + 360 * dt
            group:update(dt, ship)
            gladiator:update(dt)
        end
        check(gladiator.aerobatics.count == 1 and gladiator.aerobatics.points >= 10,
            "Clean evasion after recovering from a hit must award aerobatics points")
    end

    -- 14. Situational missile dodge: dodging a full 6-missile OBTUSE salvo counts ONCE, scored by tightest miss.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local launcher = group:spawn(ship, 3, { x = 200, y = 270 })
        group.fire:shoot(launcher, ship)
        check(#group.fire.shots == 6, "OBTUSE salvo must launch 6 missiles")

        local speed, turnRate = 350, 3.35
        local radius = speed / turnRate
        local hitDist = ship:hitRadius() + group.fire.shots[1].profile.radius
        local clearances = { 32, 24, 6, 18, 28, 36 }
        for i, rocket in ipairs(group.fire.shots) do
            local startX = ship.x - 100 - (i - 1) * 14
            local endX = ship.x + 220
            local y = ship.y + hitDist + clearances[i]
            rocket.x, rocket.y = startX, y
            rocket.vx, rocket.vy = speed, 0
            rocket.age = 0
            rocket.secondLeg = {
                direction = 1, radius = radius, speed = speed, started = 0,
                ramp = 0, sweep = 0, length = (endX - startX) / radius,
                startX = startX, startY = y, heading = 0,
                cx = startX, cy = y, radial = 0,
                exitHeading = 0, exitX = startX, exitY = y,
                x = endX, y = y,
            }
            rocket.lifetime = (endX - startX) / speed
        end

        for _ = 1, 90 do
            group:update(dt, ship)
            gladiator:update(dt)
        end
        local expected = Gladiator.evasionPoints(6, Gladiator.missileMargin, speed)
        check(gladiator.missileDodge.count == 1 and gladiator.missileDodge.points == expected
            and #gladiator.popups <= 1,
            "Dodging all 6 missiles in one OBTUSE salvo must count as one evasion using the closest miss")
    end

    -- 15. Dodging 10 missiles closely then getting hit 0.1s later must award ZERO dodge points.
    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 540, 270
        ship.prevX, ship.prevY = ship.x, ship.y
        local gladiator = Gladiator.new()
        local group = Enemies.new(function() return 0.5 end, gladiator)
        group.spawnRate = 0
        local launcher = group:spawn(ship, 3, { x = 200, y = 270 })
        group.fire:shoot(launcher, ship)
        group.fire:shoot(launcher, ship)
        -- Keep 11 missiles: 10 narrow misses followed by 1 direct hit ~0.1s later.
        table.remove(group.fire.shots)
        check(#group.fire.shots == 11, "Test must arrange 10 dodged missiles plus 1 trailing hit")

        local speed, turnRate = 400, 3.35
        local radius = speed / turnRate
        local hitDist = ship:hitRadius() + group.fire.shots[1].profile.radius
        for i, rocket in ipairs(group.fire.shots) do
            local isHit = i == 11
            local startX = isHit and (ship.x - 160) or (ship.x - 80 - (i - 1) * 4)
            local endX = ship.x + 260
            local y = isHit and ship.y or (ship.y + hitDist + 5 + (i % 3) * 4)
            rocket.x, rocket.y = startX, y
            rocket.vx, rocket.vy = speed, 0
            rocket.age = 0
            rocket.secondLeg = {
                direction = 1, radius = radius, speed = speed, started = 0,
                ramp = 0, sweep = 0, length = (endX - startX) / radius,
                startX = startX, startY = y, heading = 0,
                cx = startX, cy = y, radial = 0,
                exitHeading = 0, exitX = startX, exitY = y,
                x = endX, y = y,
            }
            rocket.lifetime = (endX - startX) / speed
        end

        for _ = 1, 90 do
            group:update(dt, ship)
            gladiator:update(dt)
        end
        check(ship.shield < ship.maxShield and gladiator.missileDodge.count == 0
            and gladiator.missileDodge.points == 0,
            "Dodging 10 missiles then getting hit 0.1s later must cancel the entire evasion situation")
    end

    -- 16. Fever Time: 1s >= 100pt trigger, 2x multiplier, >= 5s minimum, >= 100pt/s sustain, 5s cooldown, stats & visuals.
    do
        local Camera = require("camera")
        local gladiator = Gladiator.new()
        local ship = Ship.new(Arena.width, Arena.height)

        -- 60 + 50 spread over 1.1s (> 1s window) must NOT trigger Fever Time.
        gladiator:award("destroy", 60, "DESTROY", ship.x, ship.y)
        gladiator:update(1.1, ship)
        gladiator:award("destroy", 50, "DESTROY", ship.x, ship.y)
        check(not gladiator.feverActive, "Points spread over more than 1 second must not trigger Fever Time")

        -- Adding 50 more within 0.5s reaches 100 in 1s and triggers Fever Time.
        gladiator:update(0.5, ship)
        gladiator:award("destroy", 50, "DESTROY", ship.x, ship.y)
        check(gladiator.feverActive and gladiator.feverDuration == 0,
            "Earning 100+ points within 1 second must activate Fever Time")

        -- Points earned during Fever Time must be doubled (2x) and sustain beyond 5 seconds when avg >= 100/s.
        local gained = gladiator:recordDestroy(100, 100, ship.x, ship.y)
        check(gained == 20, "Enemy destruction points must be doubled during Fever Time")
        gladiator:award("aerobatics", 290, "AEROBATICS", ship.x, ship.y) -- +580 => total 600 fever points

        -- Advance to 4.9s and 5.5s: 600 / 5.5 = 109.1 >= 100, so Fever Time must stay active.
        gladiator:update(4.9, ship)
        check(gladiator.feverActive, "Fever Time must remain active before 5 seconds")
        gladiator:update(0.6, ship)
        check(gladiator.feverActive and math.abs(gladiator.feverDuration - 5.5) < 1e-6,
            "Fever Time must continue past 5 seconds while average points/sec is at least 100")

        -- Render all Fever visual effects cleanly while active.
        local camera = Camera.new(ship.x, ship.y)
        camera:update(0, ship, 1280, 800)
        local font = love.graphics.newFont(11)
        local ok, err = pcall(function()
            Arena.draw(0.5, gladiator.feverAura)
            gladiator:drawFeverWorld(ship, 1.5)
            gladiator:drawFeverOverlay(1280, 800, 1.5)
            gladiator:drawPopups(camera, 1280, 800, font)
        end)
        check(ok, "Fever Time world, overlay, arena, and popup effects must render cleanly: " .. tostring(err))

        -- Advance 0.6s (from 5.5s to 6.1s): average drops below 100 at exact 6.0s, leaving 0.1s elapsed on 5s cooldown.
        gladiator:update(0.6, ship)
        check(not gladiator.feverActive
            and math.abs(gladiator.feverTotalTime - 6.0) < 1e-6
            and math.abs(gladiator.feverMaxDuration - 6.0) < 1e-6
            and math.abs(gladiator.feverCooldown - 4.9) < 1e-6,
            "Fever Time must end at the exact moment average drops below 100/s after 5s and enter 5s cooldown")

        -- Earning 200 points during cooldown must NOT re-trigger Fever Time.
        gladiator:award("destroy", 200, "DESTROY", ship.x, ship.y)
        check(not gladiator.feverActive, "Fever Time must not trigger during the 5-second cooldown")
        gladiator:update(4.8, ship)
        gladiator:award("destroy", 200, "DESTROY", ship.x, ship.y)
        check(not gladiator.feverActive, "Fever Time must stay locked until the full 5-second cooldown finishes")

        -- After cooldown completes, 100+ points in 1s must trigger a second Fever Time lasting the 5s minimum.
        gladiator:update(0.2, ship)
        check(gladiator.feverCooldown == 0, "Cooldown must reach zero after 5 seconds")
        gladiator:award("destroy", 100, "DESTROY", ship.x, ship.y)
        check(gladiator.feverActive, "Fever Time must re-trigger after cooldown expires")
        gladiator:update(4.9, ship)
        check(gladiator.feverActive, "Second Fever Time must last at least 5 seconds even with 0 points")
        gladiator:update(0.2, ship)
        check(not gladiator.feverActive
            and math.abs(gladiator.feverTotalTime - 11.0) < 1e-6
            and math.abs(gladiator.feverMaxDuration - 6.0) < 1e-6,
            "Total Fever Time must accumulate across activations while max duration tracks the longest single session")

        -- Destroying the player ship mid-Fever must immediately stop Fever Time.
        gladiator:update(5.0, ship)
        gladiator:award("destroy", 100, "DESTROY", ship.x, ship.y)
        gladiator:update(1.5, ship)
        check(gladiator.feverActive, "Third Fever Time must be active before ship destruction")
        ship.shield, ship.armor, ship.hull = 0, 0, 0
        gladiator:update(1.0, ship)
        check(not gladiator.feverActive and math.abs(gladiator.feverTotalTime - 12.5) < 1e-6,
            "Destroying the ship must end Fever Time immediately without padding duration")
    end

    print(string.format("PASS: %d Gladiator Points checks", checks))
end
