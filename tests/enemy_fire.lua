return function(Ship, Enemies, Camera, check)
    local Arena = require("arena")
    local dt = 1 / 60

    local function fixture(kind, x, y)
        local ship = Ship.new(Arena.width, Arena.height)
        ship.x, ship.y = 650, 270
        local group = Enemies.new(function() return 0.5 end)
        group.spawnRate = 0
        local enemy = group:spawn(ship, kind, {x = x or 260, y = y or 270})
        return ship, group, enemy
    end

    do
        local ship, group, enemy = fixture(1)
        group:update(dt, ship)
        check(#group.fire.shots == 0, "Choosing the first waypoint must not trigger enemy fire")
        enemy.goal = {x = enemy.x, y = enemy.y}
        group:update(dt, ship)
        local aimX, aimY = ship.x, ship.y
        check(#group.fire.shots == 1 and #group.fire.bursts == 1,
            "A WEDGE must launch its first bullet immediately on arrival")
        ship.y = ship.y + 100
        group:update(0.1, ship)
        check(#group.fire.shots == 1, "The WEDGE follow-up rounds must wait for their burst spacing")
        group:update(0.02, ship)
        check(#group.fire.shots == 2 and group.fire.shots[2].age < 1e-9, "The second WEDGE shot must launch after 0.12 seconds")
        group:update(0.12, ship)
        check(#group.fire.shots == 3 and #group.fire.bursts == 0, "A WEDGE burst must end after exactly three shots")
        for _, shot in ipairs(group.fire.shots) do
            local cross = (aimX - shot.x) * shot.vy - (aimY - shot.y) * shot.vx
            assert(math.abs(cross) < 1e-6, "Every WEDGE shot must keep the position locked at arrival")
        end
    end

    do
        local ship, group, enemy = fixture(2)
        ship.shield, ship.armor = 5, 4
        enemy.goal = {x = enemy.x, y = enemy.y}
        group:update(dt, ship)
        check(#group.fire.shots == 1 and #group.fire.bursts == 0 and ship.hull == ship.maxHull,
            "An EQUILATERAL must emit one laser pulse without applying damage before contact")
        group:update(0.35, ship)
        check(#group.fire.shots == 0 and ship.shield == 0 and ship.armor == 0 and ship.hull == ship.maxHull - 1,
            "A laser impact must consume the pulse and apply damage through shield, armor, then hull")
        group:update(0.15, ship)
        check(ship.hull == ship.maxHull - 1, "A laser pulse must only hit the player once")
    end

    do
        local ship, group, enemy = fixture(3)
        enemy.goal = {x = enemy.x, y = enemy.y}
        group:update(dt, ship)
        local aimX, aimY = ship.x, ship.y
        check(#group.fire.shots == 6 and #group.fire.bursts == 0, "An OBTUSE must launch six missiles at once")
        local lastAngle = -math.huge
        for _, missile in ipairs(group.fire.shots) do
            local angle = math.atan2(missile.vy, missile.vx)
            assert(angle > lastAngle and missile.age == 0 and missile.targetX == aimX and missile.targetY == aimY,
                "All six missiles must have distinct ejection angles and one aim point")
            lastAngle = angle
        end
        local firstDuration = group.fire.shots[1].lifetime
        group.fire:update(0.12, ship)
        group:draw(0)
        ship.x, ship.y = aimX - 90, aimY + 170
        local secondX, secondY = ship.x, ship.y
        group.fire:update(firstDuration - 0.12, ship)
        check(#group.fire.shots == 6 and #group.fire.impacts == 0 and ship.shield == ship.maxShield,
            "OBTUSE missiles must pass the first waypoint without detonating")

        local speeds, velocities, endTime = {}, {}, firstDuration
        for i, rocket in ipairs(group.fire.shots) do
            local leg = rocket.secondLeg
            check(math.abs(rocket.x - aimX) < 1e-6 and math.abs(rocket.y - aimY) < 1e-6
                and leg and leg.x == secondX and leg.y == secondY,
                "Every missile must lock the player's position as it passes the first waypoint")
            local dx, dy = aimX - rocket.controlX, aimY - rocket.controlY
            local expectedSpeed = 2 * math.sqrt(dx * dx + dy * dy) / firstDuration
            assert(math.abs(leg.speed - expectedSpeed) < 1e-6, "The second leg must inherit the incoming speed")
            speeds[i] = leg.speed
            velocities[i] = {rocket.vx, rocket.vy}
            endTime = math.max(endTime, rocket.lifetime)
        end

        ship.x, ship.y = 200, 50
        group.fire:update(0.12, ship)
        local turned = false
        for i, rocket in ipairs(group.fire.shots) do
            local speed = math.sqrt(rocket.vx ^ 2 + rocket.vy ^ 2)
            assert(math.abs(speed - speeds[i]) < 1e-6, "The missile must maintain speed through its turn")
            assert(rocket.secondLeg.x == secondX and rocket.secondLeg.y == secondY, "A second waypoint must stay locked")
            turned = turned or math.abs(rocket.vx - velocities[i][1]) + math.abs(rocket.vy - velocities[i][2]) > 1
        end
        check(#group.fire.shots == 6 and turned, "The salvo must steer into the second leg instead of snapping or stopping")
        group.fire:update(endTime - firstDuration, ship)
        check(#group.fire.shots == 0 and #group.fire.impacts == 6 and ship.shield == ship.maxShield,
            "The missile salvo must detonate at its second waypoint if the player moves away again")
        for _, impact in ipairs(group.fire.impacts) do
            assert(math.abs(impact.x - secondX) < 1e-6 and math.abs(impact.y - secondY) < 1e-6,
                "The second waypoint must be the final detonation point for all missiles")
        end
    end

    do
        local ship, group, enemy = fixture(3)
        group.fire:shoot(enemy, ship)
        local firstDuration = group.fire.shots[1].lifetime
        group.fire:update(firstDuration, ship)
        check(#group.fire.shots == 0 and #group.fire.impacts == 6 and ship.shield == ship.maxShield - 48,
            "Actual shield contact must still detonate missiles before a waypoint transition")
    end

    do
        local ship, group, enemy = fixture(3)
        group.fire:shoot(enemy, ship)
        local firstDuration = group.fire.shots[1].lifetime
        ship.x, ship.y = 560, 410
        group.fire:update(firstDuration - 0.01, ship)
        ship.prevX, ship.prevY = ship.x, ship.y
        ship.x, ship.y = 570, 420
        group.fire:update(0.025, ship)
        for _, rocket in ipairs(group.fire.shots) do
            local leg = rocket.secondLeg
            assert(leg and math.abs(leg.x - 564) < 1e-6 and math.abs(leg.y - 414) < 1e-6,
                "Retargeting must sample the moving player at the exact waypoint time")
            assert(math.abs(rocket.x - rocket.targetX) + math.abs(rocket.y - rocket.targetY) > 1e-6,
                "The missile must use the rest of that update to start its turn")
        end
        check(#group.fire.shots == 6, "All missiles must keep moving during an in-frame retarget")
    end

    do
        local ship, group, enemy = fixture(1, Arena.width - 100, 270)
        ship.x = Arena.width - 20
        group.fire:shoot(enemy, ship)
        ship.x = 4
        group.fire:update(0.16, ship)
        check(ship.shield == ship.maxShield - 6,
            "A projectile must be able to hit the visible part of a ship wrapped across the arena seam")
    end

    do
        local ship, group, enemy = fixture(1)
        ship.shield = 1
        group.fire:shoot(enemy, ship)
        group.fire:shoot(enemy, ship)
        local direct, glancing = unpack(group.fire.shots)
        direct.x = ship.x - ship:hitRadius() - direct.profile.radius - 1
        glancing.x, glancing.y = ship.x - 14, ship.y + ship.radius + glancing.profile.radius + 1
        group.fire:update(dt, ship)
        local impact = group.fire.impacts[1]
        check(impact and impact.shield and math.abs(ship.x - impact.x - ship.radius * 1.1 - direct.profile.radius) < 1e-6
            and ship.shield == 0 and ship.armor == 95,
            "One shield point must intercept a projectile at the outer ring and show a shield impact")
        check(#group.fire.shots == 1 and group.fire.shots[1] == glancing,
            "A later shot in the same step must miss if it only crosses the depleted shield radius")
    end

    do
        local ship = Ship.new(Arena.width, Arena.height)
        ship.maxShield, ship.armor = 0, 0
        check(not ship:hasShield() and ship:hitRadius() == ship.radius,
            "Zero maximum shield must disable the shield even with a stale charge value")
        ship:takeDamage(1)
        check(ship.hull == 2 and not ship:isDestroyed(), "A small hull hit must remove exactly one of three slots")
        ship:takeDamage(1000)
        check(ship.hull == 1 and not ship:isDestroyed(), "A large hull hit must also remove exactly one slot")
        ship.vx, ship.vy = 40, 10
        ship:takeDamage(1)
        check(ship:isDestroyed() and ship.hull == 0 and ship:speed() == 0 and ship.destructionAge == 0,
            "The third hull hit must destroy the craft and stop movement")
        local x, y, battery = ship.x, ship.y, ship.battery
        ship:takeDamage(100)
        ship:update(dt, {turn = 1, thrust = true, boost = true})
        check(ship.hull == 0 and ship.x == x and ship.y == y and ship.battery == battery and ship.destructionAge == dt,
            "A destroyed ship must advance its explosion without responding to flight input")
        ship:drawDestruction()
    end

    do
        local Hud = require("hud")
        local panel = Hud.new()
        local ship = Ship.new(Arena.width, Arena.height)
        ship.shield, ship.armor, ship.hull = 1, 68, 2
        local g = love.graphics
        local originalArc, originalPrint, originalCircle = g.arc, g.print, g.circle
        local segments, labels, rings = {}, {}, 0
        g.arc = function(mode, arcType, x, y, radius, start, finish, ...)
            local _, _, _, alpha = g.getColor()
            if math.abs(alpha - 0.15) < 1e-6 then segments[radius] = (segments[radius] or 0) + 1 end
            return originalArc(mode, arcType, x, y, radius, start, finish, ...)
        end
        g.print = function(label, ...)
            labels[label] = true
            return originalPrint(label, ...)
        end
        g.circle = function(mode, x, y, radius, ...)
            if mode == "line" and math.abs(radius - ship.radius * 1.1) < 1e-6 then rings = rings + 1 end
            return originalCircle(mode, x, y, radius, ...)
        end
        local ok, message = pcall(function()
            ship:draw(0)
            panel:draw(ship, 800, 600, 0)
        end)
        local hasSegments = segments[70] == 10 and segments[59] == 10 and segments[48] == 3
            and labels.SHIELD and labels.ARMOR and labels.HULL and labels["2 / 3"] and rings > 0
        segments, labels, rings = {}, {}, 0
        ship.maxShield = 0
        local noShieldOk, noShieldMessage = pcall(function()
            ship:draw(0)
            panel:draw(ship, 800, 600, 0)
        end)
        g.arc, g.print, g.circle = originalArc, originalPrint, originalCircle
        check(ok and hasSegments, "Shield and armor need ten ticks, hull three, and an active shield needs a ring: " .. tostring(message))
        check(noShieldOk and not labels.SHIELD and labels.ARMOR and labels.HULL and segments[70] == 10
            and segments[59] == 3 and not segments[48] and rings == 0,
            "Zero maximum shield must omit the ring and reflow HUD armor and hull: " .. tostring(noShieldMessage))
    end

    do
        local ship, group = fixture(1)
        local enemy = group.items[1]
        enemy.prevX, enemy.prevY = enemy.x - 50, enemy.y
        local x = group:hitSegment(170, enemy.y, 350, enemy.y)
        check(x and group.kills == 1, "Player shots must still sweep against a moving enemy hull")
        local camera = Camera.new(ship.x, ship.y)
        local _, exit = camera:clipRay(camera.x, camera.y, 1, 0, 800, 600)
        check(exit == 400, "Player laser clipping must still end at the viewport edge")
    end
end
