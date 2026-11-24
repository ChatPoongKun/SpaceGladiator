-- 5-Slot Gladiator Coin Plinko Machine (pure Lua physics + reward logic).
-- 1 Gladiator Point = 1 Gladiator Coin.
-- Coins drop from uniformly random X positions across the full top width.
-- Outer slots (1 and 5) roll higher-value rewards more often than inner slots.
-- Unclaimed slot progress is discarded by default, with a carryover hook ready
-- for a future permanent upgrade.

local ModulesData = require("src.data.modules_data")
local ChipsData = require("src.data.chips_data")
local Rarity = require("src.data.rarity")
local Sfx = require("src.audio.sfx")

local Plinko = {}
Plinko.__index = Plinko

Plinko.SLOT_COUNT = 5
Plinko.BOARD_W = 540
Plinko.BOARD_H = 380
Plinko.PEG_ROWS = 6
Plinko.GRAVITY = 760
Plinko.COIN_RADIUS = 5
Plinko.PEG_RADIUS = 4.5

-- Slot tier weights: outer slots (1, 5) strongly favor high-value rewards,
-- mid slots (2, 4) favor mid/high rewards, center slot (3) favors utility/basic.
local slotProfiles = {
    [1] = { required = 24, highWeight = 0.72, midWeight = 0.23, label = "OUTER" },
    [2] = { required = 20, highWeight = 0.35, midWeight = 0.50, label = "MID" },
    [3] = { required = 16, highWeight = 0.12, midWeight = 0.43, label = "CENTER" },
    [4] = { required = 20, highWeight = 0.35, midWeight = 0.50, label = "MID" },
    [5] = { required = 24, highWeight = 0.72, midWeight = 0.23, label = "OUTER" },
}

local rewardPools = {
    high = {
        { kind = "module", id = "missile", rarity = "RARE" },
        { kind = "module", id = "laser", rarity = "RARE" },
        { kind = "chip", id = "fever_overdrive", rarity = "LEGENDARY" },
        { kind = "chip", id = "limiter_off", rarity = "LEGENDARY" },
        { kind = "chip", id = "dodge_trigger", rarity = "RARE" },
        { kind = "chip", id = "hit_trigger", rarity = "RARE" },
    },
    mid = {
        { kind = "module", id = "shield", rarity = "UNCOMMON" },
        { kind = "module", id = "armor", rarity = "UNCOMMON" },
        { kind = "module", id = "battery", rarity = "UNCOMMON" },
        { kind = "chip", id = "splitter", rarity = "UNCOMMON" },
        { kind = "chip", id = "burst", rarity = "UNCOMMON" },
        { kind = "chip", id = "ricochet", rarity = "UNCOMMON" },
        { kind = "chip", id = "homing", rarity = "UNCOMMON" },
        { kind = "chip", id = "wrap_trigger", rarity = "UNCOMMON" },
    },
    low = {
        { kind = "module", id = "thruster", rarity = "NORMAL" },
        { kind = "module", id = "projectile", rarity = "NORMAL" },
        { kind = "chip", id = "dodge_charge", rarity = "NORMAL" },
        { kind = "chip", id = "shockwave", rarity = "NORMAL" },
        { kind = "chip", id = "wrap_phase", rarity = "NORMAL" },
        { kind = "repair", shield = 50, armor = 50, rarity = "NORMAL" },
    },
}

local function describeReward(r)
    if r.kind == "module" then
        local def = ModulesData.get(r.id)
        local rarity = Rarity.normalize(r.rarity or (def and def.rarity))
        return {
            title = def and def.name or r.id,
            color = Rarity.getColor(rarity),
            rarity = rarity,
            rarityLabel = Rarity.getLabel(rarity),
            spec = r,
        }
    elseif r.kind == "chip" then
        local def = ChipsData.get(r.id)
        local rarity = Rarity.normalize(r.rarity or (def and def.rarity))
        return {
            title = def and def.name or r.id,
            color = Rarity.getColor(rarity),
            rarity = rarity,
            rarityLabel = Rarity.getLabel(rarity),
            spec = r,
        }
    else
        local rarity = Rarity.normalize(r.rarity)
        return {
            title = "긴급 선체 수리",
            color = Rarity.getColor(rarity),
            rarity = rarity,
            rarityLabel = Rarity.getLabel(rarity),
            spec = r,
        }
    end
end

local function makeRng(seed)
    local state = (seed or 1337) % 2147483647
    if state <= 0 then state = 1337 end
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

