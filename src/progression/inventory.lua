-- 4x4 -> 6x6 Diamond Grid Inventory.
-- Pure Lua logic (no LÖVE graphics dependency) so it can be unit-tested cleanly.
-- No permanent separate stash exists for modules or support chips: every item
-- has a grid shape and must fit inside the main diamond inventory (or a module
-- socket for support chips). Post-stage rewards sit in a temporary pending tray
-- and are discarded if not placed into the main inventory before the next stage.

local ModulesData = require("src.data.modules_data")
local ChipsData = require("src.data.chips_data")

local Inventory = {}
Inventory.__index = Inventory

Inventory.GRID_SIZE = 6
Inventory.CENTER = 3.5
Inventory.START_RADIUS = 2 -- 4x4 diamond (12 cells: 2+4+4+2)
Inventory.MAX_RADIUS = 3   -- 6x6 diamond (24 cells: 2+4+6+6+4+2)

local function cellKey(r, c)
    return r .. "," .. c
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

function Inventory.isInDiamond(r, c, radius)
    if r < 1 or r > Inventory.GRID_SIZE or c < 1 or c > Inventory.GRID_SIZE then
        return false
    end
    local dist = math.abs(r - Inventory.CENTER) + math.abs(c - Inventory.CENTER)
    return dist <= (radius or Inventory.MAX_RADIUS) + 1e-6
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
    local self = setmetatable({
        gridSize = Inventory.GRID_SIZE,
        center = Inventory.CENTER,
        unlocked = {},
        cells = {},          -- cells[r][c] = placed module or placed chip or nil
        placed = {},         -- list of placed moduleInstances
        placedChips = {},    -- list of unequipped chipInstances stored directly on grid cells
        pendingRewards = {}, -- temporary post-stage reward items (discarded if not placed)
        nextId = 1,
        metaPoints = opts.metaPoints or 0,
        expandCost = opts.expandCost or 100,
    }, Inventory)

    for r = 1, self.gridSize do
        self.cells[r] = {}
        self.unlocked[r] = {}
        for c = 1, self.gridSize do
            self.unlocked[r][c] = Inventory.isInDiamond(r, c, Inventory.START_RADIUS)
        end
    end

    if opts.unlockedCells then
        for _, coord in ipairs(opts.unlockedCells) do
            local r, c = coord[1], coord[2]
            if Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then
                self.unlocked[r][c] = true
            end
        end
    end

    return self
end

function Inventory:isUnlocked(r, c)
    if not self.unlocked[r] then return false end
    return self.unlocked[r][c] == true
end

function Inventory:unlockedCellCount()
    local count = 0
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
            if self.unlocked[r][c] then count = count + 1 end
        end
    end
    return count
end

function Inventory:maxCellCount()
    local count = 0
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
            if Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then count = count + 1 end
        end
    end
    return count
end

-- Permanent expansion: can unlock any locked cell inside the 6x6 diamond
-- that is orthogonally adjacent to an already-unlocked cell.
function Inventory:canUnlockCell(r, c)
    if not Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then
        return false, "outside_diamond"
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
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
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

function Inventory:createModule(defId)
    local def = ModulesData.get(defId)
    assert(def, "Unknown module id: " .. tostring(defId))
    local _, w, h = Inventory.getShapeCells(def, 0)
    local mod = {
        kind = "module",
        id = self.nextId,
        defId = def.id,
        def = def,
        w = w,
        h = h,
        rotation = 0,
        rotated = false,
        row = nil,
        col = nil,
        maxSockets = def.maxSockets,
        sockets = {}, -- sockets[i] = chipInstance or nil
    }
    self.nextId = self.nextId + 1
    return mod
end

