-- Unit and integration tests for Stage progression, stage-clear shutter transition,
-- 5-slot full-width random-drop Gladiator Coin Plinko, and 3-gate boundary starlight warp.
-- Runnable via `love . --test-plinko` or standalone `luajit tests/plinko_stage.lua`.

local function runTests(Stage, Plinko, Inventory, Ship, Enemies, StageTransition)
    StageTransition = StageTransition or require("stage_transition")

    -- 1. Stage timer expiration MUST NOT end the stage while enemies remain
    local s1 = Stage.new(1, { duration = 30, totalSquads = 2 })
    local mockEnemies = { squadsRemaining = 2, items = { { id = 1 } } }
    assert(not s1:update(20, mockEnemies))
    assert(math.abs(s1:remainingTime() - 10) < 1e-6)
    assert(not s1:update(10, mockEnemies), "Stage must NOT clear while enemies remain even after timer hits 0")
    assert(not s1.cleared and s1:isOvertime(), "Stage should enter overtime while remaining hostiles exist")
    assert(mockEnemies.squadsRemaining == 0, "Remaining squad quota should stop spawning after timer expires")
    assert(not s1:update(5, mockEnemies), "Stage still must NOT clear as long as any enemy remains")
    -- Once last remaining enemy is gone, stage clears immediately
    mockEnemies.items = {}
    assert(s1:update(0.1, mockEnemies), "Stage must clear once timer expired and all remaining enemies are gone")
    assert(s1.cleared and s1.clearReason == "STAGE TIME COMPLETE")

    -- 2. Stage early clear when all scheduled squads are spawned and defeated
    local s2 = Stage.new(2, { duration = 45, totalSquads = 3 })
    local clearedEnemies = { squadsRemaining = 0, items = {} }
    assert(s2:update(1.0, clearedEnemies))
    assert(s2.cleared and s2.clearReason == "ALL HOSTILES CLEARED")

    -- 3. Enemies squad quota enforcement
    if Enemies and Ship then
        local ship = Ship.new(1080, 540)
        local enemies = Enemies.new(function() return 0.5 end)
        local st = Stage.new(1, { duration = 60, totalSquads = 2 })
        st:configureEnemies(enemies)
        assert(enemies.squadsRemaining == 2)
        for _ = 1, 20 do
            enemies:update(0.5, ship, 0, nil, 1280, 800)
        end
        assert(enemies.squadsRemaining == 0, "Enemies must stop spawning once stage squad quota hits 0")
    end

    -- 4. 2.0-second Stage Clear hold + left/right shutter close + shutter open sequence
    local clearState = StageTransition.newStageClear(s2)
    assert(math.abs(clearState.totalDuration - 2.0) < 1e-6, "Stage clear transition must last 2.0 seconds")
    assert(not StageTransition.updateStageClear(clearState, 1.0))
    assert(StageTransition.stageClearCloseProgress(clearState) == 0, "Shutters stay open during initial STAGE CLEAR banner")
    assert(not StageTransition.updateStageClear(clearState, 0.5))
    assert(StageTransition.stageClearCloseProgress(clearState) > 0 and StageTransition.stageClearCloseProgress(clearState) < 1,
        "Shutters must be mid-close between 1.25s and 2.0s")
    assert(StageTransition.updateStageClear(clearState, 0.5), "Stage clear must finish at 2.0s to open Plinko")
    assert(StageTransition.stageClearCloseProgress(clearState) == 1)

    local openShutter = StageTransition.newShutterOpen()
    assert(not StageTransition.updateShutterOpen(openShutter, 0.2))
    assert(StageTransition.updateShutterOpen(openShutter, 0.5), "Plinko opening shutter must complete cleanly")

    -- 5. Three random boundary warp gates with distinct edges, rewards, trigger detection, and starlight warp
    local seedState = 777
    local function detRng()
        seedState = (seedState * 48271) % 2147483647
        return seedState / 2147483647
    end
    local gatesState = StageTransition.generateWarpGates(1080, 540, detRng)
    assert(#gatesState.gates == 3, "Must generate exactly 3 boundary warp gates")
    local seenEdges, seenRewards = {}, {}
    for _, g in ipairs(gatesState.gates) do
        assert(not seenEdges[g.edge], "Each warp gate must sit on a distinct arena boundary")
        assert(not seenRewards[g.reward.id], "Each warp gate must advertise a distinct major reward")
        seenEdges[g.edge] = true
        seenRewards[g.reward.id] = true
    end

    if Ship then
        local testShip = Ship.new(1080, 540)
        -- Gate should not trigger during initial readyDelay
        local targetGate = gatesState.gates[1]
        testShip.x, testShip.y = targetGate.x - targetGate.dirX * 20, targetGate.y - targetGate.dirY * 20
        assert(StageTransition.checkGateTrigger(gatesState, testShip) == nil)
        StageTransition.updateWarpGates(gatesState, 0.3)
        local triggered = StageTransition.checkGateTrigger(gatesState, testShip)
        assert(triggered == targetGate, "Flying into a boundary gate must trigger warp to next stage")

        -- Starlight warp speeds up then slows down smoothly as arriving at next stage
        local warp = StageTransition.newWarp(triggered, 2, testShip, 1280, 800, detRng)
        local peakSpeed = StageTransition.warpSpeedFactor(0.42)
        local arriveSpeed = StageTransition.warpSpeedFactor(0.95)
        assert(peakSpeed > 0.95 and arriveSpeed < 0.15, "Warp must cruise fast through starlight then slow down on arrival")
        local done = false
        for _ = 1, 180 do
            if StageTransition.updateWarp(warp, 1 / 60, testShip, nil, nil, 1280, 800) then
                done = true
                break
            end
        end
        assert(done and warp.done, "Starlight warp must finish and hand off to the next stage")
        assert(math.abs(testShip.x - 540) < 1e-3 and math.abs(testShip.y - 270) < 1e-3,
            "Ship must arrive smoothly at the center of the next arena")
    end

    -- 6. Plinko featured reward override + 5-slot edge-weighted rarity distribution check
    local pWeapon = Plinko.new({ stageNumber = 2, coins = 0, seed = 101, featuredReward = "weapon_module" })
    assert(pWeapon.slots[1].reward.spec.kind == "module", "Weapon warp gate must guarantee a featured weapon module slot")

    local outerHigh, centerHigh = 0, 0
    for seed = 1, 120 do
        local p = Plinko.new({ stageNumber = 1, coins = 0, seed = seed * 97 })
        assert(#p.slots == 5, "Plinko must have exactly 5 slots")
        if p.slots[1].tier == "high" then outerHigh = outerHigh + 1 end
        if p.slots[5].tier == "high" then outerHigh = outerHigh + 1 end
        if p.slots[3].tier == "high" then centerHigh = centerHigh + 1 end
    end
    assert((outerHigh / 2) > centerHigh * 2,
        "Outer slots (1 and 5) must roll high-value rewards significantly more often than center slot (3)")

    -- 7. Full-width random coin drops land across all 5 slots and grant rewards into Inventory
    local inv = Inventory.new()
    local ship = Ship and Ship.new(1080, 540) or nil
    local p = Plinko.new({ stageNumber = 1, coins = 200, seed = 4242 })
    local spent = p:invest(180)
    assert(spent == 180 and p.coins == 20 and p.invested == 180)
    p:resolveAll(inv, ship)
    assert(not p:isBusy())

    local totalLanded = 0
    local claimedCount = 0
    for i = 1, 5 do
        local slot = p.slots[i]
        totalLanded = totalLanded + slot.filled
        assert(slot.filled > 0, "Full-width random drop should reach all 5 slots over 180 coins (slot " .. i .. ")")
        if slot.claimed then claimedCount = claimedCount + 1 end
    end
    assert(totalLanded == 180, "All 180 dropped coins must land in a slot")
    assert(claimedCount >= 1 and #p.claimedLog == claimedCount, "Claimed log must match claimed slots without duplicates")
    assert(inv:pendingCount() >= 1 or claimedCount >= 1)

    -- 8. Default discard of unclaimed slots vs future permanent carryover hook
    local pDiscard = Plinko.new({ stageNumber = 1, coins = 15, seed = 9001, carryoverEnabled = false })
    pDiscard:invest(10)
    pDiscard:resolveAll(inv, ship)
    local exportedOff = pDiscard:exportCarryoverSlots()
    assert(next(exportedOff) == nil, "Unclaimed slots must be discarded when carryoverEnabled is false")

    local pCarry = Plinko.new({ stageNumber = 1, coins = 15, seed = 9001, carryoverEnabled = true })
    pCarry:invest(10)
    pCarry:resolveAll(inv, ship)
    local exportedOn = pCarry:exportCarryoverSlots()
    local carriedIndex, carriedFilled, carriedTitle
    for idx, data in pairs(exportedOn) do
        carriedIndex, carriedFilled, carriedTitle = idx, data.filled, data.reward.title
        break
    end
    assert(carriedIndex ~= nil and carriedFilled > 0, "Carryover hook must export partially filled unclaimed slots")

    local pNext = Plinko.new({ stageNumber = 2, coins = 50, seed = 9002, carriedSlots = exportedOn })
    assert(pNext.slots[carriedIndex].carriedOver == true)
    assert(pNext.slots[carriedIndex].filled == carriedFilled)
    assert(pNext.slots[carriedIndex].reward.title == carriedTitle)

    -- 9. Live LÖVE draw & UI label check (verifies no draw errors, valid Korean glyphs,
    --    and that stage-end item placement returns to battlefield instead of Plinko)
    if love and love.graphics then
        local InventoryUI = require("inventory_ui")
        local PlinkoUI = require("plinko_ui")
        local Camera = require("camera")
        local menuFont = "assets/fonts/DriftMenu.ttf"
        local fonts = {
            small = love.graphics.newFont(11),
            body = love.graphics.newFont(13),
            title = love.graphics.newFont(30),
            menuTitle = love.graphics.newFont(menuFont, 34),
            menuButton = love.graphics.newFont(menuFont, 18),
            menuBody = love.graphics.newFont(menuFont, 15),
            menuSmall = love.graphics.newFont(menuFont, 12),
        }
        local g = love.graphics
        local seenTexts = {}
        local origPrint, origPrintf = g.print, g.printf
        g.print = function(txt, ...)
            seenTexts[tostring(txt)] = true
            assert(g.getFont():hasGlyphs(tostring(txt)), "Missing glyph in print: " .. tostring(txt))
            return origPrint(txt, ...)
        end
        g.printf = function(txt, ...)
            seenTexts[tostring(txt)] = true
            assert(g.getFont():hasGlyphs(tostring(txt)), "Missing glyph in printf: " .. tostring(txt))
            return origPrintf(txt, ...)
        end
        local ok, err = pcall(function()
            -- Draw Stage Clear + closing shutters
            local cs = StageTransition.newStageClear(s2)
            StageTransition.updateStageClear(cs, 1.6)
            StageTransition.drawStageClearOverlay(cs, 1280, 800, fonts)
            assert(seenTexts["STAGE CLEAR"], "Stage clear banner must render STAGE CLEAR")

            -- Draw Plinko + opening shutters
            local pui = PlinkoUI.new()
            local osState = StageTransition.newShutterOpen()
            StageTransition.updateShutterOpen(osState, 0.2)
            pui:draw(pNext, s2, fonts, 1280, 800, 0)
            StageTransition.drawShutterOpen(osState, 1280, 800)

            -- Draw Inventory in Plinko item-placement mode: must show return-to-battlefield, NOT return-to-Plinko
            seenTexts = {}
            local iui = InventoryUI.new()
            local invEmpty = Inventory.newStarter()
            iui:draw(invEmpty, fonts, 1280, 800, false, { stageEndMode = true, returnTarget = "warpSelect" })
            assert(seenTexts["전장으로 복귀"], "Item placement screen must show return-to-battlefield button")
            assert(not seenTexts["플링코 복귀"], "Item placement screen must not show return-to-Plinko button")

            -- Draw 3 boundary warp gates + hyperspace starlight warp
            local cam = Camera.new(540, 270)
            local drawShip = Ship.new(1080, 540)
            cam:update(0, drawShip, 1280, 800)
            StageTransition.drawWarpGates(gatesState, drawShip, 1.5, fonts)
            local drawWarp = StageTransition.newWarp(gatesState.gates[1], 3, drawShip, 1280, 800, detRng)
            StageTransition.updateWarp(drawWarp, 1.0, drawShip, nil, cam, 1280, 800)
            StageTransition.drawWarp(drawWarp, drawShip, cam, 1280, 800, 2.0, fonts)
        end)
        g.print, g.printf = origPrint, origPrintf
        assert(ok, err)
    end

    print("PASS: Stage enemy-guard, 2s shutter transition, 5-slot Plinko, 3-gate boundary rewards, and starlight warp")
end

if not love then
    package.path = "./?.lua;./?/init.lua;" .. package.path
    package.loaded["sfx"] = { play = function() end, load = function() end, stop = function() end }
    local Stage = require("stage")
    local Plinko = require("plinko")
    local Inventory = require("inventory")
    local Ship = require("ship")
    local Enemies = require("enemies")
    local StageTransition = require("stage_transition")
    runTests(Stage, Plinko, Inventory, Ship, Enemies, StageTransition)
end

return runTests
