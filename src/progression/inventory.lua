-- Chassis-driven Grid Inventory (e.g. 5x3 triangle for Striker MK-I).
-- Pure Lua logic (no LÖVE graphics dependency) so it can be unit-tested cleanly.
-- Handles module & support chip placement, rotation, socket activation,
-- derived build stats, sortie validation, cloning, and loadout serialization.

local ChassisData = require("src.data.chassis_data")
local ModulesData = require("src.data.modules_data")
local ChipsData = require("src.data.chips_data")
local Rarity = require("src.data.rarity")

local Inventory = {}
Inventory.__index = Inventory
Inventory.DEFAULT_ROTATION_UNLOCKED = false

local function cellKey(r, c)
    return r .. "," .. c
end

local function canonicalCategory(category)
    if category == "battery" then
        return "generator"
    end
    return category
end

-- Duplicate parts in the same non-generator category add +50% battery usage per
-- extra part on every module in that category (2 -> +50%, 3 -> +100%, 4 -> +150%).
function Inventory.getDuplicateBatteryPenalty(category, count)
    local cat = canonicalCategory(category)
    local n = math.floor(tonumber(count) or 0)
    if cat == "generator" or n <= 1 then
        return 1.0, 0
    end
    local addPct = (n - 1) * 50
    return 1.0 + 0.5 * (n - 1), addPct
end

local function removeFromList(list, item)
    for i = 1, #list do
        if list[i] == item then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function initGridForChassis(self, chassis)
    self.chassisId = chassis.id
    self.chassis = chassis
    self.rows = chassis.grid.rows
    self.cols = chassis.grid.cols
    self.mask = chassis.grid.mask
    self.gridSize = math.max(self.rows, self.cols)
    self.unlocked = {}
    self.cells = {}
    self.placed = {}
    self.placedChips = {}
    self.pendingRewards = {}

    for r = 1, self.rows do
        self.cells[r] = {}
        self.unlocked[r] = {}
        for c = 1, self.cols do
            self.unlocked[r][c] = (self.mask[r] and self.mask[r][c] == 1) or false
        end
    end
end

function Inventory.normalizeRotation(rot)
    if type(rot) == "boolean" then
        return rot and 1 or 0
    end
    local n = math.floor(tonumber(rot) or 0)
    return ((n % 4) + 4) % 4
end

