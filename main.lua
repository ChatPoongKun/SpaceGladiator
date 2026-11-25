local Ship = require("src.combat.ship")
local Arena = require("src.core.arena")
local Display = require("src.core.display")
local Starfield = require("src.visual.starfield")
local StageBackground = require("src.visual.stage_background")
local Camera = require("src.core.camera")
local Turret = require("src.combat.turret")
local Enemies = require("src.combat.enemies")
local Gladiator = require("src.combat.gladiator")
local Hud = require("src.ui.hud")
local Menu = require("src.ui.menu")
local TitleScreen = require("src.ui.title_screen")
local TitleDemo = require("src.ui.title_demo")
local Sfx = require("src.audio.sfx")
local Bgm = require("src.audio.bgm")
local Inventory = require("src.progression.inventory")
local InventoryUI = require("src.ui.inventory_ui")
local ArmoryUI = require("src.ui.armory_ui")
local Stage = require("src.progression.stage")
local StageTransition = require("src.progression.stage_transition")
local Replay = require("src.replay.replay")
local ReplayExport = require("src.replay.replay_export")

local ship, stars, stageBackground, fonts, camera, turret, enemies, hud, gladiator, titleScreen, titleDemo
local inventory, inventoryUI, currentBuild
local armoryInventory, armoryUI
local stage
local stageClearState, warpShutter, warpGates, warpState
local replay, activeExporter
local coinWallet, lastGladiatorTotal = 0, 0
local inventoryReturnScreen = "playing"
local inventoryStageEndMode = false
local pauseReturnScreen = "playing"
local permanentUnlocksFile = "grid_unlocks.txt"
local armoryLoadoutFile = "armory_loadout.txt"
local saveDataFiles = { permanentUnlocksFile, armoryLoadoutFile }
local lastFeverState, lastEvasionCount, lastWrapEvents, lastDamageCount = false, 0, 0, 0
local lastFeedbackDamageCount, lastHullDamageCount = 0, 0
local hitstopTimer = 0
local hullFlashTimer, hullFlashDuration = 0, 0.34
local HULL_HITSTOP_DURATION = 0.085
local HIT_SHAKE_AMP = 5.0
local HIT_SHAKE_DURATION = 0.16
local HULL_SHAKE_AMP = 16.0
local HULL_SHAKE_DURATION = 0.40
local LOW_SHIELD_THRESHOLD = 0.30
local LOW_ARMOR_THRESHOLD = 0.30
local LOW_ARMOR_ALERT_INTERVAL = 3.2
local lowShieldWarned, lowArmorWarned = false, false
local lowArmorAlertCooldown = 0
local lowArmorAura = 0
local wrapTriggerCooldown, shockwaveCooldown = 0, 0
local width, height, time = Display.VIRTUAL_WIDTH, Display.VIRTUAL_HEIGHT, 0
local currentFontScale = nil
local screen, selectedButton
local confirmDialog = nil
local focused = true
local gameOverHold = 1.25
local input = { turn = 0, thrust = false, brake = false, boost = false }
local testMode = false
local testFlags = {}
local captureRequested = false
local mouseX, mouseY, firing = 0, 0, false
local defaultErrorHandler = love.errorhandler

function love.errorhandler(message)
    if not (testMode or next(testFlags) ~= nil) then return defaultErrorHandler(message) end
    print(debug.traceback("FAIL: " .. tostring(message), 2))
    return function() return 1 end
end

local function setScreen(nextScreen)
    local prevScreen = screen
    screen, selectedButton = nextScreen, 1
    confirmDialog = nil
    input.boost, firing = false, false
    local preserveSfx = (screen == "gameOver" or screen == "stageClear"
        or screen == "warpSelect" or screen == "warping" or screen == "playing")
    if not preserveSfx then Sfx.stop() end
    if screen == "playing" and replay then
        Sfx.setListener(function(cue)
            if screen == "playing" and replay then replay:recordSfxEvent(cue) end
        end)
    else
        Sfx.setListener(nil)
    end
    local hideMouse = (screen == "playing" or screen == "gameOver"
        or screen == "stageClear" or screen == "warpSelect" or screen == "warping")
    love.mouse.setVisible(not hideMouse)
    if screen == "title" then
        if activeExporter then
            activeExporter:finish("취소됨")
            activeExporter = nil
        end
        replay = nil
        if stageBackground then
            stageBackground:setLevel(StageBackground.DEFAULT_LEVEL, true)
            stageBackground:setTitle(true)
        end
        if titleScreen then
            titleScreen:reset({
                quick = (prevScreen == "settings" or prevScreen == "armory"),
                keepParallax = (prevScreen == "settings" or prevScreen == "armory"),
            })
        end
        if titleDemo then
            titleDemo:syncBuild(armoryInventory)
        end
    end
    if screen == "title" or screen == "results" then
        ship, camera, turret, enemies, gladiator = nil, nil, nil, nil, nil
        currentBuild, stage = nil, nil
        stageClearState, warpShutter, warpGates, warpState = nil, nil, nil, nil
        coinWallet, lastGladiatorTotal = 0, 0
        lastFeedbackDamageCount, lastHullDamageCount = 0, 0
        hitstopTimer, hullFlashTimer = 0, 0
        lowShieldWarned, lowArmorWarned = false, false
        lowArmorAlertCooldown, lowArmorAura = 0, 0
        pauseReturnScreen = "playing"
    end
    Bgm.syncScreen(screen, stage and stage.level or nil, {
        focused = focused or testMode,
    })
end

local function syncInventoryBuild(opts)
    if not inventory or not ship or not gladiator then return end
    currentBuild = inventory:computeBuild(gladiator.feverActive)
    ship:applyBuild(currentBuild, opts)
    local stageMult = (stage and stage.scoreMultiplier) or 1
    gladiator.scoreMultiplier = (currentBuild.scoreMultiplier or 1) * stageMult
    lastFeverState = gladiator.feverActive
end

local function savePermanentUnlocks()
    if not inventory or testMode or testFlags.flow or testFlags.gladiator or testFlags.inventory then return end
    pcall(love.filesystem.write, permanentUnlocksFile, inventory:serializeUnlockedCells())
end

local function isAnyTestActive()
    return testMode or next(testFlags) ~= nil
end

local function saveArmoryLoadout()
    if not armoryInventory or isAnyTestActive() then return end
    local valid = armoryInventory:validateLoadout(false)
    if not valid then return end
    pcall(love.filesystem.write, armoryLoadoutFile, armoryInventory:serializeLoadout())
end

local function loadArmoryLoadout()
    if not isAnyTestActive() and love.filesystem.getInfo(armoryLoadoutFile) then
        local data = love.filesystem.read(armoryLoadoutFile)
        local loaded = Inventory.deserializeLoadout(data)
        if loaded then
            return loaded
        end
    end
    return Inventory.newStarter()
end

