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
    -- Exercise Fever Time duration tracking for combat results display.
    gladiator:startFever(ship.x, ship.y)
    gladiator:update(2.4, ship)
    gladiator:endFever()

    ship:takeDamage(119)
    -- Enabling a noShield build after taking shield damage must not erase recorded shield loss in results.
    ship:applyBuild({ noShield = true })
    assert(ship.maxShield == 0 and ship.shield == 0)
    key("escape")
    click("포기하기")
    assert(state() == "results")
    local points, values = drawText()
    assert(points["전투 포기"])
    checkRow(points, values, "글레디에이터 포인트", expectedTotal .. "점")
    checkRow(points, values, "적 파괴", "3회 · 18점")
    checkRow(points, values, "미사일 회피", "1회 · " .. missilePts .. "점")
    checkRow(points, values, "곡예비행", "1회 · " .. aeroPts .. "점")
    checkRow(points, values, "피버타임 유지시간", "2.4초")
    checkRow(points, values, "피버타임 최대 지속시간", "2.4초")
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
    checkRow(points, values, "피버타임 유지시간", "0.0초")
    checkRow(points, values, "피버타임 최대 지속시간", "0.0초")
    checkRow(points, values, "입은 피해", "200")
    checkRow(points, values, "명중률", "0.0%")
    checkRow(points, values, "격추한 적", "0기")
    key("return")
    assert(state() == "title")

    -- Ending a stage during Fever Time and returning from Plinko must clear all fever effects.
    click("게임 시작")
    local _, feverShip, _, _, feverGlad, triggerStageClear = state()
    feverGlad:award("destroy", 35, "DESTROY", feverShip.x, feverShip.y)
    love.update(0.05)
    love.update(0.05)
    assert(feverGlad.feverActive and feverGlad.feverAura > 0 and #feverGlad.feverSparks > 0,
        "Fever Time and visual effects must be active before stage clear")
    local recordedFeverTime = feverGlad.feverTotalTime
    triggerStageClear()
    assert(state() == "stageClear")
    for _ = 1, 45 do love.update(0.05) end
    assert(state() == "plinko", "Stage clear must transition into Plinko after 2 seconds")
    for _ = 1, 10 do love.update(0.05) end
    key("return")
    assert(state() == "warpSelect", "Leaving Plinko must return to battlefield warp selection")
    assert(not feverGlad.feverActive and feverGlad.feverAura == 0 and feverGlad.feverFlash == 0
        and feverGlad.feverCooldown == 0 and #feverGlad.feverBursts == 0
        and #feverGlad.feverSparks == 0 and #feverGlad.popups == 0 and feverGlad.lastEvent == nil,
        "Returning from Plinko must have all fever state and visual effects cleared")
    assert(math.abs(feverGlad.feverTotalTime - recordedFeverTime) < 1e-6
        and math.abs(feverGlad.feverMaxDuration - recordedFeverTime) < 1e-6,
        "Returning from Plinko must preserve recorded fever statistics")
    -- Also verify clearFever clears any pending cooldown between stages.
    feverGlad.feverCooldown = 3.0
    feverGlad:clearFever()
    assert(feverGlad.feverCooldown == 0, "clearFever must also clear remaining fever cooldown")
    local _, warpValues = drawText()
    for _, text in pairs(warpValues) do
        assert(not tostring(text):find("FEVER", 1, true),
            "HUD must not display active fever or cooldown after returning from Plinko: " .. tostring(text))
    end
    key("escape")
    key("up")
    key("return")
    assert(state() == "title")

    -- Stage transition movement must not register boundary crossing or fire Wrapping Condenser on next stage start.
    click("게임 시작")
    local _, wrapShip, _, wrapTurret, _, triggerWrapStageClear, wrapInv, _, syncBuild = state()
    assert(wrapInv:equipChip(wrapInv.placed[1], 1, wrapInv:createChip("wrap_trigger")),
        "Wrapping Condenser must equip on starter projectile module")
    syncBuild()
    -- Cross boundary while braking during stageClear
    wrapShip.x, wrapShip.vx = 5, -180
    triggerWrapStageClear()
    assert(state() == "stageClear")
    for _ = 1, 45 do love.update(0.05) end
    assert(state() == "plinko")
    assert(wrapShip.wrapEvents == 0, "Boundary movement during stageClear must not trigger wrapEvents")
    for _ = 1, 10 do love.update(0.05) end
    key("return")
    assert(state() == "warpSelect")
    -- Advance past warp gate readyDelay, cross boundary during warpSelect, then fly into a warp gate
    for _ = 1, 8 do love.update(0.05) end
    local _, _, _, _, _, _, _, gatesState = state()
    local gate = gatesState.gates[1]
    wrapShip.x, wrapShip.y = gate.x - gate.dirX * 49, gate.y - gate.dirY * 49
    wrapShip.vx, wrapShip.vy = gate.dirX * 420, gate.dirY * 420
    love.update(0.05)
    assert(state() == "warping", "Flying into warp gate must start warping")
    assert(wrapShip.wrapEvents == 0, "Crossing boundary during warpSelect must not trigger wrapEvents")
    for _ = 1, 60 do love.update(0.05) end
    assert(state() == "playing", "Completing warp must start the next stage")
    love.update(0.05)
    assert(#wrapTurret.missiles == 0 and wrapTurret.shotsFired == 0,
        "Wrapping Condenser must not fire immediately on starting the next stage")
    -- In active combat on the new stage, genuine boundary crossing must still trigger Wrapping Condenser
    wrapShip.x, wrapShip.vx, wrapShip.wrapVx = 5, -180, 0
    love.update(0.05)
    assert(wrapShip.wrapEvents == 1 and #wrapTurret.missiles > 0,
        "Wrapping Condenser must still fire on genuine boundary crossing during combat")
    key("escape")
    key("up")
    key("return")
    assert(state() == "title")

    print("PASS: title, settings, pause, combat input, abandonment, destruction, and run summary")
end
