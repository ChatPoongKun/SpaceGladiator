return function(Ship, Enemies, Camera, check)
    local Arena = require("arena")
    local width, height, dt, tau = Arena.width, Arena.height, 1 / 60, 2 * math.pi
    local function length(x, y) return math.sqrt(x * x + y * y) end

    local function fixture()
        local ship = Ship.new(width, height)
        local first = true
        local group = Enemies.new(function()
            if first then
                first = false
                return 0 -- left edge
            end
            return 0.5
        end)
        group.spawnRate = 0
        group.patrolDuration = math.huge
        return ship, group
    end

    local function isPatrolGoal(enemy, ship, view)
        local x, y = enemy.goal.x, enemy.goal.y
        local definition = Enemies.types[enemy.kind]
        local distance = length(x - ship.x, y - ship.y)
        local margin = enemy.radius + 2
        return distance >= definition.patrolMin - 1e-6 and distance <= definition.patrolMax + 1e-6
            and x >= math.max(0, view.left) + margin and x <= math.min(width, view.right) - margin
            and y >= math.max(0, view.top) + margin and y <= math.min(height, view.bottom) - margin
    end

    do
        local speedRatios = {}
        for kind = 1, #Enemies.types do
            local ship, group = fixture()
            local enemy = group:spawn(ship, kind, {x = 400, y = 270, vx = 140, angle = math.pi / 2})
            local firstGoal = {x = enemy.x + Enemies.types[kind].arrivalRadius + 2, y = enemy.y}
            enemy.goal = firstGoal
            ship.x, ship.y = enemy.x, enemy.y
            group.rng = function() return 0.75 end
            group:update(dt, ship)
            check(enemy.goal == firstGoal and not enemy.braking and enemy:speed() >= 140,
                "Approaching a waypoint must not brake the aircraft")
            local incomingSpeed, startX = enemy:speed(), enemy.x
            group:update(dt, ship)
            local nextGoal = enemy.goal
            speedRatios[kind] = enemy:speed() / incomingSpeed
            check(nextGoal ~= firstGoal and enemy.angle < math.pi / 2 and enemy.x > startX and enemy.braking
                and math.abs(speedRatios[kind] - math.exp(-Enemies.types[kind].brake * dt)) < 1e-6,
                "Arriving must apply hull-specific braking while the aircraft slides and turns")
            group:update(0.2, ship)
            check(enemy.goal == nextGoal and not enemy.braking and enemy:speed() > 0,
                "The short waypoint brake must release and leave the aircraft moving")
        end
        check(speedRatios[1] < speedRatios[2] and speedRatios[2] < speedRatios[3] and speedRatios[3] < 1,
            "WEDGE must brake harder than EQUILATERAL, and OBTUSE must retain the most momentum")
    end

    do
        local ship, group = fixture()
        local enemy = group:spawn(ship, 3, {x = ship.x - 330, y = ship.y, angle = 0})
        local manual = Ship.new(width, height)
        manual.x, manual.y = enemy.x, enemy.y
        manual.thrust, manual.turnSpeed, manual.maxSpeed = enemy.thrust, enemy.turnSpeed, enemy.maxSpeed
        manual.driftThreshold, manual.driftDeceleration = enemy.driftThreshold, enemy.driftDeceleration
        local function matchesManual(input)
            manual:update(dt, input)
            group:update(dt, ship)
            return length(enemy.x - manual.x, enemy.y - manual.y) < 1e-6
                and length(enemy.vx - manual.vx, enemy.vy - manual.vy) < 1e-6
                and math.abs(enemy.angle - manual.angle) < 1e-6
        end

        check(matchesManual({turn = 1, thrust = false, brake = false}) and enemy:speed() == 0,
            "An enemy facing away must turn using the same flight physics as manual controls")
        enemy.angle, manual.angle = math.pi / 2, math.pi / 2
        check(matchesManual({turn = 0, thrust = true, brake = false}) and enemy.accelerating,
            "A correctly aimed enemy must accelerate like a player holding thrust")
        enemy.vx, manual.vx = -130, -130
        check(matchesManual({turn = 0, thrust = true, brake = false}) and not enemy.braking,
            "An enemy drifting away from its waypoint must steer with thrust without braking")
    end

    do
        local ship, group = fixture()
        local squad = group:spawnSquad(ship)
        local leader, escort, otherEscort = squad[1], squad[2], squad[3]
        group:update(leader.phaseRemaining + dt, ship)
        for _, enemy in ipairs({leader, escort, otherEscort}) do
            assert(isPatrolGoal(enemy, ship, group.view), "Each independent patrol must use its hull's patrol range")
        end
        check((escort.goal.x ~= otherEscort.goal.x or escort.goal.y ~= otherEscort.goal.y)
            and length(escort.goal.x - ship.x, escort.goal.y - ship.y)
            < length(leader.goal.x - ship.x, leader.goal.y - ship.y),
            "The escorts must choose distinct waypoints closer to the player than the OBTUSE")

        ship.y = ship.y + 80
        local oldGoal, leaderGoal = escort.goal, leader.goal
        group:update(0.4, ship)
        check(escort.goal == oldGoal and leader.goal == leaderGoal, "Unreached waypoints must stay fixed as the player moves")

        escort.x, escort.y = oldGoal.x, oldGoal.y
        group:update(dt, ship)
        check(escort.goal ~= oldGoal and leader.goal == leaderGoal and isPatrolGoal(escort, ship, group.view),
            "An escort reaching its goal must choose a new one independently of the OBTUSE")
        group:destroy(1)
        oldGoal = escort.goal
        escort.x, escort.y = oldGoal.x, oldGoal.y
        group:update(dt, ship)
        check(escort.goal ~= oldGoal and isPatrolGoal(escort, ship, group.view),
            "An escort must continue its own patrol after the OBTUSE is destroyed")
    end

    do
        for _, corner in ipairs({{1, 1, -1, -1}, {width - 1, 1, 1, -1},
            {1, height - 1, -1, 1}, {width - 1, height - 1, 1, 1}}) do
            local x, y, dx, dy = unpack(corner)
            for kind = 1, #Enemies.types do
                local ship, group = fixture()
                ship.x, ship.y = x, y
                local camera = Camera.new(x, y)
                camera:update(0, ship, 800, 600)
                group.rng = function() return 0.5 end
                local enemy = group:spawn(ship, kind, {x = x + dx * 300, y = y + dy * 300})
                group:update(dt, ship, nil, camera, 800, 600)
                assert(isPatrolGoal(enemy, ship, group.view), "An outward first approach must choose an inward goal")
                local first = enemy.goal
                enemy.x, enemy.y = first.x, first.y
                group:update(dt, ship, nil, camera, 800, 600)
                assert(enemy.goal ~= first and isPatrolGoal(enemy, ship, group.view),
                    "Subsequent patrol goals must also fit inside the camera and the hull's patrol range")
            end
        end
        check(true, "All hull types must choose on-screen patrol goals at all four corners")
    end

    local function step(ship, group, aim)
        local old = {}
        for i, e in ipairs(group.items) do old[i] = {e.x, e.y, e.vx, e.vy, e.angle} end
        ship.x, ship.y = (ship.x + ship.vx * dt) % width, (ship.y + ship.vy * dt) % height
        group:update(dt, ship, aim)
        for i, e in ipairs(group.items) do
            local x, y, vx, vy, angle = unpack(old[i])
            local yaw = math.abs((e.angle - angle + math.pi) % tau - math.pi)
            assert(e.prevX == x and e.prevY == y, "Enemy lost its previous position")
            local speedGain = e.accelerating and e.thrust * dt or 0
            assert(e:speed() <= length(vx, vy) + speedGain + 1e-6, "Enemy gained speed without thrust")
            assert(e:speed() <= e.maxSpeed + 1e-6, "Enemy exceeded its speed limit")
            assert(yaw <= e.turnSpeed * dt + 1e-7, "Enemy exceeded its turn limit")
        end
    end

    do
        local ship, group = fixture()
        local squad = group:spawnSquad(ship)
        local leader, leftEscort, rightEscort, leftWing, rightWing = unpack(squad)
        local offscreen = true
        for _, e in ipairs(squad) do
            offscreen = offscreen and e.phase == "entering" and e.x + e.radius < group.view.left
        end
        check(offscreen and leader.kind == 3 and leftEscort.kind == 2 and rightEscort.kind == 2
            and leftWing.kind == 1 and rightWing.kind == 1
            and leftEscort.y < leader.y and rightEscort.y > leader.y
            and leftWing.y < leftEscort.y and rightWing.y > rightEscort.y,
            "A squad must enter from one edge with an OBTUSE leader, two escorts and two flankers")

        local patrol = {leader, leftEscort, rightEscort}
        local previousGoals, visits = {}, {}
        local attackers, lastBurst = {}, nil
        for _ = 1, 10 * 60 do
            step(ship, group)
            local burst = group.fire.bursts[1]
            if burst and burst ~= lastBurst then
                attackers[#attackers + 1], lastBurst = burst.enemy, burst
                local partner = burst.enemy == leftWing and rightWing or leftWing
                assert(length(partner.x - ship.x, partner.y - ship.y) > Enemies.types[1].patrolMax,
                    "The next attacker must first pull back outside the WEDGE attack range")
            end
            for _, enemy in ipairs(patrol) do
                local goal, previous = enemy.goal, previousGoals[enemy]
                if goal and (not previous or goal.x ~= previous.x or goal.y ~= previous.y) then
                    previousGoals[enemy] = {x = goal.x, y = goal.y}
                    visits[enemy] = (visits[enemy] or 0) + 1
                end
            end
        end
        for _, enemy in ipairs(patrol) do
            assert((visits[enemy] or 0) >= 3, "Each independent patrol must visit several waypoints with the player at rest")
        end
        check(true, "The leader and both escorts must keep patrolling with the player at rest")
        check(#attackers >= 3 and attackers[1] == leftWing, "The left WEDGE must open a repeating attack")
        for i = 2, #attackers do
            assert(attackers[i] ~= attackers[i - 1], "The WEDGE pair must alternate bursts")
        end
    end

    do
        local ship, group = fixture()
        ship.x, ship.vx, ship.shield = 240, 85, 10000
        local squad = group:spawnSquad(ship)
        local left, right = squad[4], squad[5]
        for _ = 1, 6 * 60 do
            step(ship, group)
            if #group.fire.bursts > 0 then break end
        end
        local burst = group.fire.bursts[1]
        assert(burst and burst.enemy == left, "The left WEDGE must fire first against a moving player")
        local x, y = right.goal.x, right.goal.y
        check(x > ship.x and math.abs(y - ship.y) < 1e-6, "The wingman must lock a point ahead of the player's velocity")

        -- Already lined up, the wingman must still wait for the last round.
        right.angle = math.atan2(x - right.x, right.y - y)
        right.vx, right.vy = 0, 0
        ship.vx, ship.vy = 0, -80
        for _ = 1, 14 do
            step(ship, group)
            assert(right.braking and not right.accelerating and right.goal.x == x and right.goal.y == y,
                "The wingman must brake on its fixed intercept while the partner fires")
        end
        check(burst.remaining == 1, "Only the last round should still be pending")

        -- The firing signal alone must not release a wingman facing away.
        right.angle = right.angle + math.pi
        step(ship, group)
        assert(burst.remaining == 0 and right.braking, "The last round must leave before the wingman launches")
        for _ = 1, 90 do
            step(ship, group)
            if right.accelerating then break end
            assert(right.braking, "The wingman must keep braking through the turn")
        end
        local bearing = math.atan2(x - right.x, right.y - y)
        check(right.accelerating and math.abs((right.angle - bearing + math.pi) % tau - math.pi) < math.rad(9)
            and right.goal.x == x and right.goal.y == y, "Thrust must resume along the original intercept after alignment")

        for _ = 1, 5 * 60 do
            step(ship, group)
            if #group.fire.bursts > 0 then break end
        end
        burst = group.fire.bursts[1]
        assert(burst and burst.enemy == right, "The second WEDGE must finish its pass and fire")
        group:destroy(5)
        step(ship, group)
        assert(isPatrolGoal(left, ship, group.view), "Losing a firing wingman must release the survivor to solo patrol")
        left.x, left.y = left.goal.x, left.goal.y
        step(ship, group)
        check(#group.fire.bursts == 1 and group.fire.bursts[1].enemy == left,
            "The surviving WEDGE must still fire at its own waypoint")
    end

    do
        local ship, group = fixture()
        group.patrolDuration = Enemies.patrolDuration
        local camera = Camera.new(ship.x, ship.y)
        local w, h = 1280, 800
        camera:update(0, ship, w, h)
        group:update(dt, ship, nil, camera, w, h)
        local squad = group:spawnSquad(ship)
        local leader = squad[1]
        check(leader.phase == "entering" and leader.x + leader.radius < group.view.left,
            "A wave must spawn outside the actual camera viewport")
        local entryTime = leader.phaseRemaining
        group:update(entryTime, ship, nil, camera, w, h)
        check(leader.phase == "patrol" and leader.phaseRemaining == Enemies.patrolDuration
            and squad[#squad].x - squad[#squad].radius > group.view.left,
            "The patrol timer must start after the full squad has flown into the viewport")

        for _ = 1, Enemies.patrolDuration * 60 - 1 do group:update(dt, ship, nil, camera, w, h) end
        check(leader.phase == "patrol" and leader.goal, "The squad must continue its combat patrol until time expires")
        group:update(dt, ship, nil, camera, w, h)
        check(leader.phase == "departing" and not leader.goal and not leader.dead,
            "A squad must give up the patrol and start a visible departure when time expires")
        local exit = leader.wave.exit
        for _, e in ipairs(squad) do
            assert(e.phase == "departing" and e.wave.exit == exit, "The full squad must share one departure point")
        end

        w, h = 800, 600
        camera:update(0, ship, w, h)
        local left, top = camera:screenToWorld(0, 0, w, h)
        local right, bottom = camera:screenToWorld(w, h, w, h)
        for _ = 1, 12 * 60 do
            if #group.items == 0 then break end
            group:update(dt, ship, nil, camera, w, h)
            for _, e in ipairs(squad) do
                if e.dead then
                    local cleared = {e.x + e.radius < left, e.x - e.radius > right,
                        e.y + e.radius < top, e.y - e.radius > bottom}
                    assert(cleared[exit.edge],
                        "A departing hull disappeared before crossing the resized viewport edge")
                end
            end
        end
        check(#group.items == 0 and group.kills == 0, "Departures must free all wave slots without awarding kills")
        group.spawnRate = Enemies.spawnRate
        group:update(2, ship, nil, camera, w, h)
        check(#group.items == #squad and group.items[1].phase == "entering", "A new wave must replace departed ships")
    end

    do
        local ship, group = fixture()
        local camera = Camera.new(ship.x, ship.y)
        camera:update(0, ship, 1280, 800)
        local screenEdge = camera:screenToWorld(1280, 400, 1280, 800)
        local enemy = group:spawn(ship, 2, {
            x = screenEdge - 8, y = ship.y, vx = Enemies.types[2].maxSpeed,
        })
        for _ = 1, 30 do step(ship, group) end
        check(enemy.x - enemy.radius > screenEdge and group.items[1] == enemy,
            "An enemy must be able to fly entirely off-screen")
        for _ = 1, 240 do step(ship, group) end
        check(enemy.x + enemy.radius < screenEdge and group.items[1] == enemy,
            "An off-screen enemy must keep steering and be able to return")
    end

    local function onRight(range)
        local ship, group = fixture()
        group.rng = function() return 0.5 end
        local enemy = group:spawn(ship, 3, {
            x = ship.x + range, y = ship.y + 24, angle = 1.5 * math.pi,
        })
        return ship, group, enemy
    end

    do
        local ship, group, targeted = onRight(420)
        local otherShip, otherGroup, ignored = onRight(420)
        for frame = 1, 30 do
            step(ship, group, frame <= 5 and math.pi / 2 or -math.pi / 2)
            step(otherShip, otherGroup, -math.pi / 2)
        end
        local dodgeOffset = targeted.y - ignored.y
        check(dodgeOffset > 0 and targeted.aimed,
            "An aimed-at ship must keep steering away briefly after the turret turns away")
        for _ = 1, 24 do
            step(ship, group, -math.pi / 2)
            step(otherShip, otherGroup, -math.pi / 2)
        end
        check(not targeted.aimed and targeted.y - ignored.y > dodgeOffset,
            "The dodge must carry lateral momentum after the turn ends")
    end

    require("tests.enemy_fire")(Ship, Enemies, Camera, check)
end