local function startRun(opts)
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
    gladiator.onAward = function(category, points, x, y, fever, basePoints)
        if replay then replay:recordPointEvent(category, points, x, y, fever, basePoints) end
    end
    enemies = Enemies.new(nil, gladiator)
    inventory = armoryInventory and armoryInventory:clone() or Inventory.newStarter()
    if not (testMode or testFlags.flow or testFlags.gladiator or testFlags.inventory or testFlags.combat)
        and love.filesystem.getInfo(permanentUnlocksFile) then
        inventory:loadUnlockedCells(love.filesystem.read(permanentUnlocksFile))
    end
    Sfx.stop()
    Bgm.stop()
    inventoryUI = InventoryUI.new()
    stageClearState, warpShutter, warpGates, warpState = nil, nil, nil, nil
    coinWallet, lastGladiatorTotal = 0, 0
    inventoryReturnScreen = "playing"
    inventoryStageEndMode = false
    pauseReturnScreen = "playing"
    stage = Stage.new(1)
    if stageBackground then
        if opts and opts.entryWarp then
            stageBackground:setTitle(true)
        else
            stageBackground:setLevel(stage.level, true)
        end
    end
    if not (testMode or testFlags.flow or testFlags.gladiator or testFlags.inventory or testFlags.combat) then
        stage:configureEnemies(enemies)
    end
    lastEvasionCount, lastWrapEvents, lastDamageCount = 0, 0, 0
    lastFeedbackDamageCount, lastHullDamageCount = 0, 0
    hitstopTimer, hullFlashTimer = 0, 0
    lowShieldWarned, lowArmorWarned = false, false
    lowArmorAlertCooldown, lowArmorAura = 0, 0
    wrapTriggerCooldown, shockwaveCooldown = 0, 0
    syncInventoryBuild({ resetVitals = true })
    if hud then hud:reset() end
    input.turn, input.thrust, input.brake, input.boost = 0, false, false, false
    time = 0
    if opts and opts.entryWarp then
        warpState = StageTransition.newEntryWarp(stage.number, ship, width, height, nil, opts.entryPose)
        warpState.jumpSfxPlayed = true
        setScreen("warping")
        Sfx.play("warp_jump")
    else
        setScreen("playing")
    end
end

local function beginStageClear()
    if replay then replay:finalizeStage() end
    local delta = math.max(0, (gladiator.total or 0) - lastGladiatorTotal)
    lastGladiatorTotal = gladiator.total or 0
    coinWallet = coinWallet + delta
    if ship then
        lastWrapEvents = ship.wrapEvents or 0
        lastDamageCount = ship.damageCount or 0
        lastFeedbackDamageCount = ship.damageCount or 0
        lastHullDamageCount = ship.hullDamageCount or 0
    end
    hitstopTimer, hullFlashTimer = 0, 0
    lowArmorAlertCooldown = 0
    if gladiator then
        lastEvasionCount = gladiator.evasionCount or 0
    end
    if enemies then
        enemies.items = {}
        if enemies.fire then enemies.fire:beginHarmlessExpiry() end
    end
    if turret then
        turret:beginStageClear()
    end
    stageClearState = StageTransition.newStageClear(stage)
    setScreen("stageClear")
    Sfx.play("stage_clear")
end

local function enterWarpSelect(keepExistingGates)
    if inventoryUI and inventory then
        inventoryUI:cancelDrag(inventory)
    end
    if inventory then
        inventory:discardPendingRewards()
    end
    inventoryStageEndMode = false
    inventoryReturnScreen = "warpSelect"
    if enemies then
        enemies.items = {}
        if enemies.fire then enemies.fire:clear() end
        if enemies.clearEffects then enemies:clearEffects() end
    end
    if not keepExistingGates and turret then
        turret:clearEffects()
    end
    if not keepExistingGates or not warpGates then
        if ship then
            ship.x, ship.y = Arena.width * 0.5, Arena.height * 0.5
            ship.vx, ship.vy, ship.wrapVx, ship.wrapVy = 0, 0, 0, 0
            ship.knockVx, ship.knockVy = 0, 0
            ship.invulnTimer, ship.invulnDuration = 0, 0
            ship.boostRemaining, ship.boostLevel = 0, 0
            ship.accelerating, ship.braking = false, false
        end
        warpGates = StageTransition.generateWarpGates(Arena.width, Arena.height)
    end
    syncInventoryBuild()
    savePermanentUnlocks()
    setScreen("warpSelect")
end

local function enterWarpSelectFromStageClear()
    local delta = math.max(0, (gladiator.total or 0) - lastGladiatorTotal)
    lastGladiatorTotal = gladiator.total or 0
    coinWallet = coinWallet + delta
    if gladiator then
        gladiator:clearFever()
        gladiator.popups = {}
        gladiator.lastEvent = nil
    end
    syncInventoryBuild()
    if enemies then
        if enemies.fire then enemies.fire:clear() end
        if enemies.clearEffects then enemies:clearEffects() end
    end
    hitstopTimer, hullFlashTimer = 0, 0
    lowArmorAlertCooldown, lowArmorAura = 0, 0
    if turret then turret:clearEffects() end
    stageClearState = nil
    warpShutter = StageTransition.newShutterOpen()
    enterWarpSelect(false)
end

local function beginWarpToNextStage(gate)
    warpState = StageTransition.newWarp(gate, (stage and stage.number or 1) + 1, ship, width, height)
    warpGates = nil
    setScreen("warping")
    if (warpState.alignDuration or 0) <= 0 then
        warpState.jumpSfxPlayed = true
        Sfx.play("warp_jump")
    end
end

local function completeEntryWarpAndStartStage()
    warpState = nil
    warpGates = nil
    if stageBackground then
        stageBackground:setLevel(stage and stage.level or StageBackground.DEFAULT_LEVEL, true)
    end
    if ship then
        ship.invulnTimer, ship.invulnDuration = 0, 0
        lastWrapEvents = ship.wrapEvents or 0
        lastDamageCount = ship.damageCount or 0
        lastFeedbackDamageCount = ship.damageCount or 0
        lastHullDamageCount = ship.hullDamageCount or 0
        lowShieldWarned = (ship.maxShield or 0) > 0 and (ship.shield / ship.maxShield) < LOW_SHIELD_THRESHOLD
        lowArmorWarned = false
    else
        lowShieldWarned, lowArmorWarned = false, false
    end
    hitstopTimer, hullFlashTimer = 0, 0
    lowArmorAlertCooldown, lowArmorAura = 0, 0
    if turret and ship then
        turret.angle = ship.angle
    end
    if gladiator then
        lastEvasionCount = gladiator.evasionCount or 0
    end
    wrapTriggerCooldown, shockwaveCooldown = 0, 0
    if camera and ship then
        camera.pullback = 0
        camera:update(0, ship, width, height)
    end
    syncInventoryBuild()
    setScreen("playing")
end

