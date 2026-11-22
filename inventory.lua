-- 3x3 -> 5x5 Diamond Grid Inventory with Core Socket & Link Activation.
-- Pure Lua logic (no LÖVE graphics dependency) so it can be unit-tested cleanly.

local ModulesData = require("modules_data")
local ChipsData = require("chips_data")

local Inventory = {}
Inventory.__index = Inventory

Inventory.GRID_SIZE = 5
Inventory.CENTER = 3
Inventory.START_RADIUS = 1 -- 3x3 diamond (5 cells)
Inventory.MAX_RADIUS = 2   -- 5x5 diamond (13 cells)

local function cellKey(r, c)
    return r .. "," .. c
end

local function edgeKey(a, b)
    if a > b then a, b = b, a end
    return a .. "-" .. b
end

function Inventory.isInDiamond(r, c, radius)
    if r < 1 or r > Inventory.GRID_SIZE or c < 1 or c > Inventory.GRID_SIZE then
        return false
    end
    local dist = math.abs(r - Inventory.CENTER) + math.abs(c - Inventory.CENTER)
    return dist <= (radius or Inventory.MAX_RADIUS)
end

function Inventory.new(opts)
    opts = opts or {}
    local self = setmetatable({
        gridSize = Inventory.GRID_SIZE,
        center = Inventory.CENTER,
        unlocked = {},
        cells = {},        -- cells[r][c] = moduleInstance or nil
        placed = {},       -- list of placed moduleInstances
        stashModules = {}, -- unplaced moduleInstances
        stashChips = {},   -- unequipped chipInstances
        nextId = 1,
        metaPoints = opts.metaPoints or 0,
        expandCost = opts.expandCost or 100,
        linkCost = opts.linkCost or 50,
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

-- Permanent expansion: can unlock any locked cell inside the 5x5 diamond
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

function Inventory:createModule(defId, opts)
    local def = ModulesData.get(defId)
    assert(def, "Unknown module id: " .. tostring(defId))
    opts = opts or {}
    local links = {}
    local initialLinks = opts.links or def.defaultLinks or {}
    for _, edge in ipairs(initialLinks) do
        links[edgeKey(edge[1], edge[2])] = { edge[1], edge[2] }
    end
    local mod = {
        id = self.nextId,
        defId = def.id,
        def = def,
        w = def.w,
        h = def.h,
        rotated = false,
        row = nil,
        col = nil,
        maxSockets = def.maxSockets,
        sockets = {}, -- sockets[i] = chipInstance or nil
        links = links,
    }
    self.nextId = self.nextId + 1
    return mod
end

function Inventory:createChip(chipId)
    local def = ChipsData.get(chipId)
    assert(def, "Unknown chip id: " .. tostring(chipId))
    local chip = {
        id = self.nextId,
        defId = def.id,
        def = def,
    }
    self.nextId = self.nextId + 1
    return chip
end

function Inventory:addModuleToStash(defId, opts)
    local mod = type(defId) == "table" and defId or self:createModule(defId, opts)
    self.stashModules[#self.stashModules + 1] = mod
    return mod
end

function Inventory:addChipToStash(chipId)
    local chip = type(chipId) == "table" and chipId or self:createChip(chipId)
    self.stashChips[#self.stashChips + 1] = chip
    return chip
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

function Inventory:moduleDimensions(mod, rotated)
    local rot = rotated
    if rot == nil then rot = mod.rotated end
    if rot then
        return mod.def.h, mod.def.w
    end
    return mod.def.w, mod.def.h
end

function Inventory:canPlace(mod, row, col, rotated)
    if not mod then return false, "invalid_module" end
    local w, h = self:moduleDimensions(mod, rotated)
    for dr = 0, h - 1 do
        for dc = 0, w - 1 do
            local r, c = row + dr, col + dc
            if not self:isUnlocked(r, c) then
                return false, "locked_or_out_of_bounds"
            end
            local occupant = self.cells[r][c]
            if occupant and occupant ~= mod then
                return false, "occupied"
            end
        end
    end
    return true
end

function Inventory:removeModule(mod, toStash)
    if not mod or not mod.row then return false end
    for r = 1, self.gridSize do
        for c = 1, self.gridSize do
            if self.cells[r][c] == mod then
                self.cells[r][c] = nil
            end
        end
    end
    mod.row, mod.col = nil, nil
    removeFromList(self.placed, mod)
    if toStash ~= false then
        self.stashModules[#self.stashModules + 1] = mod
    end
    return true
end

function Inventory:placeModule(mod, row, col, rotated)
    local rot = rotated
    if rot == nil then rot = mod.rotated end
    local ok, reason = self:canPlace(mod, row, col, rot)
    if not ok then return false, reason end

    if mod.row then
        self:removeModule(mod, false)
    else
        removeFromList(self.stashModules, mod)
    end

    local w, h = self:moduleDimensions(mod, rot)
    mod.rotated = rot
    mod.w, mod.h = w, h
    mod.row, mod.col = row, col
    for dr = 0, h - 1 do
        for dc = 0, w - 1 do
            self.cells[row + dr][col + dc] = mod
        end
    end
    self.placed[#self.placed + 1] = mod
    return true
end

function Inventory:rotateModule(mod)
    if not mod then return false, "invalid_module" end
    if not mod.row then
        mod.rotated = not mod.rotated
        mod.w, mod.h = self:moduleDimensions(mod, mod.rotated)
        return true
    end
    return self:placeModule(mod, mod.row, mod.col, not mod.rotated)
end

-- Core Socket & Link Activation (BFS starting from Core Socket 1)
function Inventory:getActiveSockets(mod)
    local active = {}
    if not mod or mod.maxSockets < 1 then return active end
    local adj = {}
    for i = 1, mod.maxSockets do adj[i] = {} end
    for _, edge in pairs(mod.links) do
        local a, b = edge[1], edge[2]
        if adj[a] and adj[b] then
            adj[a][#adj[a] + 1] = b
            adj[b][#adj[b] + 1] = a
        end
    end
    local queue = { 1 }
    active[1] = true
    local head = 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        for _, nxt in ipairs(adj[cur]) do
            if not active[nxt] then
                active[nxt] = true
                queue[#queue + 1] = nxt
            end
        end
    end
    return active
end

function Inventory:activeSocketCount(mod)
    local active = self:getActiveSockets(mod)
    local count = 0
    for i = 1, mod.maxSockets do
        if active[i] then count = count + 1 end
    end
    return count
end

function Inventory:hasLink(mod, a, b)
    return mod.links[edgeKey(a, b)] ~= nil
end

function Inventory:unlockLink(mod, a, b)
    if not mod then return false, "invalid_module" end
    local key = edgeKey(a, b)
    if mod.links[key] then return false, "already_linked" end
    local allowed = false
    for _, edge in ipairs(mod.def.allLinks or {}) do
        if edgeKey(edge[1], edge[2]) == key then
            allowed = true
            break
        end
    end
    if not allowed then return false, "invalid_link" end
    mod.links[key] = { math.min(a, b), math.max(a, b) }
    return true
end

-- Unlocks the next missing link edge from def.allLinks (prioritizing one that
-- expands the active core-connected set).
function Inventory:unlockNextLink(mod)
    if not mod then return false, "invalid_module" end
    local active = self:getActiveSockets(mod)
    local fallback = nil
    for _, edge in ipairs(mod.def.allLinks or {}) do
        local key = edgeKey(edge[1], edge[2])
        if not mod.links[key] then
            if active[edge[1]] or active[edge[2]] then
                mod.links[key] = { edge[1], edge[2] }
                return true, edge
            elseif not fallback then
                fallback = edge
            end
        end
    end
    if fallback then
        mod.links[edgeKey(fallback[1], fallback[2])] = { fallback[1], fallback[2] }
        return true, fallback
    end
    return false, "all_linked"
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
    removeFromList(self.stashChips, chip)
    mod.sockets[socketIndex] = chip
    if previous then
        self.stashChips[#self.stashChips + 1] = previous
    end
    return true, previous
end

function Inventory:unequipChip(mod, socketIndex)
    if not mod then return nil end
    local chip = mod.sockets[socketIndex]
    if not chip then return nil end
    mod.sockets[socketIndex] = nil
    self.stashChips[#self.stashChips + 1] = chip
    return chip
end

function Inventory:getActiveChips(mod)
    local result = {}
    local active = self:getActiveSockets(mod)
    for i = 1, mod.maxSockets do
        if active[i] and mod.sockets[i] then
            result[#result + 1] = mod.sockets[i]
        end
    end
    return result
end

-- Compute full derived ship + weapon build from all currently placed modules
-- and their core-linked active support chips.
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
            -- Base weapon battery cost only applies if non-zero or modified by chips
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

-- Create a default starter inventory on the 3x3 diamond that preserves baseline
-- stats while giving the player starter stash modules & chips to test immediately.
function Inventory.newStarter(opts)
    local inv = Inventory.new(opts)
    -- Starter weapon fits cleanly in the 3x3 diamond center column: (2,3)-(3,3)
    local proj = inv:createModule("projectile")
    inv:placeModule(proj, 2, 3, false)

    -- Populate test-bench stash with additional modules & chips for prototyping
    inv:addModuleToStash("thruster")
    inv:addModuleToStash("shield")
    inv:addModuleToStash("battery")
    inv:addModuleToStash("missile")
    inv:addModuleToStash("laser")
    inv:addModuleToStash("armor")

    inv:addChipToStash("splitter")
    inv:addChipToStash("burst")
    inv:addChipToStash("dodge_trigger")
    inv:addChipToStash("wrap_trigger")
    inv:addChipToStash("fever_overdrive")
    inv:addChipToStash("dodge_charge")
    inv:addChipToStash("shockwave")
    inv:addChipToStash("wrap_phase")
    inv:addChipToStash("limiter_off")
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
