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
        local holdX = ship.x - Enemies.types[3].pressRange
        enemy.x, manual.x, enemy.vx, manual.vx = holdX, holdX, 130, 130
        check(matchesManual({turn = 0, thrust = false, brake = true}) and enemy.braking,
            "An enemy reaching its holding position must brake like a player")
    end

    do
        local ship, group = fixture()
        local left = group:spawn(ship, 3, {x = ship.x - 330, y = ship.y})
        local right = group:spawn(ship, 3, {x = ship.x + 330, y = ship.y})
        local randomValues = {0, 1, 1, 0, 0, 1, 1, 0}
        local draws = 0
        group.rng = function()
            draws = draws + 1
            return randomValues[draws] or 0.5
        end
        local refreshed = {[left] = {}, [right] = {}}
        for frame = 0, 60 do
            ship.y = height / 2 + frame
            local previousLeftY = left.goal and left.goal.y
            local previousRightY = right.goal and right.goal.y
            local previousDraws = draws
            group:update(dt, ship)
            local changes = 0
            for _, pair in ipairs({{left, previousLeftY}, {right, previousRightY}}) do
                local enemy, previousY = unpack(pair)
                if enemy.goal.y ~= previousY then
                    local times = refreshed[enemy]
                    times[#times + 1] = frame * dt
                    changes = changes + 1
                    if #times > 1 then
                        local elapsed = times[#times] - times[#times - 1]
                        assert(elapsed >= 0.25 - 1e-6 and elapsed <= 1 / 3 + 1e-6,
                            "A waypoint changed outside its scheduled refresh window")
                    end
                end
            end
            assert(changes == draws - previousDraws, "Waypoints must stay fixed between random refreshes")
        end
        local leftTimes, rightTimes = refreshed[left], refreshed[right]
        check(#leftTimes == 4 and #rightTimes == 4 and leftTimes[2] ~= rightTimes[2]
            and math.abs(rightTimes[3] - 2 * rightTimes[2]) > dt,
            "Each enemy must refresh its waypoint on its own varying schedule")
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

        local dives, regrouped = 0, false
        for _ = 1, 16 * 60 do
            local leftBefore, rightBefore = leftWing.state, rightWing.state
            step(ship, group)
            if leftBefore == "form" and leftWing.state == "dive" then
                assert(rightBefore == "form" and rightWing.state == "dive", "Flankers launched on different frames")
                dives = dives + 1
            end
            if dives > 0 and leftWing.state == "form" and rightWing.state == "form" then regrouped = true end
        end
        check(dives >= 2 and regrouped, "WEDGE pair must dive together and reform before launching again")
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

        w, h = 800, 600
        camera:update(0, ship, w, h)
        local left, top = camera:screenToWorld(0, 0, w, h)
        local right, bottom = camera:screenToWorld(w, h, w, h)
        for _ = 1, 12 * 60 do
            if #group.items == 0 then break end
            group:update(dt, ship, nil, camera, w, h)
            for _, e in ipairs(squad) do
                if e.dead then
                    assert(e.x + e.radius < left or e.x - e.radius > right
                        or e.y + e.radius < top or e.y - e.radius > bottom,
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
        for _ = 1, 180 do step(ship, group) end
        check(enemy.x + enemy.radius < screenEdge and group.items[1] == enemy,
            "An off-screen enemy must keep steering and be able to return")
    end

    do
        local ship, group = fixture()
        local squad = group:spawnSquad(ship)
        group.rng = function() return 0.2 end
        local backup = group:spawnSquad(ship)
        group:destroy(7) -- one open escort position in the backup squad
        group:destroy(1)
        step(ship, group)
        check(squad[2].leader == backup[1] and squad[3].leader == nil
            and squad[4].leader == nil and squad[5].leader == nil
            and squad[4].state == "dive" and squad[5].state == "dive",
            "Losing a leader must redirect escorts to available slots and release its WEDGE pair")
    end

    local function onRight(range, playerSpeed, braking)
        local ship, group = fixture()
        ship.vx, ship.braking = playerSpeed, braking
        local enemy = group:spawn(ship, 3, {
            x = ship.x + range, y = ship.y + 24, angle = 1.5 * math.pi,
        })
        return ship, group, enemy
    end

    do
        local ship, group, targeted = onRight(420, 0, false)
        local otherShip, otherGroup, ignored = onRight(420, 0, false)
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

    do
        local cruiseSpeed = -Ship.maxSpeed * 0.55
        local ship, group, cruising = onRight(240, cruiseSpeed, false)
        local otherShip, otherGroup, pressing = onRight(240, cruiseSpeed, true)
        for _ = 1, 4 * 60 do
            step(ship, group)
            step(otherShip, otherGroup)
        end
        check(pressing.x - otherShip.x < cruising.x - ship.x - 30,
            "A leader must press in when the player brakes")

        local fastShip, fastGroup, pursuing = onRight(420, -Ship.boostSpeed, false)
        for _ = 1, 66 do step(fastShip, fastGroup) end
        check(pursuing.vx < -pursuing.maxSpeed * 0.78 and pursuing:speed() <= pursuing.maxSpeed + 1e-6,
            "A leader must pursue a boosting player within its own speed limit")
    end
end