function Inventory:createChip(chipId)
    local def = ChipsData.get(chipId)
    assert(def, "Unknown chip id: " .. tostring(chipId))
    local _, w, h = Inventory.getShapeCells(def, 0)
    local chip = {
        kind = "chip",
        id = self.nextId,
        defId = def.id,
        def = def,
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

-- Post-stage temporary reward queue (not a permanent stash).
-- Anything remaining here when advancing to the next stage is discarded.
function Inventory:addPendingModule(defId, opts)
    local mod = type(defId) == "table" and defId or self:createModule(defId, opts)
    self.pendingRewards[#self.pendingRewards + 1] = mod
    return mod
end

function Inventory:addPendingChip(chipId)
    local chip = type(chipId) == "table" and chipId or self:createChip(chipId)
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
    local shapeCells = Inventory.getShapeCells(item, rotation)
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
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
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

-- Compute full derived ship + weapon build from all currently placed modules
-- and their equipped support chips.
function Inventory:computeBuild(feverActive)
    local build = {
        -- Ship additive bonuses on top of Ship base stats (100/100/3/100)
        maxShieldBonus = 0,
        maxArmorBonus = 0,
        maxBatteryBonus = 0,
        batteryRechargeBonus = 0,
        batteryRechargeMult = 1.0,
        maxSpeedBonus = 0,
        boostSpeedBonus = 0,
        boostCostBonus = 0,
        wrapBonusSpeedAdd = 0,
        wrapSpeedMult = 1.0,
        wrapInvulnDuration = 0,
        noShield = false,
        scoreMultiplier = 1.0,
        onDodgeBattery = 0,
        shockwaveOnHit = false,
        shockwaveRadius = 0,
        shockwaveCooldown = 4.0,
        weapons = {},
    }

    for w = 1, 3 do
        build.weapons[w] = {
            installed = false,
            extraCount = 0,
            extraSpreadDeg = 0,
            extraBurst = 0,
            damageMult = 1.0,
            cooldownMult = 1.0,
            manualCooldownMult = 1.0,
            batteryCost = 0,
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

    for _, mod in ipairs(self.placed) do
        local def = mod.def
        local stats = def.stats
        if stats then
            build.maxShieldBonus = build.maxShieldBonus + (stats.maxShield or 0)
            build.maxArmorBonus = build.maxArmorBonus + (stats.maxArmor or 0)
            build.maxBatteryBonus = build.maxBatteryBonus + (stats.maxBattery or 0)
            build.batteryRechargeBonus = build.batteryRechargeBonus + (stats.batteryRecharge or 0)
            build.maxSpeedBonus = build.maxSpeedBonus + (stats.maxSpeed or 0)
            build.boostSpeedBonus = build.boostSpeedBonus + (stats.boostSpeed or 0)
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
        if wCfg then
            wCfg.installed = true
            wCfg.batteryCost = wCfg.batteryCost + (def.baseBatteryCost or 0)
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
                build.boostCostBonus = build.boostCostBonus + m.boostCostAdd
            end

            if wCfg then
                if m.extraCount then
                    wCfg.extraCount = wCfg.extraCount + math.floor(m.extraCount * chipScale + 0.5)
                end
                if m.extraSpreadDeg then
                    wCfg.extraSpreadDeg = wCfg.extraSpreadDeg + m.extraSpreadDeg
                end
                if m.extraBurst then
                    wCfg.extraBurst = wCfg.extraBurst + math.floor(m.extraBurst * chipScale + 0.5)
                end
                if m.damageMult then
                    wCfg.damageMult = wCfg.damageMult * m.damageMult
                end
                if m.cooldownMult then
                    wCfg.cooldownMult = wCfg.cooldownMult * m.cooldownMult
                end
                if m.manualCooldownMult then
                    wCfg.manualCooldownMult = wCfg.manualCooldownMult * m.manualCooldownMult
                end
                if m.batteryCost then
                    moduleBatteryAdd = moduleBatteryAdd + m.batteryCost
                end
                if m.bounces then
                    wCfg.bounces = wCfg.bounces + math.floor(m.bounces * chipScale + 0.5)
                end
                if m.homing then
                    wCfg.homing = true
                    wCfg.homingTurnRate = math.max(wCfg.homingTurnRate, (m.homingTurnRate or 4.0) * chipScale)
                end
                if m.areaMult then
                    local bonus = (m.areaMult - 1.0) * chipScale
                    wCfg.areaMult = wCfg.areaMult * (1.0 + bonus)
                end
                if m.triggerOnDodge then
                    wCfg.triggerOnDodge = true
                    if m.autoBatteryZero then wCfg.autoBatteryZero = true end
                end
                if m.triggerOnWrap then
                    wCfg.triggerOnWrap = true
                    wCfg.wrapTriggerCooldown = math.min(wCfg.wrapTriggerCooldown, m.wrapTriggerCooldown or 1.5)
                end
                if m.triggerOnHit then
                    wCfg.triggerOnHit = true
                    wCfg.hitTriggerBattery = math.max(wCfg.hitTriggerBattery, m.hitTriggerBattery or 15)
                    wCfg.radialCount = math.max(wCfg.radialCount, math.floor((m.radialCount or 6) * chipScale + 0.5))
                end
            end
        end

        if wCfg and moduleBatteryAdd > 0 then
            wCfg.batteryCost = wCfg.batteryCost + math.floor(moduleBatteryAdd * nonFeverBatteryMult + 0.5)
        end
    end

    return build
end

-- Create a default starter inventory on the 4x4 diamond (expandable to 6x6)
-- with the baseline projectile turret installed and NO separate stash.
function Inventory.newStarter(opts)
    local inv = Inventory.new(opts)
    local proj = inv:createModule("projectile")
    inv:placeModule(proj, 3, 3, 0)
    return inv
end

function Inventory:serializeUnlockedCells()
    local parts = {}
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
            if self.unlocked[r][c] then
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
        if r and c and Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then
            self.unlocked[r][c] = true
        end
    end
end

return Inventory
