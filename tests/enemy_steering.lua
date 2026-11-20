return function(Ship, Enemies, Camera, check, near)
    local width, height, dt, tau = 1280, 800, 1 / 60, 2 * math.pi
    local function length(x, y) return math.sqrt(x * x + y * y) end

    local function fixture()
        local ship = Ship.new(width, height)
        local camera = Camera.new(ship.x, ship.y)
        local first = true
        local group = Enemies.new(function()
            if first then
                first = false
                return 0 -- left edge
            end
            return 0.5
        end)
        group.spawnRate = 0
        return ship, camera, group
    end

    local function step(ship, camera, group, aim)
        local old = {}
        for i, e in ipairs(group.items) do old[i] = {e.x, e.y, e.vx, e.vy, e.angle} end
        ship.x, ship.y = ship.x + ship.vx * dt, ship.y + ship.vy * dt
        camera.x, camera.y = ship.x, ship.y
        group:update(dt, ship, camera, width, height, aim)
        for i, e in ipairs(group.items) do
            local x, y, vx, vy, angle = unpack(old[i])
            local yaw = math.abs((e.angle - angle + math.pi) % tau - math.pi)
            assert(e.prevX == x and e.prevY == y, "Enemy lost its previous position")
            assert(length(e.vx - vx, e.vy - vy) <= e.thrustLimit * dt + 1e-6, "Enemy exceeded its thrust limit")
            assert(e:speed() <= e.maxSpeed + 1e-6, "Enemy exceeded its speed limit")
            assert(yaw <= e.turnSpeed * dt + 1e-7, "Enemy exceeded its turn limit")
        end
    end

    do
        local ship, camera, group = fixture()
        local squad = group:spawnSquad(ship, camera, width, height)
        local leader, leftEscort, rightEscort, leftWing, rightWing = unpack(squad)
        local offscreen = true
        for _, e in ipairs(squad) do
            local x = camera:worldToScreen(e.x, e.y, width, height)
            offscreen = offscreen and x + e.radius * camera.zoom < 0
        end
        check(offscreen and leader.kind == 3 and leftEscort.kind == 2 and rightEscort.kind == 2
            and leftWing.kind == 1 and rightWing.kind == 1
            and leftEscort.y < leader.y and rightEscort.y > leader.y
            and leftWing.y < leftEscort.y and rightWing.y > rightEscort.y,
            "A squad must enter from one edge with an OBTUSE leader, two escorts and two flankers")

        local dives, regrouped = 0, false
        for _ = 1, 9 * 60 do
            local leftBefore, rightBefore = leftWing.state, rightWing.state
            step(ship, camera, group)
            if leftBefore == "form" and leftWing.state == "dive" then
                assert(rightBefore == "form" and rightWing.state == "dive", "Flankers launched on different frames")
                dives = dives + 1
            end
            if dives > 0 and leftWing.state == "form" and rightWing.state == "form" then regrouped = true end
        end
        check(dives >= 2 and regrouped, "WEDGE pair must dive together and reform before launching again")
    end

    do
        local ship, camera, group = fixture()
        local squad = group:spawnSquad(ship, camera, width, height)
        group.rng = function() return 0.2 end
        local backup = group:spawnSquad(ship, camera, width, height)
        group:destroy(7) -- one open escort position in the backup squad
        group:destroy(1)
        step(ship, camera, group)
        check(squad[2].leader == backup[1] and squad[3].leader == nil
            and squad[4].leader == nil and squad[5].leader == nil
            and squad[4].state == "dive" and squad[5].state == "dive",
            "Losing a leader must redirect escorts to available slots and release its WEDGE pair")
    end

    local function onRight(range, playerSpeed, braking)
        local ship, camera, group = fixture()
        ship.vx, ship.braking = playerSpeed, braking
        local enemy = group:spawn(ship, camera, width, height, 3, {
            x = ship.x + range, y = ship.y + 24, angle = 1.5 * math.pi,
        })
        return ship, camera, group, enemy
    end

    do
        local ship, camera, group, targeted = onRight(420, 0, false)
        local otherShip, otherCamera, otherGroup, ignored = onRight(420, 0, false)
        for frame = 1, 30 do
            step(ship, camera, group, frame <= 5 and math.pi / 2 or -math.pi / 2)
            step(otherShip, otherCamera, otherGroup, -math.pi / 2)
        end
        check(targeted.y > ignored.y + 20 and targeted.aimed,
            "An aimed-at ship must keep its lateral dodge briefly after the turret turns away")
    end

    do
        local ship, camera, group, cruising = onRight(420, -250, false)
        local otherShip, otherCamera, otherGroup, pressing = onRight(420, -250, true)
        for _ = 1, 4 * 60 do
            step(ship, camera, group)
            step(otherShip, otherCamera, otherGroup)
        end
        check(pressing.x - otherShip.x < cruising.x - ship.x - 50,
            "A visible leader must press in when the player brakes")

        local fastShip, fastCamera, fastGroup, pursuing = onRight(570, -650, false)
        for _ = 1, 45 do step(fastShip, fastCamera, fastGroup) end
        check(pursuing.x - fastShip.x < 490 and pursuing.vx < fastShip.vx - 200
            and near(pursuing.vy, 0, 30),
            "A leader must close directly on a player fleeing at high speed")
    end
end
