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
        check(#group.fire.shots == 0 and ship.shield == 0 and ship.armor == 0 and ship.hull == ship.maxHull - 5,
            "A laser impact must consume the pulse and apply damage through shield, armor, then hull")
        group:update(0.15, ship)
        check(ship.hull == ship.maxHull - 5, "A laser pulse must only hit the player once")
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
        group.fire:update(0.12, ship)
        group:draw(0)
        ship.y = ship.y + 170
        group.fire:update(1.2, ship)
        check(#group.fire.shots == 0 and #group.fire.impacts == 6 and ship.shield == ship.maxShield,
            "A player leaving the aim point must evade the whole missile salvo")
        for _, impact in ipairs(group.fire.impacts) do
            assert(math.abs(impact.x - aimX) < 1e-6 and math.abs(impact.y - aimY) < 1e-6,
                "All six missile paths must converge at the locked position")
        end
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
