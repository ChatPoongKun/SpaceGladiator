local Ship = require("ship")
local Arena = require("arena")
local Starfield = require("starfield")
local Camera = require("camera")
local Turret = require("turret")
local Enemies = require("enemies")
local Gladiator = require("gladiator")
local Hud = require("hud")
local Menu = require("menu")
local Sfx = require("sfx")
local Inventory = require("inventory")
local InventoryUI = require("inventory_ui")
local Stage = require("stage")
local Plinko = require("plinko")
local PlinkoUI = require("plinko_ui")
local Replay = require("replay")
local ReplayExport = require("replay_export")

local ship, stars, fonts, camera, turret, enemies, hud, gladiator
local inventory, inventoryUI, currentBuild
local stage, plinko, plinkoUI
local replay, activeExporter
local coinWallet, lastGladiatorTotal, carriedPlinkoSlots = 0, 0, {}
local inventoryReturnScreen = "playing"
local inventoryStageEndMode = false
local permanentUnlocksFile = "grid_unlocks.txt"
local lastFeverState, lastEvasionCount, lastWrapEvents, lastDamageCount = false, 0, 0, 0
local wrapTriggerCooldown, shockwaveCooldown = 0, 0
local width, height, time = 1280, 800, 0
local screen, selectedButton
local focused = true
local gameOverHold = 1.25
local displayFile = "fullscreen.txt"
local input = { turn = 0, thrust = false, brake = false, boost = false }
local testMode = false
local testCompact, testDamaged, testFlow, testGladiator, testInventory, testPlinko, testReplay = false, false, false, false, false, false, false
local captureRequested = false
local mouseX, mouseY, firing = 0, 0, false
local weaponNames = { "PROJECTILE", "MISSILE", "LASER" }
local defaultErrorHandler = love.errorhandler

function love.errorhandler(message)
    if not (testMode or testFlow or testGladiator or testInventory or testPlinko or testReplay) then return defaultErrorHandler(message) end
    print(debug.traceback("FAIL: " .. tostring(message), 2))
    return function() return 1 end
end

local function setScreen(nextScreen)
    screen, selectedButton = nextScreen, 1
    input.boost, firing = false, false
    if screen ~= "gameOver" then Sfx.stop() end
    if screen == "playing" and replay then
        Sfx.setListener(function(cue)
            if screen == "playing" and replay then replay:recordSfxEvent(cue) end
        end)
    else
        Sfx.setListener(nil)
    end
    love.mouse.setVisible(screen ~= "playing" and screen ~= "gameOver")
    if screen == "title" then
        if activeExporter then
            activeExporter:finish("취소됨")
            activeExporter = nil
        end
        replay = nil
    end
    if screen == "title" or screen == "results" then
        ship, camera, turret, enemies, gladiator = nil, nil, nil, nil, nil
        currentBuild, stage, plinko = nil, nil, nil
        coinWallet, lastGladiatorTotal, carriedPlinkoSlots = 0, 0, {}
    end
end

local function syncInventoryBuild()
    if not inventory or not ship or not gladiator then return end
    currentBuild = inventory:computeBuild(gladiator.feverActive)
    ship:applyBuild(currentBuild)
    gladiator.scoreMultiplier = currentBuild.scoreMultiplier or 1
    lastFeverState = gladiator.feverActive
end

local function savePermanentUnlocks()
    if not inventory or testMode or testFlow or testGladiator or testInventory or testPlinko then return end
    pcall(love.filesystem.write, permanentUnlocksFile, inventory:serializeUnlockedCells())
end

local function startRun()
    ship = Ship.new(Arena.width, Arena.height)
    camera = Camera.new(ship.x, ship.y)
    camera:update(0, ship, width, height)
    turret = Turret.new(ship.angle)
    if activeExporter then
        activeExporter:finish("취소됨")
        activeExporter = nil
    end
    replay = Replay.new()
    gladiator = Gladiator.new()
    gladiator.onAward = function(category, points, x, y, fever)
        if replay then replay:recordPointEvent(category, points, x, y, fever) end
    end
    enemies = Enemies.new(nil, gladiator)
    inventory = Inventory.newStarter()
    if not (testMode or testFlow or testGladiator or testInventory or testPlinko)
        and love.filesystem.getInfo(permanentUnlocksFile) then
        inventory:loadUnlockedCells(love.filesystem.read(permanentUnlocksFile))
    end
    inventoryUI = InventoryUI.new()
    plinkoUI = PlinkoUI.new()
    plinko = nil
    coinWallet, lastGladiatorTotal, carriedPlinkoSlots = 0, 0, {}
    inventoryReturnScreen = "playing"
    inventoryStageEndMode = false
    stage = Stage.new(1)
    if not (testMode or testFlow or testGladiator or testInventory or testPlinko) then
        stage:configureEnemies(enemies)
    end
    lastEvasionCount, lastWrapEvents, lastDamageCount = 0, 0, 0
    wrapTriggerCooldown, shockwaveCooldown = 0, 0
    syncInventoryBuild()
    input.turn, input.thrust, input.brake, input.boost = 0, false, false, false
    time = 0
    setScreen("playing")
