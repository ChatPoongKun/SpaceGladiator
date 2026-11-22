-- Unit and integration tests for the 4x4 -> 6x6 diamond grid inventory,
-- grid-shaped modules & support chips, no separate stash (pending reward
-- discard), click-and-drop + hold-R rotation UI, core socket/link activation,
-- and Ship/Turret/Gladiator hooks.
-- Runnable via `love . --test-inventory` or standalone `luajit tests/inventory.lua`.

local function runTests(Inventory, Ship, Turret, Gladiator)
    -- 1. 4x4 diamond initial shape (12 cells) and 6x6 diamond maximum (24 cells)
    local inv = Inventory.new()
    assert(inv:unlockedCellCount() == 12, "4x4 diamond must start with 12 cells")
    assert(inv:maxCellCount() == 24, "6x6 diamond max must be 24 cells")
    assert(inv.stashModules == nil and inv.stashChips == nil, "No separate permanent stash must exist")

    local expectedStart = {
        {2,3}, {2,4},
        {3,2}, {3,3}, {3,4}, {3,5},
        {4,2}, {4,3}, {4,4}, {4,5},
        {5,3}, {5,4},
    }
    for _, coord in ipairs(expectedStart) do
        assert(inv:isUnlocked(coord[1], coord[2]), "Missing starting 4x4 diamond cell")
    end
    assert(not inv:isUnlocked(2, 2), "Outer 6x6 cell (2,2) must start locked")
    assert(not inv:isUnlocked(1, 3), "Outer tip (1,3) must start locked")
    assert(not inv:isUnlocked(3, 1), "Outer left tip (3,1) must start locked")
    assert(not inv:isUnlocked(6, 4), "Outer bottom tip (6,4) must start locked")

    -- 2. Outside-diamond cells can never be unlocked
    local okCorner, cornerReason = inv:unlockCell(1, 1)
    assert(not okCorner and cornerReason == "outside_diamond", "Corners outside 6x6 diamond must be rejected")
    assert(not inv:unlockCell(1, 2))
    assert(not inv:unlockCell(2, 1))
    assert(not inv:unlockCell(6, 6))

    -- 3. Permanent step-by-step expansion up to full 6x6 diamond (24 cells)
    local exp = inv:expandableCells()
    assert(#exp == 12, "All 12 outer 6x6 diamond cells are orthogonally adjacent to the 4x4 diamond")
    assert(inv:unlockCell(2, 2))
    assert(inv:unlockedCellCount() == 13)

    -- Serialization round-trip for permanent unlocks
    local saved = inv:serializeUnlockedCells()
    local reloaded = Inventory.new()
    reloaded:loadUnlockedCells(saved)
    assert(reloaded:unlockedCellCount() == 13 and reloaded:isUnlocked(2, 2))

    -- Unlock remaining cells up to full 6x6 diamond (24 cells)
    for _, cell in ipairs(inv:expandableCells()) do
        assert(inv:unlockCell(cell.r, cell.c))
    end
    assert(inv:unlockedCellCount() == 24, "Full expansion must reach 24 cells")
    assert(#inv:expandableCells() == 0, "No more cells expandable once 6x6 diamond is full")

    -- 4. Module & Support Chip grid shapes, placement, and 90-degree CW rotation
    local smallInv = Inventory.new()
    local missile = smallInv:createModule("missile")
    assert(not smallInv:canPlace(missile, 2, 2), "2x2 Missile Pod must not fit on locked (2,2)")
    assert(smallInv:placeModule(missile, 3, 3), "2x2 Missile Pod must fit in 4x4 diamond center (3,3)-(4,4)")

    -- 90-degree rotation test (1x3 laser -> 3x1 -> 1x3 -> 3x1)
    local laser = smallInv:createModule("laser")
    assert(laser.w == 1 and laser.h == 3 and laser.rotation == 0)
    assert(smallInv:rotateModule(laser))
    assert(laser.w == 3 and laser.h == 1 and laser.rotation == 1)
    assert(smallInv:rotateModule(laser))
    assert(laser.w == 1 and laser.h == 3 and laser.rotation == 2)
    assert(smallInv:rotateModule(laser))
    assert(laser.w == 3 and laser.h == 1 and laser.rotation == 3)

    -- Support chip as 1x1 grid item stored directly in the main diamond grid
    local splitter = smallInv:createChip("splitter")
    assert(splitter.kind == "chip" and splitter.w == 1 and splitter.h == 1)
    assert(smallInv:placeItem(splitter, 2, 3), "Support chip must be placeable in a 1x1 diamond cell")
    assert(smallInv.cells[2][3] == splitter and #smallInv.placedChips == 1)
    -- Placing chip into module socket automatically vacates its grid cell
    assert(smallInv:equipChip(missile, 3, splitter))
    assert(smallInv.cells[2][3] == nil and #smallInv.placedChips == 0)

    -- 5. Temporary stage reward tray: items not placed into inventory are discarded
    local pendingMod = smallInv:addPendingModule("shield")
    local pendingChip = smallInv:addPendingChip("burst")
    assert(smallInv:pendingCount() == 2)
    -- Place only the shield into the grid; leave burst unplaced
    assert(smallInv:placeItem(pendingMod, 2, 3, 0))
    assert(smallInv:pendingCount() == 1)
    local discarded = smallInv:discardPendingRewards()
    assert(discarded == 1 and smallInv:pendingCount() == 0, "Unplaced stage rewards must be discarded")
    assert(pendingChip.row == nil, "Discarded chip must not enter inventory")

    -- 6. Core Socket & Link BFS activation
    -- Missile Pod has 4 sockets; default links = { {1,2} }, so only sockets 1 and 2 are active.
    assert(smallInv:activeSocketCount(missile) == 2, "Missile Pod starts with 2 core-linked sockets")
    local burst = smallInv:createChip("burst")
    local feverChip = smallInv:createChip("fever_overdrive")
    local batteryChip = smallInv:createChip("dodge_charge")

    -- Compatibility check: battery chip must be rejected on weapon module
    local badOk, badReason = smallInv:equipChip(missile, 1, batteryChip)
    assert(not badOk and badReason == "incompatible_target", "Battery chip must not fit weapon module")

    -- Splitter is in UNLINKED socket 3 -> must NOT take effect yet
    local buildBeforeLink = smallInv:computeBuild(false)
    assert(buildBeforeLink.weapons[2].extraCount == 0, "Chip in unlinked socket must stay inactive")

    -- Unlock next link (2-3) -> socket 3 becomes reachable from Core Socket 1 -> splitter activates!
    assert(smallInv:unlockNextLink(missile))
    assert(smallInv:activeSocketCount(missile) == 3)
    local buildAfterLink = smallInv:computeBuild(false)
    assert(buildAfterLink.weapons[2].extraCount == 2, "Unlocking link must activate socket 3 chip")

    -- 7. Emergent Fever Overdrive (2x chip scaling during Fever + 1.3x non-fever battery)
    assert(smallInv:equipChip(missile, 1, burst))
    assert(smallInv:equipChip(missile, 2, feverChip))
    local normalBuild = smallInv:computeBuild(false)
    local feverBuild = smallInv:computeBuild(true)
    assert(normalBuild.weapons[2].extraCount == 2 and normalBuild.weapons[2].extraBurst == 2)
    assert(feverBuild.weapons[2].extraCount == 4 and feverBuild.weapons[2].extraBurst == 4,
        "Fever Overdrive must double linked chip numeric effects during Fever")
    assert(normalBuild.weapons[2].batteryCost > feverBuild.weapons[2].batteryCost,
        "Non-fever battery penalty must raise battery cost outside Fever")

    -- 8. Click-and-drop + hold-R rotation in InventoryUI (pure geometry test without drawing)
    local InventoryUI = require("inventory_ui")
    local ui = InventoryUI.new()
    local uiInv = Inventory.new()
    local rewardShield = uiInv:addPendingModule("shield") -- 2x1
    local rewardChip = uiInv:addPendingChip("splitter")   -- 1x1
    local step = 72 + 5
    ui.gridRect = { x = 100, y = 100, span = 6 * 72 + 5 * 5, cellSize = 72, gap = 5, gridSize = 6 }

    -- Pick up shield from tray, press R while holding (2x1 -> 1x2), drag to col 3 rows 3-4, release
    ui:startDrag(uiInv, rewardShield, "tray", 650, 250)
    assert(ui.dragging ~= nil and ui.dragging.rotation == 0)
    ui:keypressed(uiInv, "r")
    assert(ui.dragging.rotation == 1 and ui.dragging.rotated == true, "Pressing R while holding must rotate dragged item")
    -- Center of cells (3,3) and (4,3)
    local dropX = ui.gridRect.x + (3 - 1) * step + 36
    local dropY = ui.gridRect.y + (3 - 1) * step + 72 + 2.5
    ui:mousemoved(dropX, dropY)
    local res = ui:mousereleased(uiInv, dropX, dropY, 1, { stageEndMode = true })
    assert(res == "changed" and ui.dragging == nil, "Releasing dragged rotated item over valid cells must place it")
    assert(rewardShield.row == 3 and rewardShield.col == 3 and rewardShield.w == 1 and rewardShield.h == 2)

    -- Pick up 1x1 chip from tray and drop onto empty grid cell (2, 4)
    ui:startDrag(uiInv, rewardChip, "tray", 650, 320)
    local chipX = ui.gridRect.x + (4 - 1) * step + 36
    local chipY = ui.gridRect.y + (2 - 1) * step + 36
    ui:mousemoved(chipX, chipY)
    local chipRes = ui:mousereleased(uiInv, chipX, chipY, 1, { stageEndMode = true })
    assert(chipRes == "changed" and uiInv.cells[2][4] == rewardChip, "Chip dropped on empty diamond cell must be stored in grid")

    -- Drag a weapon chip from grid cell onto a weapon module's socket cell
    local projMod = uiInv:createModule("projectile")
    assert(uiInv:placeItem(projMod, 3, 4, 0))
    ui:startDrag(uiInv, rewardChip, "grid", chipX, chipY)
    local sockX = ui.gridRect.x + (4 - 1) * step + 36
    local sockY = ui.gridRect.y + (3 - 1) * step + 36
    ui:mousemoved(sockX, sockY)
    local equipRes = ui:mousereleased(uiInv, sockX, sockY, 1, { stageEndMode = true })
    assert(equipRes == "changed" and projMod.sockets[1] == rewardChip and uiInv.cells[2][4] == nil,
        "Dropping compatible chip onto module cell must equip it in that cell's socket")

    -- Right-click cancels drag and restores chip to socket
    ui:startDrag(uiInv, rewardChip, "socket", sockX, sockY, { mod = projMod, socketIndex = 1 })
    assert(projMod.sockets[1] == nil and ui.dragging ~= nil)
    ui:mousepressed(uiInv, sockX + 50, sockY + 50, 2, { stageEndMode = true })
    assert(ui.dragging == nil and projMod.sockets[1] == rewardChip, "Right-click must cancel drag and restore chip to socket")

    -- Smoke-test actual LÖVE rendering and verify every item image loads with exact grid aspect ratio
    if love and love.graphics then
        local ModulesData = require("modules_data")
        local ChipsData = require("chips_data")
        for _, def in ipairs(ModulesData.list) do
            assert(def.image, "Module missing image path: " .. def.id)
            local img = love.graphics.newImage(def.image)
            local iw, ih = img:getDimensions()
            assert(iw == def.w * 128 and ih == def.h * 128,
                string.format("Module %s image (%dx%d) must match grid size %dx%d", def.id, iw, ih, def.w * 128, def.h * 128))
        end
        for _, def in ipairs(ChipsData.list) do
            assert(def.image, "Chip missing image path: " .. def.id)
            local img = love.graphics.newImage(def.image)
            local iw, ih = img:getDimensions()
            assert(iw == def.w * 128 and ih == def.h * 128,
                string.format("Chip %s image (%dx%d) must match grid size %dx%d", def.id, iw, ih, def.w * 128, def.h * 128))
        end

        local menuFont = "assets/fonts/DriftMenu.ttf"
        local testFonts = {
            small = love.graphics.newFont(11),
            body = love.graphics.newFont(13),
            title = love.graphics.newFont(30),
            menuTitle = love.graphics.newFont(menuFont, 34),
            menuButton = love.graphics.newFont(menuFont, 18),
            menuBody = love.graphics.newFont(menuFont, 15),
        }
        uiInv:addPendingModule("laser")
        uiInv:addPendingChip("burst")

        -- Verify slot/socket indicators stay hidden until mouse hover so item artwork stays prominent.
        local function drawAndCaptureOverlays()
            local circles = 0
            local texts = {}
            local origCircle = love.graphics.circle
            local origPrintf = love.graphics.printf
            love.graphics.circle = function(...)
                circles = circles + 1
                return origCircle(...)
            end
            love.graphics.printf = function(txt, ...)
                texts[tostring(txt)] = true
                return origPrintf(txt, ...)
            end
            local ok, err = pcall(function()
                ui:draw(uiInv, testFonts, 1280, 800, false, { stageEndMode = true, returnTarget = "nextStage" })
            end)
            love.graphics.circle = origCircle
            love.graphics.printf = origPrintf
            assert(ok, err)
            return circles, texts
        end

        ui:mousemoved(0, 0)
        local idleCircles, idleTexts = drawAndCaptureOverlays()
        assert(idleCircles == 0 and not idleTexts["C"] and not idleTexts["SHLD"],
            "Module slot indicators must stay hidden when not hovered")

        -- Hover over the placed shield module at (row=3, col=3) -> slot/socket overlay appears
        local gStep = ui.gridRect.cellSize + ui.gridRect.gap
        local shieldHoverX = ui.gridRect.x + (rewardShield.col - 1) * gStep + ui.gridRect.cellSize * 0.5
        local shieldHoverY = ui.gridRect.y + (rewardShield.row - 1) * gStep + ui.gridRect.cellSize * 0.5
        ui:mousemoved(shieldHoverX, shieldHoverY)
        local hoverCircles, hoverTexts = drawAndCaptureOverlays()
        assert(hoverCircles > 0 and hoverTexts["C"] and hoverTexts["SHLD"],
            "Module slot indicators must appear when hovering over the module")

        ui:startDrag(uiInv, uiInv.pendingRewards[1], "tray", 800, 350)
        ui:keypressed(uiInv, "r")
        ui:mousemoved(ui.gridRect.x + 150, ui.gridRect.y + 150)
        ui:draw(uiInv, testFonts, 1280, 800, true, { stageEndMode = true, returnTarget = "plinko" })
        ui:cancelDrag(uiInv)
        ui:draw(uiInv, testFonts, 1280, 800, false, { stageEndMode = false, returnTarget = "playing" })
    end

    -- 9. Starter loadout baseline invariant check (must preserve existing flow.lua invariants)
    local starter = Inventory.newStarter()
    assert(starter:unlockedCellCount() == 12)
    assert(starter:pendingCount() == 0)
    local baseBuild = starter:computeBuild(false)
    assert(baseBuild.maxShieldBonus == 0 and baseBuild.maxArmorBonus == 0 and baseBuild.maxBatteryBonus == 0)
    assert(baseBuild.weapons[1].installed and baseBuild.weapons[1].extraCount == 0 and baseBuild.weapons[1].batteryCost == 0)

    -- 10. Integration with Ship, Turret, Gladiator
    if Ship and Turret and Gladiator then
        local ship = Ship.new(1080, 540)
        local turret = Turret.new(0)
        local gladiator = Gladiator.new()
        local mockCamera = {
            zoom = 1,
            worldToScreen = function(_, x, y) return x, y end,
            screenToWorld = function(_, x, y) return x, y end,
            clipRay = function() return 0, 500 end,
        }

        ship:applyBuild(baseBuild)
        assert(ship.maxShield == 100 and ship.maxArmor == 100 and ship.maxBattery == 100)

        -- Weapon 1 baseline fires 3 projectiles with 0 battery cost
        turret:fire(ship, ship.x, ship.y - 200, nil, 1, mockCamera, 1280, 800, baseBuild.weapons[1])
        assert(#turret.missiles == 3 and ship.battery == 100)

        -- Equip splitter + burst on starter projectile module -> 5 projectiles + 2 burst shots queued
        local starterProj = starter.placed[1]
        assert(starter:equipChip(starterProj, 1, starter:createChip("splitter")))
        assert(starter:equipChip(starterProj, 2, starter:createChip("burst")))
        local moddedBuild = starter:computeBuild(false)
        turret.missiles = {}
        turret.burstQueue = {}
        turret:fire(ship, ship.x, ship.y - 200, nil, 1, mockCamera, 1280, 800, moddedBuild.weapons[1])
        assert(#turret.missiles == 5, "Splitter must add +2 projectiles (3 -> 5)")
        assert(#turret.burstQueue == 2, "Burst Core must queue 2 follow-up shots")
        assert(ship.battery == 100 - moddedBuild.weapons[1].batteryCost, "Weapon fire must deduct battery cost")

        -- Limiter Off -> noShield + 1.5x Gladiator scoreMultiplier
        assert(starter:equipChip(starterProj, 2, starter:createChip("limiter_off")))
        local riskBuild = starter:computeBuild(false)
        ship:applyBuild(riskBuild)
        gladiator.scoreMultiplier = riskBuild.scoreMultiplier
        assert(ship.maxShield == 0 and ship.shield == 0, "Limiter Off must zero maxShield")
        local pts = gladiator:recordDestroy(100, 100)
        assert(pts == 15, "Limiter Off must multiply Gladiator points by 1.5 (10 -> 15)")

        -- Thruster + Wrap Phase -> wrap bonus speed + invulnerability on wrap
        local thruster = starter:createModule("thruster")
        assert(starter:placeModule(thruster, 3, 2))
        assert(starter:equipChip(thruster, 1, starter:createChip("wrap_phase")))
        local phaseBuild = starter:computeBuild(false)
        ship:applyBuild(phaseBuild)
        assert(ship.wrapBonusSpeed > Ship.wrapBonusSpeed and ship.wrapInvulnDuration > 0)
        -- Suppressing wrap detection (used during stage transitions) must wrap position without triggering wrap events/invuln
        ship.x, ship.vx, ship.wrapVx, ship.invulnTimer = 5, -180, 0, 0
        local wrapEventsBefore = ship.wrapEvents
        ship:update(0.1, { turn = 0, thrust = false, brake = false, boost = false }, { disableWrapDetection = true })
        assert(ship.x > 900, "Suppressed wrap detection must still wrap ship coordinates across arena edge")
        assert(ship.wrapEvents == wrapEventsBefore and ship.invulnTimer == 0,
            "Suppressed wrap detection must not increment wrapEvents or grant wrap invulnerability")
        -- Normal combat wrap detection still increments wrapEvents and grants invulnerability
        ship.x, ship.vx, ship.wrapVx = 5, -180, 0
        ship:update(0.1, { turn = 0, thrust = false, brake = false, boost = false })
        assert(ship.wrapEvents >= 1 and ship.invulnTimer > 0, "Wrapping with Wrap Phase must grant invulnerability")
        local armorBefore = ship.armor
        ship:takeDamage(20)
        assert(ship.armor == armorBefore, "Invulnerable ship must ignore damage during wrap phase")
    end

    print("PASS: 4x4->6x6 diamond grid inventory, grid-shaped click-and-drop + R rotation, no stash, chips, and Ship/Turret/Gladiator integration")
end

-- Support standalone execution via `luajit tests/inventory.lua`
if not love then
    package.path = "./?.lua;./?/init.lua;" .. package.path
    package.loaded["sfx"] = { play = function() end, load = function() end, stop = function() end }
    local Inventory = require("inventory")
    local Ship = require("ship")
    local Turret = require("turret")
    local Gladiator = require("gladiator")
    runTests(Inventory, Ship, Turret, Gladiator)
end

return runTests
