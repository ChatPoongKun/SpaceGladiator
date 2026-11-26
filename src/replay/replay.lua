local Arena = require("src.core.arena")
local Display = require("src.core.display")
local Ship = require("src.combat.ship")
local Turret = require("src.combat.turret")
local Enemies = require("src.combat.enemies")
local Gladiator = require("src.combat.gladiator")
local Starfield = require("src.visual.starfield")
local StageBackground = require("src.visual.stage_background")
local Sfx = require("src.audio.sfx")

local okFfi, ffi = pcall(require, "ffi")

if okFfi then
    pcall(ffi.cdef, [[
        typedef struct {
            float time;
            float stageRemaining;
            int32_t stageNumber;
            float shipX, shipY, shipVx, shipVy, shipWrapVx, shipWrapVy, shipAngle;
            float shipBoostRemaining, shipBoostLevel, shipBoostX, shipBoostY, shipBoostOriginX, shipBoostOriginY;
            float shipShield, shipMaxShield, shipArmor, shipMaxArmor, shipHull, shipMaxHull;
            float shipBattery, shipMaxBattery, shipDestructionAge, shipInvulnTimer, shipInvulnDuration;
            float turretAngle;
            int32_t turretWeapon;
            uint8_t shipAccelerating, shipBraking;
            float camX, camY, camZoom, camScreenOffsetY, camPullback;
            int32_t gladTotal;
            uint8_t gladFeverActive;
            float gladFeverDuration, gladFeverPoints, gladFeverAura, gladFeverFlash, gladFeverCooldown;
            int32_t enemiesKills;
            int32_t enemyOff, enemyCnt;
            int32_t shotOff, shotCnt;
            int32_t impactOff, impactCnt;
            int32_t missileOff, missileCnt;
            int32_t beamOff, beamCnt;
            int32_t explosionOff, explosionCnt;
            int32_t burstOff, burstCnt;
            int32_t sparkOff, sparkCnt;
        } SGFrameHeader;

        typedef struct {
            float x, y, angle;
            uint8_t kind, aimed;
        } SGEnemyRec;

        typedef struct {
            float x, y, vx, vy, age;
            uint8_t kind;
        } SGShotRec;

        typedef struct {
            float x, y, age;
            uint8_t kind, shield;
        } SGImpactRec;

        typedef struct {
            float x, y, vx, vy, speed, age, distance, ownerX, ownerY;
            uint8_t isRocket;
        } SGMissileRec;

        typedef struct {
            float x, y, dx, dy, hitX, hitY, age;
            uint8_t hasHit;
        } SGBeamRec;

        typedef struct {
            float x, y, radius, age, lifetime;
            uint8_t isBeamImpact;
        } SGExplosionRec;

        typedef struct {
            float x, y, age, duration;
        } SGBurstRec;

        typedef struct {
            float x, y, age, duration, size;
            uint8_t gold;
        } SGSparkRec;
    ]])
end

local Replay = {}
Replay.__index = Replay

Replay.SAMPLE_HZ = 30
Replay.SAMPLE_DT = 1 / Replay.SAMPLE_HZ
Replay.MAX_STAGE_SECONDS = 120
Replay.MAX_FRAMES = Replay.SAMPLE_HZ * Replay.MAX_STAGE_SECONDS

Replay.MIN_PEAK_RATE = 30
Replay.CLIP_DURATION = 6.0
Replay.PEAK_MARGIN = 1.0
Replay.SLOWMO_SOURCE_DURATION = 1.25
Replay.SLOWMO_PLAYBACK_DURATION = 2.25
Replay.SLOWMO_RAMP_PLAYBACK = 0.25
Replay.SLOWMO_HOLD_PLAYBACK = 1.75
Replay.SLOWMO_SPEED = 0.5
Replay.TARGET_PLAYBACK_DURATION = 7.0

-- Hard caps per frame to keep memory and CPU bounded as enemy/bullet counts grow.
Replay.CAP_ENEMIES = 64
Replay.CAP_SHOTS = 512
Replay.CAP_IMPACTS = 128
Replay.CAP_MISSILES = 256
Replay.CAP_BEAMS = 64
Replay.CAP_EXPLOSIONS = 256
Replay.CAP_BURSTS = 16
Replay.CAP_SPARKS = 256

-- Flat pool capacities for one stage recording (~11 MB total in LuaJIT FFI, 0 Lua GC).
local POOL_ENEMIES = 65536
local POOL_SHOTS = 131072
local POOL_IMPACTS = 32768
local POOL_MISSILES = 65536
local POOL_BEAMS = 16384
local POOL_EXPLOSIONS = 65536
local POOL_BURSTS = 4096
local POOL_SPARKS = 65536

local enemyShotProfiles = {
    [1] = { speed = 440, lifetime = 1.65, radius = 3.5, trail = 15, color = { 1, 0.45, 0.23 } },
    [2] = { speed = 1150, lifetime = 0.95, radius = 4.5, trail = 56, color = { 1, 0.24, 0.65 }, isLaser = true },
    [3] = { radius = 5, trail = 24, color = { 1, 0.28, 0.28 } },
    [4] = { speed = 255, lifetime = 3.8, radius = 5.0, trail = 10, color = { 1.0, 0.78, 0.24 }, isOrb = true },
    [5] = { speed = 210, lifetime = 4.2, radius = 5.0, trail = 10, color = { 0.82, 0.34, 1.0 }, isOrb = true },
}

local explosionColors = { glow = { 0.141, 0.549, 1.0 }, ring = { 0.220, 0.863, 1.0 }, core = { 0.933, 0.984, 1.0 } }
local beamImpactColors = { glow = { 0.12, 0.68, 1 }, ring = { 0.30, 0.92, 1 }, core = { 0.83, 0.98, 1 } }
local tau = math.pi * 2

local function classifyEnemyShotProfile(profile)
    if not profile then return 1 end
    if profile.replayKind then return profile.replayKind end
    if profile.isLaser or profile.speed == 1400 or profile.speed == 1150 or profile.radius == 4 then return 2 end
    if profile.isOrb and profile.color and profile.color[3] and profile.color[3] > 0.6 then return 5 end
    if profile.isOrb or profile.trail == 10 then return 4 end
    if profile.isMissile or profile.radius == 5 or profile.trail == 24 then return 3 end
    return 1
end

local function isBeamImpactExplosion(exp)
    if not exp or not exp.colors or not exp.colors.glow then return false end
    return exp.colors.glow[3] > 0.5
end

local function allocArray(ctype, count)
    if okFfi then
        return ffi.new(ctype .. "[?]", count)
    end
    local t = {}
    for i = 0, count - 1 do
        t[i] = {}
    end
    return t
end

function Replay.new()
    local self = setmetatable({
        useFfi = okFfi,
        headers = allocArray("SGFrameHeader", Replay.MAX_FRAMES),
        enemiesPool = allocArray("SGEnemyRec", POOL_ENEMIES),
        shotsPool = allocArray("SGShotRec", POOL_SHOTS),
        impactsPool = allocArray("SGImpactRec", POOL_IMPACTS),
        missilesPool = allocArray("SGMissileRec", POOL_MISSILES),
        beamsPool = allocArray("SGBeamRec", POOL_BEAMS),
        explosionsPool = allocArray("SGExplosionRec", POOL_EXPLOSIONS),
        burstsPool = allocArray("SGBurstRec", POOL_BURSTS),
        sparksPool = allocArray("SGSparkRec", POOL_SPARKS),
        frameCount = 0,
        writeHead = 0,
        wrapped = false,
        enemyCursor = 0,
        shotCursor = 0,
        impactCursor = 0,
        missileCursor = 0,
        beamCursor = 0,
        explosionCursor = 0,
        burstCursor = 0,
        sparkCursor = 0,
        accumulator = 0,
        stageTime = 0,
        pointEvents = {},
        sfxEvents = {},
        bestClip = nil,
        -- Playback state
        active = false,
        playing = false,
        playbackTime = 0,
        nextSfxIndex = 1,
        stars = nil,
        stageBackground = nil,
        exportStatus = nil,
        exportProgress = 0,
        exporting = false,
        exportError = nil,
        lastExportPath = nil,
        buttons = {},
    }, Replay)
    return self