end

local function enterPlinkoStageEnd()
    if replay then replay:finalizeStage() end
    local delta = math.max(0, (gladiator.total or 0) - lastGladiatorTotal)
    lastGladiatorTotal = gladiator.total or 0
    coinWallet = coinWallet + delta
    if enemies and enemies.fire then enemies.fire.items = {} end
    plinko = Plinko.new({
        stageNumber = stage and stage.number or 1,
        coins = coinWallet,
        carriedSlots = carriedPlinkoSlots,
        carryoverEnabled = false,
    })
    setScreen("plinko")
    Sfx.play("stage_clear")
end

local function launchNextStage()
    if inventoryUI and inventory then
        inventoryUI:cancelDrag(inventory)
    end
    if inventory then
        inventory:discardPendingRewards()
    end
    inventoryStageEndMode = false
    inventoryReturnScreen = "playing"
    stage = stage and stage:nextStage() or Stage.new(2)
    enemies.items = {}
    if enemies.fire then enemies.fire.items = {} end
    enemies.spawnAccumulator = 0.5
    stage:configureEnemies(enemies)
    syncInventoryBuild()
    savePermanentUnlocks()
    setScreen("playing")
end

local function closeInventoryScreen()
    if inventoryUI and inventory then
        inventoryUI:cancelDrag(inventory)
    end
    syncInventoryBuild()
    savePermanentUnlocks()
    if inventoryReturnScreen == "nextStage" then
        launchNextStage()
        return
    end
    local target = inventoryReturnScreen or "playing"
    if target ~= "plinko" then
        inventoryStageEndMode = false
    end
    setScreen(target)
end

local function advanceToNextStage()
    if plinko then
        plinko:resolveAll(inventory, ship)
        coinWallet = plinko.coins
        carriedPlinkoSlots = plinko:exportCarryoverSlots()
        plinko = nil
    end
    if inventory and inventory:pendingCount() > 0 then
        inventoryReturnScreen = "nextStage"
        inventoryStageEndMode = true
        setScreen("inventory")
        return
    end
    launchNextStage()
end

local menus = {}

local function closeReplay()
    if activeExporter then
        activeExporter:finish("내보내기 취소됨")
        activeExporter = nil
        if replay then replay.exporting = false end
    end
    if replay then replay:closePlayback() end
    setScreen("results")
end

local function openReplay()
    if replay and replay:openPlayback(width, height) then
        setScreen("replay")
    end
end

local function startReplayExport()
    if activeExporter or not replay or not replay:hasHighlight() then return end
    replay.exportError = nil
    replay.exportStatus = "MP4 인코딩 준비 중..."
    local exporter, err = ReplayExport.start(replay.bestClip, fonts)
    if not exporter then
        replay.exportStatus = nil
        replay.exportError = err or "MP4 내보내기 시작 실패"
        return
    end
    activeExporter = exporter
    replay.exporting = true
    replay.exportProgress = 0
    replay.exportStatus = "MP4 인코딩 중..."
    replay.playing = false
    Sfx.stop()
end