-- Returns rotated 0-indexed cell coordinates {{dr, dc}, ...}, bounding width w,
-- and bounding height h for a module/chip instance or its definition.
-- Preserves cell ordering so index i maps directly to socket i on modules.
function Inventory.getShapeCells(itemOrDef, rotation)
    local def = (itemOrDef and itemOrDef.def) or itemOrDef
    if not def then return {}, 0, 0 end

    local rot
    if rotation ~= nil then
        rot = Inventory.normalizeRotation(rotation)
    elseif itemOrDef.rotation ~= nil then
        rot = Inventory.normalizeRotation(itemOrDef.rotation)
    else
        rot = Inventory.normalizeRotation(itemOrDef.rotated)
    end

    local cells = {}
    if def.shape and #def.shape > 0 then
        for i, coord in ipairs(def.shape) do
            cells[i] = { coord[1], coord[2] }
        end
    else
        local baseW = def.w or 1
        local baseH = def.h or 1
        for dr = 0, baseH - 1 do
            for dc = 0, baseW - 1 do
                cells[#cells + 1] = { dr, dc }
            end
        end
    end

    for _ = 1, rot do
        local maxR = 0
        for _, coord in ipairs(cells) do
            if coord[1] > maxR then maxR = coord[1] end
        end
        for _, coord in ipairs(cells) do
            local nr = coord[2]
            local nc = maxR - coord[1]
            coord[1], coord[2] = nr, nc
        end
        local minR, minC = math.huge, math.huge
        for _, coord in ipairs(cells) do
            if coord[1] < minR then minR = coord[1] end
            if coord[2] < minC then minC = coord[2] end
        end
        for _, coord in ipairs(cells) do
            coord[1] = coord[1] - minR
            coord[2] = coord[2] - minC
        end
    end

    local maxR, maxC = 0, 0
    for _, coord in ipairs(cells) do
        if coord[1] > maxR then maxR = coord[1] end
        if coord[2] > maxC then maxC = coord[2] end
    end
    return cells, maxC + 1, maxR + 1
end

function Inventory.new(opts)
    opts = opts or {}
    local chassis = ChassisData.get(opts.chassisId or ChassisData.DEFAULT_ID)
    local rotationUnlocked
    if opts.rotationUnlocked ~= nil then
        rotationUnlocked = opts.rotationUnlocked == true
    else
        rotationUnlocked = Inventory.DEFAULT_ROTATION_UNLOCKED
    end
    local self = setmetatable({
        nextId = 1,
        metaPoints = opts.metaPoints or 0,
        expandCost = opts.expandCost or 100,
        rotationUnlocked = rotationUnlocked,
    }, Inventory)

    initGridForChassis(self, chassis)

    if opts.unlockedCells then
        for _, coord in ipairs(opts.unlockedCells) do
            local r, c = coord[1], coord[2]
            if self:isValidCell(r, c) then
                self.unlocked[r][c] = true
            end
        end
    end

    return self
end

function Inventory:setChassis(chassisId)
    local chassis = ChassisData.get(chassisId)
    initGridForChassis(self, chassis)
    return chassis
end

function Inventory:isValidCell(r, c)
    if not r or not c or r < 1 or r > self.rows or c < 1 or c > self.cols then
        return false
    end
    return self.mask[r] ~= nil and self.mask[r][c] == 1
end

function Inventory:isUnlocked(r, c)
    if not self:isValidCell(r, c) or not self.unlocked[r] then
        return false
    end
    return self.unlocked[r][c] == true
end

function Inventory:unlockedCellCount()
    local count = 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self:isUnlocked(r, c) then count = count + 1 end
        end
    end
    return count
end

function Inventory:maxCellCount()
    local count = 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self:isValidCell(r, c) then count = count + 1 end
        end
    end
    return count
end

function Inventory:canUnlockCell(r, c)
    if not self:isValidCell(r, c) then
        return false, "outside_chassis"
    end
    if self:isUnlocked(r, c) then
        return false, "already_unlocked"
    end
    local neighbors = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, d in ipairs(neighbors) do
        if self:isUnlocked(r + d[1], c + d[2]) then
            return true
        end
    end
    return false, "not_adjacent"
end

function Inventory:expandableCells()
    local result = {}
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self:canUnlockCell(r, c) then
                result[#result + 1] = { r = r, c = c }
            end
        end
    end
    return result
end

function Inventory:unlockCell(r, c)
    local ok, reason = self:canUnlockCell(r, c)
    if not ok then return false, reason end
    self.unlocked[r][c] = true
    return true
end

function Inventory:createModule(defId, opts)
    local def = ModulesData.get(defId)
    assert(def, "Unknown module id: " .. tostring(defId))
    local _, w, h = Inventory.getShapeCells(def, 0)
    local mod = {
        kind = "module",
        id = self.nextId,
        defId = def.id,
        def = def,
        rarity = Rarity.normalize((opts and opts.rarity) or def.rarity),
        w = w,
        h = h,
        rotation = 0,
        rotated = false,
        row = nil,
        col = nil,
        disabled = false,
        maxSockets = def.maxSockets,
        sockets = {},
    }
    self.nextId = self.nextId + 1
    return mod
end

function Inventory:createChip(chipId, opts)
    local def = ChipsData.get(chipId)
    assert(def, "Unknown chip id: " .. tostring(chipId))
    local _, w, h = Inventory.getShapeCells(def, 0)
    local chip = {
        kind = "chip",
        id = self.nextId,
        defId = def.id,
        def = def,
        rarity = Rarity.normalize((opts and opts.rarity) or def.rarity),
        w = w,
        h = h,
        rotation = 0,
        rotated = false,
        row = nil,
        col = nil,
    }
    self.nextId = self.nextId + 1
    return chip
end

function Inventory:addPendingModule(defId, opts)
    local mod = type(defId) == "table" and defId or self:createModule(defId, opts)
    self.pendingRewards[#self.pendingRewards + 1] = mod
    return mod
end

function Inventory:addPendingChip(chipId, opts)
    local chip = type(chipId) == "table" and chipId or self:createChip(chipId, opts)
    self.pendingRewards[#self.pendingRewards + 1] = chip
    return chip
end

function Inventory:addPendingItem(item)
    if not item then return nil end
    for i = 1, #self.pendingRewards do
        if self.pendingRewards[i] == item then return item end
    end
    self.pendingRewards[#self.pendingRewards + 1] = item
    return item
end

function Inventory:removePendingItem(item)
    return removeFromList(self.pendingRewards, item)
end

function Inventory:pendingCount()
    return #self.pendingRewards
end

function Inventory:discardPendingRewards()
    local discarded = #self.pendingRewards
    self.pendingRewards = {}
    return discarded
end

function Inventory:moduleDimensions(item, rotation)
    local _, w, h = Inventory.getShapeCells(item, rotation)
    return w, h
end

function Inventory:getItemCells(item, row, col, rotation)
    local r0 = row or item.row
    local c0 = col or item.col
    if not r0 or not c0 then return {} end
    local shapeCells = Inventory.getShapeCells(item, rotation)
    local result = {}
    for i, coord in ipairs(shapeCells) do
        result[i] = { r = r0 + coord[1], c = c0 + coord[2] }
    end
    return result
end

function Inventory:getSocketAtGridCell(mod, r, c)
    if not mod or mod.kind ~= "module" or not mod.row or not mod.col then
        return nil
    end
    local shapeCells = Inventory.getShapeCells(mod, mod.rotation)
    for i, coord in ipairs(shapeCells) do
        if mod.row + coord[1] == r and mod.col + coord[2] == c then
            if i <= (mod.maxSockets or 0) then
                return i
            end
        end
    end
    return nil
end

function Inventory:findEquippedChip(chip)
    if not chip then return nil, nil end
    for _, mod in ipairs(self.placed) do
        for i = 1, mod.maxSockets do
            if mod.sockets[i] == chip then
                return mod, i
            end
        end
    end
    return nil, nil
end

function Inventory:canPlace(item, row, col, rotation)
    if not item or not row or not col then return false, "invalid_item" end
    if self.chassis and self.chassis.locked then return false, "locked_chassis" end
    local rot = rotation ~= nil and Inventory.normalizeRotation(rotation) or (item.rotation or 0)
    if not self.rotationUnlocked and rot ~= 0 then
        return false, "rotation_locked"
    end
    local shapeCells = Inventory.getShapeCells(item, rot)
    if #shapeCells == 0 then return false, "invalid_shape" end
    for _, coord in ipairs(shapeCells) do
        local r, c = row + coord[1], col + coord[2]
        if not self:isUnlocked(r, c) then
            return false, "locked_or_out_of_bounds"
        end
        local occupant = self.cells[r][c]
        if occupant and occupant ~= item then
            return false, "occupied"
        end
    end
    return true
end

function Inventory:removeItem(item, toPending)
    if not item or not item.row then return false end
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.cells[r][c] == item then
                self.cells[r][c] = nil
            end
        end
    end
    item.row, item.col = nil, nil
    if item.kind == "chip" then
        removeFromList(self.placedChips, item)
    else
        removeFromList(self.placed, item)
    end
    if toPending == true then
        self:addPendingItem(item)
    end
    return true
end

function Inventory:removeModule(mod, toPending)
    return self:removeItem(mod, toPending)
end

function Inventory:placeItem(item, row, col, rotation)
    if not item then return false, "invalid_item" end
    local rot = rotation ~= nil and Inventory.normalizeRotation(rotation) or (item.rotation or 0)
    local ok, reason = self:canPlace(item, row, col, rot)
    if not ok then return false, reason end

    if item.row then
        self:removeItem(item, false)
    else
        removeFromList(self.pendingRewards, item)
        if item.kind == "chip" then
            local hostMod, hostIdx = self:findEquippedChip(item)
            if hostMod and hostIdx then
                hostMod.sockets[hostIdx] = nil
            end
        end
    end

    local shapeCells, w, h = Inventory.getShapeCells(item, rot)
    item.rotation = rot
    item.rotated = (rot % 2 == 1)
    item.w, item.h = w, h
    item.row, item.col = row, col
    for _, coord in ipairs(shapeCells) do
        self.cells[row + coord[1]][col + coord[2]] = item
    end
    if item.kind == "chip" then
        self.placedChips[#self.placedChips + 1] = item
    else
        self.placed[#self.placed + 1] = item
    end
    return true
end

function Inventory:placeModule(mod, row, col, rotation)
    return self:placeItem(mod, row, col, rotation)
end

function Inventory:rotateItem(item, steps)
    if not item then return false, "invalid_item" end
    if not self.rotationUnlocked then return false, "rotation_locked" end
    local nextRot = Inventory.normalizeRotation((item.rotation or 0) + (steps or 1))
    if not item.row then
        local _, w, h = Inventory.getShapeCells(item, nextRot)
        item.rotation = nextRot
        item.rotated = (nextRot % 2 == 1)
        item.w, item.h = w, h
        return true
    end
    return self:placeItem(item, item.row, item.col, nextRot)
end

function Inventory:rotateModule(mod, steps)
    return self:rotateItem(mod, steps)
end

function Inventory:equippedSocketCount(mod)
    if not mod then return 0 end
    local count = 0
    for i = 1, (mod.maxSockets or 0) do
        if mod.sockets[i] then count = count + 1 end
    end
    return count
end

function Inventory:equipChip(mod, socketIndex, chip)
    if not mod or not chip then return false, "invalid_args" end
    if socketIndex < 1 or socketIndex > mod.maxSockets then
        return false, "invalid_socket"
    end
    if not ChipsData.isCompatible(chip.def, mod.def) then
        return false, "incompatible_target"
    end
    local previous = mod.sockets[socketIndex]
    if previous == chip then
        return true, nil
    end

    removeFromList(self.pendingRewards, chip)
    if chip.row then
        self:removeItem(chip, false)
    else
        local oldMod, oldIdx = self:findEquippedChip(chip)
        if oldMod and oldIdx then
            oldMod.sockets[oldIdx] = nil
        end
    end

    mod.sockets[socketIndex] = chip
    return true, previous
end

function Inventory:unequipChip(mod, socketIndex)
    if not mod then return nil end
    local chip = mod.sockets[socketIndex]
    if not chip then return nil end
    mod.sockets[socketIndex] = nil
    return chip
end

function Inventory.isWeaponModule(item)
    return item ~= nil and item.kind == "module" and item.def ~= nil and item.def.category == "weapon"
end

function Inventory:countByCategory(category, excludeMod)
    local target = (category == "battery") and "generator" or category
    local count = 0
    for _, mod in ipairs(self.placed) do
        if mod ~= excludeMod and mod.def then
            local cat = (mod.def.category == "battery") and "generator" or mod.def.category
            if cat == target and not (cat == "weapon" and mod.disabled) then
                count = count + 1
            end
        end
    end
    return count
end

function Inventory:activeWeaponCount(excludeMod)
    return self:countByCategory("weapon", excludeMod)
end

function Inventory:totalWeaponCount(excludeItem)
    local count = 0
    for _, mod in ipairs(self.placed) do
        if mod ~= excludeItem and Inventory.isWeaponModule(mod) then
            count = count + 1
        end
    end
    for _, item in ipairs(self.pendingRewards) do
        if item ~= excludeItem and Inventory.isWeaponModule(item) then
            count = count + 1
        end
    end
    return count
end

function Inventory:canDisableWeapon(mod)
    if not Inventory.isWeaponModule(mod) or not mod.row then
        return false, "not_placed_weapon"
    end
    if mod.disabled then
        return true
    end
    if self:activeWeaponCount(mod) < 1 then
        return false, "last_active_weapon"
    end
    return true
end

function Inventory:toggleWeaponEnabled(mod)
    if not Inventory.isWeaponModule(mod) or not mod.row then
        return false, "not_placed_weapon"
    end
    if mod.disabled then
        mod.disabled = false
        return true, true
    end
    local ok, reason = self:canDisableWeapon(mod)
    if not ok then
        return false, reason
    end
    mod.disabled = true
    return true, false
end

function Inventory:canDiscardItem(item)
    if not item then return false, "invalid_item" end
    if Inventory.isWeaponModule(item) and not item.disabled and item.row then
        if self:activeWeaponCount(item) < 1 then
            return false, "last_active_weapon"
        end
    end
    return true
end

function Inventory:discardItem(item)
    local ok, reason = self:canDiscardItem(item)
    if not ok then return false, reason end
    if item.row then
        self:removeItem(item, false)
    else
        self:removePendingItem(item)
    end
    return true
end

function Inventory:getActiveChips(mod)
    local result = {}
    if not mod then return result end
    for i = 1, (mod.maxSockets or 0) do
        if mod.sockets[i] then
            result[#result + 1] = mod.sockets[i]
        end
    end
    return result
end

function Inventory:getPartPeakBatteryCost(mod, feverActive)
    if not mod or not mod.def then return 0 end
    local def = mod.def
    local fireCost = def.baseBatteryCost or 0
    local activationCost = (def.stats and def.stats.boostCost) or 0

    local activeChips = self:getActiveChips(mod)
    local nonFeverBatteryMult = 1.0
    local chipFireAdd = 0
    local boostCostAdd = 0
    local triggerCost = 0
    for _, chip in ipairs(activeChips) do
        local m = chip.def and chip.def.modifiers
        if m then
            if m.nonFeverBatteryMult and not feverActive then
                nonFeverBatteryMult = nonFeverBatteryMult * m.nonFeverBatteryMult
            end
            if m.batteryCost then
                chipFireAdd = chipFireAdd + m.batteryCost
            end
            if m.boostCostAdd then
                boostCostAdd = boostCostAdd + m.boostCostAdd
            end
            if m.hitTriggerBattery then
                triggerCost = math.max(triggerCost, m.hitTriggerBattery)
            end
        end
    end

    if def.weaponIndex and chipFireAdd > 0 then
        fireCost = fireCost + math.floor(chipFireAdd * nonFeverBatteryMult + 0.5)
    end
    if activationCost > 0 then
        activationCost = activationCost + boostCostAdd
    end
    return math.max(fireCost, activationCost, triggerCost)
end

local function newWeaponConfig(def, mod)
    return {
        moduleId = mod and mod.id or nil,
        defId = def and def.id or nil,
        name = def and def.name or nil,
        weaponIndex = def and def.weaponIndex or nil,
        fireMode = def and def.fireMode or nil,
        projectileStyle = def and def.projectileStyle or nil,
        impactStyle = def and def.impactStyle or nil,
        fireSfx = def and def.fireSfx or nil,
        impactSfx = def and def.impactSfx or nil,
        fireInterval = def and def.fireInterval or nil,
        beamDuration = def and def.beamDuration or nil,
        beamTickInterval = def and def.beamTickInterval or nil,
        damage = def and def.damage or nil,
        shotCount = def and def.shotCount or nil,
        burstCount = def and def.burstCount or nil,
        burstInterval = def and def.burstInterval or nil,
        ejectAnglesDeg = def and def.ejectAnglesDeg or nil,
        ejectBend = def and def.ejectBend or nil,
        spreadDeg = def and def.spreadDeg or nil,
        angleInaccuracy = def and def.angleInaccuracy or nil,
        targetScatterRadius = def and def.targetScatterRadius or nil,
        projectileSpeed = def and def.projectileSpeed or nil,
        projectileRange = def and def.projectileRange or nil,
        blastRadius = def and def.blastRadius or nil,
        installed = mod ~= nil,
        extraCount = 0,
        extraSpreadDeg = 0,
        extraBurst = 0,
        damageMult = 1.0,
        cooldownMult = 1.0,
        manualCooldownMult = 1.0,
        batteryCost = (def and def.baseBatteryCost) or 0,
        bounces = 0,
        homing = false,
        homingTurnRate = 0,
        areaMult = 1.0,
        triggerOnDodge = false,
        autoBatteryZero = false,
        triggerOnWrap = false,
        wrapTriggerCooldown = 1.5,
        triggerOnHit = false,
        hitTriggerBattery = 0,
        radialCount = 0,
    }
end

local function applyWeaponChipModifiers(targetCfg, m, chipScale)
    if m.extraCount then
        targetCfg.extraCount = targetCfg.extraCount + math.floor(m.extraCount * chipScale + 0.5)
    end
    if m.extraSpreadDeg then
        targetCfg.extraSpreadDeg = targetCfg.extraSpreadDeg + m.extraSpreadDeg
    end
    if m.extraBurst then
        targetCfg.extraBurst = targetCfg.extraBurst + math.floor(m.extraBurst * chipScale + 0.5)
    end
    if m.damageMult then
        targetCfg.damageMult = targetCfg.damageMult * m.damageMult
    end
    if m.cooldownMult then
        targetCfg.cooldownMult = targetCfg.cooldownMult * m.cooldownMult
    end
    if m.manualCooldownMult then
        targetCfg.manualCooldownMult = targetCfg.manualCooldownMult * m.manualCooldownMult
    end
    if m.bounces then
        targetCfg.bounces = targetCfg.bounces + math.floor(m.bounces * chipScale + 0.5)
    end
    if m.homing then
        targetCfg.homing = true
        targetCfg.homingTurnRate = math.max(targetCfg.homingTurnRate, (m.homingTurnRate or 4.0) * chipScale)
    end
    if m.areaMult then
        local bonus = (m.areaMult - 1.0) * chipScale
        targetCfg.areaMult = targetCfg.areaMult * (1.0 + bonus)
    end
    if m.triggerOnDodge then
        targetCfg.triggerOnDodge = true
        if m.autoBatteryZero then targetCfg.autoBatteryZero = true end
    end
    if m.triggerOnWrap then
        targetCfg.triggerOnWrap = true
        targetCfg.wrapTriggerCooldown = math.min(targetCfg.wrapTriggerCooldown, m.wrapTriggerCooldown or 1.5)
    end
    if m.triggerOnHit then
        targetCfg.triggerOnHit = true
        targetCfg.hitTriggerBattery = math.max(targetCfg.hitTriggerBattery, m.hitTriggerBattery or 15)
        targetCfg.radialCount = math.max(targetCfg.radialCount, math.floor((m.radialCount or 6) * chipScale + 0.5))
    end
end

-- Compute full derived ship + weapon build from the selected chassis, all
-- currently placed modules, and their equipped support chips.
function Inventory:computeBuild(feverActive)
    local chassis = self.chassis or ChassisData.get(self.chassisId)
    local base = (chassis and chassis.baseStats) or {}

    local baseWeight = base.weight or (chassis and chassis.weight) or 0
    local baseShield = base.maxShield or 0
    local baseShieldRegen = base.shieldRegen or 0
    local baseShieldRegenBatteryCost = base.shieldRegenBatteryCost or 0
    local baseShieldRegenDelay = base.shieldRegenDelay or 2.0
    local baseArmor = base.maxArmor or 0
    local baseHull = base.maxHull or 0
    local baseBattery = base.maxBattery or 0
    local baseRecharge = base.batteryRecharge or 0
    local baseThrust = base.thrust or 0
    local baseBoostThrust = base.boostThrust or 0
    local baseBoostCost = base.boostCost or 0
    local baseThrustBatteryCost = base.thrustBatteryCost or 0
    local baseWrapBonusSpeed = base.wrapBonusSpeed or 0

    local build = {
        fromChassis = true,
        chassisId = chassis and chassis.id or self.chassisId,
        chassis = chassis,
        specialEffect = chassis and chassis.specialEffect or nil,

        -- Weight breakdown (chassis + all mounted modules)
        chassisWeight = baseWeight,
        moduleWeight = 0,
        totalWeight = baseWeight,

        -- Absolute derived chassis + module stats
        maxShield = baseShield,
        shieldRegen = baseShieldRegen,
        shieldRegenBatteryCost = baseShieldRegenBatteryCost,
        shieldRegenDelay = baseShieldRegenDelay,
        maxArmor = baseArmor,
        maxHull = baseHull,
        maxBattery = baseBattery,
        batteryRecharge = baseRecharge,
        maxSpeed = 0,
        thrust = baseThrust,
        boostThrust = baseBoostThrust,
        boostSpeed = 0,
        boostCost = baseBoostCost,
        thrustBatteryCost = baseThrustBatteryCost,
        wrapBonusSpeed = baseWrapBonusSpeed,
        turnSpeed = base.turnSpeed or 4.5,
        brake = base.brake or 2.5,

        -- Additive bonus view (module contribution over chassis base)
        maxShieldBonus = 0,
        shieldRegenBonus = 0,
        shieldRegenBatteryCostBonus = 0,
        maxArmorBonus = 0,
        maxBatteryBonus = 0,
        batteryRechargeBonus = 0,
        batteryRechargeMult = 1.0,
        thrustBonus = 0,
        boostThrustBonus = 0,
        boostCostBase = 0,
        boostCostBonus = 0,
        thrustBatteryCostBonus = 0,
        wrapBonusSpeedAdd = 0,
        wrapSpeedMult = 1.0,
        wrapInvulnDuration = 0,

        maxWeaponBatteryCost = 0,
        maxWeaponBatteryName = nil,
        maxSingleActionBatteryCost = 0,
        maxPartBatteryCost = 0,
        maxPartBatteryName = nil,

        noShield = false,
        scoreMultiplier = 1.0,
        onDodgeBattery = 0,
        shockwaveOnHit = false,
        shockwaveRadius = 0,
        shockwaveCooldown = 4.0,
        weapons = {},
        weaponModules = {},
    }

    for w = 1, 3 do
        local cfg = newWeaponConfig(nil, nil)
        cfg.weaponIndex = w
        build.weapons[w] = cfg
    end

    local categoryCounts = {}
    local categoryHasBatteryUsage = {
        weapon = true,
        thruster = true,
    }
    for _, mod in ipairs(self.placed) do
        local def = mod.def
        local isDisabledWeapon = Inventory.isWeaponModule(mod) and mod.disabled == true
        if not isDisabledWeapon and def and def.category then
            local cat = canonicalCategory(def.category)
            categoryCounts[cat] = (categoryCounts[cat] or 0) + 1
            local s = def.stats
            if (def.baseBatteryCost or 0) > 0
                or (s and ((s.boostCost or 0) > 0 or (s.thrustBatteryCost or 0) > 0 or (s.shieldRegenBatteryCost or 0) > 0)) then
                categoryHasBatteryUsage[cat] = true
            end
        end
    end

    build.categoryCounts = categoryCounts
    build.categoryPenalties = {}
    build.duplicateCautions = {}

    for _, mod in ipairs(self.placed) do
        local def = mod.def
        local isDisabledWeapon = Inventory.isWeaponModule(mod) and mod.disabled == true
        if def then
            build.moduleWeight = build.moduleWeight + (def.weight or (def.stats and def.stats.weight) or 0)
        end
        if not isDisabledWeapon and def then
            local cat = canonicalCategory(def.category)
            local catMult = Inventory.getDuplicateBatteryPenalty(cat, categoryCounts[cat])
            local _, catAddPct = Inventory.getDuplicateBatteryPenalty(cat, categoryCounts[cat])

            local stats = def.stats
            if stats then
                build.maxShieldBonus = build.maxShieldBonus + (stats.maxShield or 0)
                build.shieldRegenBonus = build.shieldRegenBonus + (stats.shieldRegen or 0)
                build.shieldRegenBatteryCostBonus = build.shieldRegenBatteryCostBonus + (stats.shieldRegenBatteryCost or 0) * catMult
                if stats.shieldRegenDelay then
                    build.shieldRegenDelay = stats.shieldRegenDelay
                end
                build.maxArmorBonus = build.maxArmorBonus + (stats.maxArmor or 0)
                build.maxBatteryBonus = build.maxBatteryBonus + (stats.maxBattery or 0)
                build.batteryRechargeBonus = build.batteryRechargeBonus + (stats.batteryRecharge or 0)
                build.thrustBonus = build.thrustBonus + (stats.thrust or 0)
                build.boostThrustBonus = build.boostThrustBonus + (stats.boostThrust or 0)
                build.boostCostBase = build.boostCostBase + (stats.boostCost or 0) * catMult
                build.thrustBatteryCostBonus = build.thrustBatteryCostBonus + (stats.thrustBatteryCost or 0) * catMult
                build.wrapBonusSpeedAdd = build.wrapBonusSpeedAdd + (stats.wrapBonusSpeed or 0)
            end

            local activeChips = self:getActiveChips(mod)
            local chipScale = 1.0
            local nonFeverBatteryMult = 1.0
            for _, chip in ipairs(activeChips) do
                local m = chip.def.modifiers
                if m.feverChipMult and feverActive then
                    chipScale = chipScale * m.feverChipMult
                end
                if m.nonFeverBatteryMult and not feverActive then
                    nonFeverBatteryMult = nonFeverBatteryMult * m.nonFeverBatteryMult
                end
            end

            local wCfg = def.weaponIndex and build.weapons[def.weaponIndex] or nil
            local mCfg = nil
            if wCfg then
                wCfg.installed = true
                wCfg.fireMode = wCfg.fireMode or def.fireMode
                wCfg.projectileStyle = wCfg.projectileStyle or def.projectileStyle
                wCfg.impactStyle = wCfg.impactStyle or def.impactStyle
                wCfg.fireSfx = wCfg.fireSfx or def.fireSfx
                wCfg.impactSfx = wCfg.impactSfx or def.impactSfx
                wCfg.fireInterval = wCfg.fireInterval or def.fireInterval
                if wCfg.beamDuration == nil then wCfg.beamDuration = def.beamDuration end
                if wCfg.beamTickInterval == nil then wCfg.beamTickInterval = def.beamTickInterval end
                wCfg.damage = wCfg.damage or def.damage
                wCfg.shotCount = wCfg.shotCount or def.shotCount
                wCfg.burstCount = wCfg.burstCount or def.burstCount
                wCfg.burstInterval = wCfg.burstInterval or def.burstInterval
                wCfg.ejectAnglesDeg = wCfg.ejectAnglesDeg or def.ejectAnglesDeg
                wCfg.ejectBend = wCfg.ejectBend or def.ejectBend
                wCfg.spreadDeg = wCfg.spreadDeg or def.spreadDeg
                if wCfg.angleInaccuracy == nil then wCfg.angleInaccuracy = def.angleInaccuracy end
                if wCfg.targetScatterRadius == nil then wCfg.targetScatterRadius = def.targetScatterRadius end
                wCfg.projectileSpeed = wCfg.projectileSpeed or def.projectileSpeed
                wCfg.projectileRange = wCfg.projectileRange or def.projectileRange
                wCfg.blastRadius = wCfg.blastRadius or def.blastRadius
                mCfg = newWeaponConfig(def, mod)
                build.weaponModules[#build.weaponModules + 1] = mCfg
            end

            local moduleBatteryAdd = 0
            for _, chip in ipairs(activeChips) do
                local m = chip.def.modifiers
                if m.noShield then build.noShield = true end
                if m.scoreMult then
                    local bonus = (m.scoreMult - 1.0) * chipScale
                    build.scoreMultiplier = build.scoreMultiplier * (1.0 + bonus)
                end
                if m.onDodgeBattery then
                    build.onDodgeBattery = build.onDodgeBattery + math.floor(m.onDodgeBattery * chipScale + 0.5)
                end
                if m.rechargeMult then
                    build.batteryRechargeMult = build.batteryRechargeMult * m.rechargeMult
                end
                if m.shockwaveOnHit then
                    build.shockwaveOnHit = true
                    build.shockwaveRadius = math.max(build.shockwaveRadius, (m.shockwaveRadius or 180) * chipScale)
                    build.shockwaveCooldown = math.min(build.shockwaveCooldown, m.shockwaveCooldown or 4.0)
                end
                if m.wrapSpeedMult then
                    local bonus = (m.wrapSpeedMult - 1.0) * chipScale
                    build.wrapSpeedMult = build.wrapSpeedMult * (1.0 + bonus)
                end
                if m.wrapInvuln then
                    build.wrapInvulnDuration = math.max(build.wrapInvulnDuration, m.wrapInvuln * chipScale)
                end
                if m.boostCostAdd then
                    categoryHasBatteryUsage[cat] = true
                    build.boostCostBonus = build.boostCostBonus + m.boostCostAdd * catMult
                end

                if wCfg and mCfg then
                    applyWeaponChipModifiers(wCfg, m, chipScale)
                    applyWeaponChipModifiers(mCfg, m, chipScale)
                    if m.batteryCost then
                        moduleBatteryAdd = moduleBatteryAdd + m.batteryCost
                    end
                end
            end

            if wCfg and mCfg then
                local scaledBatteryAdd = moduleBatteryAdd > 0
                    and math.floor(moduleBatteryAdd * nonFeverBatteryMult + 0.5)
                    or 0
                local rawWeaponCost = (def.baseBatteryCost or 0) + scaledBatteryAdd
                mCfg.baseBatteryCostBeforePenalty = rawWeaponCost
                mCfg.batteryPenaltyPct = catAddPct
                mCfg.batteryCost = math.floor(rawWeaponCost * catMult + 0.5)
                if mCfg.triggerOnHit and (mCfg.hitTriggerBattery or 0) > 0 then
                    mCfg.hitTriggerBattery = math.floor(mCfg.hitTriggerBattery * catMult + 0.5)
                    wCfg.hitTriggerBattery = math.max(wCfg.hitTriggerBattery or 0, mCfg.hitTriggerBattery)
                end
                wCfg.batteryCost = wCfg.batteryCost + mCfg.batteryCost
            end

            if mCfg then
                local shotCost = math.max(mCfg.batteryCost or 0, mCfg.triggerOnHit and (mCfg.hitTriggerBattery or 0) or 0)
                if shotCost > build.maxWeaponBatteryCost then
                    build.maxWeaponBatteryCost = shotCost
                    build.maxWeaponBatteryName = def.name
                end
            end
        end
    end

    for _, catDef in ipairs(ModulesData.categories) do
        local cat = canonicalCategory(catDef.id)
        local count = categoryCounts[cat] or 0
        if cat ~= "generator" and count >= 2 and categoryHasBatteryUsage[cat] then
            local mult, addPct = Inventory.getDuplicateBatteryPenalty(cat, count)
            local label = ModulesData.getCategoryLabel(cat)
            build.categoryPenalties[cat] = {
                category = cat,
                label = label,
                count = count,
                addPct = addPct,
                mult = mult,
            }
            build.duplicateCautions[#build.duplicateCautions + 1] = {
                code = "duplicate_category_" .. cat,
                category = cat,
                label = label,
                count = count,
                addPct = addPct,
                mult = mult,
                message = string.format("%s %d개 장착: 각 모듈 배터리 사용량 +%d%%", label, count, addPct),
            }
        end
    end

    build.maxShield = build.noShield and 0 or (baseShield + build.maxShieldBonus)
    build.shieldRegen = build.noShield and 0 or (baseShieldRegen + build.shieldRegenBonus)
    build.shieldRegenBatteryCost = build.noShield and 0 or (baseShieldRegenBatteryCost + build.shieldRegenBatteryCostBonus)
    build.maxArmor = baseArmor + build.maxArmorBonus
    build.maxBattery = baseBattery + build.maxBatteryBonus
    build.batteryRecharge = (baseRecharge + build.batteryRechargeBonus) * build.batteryRechargeMult
    build.totalWeight = baseWeight + build.moduleWeight
    build.thrust = baseThrust + build.thrustBonus
    build.boostThrust = baseBoostThrust + build.boostThrustBonus
    build.maxSpeed = math.max(0, build.thrust - build.totalWeight)
    build.boostSpeed = math.max(0, build.boostThrust - build.totalWeight)
    build.boostCost = math.floor((baseBoostCost + build.boostCostBase) + 0.5)
    if build.boostCost > 0 then
        build.boostCost = math.max(5, math.floor(build.boostCost + build.boostCostBonus + 0.5))
    end
    build.thrustBatteryCost = baseThrustBatteryCost + build.thrustBatteryCostBonus
    build.wrapBonusSpeed = (baseWrapBonusSpeed + build.wrapBonusSpeedAdd) * build.wrapSpeedMult
    build.maxSingleActionBatteryCost = math.max(build.maxWeaponBatteryCost, build.boostCost or 0)
    if build.boostCost > build.maxWeaponBatteryCost then
        build.maxPartBatteryCost = build.boostCost
        build.maxPartBatteryName = "부스터"
    else
        build.maxPartBatteryCost = build.maxWeaponBatteryCost
        build.maxPartBatteryName = build.maxWeaponBatteryName
    end

    if chassis and chassis.applySpecialEffect then
        chassis.applySpecialEffect(build, self)
    end

    return build
end

function Inventory:validateLoadout(feverActive)
    local build = self:computeBuild(feverActive)
    local warnings = {}
    local weaponCount = self:countByCategory("weapon")
    local thrusterCount = self:countByCategory("thruster")
    local generatorCount = self:countByCategory("generator")

    if self.chassis and self.chassis.locked then
        warnings[#warnings + 1] = {
            code = "locked_chassis",
            message = "해금되지 않은 섀시입니다.",
        }
    end
    if weaponCount < 1 then
        warnings[#warnings + 1] = {
            code = "missing_weapon",
            message = "무기 모듈을 최소 1개 이상 장착해야 합니다.",
        }
    end
    if thrusterCount < 1 then
        warnings[#warnings + 1] = {
            code = "missing_thruster",
            message = "추진기 모듈을 최소 1개 이상 장착해야 합니다.",
        }
    end
    if generatorCount < 1 then
        warnings[#warnings + 1] = {
            code = "missing_generator",
            message = "제너레이터 모듈을 최소 1개 이상 장착해야 합니다.",
        }
    end
    if thrusterCount >= 1 and (build.maxSpeed or 0) <= 0 then
        warnings[#warnings + 1] = {
            code = "overweight",
            message = string.format("기체 총 무게(%d)가 추진력(%d) 이상이어서 이동할 수 없습니다.",
                build.totalWeight or 0, build.thrust or 0),
        }
    end

    if (build.maxWeaponBatteryCost or 0) > build.maxBattery then
        warnings[#warnings + 1] = {
            code = "weapon_battery_exceeded",
            message = string.format("%s의 1회 발사 배터리(%d)가 배터리 총량(%d)을 초과했습니다.",
                build.maxWeaponBatteryName or "무기", build.maxWeaponBatteryCost, build.maxBattery),
        }
    end
    if (build.boostCost or 0) > build.maxBattery then
        warnings[#warnings + 1] = {
            code = "boost_battery_exceeded",
            message = string.format("부스트 1회 소모(%d)가 배터리 총량(%d)을 초과했습니다.",
                build.boostCost, build.maxBattery),
        }
    end

    local summary = {
        build = build,
        weaponCount = weaponCount,
        thrusterCount = thrusterCount,
        generatorCount = generatorCount,
        totalWeight = build.totalWeight,
        maxBattery = build.maxBattery,
        batteryRecharge = build.batteryRecharge,
        shieldRegen = build.shieldRegen,
        shieldRegenBatteryCost = build.shieldRegenBatteryCost,
        shieldRegenDelay = build.shieldRegenDelay,
        boostCost = build.boostCost,
        thrustBatteryCost = build.thrustBatteryCost,
        maxWeaponBatteryCost = build.maxWeaponBatteryCost,
        maxWeaponBatteryName = build.maxWeaponBatteryName,
        maxSingleActionBatteryCost = build.maxSingleActionBatteryCost,
        maxPartBatteryCost = build.maxPartBatteryCost,
        maxPartBatteryName = build.maxPartBatteryName,
        cautions = build.duplicateCautions or {},
        categoryPenalties = build.categoryPenalties or {},
    }
    return #warnings == 0, warnings, summary
end

function Inventory:clone()
    local copy = Inventory.new({
        chassisId = self.chassisId,
        rotationUnlocked = self.rotationUnlocked,
    })
    for r = 1, self.rows do
        for c = 1, self.cols do
            copy.unlocked[r][c] = self.unlocked[r][c] == true
        end
    end

    for _, mod in ipairs(self.placed) do
        local newMod = copy:createModule(mod.defId, { rarity = mod.rarity })
        newMod.disabled = mod.disabled == true
        copy:placeItem(newMod, mod.row, mod.col, mod.rotation)
        for i = 1, (mod.maxSockets or 0) do
            local chip = mod.sockets[i]
            if chip then
                local newChip = copy:createChip(chip.defId, { rarity = chip.rarity })
                copy:equipChip(newMod, i, newChip)
            end
        end
    end

    for _, chip in ipairs(self.placedChips) do
        local newChip = copy:createChip(chip.defId, { rarity = chip.rarity })
        copy:placeItem(newChip, chip.row, chip.col, chip.rotation)
    end

    for _, item in ipairs(self.pendingRewards) do
        if item.kind == "chip" then
            copy:addPendingChip(item.defId, { rarity = item.rarity })
        else
            copy:addPendingModule(item.defId, { rarity = item.rarity })
        end
    end

    return copy
end

-- Create a default valid starter loadout on the Striker MK-I 5x3 triangle grid:
-- projectile (1x2) at (1,3), battery/generator (1x2) at (2,2), thruster (1x1) at (3,3).
function Inventory.newStarter(opts)
    local inv = Inventory.new({
        chassisId = opts and opts.chassisId or ChassisData.DEFAULT_ID,
        metaPoints = opts and opts.metaPoints or 0,
        expandCost = opts and opts.expandCost or 100,
    })
    if not (inv.chassis and inv.chassis.locked) then
        local proj = inv:createModule("projectile")
        inv:placeModule(proj, 1, 3, 0)
        local gen = inv:createModule("battery")
        inv:placeModule(gen, 2, 2, 0)
        local thr = inv:createModule("thruster")
        inv:placeModule(thr, 3, 3, 0)
    end
    return inv
end

function Inventory:serializeLoadout()
    local lines = {
        "chassis=" .. tostring(self.chassisId or ChassisData.DEFAULT_ID),
    }
    for idx, mod in ipairs(self.placed) do
        lines[#lines + 1] = string.format("mod=%s,%d,%d,%d,%d",
            mod.defId, mod.row or 1, mod.col or 1, mod.rotation or 0, mod.disabled and 1 or 0)
        for s = 1, (mod.maxSockets or 0) do
            local chip = mod.sockets[s]
            if chip then
                lines[#lines + 1] = string.format("chip=%d,%d,%s", idx, s, chip.defId)
            end
        end
    end
    for _, chip in ipairs(self.placedChips) do
        lines[#lines + 1] = string.format("gridchip=%s,%d,%d,%d",
            chip.defId, chip.row or 1, chip.col or 1, chip.rotation or 0)
    end
    return table.concat(lines, "\n")
end

function Inventory.deserializeLoadout(str)
    if type(str) ~= "string" or str == "" then
        return nil, "empty"
    end
    local chassisId = str:match("chassis=([%w_%-]+)")
    local chassis = chassisId and ChassisData.byId[chassisId] or nil
    if not chassis or chassis.locked then
        return nil, "invalid_chassis"
    end

    local inv = Inventory.new({ chassisId = chassis.id })
    local placedMods = {}

    for line in str:gmatch("[^\r\n]+") do
        local defId, rStr, cStr, rotStr, disStr = line:match("^mod=([%w_%-]+),(%d+),(%d+),(%d+),(%d+)$")
        if defId then
            if not ModulesData.get(defId) then return nil, "unknown_module" end
            local mod = inv:createModule(defId)
            mod.disabled = (tonumber(disStr) == 1)
            local ok, reason = inv:placeItem(mod, tonumber(rStr), tonumber(cStr), tonumber(rotStr))
            if not ok then return nil, reason or "place_failed" end
            placedMods[#placedMods + 1] = mod
        else
            local modIdxStr, sockStr, chipId = line:match("^chip=(%d+),(%d+),([%w_%-]+)$")
            if modIdxStr then
                local host = placedMods[tonumber(modIdxStr)]
                if not host or not ChipsData.get(chipId) then return nil, "invalid_chip" end
                local chip = inv:createChip(chipId)
                local ok, reason = inv:equipChip(host, tonumber(sockStr), chip)
                if not ok then return nil, reason or "equip_failed" end
            else
                local gChipId, grStr, gcStr, gRotStr = line:match("^gridchip=([%w_%-]+),(%d+),(%d+),(%d+)$")
                if gChipId then
                    if not ChipsData.get(gChipId) then return nil, "unknown_chip" end
                    local chip = inv:createChip(gChipId)
                    local ok, reason = inv:placeItem(chip, tonumber(grStr), tonumber(gcStr), tonumber(gRotStr))
                    if not ok then return nil, reason or "chip_place_failed" end
                end
            end
        end
    end

    local valid = inv:validateLoadout(false)
    if not valid then
        return nil, "invalid_loadout"
    end
    return inv
end

function Inventory:serializeUnlockedCells()
    local parts = {}
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self:isUnlocked(r, c) then
                parts[#parts + 1] = cellKey(r, c)
            end
        end
    end
    return table.concat(parts, ";")
end

function Inventory:loadUnlockedCells(str)
    if not str or str == "" then return end
    for rStr, cStr in string.gmatch(str, "(%d+),(%d+)") do
        local r, c = tonumber(rStr), tonumber(cStr)
        if r and c and self:isValidCell(r, c) then
            self.unlocked[r][c] = true
        end
    end
end

return Inventory
