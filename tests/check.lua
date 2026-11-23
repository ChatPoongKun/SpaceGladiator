return function(Ship, Starfield, Camera, Turret, Enemies, Hud)
    local Arena = require("arena")
    local width, height = Arena.width, Arena.height
    local coast = { turn = 0, thrust = false, brake = false }
    local thrust = { turn = 0, thrust = true, brake = false }
    local brake = { turn = 0, thrust = false, brake = true }
    local checks = 0
    local function check(condition, message)
        assert(condition, message)
        checks = checks + 1
    end
    local function near(a, b, tolerance)
        return math.abs(a - b) <= (tolerance or 0.00001)
    end
    local function step(ship, input, seconds, fps)
        for _ = 1, math.floor(seconds * fps) do
            ship:update(1 / fps, input)
        end
    end

    local startingSpeed = math.max(100, Ship.driftThreshold)
    local ship = Ship.new(width, height)
    ship.vy = -startingSpeed
    step(ship, thrust, 0.15, 60)
    check(near(ship.vx, 0) and near(ship.vy, -startingSpeed - Ship.thrust * 0.15), "W must accelerate toward the nose")
    local vx, vy, y = ship.vx, ship.vy, ship.y
    local quarterDecay = (1 - Ship.naturalDrag) ^ 0.25
    step(ship, coast, 0.25, 60)
    check(near(ship.vx, vx * quarterDecay) and near(ship.vy, vy * quarterDecay),
        "Releasing W must apply 50%/s natural deceleration without changing direction")
    check(ship.y < y, "Coasting must advance position")
    local coastVy = ship.vy
    step(ship, { turn = 1, thrust = false, brake = false }, 0.25, 60)
    check(near(ship.vx, 0) and near(ship.vy, coastVy * quarterDecay),
        "Turning must not rotate existing momentum while naturally decelerating")
    check(near(ship.angle, Ship.turnSpeed * 0.25), "D must rotate clockwise")
    step(ship, { turn = -1, thrust = false, brake = false }, 0.25, 60)
    check(near(ship.angle, 0) or near(ship.angle, 2 * math.pi), "A must rotate counterclockwise")

    vy = ship.vy
    ship.angle = math.pi / 2
    step(ship, thrust, 0.2, 60)
    check(ship.vx > 0 and near(ship.vy, vy), "New thrust must add to existing momentum without natural drag")
    local previousSpeed = ship:speed()
    for _ = 1, 60 do
        ship:update(1 / 60, brake)
        check(ship:speed() <= previousSpeed, "S must reduce speed at every heading")
        previousSpeed = ship:speed()
    end
    step(ship, brake, 5, 60)
    check(ship:speed() == 0, "Braking must reach a stable stop without reversing")
    step(ship, { turn = 0, thrust = true, brake = true }, 1, 60)
    check(ship:speed() == 0 and not ship.accelerating, "S must take precedence over W")

    ship = Ship.new(width, height)
    ship.angle = math.pi / 2
    step(ship, thrust, 1.5, 60)
    check(near(ship:speed(), Ship.maxSpeed), "Speed must be capped")
    for _, edge in ipairs({{"x", width, -1}, {"x", width, 1}, {"y", height, -1}, {"y", height, 1}}) do
        local axis, extent, sign = unpack(edge)
        local velocity = "v" .. axis
        local bonus = sign * Ship.wrapBonusSpeed
        local crossing = Ship.new(width, height)
        local baseline = Ship.new(width, height)
        local margin = crossing:hitRadius() + 1
        local distance = margin + 0.5
        crossing[axis] = sign < 0 and distance or extent - distance
        crossing[velocity], baseline[velocity] = sign * Ship.driftThreshold / 2, sign * Ship.driftThreshold / 2
        local function checkCrossingStep(dt, input, push)
            local start, baselineStart = crossing[axis], baseline[axis]
            crossing:update(dt, input)
            baseline:update(dt, input)
            local travel = baseline[axis] - baselineStart + push * dt
            check(near(crossing[axis], (start + travel) % extent), "The crossing push must affect position")
            check(near(crossing[velocity], baseline[velocity]) and near(crossing:speed(), baseline:speed()),
                "The crossing push must leave flight velocity equal to the interior baseline")
        end
        checkCrossingStep(1 / 30, coast, bonus)
        local arrival
        for _ = 1, 36 do
            checkCrossingStep(1 / 60, brake, bonus)
            arrival = sign < 0 and extent - crossing[axis] or crossing[axis]
            if arrival >= margin and arrival < extent / 2 then break end
        end
        check(arrival >= margin and arrival < extent / 2, "The push must last until the hull clears the opposite edge")
        checkCrossingStep(1 / 60, brake, 0)
        step(crossing, brake, 2, 60)
        check(crossing:speed() == 0, "Normal braking must resume once the hull clears the seam")
    end

    local low = Ship.new(width, height)
    local dragRate = -math.log(1 - Ship.naturalDrag)
    local offset = Ship.driftDeceleration / dragRate
    local belowThreshold = Ship.driftThreshold - 1
    local remaining = math.max(0, (belowThreshold + offset) * math.exp(-dragRate * 0.2) - offset)
    low.vx, low.vy = belowThreshold * 0.6, belowThreshold * 0.8
    low:update(0.2, coast)
    check(near(low:speed(), remaining) and near(low.vx, remaining * 0.6) and near(low.vy, remaining * 0.8),
        "Below the configured threshold, automatic deceleration must reduce speed without changing direction")
    step(low, coast, math.ceil(belowThreshold / Ship.driftDeceleration), 60)
    check(low:speed() == 0, "Low-speed deceleration must stop without reversing")

    local cruising = Ship.new(width, height)
    cruising.vx, cruising.vy = Ship.maxSpeed * 0.6, Ship.maxSpeed * 0.8
    step(cruising, coast, 1, 60)
    local expectedHalf = Ship.maxSpeed * (1 - Ship.naturalDrag)
    check(near(cruising:speed(), expectedHalf) and near(cruising.vx, expectedHalf * 0.6)
        and near(cruising.vy, expectedHalf * 0.8),
        "Coasting above the drift threshold must reduce speed by 50% per second without changing direction")

    low = Ship.new(width, height)
    step(low, thrust, 0.1, 60)
    check(near(low:speed(), (Ship.thrust - Ship.driftDeceleration) * 0.1),
        "Thrust must overcome low-speed deceleration without natural drag when starting")

    local slow, fast = Ship.new(width, height), Ship.new(width, height)
    slow.vy, fast.vy = -startingSpeed, -startingSpeed
    step(slow, thrust, 1 / 6, 30)
    step(fast, thrust, 1 / 6, 144)
    check(near(slow.vy, fast.vy) and near(slow.y, fast.y), "Acceleration must be frame-rate independent")
    slow.vy, fast.vy = -Ship.maxSpeed, -Ship.maxSpeed
    step(slow, brake, 1 / 6, 30)
    step(fast, brake, 1 / 6, 144)
    check(near(slow.vy, fast.vy), "Braking must be frame-rate independent")
    slow.vx, slow.vy, fast.vx, fast.vy = Ship.maxSpeed, 0, Ship.maxSpeed, 0
    step(slow, coast, 1, 30)
    step(fast, coast, 1, 144)
    check(near(slow.vx, expectedHalf) and near(fast.vx, expectedHalf),
        "Natural coast deceleration must be frame-rate independent")
    slow.vx, slow.vy, fast.vx, fast.vy = belowThreshold, 0, belowThreshold, 0
    step(slow, coast, 0.5, 30)
    step(fast, coast, 0.5, 144)
    remaining = math.max(0, (belowThreshold + offset) * math.exp(-dragRate * 0.5) - offset)
    check(near(slow.vx, remaining) and near(fast.vx, remaining), "Low-speed deceleration must be frame-rate independent")

    local boost = { turn = 0, thrust = false, brake = false, boost = true }
    ship = Ship.new(width, height)
    ship.angle = math.pi / 2
    local camera = Camera.new(ship.x, ship.y)
    camera:update(0, ship, 1280, 800)
    local normalZoom = camera.zoom
    ship:update(1 / 60, boost)
    camera:update(1 / 60, ship, 1280, 800)
    check(near(ship.vx, Ship.boostSpeed) and near(ship.vy, 0)
        and ship.battery == ship.maxBattery - Ship.boostCost,
        "A boost from rest must spend battery once and launch in the direction of the nose")
    check(camera.zoom < normalZoom and camera.x > width / 2, "The boost must pull the camera back and forward")
    ship:update(Ship.boostHold, boost)
    check(ship.battery == ship.maxBattery - Ship.boostCost and ship:speed() < Ship.boostSpeed
        and ship:speed() > Ship.maxSpeed, "A second press during boost must be ignored as the speed starts to decay")
    ship:update(Ship.boostFalloff - 1 / 60, coast)
    check(near(ship:speed(), Ship.maxSpeed) and ship.boostLevel == 0,
        "Boost must return to normal speed after the short falloff without natural drag")
    step(ship, coast, 1, 60)
    check(near(ship:speed(), Ship.maxSpeed * (1 - Ship.naturalDrag)),
        "Natural deceleration must resume after boosting ends")
    check(ship.battery > ship.maxBattery - Ship.boostCost, "The battery must recharge after boosting")
    camera:update(1, ship, 1280, 800)
    check(near(camera.zoom, normalZoom) and near(camera.x, width / 2), "The camera must settle on the arena center")

    ship.battery = 0
    ship:update(1 / 60, boost)
    check(ship.boostRemaining == 0 and ship.battery > 0 and ship.battery < Ship.boostCost,
        "A boost with insufficient charge must be ignored")

    ship = Ship.new(width, height)
    ship.x, ship.y, ship.angle = 1, 1, -math.pi / 4
    ship:update(1 / 60, boost)
    local travel = (Ship.boostSpeed / math.sqrt(2) + Ship.wrapBonusSpeed) / 60
    check(near(ship.x, width + 1 - travel) and near(ship.y, height + 1 - travel)
        and near(ship:speed(), Ship.boostSpeed) and ship.boostLevel > 0,
        "Boosting through a corner must apply the push on both axes and report the boost speed")
    step(ship, coast, 0.1, 60)
    check(near(ship:speed(), Ship.boostSpeed) and ship.boostLevel == 1,
        "Boost speed must stay consistent after clearing the corner")
    for _, viewport in ipairs({{1280, 800}, {800, 600}}) do
        local w, h = unpack(viewport)
        camera:update(1 / 60, ship, w, h)
        local left, top = camera:worldToScreen(0, 0, w, h)
        local right, bottom = camera:worldToScreen(width, height, w, h)
        check(left >= 0 and top >= 0 and right <= w and bottom <= h,
            "All arena boundaries must stay visible during the boost at both supported viewport sizes")
        local aimX, aimY = camera:screenToWorld(w * 0.8, h * 0.35, w, h)
        local x, y = camera:worldToScreen(aimX, aimY, w, h)
        check(near(x, w * 0.8) and near(y, h * 0.35), "Aiming must account for the boost camera")
    end

    -- Verify full-screen arena expansion across standard, widescreen, and compact viewports.
    do
        local prevW, prevH = Arena.width, Arena.height
        local idleShip = Ship.new(width, height)
        for _, viewport in ipairs({{1280, 800}, {1920, 1080}, {800, 600}}) do
            local w, h = unpack(viewport)
            Arena.resize(w, h)
            local fullCam = Camera.new(Arena.width / 2, Arena.height / 2)
            fullCam:update(0, idleShip, w, h)
            local left, top = fullCam:worldToScreen(0, 0, w, h)
            local right, bottom = fullCam:worldToScreen(Arena.width, Arena.height, w, h)
            check(near(left, 0) and near(top, 0) and near(right, w) and near(bottom, h),
                "Battlefield must expand to fill the entire screen at " .. w .. "x" .. h)
        end
        Arena.width, Arena.height = prevW, prevH
    end

    ship = Ship.new(1280, 800)
    local turret = Turret.new(0)
    local function explodedAt(x, y)
        for _, explosion in ipairs(turret.explosions) do
            if near(explosion.x, x) and near(explosion.y, y) then return true end
        end
        return false
    end
    turret:update(0.125, ship, ship.x + 1000, ship.y, false)
    check(near(turret.angle, math.pi / 4), "Turret must turn at exactly 360 degrees per second")
    local missile = turret:fire(ship)
    local left, right = turret.missiles[2], turret.missiles[3]
    local spread = math.rad(5)
    check(#turret.missiles == 3 and turret.shotsFired == 1
        and near(math.atan2(left.vx, -left.vy), turret.angle - spread)
        and near(math.atan2(right.vx, -right.vy), turret.angle + spread),
        "One shot must launch three projectiles with a symmetric spread")
    local shotX, shotY = missile.x, missile.y
    turret:update(0.1, ship, ship.x + 1000, ship.y, false)
    check(near(missile.x - shotX, Turret.missileSpeed * 0.1 / math.sqrt(2))
        and near(missile.y - shotY, -Turret.missileSpeed * 0.1 / math.sqrt(2)),
        "Missile must follow the current barrel direction even before the turret reaches its target")
    turret:update(1, ship, ship.x + 1000, ship.y, false)
    check(near(turret.angle, math.pi / 2), "Turret must stop at the mouse angle without overshooting")

    turret = Turret.new(math.pi * 2 - 0.1)
    turret:update(0.01, ship, ship.x, ship.y - 1000, false)
    check(turret.angle > math.pi * 2 - 0.1, "Turret must use the shortest path across the angle boundary")
    local angle = turret.angle
    ship.angle = math.pi
    turret:update(0.01, ship, ship.x, ship.y, false)
    check(near(turret.angle, angle), "Hull rotation and a coincident mouse must not snap the turret")

    turret = Turret.new(math.pi / 2)
    missile = turret:fire(ship)
    shotX, shotY = missile.x, missile.y
    turret:update(Turret.missileLifetime - 0.01, ship, ship.x + 1000, ship.y, false)
    check(#turret.missiles == 3, "All projectiles must remain alive until their lifetime expires")
    turret:update(0.02, ship, ship.x + 1000, ship.y, false)
    check(#turret.missiles == 0 and #turret.explosions == 3,
        "All projectiles must expire on time and each create an explosion")
    check(explodedAt(shotX + Turret.missileSpeed * Turret.missileLifetime, shotY),
        "Explosion position must use velocity times lifetime")
    turret:update(2, ship, ship.x + 1000, ship.y, false)
    check(#turret.explosions == 0, "Explosions must clean themselves up")
    turret = Turret.new(0)
    for _ = 1, 12 do turret:update(1 / 60, ship, ship.x, ship.y - 1000, true) end
    check(turret.shotsFired == 2 and #turret.missiles == 6,
        "Holding the left mouse button must repeat fire and count each volley once")
    local count = #turret.missiles
    turret:update(0.1, ship, ship.x, ship.y - 1000, false)
    check(#turret.missiles == count, "Releasing fire must stop creating missiles")
    turret:drawEffects()

    ship.vx, ship.vy = 300, -200
    turret = Turret.new(0)
    missile = turret:fire(ship)
    check(near(missile.vx, 300) and near(missile.vy, -1100),
        "Missile launch velocity must add both components of the ship velocity")
    shotX, shotY = missile.x, missile.y
    ship.vx, ship.vy, ship.angle = -400, 500, math.pi
    turret:update(0.1, ship, ship.x, ship.y - 1000, false)
    check(near(missile.vx, 300) and near(missile.vy, -1100)
        and near(missile.x - shotX, 30) and near(missile.y - shotY, -110),
        "After launch, ship acceleration must not change an existing missile's inherited velocity")

    ship.vx, ship.vy = 500, -300
    turret = Turret.new(math.pi / 2)
    missile = turret:fire(ship)
    shotX, shotY = missile.x, missile.y
    turret:update(Turret.missileLifetime + 0.001, ship, ship.x + 1000, ship.y, false)
    check(#turret.missiles == 0 and #turret.explosions == 3,
        "Inherited velocity must not change missile expiry time")
    check(explodedAt(shotX + missile.vx * Turret.missileLifetime, shotY + missile.vy * Turret.missileLifetime),
        "Faster missiles must travel farther over the same lifetime")

    for _, shipVelocity in ipairs({ -760, 760 }) do
        ship.vx, ship.vy = shipVelocity, 0
        turret = Turret.new(math.pi / 2)
        missile = turret:fire(ship)
        shotX, shotY = missile.x, missile.y
        turret:update(0.1, ship, ship.x + 1000, ship.y, false)
        check(near(missile.x - shotX, (900 + shipVelocity) * 0.1),
            "Same-direction and opposite-direction firing must add ship velocity without clamping")
        turret:update(Turret.missileLifetime - 0.101, ship, ship.x + 1000, ship.y, false)
        check(#turret.missiles == 3, "Fast and slow projectiles must both survive until the same expiry time")
        turret:update(0.002, ship, ship.x + 1000, ship.y, false)
        check(#turret.missiles == 0 and #turret.explosions == 3
            and explodedAt(shotX + (900 + shipVelocity) * Turret.missileLifetime, shotY),
            "Fast and slow missiles must expire together at their respective time-based endpoints")
    end
    turret:drawEffects()

    ship.vx, ship.vy = 0, 900
    turret = Turret.new(0)
    missile = turret:fire(ship)
    shotX, shotY = missile.x, missile.y
    turret:update(Turret.missileLifetime + 0.001, ship, ship.x, ship.y - 1000, false)
    check(#turret.missiles == 0 and #turret.explosions == 3 and explodedAt(shotX, shotY),
        "A zero-velocity missile must still expire and explode on time")
    turret = Turret.new(0)
    turret:fire(ship)
    turret:update(5, ship, ship.x, ship.y - 1000, false)
    check(#turret.missiles == 0 and #turret.explosions == 0,
        "A large update must finish both missile and explosion lifetimes")

    local owner = Ship.new(1280, 800)
    owner.vx, owner.vy = 300, -200
    turret = Turret.new(math.pi / 2)
    missile = turret:fire(owner)
    turret:update(0.1, owner, owner.x + 1000, owner.y, false)
    local function captureProjectileLines()
        local originalLine = love.graphics.line
        local tail, head
        love.graphics.line = function(x1, y1, x2, y2)
            local r, g, b = love.graphics.getColor()
            if near(r, 1) and near(g, 0.42) and near(b, 0.12) and near(x1, missile.x) and near(y1, missile.y) then
                tail = { x1, y1, x2, y2 }
            end
            if near(r, 1) and near(g, 0.87) and near(b, 0.46) and near(x2, missile.x) and near(y2, missile.y) then
                head = { x1, y1, x2, y2 }
            end
            return originalLine(x1, y1, x2, y2)
        end
        local ok, message = pcall(function() turret:drawEffects() end)
        love.graphics.line = originalLine
        check(ok, "Missile tail drawing must stay valid: " .. tostring(message))
        return tail, head
    end
    owner.x, owner.y = missile.x + 60, missile.y + 80
    local tail, head = captureProjectileLines()
    check(tail and near(tail[1], missile.x) and near(tail[2], missile.y)
        and near(tail[3] - missile.x, 14.4) and near(tail[4] - missile.y, 19.2)
        and head and near(head[3], missile.x) and near(head[4], missile.y)
        and near(head[3] - head[1], -3.6) and near(head[4] - head[2], -4.8),
        "A projectile's head and tail must point in opposite directions along the line to its launching ship")
    owner.x, owner.y = missile.x + 3, missile.y + 4
    tail = captureProjectileLines()
    check(tail and near(tail[3], owner.x) and near(tail[4], owner.y),
        "A missile tail must not extend beyond a nearby launching ship")
    owner.x, owner.y = missile.x, missile.y
    tail = captureProjectileLines()
    check(tail == nil, "Coincident missile and launcher positions must not divide by zero")

    ship = Ship.new(width, height)
    local enemyGroup = Enemies.new(function() return 0.5 end)
    for kind = 1, 3 do
        local enemy = enemyGroup:spawn(ship, kind)
        check(enemy.x >= enemy.radius and enemy.x <= width - enemy.radius
            and enemy.y >= enemy.radius and enemy.y <= height - enemy.radius
            and (enemy.x - ship.x) ^ 2 + (enemy.y - ship.y) ^ 2 >= 260 ^ 2,
            "Every default spawn must leave the enemy a safe distance from the player")
        check(enemy.kind == kind and enemy.radius == Enemies.types[kind].radius,
            "Each enemy must spawn with its selected shape and hull radius")
    end
    local wedge = Enemies.types[1].vertices
    local equilateral = Enemies.types[2].vertices
    local obtuse = Enemies.types[3].vertices
    check(#wedge == 8 and #equilateral == 6 and #obtuse == 6,
        "Enemy silhouettes must be a quadrilateral and two triangles")
    local function sideSquared(vertices, a, b)
        return (vertices[a] - vertices[b]) ^ 2 + (vertices[a + 1] - vertices[b + 1]) ^ 2
    end
    local a, b, c = sideSquared(equilateral, 1, 3), sideSquared(equilateral, 3, 5),
        sideSquared(equilateral, 5, 1)
    check(near(a, b, 0.01) and near(b, c, 0.01), "The medium equilateral enemy must have three equal sides")
    a, b, c = sideSquared(obtuse, 1, 3), sideSquared(obtuse, 1, 5), sideSquared(obtuse, 3, 5)
    check(near(a, b, 0.01) and c > a + b, "The distant enemy must be an obtuse isosceles triangle")

    for _, fps in ipairs({ 30, 60, 144 }) do
        local group = Enemies.new(function() return 0.5 end)
        for _ = 1, 2 * fps do group:update(1 / fps, ship) end
        check(#group.items == 5, "A full squad must arrive after two seconds at every frame rate")
    end
    local group = Enemies.new(function() return 0.5 end)
    group:update(0.3, ship)
    check(#group.items == 0, "Enemy spawning must not create an initial burst")
    group:update(1.7, ship)
    check(#group.items == 5, "The full squad must arrive across uneven frame durations")

    local capped = Enemies.new(function() return 0.5 end)
    for _ = 1, capped.maxCount do capped:spawn(ship, 1) end
    check(#capped.items == capped.maxCount and capped:spawn(ship, 1) == nil,
        "Every spawn path must enforce the enemy cap")
    local first = capped.items[1]
    local beforeX, beforeY = first.x, first.y
    capped:update(0.5, ship)
    check(#capped.items == capped.maxCount and capped.spawnAccumulator == 0,
        "A full enemy population must pause reinforcements without accumulating a backlog")
    check(first.x ~= beforeX or first.y ~= beforeY,
        "Existing enemies must keep moving while the population is at its limit")
    capped:destroy(1)
    capped:update(4, ship)
    check(#capped.items == capped.maxCount - 1, "One free slot must not spawn a partial squad")
    for _ = 1, 4 do capped:destroy(1) end
    capped:update(3.8, ship)
    check(#capped.items == capped.maxCount - 5, "Reinforcements must wait for a new spawn interval")
    capped:update(0.2, ship)
    check(#capped.items == capped.maxCount and capped.kills == 5,
        "A full replacement squad must refill the available slots")

    require("tests.enemy_steering")(Ship, Enemies, Camera, check)

    local function target(x, y, radius, prevX, prevY)
        return { x = x, y = y, radius = radius or 10, prevX = prevX or x, prevY = prevY or y }
    end
    local hits = Enemies.new()
    hits.items = { target(80, 0), target(40, 0) }
    local hx, hy, hitFraction = hits:hitSegment(0, 0, 100, 0, 0, 1)
    check(hx and hx < 40 and hy == 0 and hitFraction < 0.4
        and #hits.items == 1 and hits.items[1].x == 80 and hits.kills == 1,
        "A swept missile must destroy only the first enemy in its path")
    hits.items = { target(50, 25) }
    check(hits:hitSegment(0, 0, 100, 0, 0, 1) == nil and #hits.items == 1,
        "A near miss must leave an enemy alive")
    hits.items = { target(50, -50, 8, 50, 50) }
    check(hits:hitSegment(0, 0, 100, 0, 0, 1) ~= nil and #hits.items == 0,
        "Relative swept collision must catch enemies crossing a fast missile between frames")
    hits.items = { target(50, -50, 8, 50, 50) }
    check(hits:hitSegment(0, 0, 100, 0, 0, 0.25) == nil,
        "Missile collision must not use enemy movement from a later part of the frame")
    check(hits:hitSegment(0, 0, 100, 0, 0.375, 0.625) ~= nil,
        "Missile collision must interpolate enemy motion over the matching simulation slice")
    hits.items = { target(0, 0) }
    check(hits:hitSegment(0, 0, 0, 0, 0, 1) ~= nil,
        "Overlapping stationary missiles and enemies must still register a hit")

    ship = Ship.new(1280, 800)
    turret = Turret.new(math.pi / 2)
    missile = turret:fire(ship)
    hits = Enemies.new()
    hits.items = { target(missile.x + 40, missile.y) }
    turret:update(0.1, ship, ship.x + 1000, ship.y, false, hits)
    check(#hits.items == 0 and hits.kills == 1 and #turret.missiles == 2 and #turret.explosions == 1
        and turret.shotsHit == 1,
        "One projectile hit must count the shot and consume only the projectile that collided")
    turret = Turret.new(math.pi / 2)
    missile = turret:fire(ship)
    hits.items = { target(missile.x + 900, missile.y) }
    turret:update(1, ship, ship.x + 1000, ship.y, false, hits)
    check(#hits.items == 1 and #turret.missiles == 0 and turret.shotsHit == 0,
        "Projectiles must not hit enemies beyond their lifetime endpoints")

    -- Switch weapons during held fire while the missile is still in flight.
    ship, turret, hits = Ship.new(0, 0), Turret.new(0), Enemies.new()
    local far, outside = target(200, 0), target(400, 110)
    hits.items = { far, target(100, 0), target(400, 25), target(400, -80), outside }
    local combatView = Camera.new(ship.x, ship.y)
    turret.weapon = 2
    turret:update(0.05, ship, 400, 0, true, hits, combatView, 800, 600)
    local rocket = turret.missiles[1]
    local ejectedSideways = math.abs(rocket.y - rocket.startY) > math.abs(rocket.x - rocket.startX)
    local launchSpeed = rocket.speed
    turret:update(0.12, ship, 400, 0, true, hits, combatView, 800, 600)
    check(ejectedSideways and rocket.vx > math.abs(rocket.vy) and rocket.speed > launchSpeed,
        "A missile must eject sideways, then turn and accelerate toward its target")
    turret.weapon = 3
    turret:update(0.02, ship, 50, 0, true, hits, combatView, 800, 600)
    local impact = turret.explosions[1]
    check(hits.kills == 1 and hits.items[1] == far and turret.beam and near(turret.beam.hitX, 88)
        and turret.shotsFired == 2 and turret.shotsHit == 1
        and impact and impact.x == turret.beam.hitX and impact.y == turret.beam.hitY,
        "The laser must stop at the first hull beyond the cursor and show an effect at the hit")
    turret:drawEffects(combatView, 800, 600)
    turret.weapon = 1
    turret:update(0.5, ship, -400, 0, false, hits, combatView, 800, 600)
    check(hits.kills == 3 and #hits.items == 2 and hits.items[1] == far and hits.items[2] == outside
        and turret.shotsFired == 2 and turret.shotsHit == 2
        and #turret.explosions == 1 and near(turret.explosions[1].x, 400),
        "After switching, the missile must explode at its original target and hit each hull in range")

    do
        local movingShip = Ship.new(0, 0)
        movingShip.vx, movingShip.vy = 420, -560
        local stationary, moving = Turret.new(0), Turret.new(0)
        stationary.weapon, moving.weapon = 2, 2
        local view = Camera.new(0, 0)
        local cursorX, cursorY = 650, 330
        local aimX, aimY = view:screenToWorld(cursorX, cursorY, 800, 600)
        stationary:update(0.1, ship, aimX, aimY, true, nil, combatView, 800, 600)
        moving:update(0, movingShip, aimX, aimY, true, nil, view, 800, 600)

        movingShip.x, movingShip.y = movingShip.vx * 0.1, movingShip.vy * 0.1
        view.x, view.y = movingShip.x, movingShip.y
        moving:update(0.1, movingShip, -400, 0, false, nil, view, 800, 600)
        local stillRocket, movingRocket = stationary.missiles[1], moving.missiles[1]
        local carriesVelocity = near(movingRocket.x - stillRocket.x, movingShip.x)
            and near(movingRocket.y - stillRocket.y, movingShip.y)

        view.x, view.y, view.zoom = 210, -160, 0.85
        moving:update(0.35, movingShip, -400, 0, false, Enemies.new(), view, 800, 600)
        local blast = moving.explosions[1]
        local screenX, screenY = view:worldToScreen(blast.x, blast.y, 800, 600)
        check(carriesVelocity and near(screenX, cursorX) and near(screenY, cursorY) and moving.shotsHit == 0,
            "A missile must reach the original target after pan and zoom, and miss if no enemy is there")
    end

    do
        local laser, enemies = Turret.new(0), Enemies.new()
        local view = Camera.new(80, -30)
        view.zoom = 0.85
        laser.weapon = 3
        enemies.items = { target(650, -325) }
        laser:update(0.01, ship, 50, -25, true, enemies, view, 800, 600)

        -- The same ray reaches the top edge after panning, zooming and widening the view.
        view.x, view.y, view.zoom = -55, 80, 0.95
        local originalLine, endX, endY = love.graphics.line
        love.graphics.line = function(x1, y1, x2, y2)
            endX, endY = view:worldToScreen(x2, y2, 1280, 600)
            return originalLine(x1, y1, x2, y2)
        end
        local ok, message = pcall(laser.drawEffects, laser, view, 1280, 600)
        love.graphics.line = originalLine
        check(ok and enemies.kills == 0 and laser.shotsHit == 0 and endX and endX > 0 and endX < 1280 and near(endY, 0),
            "The laser must leave offscreen targets intact and follow the current screen edge: " .. tostring(message))
    end

    -- Verify enemies outside the screen cannot be damaged by any weapon (projectile, missile blast, laser, or homing).
    do
        local w, h = 1280, 800
        local prevW, prevH = Arena.width, Arena.height
        Arena.resize(w, h)
        local edgeShip = Ship.new(Arena.width, Arena.height)
        edgeShip.x, edgeShip.y = Arena.width - 40, Arena.height * 0.5
        local screenCam = Camera.new(Arena.width * 0.5, Arena.height * 0.5)
        screenCam:update(0, edgeShip, w, h)

        -- 1. Projectile flying off-screen must not hit off-screen enemy, even if near the edge.
        local offEnemies = Enemies.new()
        offEnemies.items = { target(Arena.width + 12, edgeShip.y, 24), target(Arena.width + 120, edgeShip.y, 24) }
        local projTurret = Turret.new(math.pi / 2)
        projTurret.weapon = 1
        projTurret:fire(edgeShip, Arena.width + 200, edgeShip.y, offEnemies, 0, screenCam, w, h)
        for _ = 1, 30 do
            projTurret:update(1 / 60, edgeShip, Arena.width + 200, edgeShip.y, false, offEnemies, screenCam, w, h)
        end
        check(offEnemies.kills == 0 and #offEnemies.items == 2,
            "Projectiles must not hit enemies outside the screen")

        -- 2. Missile blast near the screen edge must not damage off-screen enemies, while still hitting on-screen ones.
        local onEnemy = target(Arena.width - 20, edgeShip.y, 16)
        local offBlastEnemy = target(Arena.width + 15, edgeShip.y, 24)
        offEnemies.items = { onEnemy, offBlastEnemy }
        local rocketTurret = Turret.new(math.pi / 2)
        rocketTurret.weapon = 2
        rocketTurret:update(0.01, edgeShip, Arena.width - 10, edgeShip.y, true, offEnemies, screenCam, w, h)
        for _ = 1, 60 do
            rocketTurret:update(1 / 60, edgeShip, Arena.width - 10, edgeShip.y, false, offEnemies, screenCam, w, h)
        end
        check(offEnemies.kills == 1 and #offEnemies.items == 1 and offEnemies.items[1] == offBlastEnemy,
            "Missile blast must hit on-screen enemies while leaving off-screen enemies unharmed")

        -- 3. Laser aimed at an enemy whose center is outside the screen edge must not hit it.
        local edgeLaserEnemies = Enemies.new()
        edgeLaserEnemies.items = { target(Arena.width + 8, edgeShip.y, 24) }
        local laserTurret = Turret.new(math.pi / 2)
        laserTurret.weapon = 3
        laserTurret:update(0.01, edgeShip, Arena.width + 8, edgeShip.y, true, edgeLaserEnemies, screenCam, w, h)
        check(edgeLaserEnemies.kills == 0 and #edgeLaserEnemies.items == 1,
            "Laser must not hit enemies whose center lies outside the screen")

        Arena.width, Arena.height = prevW, prevH
    end
    enemyGroup:draw(1)

    local panel = Hud.new()
    local statusShip = Ship.new(1280, 800)
    check(statusShip.shield == 100 and statusShip.maxShield == 100
        and statusShip.armor == 100 and statusShip.maxArmor == 100
        and statusShip.hull == 3 and statusShip.maxHull == 3
        and statusShip.battery == 100 and statusShip.maxBattery == 100,
        "New ships must expose full shield, armor, hull, and battery values for the HUD")
    for _, value in ipairs({ 100, 50, 0, -10, 150 }) do
        statusShip.shield, statusShip.armor, statusShip.hull, statusShip.battery = value, value, value, value
        statusShip.vx = value * 10
        local oldFont = love.graphics.getFont()
        love.graphics.setColor(0.3, 0.4, 0.5, 0.6)
        love.graphics.setLineWidth(3)
        panel:draw(statusShip, 1280, 800, 1)
        panel:draw(statusShip, 800, 600, 1)
        local r, g, b, a = love.graphics.getColor()
        check(near(r, 0.3) and near(g, 0.4) and near(b, 0.5) and near(a, 0.6)
            and love.graphics.getFont() == oldFont and love.graphics.getLineWidth() == 3,
            "HUD must render full, partial, empty, and clamped gauges without leaking drawing state")
        check(statusShip.shield == value and statusShip.armor == value and statusShip.hull == value
            and statusShip.battery == value, "HUD display must not change ship resources")
    end
    statusShip.maxShield, statusShip.maxArmor, statusShip.maxHull, statusShip.maxBattery = 0, 0, 0, 0
    panel:draw(statusShip, 800, 600, 1)
    check(true, "HUD must tolerate an empty resource capacity without invalid drawing coordinates")

    -- Verify battery arc counter-clockwise depletion and proximity opacity fade (0.80 -> 0.10).
    do
        local hudPanel = Hud.new()
        local w, h = 1280, 800
        local hudShip = Ship.new(w, h)
        local hudCam = Camera.new(w / 2, h / 2)
        hudCam:update(0, hudShip, w, h)
        local hx, hy = hudPanel:center(w, h)

        -- Battery arc max angle must shrink counter-clockwise (smaller end angle) as battery depletes.
        local function maxBatteryArcEnd(batteryVal)
            hudShip.battery = batteryVal
            local batRadius = Hud.RING_OUTER_RADIUS - 3 * Hud.RING_STEP
            local maxEnd = -math.huge
            local origArc = love.graphics.arc
            love.graphics.arc = function(mode, arcType, x, y, radius, start, finish, ...)
                local _, _, _, a = love.graphics.getColor()
                if math.abs(radius - batRadius) < 1e-4 and a > 0.5 * Hud.BASE_ALPHA then
                    if finish > maxEnd then maxEnd = finish end
                end
                return origArc(mode, arcType, x, y, radius, start, finish, ...)
            end
            hudPanel:draw(hudShip, w, h, 0)
            love.graphics.arc = origArc
            return maxEnd
        end
        local endFull = maxBatteryArcEnd(100)
        local endHalf = maxBatteryArcEnd(50)
        local endQuarter = maxBatteryArcEnd(25)
        check(endFull > endHalf and endHalf > endQuarter,
            "Battery circular bar must shrink counter-clockwise as battery is consumed")

        -- Clear area: opacity stays at BASE_ALPHA (0.80).
        hudShip.x, hudShip.y = w / 2, 160
        local clearAlpha = hudPanel:update(0, { ship = hudShip, camera = hudCam }, w, h)
        check(near(clearAlpha, Hud.BASE_ALPHA), "HUD default opacity must be 80% when no entities are nearby")

        -- Player near HUD: opacity drops to PROXIMITY_ALPHA (0.10).
        hudShip.x, hudShip.y = hx, hy
        local shipNearAlpha = hudPanel:update(0, { ship = hudShip, camera = hudCam }, w, h)
        check(near(shipNearAlpha, Hud.PROXIMITY_ALPHA), "HUD must fade to 10% when the player approaches")

        -- Enemy near HUD while player is far: opacity drops to 10%.
        hudShip.x, hudShip.y = w / 2, 160
        local nearEnemies = Enemies.new()
        nearEnemies.items = { { x = hx + 20, y = hy, radius = 20 } }
        local enemyNearAlpha = hudPanel:update(0, { ship = hudShip, enemies = nearEnemies, camera = hudCam }, w, h)
        check(near(enemyNearAlpha, Hud.PROXIMITY_ALPHA), "HUD must fade to 10% when an enemy approaches")

        -- Enemy projectile near HUD: opacity drops to 10%.
        nearEnemies.items = {}
        nearEnemies.fire.shots = { { x = hx, y = hy - 40, vx = 0, vy = 200, age = 0.1, profile = { radius = 4, trail = 14 } } }
        local bulletNearAlpha = hudPanel:update(0, { ship = hudShip, enemies = nearEnemies, camera = hudCam }, w, h)
        check(near(bulletNearAlpha, Hud.PROXIMITY_ALPHA), "HUD must fade to 10% when an enemy projectile approaches")

        -- Bottom warp gate near HUD: opacity drops to 10%, then recovers smoothly when cleared.
        nearEnemies.fire.shots = {}
        local bottomGate = {
            arenaW = w, arenaH = h,
            gates = { { edge = "bottom", x = hx, y = h, dirX = 0, dirY = 1, width = 116 } },
        }
        local gateNearAlpha = hudPanel:update(0, { ship = hudShip, warpGates = bottomGate, camera = hudCam }, w, h)
        check(near(gateNearAlpha, Hud.PROXIMITY_ALPHA), "HUD must fade to 10% when a bottom warp gate overlaps it")

        local recovered = hudPanel:update(0.25, { ship = hudShip, camera = hudCam }, w, h)
        check(recovered > Hud.PROXIMITY_ALPHA and recovered <= Hud.BASE_ALPHA,
            "HUD opacity must smoothly recover toward 80% once nearby entities leave")
    end

    local stars = Starfield.new(800, 600, function() return 0.5 end)
    check(#stars.layers == 3, "Background must contain exactly three star layers")
    stars:update(1, 100, -50, 0, 800, 600)
    local lastDistance = 0
    for _, layer in ipairs(stars.layers) do
        local star = layer.stars[1]
        local distance = 400 - star.x
        check(near(distance, 100 * layer.parallax) and near(star.y, 300 + 50 * layer.parallax),
            "Star layers must scroll opposite velocity at their own parallax speeds")
        check(distance > lastDistance, "Closer stars must move faster than distant stars")
        lastDistance = distance
    end
    local star = stars.layers[1].stars[1]
    local x, y, time = star.x, star.y, stars.time
    stars:update(0.1, 0, 0, 0, 800, 600)
    check(star.x == x and star.y == y and stars.time ~= time,
        "Stationary stars must still twinkle without drifting")
    local boosted = Starfield.new(800, 600, function() return 0.5 end)
    boosted:update(1, 100, -50, 1, 800, 600)
    check(boosted.layers[1].stars[1].x < star.x, "Acceleration must strengthen the star response")
    stars:update(10, -760, 400, 1, 800, 600)
    stars:resize(1200, 700)
    stars:resize(800, 600)
    for _, layer in ipairs(stars.layers) do
        local inside = true
        for _, particle in ipairs(layer.stars) do
            inside = inside and particle.x >= 0 and particle.x < 800
                and particle.y >= 0 and particle.y < 600
        end
        check(inside, "All stars must wrap and stay inside resized bounds")
    end
    stars:draw()
    check(true, "Starfield update, resize, and draw must run")
    print(string.format("PASS: %d flight, camera, combat, enemy, HUD, and starfield checks", checks))
end