local function showResults(reason)
    if replay then replay:finalizeStage() end
    local shield = ship.maxShield - ship.shield
    local armor = ship.maxArmor - ship.armor
    local rows = {
        {label = "글레디에이터 포인트", value = gladiator.total .. "점", heading = true},
        {label = "적 파괴", value = string.format("%d회 · %d점", gladiator.destroy.count, gladiator.destroy.points)},
        {label = "미사일 회피", value = string.format("%d회 · %d점", gladiator.missileDodge.count, gladiator.missileDodge.points)},
        {label = "곡예비행", value = string.format("%d회 · %d점", gladiator.aerobatics.count, gladiator.aerobatics.points)},
        {label = "피버타임 유지시간", value = string.format("%.1f초", gladiator.feverTotalTime)},
        {label = "피버타임 최대 지속시간", value = string.format("%.1f초", gladiator.feverMaxDuration)},
        {label = "입은 피해", value = tostring(shield + armor), heading = true},
        {label = "실드 손실", value = tostring(shield)},
        {label = "장갑 손실", value = tostring(armor)},
        {label = "격추한 적", value = enemies.kills .. "기", heading = true},
    }
    for i, kind in ipairs(Enemies.types) do
        rows[#rows + 1] = {label = kind.name, value = (enemies.killsByKind[i] or 0) .. "기", vertices = kind.vertices}
    end
    local accuracy = turret.shotsFired > 0 and 100 * turret.shotsHit / turret.shotsFired or 0
    rows[#rows + 1] = {label = "명중률", value = string.format("%.1f%%", accuracy), heading = true}
    local resultButtons = {}
    if replay and replay:hasHighlight() then
        resultButtons[#resultButtons + 1] = {label = "하이라이트 보기", action = openReplay}
    end
    resultButtons[#resultButtons + 1] = {label = "확인", action = function() setScreen("title") end}
    menus.results.buttons = resultButtons
    menus.results.subtitle, menus.results.rows = reason, rows
    setScreen("results")
end

local function openSettings()
    menus.settings.subtitle = nil
    setScreen("settings")
end

local function closeSettings()
    setScreen(ship and "pause" or "title")
end

local function fullscreenLabel()
    return love.window.getFullscreen() and "전체 화면  ·  켜짐" or "전체 화면  ·  꺼짐"
end

local function toggleFullscreen()
    local fullscreen = not love.window.getFullscreen()
    if not love.window.setFullscreen(fullscreen, "desktop") then
        menus.settings.subtitle = "화면 모드를 변경할 수 없습니다."
        return
    end
    love.resize(love.graphics.getDimensions())
    menus.settings.subtitle = nil
    if not love.filesystem.write(displayFile, fullscreen and "1" or "0") then
        menus.settings.subtitle = "화면 설정을 저장할 수 없습니다."
    end
end

menus.title = {title = "DRIFT", buttons = {
    {label = "게임 시작", action = startRun},
    {label = "설정", action = openSettings},
    {label = "게임 종료", action = function() love.event.quit() end},
}}
menus.pause = {title = "일시정지", buttons = {
    {label = "계속하기", action = function() setScreen("playing") end},
    {label = "설정", action = openSettings},
    {label = "포기하기", action = function() showResults("전투 포기") end},
    {label = "타이틀로 나가기", action = function() setScreen("title") end},
}}
menus.settings = {title = "설정", buttons = {
    {label = fullscreenLabel, action = toggleFullscreen},
    {label = "뒤로", action = closeSettings},
}}
menus.results = {title = "전투 정산", buttons = {
    {label = "확인", action = function() setScreen("title") end},
}}
local gameOverMenu = {title = "GAME OVER", subtitle = "기체 파괴"}
local unfocusedMenu = {title = "일시정지", subtitle = "게임 창으로 돌아오면 전투를 계속합니다."}

function love.load(args)
    for _, arg in ipairs(args or {}) do
        if arg == "--test" then testMode = true end
        if arg == "--test-flow" then testFlow = true end
        if arg == "--test-gladiator" then testGladiator = true end
        if arg == "--test-inventory" then testInventory = true end
        if arg == "--test-plinko" then testPlinko = true end
        if arg == "--test-replay" then testReplay = true end
        if arg == "--test-compact" then testMode, testCompact = true, true end
        if arg == "--test-damaged" then testMode, testDamaged = true, true end
    end
    love.graphics.setBackgroundColor(0.018, 0.028, 0.055)
    love.graphics.setLineStyle("smooth")
    if not (testMode or testFlow or testGladiator or testInventory or testPlinko) and love.filesystem.getInfo(displayFile)
        and love.filesystem.read(displayFile) == "1" then
        love.window.setFullscreen(true, "desktop")
    end
    width, height = love.graphics.getDimensions()
    local menuFont = "assets/fonts/DriftMenu.ttf"
    fonts = {
        small = love.graphics.newFont(11),
        body = love.graphics.newFont(13),
        title = love.graphics.newFont(30),
        menuTitle = love.graphics.newFont(menuFont, 34),
        menuButton = love.graphics.newFont(menuFont, 18),
        menuBody = love.graphics.newFont(menuFont, 15),
    }
    hud = Hud.new()
    stars = Starfield.new(width, height)
    if not (testMode or testFlow or testGladiator or testInventory or testPlinko) then Sfx.load() end
    setScreen("title")
    if testGladiator then
        require("tests.gladiator")(Ship, Enemies, Turret, Gladiator)
        love.event.quit(0)
        return
    end
    if testInventory then
        require("tests.inventory")(Inventory, Ship, Turret, Gladiator)
        love.event.quit(0)
        return
    end
    if testPlinko then
        require("tests.plinko_stage")(Stage, Plinko, Inventory, Ship, Enemies)
        love.event.quit(0)
        return
    end
    if testReplay then
        require("tests.replay")(Replay, ReplayExport)
        love.event.quit(0)
        return
    end
    if testFlow then
        require("tests.flow")(function() return screen, ship, enemies, turret, gladiator end)
        love.event.quit(0)
        return
    end
    if testCompact then
        love.window.updateMode(800, 600)
        love.resize(800, 600)
    end
    if testMode then
        require("tests.check")(Ship, Starfield, Camera, Turret, Enemies, Hud)
        startRun()
        -- Exercise the real input, update, and draw callbacks in the arena.
        for frame = 1, 900 do
            if frame == 120 then love.keypressed("space") end
            love.update(1 / 60)
            if frame == 120 then assert(ship.battery == ship.maxBattery - ship.boostCost) end
        end
        if testDamaged then ship.shield, ship.armor, ship.hull, ship.battery = 27, 68, 2, 42 end
    end
end

function love.update(dt)
    if not focused and not testMode then return end
    dt = math.min(dt, 1 / 20)
    if dt <= 0 then return end
    if screen == "replay" and replay then
        if activeExporter then
            local finished = activeExporter:step()
            replay.exportProgress = activeExporter:progress()
            if finished then
                replay.exporting = false
                if activeExporter.error then
                    replay.exportStatus = nil
                    replay.exportError = activeExporter.error
                else
                    replay.exportError = nil
                    replay.lastExportPath = activeExporter.mp4Path
                    replay.exportStatus = "저장 완료: replays/" .. activeExporter.filename
                end
                activeExporter = nil
            end
        else
            replay:updatePlayback(dt, width, height)
        end
        return
    end
    if not ship then
        stars:update(dt, 12, -18, 0, width, height, 0)
        return
    end
    if screen == "plinko" then
        if plinko then plinko:update(dt, inventory, ship) end
        stars:update(dt, 18, -24, 0, width, height, 0)
        return
    end
    if screen == "pause" or screen == "settings" or screen == "inventory" then return end
    time = time + dt
    if screen == "gameOver" then
        ship:update(dt, input)
        gladiator:update(dt, ship)
        if ship.destructionAge >= Ship.destructionDuration + gameOverHold then
            showResults("기체 파괴")
        end
        return
    end
    input.turn = (love.keyboard.isDown("d") and 1 or 0)
        - (love.keyboard.isDown("a") and 1 or 0)
    input.thrust = love.keyboard.isDown("w")
    input.brake = love.keyboard.isDown("s")
    mouseX, mouseY = love.mouse.getPosition()
    if testMode then
        input.turn, input.thrust, input.brake = 0.55, true, false
        mouseX, mouseY, firing = width * 0.60, height * 0.24, true
    end

    ship:update(dt, input)
    input.boost = false
    camera:update(dt, ship, width, height)
    local surge = 1050 * ship.boostLevel
    local vx, vy = ship:worldVelocity()
    stars:update(dt, 120 + vx * 2.8 + ship.boostX * surge,
        -290 + vy * 2.8 + ship.boostY * surge,
        ship.accelerating and 1 or 0, width, height, ship.boostLevel)
    enemies:update(dt, ship, turret.angle, camera, width, height)
    if ship:isDestroyed() then
        setScreen("gameOver")
        return
    end
    local worldX, worldY = camera:screenToWorld(mouseX, mouseY, width, height)
    if currentBuild and gladiator.feverActive ~= lastFeverState then
        syncInventoryBuild()
    end
    local activeWeaponBuild = currentBuild and currentBuild.weapons[turret.weapon] or nil
    turret:update(dt, ship, worldX, worldY, firing, enemies, camera, width, height, activeWeaponBuild)
    gladiator:update(dt, ship)
    if replay then
        replay:recordFrame(dt, ship, camera, turret, enemies, gladiator, stage)
    end

    -- Sync 1:1 Gladiator Coins and check stage completion (timer or all squads cleared)
    if gladiator and (gladiator.total or 0) > lastGladiatorTotal then
        coinWallet = coinWallet + (gladiator.total - lastGladiatorTotal)
        lastGladiatorTotal = gladiator.total
    end
    if stage and not (testMode or testFlow or testGladiator or testInventory or testPlinko) then
        if stage:update(dt, enemies) then
            enterPlinkoStageEnd()
            return
        end
    end

    if currentBuild then
        wrapTriggerCooldown = math.max(0, wrapTriggerCooldown - dt)
        shockwaveCooldown = math.max(0, shockwaveCooldown - dt)

        -- On-dodge triggers & dodge battery recharge
        if (gladiator.evasionCount or 0) > lastEvasionCount then
            lastEvasionCount = gladiator.evasionCount
            if (currentBuild.onDodgeBattery or 0) > 0 then
                ship:rechargeBattery(currentBuild.onDodgeBattery)
            end
            for w = 1, 3 do
                local wCfg = currentBuild.weapons[w]
                if wCfg.installed and wCfg.triggerOnDodge then
                    turret:fireTriggered(w, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
                        free = wCfg.autoBatteryZero,
                    })
                end
            end
        end

        -- On-wrap triggers
        if (ship.wrapEvents or 0) > lastWrapEvents then
            lastWrapEvents = ship.wrapEvents
            if wrapTriggerCooldown <= 0 then
                for w = 1, 3 do
                    local wCfg = currentBuild.weapons[w]
                    if wCfg.installed and wCfg.triggerOnWrap then
                        turret:fireTriggered(w, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
                            free = true, areaMult = wCfg.areaMult,
                        })
                        wrapTriggerCooldown = wCfg.wrapTriggerCooldown or 1.5
                    end
                end
            end
        end

        -- On-hit triggers (counter fire + shockwave bullet clear)
        if (ship.damageCount or 0) > lastDamageCount then
            lastDamageCount = ship.damageCount
            if currentBuild.shockwaveOnHit and shockwaveCooldown <= 0 and enemies and enemies.fire and enemies.fire.items then
                local rSq = (currentBuild.shockwaveRadius or 180) ^ 2
                for bi = #enemies.fire.items, 1, -1 do
                    local b = enemies.fire.items[bi]
                    local bdx, bdy = (b.x or 0) - ship.x, (b.y or 0) - ship.y
                    if bdx * bdx + bdy * bdy <= rSq then
                        table.remove(enemies.fire.items, bi)
                    end
                end
                shockwaveCooldown = currentBuild.shockwaveCooldown or 4.0
            end
            for w = 1, 3 do
                local wCfg = currentBuild.weapons[w]
                if wCfg.installed and wCfg.triggerOnHit and (ship.battery or 0) >= (wCfg.hitTriggerBattery or 15) then
                    ship.battery = ship.battery - (wCfg.hitTriggerBattery or 15)
                    turret:fireTriggered(w, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
                        radialCount = wCfg.radialCount or 6,
                    })
                end
            end
        end
    end
end

local function label(text, x, y, alpha)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.53, 0.65, 0.75, alpha or 1)
    love.graphics.print(text, x, y)