local function completeWarpAndStartStage(gate)
    local reward = gate and gate.reward or nil
    stage = stage and stage:nextStage({ featuredReward = reward }) or Stage.new(2, { featuredReward = reward })
    if stageBackground then
        local changedLevel = (stageBackground.level ~= stage.level)
        stageBackground:setLevel(stage.level, changedLevel)
    end
    local bonusCoins = StageTransition.applyRewardOnArrival(reward, inventory, ship, coinWallet)
    coinWallet = coinWallet + bonusCoins
    enemies.items = {}
    if enemies.fire then enemies.fire:clear() end
    if turret then turret:clearEffects() end
    enemies.spawnAccumulator = 0.5
    stage:configureEnemies(enemies)
    warpState = nil
    warpGates = nil
    if ship then
        ship.invulnTimer, ship.invulnDuration = 0, 0
        lastWrapEvents = ship.wrapEvents or 0
        lastDamageCount = ship.damageCount or 0
        lastFeedbackDamageCount = ship.damageCount or 0
        lastHullDamageCount = ship.hullDamageCount or 0
        lowShieldWarned = (ship.maxShield or 0) > 0 and (ship.shield / ship.maxShield) < LOW_SHIELD_THRESHOLD
        lowArmorWarned = false
    else
        lowShieldWarned, lowArmorWarned = false, false
    end
    hitstopTimer, hullFlashTimer = 0, 0
    lowArmorAlertCooldown, lowArmorAura = 0, 0
    if turret and ship then
        turret.angle = ship.angle
    end
    if gladiator then
        lastEvasionCount = gladiator.evasionCount or 0
    end
    wrapTriggerCooldown, shockwaveCooldown = 0, 0
    if camera and ship then
        camera.pullback = 0
        camera:update(0, ship, width, height)
    end
    syncInventoryBuild()
    savePermanentUnlocks()
    setScreen("playing")
end

