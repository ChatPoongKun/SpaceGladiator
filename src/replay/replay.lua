local Arena = require("src.core.arena")
local Camera = require("src.core.camera")
local Display = require("src.core.display")
local Ship = require("src.combat.ship")
local Turret = require("src.combat.turret")
local Enemies = require("src.combat.enemies")
local Gladiator = require("src.combat.gladiator")
local Starfield = require("src.visual.starfield")
local StageBackground = require("src.visual.stage_background")
local BattleScene = require("src.visual.battle_scene")
local Sfx = require("src.audio.sfx")
local Bgm = require("src.audio.bgm")

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
Replay.CAP_EMBERS = 256
Replay.CAP_DEATH_BURSTS = 64
Replay.CAP_DEATH_PARTICLES = 256

-- Extensible layer registry: any subsystem or future feature can register
-- its own snapshot capture/restore hooks without modifying Replay core.
Replay.layers = {}

function Replay.registerLayer(spec)
    if not spec or not spec.id then return end
    for i = #Replay.layers, 1, -1 do
        if Replay.layers[i].id == spec.id then
            table.remove(Replay.layers, i)
        end
    end
    Replay.layers[#Replay.layers + 1] = {
        id = spec.id,
        order = spec.order or 0,
        capture = spec.capture,
        restore = spec.restore,
    }
    table.sort(Replay.layers, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
end

function Replay.unregisterLayer(id)
    for i = #Replay.layers, 1, -1 do
        if Replay.layers[i].id == id then
            table.remove(Replay.layers, i)
        end
    end
end

Replay.registerLayer({
    id = "environment",
    order = 10,
    capture = function(ctx)
        local st = ctx.stage
        local ex = ctx.extras
        local bg = ex and ex.stageBackground
        return {
            stageNumber = st and st.number or 1,
            stageLevel = (st and st.level) or (bg and bg.level) or StageBackground.DEFAULT_LEVEL,
            stageRemaining = st and st:remainingTime() or 0,
            bgU = bg and bg.u or 0,
            bgV = bg and bg.v or 0,
            bgTime = bg and bg.time or 0,
            bgmLevel = ex and ex.bgmLevel or nil,
            bgmPosition = ex and ex.bgmPosition or 0,
        }
    end,
    restore = function(s0, _, _, _, ctx)
        if not s0 then return end
        ctx.sceneState.stageNumber = s0.stageNumber or 1
        ctx.sceneState.stageLevel = s0.stageLevel or StageBackground.DEFAULT_LEVEL
        ctx.sceneState.stageRemaining = s0.stageRemaining or 0
    end,
})

Replay.registerLayer({
    id = "camera",
    order = 20,
    capture = function(ctx)
        return ctx.camera and ctx.camera:captureReplayState() or nil
    end,
    restore = function(s0, s1, alpha, _, ctx)
        ctx.sceneState.camera = Camera.buildReplayProxy(s0, s1, alpha, ctx.width, ctx.height)
    end,
})

Replay.registerLayer({
    id = "ship",
    order = 30,
    capture = function(ctx)
        return ctx.ship and ctx.ship:captureReplayState() or nil
    end,
    restore = function(s0, s1, alpha, _, ctx)
        ctx.sceneState.ship = Ship.buildReplayProxy(s0, s1, alpha)
    end,
})

Replay.registerLayer({
    id = "turret",
    order = 40,
    capture = function(ctx, caps)
        return ctx.turret and ctx.turret:captureReplayState(caps) or nil
    end,
    restore = function(s0, s1, alpha, dt, ctx)
        ctx.sceneState.turret = Turret.buildReplayProxy(s0, s1, alpha, dt)
    end,
})

Replay.registerLayer({
    id = "enemies",
    order = 50,
    capture = function(ctx, caps)
        return ctx.enemies and ctx.enemies:captureReplayState(caps) or nil
    end,
    restore = function(s0, s1, alpha, dt, ctx)
        ctx.sceneState.enemies = Enemies.buildReplayProxy(s0, s1, alpha, dt)
    end,
})

Replay.registerLayer({
    id = "gladiator",
    order = 60,
    capture = function(ctx, caps)
        return ctx.gladiator and ctx.gladiator:captureReplayState(caps) or nil
    end,
    restore = function(s0, s1, alpha, dt, ctx)
        ctx.sceneState.gladiator = Gladiator.buildReplayProxy(
            s0, s1, alpha, dt, ctx.activePopups, ctx.srcTime)
    end,
})

Replay.registerLayer({
    id = "effects",
    order = 70,
    capture = function(ctx)
        local ex = ctx.extras
        return {
            lowArmorAura = ex and ex.lowArmorAura or 0,
            hullFlashTimer = ex and ex.hullFlashTimer or 0,
            hullFlashDuration = ex and ex.hullFlashDuration or 0.34,
        }
    end,
    restore = function(s0, s1, alpha, dt, ctx)
        if not s0 then return end
        local nextS = s1 or s0
        local a0 = s0.lowArmorAura or 0
        local a1 = nextS.lowArmorAura or a0
        ctx.sceneState.lowArmorAura = a0 + (a1 - a0) * alpha
        ctx.sceneState.hullFlashTimer = math.max(0, (s0.hullFlashTimer or 0) - math.max(0, dt or 0))
        ctx.sceneState.hullFlashDuration = s0.hullFlashDuration or 0.34
    end,
})

function Replay.slowMoPitchScale(speed)
    return math.max(0.62, math.min(1.0, 0.35 + 0.65 * (speed or 1.0)))
end

function Replay.new()
    local self = setmetatable({
        frames = {},
        frameCount = 0,
        writeHead = 0,
        wrapped = false,
        accumulator = 0,
        stageTime = 0,
        pointEvents = {},
        sfxEvents = {},
        bestClip = nil,
        -- Playback state
        active = false,
        playing = false,
        focused = true,
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
    self.frames = {}
    self.frameCount = 0
    self.writeHead = 0
    self.wrapped = false
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

function Replay:recordSfxEvent(cue, pitchScale, pitch, meta)
    if not cue then return end
    if meta and meta.action == "fadeOut" then
        for i = #self.sfxEvents, 1, -1 do
            local ev = self.sfxEvents[i]
            if ev.sustained and ev.endTime == nil and ((meta.id and ev.sustainedId == meta.id) or (not meta.id and ev.cue == cue)) then
                ev.endTime = self.stageTime
                if meta.fadeOut ~= nil then
                    ev.fadeOut = meta.fadeOut
                end
                return
            end
        end
        return
    end
    local entry = {
        time = self.stageTime,
        cue = cue,
        pitchScale = pitchScale or 1.0,
        pitch = pitch,
    }
    if meta and meta.action == "start" then
        entry.sustained = true
        entry.sustainedId = meta.id
        entry.duration = meta.duration
        entry.fadeOut = meta.fadeOut
        entry.loop = meta.loop ~= false
    end
    self.sfxEvents[#self.sfxEvents + 1] = entry
end

local function buildCaps()
    return {
        enemies = Replay.CAP_ENEMIES,
        shots = Replay.CAP_SHOTS,
        impacts = Replay.CAP_IMPACTS,
        missiles = Replay.CAP_MISSILES,
        beams = Replay.CAP_BEAMS,
        explosions = Replay.CAP_EXPLOSIONS,
        bursts = Replay.CAP_BURSTS,
        sparks = Replay.CAP_SPARKS,
        embers = Replay.CAP_EMBERS,
        deathBursts = Replay.CAP_DEATH_BURSTS,
        deathParticles = Replay.CAP_DEATH_PARTICLES,
    }
end

function Replay:captureSnapshot(ship, camera, turret, enemies, gladiator, stage, extras)
    if not ship or not camera or not turret or not enemies or not gladiator then return end

    local idx = self.writeHead
    local ctx = {
        time = self.stageTime,
        ship = ship,
        camera = camera,
        turret = turret,
        enemies = enemies,
        gladiator = gladiator,
        stage = stage,
        extras = extras,
    }
    local caps = buildCaps()
    local captured = {}
    for i = 1, #Replay.layers do
        local layer = Replay.layers[i]
        if layer.capture then
            captured[layer.id] = layer.capture(ctx, caps)
        end
    end

    self.frames[idx] = {
        time = self.stageTime,
        layers = captured,
    }

    self.writeHead = (idx + 1) % Replay.MAX_FRAMES
    if self.frameCount < Replay.MAX_FRAMES then
        self.frameCount = self.frameCount + 1
    else
        self.wrapped = true
    end
end

function Replay:recordFrame(dt, ship, camera, turret, enemies, gladiator, stage, extras)
    if dt <= 0 then return end
    self.stageTime = self.stageTime + dt
    if self.frameCount == 0 then
        self:captureSnapshot(ship, camera, turret, enemies, gladiator, stage, extras)
        self.accumulator = 0
        return
    end
    self.accumulator = self.accumulator + dt
    if self.accumulator >= Replay.SAMPLE_DT then
        self.accumulator = self.accumulator - Replay.SAMPLE_DT
        if self.accumulator > Replay.SAMPLE_DT then
            self.accumulator = 0
        end
        self:captureSnapshot(ship, camera, turret, enemies, gladiator, stage, extras)
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
        local u = r * (-1 + math.sqrt(1 + 4 * dsUp / r))
        return pre + r + h + u, 0.5 + 0.5 * (u / r)
    end

    return math.min(clip.playbackDuration, clip.slowPlaybackEnd + (s - clip.slowEnd)), 1.0
end

function Replay:getOrderedFrame(orderIndex)
    local startIdx = self.wrapped and self.writeHead or 0
    local realIdx = (startIdx + orderIndex) % Replay.MAX_FRAMES
    return self.frames[realIdx]
end

function Replay:extractClip(window)
    local frames = {}
    local padLo = window.clipStart - Replay.SAMPLE_DT * 2
    local padHi = window.clipEnd + Replay.SAMPLE_DT * 2

    for i = 0, self.frameCount - 1 do
        local f = self:getOrderedFrame(i)
        if f and f.time >= padLo and f.time <= padHi then
            frames[#frames + 1] = f
        end
    end

    if #frames == 0 then return nil end

    local clipPoints = {}
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
        if ev.sustained then
            local rawEnd = ev.endTime or (ev.duration and (ev.time + ev.duration)) or ev.time
            local evEnd = math.max(ev.time, rawEnd)
            if evEnd >= window.clipStart - 0.02 and ev.time <= window.clipEnd + 0.02 then
                local clampedStart = math.max(window.clipStart, math.min(window.clipEnd, ev.time))
                local clampedEnd = math.max(clampedStart, math.min(window.clipEnd, evEnd))
                local pbTime, speed = Replay.mapSourceTime(window, clampedStart)
                local endPbTime = Replay.mapSourceTime(window, clampedEnd)
                clipSfx[#clipSfx + 1] = {
                    sourceTime = clampedStart,
                    playbackTime = pbTime,
                    speed = speed,
                    cue = ev.cue,
                    pitchScale = ev.pitchScale or 1.0,
                    pitch = ev.pitch,
                    sustained = true,
                    sustainedDuration = math.max(0, endPbTime - pbTime),
                    fadeOut = ev.fadeOut,
                    loop = ev.loop ~= false,
                }
            end
        elseif ev.time >= window.clipStart - 0.02 and ev.time <= window.clipEnd + 0.02 then
            local pbTime, speed = Replay.mapSourceTime(window, ev.time)
            clipSfx[#clipSfx + 1] = {
                sourceTime = ev.time,
                playbackTime = pbTime,
                speed = speed,
                cue = ev.cue,
                pitchScale = ev.pitchScale or 1.0,
                pitch = ev.pitch,
            }
        end
    end
    table.sort(clipSfx, function(a, b) return a.playbackTime < b.playbackTime end)

    -- Pick environment/BGM anchor closest to clipStart
    local refFrame = frames[1]
    for i = 1, #frames do
        if frames[i].time >= window.clipStart - 1e-6 then
            refFrame = frames[i]
            break
        end
    end
    local env = refFrame.layers and refFrame.layers.environment
    local firstEnv = frames[1].layers and frames[1].layers.environment
    local gladEnv = frames[1].layers and frames[1].layers.gladiator
    local bgmOffset = env and env.bgmPosition or 0
    if env and refFrame.time then
        bgmOffset = math.max(0, bgmOffset + (window.clipStart - refFrame.time))
    end

    window.frames = frames
    window.pointEvents = clipPoints
    window.sfxEvents = clipSfx
    window.startTotal = (gladEnv and gladEnv.total) or 0
    window.stageNumber = (env and env.stageNumber) or (firstEnv and firstEnv.stageNumber) or 1
    window.level = (env and env.stageLevel) or (firstEnv and firstEnv.stageLevel) or StageBackground.DEFAULT_LEVEL
    window.bgU = (env and env.bgU) or 0
    window.bgV = (env and env.bgV) or 0
    window.bgTime = (env and env.bgTime) or 0
    window.bgmLevel = env and env.bgmLevel or nil
    window.bgmOffset = bgmOffset
    return window
end

function Replay:finalizeStage()
    if self.frameCount < 2 or #self.pointEvents == 0 then
        self:resetStage()
        return nil
    end

    local firstF = self:getOrderedFrame(0)
    local lastF = self:getOrderedFrame(self.frameCount - 1)
    if not firstF or not lastF then
        self:resetStage()
        return nil
    end
    local window = Replay.selectHighlightWindow(self.pointEvents, firstF.time, lastF.time)
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

local function syncBackgroundToClip(bgObj, clip)
    if not bgObj or not clip then return end
    bgObj:setLevel(clip.level or StageBackground.DEFAULT_LEVEL, true)
    bgObj.u = clip.bgU or 0
    bgObj.v = clip.bgV or 0
    bgObj.time = clip.bgTime or 0
end

function Replay.syncBackgroundToClip(bgObj, clip)
    syncBackgroundToClip(bgObj, clip)
end

function Replay:startClipBgm(speed)
    local clip = self.bestClip
    if not clip or not self.focused then return end
    if clip.bgmLevel and Bgm.hasTrack and Bgm.hasTrack(clip.bgmLevel) then
        Bgm.playForLevel(clip.bgmLevel, {
            restart = true,
            seek = clip.bgmOffset or 0,
            pitch = Replay.slowMoPitchScale(speed or 1.0),
        })
    end
end

function Replay:openPlayback(width, height, opts)
    if not self:hasHighlight() then return false end
    self.active = true
    self.playing = true
    self.focused = not (opts and opts.focused == false)
    self.playbackTime = 0
    self.nextSfxIndex = 1
    self.exportStatus = nil
    self.exportError = nil
    local clip = self.bestClip
    if love and love.graphics then
        local _, _, vpW, vpH = Display.viewportRect()
        local bgW = width or vpW or Display.VIRTUAL_WIDTH
        local bgH = height or vpH or Display.VIRTUAL_HEIGHT
        self.stars = Starfield.new(bgW, bgH)
        self.stageBackground = StageBackground.new(bgW, bgH, {
            level = clip.level or StageBackground.DEFAULT_LEVEL,
        })
        syncBackgroundToClip(self.stageBackground, clip)
    end
    Sfx.stop()
    Bgm.stop()
    self:startClipBgm(1.0)
    return true
end

function Replay:setFocused(isFocused)
    self.focused = isFocused == true
    if not self.active or not self:hasHighlight() then return end
    local clip = self.bestClip
    if not self.focused then
        Sfx.stop()
        if clip.bgmLevel then Bgm.pause() end
    elseif self.playing then
        if clip.bgmLevel and Bgm.hasTrack and Bgm.hasTrack(clip.bgmLevel) then
            local _, speed = Replay.mapPlaybackTime(clip, self.playbackTime)
            if Bgm.isPaused and Bgm.isPaused(clip.bgmLevel) then
                Bgm.setPitch(Replay.slowMoPitchScale(speed))
                Bgm.resume()
            else
                self:startClipBgm(speed)
            end
        end
    end
end

function Replay:restartPlayback()
    if not self:hasHighlight() then return end
    self.playbackTime = 0
    self.nextSfxIndex = 1
    self.playing = true
    syncBackgroundToClip(self.stageBackground, self.bestClip)
    Sfx.stop()
    Bgm.stop()
    self:startClipBgm(1.0)
end

function Replay:togglePlay()
    if not self:hasHighlight() then return end
    if self.playbackTime >= self.bestClip.playbackDuration - 1e-3 then
        self:restartPlayback()
        return
    end
    self.playing = not self.playing
    if not self.playing then
        Sfx.stop()
        Bgm.pause()
    elseif self.focused then
        local _, speed = Replay.mapPlaybackTime(self.bestClip, self.playbackTime)
        if self.bestClip.bgmLevel and Bgm.isPaused and Bgm.isPaused(self.bestClip.bgmLevel) then
            Bgm.setPitch(Replay.slowMoPitchScale(speed))
            Bgm.resume()
        else
            self:startClipBgm(speed)
        end
    end
end

function Replay:closePlayback()
    self.active = false
    self.playing = false
    Sfx.stop()
    Bgm.stop()
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

    -- Trigger SFX events using exact in-game Sfx voice pool, volume, and recorded pitch
    local sfxEvents = clip.sfxEvents or {}
    while self.nextSfxIndex <= #sfxEvents and sfxEvents[self.nextSfxIndex].playbackTime <= self.playbackTime do
        local ev = sfxEvents[self.nextSfxIndex]
        if ev.playbackTime >= prevPb - 0.05 then
            local speedScale = Replay.slowMoPitchScale(ev.speed)
            if ev.sustained and Sfx.playReplaySustained then
                Sfx.playReplaySustained(ev.cue, ev.pitch, speedScale, {
                    duration = ev.sustainedDuration or 0,
                    fadeOut = ev.fadeOut,
                    loop = ev.loop ~= false,
                })
            elseif Sfx.playReplay then
                Sfx.playReplay(ev.cue, ev.pitch, speedScale)
            elseif Sfx.playWithPitchScale then
                Sfx.playWithPitchScale(ev.cue, (ev.pitchScale or 1.0) * speedScale)
            else
                Sfx.play(ev.cue)
            end
        end
        self.nextSfxIndex = self.nextSfxIndex + 1
    end

    if Sfx.update then
        Sfx.update(dt)
    end

    if self.playbackTime >= clip.playbackDuration then
        self.playbackTime = 0
        self.nextSfxIndex = 1
        syncBackgroundToClip(self.stageBackground, clip)
        Sfx.stop()
        Bgm.stop()
        self:startClipBgm(1.0)
    end

    local srcTime, speed = Replay.mapPlaybackTime(clip, self.playbackTime)
    if self.focused and clip.bgmLevel then
        Bgm.setPitch(Replay.slowMoPitchScale(speed))
    end

    if self.stars or self.stageBackground then
        local f0, f1, alpha = Replay.sampleClipFrame(clip, srcTime)
        local l0 = f0.layers and f0.layers.ship
        local l1 = f1.layers and f1.layers.ship
        local shipProxy = Ship.buildReplayProxy(l0, l1, alpha)
        local bgScale = Display.scale or 1
        local _, _, vpW, vpH = Display.viewportRect()
        local bgW = width or vpW or Display.VIRTUAL_WIDTH
        local bgH = height or vpH or Display.VIRTUAL_HEIGHT
        BattleScene.updateEnvironment(dt * speed, {
            ship = shipProxy,
            stageBackground = self.stageBackground,
            stars = self.stars,
        }, bgW, bgH, { scale = bgScale })
    end
end

function Replay.buildSceneState(clip, playbackTime, width, height)
    local srcTime, speed = Replay.mapPlaybackTime(clip, playbackTime)
    local f0, f1, alpha = Replay.sampleClipFrame(clip, srcTime)
    local dt = math.max(0, srcTime - f0.time)

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

    local sceneState = {}
    local ctx = {
        clip = clip,
        playbackTime = playbackTime,
        srcTime = srcTime,
        speed = speed,
        width = width,
        height = height,
        activePopups = activePopups,
        gainedSoFar = gainedSoFar,
        sceneState = sceneState,
    }

    local l0 = f0.layers or {}
    local l1 = f1.layers or {}
    for i = 1, #Replay.layers do
        local layer = Replay.layers[i]
        if layer.restore then
            layer.restore(l0[layer.id], l1[layer.id], alpha, dt, ctx)
        end
    end

    return sceneState, srcTime, speed, gainedSoFar
end

-- Renders a single replay frame at `playbackTime` into the current graphics target
-- using the exact same BattleScene pipeline as live combat.
function Replay.renderClipFrame(clip, playbackTime, width, height, fonts, starsObj, forExport, bgObj)
    local g = love.graphics
    local sceneState, srcTime, speed, gainedSoFar = Replay.buildSceneState(clip, playbackTime, width, height)

    local vpX, vpY, vpW, vpH = 0, 0, width, height
    if not forExport then
        vpX, vpY, vpW, vpH = Display.viewportRect()
    end

    BattleScene.drawBackground({
        stageBackground = bgObj,
        stars = starsObj,
        camera = sceneState.camera,
    }, { x = vpX, y = vpY, w = vpW, h = vpH })

    g.push("all")
    if not forExport then
        Display.applyTransform()
    end

    BattleScene.drawWorld(sceneState, width, height, srcTime)
    BattleScene.drawScreenEffects(sceneState, width, height, srcTime, fonts)

    -- Top Replay Telemetry Bar
    local gladProxy = sceneState.gladiator
    g.push("all")
    g.setColor(0.018, 0.028, 0.055, 0.78)
    g.rectangle("fill", 0, 0, width, 96)
    g.setColor(0.25, 0.47, 0.58, 0.22)
    g.setLineWidth(1)
    g.line(32, 95, width - 32, 95)

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

    local cx = math.floor(width / 2) - 130
    g.setFont(fonts.small)
    if gladProxy and gladProxy.feverActive then
        g.setColor(1.0, 0.86, 0.36, 1)
        g.printf("FEVER TIME x2", cx, 18, 260, "center")
    else
        g.setColor(0.60, 0.74, 0.84, 1)
        g.printf("GLADIATOR POINTS", cx, 18, 260, "center")
    end
    g.setFont(fonts.title)
    g.setColor(1.0, 0.90, 0.50, 1)
    g.printf(string.format("%04d", gladProxy and gladProxy.total or 0), cx, 34, 260, "center")
    g.setFont(fonts.small)
    g.setColor(0.42, 0.92, 0.82, 0.95)
    g.printf(string.format("HIGHLIGHT +%d PTS", gainedSoFar), cx, 70, 260, "center")

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