end

local function keycap(key, text, x, y, active)
    local g = love.graphics
    local keyWidth = key == "SPACE" and 48 or 27
    g.setColor(0.10, 0.19, 0.24, active and 0.95 or 0.45)
    g.rectangle("fill", x, y, keyWidth, 27, 5, 5)
    g.setColor(0.34, 0.70, 0.76, active and 0.9 or 0.24)
    g.rectangle("line", x, y, keyWidth, 27, 5, 5)
    g.setFont(fonts.body)
    g.setColor(0.75, 0.91, 0.96, 1)
    g.printf(key, x, y + 6, keyWidth, "center")
    g.setColor(0.53, 0.65, 0.75, 1)
    g.print(text, x + keyWidth + 9, y + 6)
end

local function drawHud()
    local g = love.graphics
    -- Keep telemetry legible when enemies or explosions pass behind it.
    g.setColor(0.018, 0.028, 0.055, 0.72)
    g.rectangle("fill", 0, 0, width, 104)
    g.setColor(0.25, 0.47, 0.58, 0.16)
    g.setLineWidth(1)
    g.line(32, 103, width - 32, 103)
    g.setFont(fonts.title)
    g.setColor(0.83, 0.93, 0.97, 1)
    g.print("D R I F T", 32, 25)
    label(stage and string.format("STAGE %02d  /  %.1fS", stage.number, stage:remainingTime()) or "04  /  TACTICAL FLIGHT", 34, 66)
    local gx, gw = math.floor(width / 2) - 115, 230
    g.setFont(fonts.small)
    if gladiator.feverActive then
        local pulse = 0.78 + 0.22 * math.sin(time * 14)
        g.setColor(1, 0.84, 0.34, pulse)
        g.printf(string.format("FEVER TIME x2  /  %.1fS", gladiator.feverDuration), gx, 26, gw, "center")
        g.setFont(fonts.title)
        g.setColor(1, 0.92, 0.52, 1)
        g.printf(string.format("%04d", gladiator.total), gx, 43, gw, "center")
        local rate = gladiator:feverAverageRate()
        local barW = 148
        local barX, barY = math.floor(width / 2 - barW / 2), 82
        local ratio = math.min(1, rate / gladiator.feverSustainRate)
        g.setColor(0.18, 0.14, 0.22, 0.85)
        g.rectangle("fill", barX, barY, barW, 5, 2, 2)
        if gladiator.feverDuration < gladiator.feverMinDuration or rate >= gladiator.feverSustainRate then
            g.setColor(1, 0.82, 0.32, 0.95)
        else
            g.setColor(1, 0.36, 0.48, 0.95)
        end
        g.rectangle("fill", barX, barY, math.max(3, barW * ratio), 5, 2, 2)
        g.setFont(fonts.small)
        g.setColor(1, 0.88, 0.58, 0.9)
        g.printf(string.format("%d / %d PTS/S", math.floor(rate + 0.5), gladiator.feverSustainRate),
            gx, 89, gw, "center")
    else
        g.setColor(0.53, 0.65, 0.75, 1)
        g.printf("GLADIATOR COINS", gx, 29, gw, "center")
        g.setFont(fonts.title)
        if gladiator.lastEvent then
            g.setColor(1, 0.84, 0.44, 1)
        else
            g.setColor(0.92, 0.86, 0.68, 1)
        end
        g.printf(string.format("%04d", gladiator.total), gx, 46, gw, "center")
        if gladiator.feverCooldown > 0 then
            g.setFont(fonts.small)
            g.setColor(0.58, 0.66, 0.76, 0.82)
            g.printf(string.format("FEVER COOLDOWN  %.1fS", gladiator.feverCooldown), gx, 82, gw, "center")
        else
            local recent = gladiator:recentPoints()
            if recent > 0 then
                local barW = 128
                local barX, barY = math.floor(width / 2 - barW / 2), 84
                g.setColor(0.12, 0.18, 0.24, 0.85)
                g.rectangle("fill", barX, barY, barW, 4, 2, 2)
                g.setColor(1, 0.78, 0.34, 0.9)
                g.rectangle("fill", barX, barY, barW * math.min(1, recent / gladiator.feverThreshold), 4, 2, 2)
            elseif gladiator.lastEvent then
                local fade = math.max(0, 1 - gladiator.lastEvent.age / gladiator.noticeDuration)
                g.setFont(fonts.small)
                g.setColor(1, 0.82, 0.40, fade)
                g.printf(string.format("+%d  %s", gladiator.lastEvent.points, gladiator.lastEvent.label),
                    gx, 82, gw, "center")
            end
        end
    end
    local sx = width - 232
    label("HOSTILES  /  DESTROYED", sx, 29)
    g.setFont(fonts.title)
    g.setColor(0.86, 0.91, 0.93, 1)
    g.print(string.format("%02d  /  %03d", #enemies.items, enemies.kills), sx, 46)

    hud:draw(ship, width, height, time)
    local y = height - 183
    label("FLIGHT CONTROLS", 24, y - 12)
    keycap("W", "THRUST", 24, y + 4, ship.accelerating)
    keycap("S", "BRAKE", 24, y + 33, ship.braking)
    keycap("A/D", "ROTATE", 24, y + 62, input.turn ~= 0)
    keycap("SPACE", "BOOST", 24, y + 91, ship.boostLevel > 0)
    keycap("1-3", turret.weapon .. " / " .. weaponNames[turret.weapon], 24, y + 120, true)
    keycap("LMB", "FIRE", 24, y + 149, firing)

    local mode = ship.braking and "BRAKING" or ship.accelerating and "THRUST" or "COAST"
    if ship.boostLevel > 0 then mode = "BOOST" end
    if screen ~= "playing" or not focused then mode = "PAUSED" end
    if ship:isDestroyed() then mode = "DESTROYED" end
    local mx = width - 180
    g.setColor(0.38, 0.91, 0.78, 0.85)
    g.circle("fill", mx, y + 14, 3)
    label(mode, mx + 12, y + 8)
    label(string.format("ZOOM  %d%%", math.floor(camera.zoom * 100 + 0.5)), mx - 3, y + 59)
    label("TAB / I  GRID", mx - 3, height - 85)
    label("R  RESET", mx - 3, height - 63)
    label("ESC / P  PAUSE", mx - 3, height - 41)
end

local function wrapOffsets(position, extent, reach)
    if position < reach then return {0, extent} end
    if position > extent - reach then return {0, -extent} end
    return {0}
end

local function drawPlayer(originX, originY)
    local g = love.graphics
    g.push("all")
    g.intersectScissor(originX, originY, Arena.width * camera.zoom, Arena.height * camera.zoom)
    local destroyed = ship:isDestroyed()
    if not destroyed then ship:drawBoostPulse() end
    -- Include the longer boost plume when deciding which copies can reach the arena.
    local reach = destroyed and 90 or 75 + 70 * ship.boostLevel
    local xOffsets = wrapOffsets(ship.x, Arena.width, reach)
    local yOffsets = wrapOffsets(ship.y, Arena.height, reach)
    for _, dx in ipairs(xOffsets) do
        for _, dy in ipairs(yOffsets) do
            g.push()
            g.translate(dx, dy)
            if destroyed then
                ship:drawDestruction()
            else
                ship:draw(time)
                turret:drawMount(ship, time)
            end
            g.pop()
        end
    end
    g.pop()
end

local function drawFlight()
    love.graphics.push()
    local originX, originY = camera:worldToScreen(0, 0, width, height)
    love.graphics.translate(originX, originY)
    love.graphics.scale(camera.zoom)
    Arena.draw(ship.boostLevel, gladiator.feverAura)
    enemies:draw(time)
    gladiator:drawFeverWorld(ship, time)
    drawPlayer(originX, originY)
    turret:drawEffects(camera, width, height)
    love.graphics.pop()
    gladiator:drawFeverOverlay(width, height, time)
    gladiator:drawPopups(camera, width, height, fonts.small)
    drawHud()
    if screen == "playing" and (focused or testMode) then
        local g = love.graphics
        local x, y = love.mouse.getPosition()
        if testMode then x, y = mouseX, mouseY end
        g.setLineWidth(1)
        if firing then g.setColor(1, 0.72, 0.36, 0.8)
        else g.setColor(0.48, 0.88, 0.94, 0.7) end
        g.circle("line", x, y, 7)
        g.line(x - 12, y, x - 9, y)
        g.line(x + 9, y, x + 12, y)
        g.line(x, y - 12, x, y - 9)
        g.line(x, y + 9, x, y + 12)
    end
end

function love.draw()
    if screen == "replay" and replay then
        replay:drawPlayback(width, height, fonts)
        return
    end
    stars:draw()
    if ship then drawFlight() end
    local menu = menus[screen]
    if screen == "gameOver" and ship.destructionAge >= Ship.destructionDuration then
        menu = gameOverMenu
    elseif screen == "playing" and not focused and not testMode then
        menu = unfocusedMenu
    end
    if screen == "plinko" and plinko and plinkoUI then
        plinkoUI:draw(plinko, stage, fonts, width, height, inventory and inventory:pendingCount() or 0)
    elseif screen == "inventory" and inventory and inventoryUI then
        inventoryUI:draw(inventory, fonts, width, height, gladiator and gladiator.feverActive, {
            stageEndMode = inventoryStageEndMode,
            returnTarget = inventoryReturnScreen,
        })
    elseif menu then
        Menu.draw(menu, fonts, selectedButton, width, height, ship ~= nil)
    end
    if testMode and not captureRequested then
        captureRequested = true
        love.graphics.captureScreenshot(function(data)
            local name = testCompact and "hud-compact-preview.png"
                or testDamaged and "hud-damaged-preview.png" or "flight-preview.png"
            local file = assert(io.open(love.filesystem.getSource() .. "/" .. name, "wb"))
            file:write(data:encode("png"):getString())
            file:close()
            print("PASS: update/draw smoke test; " .. name .. " saved")
            love.event.quit(0)
        end)
    end
end

function love.keypressed(key, _, isRepeat)
    if isRepeat then return end
    if screen == "replay" and replay then
        if key == "escape" then
            closeReplay()
        elseif key == "space" and not activeExporter then
            replay:togglePlay()
        elseif key == "r" and not activeExporter then
            replay:restartPlayback()
        elseif key == "e" then
            startReplayExport()
        end
        return
    end
    if key == "tab" or key == "i" then
        if screen == "playing" or screen == "plinko" then
            inventoryReturnScreen = screen
            inventoryStageEndMode = (screen == "plinko")
            setScreen("inventory")
            return
        elseif screen == "inventory" then
            closeInventoryScreen()
            return
        end
    end
    if screen == "plinko" then
        if key == "space" and plinko then
            plinko:invest(10)
        elseif key == "return" or key == "kpenter" then
            advanceToNextStage()
        end
        return
    end
    if screen == "inventory" then
        if key == "escape" then
            if inventoryUI and inventory and inventoryUI.dragging then
                inventoryUI:cancelDrag(inventory)
                Sfx.play("ui_click")
            else
                closeInventoryScreen()
            end
        elseif (key == "return" or key == "kpenter") and inventoryReturnScreen == "nextStage" then
            closeInventoryScreen()
        elseif inventoryUI and inventory then
            if inventoryUI:keypressed(inventory, key) == "changed" then
                syncInventoryBuild()
                savePermanentUnlocks()
            end
        end
        return
    end
    if key == "escape" or key == "p" then
        if screen == "playing" then setScreen("pause")
        elseif screen == "pause" then setScreen("playing")
        elseif screen == "settings" and key == "escape" then closeSettings() end
        return
    end

    local menu = menus[screen]
    if menu then
        if key == "up" then
            selectedButton = (selectedButton - 2) % #menu.buttons + 1
            Sfx.play("ui_hover")
        elseif key == "down" then
            selectedButton = selectedButton % #menu.buttons + 1
            Sfx.play("ui_hover")
        elseif key == "return" or key == "kpenter" then
            Sfx.play("ui_click")
            menu.buttons[selectedButton].action()
        end
        return
    end

    if screen ~= "playing" then return end
    if key == "r" then startRun()
    elseif key == "1" or key == "2" or key == "3" then turret.weapon = tonumber(key); Sfx.play("ui_hover")
    elseif key == "space" and (focused or testMode) then input.boost = true end
end

function love.mousemoved(x, y)
    if screen == "inventory" and inventoryUI then
        inventoryUI:mousemoved(x, y)
        return
    elseif screen == "plinko" and plinkoUI then
        plinkoUI:mousemoved(x, y)
        return
    end
    local menu = menus[screen]
    if menu then
        local hovered = Menu.buttonAt(menu, width, height, x, y)
        if hovered and hovered ~= selectedButton then
            selectedButton = hovered
            Sfx.play("ui_hover")
        end
    end
end

function love.mousepressed(x, y, button)
    if screen == "inventory" and inventory and inventoryUI then
        local action = inventoryUI:mousepressed(inventory, x, y, button, {
            stageEndMode = inventoryStageEndMode,
        })
        if action == "close" then
            closeInventoryScreen()
        elseif action == "changed" then
            syncInventoryBuild()
            savePermanentUnlocks()
        end
        return
    end
    if button ~= 1 then return end
    if screen == "replay" and replay then
        local action = replay:buttonAt(x, y)
        if action == "toggle" and not activeExporter then
            replay:togglePlay()
        elseif action == "restart" and not activeExporter then
            replay:restartPlayback()
        elseif action == "export" then
            startReplayExport()
        elseif action == "back" then
            closeReplay()
        end
        return
    end
    if screen == "plinko" and plinko and plinkoUI then
        local action = plinkoUI:mousepressed(plinko, x, y, button)
        if action == "openInventory" then
            inventoryReturnScreen = "plinko"
            inventoryStageEndMode = true
            setScreen("inventory")
        elseif action == "nextStage" then
            advanceToNextStage()
        end
        return
    end
    if screen == "playing" then
        firing = focused
        return
    end
    local menu = menus[screen]
    if not menu then return end
    local index = Menu.buttonAt(menu, width, height, x, y)
    if index then
        selectedButton = index
        Sfx.play("ui_click")
        menu.buttons[index].action()
    end
end

function love.mousereleased(x, y, button)
    if screen == "inventory" and inventory and inventoryUI then
        local action = inventoryUI:mousereleased(inventory, x, y, button, {
            stageEndMode = inventoryStageEndMode,
        })
        if action == "close" then
            closeInventoryScreen()
        elseif action == "changed" then
            syncInventoryBuild()
            savePermanentUnlocks()
        end
        return
    end
    if button == 1 then firing = false end
end

function love.focus(hasFocus)
    focused = hasFocus
    if not focused then
        input.boost, firing = false, false
        Sfx.stop()
    end
end

function love.resize(w, h)
    width, height = w, h
    stars:resize(w, h)
    if replay and replay.stars then replay.stars:resize(w, h) end
    if camera then camera:update(0, ship, w, h) end
end
