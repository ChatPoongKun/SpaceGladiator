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
        check(matchesManual({turn = 0, thrust = false, brake = true}) and enemy.braking,
            "An enemy drifting away from its waypoint must brake like a player")
    end

    do
        local ship, group = fixture()
        local squad = group:spawnSquad(ship)
        local leader, wing = squad[1], squad[4]
        group:update(leader.phaseRemaining + dt, ship)
        local route = leader.route
        local first = route.waypoints[1]
        local function isInPatrolRange(point)
            local distance = length(point.x - ship.x, point.y - ship.y)
            return distance >= 195 - 1e-6 and distance <= 290 + 1e-6
        end
        local function occupiesSlot(enemy, point)
            local x, y = enemy.goal.x - point.x, enemy.goal.y - point.y
            local fx, fy = math.sin(point.angle), -math.cos(point.angle)
            return math.abs(x * fx + y * fy - enemy.forward) < 1e-6
                and math.abs(y * fx - x * fy - enemy.right) < 1e-6
        end
        check(isInPatrolRange(first) and leader.goal.x == first.x and leader.goal.y == first.y
            and occupiesSlot(wing, first), "The random OBTUSE waypoint must define every formation slot")

        ship.y = ship.y + 80
        local oldGoal = wing.goal
        group:update(0.4, ship)
        check(wing.goal == oldGoal and leader.waypointIndex == 1, "Unreached waypoints must stay fixed as the player moves")

        wing.x, wing.y = wing.goal.x, wing.goal.y
        group:update(dt, ship)
        local second = route.waypoints[2]
        check(wing.waypointIndex == 2 and leader.waypointIndex == 1 and isInPatrolRange(second)
            and occupiesSlot(wing, second), "A wing reaching its slot must advance while the OBTUSE is still approaching")

        leader.x, leader.y = leader.goal.x, leader.goal.y
        group:update(dt, ship)
        check(leader.waypointIndex == 2 and leader.goal.x == second.x and leader.goal.y == second.y,
            "The OBTUSE must follow the same waypoint after reaching its own slot")
        group:destroy(1)
        wing.x, wing.y = wing.goal.x, wing.goal.y
        group:update(dt, ship)
        check(wing.waypointIndex == 3 and occupiesSlot(wing, route.waypoints[3]),
            "Surviving ships must continue the formation route after the OBTUSE is destroyed")
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

        for _ = 1, 10 * 60 do step(ship, group) end
        for _, enemy in ipairs(squad) do
            assert(enemy.waypointIndex >= 3, "Every aircraft must keep reaching new waypoints with the player at rest")
        end
        check(#leader.route.waypoints >= 3, "The stationary-player patrol must visit several distinct waypoints")
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
        local exit = leader.route.exit
        for _, e in ipairs(squad) do
            assert(e.phase == "departing" and e.route.exit == exit, "The full squad must share one departure point")
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
        check(targeted.y > ignored.y and targeted.aimed,
            "An aimed-at ship must keep steering away briefly after the turret turns away")
        for _ = 1, 24 do
            step(ship, group, -math.pi / 2)
            step(otherShip, otherGroup, -math.pi / 2)
        end
        check(targeted.y > ignored.y + 10, "The dodge must carry lateral momentum after the turn ends")
    end

end
