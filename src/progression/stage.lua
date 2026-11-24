-- Stage progression manager for SpaceGladiator.
-- Each stage never ends while active hostiles remain. It clears once all
-- scheduled squads are defeated (early clear) OR after the stage timer expires
-- and all remaining hostiles on the battlefield are gone.

local Stage = {}
Stage.__index = Stage

Stage.DEFAULT_LEVEL = 1
Stage.DEFAULT_DURATION = 45
Stage.BASE_SQUADS = 3 -- Stage 1 spawns 3 squads (15 ships); +1 squad per stage

function Stage.new(stageNumber, opts)
    opts = opts or {}
    local num = stageNumber or 1
    local level = opts.level or Stage.DEFAULT_LEVEL
    local duration = opts.duration or Stage.DEFAULT_DURATION
    local totalSquads = opts.totalSquads or (Stage.BASE_SQUADS + (num - 1))
    local featuredReward = opts.featuredReward or nil
    local scoreMultiplier = opts.scoreMultiplier or (featuredReward and featuredReward.id == "coin_jackpot" and 1.5 or 1)
    return setmetatable({
        number = num,
        level = level,
        duration = duration,
        elapsed = 0,
        totalSquads = totalSquads,
        cleared = false,
        clearReason = nil,
        featuredReward = featuredReward,
        scoreMultiplier = scoreMultiplier,
    }, Stage)
end

function Stage:remainingTime()
    return math.max(0, self.duration - self.elapsed)
end

function Stage:isOvertime()
    return not self.cleared and self.elapsed >= self.duration
end

function Stage:configureEnemies(enemies)
    if not enemies then return end
    enemies.squadsRemaining = self.totalSquads
    enemies.stageEnemiesDestroyed = 0
    enemies.stageEnemiesDeparted = 0
end

function Stage:update(dt, enemies)
    if self.cleared or dt <= 0 then return false end
    self.elapsed = self.elapsed + dt

    local activeCount = (enemies and enemies.items) and #enemies.items or 0
    local timeUp = self.elapsed >= self.duration

    -- Once the stage timer expires, stop scheduling new squads so the player
    -- only has to finish off the enemies still remaining on the battlefield.
    if timeUp and enemies and enemies.squadsRemaining ~= nil and enemies.squadsRemaining > 0 then
        enemies.squadsRemaining = 0
    end

    -- Never end the stage as long as any enemies remain.
    if activeCount > 0 then
        return false
    end

    -- Early clear: all scheduled squads spawned and zero active hostiles remain
    if enemies and enemies.squadsRemaining == 0 and not timeUp then
        self.cleared = true
        self.clearReason = "ALL HOSTILES CLEARED"
        return true
    end

    -- Time limit reached and zero enemies remain
    if timeUp then
        self.cleared = true
        self.clearReason = "STAGE TIME COMPLETE"
        return true
    end

    return false
end

function Stage:nextStage(opts)
    local nextOpts = {}
    if opts then
        for k, v in pairs(opts) do nextOpts[k] = v end
    end
    if nextOpts.level == nil then
        nextOpts.level = self.level or Stage.DEFAULT_LEVEL
    end
    return Stage.new(self.number + 1, nextOpts)
end

return Stage