end

function Replay:resetStage()
    self.frameCount = 0
    self.writeHead = 0
    self.wrapped = false
    self.enemyCursor = 0
    self.shotCursor = 0
    self.impactCursor = 0
    self.missileCursor = 0
    self.beamCursor = 0
    self.explosionCursor = 0
    self.burstCursor = 0
    self.sparkCursor = 0
    self.accumulator = 0
    self.stageTime = 0
    self.pointEvents = {}
    self.sfxEvents = {}
end

function Replay:resetRun()
    self:resetStage()
    self.bestClip = nil
    self.active = false
    self.playing = false
    self.playbackTime = 0
    self.nextSfxIndex = 1
    self.exportStatus = nil
    self.exportProgress = 0
    self.exporting = false
    self.exportError = nil
    self.lastExportPath = nil
end

function Replay:recordPointEvent(category, points, x, y, fever, basePoints)
    if not points or points <= 0 then return end
    local isFever = fever and true or false
    local rawPoints = basePoints
    if rawPoints == nil then
        rawPoints = isFever and (points / (Gladiator.feverMultiplier or 2)) or points
    end
    self.pointEvents[#self.pointEvents + 1] = {
        time = self.stageTime,
        category = category,
        points = points,
        basePoints = rawPoints,
        x = x or 0,
        y = y or 0,
        fever = isFever,
    }
end

function Replay:recordSfxEvent(cue)
    if not cue then return end
    self.sfxEvents[#self.sfxEvents + 1] = {
        time = self.stageTime,
        cue = cue,
    }
end

local function reservePool(cursor, cap, count)
    if count <= 0 then return cursor, 0 end
    if cursor + count > cap then
        cursor = 0
    end
    if count > cap then count = cap end
    return cursor, count
end

