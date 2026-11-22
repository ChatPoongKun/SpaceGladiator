++ b/tests/plinko_stage.lua
-- Unit and integration tests for Stage progression and the 5-slot full-width
-- random-drop Gladiator Coin Plinko machine.
-- Runnable via `love . --test-plinko` or standalone `luajit tests/plinko_stage.lua`.

local function runTests(Stage, Plinko, Inventory, Ship, Enemies)
    -- 1. Stage timer expiration clear
    local s1 = Stage.new(1, { duration = 30, totalSquads = 2 })
    local mockEnemies = { squadsRemaining = 2, items = { { id = 1 } } }
    assert(not s1:update(20, mockEnemies))
    assert(math.abs(s1:remainingTime() - 10) < 1e-6)
    assert(s1:update(10, mockEnemies))
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

    -- 4. Plinko 5-slot edge-weighted rarity distribution check
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

    -- 5. Full-width random coin drops land across all 5 slots and grant rewards into Inventory
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
    assert((#inv.stashModules + #inv.stashChips) >= 1 or claimedCount >= 1)

    -- 6. Default discard of unclaimed slots vs future permanent carryover hook
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

    print("PASS: Stage timer/early-clear, 5-slot full-width Plinko, reward granting, and carryover hook")
end

if not love then
    package.path = "./?.lua;./?/init.lua;" .. package.path
    package.loaded["sfx"] = { play = function() end, load = function() end, stop = function() end }
    local Stage = require("stage")
    local Plinko = require("plinko")
    local Inventory = require("inventory")
    local Ship = require("ship")
    local Enemies = require("enemies")
    runTests(Stage, Plinko, Inventory, Ship, Enemies)
end

return runTests
