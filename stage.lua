-- Stage progression manager for SpaceGladiator.
-- Each stage lasts for a fixed duration (default 45s) OR ends immediately
-- once all enemies scheduled for that stage have been spawned and defeated.

local Stage = {}
Stage.__index = Stage

Stage.DEFAULT_DURATION = 45
Stage.BASE_SQUADS = 3 -- Stage 1 spawns 3 squads (15 ships); +1 squad per stage

function Stage.new(stageNumber, opts)
    opts = opts or {}
    local num = stageNumber or 1
    local duration = opts.duration or Stage.DEFAULT_DURATION
    local totalSquads = opts.totalSquads or (Stage.BASE_SQUADS + (num - 1))
    return setmetatable({
        number = num,
        duration = duration,
        elapsed = 0,
        totalSquads = totalSquads,
        cleared = false,
        clearReason = nil,
    }, Stage)
end

function Stage:remainingTime()
    return math.max(0, self.duration - self.elapsed)
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

    -- Early clear: all scheduled squads spawned and zero active hostiles remain
    if enemies and enemies.squadsRemaining == 0 and #enemies.items == 0 then
        self.cleared = true
        self.clearReason = "ALL HOSTILES CLEARED"
        return true
    end

    -- Time limit clear
    if self.elapsed >= self.duration then
        self.cleared = true
        self.clearReason = "STAGE TIME COMPLETE"
        return true
    end

    return false
end

function Stage:nextStage(opts)
    return Stage.new(self.number + 1, opts)
end

return Stage
