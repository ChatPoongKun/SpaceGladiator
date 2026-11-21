return function(state)
    local g, key = love.graphics, love.keypressed
    local function drawText()
        local points, values = {}, {}
        local print, printf = g.print, g.printf
        g.print = function(label, x, y, ...)
            points[label] = {x, y}
            assert(g.getFont():hasGlyphs(label), "Missing glyph in " .. label)
            print(label, x, y, ...)
        end
        g.printf = function(label, x, y, ...)
            values[y] = label
            printf(label, x, y, ...)
        end
        local ok, message = pcall(love.draw)
        g.print, g.printf = print, printf
        assert(ok, message)
        return points, values
    end
    local function click(label)
        local point = assert(drawText()[label], "Missing button " .. label)
        love.mousepressed(point[1] + 1, point[2] + 5, 1)
    end
    local function checkRow(points, values, label, value)
        assert(points[label] and values[points[label][2]] == value, "Wrong result for " .. label)
    end

    local quit, quitRequested = love.event.quit, false
    love.event.quit = function() quitRequested = true end
    key("escape")
    assert(state() == "title" and not quitRequested and love.mouse.isVisible())
    click("게임 종료")
    assert(quitRequested)
    love.event.quit = quit

    -- Exercise the display setting without writing to the player's preferences.
    local write, saved = love.filesystem.write, nil
    love.filesystem.write = function(file, value)
        assert(file == "fullscreen.txt")
        saved = value
        return true
    end
    click("설정")
    assert(state() == "settings")
    local initiallyFull = love.window.getFullscreen()
    click(initiallyFull and "전체 화면  ·  켜짐" or "전체 화면  ·  꺼짐")
    assert(love.window.getFullscreen() ~= initiallyFull and saved == (initiallyFull and "0" or "1"))
    key("return")
    assert(love.window.getFullscreen() == initiallyFull and saved == (initiallyFull and "1" or "0"))
    love.filesystem.write = write
    click("뒤로")
    assert(state() == "title")

    click("게임 시작")
    local screen, ship, enemies, turret, gladiator = state()
    assert(screen == "playing" and not love.mouse.isVisible())
    love.update(0.05)
    assert(#turret.missiles == 0, "Starting the run must not also fire a weapon")
    local function fireVolley()
        love.mousepressed(0, 0, 1)
        love.update(0.05)
        love.mousereleased(0, 0, 1)
        assert(#turret.missiles == 3, "Weapon 1 must fire three projectiles per volley")
    end
    love.mousereleased(0, 0, 1)
    fireVolley()

    local shot, spawnAccumulator = turret.missiles[1], enemies.spawnAccumulator
    local age = shot.age
    key("space")
    key("escape")
    assert(state() == "pause" and love.mouse.isVisible())
    love.update(0.05)
    assert(shot.age == age and enemies.spawnAccumulator == spawnAccumulator)
    key("escape", nil, true)
    key("2")
    click("설정")
    love.update(0.05)
    assert(state() == "settings" and enemies.spawnAccumulator == spawnAccumulator and shot.age == age and turret.weapon == 1)
    key("escape")
    assert(state() == "pause")
    click("계속하기")
    love.update(0.05)
    assert(state() == "playing" and shot.age > age and ship.battery == ship.maxBattery)

    enemies.spawnRate = 0
    local function placeTarget(kind, projectile, flightTime)
        local enemy = enemies:spawn(ship, kind, {
            x = projectile.startX + projectile.vx * flightTime,
            y = projectile.startY + projectile.vy * flightTime,
            entryTime = 1,
        })
        enemy.thrust = 0
    end
    local function finishVolley(hits)
        local kills = enemies.kills
        for _ = 1, 6 do love.update(0.05) end
        assert(enemies.kills - kills == hits and #turret.missiles == 3 - hits,
            "Expected " .. hits .. " projectile hits in the volley")
        for _ = 1, 8 do love.update(0.05) end
        assert(#turret.missiles == 0, "The volley must resolve before the next shot")
    end

    -- Give one side projectile enough separation to hit alone.
    placeTarget(1, turret.missiles[2], 0.27)
    finishVolley(1)
    fireVolley()
    -- Stagger the impacts from this volley across updates.
    placeTarget(2, turret.missiles[2], 0.15)
    placeTarget(2, turret.missiles[3], 0.27)
    finishVolley(2)
    fireVolley()
    finishVolley(0)

    -- Record one missile dodge and one aerobatic flyby so combat results display all three point sources.
    local missilePts = gladiator:recordMissileDodge(12, 350)
    local aeroPts = gladiator:recordAerobatics(10, 420)
    local expectedTotal = 18 + missilePts + aeroPts
    assert(gladiator.total == expectedTotal)

    ship:takeDamage(119)
    key("escape")
    click("포기하기")
    assert(state() == "results")
    local points, values = drawText()
    assert(points["전투 포기"])
    checkRow(points, values, "글레디에이터 포인트", expectedTotal .. "점")
    checkRow(points, values, "적 파괴", "3회 · 18점")
    checkRow(points, values, "미사일 회피", "1회 · " .. missilePts .. "점")
    checkRow(points, values, "곡예비행", "1회 · " .. aeroPts .. "점")
    checkRow(points, values, "입은 피해", "119")
    checkRow(points, values, "실드 손실", "100")
    checkRow(points, values, "장갑 손실", "19")
    assert(not points["선체 손실"])
    checkRow(points, values, "명중률", "66.7%")
    checkRow(points, values, "격추한 적", "3기")
    checkRow(points, values, "WEDGE", "1기")
    checkRow(points, values, "EQUILATERAL", "2기")
    checkRow(points, values, "OBTUSE", "0기")
    click("확인")
    assert(state() == "title")

    key("return")
    local _, fresh, freshEnemies, _, freshGladiator = state()
    assert(fresh ~= ship and fresh.shield == fresh.maxShield and freshEnemies.kills == 0 and freshGladiator.total == 0)
    key("escape")
    key("up")
    key("return")
    assert(state() == "title", "Return to Title must bypass the run summary")

    key("return")
    local _, doomed, attackers = state()
    doomed:takeDamage(doomed.maxShield + doomed.maxArmor)
    local enemy = attackers:spawn(doomed, 2, {x = doomed.x - 60, y = doomed.y})
    for _ = 1, doomed.maxHull do attackers.fire:shoot(enemy, doomed) end
    love.update(0.05)
    assert(state() == "gameOver" and not drawText()["GAME OVER"], "The explosion must play first")
    key("escape")
    key("r")
    for _ = 1, 15 do love.update(0.05) end
    assert(state() == "gameOver" and drawText()["GAME OVER"])
    for _ = 1, 30 do love.update(0.05) end
    assert(state() == "results" and love.mouse.isVisible())
    points, values = drawText()
    assert(points["기체 파괴"] and points["전투 정산"])
    assert(not points["선체 손실"])
    checkRow(points, values, "글레디에이터 포인트", "0점")
    checkRow(points, values, "적 파괴", "0회 · 0점")
    checkRow(points, values, "미사일 회피", "0회 · 0점")
    checkRow(points, values, "곡예비행", "0회 · 0점")
    checkRow(points, values, "입은 피해", "200")
    checkRow(points, values, "명중률", "0.0%")
    checkRow(points, values, "격추한 적", "0기")
    key("return")
    assert(state() == "title")
    print("PASS: title, settings, pause, combat input, abandonment, destruction, and run summary")
end