function Replay:captureSnapshot(ship, camera, turret, enemies, gladiator, stage)
    if not ship or not camera or not turret or not enemies or not gladiator then return end

    local idx = self.writeHead
    local h = self.headers[idx]

    h.time = self.stageTime
    h.stageNumber = stage and stage.number or 1
    h.stageRemaining = stage and stage:remainingTime() or 0

    h.shipX = ship.x or 0
    h.shipY = ship.y or 0
    h.shipVx = ship.vx or 0
    h.shipVy = ship.vy or 0
    h.shipWrapVx = ship.wrapVx or 0
    h.shipWrapVy = ship.wrapVy or 0
    h.shipAngle = ship.angle or 0
    h.shipBoostRemaining = ship.boostRemaining or 0
    h.shipBoostLevel = ship.boostLevel or 0
    h.shipBoostX = ship.boostX or 0
    h.shipBoostY = ship.boostY or -1
    h.shipBoostOriginX = ship.boostOriginX or h.shipX
    h.shipBoostOriginY = ship.boostOriginY or h.shipY
    h.shipShield = ship.shield or 0
    h.shipMaxShield = ship.maxShield or 100
    h.shipArmor = ship.armor or 0
    h.shipMaxArmor = ship.maxArmor or 100
    h.shipHull = ship.hull or 0
    h.shipMaxHull = ship.maxHull or 3
    h.shipBattery = ship.battery or 0
    h.shipMaxBattery = ship.maxBattery or 100
    h.shipDestructionAge = ship.destructionAge or 0
    h.shipInvulnTimer = ship.invulnTimer or 0
    h.shipInvulnDuration = ship.invulnDuration or 0
    h.turretAngle = turret.angle or 0
    h.turretWeapon = turret.weapon or 1
    h.shipAccelerating = ship.accelerating and 1 or 0
    h.shipBraking = ship.braking and 1 or 0

    h.camX = camera.x or Arena.width * 0.5
    h.camY = camera.y or Arena.height * 0.5
    h.camZoom = camera.zoom or 1
    h.camScreenOffsetY = camera.screenOffsetY or 0
    h.camPullback = camera.pullback or 0

    h.gladTotal = gladiator.total or 0
    h.gladFeverActive = gladiator.feverActive and 1 or 0
    h.gladFeverDuration = gladiator.feverDuration or 0
    h.gladFeverPoints = gladiator.feverPoints or 0
    h.gladFeverAura = gladiator.feverAura or 0
    h.gladFeverFlash = gladiator.feverFlash or 0
    h.gladFeverCooldown = gladiator.feverCooldown or 0
    h.enemiesKills = enemies.kills or 0

    -- Enemies
    local eList = enemies.items or {}
    local eCnt = math.min(#eList, Replay.CAP_ENEMIES)
    local eOff
    eOff, eCnt = reservePool(self.enemyCursor, POOL_ENEMIES, eCnt)
    h.enemyOff, h.enemyCnt = eOff, eCnt
    for i = 1, eCnt do
        local src = eList[i]
        local dst = self.enemiesPool[eOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.angle = src.angle or 0
        dst.kind = src.kind or 1
        dst.aimed = src.aimed and 1 or 0
    end
    self.enemyCursor = eOff + eCnt

    -- Enemy shots
    local sList = (enemies.fire and enemies.fire.shots) or {}
    local sCnt = math.min(#sList, Replay.CAP_SHOTS)
    local sOff
    sOff, sCnt = reservePool(self.shotCursor, POOL_SHOTS, sCnt)
    h.shotOff, h.shotCnt = sOff, sCnt
    for i = 1, sCnt do
        local src = sList[i]
        local dst = self.shotsPool[sOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.vx = src.vx or 0
        dst.vy = src.vy or 0
        dst.age = src.age or 0
        dst.kind = classifyEnemyShotProfile(src.profile)
    end
    self.shotCursor = sOff + sCnt

    -- Enemy impacts
    local imList = (enemies.fire and enemies.fire.impacts) or {}
    local imCnt = math.min(#imList, Replay.CAP_IMPACTS)
    local imOff
    imOff, imCnt = reservePool(self.impactCursor, POOL_IMPACTS, imCnt)
    h.impactOff, h.impactCnt = imOff, imCnt
    for i = 1, imCnt do
        local src = imList[i]
        local dst = self.impactsPool[imOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.age = src.age or 0
        dst.kind = classifyEnemyShotProfile(src.profile)
        dst.shield = src.shield and 1 or 0
    end
    self.impactCursor = imOff + imCnt

    -- Player missiles / projectiles
    local mList = turret.missiles or {}
    local mCnt = math.min(#mList, Replay.CAP_MISSILES)
    local mOff
    mOff, mCnt = reservePool(self.missileCursor, POOL_MISSILES, mCnt)
    h.missileOff, h.missileCnt = mOff, mCnt
    for i = 1, mCnt do
        local src = mList[i]
        local dst = self.missilesPool[mOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.vx = src.vx or 0
        dst.vy = src.vy or 0
        dst.speed = src.speed or 1
        dst.age = src.age or 0
        dst.distance = src.distance or 0
        dst.isRocket = src.targetScreenX and 1 or 0
        dst.ownerX = (src.owner and src.owner.x) or h.shipX
        dst.ownerY = (src.owner and src.owner.y) or h.shipY
    end
    self.missileCursor = mOff + mCnt

    -- Beams
    local bList = (turret.beams and #turret.beams > 0) and turret.beams or (turret.beam and { turret.beam } or {})
    local bCnt = math.min(#bList, Replay.CAP_BEAMS)
    local bOff
    bOff, bCnt = reservePool(self.beamCursor, POOL_BEAMS, bCnt)
    h.beamOff, h.beamCnt = bOff, bCnt
    for i = 1, bCnt do
        local src = bList[i]
        local dst = self.beamsPool[bOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.dx = src.dx or 0
        dst.dy = src.dy or -1
        dst.hasHit = src.hitX and 1 or 0
        dst.hitX = src.hitX or 0
        dst.hitY = src.hitY or 0
        dst.age = src.age or 0
    end
    self.beamCursor = bOff + bCnt

    -- Explosions
    local exList = turret.explosions or {}
    local exCnt = math.min(#exList, Replay.CAP_EXPLOSIONS)
    local exOff
    exOff, exCnt = reservePool(self.explosionCursor, POOL_EXPLOSIONS, exCnt)
    h.explosionOff, h.explosionCnt = exOff, exCnt
    for i = 1, exCnt do
        local src = exList[i]
        local dst = self.explosionsPool[exOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.radius = src.radius or 41
        dst.age = src.age or 0
        dst.lifetime = src.lifetime or 0.45
        dst.isBeamImpact = isBeamImpactExplosion(src) and 1 or 0
    end
    self.explosionCursor = exOff + exCnt

    -- Fever bursts
    local fbList = gladiator.feverBursts or {}
    local fbCnt = math.min(#fbList, Replay.CAP_BURSTS)
    local fbOff
    fbOff, fbCnt = reservePool(self.burstCursor, POOL_BURSTS, fbCnt)
    h.burstOff, h.burstCnt = fbOff, fbCnt
    for i = 1, fbCnt do
        local src = fbList[i]
        local dst = self.burstsPool[fbOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.age = src.age or 0
        dst.duration = src.duration or 0.85
    end
    self.burstCursor = fbOff + fbCnt

    -- Fever sparks
    local fsList = gladiator.feverSparks or {}
    local fsCnt = math.min(#fsList, Replay.CAP_SPARKS)
    local fsOff
    fsOff, fsCnt = reservePool(self.sparkCursor, POOL_SPARKS, fsCnt)
    h.sparkOff, h.sparkCnt = fsOff, fsCnt
    for i = 1, fsCnt do
        local src = fsList[i]
        local dst = self.sparksPool[fsOff + i - 1]
        dst.x = src.x or 0
        dst.y = src.y or 0
        dst.age = src.age or 0
        dst.duration = src.duration or 0.4
        dst.size = src.size or 2.5
        dst.gold = src.gold and 1 or 0
    end
    self.sparkCursor = fsOff + fsCnt

    self.writeHead = (idx + 1) % Replay.MAX_FRAMES
    if self.frameCount < Replay.MAX_FRAMES then
        self.frameCount = self.frameCount + 1
    else
        self.wrapped = true
    end
end

function Replay:recordFrame(dt, ship, camera, turret, enemies, gladiator, stage)
    if dt <= 0 then return end
    self.stageTime = self.stageTime + dt
    if self.frameCount == 0 then
        self:captureSnapshot(ship, camera, turret, enemies, gladiator, stage)
        self.accumulator = 0
        return
    end
    self.accumulator = self.accumulator + dt
    if self.accumulator >= Replay.SAMPLE_DT then
        self.accumulator = self.accumulator - Replay.SAMPLE_DT
        if self.accumulator > Replay.SAMPLE_DT then
            self.accumulator = 0
        end
        self:captureSnapshot(ship, camera, turret, enemies, gladiator, stage)
    end
end

-- Pure analytical highlight window selection:
-- 1. Find 1.0s centered window with max base points (excluding fever/score multipliers) >= MIN_PEAK_RATE (30 base pts/s).
-- 2. Select highest-scoring (by base points) 6.0s window containing [peak - 1.0, peak + 1.0].
-- 3. Place 0.5x slow-mo ramp block (1.25s source -> 2.25s playback, +1.0s) centered on peak -> 7.0s output.
function Replay.selectHighlightWindow(pointEvents, minTime, maxTime)
    if not pointEvents or #pointEvents == 0 or not minTime or not maxTime or maxTime <= minTime then
        return nil
    end

    local function eventBasePoints(ev)
        if ev.basePoints ~= nil then
            return ev.basePoints
        end
        if ev.fever then
            return ev.points / (Gladiator.feverMultiplier or 2)
        end
        return ev.points
    end

    local function sumBasePoints(lo, hi)
        local total = 0
        for i = 1, #pointEvents do
            local ev = pointEvents[i]
            if ev.time >= lo - 1e-6 and ev.time <= hi + 1e-6 then
                total = total + eventBasePoints(ev)
            end
        end
        return total
    end

    local function sumAwardedPoints(lo, hi)
        local total = 0
        for i = 1, #pointEvents do
            local ev = pointEvents[i]
            if ev.time >= lo - 1e-6 and ev.time <= hi + 1e-6 then
                total = total + ev.points
            end
        end
        return total
    end

    -- Step 1: scan 1.0s windows at 0.05s resolution to find peak rate and peak center
    local step = 0.05
    local bestRate = 0
    local bestPeakTime = nil
    local t = minTime
    while t <= maxTime + 1e-6 do
        local rate = sumBasePoints(t - 0.5, t + 0.5)
        if rate > bestRate then
            bestRate = rate
            bestPeakTime = t
        end
        t = t + step
    end

    -- Also check exact event timestamps so brief bursts are never missed
    for i = 1, #pointEvents do
        local et = pointEvents[i].time
        if et >= minTime and et <= maxTime then
            local rate = sumBasePoints(et - 0.5, et + 0.5)
            if rate > bestRate then
                bestRate = rate
                bestPeakTime = et
            end
        end
    end

    if bestRate < Replay.MIN_PEAK_RATE or not bestPeakTime then
        return nil
    end

    -- Step 2: pick optimal 6.0s clip containing [peak - 1.0, peak + 1.0]
    local totalSpan = maxTime - minTime
    local clipDuration = math.min(Replay.CLIP_DURATION, totalSpan)
    local clipStart, clipEnd

    if totalSpan <= Replay.CLIP_DURATION + 1e-6 then
        clipStart, clipEnd = minTime, maxTime
    else
        local minStart = math.max(minTime, bestPeakTime + Replay.PEAK_MARGIN - clipDuration)
        local maxStart = math.min(maxTime - clipDuration, bestPeakTime - Replay.PEAK_MARGIN)
        if minStart > maxStart then
            clipStart = math.max(minTime, math.min(maxTime - clipDuration, bestPeakTime - clipDuration * 0.5))
        else
            local bestWindowScore = -1
            local bestDist = math.huge
            local cand = minStart
            while cand <= maxStart + 1e-6 do
                local score = sumBasePoints(cand, cand + clipDuration)
                local centerDist = math.abs((cand + clipDuration * 0.5) - bestPeakTime)
                if score > bestWindowScore or (score == bestWindowScore and centerDist < bestDist) then
                    bestWindowScore = score
                    bestDist = centerDist
                    clipStart = cand
                end
                cand = cand + step
            end
            clipStart = clipStart or minStart
        end
        clipEnd = clipStart + clipDuration
    end

    -- Step 3: compute slow-mo source window (1.25s source -> 2.25s playback, adding +1.0s)
    local slowSourceDur = math.min(Replay.SLOWMO_SOURCE_DURATION, clipDuration * 0.5)
    local slowStart = math.max(clipStart + 0.2, math.min(clipEnd - slowSourceDur - 0.2, bestPeakTime - slowSourceDur * 0.5))
    if slowStart < clipStart then slowStart = clipStart end
    local slowEnd = math.min(clipEnd, slowStart + slowSourceDur)
    slowSourceDur = slowEnd - slowStart

    -- Ramp geometry in playback time:
    -- rampDown (r) from 1.0 -> 0.5 covers 0.75 * r source
    -- hold (h) at 0.5 covers 0.5 * h source
    -- rampUp (r) from 0.5 -> 1.0 covers 0.75 * r source
    -- Total source in slow block = 1.5 * r + 0.5 * h
    local rampPb = math.min(Replay.SLOWMO_RAMP_PLAYBACK, slowSourceDur / 2.0)
    local holdSource = math.max(0, slowSourceDur - 1.5 * rampPb)
    local holdPb = holdSource / Replay.SLOWMO_SPEED
    local slowPlaybackDur = 2 * rampPb + holdPb

    local preDuration = slowStart - clipStart
    local postDuration = clipEnd - slowEnd
    local playbackDuration = preDuration + slowPlaybackDur + postDuration

    return {
        clipStart = clipStart,
        clipEnd = clipEnd,
        clipDuration = clipDuration,
        peakTime = bestPeakTime,
        peakRate = bestRate,
        clipBasePoints = sumBasePoints(clipStart, clipEnd),
        clipPoints = sumAwardedPoints(clipStart, clipEnd),
        slowStart = slowStart,
        slowEnd = slowEnd,
        slowSourceDuration = slowSourceDur,
        rampPlayback = rampPb,
        holdPlayback = holdPb,
        slowPlaybackStart = preDuration,
        slowPlaybackEnd = preDuration + slowPlaybackDur,
        playbackDuration = playbackDuration,
    }
end

-- Exact closed-form mapping from playback time [0, playbackDuration] -> (sourceTime, speed).
function Replay.mapPlaybackTime(clip, playbackTime)
    local pb = math.max(0, math.min(clip.playbackDuration, playbackTime))
    local pre = clip.slowPlaybackStart
    local r = clip.rampPlayback
    local h = clip.holdPlayback

    if pb <= pre then
        return clip.clipStart + pb, 1.0
    end

    local u = pb - pre
    if u <= r and r > 0 then
        -- v(t) = 1.0 - 0.5 * (t / r)
        local speed = 1.0 - 0.5 * (u / r)
        local srcDelta = u - 0.25 * (u * u) / r
        return clip.slowStart + srcDelta, speed
    end

    local uHold = u - r
    local srcAfterRampDown = 0.75 * r
    if uHold <= h then
        return clip.slowStart + srcAfterRampDown + uHold * 0.5, 0.5
    end

    local uUp = uHold - h
    local srcAfterHold = srcAfterRampDown + 0.5 * h
    if uUp <= r and r > 0 then
        -- v(t) = 0.5 + 0.5 * (t / r)
        local speed = 0.5 + 0.5 * (uUp / r)
        local srcDelta = 0.5 * uUp + 0.25 * (uUp * uUp) / r
        return clip.slowStart + srcAfterHold + srcDelta, speed
    end

    local uPost = uUp - r
    return math.min(clip.clipEnd, clip.slowEnd + uPost), 1.0
end

-- Exact inverse mapping from sourceTime [clipStart, clipEnd] -> (playbackTime, speed).
function Replay.mapSourceTime(clip, sourceTime)
    local s = math.max(clip.clipStart, math.min(clip.clipEnd, sourceTime))
    local pre = clip.slowPlaybackStart
    local r = clip.rampPlayback
    local h = clip.holdPlayback

    if s <= clip.slowStart then
        return s - clip.clipStart, 1.0
    end

    local ds = s - clip.slowStart
    local srcRampDown = 0.75 * r
    if ds <= srcRampDown and r > 0 then
        -- u - (u^2)/(4r) = ds  =>  u = 2r * (1 - sqrt(1 - ds / r))
        local disc = math.max(0, 1 - ds / r)
        local u = 2 * r * (1 - math.sqrt(disc))
        return pre + u, 1.0 - 0.5 * (u / r)
    end

    local dsHold = ds - srcRampDown
    local srcHold = 0.5 * h
    if dsHold <= srcHold then
        return pre + r + dsHold * 2.0, 0.5
    end

    local dsUp = dsHold - srcHold
    local srcRampUp = 0.75 * r
    if dsUp <= srcRampUp and r > 0 then
        -- 0.5*u + (u^2)/(4r) = dsUp  =>  u = r * (-1 + sqrt(1 + 4*dsUp / r))
        local u = r * (-1 + math.sqrt(1 + 4 * dsUp / r))
        return pre + r + h + u, 0.5 + 0.5 * (u / r)
    end

    return math.min(clip.playbackDuration, clip.slowPlaybackEnd + (s - clip.slowEnd)), 1.0
end

function Replay:getOrderedHeader(orderIndex)
    local startIdx = self.wrapped and self.writeHead or 0
    local realIdx = (startIdx + orderIndex) % Replay.MAX_FRAMES
    return self.headers[realIdx]
end

function Replay:extractClip(window)
    local frames = {}
    local padLo = window.clipStart - Replay.SAMPLE_DT * 2
    local padHi = window.clipEnd + Replay.SAMPLE_DT * 2

    for i = 0, self.frameCount - 1 do
        local h = self:getOrderedHeader(i)
        if h.time >= padLo and h.time <= padHi then
            local frame = {
                time = h.time,
                stageNumber = h.stageNumber,
                stageRemaining = h.stageRemaining,
                shipX = h.shipX, shipY = h.shipY,
                shipVx = h.shipVx, shipVy = h.shipVy,
                shipWrapVx = h.shipWrapVx, shipWrapVy = h.shipWrapVy,
                shipAngle = h.shipAngle,
                shipBoostRemaining = h.shipBoostRemaining,
                shipBoostLevel = h.shipBoostLevel,
                shipBoostX = h.shipBoostX, shipBoostY = h.shipBoostY,
                shipBoostOriginX = h.shipBoostOriginX, shipBoostOriginY = h.shipBoostOriginY,
                shipShield = h.shipShield, shipMaxShield = h.shipMaxShield,
                shipArmor = h.shipArmor, shipMaxArmor = h.shipMaxArmor,
                shipHull = h.shipHull, shipMaxHull = h.shipMaxHull,
                shipBattery = h.shipBattery, shipMaxBattery = h.shipMaxBattery,
                shipDestructionAge = h.shipDestructionAge,
                shipInvulnTimer = h.shipInvulnTimer,
                shipInvulnDuration = h.shipInvulnDuration,
                turretAngle = h.turretAngle, turretWeapon = h.turretWeapon,
                shipAccelerating = h.shipAccelerating == 1,
                shipBraking = h.shipBraking == 1,
                camX = h.camX, camY = h.camY, camZoom = h.camZoom,
                camScreenOffsetY = h.camScreenOffsetY, camPullback = h.camPullback,
                gladTotal = h.gladTotal,
                gladFeverActive = h.gladFeverActive == 1,
                gladFeverDuration = h.gladFeverDuration,
                gladFeverPoints = h.gladFeverPoints,
                gladFeverAura = h.gladFeverAura,
                gladFeverFlash = h.gladFeverFlash,
                gladFeverCooldown = h.gladFeverCooldown,
                enemiesKills = h.enemiesKills,
                enemies = {}, shots = {}, impacts = {},
                missiles = {}, beams = {}, explosions = {},
                bursts = {}, sparks = {},
            }

            for j = 0, h.enemyCnt - 1 do
                local src = self.enemiesPool[h.enemyOff + j]
                frame.enemies[j + 1] = {
                    x = src.x, y = src.y, angle = src.angle,
                    kind = src.kind, aimed = src.aimed == 1,
                }
            end
            for j = 0, h.shotCnt - 1 do
                local src = self.shotsPool[h.shotOff + j]
                frame.shots[j + 1] = {
                    x = src.x, y = src.y, vx = src.vx, vy = src.vy,
                    age = src.age, kind = src.kind,
                }
            end
            for j = 0, h.impactCnt - 1 do
                local src = self.impactsPool[h.impactOff + j]
                frame.impacts[j + 1] = {
                    x = src.x, y = src.y, age = src.age,
                    kind = src.kind, shield = src.shield == 1,
                }
            end
            for j = 0, h.missileCnt - 1 do
                local src = self.missilesPool[h.missileOff + j]
                frame.missiles[j + 1] = {
                    x = src.x, y = src.y, vx = src.vx, vy = src.vy,
                    speed = src.speed, age = src.age, distance = src.distance,
                    isRocket = src.isRocket == 1,
                    ownerX = src.ownerX, ownerY = src.ownerY,
                }
            end
            for j = 0, h.beamCnt - 1 do
                local src = self.beamsPool[h.beamOff + j]
                frame.beams[j + 1] = {
                    x = src.x, y = src.y, dx = src.dx, dy = src.dy,
                    hitX = src.hasHit == 1 and src.hitX or nil,
                    hitY = src.hasHit == 1 and src.hitY or nil,
                    age = src.age,
                }
            end
            for j = 0, h.explosionCnt - 1 do
                local src = self.explosionsPool[h.explosionOff + j]
                frame.explosions[j + 1] = {
                    x = src.x, y = src.y, radius = src.radius,
                    age = src.age, lifetime = src.lifetime,
                    isBeamImpact = src.isBeamImpact == 1,
                }
            end
            for j = 0, h.burstCnt - 1 do
                local src = self.burstsPool[h.burstOff + j]
                frame.bursts[j + 1] = {
                    x = src.x, y = src.y, age = src.age, duration = src.duration,
                }
            end
            for j = 0, h.sparkCnt - 1 do
                local src = self.sparksPool[h.sparkOff + j]
                frame.sparks[j + 1] = {
                    x = src.x, y = src.y, age = src.age,
                    duration = src.duration, size = src.size, gold = src.gold == 1,
                }
            end

            frames[#frames + 1] = frame
        end
    end

    if #frames == 0 then return nil end

    local clipPoints = {}
    local startTotal = frames[1].gladTotal or 0
    for i = 1, #self.pointEvents do
        local ev = self.pointEvents[i]
        if ev.time >= window.clipStart - Gladiator.popupDuration and ev.time <= window.clipEnd + 0.05 then
            clipPoints[#clipPoints + 1] = {
                time = ev.time,
                category = ev.category,
                points = ev.points,
                basePoints = ev.basePoints,
                x = ev.x,
                y = ev.y,
                fever = ev.fever,
            }
        end
    end

    local clipSfx = {}
    for i = 1, #self.sfxEvents do
        local ev = self.sfxEvents[i]
        if ev.time >= window.clipStart - 0.02 and ev.time <= window.clipEnd + 0.02 then
            local pbTime, speed = Replay.mapSourceTime(window, ev.time)
            clipSfx[#clipSfx + 1] = {
                sourceTime = ev.time,
                playbackTime = pbTime,
                speed = speed,
                cue = ev.cue,
            }
        end
    end
    table.sort(clipSfx, function(a, b) return a.playbackTime < b.playbackTime end)

    window.frames = frames
    window.pointEvents = clipPoints
    window.sfxEvents = clipSfx
    window.startTotal = startTotal
    window.stageNumber = frames[1].stageNumber or 1
    return window
end

function Replay:finalizeStage()
    if self.frameCount < 2 or #self.pointEvents == 0 then
        self:resetStage()
        return nil
    end

    local firstH = self:getOrderedHeader(0)
    local lastH = self:getOrderedHeader(self.frameCount - 1)
    local window = Replay.selectHighlightWindow(self.pointEvents, firstH.time, lastH.time)
    local extracted = nil
    if window then
        extracted = self:extractClip(window)
        if extracted then
            local better = (not self.bestClip)
                or (extracted.peakRate > self.bestClip.peakRate)
                or (extracted.peakRate == self.bestClip.peakRate
                    and (extracted.clipBasePoints or extracted.clipPoints) > (self.bestClip.clipBasePoints or self.bestClip.clipPoints))
            if better then
                self.bestClip = extracted
            end
        end
    end
    self:resetStage()
    return extracted
end

function Replay:hasHighlight()
    return self.bestClip ~= nil and self.bestClip.frames ~= nil and #self.bestClip.frames > 0
end

function Replay:openPlayback(width, height)
    if not self:hasHighlight() then return false end
    self.active = true
    self.playing = true
    self.playbackTime = 0
    self.nextSfxIndex = 1
    self.exportStatus = nil
    self.exportError = nil
    if love and love.graphics then
        local _, _, vpW, vpH = Display.viewportRect()
        local bgW = width or vpW or Display.VIRTUAL_WIDTH
        local bgH = height or vpH or Display.VIRTUAL_HEIGHT
        self.stars = Starfield.new(bgW, bgH)
        self.stageBackground = StageBackground.new(bgW, bgH, {
            level = self.bestClip.level or StageBackground.DEFAULT_LEVEL,
        })
    end
    Sfx.stop()
    return true
end

function Replay:restartPlayback()
    if not self:hasHighlight() then return end
    self.playbackTime = 0
    self.nextSfxIndex = 1
    self.playing = true
    if self.stageBackground then
        self.stageBackground:setLevel(self.bestClip.level or StageBackground.DEFAULT_LEVEL, true)
    end
    Sfx.stop()
end

function Replay:togglePlay()
    if not self:hasHighlight() then return end
    if self.playbackTime >= self.bestClip.playbackDuration - 1e-3 then
        self:restartPlayback()
        return
    end
    self.playing = not self.playing
    if not self.playing then Sfx.stop() end
end

function Replay:closePlayback()
    self.active = false
    self.playing = false
    Sfx.stop()
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpAngle(a, b, t)
    local diff = (b - a + math.pi) % tau - math.pi
    return (a + diff * t) % tau
end

local function lerpWrapped(a, b, extent, t)
    local diff = b - a
    if math.abs(diff) > extent * 0.5 then
        if diff > 0 then
            diff = diff - extent
        else
            diff = diff + extent
        end
    end
    return (a + diff * t) % extent
end

function Replay.sampleClipFrame(clip, sourceTime)
    local frames = clip.frames
    local n = #frames
    if n == 1 or sourceTime <= frames[1].time then
        return frames[1], frames[1], 0
    end
    if sourceTime >= frames[n].time then
        return frames[n], frames[n], 0
    end
    -- Binary search for surrounding frames
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) * 0.5)
        if frames[mid].time <= sourceTime then
            lo = mid
        else
            hi = mid
        end
    end
    local f0, f1 = frames[lo], frames[hi]
    local span = f1.time - f0.time
    local alpha = span > 1e-6 and math.max(0, math.min(1, (sourceTime - f0.time) / span)) or 0
    return f0, f1, alpha
end

function Replay:updatePlayback(dt, width, height)
    if not self.active or not self:hasHighlight() then return end
    local clip = self.bestClip
    if not self.playing then return end

    local prevPb = self.playbackTime
    self.playbackTime = self.playbackTime + dt

    -- Trigger SFX events that fall in [prevPb, self.playbackTime]
    local sfxEvents = clip.sfxEvents or {}
    while self.nextSfxIndex <= #sfxEvents and sfxEvents[self.nextSfxIndex].playbackTime <= self.playbackTime do
        local ev = sfxEvents[self.nextSfxIndex]
        if ev.playbackTime >= prevPb - 0.05 then
            local pitchScale = math.max(0.62, math.min(1.0, 0.35 + 0.65 * (ev.speed or 1.0)))
            if Sfx.playWithPitchScale then
                Sfx.playWithPitchScale(ev.cue, pitchScale)
            else
                Sfx.play(ev.cue)
            end
        end
        self.nextSfxIndex = self.nextSfxIndex + 1
    end

    if self.playbackTime >= clip.playbackDuration then
        self.playbackTime = 0
        self.nextSfxIndex = 1
        Sfx.stop()
    end

    if self.stars or self.stageBackground then
        local srcTime, speed = Replay.mapPlaybackTime(clip, self.playbackTime)
        local f0, f1, alpha = Replay.sampleClipFrame(clip, srcTime)
        local vx = lerp(f0.shipVx + f0.shipWrapVx, f1.shipVx + f1.shipWrapVx, alpha)
        local vy = lerp(f0.shipVy + f0.shipWrapVy, f1.shipVy + f1.shipWrapVy, alpha)
        local boostLevel = lerp(f0.shipBoostLevel, f1.shipBoostLevel, alpha)
        local bgScale = Display.scale or 1
        local _, _, vpW, vpH = Display.viewportRect()
        local bgW = width or vpW or Display.VIRTUAL_WIDTH
        local bgH = height or vpH or Display.VIRTUAL_HEIGHT
        if self.stageBackground then
            local bgBoost = 120 * boostLevel
            self.stageBackground:update(dt * speed,
                (vx + f0.shipBoostX * bgBoost) * bgScale,
                (vy + f0.shipBoostY * bgBoost) * bgScale,
                bgW, bgH)
        end
        if self.stars then
            local surge = 1050 * boostLevel
            self.stars:update(dt * speed,
                (120 + vx * 2.8 + f0.shipBoostX * surge) * bgScale,
                (-290 + vy * 2.8 + f0.shipBoostY * surge) * bgScale,
                f0.shipAccelerating and 1 or 0, bgW, bgH, boostLevel)
        end
    end
end

local function drawEnemyFireSnapshot(shots, impacts)
    local g = love.graphics
    g.push("all")
    for i = 1, #shots do
        local shot = shots[i]
        local profile = enemyShotProfiles[shot.kind] or enemyShotProfiles[1]
        local r, green, b = unpack(profile.color)
        local length = math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy)
        local dx, dy = 0, 0
        if length > 0 then dx, dy = shot.vx / length, shot.vy / length end
        local trail = math.min(profile.trail, profile.radius + length * shot.age)
        local tailX, tailY = shot.x - dx * trail, shot.y - dy * trail
        if profile.isOrb then
            g.setLineWidth(profile.radius * 1.1)
            g.setColor(r, green, b, 0.20)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setColor(r, green, b, 0.24)
            g.circle("fill", shot.x, shot.y, profile.radius * 2.1)
            g.setColor(r, green, b, 0.95)
            g.circle("fill", shot.x, shot.y, profile.radius)
            g.setLineWidth(1.0)
            g.setColor(1, 0.94, 0.72, 0.85)
            g.circle("line", shot.x, shot.y, profile.radius)
            g.setColor(1, 0.97, 0.85, 1)
            g.circle("fill", shot.x, shot.y, profile.radius * 0.56)
        else
            g.setLineWidth(profile.radius * 1.8)
            g.setColor(r, green, b, 0.25)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setLineWidth(profile.isLaser and 3 or 1.5)
            g.setColor(r, green, b, 0.9)
            g.line(tailX, tailY, shot.x, shot.y)
            g.setColor(1, 0.85, 0.75, 1)
            g.circle("fill", shot.x, shot.y, profile.radius * 0.55)
        end
    end
    for i = 1, #impacts do
        local effect = impacts[i]
        local progress = math.min(1, effect.age / 0.24)
        if effect.kind == 3 then
            local radius = 4 + progress * 20
            local alpha = 1 - progress
            local glowR, glowG, glowB = 1.0, 0.28, 0.24
            local ringR, ringG, ringB = 1.0, 0.54, 0.32
            local coreR, coreG, coreB = 1.0, 0.88, 0.72
            if effect.shield then
                glowR, glowG, glowB = 0.20, 0.58, 1.0
                ringR, ringG, ringB = 0.35, 0.78, 1.0
                coreR, coreG, coreB = 0.82, 0.95, 1.0
            end
            g.setColor(glowR, glowG, glowB, alpha * 0.28)
            g.circle("fill", effect.x, effect.y, radius)
            g.setLineWidth(1.8 * alpha + 0.5)
            g.setColor(ringR, ringG, ringB, alpha * 0.9)
            g.circle("line", effect.x, effect.y, radius)
            g.setColor(coreR, coreG, coreB, alpha * 0.95)
            g.circle("fill", effect.x, effect.y, 5.5 * alpha)
            g.setLineWidth(1.2)
            g.setColor(ringR, ringG, ringB, alpha * 0.85)
            for j = 1, 6 do
                local angle = j * tau / 6
                local dx, dy = math.cos(angle), math.sin(angle)
                g.line(effect.x + dx * radius * 0.65, effect.y + dy * radius * 0.65,
                    effect.x + dx * (radius + 4), effect.y + dy * (radius + 4))
            end
        else
            local profile = enemyShotProfiles[effect.kind] or enemyShotProfiles[1]
            local r, green, b = unpack(profile.color)
            if effect.shield then r, green, b = 0.30, 0.70, 1 end
            g.setLineWidth(1.5)
            g.setColor(r, green, b, 0.8 * (1 - progress))
            g.circle("line", effect.x, effect.y, 4 + progress * profile.radius * 4)
        end
    end
    g.pop()
end

-- Renders a single replay frame at `playbackTime` into the current graphics target.
-- When `forExport` is true, omits interactive playback controls.
function Replay.renderClipFrame(clip, playbackTime, width, height, fonts, starsObj, forExport, bgObj)
    local g = love.graphics
    local srcTime, speed = Replay.mapPlaybackTime(clip, playbackTime)
    local f0, f1, alpha = Replay.sampleClipFrame(clip, srcTime)

    -- Background (fills 16:9 viewport in live playback, or export canvas when exporting)
    local vpX, vpY, vpW, vpH = 0, 0, width, height
    if not forExport then
        vpX, vpY, vpW, vpH = Display.viewportRect()
    end
    if bgObj then
        bgObj:draw(vpW, vpH, { originX = vpX, originY = vpY })
        if starsObj then
            starsObj:draw({ transparent = true, originX = vpX, originY = vpY })
        end
    elseif starsObj then
        starsObj:draw({ originX = vpX, originY = vpY })
    else
        g.push("all")
        g.origin()
        g.setColor(0.018, 0.025, 0.065, 1)
        g.rectangle("fill", vpX, vpY, vpW, vpH)
        g.pop()
    end

    g.push("all")
    if not forExport then
        Display.applyTransform()
    end

    -- Reconstruct camera matching target viewport size
    local fit = math.min(width / Arena.width, height / Arena.height)
    local pullback = lerp(f0.camPullback, f1.camPullback, alpha)
    local cam = setmetatable({
        x = lerp(f0.camX, f1.camX, alpha),
        y = lerp(f0.camY, f1.camY, alpha),
        zoom = fit * (1 - 0.12 * pullback),
        screenOffsetY = 0,
        pullback = pullback,
    }, require("src.core.camera"))

    -- Reconstruct player ship proxy
    local shipProxy = setmetatable({
        x = lerpWrapped(f0.shipX, f1.shipX, Arena.width, alpha),
        y = lerpWrapped(f0.shipY, f1.shipY, Arena.height, alpha),
        vx = lerp(f0.shipVx, f1.shipVx, alpha),
        vy = lerp(f0.shipVy, f1.shipVy, alpha),
        wrapVx = lerp(f0.shipWrapVx, f1.shipWrapVx, alpha),
        wrapVy = lerp(f0.shipWrapVy, f1.shipWrapVy, alpha),
        angle = lerpAngle(f0.shipAngle, f1.shipAngle, alpha),
        accelerating = f0.shipAccelerating,
        braking = f0.shipBraking,
        boostRemaining = lerp(f0.shipBoostRemaining, f1.shipBoostRemaining, alpha),
        boostLevel = lerp(f0.shipBoostLevel, f1.shipBoostLevel, alpha),
        boostX = f0.shipBoostX,
        boostY = f0.shipBoostY,
        boostOriginX = f0.shipBoostOriginX,
        boostOriginY = f0.shipBoostOriginY,
        shield = lerp(f0.shipShield, f1.shipShield, alpha),
        maxShield = f0.shipMaxShield,
        armor = lerp(f0.shipArmor, f1.shipArmor, alpha),
        maxArmor = f0.shipMaxArmor,
        hull = f0.shipHull,
        maxHull = f0.shipMaxHull,
        battery = lerp(f0.shipBattery, f1.shipBattery, alpha),
        maxBattery = f0.shipMaxBattery,
        destructionAge = lerp(f0.shipDestructionAge, f1.shipDestructionAge, alpha),
        invulnTimer = (f0.shipInvulnTimer or 0) > 0 and lerp(f0.shipInvulnTimer, f1.shipInvulnTimer or 0, alpha) or 0,
        invulnDuration = f0.shipInvulnDuration or Ship.hitInvulnDuration,
        radius = Ship.radius,
        shieldMargin = Ship.shieldMargin,
        maxSpeed = Ship.maxSpeed,
        boostHold = Ship.boostHold,
        boostFalloff = Ship.boostFalloff,
        destructionDuration = Ship.destructionDuration,
    }, Ship)

    local turretProxy = setmetatable({
        angle = lerpAngle(f0.turretAngle, f1.turretAngle, alpha),
        weapon = f0.turretWeapon,
        missiles = {},
        beams = f0.beams,
        explosions = {},
    }, Turret)

    for i = 1, #f0.missiles do
        local m = f0.missiles[i]
        turretProxy.missiles[i] = {
            x = m.x, y = m.y, vx = m.vx, vy = m.vy,
            speed = m.speed, age = m.age, distance = m.distance,
            targetScreenX = m.isRocket and 1 or nil,
            owner = { x = m.ownerX, y = m.ownerY },
        }
    end
    for i = 1, #f0.explosions do
        local ex = f0.explosions[i]
        turretProxy.explosions[i] = {
            x = ex.x, y = ex.y, radius = ex.radius,
            age = ex.age, lifetime = ex.lifetime,
            colors = ex.isBeamImpact and beamImpactColors or explosionColors,
            isSalvo = (not ex.isBeamImpact) and ((ex.radius or 0) > 50),
            sparkAngle = ((ex.x or 0) * 0.037 + (ex.y or 0) * 0.053) % (2 * math.pi),
        }
    end

    -- Reconstruct active popups from point event log for smooth slow-mo motion
    local activePopups = {}
    local gainedSoFar = 0
    for i = 1, #(clip.pointEvents or {}) do
        local ev = clip.pointEvents[i]
        if ev.time >= clip.clipStart - 1e-6 and ev.time <= srcTime + 1e-6 then
            gainedSoFar = gainedSoFar + ev.points
        end
        local age = srcTime - ev.time
        if age >= 0 and age < Gladiator.popupDuration then
            activePopups[#activePopups + 1] = {
                category = ev.category,
                points = ev.points,
                x = ev.x,
                y = ev.y,
                age = age,
                duration = Gladiator.popupDuration,
                fever = ev.fever,
            }
        end
    end

    local gladProxy = setmetatable({
        total = f0.gladTotal,
        feverActive = f0.gladFeverActive,
        feverDuration = lerp(f0.gladFeverDuration, f1.gladFeverDuration, alpha),
        feverPoints = lerp(f0.gladFeverPoints, f1.gladFeverPoints, alpha),
        feverAura = lerp(f0.gladFeverAura, f1.gladFeverAura, alpha),
        feverFlash = lerp(f0.gladFeverFlash, f1.gladFeverFlash, alpha),
        feverCooldown = lerp(f0.gladFeverCooldown, f1.gladFeverCooldown, alpha),
        feverBursts = f0.bursts,
        feverSparks = f0.sparks,
        popups = activePopups,
        popupRise = Gladiator.popupRise,
        elapsed = srcTime,
    }, Gladiator)

    -- Draw world
    g.push()
    local originX, originY = cam:worldToScreen(0, 0, width, height)
    g.translate(originX, originY)
    g.scale(cam.zoom)
    Arena.draw(shipProxy.boostLevel, gladProxy.feverAura)

    -- Draw enemies (with interpolation when matched)
    g.push("all")
    for i = 1, #f0.enemies do
        local e0 = f0.enemies[i]
        local ex, ey, ea = e0.x, e0.y, e0.angle
        local e1 = f1.enemies[i]
        if e1 and e1.kind == e0.kind and math.abs(e1.x - e0.x) < 120 and math.abs(e1.y - e0.y) < 120 then
            ex = lerp(e0.x, e1.x, alpha)
            ey = lerp(e0.y, e1.y, alpha)
            ea = lerpAngle(e0.angle, e1.angle, alpha)
        end
        g.push()
        g.translate(ex, ey)
        g.rotate(ea)
        Enemies.drawHull(e0.kind, e0.aimed, srcTime, { thrust = 0.55 })
        g.pop()
    end
    g.pop()
    drawEnemyFireSnapshot(f0.shots, f0.impacts)

    gladProxy:drawFeverWorld(shipProxy, srcTime)

    -- Draw player once without arena-boundary clipping or duplicate wrap copies
    g.push("all")
    if shipProxy:isDestroyed() then
        shipProxy:drawDestruction()
    else
        shipProxy:drawBoostPulse()
        turretProxy:drawMount(shipProxy, srcTime, width)
        shipProxy:draw(srcTime)
    end
    g.pop()

    turretProxy:drawEffects(cam, width, height)
    g.pop()

    -- Screen-space overlays & popups
    gladProxy:drawFeverOverlay(width, height, srcTime)
    gladProxy:drawPopups(cam, width, height, fonts.small)

    -- Top Replay Telemetry Bar
    g.push("all")
    g.setColor(0.018, 0.028, 0.055, 0.78)
    g.rectangle("fill", 0, 0, width, 96)
    g.setColor(0.25, 0.47, 0.58, 0.22)
    g.setLineWidth(1)
    g.line(32, 95, width - 32, 95)

    -- Left badge: HIGHLIGHT REPLAY + Stage
    local isSlow = speed < 0.92
    if isSlow then
        g.setColor(1.0, 0.78, 0.28, 0.95)
    else
        g.setColor(0.36, 0.88, 0.84, 0.95)
    end
    g.circle("fill", 42, 38, 5)
    g.setFont(fonts.menuButton or fonts.title)
    g.setColor(0.88, 0.95, 0.98, 1)
    g.print("HIGHLIGHT REPLAY", 56, 26)
    g.setFont(fonts.small)
    g.setColor(0.58, 0.72, 0.82, 0.95)
    g.print(string.format("STAGE %02d  ·  PEAK %d PTS/S", clip.stageNumber or 1, math.floor(clip.peakRate + 0.5)), 56, 56)

    -- Center: Gladiator Score + Highlight Gained
    local cx = math.floor(width / 2) - 130
    g.setFont(fonts.small)
    if gladProxy.feverActive then
        g.setColor(1.0, 0.86, 0.36, 1)
        g.printf("FEVER TIME x2", cx, 18, 260, "center")
    else
        g.setColor(0.60, 0.74, 0.84, 1)
        g.printf("GLADIATOR POINTS", cx, 18, 260, "center")
    end
    g.setFont(fonts.title)
    g.setColor(1.0, 0.90, 0.50, 1)
    g.printf(string.format("%04d", gladProxy.total), cx, 34, 260, "center")
    g.setFont(fonts.small)
    g.setColor(0.42, 0.92, 0.82, 0.95)
    g.printf(string.format("HIGHLIGHT +%d PTS", gainedSoFar), cx, 70, 260, "center")

    -- Right: Speed & Timestamp
    local rx = width - 250
    if isSlow then
        g.setColor(1.0, 0.72, 0.22, 0.20)
        g.rectangle("fill", rx, 22, 218, 52, 6, 6)
        g.setColor(1.0, 0.82, 0.34, 0.95)
        g.rectangle("line", rx, 22, 218, 52, 6, 6)
        g.setFont(fonts.menuButton or fonts.body)
        g.printf(string.format("%.2fx SLOW-MO", speed), rx, 29, 218, "center")
    else
        g.setFont(fonts.menuButton or fonts.body)
        g.setColor(0.75, 0.88, 0.94, 0.9)
        g.printf("1.00x", rx, 29, 218, "center")
    end
    g.setFont(fonts.small)
    g.setColor(0.62, 0.75, 0.84, 0.9)
    g.printf(string.format("%.1fs / %.1fs", playbackTime, clip.playbackDuration), rx, 55, 218, "center")

    g.pop()
    g.pop()

    if forExport then return end
end

function Replay:layoutButtons(width, height)
    local barY = height - 74
    local btnW, btnH, gap = 166, 38, 12
    local labels = {
        { id = "toggle", label = self.playing and "일시정지 (SPACE)" or "재생 (SPACE)" },
        { id = "restart", label = "다시 보기 (R)" },
        { id = "export", label = self.exporting and string.format("내보내는 중 %d%%", math.floor(self.exportProgress * 100 + 0.5)) or "MP4 내보내기 (E)" },
        { id = "back", label = "정산으로 (ESC)" },
    }
    local totalW = #labels * btnW + (#labels - 1) * gap
    local startX = math.floor((width - totalW) * 0.5)
    local buttons = {}
    for i, item in ipairs(labels) do
        buttons[i] = {
            id = item.id,
            label = item.label,
            x = startX + (i - 1) * (btnW + gap),
            y = barY,
            w = btnW,
            h = btnH,
        }
    end
    self.buttons = buttons
    return buttons
end

function Replay:buttonAt(mx, my)
    for _, b in ipairs(self.buttons or {}) do
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            return b.id
        end
    end
    return nil
end

function Replay:drawPlayback(width, height, fonts)
    if not self:hasHighlight() then return end
    local clip = self.bestClip
    Replay.renderClipFrame(clip, self.playbackTime, width, height, fonts, self.stars, false, self.stageBackground)

    local g = love.graphics
    g.push("all")
    Display.applyTransform()

    -- Bottom control panel
    local panelY = height - 134
    g.setColor(0.018, 0.028, 0.055, 0.82)
    g.rectangle("fill", 0, panelY, width, 134)
    g.setColor(0.25, 0.47, 0.58, 0.22)
    g.setLineWidth(1)
    g.line(32, panelY + 0.5, width - 32, panelY + 0.5)

    -- Timeline bar with golden slow-mo peak zone
    local barX, barY, barW, barH = 48, panelY + 24, width - 96, 10
    g.setColor(0.10, 0.17, 0.24, 0.95)
    g.rectangle("fill", barX, barY, barW, barH, 4, 4)

    local slowX = barX + barW * (clip.slowPlaybackStart / clip.playbackDuration)
    local slowW = barW * ((clip.slowPlaybackEnd - clip.slowPlaybackStart) / clip.playbackDuration)
    g.setColor(1.0, 0.78, 0.26, 0.45)
    g.rectangle("fill", slowX, barY, math.max(4, slowW), barH, 3, 3)

    local progW = barW * math.max(0, math.min(1, self.playbackTime / clip.playbackDuration))
    g.setColor(0.36, 0.88, 0.84, 0.95)
    g.rectangle("fill", barX, barY, progW, barH, 4, 4)
    g.setColor(0.92, 0.98, 1, 1)
    g.circle("fill", barX + progW, barY + barH * 0.5, 6)

    -- Status line (export progress / saved path / error)
    if self.exportError then
        g.setFont(fonts.menuBody or fonts.body)
        g.setColor(1.0, 0.45, 0.42, 1)
        g.printf(self.exportError, 48, panelY + 42, width - 96, "center")
    elseif self.exportStatus then
        g.setFont(fonts.menuBody or fonts.body)
        g.setColor(0.55, 0.94, 0.80, 1)
        g.printf(self.exportStatus, 48, panelY + 42, width - 96, "center")
    end

    -- Buttons
    local buttons = self:layoutButtons(width, height)
    local mx, my = Display.getMousePosition()
    local hovered = self:buttonAt(mx, my)
    g.setFont(fonts.menuBody or fonts.body)
    for _, b in ipairs(buttons) do
        local isHover = (hovered == b.id)
        local isDisabled = (b.id == "export" and self.exporting)
        if isDisabled then
            g.setColor(0.14, 0.22, 0.26, 0.7)
        elseif isHover then
            g.setColor(0.14, 0.36, 0.38, 0.95)
        else
            g.setColor(0.066, 0.13, 0.18, 0.95)
        end
        g.rectangle("fill", b.x, b.y, b.w, b.h, 5, 5)
        if b.id == "export" then
            g.setColor(1.0, 0.80, 0.34, isHover and 1 or 0.7)
        elseif isHover then
            g.setColor(0.36, 0.86, 0.82, 1)
        else
            g.setColor(0.25, 0.43, 0.49, 0.9)
        end
        g.rectangle("line", b.x, b.y, b.w, b.h, 5, 5)
        g.setColor(0.88, 0.95, 0.98, isDisabled and 0.6 or 1)
        local ty = b.y + math.floor((b.h - g.getFont():getHeight()) * 0.5)
        g.printf(b.label, b.x, ty, b.w, "center")
    end

    g.pop()
end

return Replay