local function closeInventoryScreen()
    if inventoryUI and inventory then
        inventoryUI:cancelDrag(inventory)
    end
    if inventory and inventory:activeWeaponCount() < 1 then
        if inventoryUI then
            inventoryUI:showWarningPopup("최소 하나의 무기는 사용해야 합니다.")
            inventoryUI.message = "최소 하나의 무기는 사용해야 합니다."
        end
        Sfx.play("ui_error")
        return
    end
    syncInventoryBuild()
    savePermanentUnlocks()
    if inventoryReturnScreen == "warpSelect" then
        enterWarpSelect(warpGates ~= nil)
        return
    end
    inventoryStageEndMode = false
    setScreen(inventoryReturnScreen or "playing")
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
    local _, _, vpW, vpH = Display.viewportRect()
    if replay and replay:openPlayback(vpW, vpH) then
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
    local shield = ship.shieldDamageTaken or 0
    local armor = ship.armorDamageTaken or 0
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
        rows[#rows + 1] = {label = kind.name, value = (enemies.killsByKind[i] or 0) .. "기", vertices = kind.vertices, enemyKind = i}
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

local function buildFonts(dpiScale)
    local scale = math.max(1, dpiScale or 1)
    if currentFontScale == scale and fonts then return end
    currentFontScale = scale
    local menuFont = "assets/fonts/DriftMenu.ttf"
    fonts = {
        small = love.graphics.newFont(11, "normal", scale),
        body = love.graphics.newFont(13, "normal", scale),
        title = love.graphics.newFont(30, "normal", scale),
        menuTitle = love.graphics.newFont(menuFont, 34, "normal", scale),
        menuButton = love.graphics.newFont(menuFont, 18, "normal", scale),
        menuBody = love.graphics.newFont(menuFont, 15, "normal", scale),
        menuSmall = love.graphics.newFont(menuFont, 12, "normal", scale),
        titleHero = love.graphics.newFont(menuFont, 72, "normal", scale),
        titleSub = love.graphics.newFont(menuFont, 28, "normal", scale),
        titlePrimary = love.graphics.newFont(menuFont, 23, "normal", scale),
        titleButton = love.graphics.newFont(menuFont, 19, "normal", scale),
        titleMicro = love.graphics.newFont(menuFont, 11, "normal", scale),
    }
    if hud and hud.setFontScale then
        hud:setFontScale(scale)
    end
end

local function rebuildFontsIfNeeded()
    buildFonts(Display.fontDpiScale())
end

local function closeSettings()
    confirmDialog = nil
    setScreen(ship and "pause" or "title")
end

local function resetSaveData()
    local removedOk = true
    for _, filename in ipairs(saveDataFiles) do
        if love.filesystem.getInfo(filename) then
            local ok, removed = pcall(love.filesystem.remove, filename)
            if not ok or not removed then
                removedOk = false
            end
        end
    end
    inventory = nil
    armoryInventory = Inventory.newStarter()
    if titleDemo then titleDemo:syncBuild(armoryInventory) end
    if removedOk then
        menus.settings.subtitle = "저장 데이터가 초기화되었습니다."
        selectedButton = 3
    else
        menus.settings.subtitle = "저장 데이터를 초기화할 수 없습니다."
        Sfx.play("ui_error")
    end
end

local function openResetSaveConfirm()
    confirmDialog = {
        title = "저장 데이터 초기화",
        message = "정말로 모든 데이터를 초기화하시겠습니까?",
        warning = "초기화된 데이터는 되돌릴 수 없습니다.",
        selected = 1,
        buttons = {
            {
                label = "취소",
                action = function()
                    confirmDialog = nil
                end,
            },
            {
                label = "초기화",
                danger = true,
                action = function()
                    confirmDialog = nil
                    resetSaveData()
                end,
            },
        },
    }
end

local function displayModeValue()
    local label = Display.MODE_LABELS[Display.mode] or Display.mode
    return "< " .. label .. " >"
end

local function resolutionValue()
    if Display.mode == "borderless" then
        return Display.formatResolution(Display.windowWidth, Display.windowHeight) .. " (자동)"
    end
    return "< " .. Display.formatResolution(Display.selectedWidth, Display.selectedHeight) .. " >"
end

local function applyDisplayChange(mode, resW, resH)
    local ok, err = Display.applyMode(mode, resW, resH)
    if not ok then
        menus.settings.subtitle = err or "화면 모드를 변경할 수 없습니다."
        return
    end
    love.resize(love.graphics.getDimensions())
    menus.settings.subtitle = nil
    if not Display.saveSettings() then
        menus.settings.subtitle = "화면 설정을 저장할 수 없습니다."
    end
end

local function changeDisplayMode(dir)
    local nextMode = Display.nextMode(dir)
    applyDisplayChange(nextMode, Display.selectedWidth, Display.selectedHeight)
end

local function changeResolution(dir)
    if Display.mode == "borderless" then
        menus.settings.subtitle = "전체창모드는 모니터 기본 해상도를 사용합니다."
        return
    end
    local nextRes = Display.nextResolution(dir)
    applyDisplayChange(Display.mode, nextRes.w, nextRes.h)
end

local function buildSettingsButtons(fromTitle)
    local buttons = {
        {
            label = "화면 모드",
            value = displayModeValue,
            action = function() changeDisplayMode(1) end,
            onLeft = function() changeDisplayMode(-1) end,
            onRight = function() changeDisplayMode(1) end,
        },
        {
            label = "해상도",
            value = resolutionValue,
            action = function() changeResolution(1) end,
            onLeft = function() changeResolution(-1) end,
            onRight = function() changeResolution(1) end,
        },
        {label = "뒤로", action = closeSettings},
    }
    if fromTitle then
        buttons[#buttons + 1] = {
            label = "저장 데이터 초기화",
            compact = true,
            danger = true,
            dividerBefore = true,
            action = openResetSaveConfirm,
        }
    end
    return buttons
end

local function openSettings()
    confirmDialog = nil
    menus.settings.subtitle = nil
    menus.settings.buttons = buildSettingsButtons(ship == nil)
    setScreen("settings")
end

local function openArmory()
    confirmDialog = nil
    if not armoryUI then
        armoryUI = ArmoryUI.new()
    end
    if not armoryInventory then
        armoryInventory = Inventory.newStarter()
    end
    armoryInventory = armoryUI:open(armoryInventory)
    setScreen("armory")
end

local function closeArmory(nextInv, saveChanges)
    if nextInv then
        armoryInventory = nextInv
    end
    if saveChanges then
        saveArmoryLoadout()
    end
    setScreen("title")
end

menus.title = {title = "SPACE GLADIATOR", buttons = {
    {label = "게임 시작", sublabel = "LAUNCH", primary = true, action = function()
        local entryPose = titleDemo and titleDemo:getShipPose() or nil
        if titleScreen then titleScreen:beginLaunch(menus.title, selectedButton) end
        startRun({ entryWarp = true, entryPose = entryPose })
    end},
    {label = "아머리", sublabel = "ARMORY", action = openArmory},
    {label = "설정", sublabel = "SETTINGS", action = openSettings},
    {label = "게임 종료", sublabel = "EXIT", action = function() love.event.quit() end},
}}
menus.pause = {title = "일시정지", buttons = {
    {label = "계속하기", action = function() setScreen(pauseReturnScreen or "playing") end},
    {label = "설정", action = openSettings},
    {label = "포기하기", action = function() showResults("전투 포기") end},
    {label = "타이틀로 나가기", action = function() setScreen("title") end},
}}
menus.settings = {title = "설정", panelWidth = 510, buttons = buildSettingsButtons(true)}
menus.results = {title = "전투 정산", buttons = {
    {label = "확인", action = function() setScreen("title") end},
}}
local gameOverMenu = {title = "GAME OVER", subtitle = "기체 파괴"}
local unfocusedMenu = {title = "일시정지", subtitle = "게임 창으로 돌아오면 전투를 계속합니다."}

local function dispatchRequestedTests()
    if testFlags.gladiator then
        require("tests.gladiator")(Ship, Enemies, Turret, Gladiator)
        love.event.quit(0)
        return true
    end
    if testFlags.inventory then
        require("tests.inventory")(Inventory, Ship, Turret, Gladiator)
        love.event.quit(0)
        return true
    end
    if testFlags.armory then
        local ChassisData = require("src.data.chassis_data")
        local ModulesData = require("src.data.modules_data")
        require("tests.armory")(ArmoryUI, Inventory, ChassisData, ModulesData, Ship, fonts, width, height)
        return true
    end
    if testFlags.replay then
        require("tests.replay")(Replay, ReplayExport)
        love.event.quit(0)
        return true
    end
    if testFlags.fullscreen then
        require("tests.fullscreen_arena")
        love.event.quit(0)
        return true
    end
    if testFlags.background then
        require("tests.stage_background")
        love.event.quit(0)
        return true
    end
    if testFlags.title then
        require("tests.title_screen")(function()
            return screen, titleScreen, menus.title, selectedButton, fonts, width, height, titleDemo, warpState
        end)
        return true
    end
    if testFlags.combat then
        require("tests.combat_feel")(Ship, Enemies, Turret, Gladiator, Camera, function()
            return screen, ship, enemies, turret, gladiator, camera, hitstopTimer, hullFlashTimer, startRun, lowArmorAura
        end)
        love.event.quit(0)
        return true
    end
    if testFlags.flow then
        require("tests.flow")(function()
            return screen, ship, enemies, turret, gladiator, beginStageClear, inventory, warpGates, syncInventoryBuild
        end)
        love.event.quit(0)
        return true
    end
    return false
end

function love.load(args)
    for _, arg in ipairs(args or {}) do
        if arg == "--test" then testMode = true end
        if arg == "--test-flow" then testFlags.flow = true end
        if arg == "--test-gladiator" then testFlags.gladiator = true end
        if arg == "--test-inventory" then testFlags.inventory = true end
        if arg == "--test-armory" then testFlags.armory = true end
        if arg == "--test-replay" then testFlags.replay = true end
        if arg == "--test-fullscreen" then testFlags.fullscreen = true end
        if arg == "--test-background" then testFlags.background = true end
        if arg == "--test-title" then testFlags.title = true end
        if arg == "--test-combat" then testFlags.combat = true end
        if arg == "--test-compact" then testMode, testFlags.compact = true, true end
        if arg == "--test-damaged" then testMode, testFlags.damaged = true, true end
    end
    love.graphics.setBackgroundColor(0, 0, 0)
    love.graphics.setLineStyle("smooth")
    local anyTest = isAnyTestActive()
    if not anyTest then
        local saved = Display.loadSettings()
        Display.applyMode(saved.mode, saved.width, saved.height)
    end
    Display.syncFromWindow()
    if not anyTest and love.window and love.window.hasFocus then
        focused = love.window.hasFocus()
    end
    width, height = Display.VIRTUAL_WIDTH, Display.VIRTUAL_HEIGHT
    Arena.resize()
    hud = Hud.new(Display.fontDpiScale())
    titleScreen = TitleScreen.new()
    armoryUI = ArmoryUI.new()
    armoryInventory = loadArmoryLoadout()
    titleDemo = TitleDemo.new(armoryInventory)
    buildFonts(Display.fontDpiScale())
    local _, _, vpW, vpH = Display.viewportRect()
    stars = Starfield.new(vpW, vpH)
    stageBackground = StageBackground.new(vpW, vpH)
    if not anyTest or testFlags.replay or testFlags.fullscreen then
        Sfx.load()
        Bgm.load()
    end
    setScreen("title")
    if dispatchRequestedTests() then
        return
    end
    if testFlags.compact then
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
        if testFlags.damaged then ship.shield, ship.armor, ship.hull, ship.battery = 27, 68, 2, 42 end
    end
end

local function processPlayerDamageFeedback()
    if not ship or not camera then return end
    if (ship.hullDamageCount or 0) > lastHullDamageCount then
        lastHullDamageCount = ship.hullDamageCount
        lastFeedbackDamageCount = ship.damageCount or lastFeedbackDamageCount
        camera:addShake(HULL_SHAKE_AMP, HULL_SHAKE_DURATION)
        hullFlashTimer = hullFlashDuration
        hitstopTimer = HULL_HITSTOP_DURATION
        camera:update(0, ship, width, height, { freezeDecay = true })
    elseif (ship.damageCount or 0) > lastFeedbackDamageCount then
        lastFeedbackDamageCount = ship.damageCount
        camera:addShake(HIT_SHAKE_AMP, HIT_SHAKE_DURATION)
    end
end

local function updateLowStatusWarnings(dt)
    if not ship or ship:isDestroyed() then
        lowShieldWarned, lowArmorWarned = false, false
        lowArmorAlertCooldown = 0
        return
    end
    local shieldLow = (ship.maxShield or 0) > 0 and (ship.shield / ship.maxShield) < LOW_SHIELD_THRESHOLD
    local armorLow = (ship.maxArmor or 0) > 0 and (ship.armor / ship.maxArmor) < LOW_ARMOR_THRESHOLD
    local armorJustTriggered = armorLow and not lowArmorWarned

    if armorLow then
        if not lowArmorWarned then
            lowArmorWarned = true
            Sfx.play("low_armor")
            lowArmorAlertCooldown = LOW_ARMOR_ALERT_INTERVAL
        else
            lowArmorAlertCooldown = lowArmorAlertCooldown - dt
            if lowArmorAlertCooldown <= 0 then
                Sfx.play("low_armor")
                lowArmorAlertCooldown = LOW_ARMOR_ALERT_INTERVAL
            end
        end
    else
        lowArmorWarned = false
        lowArmorAlertCooldown = 0
    end

    if shieldLow then
        if not lowShieldWarned then
            lowShieldWarned = true
            if not armorJustTriggered then
                Sfx.play("low_shield")
            end
        end
    else
        lowShieldWarned = false
    end

    local targetAura = armorLow and 1 or 0
    local auraRate = armorLow and 5.0 or 3.5
    lowArmorAura = lowArmorAura + (targetAura - lowArmorAura) * math.min(1, dt * auraRate)
    if not armorLow and lowArmorAura < 0.005 then lowArmorAura = 0 end
end

local function updateHudProximity(dt)
    if not hud then return end
    hud:update(dt, {
        ship = ship,
        enemies = enemies,
        turret = turret,
        warpGates = screen == "warpSelect" and warpGates or nil,
        camera = camera,
        arenaWidth = Arena.width,
        arenaHeight = Arena.height,
    }, width, height)
end

function love.update(dt)
    local isFrontendScreen = (screen == "title" or screen == "armory" or screen == "settings" or screen == "results")
    if not focused and not testMode and not isFrontendScreen then return end
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
                    replay.exportStatus = "저장 완료: " .. (activeExporter.mp4Path or ("SpaceGladiator/" .. activeExporter.filename))
                end
                activeExporter = nil
            end
        else
            local _, _, vpW, vpH = Display.viewportRect()
            replay:updatePlayback(dt, vpW, vpH)
        end
        return
    end
    local _, _, bgW, bgH = Display.viewportRect()
    local bgScale = Display.scale or 1
    if not ship then
        if stageBackground then stageBackground:update(dt, 0, 0, bgW, bgH) end
        stars:update(dt, 12 * bgScale, -18 * bgScale, 0, bgW, bgH, 0)
        if screen == "title" then
            if titleDemo then titleDemo:update(dt, width, height) end
            if titleScreen then titleScreen:update(dt, menus.title, selectedButton) end
        elseif screen == "armory" and armoryUI then
            armoryUI:update(dt)
        end
        return
    end
    if screen == "pause" or screen == "settings" or screen == "inventory" then return end
    time = time + dt
    if screen == "stageClear" then
        if lowArmorAura > 0 then
            lowArmorAura = lowArmorAura * math.max(0, 1 - math.min(1, dt * 3.5))
            if lowArmorAura < 0.005 then lowArmorAura = 0 end
        end
        ship:update(dt, { turn = 0, thrust = false, brake = true, boost = false }, { disableWrapDetection = true })
        if enemies then
            if enemies.fire then enemies.fire:updateHarmless(dt) end
            if enemies.updateEffects then enemies:updateEffects(dt) end
        end
        camera:update(dt, ship, width, height)
        if turret then
            turret:updateEffects(dt, camera, width, height)
        end
        if gladiator then
            gladiator:updateVisuals(dt)
        end
        updateHudProximity(dt)
        local vx, vy = ship:worldVelocity()
        if stageBackground then stageBackground:update(dt, vx * bgScale, vy * bgScale, bgW, bgH) end
        stars:update(dt, (90 + vx * 1.8) * bgScale, (-210 + vy * 1.8) * bgScale, 0, bgW, bgH, 0)
        if StageTransition.updateStageClear(stageClearState, dt) then
            enterWarpSelectFromStageClear()
        end
        return
    end
    if screen == "warping" then
        local finished = StageTransition.updateWarp(warpState, dt, ship, stars, camera, width, height, turret)
        if titleScreen and titleScreen:isLaunching() then
            titleScreen:update(dt, menus.title, selectedButton)
        end
        if stageBackground and warpState then
            local warpDrift = 140 * (warpState.speedFactor or 0)
            stageBackground:update(dt, warpState.dirX * warpDrift * bgScale, warpState.dirY * warpDrift * bgScale, bgW, bgH)
        end
        if finished then
            if warpState and warpState.mode == "entry" then
                completeEntryWarpAndStartStage()
            else
                completeWarpAndStartStage(warpState.gate)
            end
        end
        return
    end
    if screen == "gameOver" then
        if hitstopTimer > 0 then
            hitstopTimer = math.max(0, hitstopTimer - dt)
            if camera and ship then
                camera:update(dt, ship, width, height, { freezeDecay = true })
            end
            return
        end
        hullFlashTimer = math.max(0, hullFlashTimer - dt)
        if lowArmorAura > 0 then
            lowArmorAura = lowArmorAura * math.max(0, 1 - math.min(1, dt * 3.5))
            if lowArmorAura < 0.005 then lowArmorAura = 0 end
        end
        ship:update(dt, input)
        if camera then camera:update(dt, ship, width, height) end
        if enemies and enemies.updateEffects then enemies:updateEffects(dt) end
        gladiator:update(dt, ship)
        updateHudProximity(dt)
        if ship.destructionAge >= Ship.destructionDuration + gameOverHold then
            showResults("기체 파괴")
        end
        return
    end
    input.turn = (love.keyboard.isDown("d") and 1 or 0)
        - (love.keyboard.isDown("a") and 1 or 0)
    input.thrust = love.keyboard.isDown("w")
    input.brake = love.keyboard.isDown("s")
    mouseX, mouseY = Display.getMousePosition()
    if testMode then
        input.turn, input.thrust, input.brake = 0.55, true, false
        mouseX, mouseY, firing = width * 0.60, height * 0.24, true
    end

    if screen == "warpSelect" then
        if warpShutter and StageTransition.updateShutterOpen(warpShutter, dt) then
            warpShutter = nil
        end
        StageTransition.updateWarpGates(warpGates, dt)
        local preGate = StageTransition.checkGateTrigger(warpGates, ship)
        if preGate then
            beginWarpToNextStage(preGate)
            return
        end
        ship:update(dt, input, { disableWrapDetection = true })
        input.boost = false
        local postGate = StageTransition.checkGateTrigger(warpGates, ship)
        if postGate then
            beginWarpToNextStage(postGate)
            return
        end
        camera:update(dt, ship, width, height)
        local surge = 1050 * ship.boostLevel
        local vx, vy = ship:worldVelocity()
        if stageBackground then
            local bgBoost = 120 * ship.boostLevel
            stageBackground:update(dt, (vx + ship.boostX * bgBoost) * bgScale, (vy + ship.boostY * bgBoost) * bgScale, bgW, bgH)
        end
        stars:update(dt, (120 + vx * 2.8 + ship.boostX * surge) * bgScale,
            (-290 + vy * 2.8 + ship.boostY * surge) * bgScale,
            ship.accelerating and 1 or 0, bgW, bgH, ship.boostLevel)
        local worldX, worldY = camera:screenToWorld(mouseX, mouseY, width, height)
        local activeWeapons = currentBuild and currentBuild.weaponModules or {}
        turret:update(dt, ship, worldX, worldY, firing, enemies, camera, width, height, activeWeapons)
        updateHudProximity(dt)
        return
    end

    if hitstopTimer > 0 then
        hitstopTimer = math.max(0, hitstopTimer - dt)
        if camera and ship then
            camera:update(dt, ship, width, height, { freezeDecay = true })
        end
        return
    end
    hullFlashTimer = math.max(0, hullFlashTimer - dt)

    ship:update(dt, input)
    input.boost = false
    camera:update(dt, ship, width, height)
    local surge = 1050 * ship.boostLevel
    local vx, vy = ship:worldVelocity()
    if stageBackground then
        local bgBoost = 120 * ship.boostLevel
        stageBackground:update(dt, (vx + ship.boostX * bgBoost) * bgScale, (vy + ship.boostY * bgBoost) * bgScale, bgW, bgH)
    end
    stars:update(dt, (120 + vx * 2.8 + ship.boostX * surge) * bgScale,
        (-290 + vy * 2.8 + ship.boostY * surge) * bgScale,
        ship.accelerating and 1 or 0, bgW, bgH, ship.boostLevel)
    enemies:update(dt, ship, turret.angle, camera, width, height)
    processPlayerDamageFeedback()
    if ship:isDestroyed() then
        setScreen("gameOver")
        return
    end
    updateLowStatusWarnings(dt)
    local worldX, worldY = camera:screenToWorld(mouseX, mouseY, width, height)
    if currentBuild and gladiator.feverActive ~= lastFeverState then
        syncInventoryBuild()
    end
    local activeWeapons = currentBuild and currentBuild.weaponModules or {}
    turret:update(dt, ship, worldX, worldY, firing, enemies, camera, width, height, activeWeapons)
    gladiator:update(dt, ship)
    updateHudProximity(dt)
    if replay then
        replay:recordFrame(dt, ship, camera, turret, enemies, gladiator, stage)
    end

    -- Sync 1:1 Gladiator Coins and check stage completion (timer or all squads cleared)
    if gladiator and (gladiator.total or 0) > lastGladiatorTotal then
        coinWallet = coinWallet + (gladiator.total - lastGladiatorTotal)
        lastGladiatorTotal = gladiator.total
    end
    if stage and not (testMode or testFlags.flow or testFlags.gladiator or testFlags.inventory or testFlags.combat) then
        if stage:update(dt, enemies) then
            beginStageClear()
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
            for _, wCfg in ipairs(currentBuild.weaponModules or {}) do
                if wCfg.triggerOnDodge then
                    turret:fireTriggered(wCfg.weaponIndex, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
                        free = wCfg.autoBatteryZero,
                    })
                end
            end
        end

        -- On-wrap triggers
        if (ship.wrapEvents or 0) > lastWrapEvents then
            lastWrapEvents = ship.wrapEvents
            if wrapTriggerCooldown <= 0 then
                for _, wCfg in ipairs(currentBuild.weaponModules or {}) do
                    if wCfg.triggerOnWrap then
                        turret:fireTriggered(wCfg.weaponIndex, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
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
            for _, wCfg in ipairs(currentBuild.weaponModules or {}) do
                if wCfg.triggerOnHit and (ship.battery or 0) >= (wCfg.hitTriggerBattery or 15) then
                    ship.battery = ship.battery - (wCfg.hitTriggerBattery or 15)
                    turret:fireTriggered(wCfg.weaponIndex, ship, worldX, worldY, enemies, camera, width, height, wCfg, {
                        radialCount = wCfg.radialCount or 6,
                    })
                end
            end
        end
    end
end

local function drawHud()
    local g = love.graphics
    local gx, gw = math.floor(width / 2) - 115, 230
    -- Subtle compact backing keeps Gladiator Points legible over the full-screen battlefield.
    g.setColor(0.018, 0.028, 0.055, 0.62)
    g.rectangle("fill", gx - 10, 16, gw + 20, 88, 8, 8)
    g.setColor(0.25, 0.47, 0.58, 0.24)
    g.setLineWidth(1)
    g.rectangle("line", gx - 10, 16, gw + 20, 88, 8, 8)
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

    hud:draw(ship, width, height, time)
end

local function wrapOffsets(position, extent, reach)
    if position < reach then return {0, extent} end
    if position > extent - reach then return {0, -extent} end
    return {0}
end

local function drawPlayer(originX, originY)
    local g = love.graphics
    g.push("all")
    local sx, sy, sw, sh = Display.virtualRectToWindow(originX, originY, Arena.width * camera.zoom, Arena.height * camera.zoom)
    g.intersectScissor(sx, sy, sw, sh)
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
                turret:drawMount(ship, time, width)
                ship:draw(time)
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
    if screen == "warpSelect" and warpGates then
        StageTransition.drawWarpGates(warpGates, ship, time, fonts, width, height)
    end
    gladiator:drawFeverOverlay(width, height, time)
    if lowArmorAura > 0 then
        local g = love.graphics
        local pulse = math.min(1.1, 0.55 + 0.45 * math.sin(time * 4.2) + 0.12 * math.max(0, math.sin(time * 8.4)))
        g.push("all")
        g.setColor(0.88, 0.05, 0.07, 0.11 * lowArmorAura * pulse)
        g.rectangle("fill", 0, 0, width, height)
        local bands = { 14, 30, 50, 74, 102 }
        for idx, thickness in ipairs(bands) do
            local alpha = (0.20 / idx) * lowArmorAura * pulse
            g.setColor(0.95, 0.06, 0.08, alpha)
            g.rectangle("fill", 0, 0, width, thickness)
            g.rectangle("fill", 0, height - thickness, width, thickness)
            g.rectangle("fill", 0, thickness, thickness, height - thickness * 2)
            g.rectangle("fill", width - thickness, thickness, thickness, height - thickness * 2)
        end
        g.setLineWidth(2.0)
        g.setColor(1.0, 0.18, 0.20, 0.52 * lowArmorAura * pulse)
        g.rectangle("line", 4, 4, width - 8, height - 8)
        local span = 28 + math.sin(time * 4.2) * 4
        g.setLineWidth(2.5)
        g.setColor(1.0, 0.22, 0.24, 0.72 * lowArmorAura * pulse)
        for _, cx in ipairs({ 12, width - 12 }) do
            local sx = cx == 12 and 1 or -1
            for _, cy in ipairs({ 12, height - 12 }) do
                local sy = cy == 12 and 1 or -1
                g.line(cx + sx * span, cy, cx, cy, cx, cy + sy * span)
            end
        end
        g.pop()
    end
    if hullFlashTimer > 0 and hullFlashDuration > 0 then
        local g = love.graphics
        local p = math.max(0, math.min(1, hullFlashTimer / hullFlashDuration))
        g.push("all")
        if p > 0.70 then
            local peak = (p - 0.70) / 0.30
            g.setColor(1.0, 0.94, 0.86, 0.56 * peak)
            g.rectangle("fill", 0, 0, width, height)
        end
        g.setColor(0.95, 0.14, 0.10, 0.34 * p * p)
        g.rectangle("fill", 0, 0, width, height)
        for band = 1, 3 do
            local thickness = band * 14
            local alpha = (0.30 / band) * p
            g.setColor(1.0, 0.20, 0.14, alpha)
            g.rectangle("fill", 0, 0, width, thickness)
            g.rectangle("fill", 0, height - thickness, width, thickness)
            g.rectangle("fill", 0, thickness, thickness, height - thickness * 2)
            g.rectangle("fill", width - thickness, thickness, thickness, height - thickness * 2)
        end
        g.pop()
    end
    gladiator:drawPopups(camera, width, height, fonts.small)
    drawHud()
    if screen == "warpSelect" then
        local g = love.graphics
        local bw, bh = math.min(540, width - 80), 32
        local bx, by = math.floor((width - bw) * 0.5), 110
        g.setColor(0.024, 0.056, 0.094, 0.88)
        g.rectangle("fill", bx, by, bw, bh, 6, 6)
        g.setColor(0.45, 0.92, 0.84, 0.72)
        g.setLineWidth(1.2)
        g.rectangle("line", bx, by, bw, bh, 6, 6)
        g.setFont(fonts.menuBody)
        g.setColor(0.86, 0.98, 0.95, 1)
        g.printf("다음 스테이지 워프 개방 · 원하는 보상의 경계로 비행하세요", bx + 10, by + 7, bw - 20, "center")
    end
    if (screen == "playing" or screen == "warpSelect") and (focused or testMode) then
        local g = love.graphics
        local x, y = Display.getMousePosition()
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
    local gw, gh = love.graphics.getDimensions()
    if gw > 0 and gh > 0 and (gw ~= Display.windowWidth or gh ~= Display.windowHeight) then
        love.resize(gw, gh)
    end
    local vpX, vpY, bgW, bgH = Display.viewportRect()
    Display.applyViewportScissor()
    if screen == "replay" and replay then
        replay:drawPlayback(width, height, fonts)
        Display.drawLetterboxFrame()
        love.graphics.setScissor()
        return
    end
    if screen == "warping" and warpState then
        if stageBackground then
            local p = StageTransition.warpProgress(warpState)
            local isEntry = (warpState.mode == "entry")
            local bgBlend = isEntry
                and math.max(0, math.min(1, (p - 0.05) / 0.90))
                or math.max(0, math.min(1, (p - 0.30) / 0.40))
            local warpSpeed = warpState.speedFactor or 0
            local pullback = math.max(camera and camera.pullback or 0, warpSpeed)
            local titleVisible = stageBackground.titleActive and (not isEntry or p < 0.37)
            local tpx, tpy = 0, 0
            if titleVisible and titleScreen then
                tpx, tpy = titleScreen:getBackgroundParallax()
                local s = Display.scale or 1
                tpx, tpy = tpx * s, tpy * s
            end
            local planetMask = titleVisible and stageBackground:titlePlanetMask(bgW, bgH, tpx, tpy) or nil
            stageBackground:draw(bgW, bgH, {
                originX = vpX,
                originY = vpY,
                nextLevel = stage and stage.level or StageBackground.DEFAULT_LEVEL,
                blend = bgBlend,
                fadeThroughBlack = isEntry,
                pullback = pullback,
                shake = warpSpeed * warpSpeed,
                titleParallaxX = tpx,
                titleParallaxY = tpy,
            })
            stars:draw({ transparent = true, originX = vpX, originY = vpY, excludeZone = planetMask })
        else
            stars:draw({ originX = vpX, originY = vpY })
        end
        love.graphics.push("all")
        Display.applyTransform()
        StageTransition.drawWarp(warpState, ship, camera, width, height, time, fonts, turret)
        if warpState.mode == "entry" and titleScreen and titleScreen:isLaunching() then
            titleScreen:drawLaunchOverlay(fonts, width, height)
        end
        love.graphics.pop()
        Display.drawLetterboxFrame()
        love.graphics.setScissor()
        return
    end
    if stageBackground then
        local tpx, tpy = 0, 0
        if stageBackground.titleActive and titleScreen then
            tpx, tpy = titleScreen:getBackgroundParallax()
            local s = Display.scale or 1
            tpx, tpy = tpx * s, tpy * s
        end
        local planetMask = stageBackground.titleActive and stageBackground:titlePlanetMask(bgW, bgH, tpx, tpy) or nil
        stageBackground:draw(bgW, bgH, {
            originX = vpX,
            originY = vpY,
            pullback = camera and camera.pullback or 0,
            shake = camera and camera:shakeIntensity() or 0,
            titleParallaxX = tpx,
            titleParallaxY = tpy,
        })
        stars:draw({ transparent = true, originX = vpX, originY = vpY, excludeZone = planetMask })
    else
        stars:draw({ originX = vpX, originY = vpY })
    end
    love.graphics.push("all")
    Display.applyTransform()
    if ship then drawFlight() end
    local menu = menus[screen]
    if screen == "gameOver" and ship.destructionAge >= Ship.destructionDuration then
        menu = gameOverMenu
    elseif (screen == "playing" or screen == "warpSelect") and not focused and not testMode then
        menu = unfocusedMenu
    end
    if screen == "stageClear" and stageClearState then
        StageTransition.drawStageClearOverlay(stageClearState, width, height, fonts)
    elseif screen == "warpSelect" and warpShutter then
        StageTransition.drawShutterOpen(warpShutter, width, height)
    elseif screen == "inventory" and inventory and inventoryUI then
        inventoryUI:draw(inventory, fonts, width, height, gladiator and gladiator.feverActive, {
            stageEndMode = inventoryStageEndMode,
            returnTarget = inventoryReturnScreen,
        })
    elseif screen == "armory" and armoryUI then
        armoryInventory = armoryUI:draw(armoryInventory, fonts, width, height)
    elseif screen == "title" and titleScreen then
        if titleDemo then
            titleDemo:draw(titleDemo.time, width, height)
        end
        titleScreen:draw(menu, fonts, selectedButton, width, height)
    elseif menu then
        Menu.draw(menu, fonts, selectedButton, width, height, ship ~= nil)
        if confirmDialog then
            Menu.drawConfirm(confirmDialog, fonts, confirmDialog.selected, width, height)
        end
    end
    love.graphics.pop()
    Display.drawLetterboxFrame()
    love.graphics.setScissor()
    if testMode and not captureRequested then
        captureRequested = true
        love.graphics.captureScreenshot(function(data)
            local name = testFlags.compact and "hud-compact-preview.png"
                or testFlags.damaged and "hud-damaged-preview.png" or "flight-preview.png"
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
    if not focused and love.window and love.window.hasFocus and love.window.hasFocus() then
        focused = true
    end
    if confirmDialog then
        local count = #(confirmDialog.buttons or {})
        if key == "escape" then
            confirmDialog = nil
            Sfx.play("ui_click")
        elseif (key == "left" or key == "up" or key == "a" or key == "w") and count > 0 then
            confirmDialog.selected = (confirmDialog.selected - 2) % count + 1
            Sfx.play("ui_hover")
        elseif (key == "right" or key == "down" or key == "d" or key == "s" or key == "tab") and count > 0 then
            confirmDialog.selected = confirmDialog.selected % count + 1
            Sfx.play("ui_hover")
        elseif (key == "return" or key == "kpenter") and confirmDialog.buttons[confirmDialog.selected] then
            Sfx.play("ui_click")
            confirmDialog.buttons[confirmDialog.selected].action()
        end
        return
    end
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
    if screen == "stageClear" or screen == "warping" then
        return
    end
    if key == "tab" or key == "i" then
        if screen == "playing" or screen == "warpSelect" then
            inventoryReturnScreen = screen
            inventoryStageEndMode = false
            setScreen("inventory")
            return
        elseif screen == "inventory" then
            if inventoryUI and inventoryUI:hasWarningPopup() then
                inventoryUI:dismissWarningPopup()
                Sfx.play("ui_click")
            else
                closeInventoryScreen()
            end
            return
        end
    end
    if screen == "armory" and armoryUI then
        local nextInv, action = armoryUI:keypressed(armoryInventory, key)
        if nextInv then armoryInventory = nextInv end
        if action == "saveAndExit" then
            closeArmory(armoryInventory, true)
        elseif action == "cancelExit" then
            closeArmory(armoryInventory, false)
        end
        return
    end
    if screen == "inventory" then
        if inventoryUI and inventoryUI:hasWarningPopup() then
            inventoryUI:keypressed(inventory, key)
            return
        end
        if key == "escape" then
            if inventoryUI and inventory and inventoryUI.dragging then
                inventoryUI:cancelDrag(inventory)
                Sfx.play("ui_click")
            else
                closeInventoryScreen()
            end
        elseif (key == "return" or key == "kpenter") and inventoryReturnScreen == "warpSelect" then
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
        if screen == "title" and titleScreen and titleScreen:isIntroActive() then
            titleScreen:skipIntro()
            return
        elseif screen == "playing" or screen == "warpSelect" then
            pauseReturnScreen = screen
            setScreen("pause")
        elseif screen == "pause" then
            setScreen(pauseReturnScreen or "playing")
        elseif screen == "settings" and key == "escape" then
            closeSettings()
        end
        return
    end

    local menu = menus[screen]
    if menu then
        local isTitle = (screen == "title" and titleScreen ~= nil)
        if key == "up" or (isTitle and key == "w") then
            if isTitle then titleScreen:skipIntro() end
            selectedButton = (selectedButton - 2) % #menu.buttons + 1
            Sfx.play("ui_hover")
        elseif key == "down" or (isTitle and key == "s") then
            if isTitle then titleScreen:skipIntro() end
            selectedButton = selectedButton % #menu.buttons + 1
            Sfx.play("ui_hover")
        elseif key == "left" and menu.buttons[selectedButton] and menu.buttons[selectedButton].onLeft then
            Sfx.play("ui_click")
            menu.buttons[selectedButton].onLeft()
        elseif key == "right" and menu.buttons[selectedButton] and menu.buttons[selectedButton].onRight then
            Sfx.play("ui_click")
            menu.buttons[selectedButton].onRight()
        elseif key == "return" or key == "kpenter" then
            if isTitle then titleScreen:skipIntro() end
            Sfx.play("ui_click")
            menu.buttons[selectedButton].action()
        elseif isTitle and titleScreen:isIntroActive() then
            titleScreen:skipIntro()
        end
        return
    end

    if screen ~= "playing" and screen ~= "warpSelect" then return end
    if key == "r" then startRun()
    elseif key == "space" and (focused or testMode) then input.boost = true end
end

function love.mousemoved(x, y)
    x, y = Display.windowToVirtual(x, y)
    if confirmDialog then
        local hovered = Menu.confirmButtonAt(confirmDialog, width, height, x, y)
        if hovered and hovered ~= confirmDialog.selected then
            confirmDialog.selected = hovered
            Sfx.play("ui_hover")
        end
        return
    end
    if screen == "armory" and armoryUI then
        armoryUI:mousemoved(armoryInventory, x, y)
        return
    end
    if screen == "inventory" and inventoryUI then
        inventoryUI:mousemoved(x, y)
        return
    end
    local menu = menus[screen]
    if menu then
        local hovered
        if screen == "title" and titleScreen then
            titleScreen:setMouse(x, y, width, height)
            hovered = titleScreen:buttonAt(menu, width, height, x, y)
        else
            hovered = Menu.buttonAt(menu, width, height, x, y)
        end
        if hovered and hovered ~= selectedButton then
            selectedButton = hovered
            Sfx.play("ui_hover")
        end
    end
end

function love.mousepressed(x, y, button)
    if not focused and love.window and love.window.hasFocus and love.window.hasFocus() then
        focused = true
    end
    x, y = Display.windowToVirtual(x, y)
    if confirmDialog then
        if button ~= 1 then return end
        local index = Menu.confirmButtonAt(confirmDialog, width, height, x, y)
        if index and confirmDialog.buttons[index] then
            confirmDialog.selected = index
            Sfx.play("ui_click")
            confirmDialog.buttons[index].action()
        end
        return
    end
    if screen == "armory" and armoryUI then
        local nextInv, action = armoryUI:mousepressed(armoryInventory, x, y, button)
        if nextInv then armoryInventory = nextInv end
        if action == "saveAndExit" then
            closeArmory(armoryInventory, true)
        elseif action == "cancelExit" then
            closeArmory(armoryInventory, false)
        end
        return
    end
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
    if screen == "playing" or screen == "warpSelect" then
        firing = focused
        return
    end
    local menu = menus[screen]
    if not menu then return end
    local index
    if screen == "title" and titleScreen then
        index = titleScreen:buttonAt(menu, width, height, x, y)
        if not index and titleScreen:isIntroActive() then
            titleScreen:skipIntro()
            return
        end
    else
        index = Menu.buttonAt(menu, width, height, x, y)
    end
    if index then
        if screen == "title" and titleScreen then
            titleScreen:skipIntro()
        end
        selectedButton = index
        Sfx.play("ui_click")
        menu.buttons[index].action()
    end
end

function love.mousereleased(x, y, button)
    x, y = Display.windowToVirtual(x, y)
    if screen == "armory" and armoryUI then
        local nextInv, action = armoryUI:mousereleased(armoryInventory, x, y, button)
        if nextInv then armoryInventory = nextInv end
        if action == "saveAndExit" then
            closeArmory(armoryInventory, true)
        end
        return
    end
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

function love.wheelmoved(wx, wy)
    if screen == "armory" and armoryUI then
        local mx, my = Display.getMousePosition()
        armoryUI:wheelmoved(mx, my, wx, wy)
    end
end

function love.focus(hasFocus)
    focused = hasFocus
    if not focused then
        input.boost, firing = false, false
        Sfx.stop()
    end
    Bgm.syncScreen(screen, stage and stage.level or nil, { focused = focused or testMode })
end

function love.resize(w, h)
    if love and love.graphics and love.graphics.getDimensions then
        local gw, gh = love.graphics.getDimensions()
        if gw and gh and gw > 0 and gh > 0 then
            w, h = gw, gh
        end
    end
    Display.resize(w, h)
    Arena.resize()
    rebuildFontsIfNeeded()
    local _, _, vpW, vpH = Display.viewportRect()
    if stars then stars:resize(vpW, vpH) end
    if stageBackground then stageBackground:resize(vpW, vpH) end
    if replay and replay.stars then replay.stars:resize(vpW, vpH) end
    if replay and replay.stageBackground then replay.stageBackground:resize(vpW, vpH) end
    if camera and ship then camera:update(0, ship, width, height) end
end
