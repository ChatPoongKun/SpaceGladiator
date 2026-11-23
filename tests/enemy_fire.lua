return function(Ship, Enemies, Camera, check)
    local Arena = require("arena")
    local dt = 1 / 60

    local function headingChange(ax, ay, bx, by)
        return math.abs(math.atan2(ax * by - ay * bx, ax * bx + ay * by))
    end

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
        check(#group.fire.shots == 1 and #group.fire.bursts == 1 and not enemy.braking,
            "A WEDGE must launch its first bullet immediately on arrival without stopping")
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
        group.fire:update(dt, ship)
        for i, rocket in ipairs(group.fire.shots) do
            local old = velocities[i]
            assert(headingChange(old[1], old[2], rocket.vx, rocket.vy) < 0.02,
                "Missiles must ease into a heavy turn without an abrupt first-frame rotation")
        end
        group.fire:update(0.12 - dt, ship)
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
        local rocket = group.fire.shots[1]
        group.fire.shots = {rocket}
        ship.x, ship.y = 560, 440
        group.fire:update(rocket.lifetime, ship)
        local leg = rocket.secondLeg
        ship.x, ship.y = 200, 50
        local turnEnd = (2 * leg.ramp + leg.sweep) * leg.radius / leg.speed
        group.fire:update(turnEnd - 2 * dt, ship)
        local vx, vy = rocket.vx, rocket.vy
        group.fire:update(dt, ship)
        local bank = headingChange(vx, vy, rocket.vx, rocket.vy)
        vx, vy = rocket.vx, rocket.vy
        group.fire:update(dt, ship)
        local taper = headingChange(vx, vy, rocket.vx, rocket.vy)
        vx, vy = rocket.vx, rocket.vy
        group.fire:update(dt, ship)
        check(leg.ramp > 0 and bank > taper and taper > 0
            and headingChange(vx, vy, rocket.vx, rocket.vy) < 1e-8,
            "The missile must ease out of the turn before flying straight into the target")
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
        local shieldRadius = ship:hitRadius() + direct.profile.radius
        local hullRadius = ship.radius + glancing.profile.radius
        local grazingOffset = (shieldRadius + hullRadius) / 2
        local grazingContactX = math.sqrt(shieldRadius ^ 2 - grazingOffset ^ 2)
        direct.x = ship.x - shieldRadius - 1
        glancing.x, glancing.y = ship.x - grazingContactX - 4, ship.y + grazingOffset
        group.fire:update(dt, ship)
        local impact = group.fire.impacts[1]
        check(impact and impact.shield and math.abs(ship.x - impact.x - shieldRadius) < 1e-6
            and ship.shield == 0 and ship.armor == 95,
            "One shield point must intercept a projectile at the outer ring and show a shield impact")
        check(#group.fire.shots == 1 and group.fire.shots[1] == glancing,
            "A later shot in the same step must miss if it only crosses the depleted shield radius")
    end

    do
        local ship = Ship.new(Arena.width, Arena.height)
        local coast = { turn = 0, thrust = false, brake = false }
        ship.maxShield, ship.armor = 0, 0
        check(not ship:hasShield() and ship:hitRadius() == ship.radius,
            "Zero maximum shield must disable the shield even with a stale charge value")
        ship:takeDamage(1)
        check(ship.hull == 2 and not ship:isDestroyed() and ship:isInvulnerable()
            and math.abs(ship.invulnTimer - Ship.hitInvulnDuration) < 1e-9,
            "A small hull hit must remove one slot and grant 0.5s invulnerability")
        ship:takeDamage(1000)
        check(ship.hull == 2, "Damage during post-hit invulnerability must be ignored")
        ship:update(Ship.hitInvulnDuration, coast)
        check(not ship:isInvulnerable(), "Post-hit invulnerability must expire after 0.5 seconds")
        ship:takeDamage(1000)
        check(ship.hull == 1 and not ship:isDestroyed() and ship:isInvulnerable(),
            "A large hull hit after invulnerability ends must also remove exactly one slot")
        ship:update(Ship.hitInvulnDuration, coast)
        ship.vx, ship.vy = 40, 10
        ship:takeDamage(1)
        check(ship:isDestroyed() and ship.hull == 0 and not ship:isInvulnerable()
            and ship:speed() == 0 and ship.destructionAge == 0,
            "The third hull hit must destroy the craft, clear invulnerability, and stop movement")
        local x, y, battery = ship.x, ship.y, ship.battery
        ship:takeDamage(100)
        ship:update(dt, {turn = 1, thrust = true, boost = true})
        check(ship.hull == 0 and ship.x == x and ship.y == y and ship.battery == battery and ship.destructionAge == dt,
            "A destroyed ship must advance its explosion without responding to flight input")
        ship:drawDestruction()
    end

    -- Post-hit invulnerability: shield-blocked hits grant none; armor/hull hits grant 0.5s with blinking and no hit detection.
    do
        local coast = { turn = 0, thrust = false, brake = false }

        -- 1. Shield completely blocking enemy collision or missile grants NO invulnerability.
        local ship, group, enemy = fixture(3)
        ship.shield, ship.armor = 20, 100
        enemy.x, enemy.y = ship.x, ship.y
        enemy.prevX, enemy.prevY = enemy.x, enemy.y
        enemy.thrust, enemy.vx, enemy.vy, enemy.maxSpeed = 0, 0, 0, 0
        group:update(dt, ship)
        check(ship.shield == 0 and ship.armor == 100 and not ship:isInvulnerable() and ship.invulnTimer == 0,
            "An enemy collision fully absorbed by shield must not grant invulnerability")

        -- 2. Missile hitting armor grants 0.5s invulnerability and skips hit detection on remaining shots in the salvo.
        local mShip, mGroup, launcher = fixture(3)
        mShip.shield, mShip.armor = 0, 100
        mGroup.fire:shoot(launcher, mShip)
        local firstDuration = mGroup.fire.shots[1].lifetime
        mGroup.fire:update(firstDuration, mShip)
        check(mShip.armor == 92 and mShip:isInvulnerable()
            and math.abs(mShip.invulnTimer - 0.5) < 1e-9
            and #mGroup.fire.impacts == 1 and #mGroup.fire.shots == 5,
            "First missile hitting armor must grant 0.5s invulnerability and let companion missiles pass without hit detection")

        -- Blinking visual alternates between bright flash and dim transparency during invulnerability.
        local a0, f0 = mShip:invulnBlinkAlpha()
        mShip:draw(0)
        mShip:update(Ship.invulnBlinkInterval, coast)
        local a1, f1 = mShip:invulnBlinkAlpha()
        mShip:draw(Ship.invulnBlinkInterval)
        check(a0 == 1 and f0 > 0 and a1 < 0.5 and f1 == 0,
            "Post-hit invulnerability must alternate between bright flash and dim blink phases")

        -- 3. During remaining invulnerability, incoming shots and overlapping enemy ships do not register hits at all.
        local wedge = mGroup:spawn(mShip, 1, { x = mShip.x - 40, y = mShip.y, entryTime = 5 })
        wedge.thrust, wedge.vx, wedge.vy, wedge.maxSpeed = 0, 0, 0, 0
        mGroup.fire:clear()
        mGroup.fire:shoot(wedge, mShip)
        mGroup.fire.bursts = {}
        local dmgBefore = mShip.damageCount
        local armorBefore = mShip.armor
        local passedShot = mGroup.fire.shots[1]
        for _ = 1, 10 do
            mShip:update(dt, coast)
            mGroup:update(dt, mShip)
        end
        check(mShip:isInvulnerable() and mShip.armor == armorBefore and mShip.damageCount == dmgBefore
            and #mGroup.fire.impacts == 0 and not passedShot.spent and passedShot.x > mShip.x,
            "Shots crossing an invulnerable player must pass through with zero hit detection or impact effects")

        -- Overlapping enemy ship during invulnerability must also skip collision entirely.
        wedge.x, wedge.y = mShip.x, mShip.y
        wedge.prevX, wedge.prevY = wedge.x, wedge.y
        mShip:update(dt, coast)
        mGroup:update(dt, mShip)
        check(mShip:isInvulnerable() and mShip.armor == armorBefore and mShip.damageCount == dmgBefore
            and wedge.contactRadius == nil,
            "Enemy ship overlap during invulnerability must not trigger contact hit detection")

        -- Once the 0.5s window expires, blinking ends and hit detection resumes normally.
        mShip:update(mShip.invulnTimer, coast)
        local aEnd, fEnd = mShip:invulnBlinkAlpha()
        check(not mShip:isInvulnerable() and aEnd == 1 and fEnd == 0,
            "After 0.5s invulnerability expires, blink must stop")
        mGroup:update(dt, mShip)
        check(mShip.armor == armorBefore - 20 and mShip.damageCount == dmgBefore + 1 and mShip:isInvulnerable(),
            "After 0.5s invulnerability expires, enemy contact must resume and trigger a new 0.5s window")

        -- 4. Shield overflow into armor also grants 0.5s invulnerability.
        local oShip, oGroup, oEnemy = fixture(1)
        oShip.shield, oShip.armor = 2, 100
        oGroup.fire:shoot(oEnemy, oShip)
        oGroup.fire.bursts = {}
        oGroup.fire.shots[1].x = oShip.x - oShip:hitRadius() - 2
        oGroup.fire:update(dt, oShip)
        check(oShip.shield == 0 and oShip.armor == 96 and oShip:isInvulnerable(),
            "Damage breaking through shield into armor must grant 0.5s invulnerability")
    end

    do
        local Hud = require("hud")
        local panel = Hud.new()
        local ship = Ship.new(Arena.width, Arena.height)
        ship.shield, ship.armor, ship.hull, ship.battery = 1, 68, 2, 75
        ship.vx, ship.vy = 120, 0
        local g = love.graphics
        local originalArc, originalPrint, originalPrintf, originalCircle, originalPolygon =
            g.arc, g.print, g.printf, g.circle, g.polygon
        local segments, printed, texts, rings, polygons = {}, {}, {}, 0, 0
        local expectedTrackAlpha = 0.15 * Hud.BASE_ALPHA
        g.arc = function(mode, arcType, x, y, radius, start, finish, ...)
            local _, _, _, alpha = g.getColor()
            if math.abs(alpha - expectedTrackAlpha) < 1e-5 then
                -- Distinguish upper resource arcs from the lower velocity arc (which starts near pi/6).
                if start >= math.pi * 0.5 then
                    segments[radius] = (segments[radius] or 0) + 1
                end
            end
            return originalArc(mode, arcType, x, y, radius, start, finish, ...)
        end
        g.print = function(label, ...)
            printed[label] = true
            return originalPrint(label, ...)
        end
        g.printf = function(label, ...)
            texts[tostring(label)] = true
            return originalPrintf(label, ...)
        end
        g.circle = function(mode, x, y, radius, ...)
            if mode == "line" and math.abs(radius - ship.radius * ship.shieldMargin) < 1e-6 then rings = rings + 1 end
            return originalCircle(mode, x, y, radius, ...)
        end
        g.polygon = function(...)
            polygons = polygons + 1
            return originalPolygon(...)
        end
        local ok, message = pcall(function()
            ship:draw(0)
            polygons = 0
            panel:draw(ship, 800, 600, 0)
        end)
        local r1 = Hud.RING_OUTER_RADIUS
        local r2 = r1 - Hud.RING_STEP
        local r3 = r1 - Hud.RING_STEP * 2
        local r4 = r1 - Hud.RING_STEP * 3
        local hasSegments = segments[r1] == 10 and segments[r2] == 10 and segments[r3] == 3 and segments[r4] == 10
            and not printed.SHIELD and not printed.ARMOR and not printed.HULL
            and texts.BATTERY and texts["75"] and texts.MJ
            and texts["120"] and texts["PX/S"] and not texts["67% MAX"]
            and rings > 0 and polygons == 0
        segments, printed, texts, rings = {}, {}, {}, 0
        ship.maxShield = 0
        local noShieldOk, noShieldMessage = pcall(function()
            ship:draw(0)
            panel:draw(ship, 800, 600, 0)
        end)
        g.arc, g.print, g.printf, g.circle, g.polygon =
            originalArc, originalPrint, originalPrintf, originalCircle, originalPolygon
        check(ok and hasSegments,
            "Circular HUD must draw shield/armor/hull/battery rings, MJ center, and bottom velocity without side panels: " .. tostring(message))
        check(noShieldOk and segments[r1] == 10 and segments[r2] == 3 and segments[r3] == 10 and not segments[r4] and rings == 0,
            "Zero maximum shield must omit the ring and reflow HUD armor, hull, and battery: " .. tostring(noShieldMessage))
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
