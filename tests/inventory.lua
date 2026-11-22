-- Unit and integration tests for the 3x3 -> 5x5 diamond grid inventory,
-- core socket/link activation, support chips, and Ship/Turret/Gladiator hooks.
-- Runnable both via `love . --test-inventory` and standalone `luajit tests/inventory.lua`.

local function runTests(Inventory, Ship, Turret, Gladiator)
    -- 1. 3x3 diamond initial shape (5 cells) and 5x5 diamond maximum (13 cells)
    local inv = Inventory.new()
    assert(inv:unlockedCellCount() == 5, "3x3 diamond must start with 5 cells")
    assert(inv:maxCellCount() == 13, "5x5 diamond max must be 13 cells")
    local expectedStart = { {2,3}, {3,2}, {3,3}, {3,4}, {4,3} }
    for _, coord in ipairs(expectedStart) do
        assert(inv:isUnlocked(coord[1], coord[2]), "Missing starting diamond cell")
    end
    assert(not inv:isUnlocked(2, 2), "Diagonal cell (2,2) must start locked")
    assert(not inv:isUnlocked(1, 3), "Outer tip (1,3) must start locked")

    -- 2. Outside-diamond cells can never be unlocked
    local okCorner, cornerReason = inv:unlockCell(1, 1)
    assert(not okCorner and cornerReason == "outside_diamond", "Corners outside 5x5 diamond must be rejected")
    assert(not inv:unlockCell(1, 2))
    assert(not inv:unlockCell(5, 5))

    -- 3. Permanent step-by-step expansion up to full 5x5 diamond (13 cells)
    local exp = inv:expandableCells()
    assert(#exp == 8, "All 8 outer diamond cells are orthogonally adjacent to the 3x3 diamond")
    assert(inv:unlockCell(2, 2))
    assert(inv:unlockedCellCount() == 6)

    -- Serialization round-trip for permanent unlocks
    local saved = inv:serializeUnlockedCells()
    local reloaded = Inventory.new()
    reloaded:loadUnlockedCells(saved)
    assert(reloaded:unlockedCellCount() == 6 and reloaded:isUnlocked(2, 2))

    -- 4. Module placement & geometry gating (2x2 Missile Pod requires diagonal unlock)
    local smallInv = Inventory.new()
    local missile = smallInv:createModule("missile")
    assert(not smallInv:canPlace(missile, 2, 2), "2x2 Missile Pod must not fit in 3x3 diamond")
    assert(smallInv:unlockCell(2, 2), "Unlocking (2,2) forms a 2x2 area (2,2)-(3,3)")
    assert(smallInv:placeModule(missile, 2, 2), "2x2 Missile Pod must fit after unlocking (2,2)")

    -- Rotation test
    local shield = smallInv:createModule("shield") -- 2x1
    assert(shield.w == 2 and shield.h == 1)
    assert(smallInv:rotateModule(shield))
    assert(shield.w == 1 and shield.h == 2)

    -- 5. Core Socket & Link BFS activation
    -- Missile Pod has 4 sockets; default links = { {1,2} }, so only sockets 1 and 2 are active.
    assert(smallInv:activeSocketCount(missile) == 2, "Missile Pod starts with 2 core-linked sockets")
    local splitter = smallInv:createChip("splitter")
    local burst = smallInv:createChip("burst")
    local feverChip = smallInv:createChip("fever_overdrive")
    local batteryChip = smallInv:createChip("dodge_charge")

    -- Compatibility check: battery chip must be rejected on weapon module
    local badOk, badReason = smallInv:equipChip(missile, 1, batteryChip)
    assert(not badOk and badReason == "incompatible_target", "Battery chip must not fit weapon module")

    -- Equip splitter in UNLINKED socket 3 -> must NOT take effect yet
    assert(smallInv:equipChip(missile, 3, splitter))
    local buildBeforeLink = smallInv:computeBuild(false)
    assert(buildBeforeLink.weapons[2].extraCount == 0, "Chip in unlinked socket must stay inactive")

    -- Unlock next link (2-3) -> socket 3 becomes reachable from Core Socket 1 -> splitter activates!
    assert(smallInv:unlockNextLink(missile))
    assert(smallInv:activeSocketCount(missile) == 3)
    local buildAfterLink = smallInv:computeBuild(false)
    assert(buildAfterLink.weapons[2].extraCount == 2, "Unlocking link must activate socket 3 chip")

    -- 6. Emergent Fever Overdrive (2x chip scaling during Fever + 1.3x non-fever battery)
    assert(smallInv:equipChip(missile, 1, burst))
    assert(smallInv:equipChip(missile, 2, feverChip))
    local normalBuild = smallInv:computeBuild(false)
    local feverBuild = smallInv:computeBuild(true)
    assert(normalBuild.weapons[2].extraCount == 2 and normalBuild.weapons[2].extraBurst == 2)
    assert(feverBuild.weapons[2].extraCount == 4 and feverBuild.weapons[2].extraBurst == 4,
        "Fever Overdrive must double linked chip numeric effects during Fever")
    assert(normalBuild.weapons[2].batteryCost > feverBuild.weapons[2].batteryCost,
        "Non-fever battery penalty must raise battery cost outside Fever")

    -- 7. Starter loadout baseline invariant check (must preserve existing flow.lua invariants)
    local starter = Inventory.newStarter()
    assert(starter:unlockedCellCount() == 5)
    local baseBuild = starter:computeBuild(false)
    assert(baseBuild.maxShieldBonus == 0 and baseBuild.maxArmorBonus == 0 and baseBuild.maxBatteryBonus == 0)
    assert(baseBuild.weapons[1].installed and baseBuild.weapons[1].extraCount == 0 and baseBuild.weapons[1].batteryCost == 0)

    -- 8. Integration with Ship, Turret, Gladiator
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
        ship.x, ship.vx = 5, -180
        ship:update(0.1, { turn = 0, thrust = false, brake = false, boost = false })
        assert(ship.wrapEvents >= 1 and ship.invulnTimer > 0, "Wrapping with Wrap Phase must grant invulnerability")
        local armorBefore = ship.armor
        ship:takeDamage(20)
        assert(ship.armor == armorBefore, "Invulnerable ship must ignore damage during wrap phase")
    end

    print("PASS: 3x3->5x5 diamond grid inventory, core socket/link BFS, chips, and Ship/Turret/Gladiator integration")
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