local function pickRewardForSlot(slotIndex, rand, stageNumber)
    local p = slotProfiles[slotIndex] or slotProfiles[3]
    local stageBoost = math.min(0.18, ((stageNumber or 1) - 1) * 0.04)
    local roll = rand()
    local tier = "low"
    if roll < p.highWeight + stageBoost then
        tier = "high"
    elseif roll < p.highWeight + stageBoost + p.midWeight then
        tier = "mid"
    end
    local pool = rewardPools[tier]
    local chosen = pool[math.floor(rand() * #pool) + 1]
    return describeReward(chosen), tier
end

local function buildPegs(boardW, boardH, rows)
    local pegs = {}
    local topY = 58
    local bottomY = boardH - 92
    local rowStep = (bottomY - topY) / math.max(1, rows - 1)
    for row = 1, rows do
        local cols = (row % 2 == 1) and 7 or 6
        local margin = (row % 2 == 1) and 42 or 78
        local span = boardW - margin * 2
        local step = cols > 1 and (span / (cols - 1)) or 0
        local y = topY + (row - 1) * rowStep
        for col = 1, cols do
            pegs[#pegs + 1] = {
                x = margin + (col - 1) * step,
                y = y,
                radius = Plinko.PEG_RADIUS,
            }
        end
    end
    return pegs
end

function Plinko.new(opts)
    opts = opts or {}
    local rand = opts.rand or makeRng(opts.seed or math.floor((os.clock() or 1) * 100000))
    local stageNumber = opts.stageNumber or 1
    local boardW = opts.boardW or Plinko.BOARD_W
    local boardH = opts.boardH or Plinko.BOARD_H
    local carried = opts.carriedSlots or {}

    local slots = {}
    local slotW = boardW / Plinko.SLOT_COUNT
    for i = 1, Plinko.SLOT_COUNT do
        local p = slotProfiles[i]
        local prev = carried[i]
        if prev and not prev.claimed then
            slots[i] = {
                index = i,
                x = (i - 1) * slotW,
                w = slotW,
                required = prev.required,
                filled = prev.filled,
                claimed = false,
                reward = prev.reward,
                tier = prev.tier,
                carriedOver = true,
            }
        else
            local reward, tier = pickRewardForSlot(i, rand, stageNumber)
            slots[i] = {
                index = i,
                x = (i - 1) * slotW,
                w = slotW,
                required = p.required,
                filled = 0,
                claimed = false,
                reward = reward,
                tier = tier,
                carriedOver = false,
            }
        end
    end

    -- Apply next-stage warp gate featured reward overrides when specified
    local featured = opts.featuredReward
    local featuredId = type(featured) == "table" and featured.id or featured
    if featuredId == "weapon_module" then
        local weaponSpecs = {
            { kind = "module", id = "missile", rarity = "RARE" },
            { kind = "module", id = "laser", rarity = "RARE" },
        }
        local pick = weaponSpecs[math.floor(rand() * #weaponSpecs) + 1]
        if not slots[1].carriedOver then
            slots[1].reward = describeReward(pick)
            slots[1].tier = "high"
            slots[1].required = math.max(16, slots[1].required - 4)
        end
    elseif featuredId == "support_chip" then
        local rareChips = {
            { kind = "chip", id = "fever_overdrive", rarity = "LEGENDARY" },
            { kind = "chip", id = "limiter_off", rarity = "LEGENDARY" },
            { kind = "chip", id = "dodge_trigger", rarity = "RARE" },
            { kind = "chip", id = "hit_trigger", rarity = "RARE" },
        }
        if not slots[1].carriedOver then
            slots[1].reward = describeReward(rareChips[math.floor(rand() * #rareChips) + 1])
            slots[1].tier = "high"
        end
        if not slots[5].carriedOver then
            slots[5].reward = describeReward(rareChips[math.floor(rand() * #rareChips) + 1])
            slots[5].tier = "high"
        end
    elseif featuredId == "defense_module" then
        local defSpecs = {
            { kind = "module", id = "shield", rarity = "RARE" },
            { kind = "module", id = "armor", rarity = "RARE" },
            { kind = "module", id = "battery", rarity = "RARE" },
            { kind = "module", id = "thruster", rarity = "UNCOMMON" },
        }
        if not slots[2].carriedOver then
            slots[2].reward = describeReward(defSpecs[math.floor(rand() * #defSpecs) + 1])
            slots[2].tier = "mid"
        end
        if not slots[4].carriedOver then
            slots[4].reward = describeReward(defSpecs[math.floor(rand() * #defSpecs) + 1])
            slots[4].tier = "mid"
        end
    end

    return setmetatable({
        stageNumber = stageNumber,
        boardW = boardW,
        boardH = boardH,
        slotTopY = boardH - 68,
        pegs = buildPegs(boardW, boardH, Plinko.PEG_ROWS),
        slots = slots,
        coins = opts.coins or 0,
        invested = 0,
        activeCoins = {},
        dropQueue = 0,
        dropTimer = 0,
        dropInterval = 0.035,
        claimedLog = {},
        carryoverEnabled = opts.carryoverEnabled == true, -- future permanent upgrade hook
        rand = rand,
    }, Plinko)
end

-- Invest coins from the player's available Gladiator Coin pool.
-- Coins are queued and spawned across the full top width at random X positions.
function Plinko:invest(amount)
    local n = math.floor(amount or 0)
    if n <= 0 or self.coins <= 0 then return 0 end
    local spent = math.min(n, self.coins)
    self.coins = self.coins - spent
    self.invested = self.invested + spent
    self.dropQueue = self.dropQueue + spent
    if spent > 0 then Sfx.play("plinko_drop") end
    return spent
end

function Plinko:spawnCoin()
    local margin = 24
    local x = margin + self.rand() * (self.boardW - margin * 2)
    local vx = (self.rand() - 0.5) * 48
    self.activeCoins[#self.activeCoins + 1] = {
        x = x,
        y = 14,
        vx = vx,
        vy = 20 + self.rand() * 35,
        radius = Plinko.COIN_RADIUS,
    }
end

function Plinko:grantReward(slot, inventory, ship)
    local spec = slot.reward.spec
    if spec.kind == "module" and inventory then
        inventory:addPendingModule(spec.id, { rarity = slot.reward.rarity })
    elseif spec.kind == "chip" and inventory then
        inventory:addPendingChip(spec.id, { rarity = slot.reward.rarity })
    elseif spec.kind == "repair" and ship then
        ship.shield = math.min(ship.maxShield, ship.shield + (spec.shield or 50))
        ship.armor = math.min(ship.maxArmor, ship.armor + (spec.armor or 50))
    end
    self.claimedLog[#self.claimedLog + 1] = slot.reward.title
end

function Plinko:update(dt, inventory, ship)
    if dt <= 0 then return end
    -- Release queued coins in a rapid waterfall
    if self.dropQueue > 0 then
        self.dropTimer = self.dropTimer - dt
        while self.dropQueue > 0 and self.dropTimer <= 0 do
            self:spawnCoin()
            self.dropQueue = self.dropQueue - 1
            self.dropTimer = self.dropTimer + self.dropInterval
        end
    end

    local slotW = self.boardW / Plinko.SLOT_COUNT
    for i = #self.activeCoins, 1, -1 do
        local c = self.activeCoins[i]
        c.vy = c.vy + Plinko.GRAVITY * dt
        c.x = c.x + c.vx * dt
        c.y = c.y + c.vy * dt

        -- Side wall bounce
        if c.x < c.radius + 6 then
            c.x = c.radius + 6
            c.vx = math.abs(c.vx) * 0.65 + 15
        elseif c.x > self.boardW - c.radius - 6 then
            c.x = self.boardW - c.radius - 6
            c.vx = -math.abs(c.vx) * 0.65 - 15
        end

        -- Peg collisions
        for _, peg in ipairs(self.pegs) do
            local dx, dy = c.x - peg.x, c.y - peg.y
            local minDist = c.radius + peg.radius
            local distSq = dx * dx + dy * dy
            if distSq < minDist * minDist then
                local dist = math.sqrt(distSq)
                local nx, ny
                if dist < 1e-4 then
                    nx = (self.rand() < 0.5) and -0.7 or 0.7
                    ny = -0.7
                else
                    nx, ny = dx / dist, dy / dist
                end
                c.x = peg.x + nx * (minDist + 0.5)
                c.y = peg.y + ny * (minDist + 0.5)
                local dot = c.vx * nx + c.vy * ny
                if dot < 0 then
                    c.vx = (c.vx - 1.55 * dot * nx) + (self.rand() - 0.5) * 42
                    c.vy = (c.vy - 1.45 * dot * ny) * 0.72
                    Sfx.play("plinko_peg")
                end
            end
        end

        -- Landed in one of the 5 bottom slots
        if c.y >= self.slotTopY then
            local idx = math.max(1, math.min(Plinko.SLOT_COUNT, math.floor(c.x / slotW) + 1))
            local slot = self.slots[idx]
            slot.filled = slot.filled + 1
            local ratio = math.min(1, slot.filled / math.max(1, slot.required))
            if not slot.claimed and slot.filled >= slot.required then
                slot.claimed = true
                Sfx.play("plinko_claim")
                self:grantReward(slot, inventory, ship)
            else
                Sfx.play("plinko_slot", 0.90 + 0.45 * ratio)
            end
            table.remove(self.activeCoins, i)
        end
    end
end

function Plinko:isBusy()
    return self.dropQueue > 0 or #self.activeCoins > 0
end

-- Fast-forward all remaining queued/falling coins (useful on skip or in tests).
function Plinko:resolveAll(inventory, ship)
    local guard = 0
    while self:isBusy() and guard < 2000 do
        self:update(1 / 60, inventory, ship)
        guard = guard + 1
    end
end

-- Future permanent upgrade hook: returns partially filled unclaimed slots
-- when carryoverEnabled is true; returns empty table by default (discarded).
function Plinko:exportCarryoverSlots()
    local carried = {}
    if not self.carryoverEnabled then return carried end
    for i, slot in ipairs(self.slots) do
        if not slot.claimed and slot.filled > 0 then
            carried[i] = {
                required = slot.required,
                filled = slot.filled,
                claimed = false,
                reward = slot.reward,
                tier = slot.tier,
            }
        end
    end
    return carried
end

return Plinko
