local Sfx = {}
Sfx.SUSTAINED_FADE_OUT = 0.08
local pools = {}
local lastPlayed = {}
local sustainedStates = {}
local nextSustainedId = 0
local listener = nil
local muted = false

-- Cue format: { asset, volume, basePitch, voices, minInterval, jitter }
local cues = {
    -- Combat (upgraded & separated)
    projectile      = { "projectile",   0.48, 1.00, 3, 0.03, 0.04 },
    missile         = { "rocket",       0.64, 1.00, 3, 0.04, 0.04 },
    laser           = { "laser",        0.54, 1.00, 2, 0.04, 0.03 },
    enemyProjectile = { "projectile",   0.22, 1.24, 3, 0.05, 0.05 },
    enemyLaser      = { "laser",        0.30, 0.82, 2, 0.06, 0.03 },
    impact          = { "impact",       0.68, 1.00, 3, 0.03, 0.06 },
    impact_projectile = { "impact_projectile", 0.56, 1.00, 4, 0.025, 0.07 },
    impact_missile    = { "impact_missile",    0.72, 1.00, 4, 0.035, 0.05 },
    impact_laser      = { "impact_laser",      0.50, 1.00, 3, 0.04, 0.06 },
    player_hit_shield = { "player_hit_shield", 0.72, 1.00, 3, 0.04, 0.04 },
    player_hit_armor  = { "player_hit_armor",  0.82, 1.00, 2, 0.05, 0.03 },
    player_hit_hull   = { "player_hit_hull",   0.92, 1.00, 2, 0.05, 0.02 },
    low_shield        = { "low_shield",        0.58, 1.00, 1, 0.40, 0.00 },
    low_armor         = { "low_armor",         0.68, 1.00, 1, 0.50, 0.00 },
    boost           = { "boost",        0.60, 1.00, 1, 0.08, 0.02 },
    ship_destroy    = { "ship_destroy", 0.82, 1.00, 1, 0.10, 0.00 },
    enemy_destroy   = { "enemy_destroy",0.72, 1.00, 4, 0.035, 0.08 },

    -- Gladiator / Stage feel
    evasion         = { "evasion",      0.56, 1.00, 3, 0.05, 0.05 },
    fever_start     = { "fever_start",  0.76, 1.00, 1, 0.20, 0.00 },
    stage_clear     = { "stage_clear",  0.72, 1.00, 1, 0.20, 0.00 },
    shutter_close   = { "shutter_close",0.68, 1.00, 1, 0.15, 0.00 },
    shutter_open    = { "shutter_open", 0.62, 1.00, 1, 0.15, 0.00 },
    warp_jump       = { "warp_jump",    0.76, 1.00, 1, 0.20, 0.00 },
    warp_arrive     = { "warp_arrive",  0.68, 1.00, 1, 0.20, 0.00 },

    -- UI interaction
    ui_hover        = { "ui_hover",     0.38, 1.00, 2, 0.03, 0.02 },
    ui_click        = { "ui_click",     0.54, 1.00, 2, 0.03, 0.02 },
    ui_equip        = { "ui_equip",     0.60, 1.00, 2, 0.04, 0.03 },
    ui_error        = { "ui_error",     0.54, 1.00, 1, 0.06, 0.00 },
}

Sfx.cues = cues

local function now()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.clock()
end

function Sfx.assetPath(asset)
    if not asset then return nil end
    return "assets/audio/" .. asset .. ".wav"
end

function Sfx.load()
    if not (love and love.audio) then return end
    pools = {}
    lastPlayed = {}
    sustainedStates = {}
    nextSustainedId = 0
    local loaded = {}
    for name, cue in pairs(cues) do
        local asset, volume, basePitch, voices = cue[1], cue[2], cue[3] or 1, cue[4] or 1
        local base = loaded[asset]
        if not base then
            base = love.audio.newSource(Sfx.assetPath(asset), "static")
            loaded[asset] = base
        end
        local list = {}
        for i = 1, voices do
            local src = base:clone()
            src:setVolume(volume)
            src:setPitch(basePitch)
            list[i] = src
        end
        pools[name] = { list = list, cursor = 1, cue = cue }
    end
end

function Sfx.getCues()
    return cues
end

function Sfx.getCueSpec(name)
    local cue = name and cues[name] or nil
    if not cue then return nil end
    return {
        name = name,
        asset = cue[1],
        path = Sfx.assetPath(cue[1]),
        volume = cue[2] or 0.6,
        basePitch = cue[3] or 1.0,
        voices = cue[4] or 1,
        minInterval = cue[5] or 0,
        jitter = cue[6] or 0,
    }
end

function Sfx.setListener(fn)
    listener = fn
end

function Sfx.setMuted(value)
    muted = value == true
end

function Sfx.isMuted()
    return muted
end

local function computePitch(cue, pitchScale, opts)
    local effectiveScale = pitchScale or 1
    local basePitch = cue[3] or 1
    local jitter = (opts and opts.noJitter) and 0 or (cue[6] or 0)
    local offset = jitter > 0 and ((math.random() * 2 - 1) * jitter) or 0
    local pitch
    if opts and opts.exactPitch then
        pitch = math.max(0.35, opts.exactPitch * effectiveScale)
    else
        pitch = math.max(0.35, (basePitch + offset) * effectiveScale)
    end
    return effectiveScale, pitch
end

local function stopSourceImmediately(source)
    if not source then return end
    source:setVolume(0)
    source:stop()
    if source.setLooping then source:setLooping(false) end
end

local function playCue(name, pitchScale, notify, opts)
    if muted then return end
    local pool = pools[name]
    local cue = (pool and pool.cue) or cues[name]
    if not cue then return end

    if pool then
        local minInterval = cue[5] or 0
        local t = now()
        if minInterval > 0 and lastPlayed[name] and (t - lastPlayed[name]) < minInterval then
            return
        end
        lastPlayed[name] = t
    end

    local effectiveScale, pitch = computePitch(cue, pitchScale, opts)

    if notify and listener then
        listener(name, effectiveScale, pitch)
    end
    if not pool then return end

    local list = pool.list
    local activeState = sustainedStates[name]
    local activeSrc = activeState and activeState.source or nil
    local source = list[pool.cursor]
    pool.cursor = (pool.cursor % #list) + 1
    if activeSrc and source == activeSrc and #list > 1 then
        source = list[pool.cursor]
        pool.cursor = (pool.cursor % #list) + 1
    end
    if activeSrc and source == activeSrc then
        sustainedStates[name] = nil
    end

    if source.setLooping then source:setLooping(false) end
    source:setVolume(cue[2] or 0.6)
    source:setPitch(pitch)
    source:stop()
    source:play()
end

function Sfx.play(name, pitchScale)
    playCue(name, pitchScale, true)
end

function Sfx.playWithPitchScale(name, pitchScale)
    playCue(name, pitchScale, false)
end

function Sfx.playReplay(name, recordedPitch, speedPitchScale)
    playCue(name, speedPitchScale or 1, false, {
        exactPitch = recordedPitch,
        noJitter = true,
    })
end

function Sfx.startSustained(name, opts)
    if muted then return nil end
    local pool = pools[name]
    local cue = (pool and pool.cue) or cues[name]
    if not cue then return nil end

    local fadeOut = (opts and opts.fadeOut ~= nil) and opts.fadeOut or Sfx.SUSTAINED_FADE_OUT
    local handle = { cue = name, fadeOut = fadeOut }
    local existing = sustainedStates[name]

    if existing and existing.activeCount > 0 and not existing.fading then
        existing.activeHandles[handle] = true
        existing.activeCount = existing.activeCount + 1
        existing.currentVolume = existing.baseVolume
        if existing.source then
            if existing.source.setLooping then existing.source:setLooping(existing.loop) end
            existing.source:setVolume(existing.baseVolume)
            if existing.source.isPlaying and not existing.source:isPlaying() then
                existing.source:play()
            end
        end
        return handle
    end

    local source = nil
    if pool and #pool.list > 0 then
        if existing and existing.source then
            source = existing.source
        else
            source = pool.list[pool.cursor]
            pool.cursor = (pool.cursor % #pool.list) + 1
        end
    end

    local effectiveScale, pitch = computePitch(cue, opts and opts.pitchScale, opts)
    local baseVolume = cue[2] or 0.6
    local loop = not (opts and opts.loop == false)
    local autoFade = (opts and opts.autoFade) == true
    local notify = not (opts and opts.notify == false)

    nextSustainedId = nextSustainedId + 1
    local state = {
        id = nextSustainedId,
        cueName = name,
        source = source,
        baseVolume = baseVolume,
        currentVolume = baseVolume,
        activeHandles = { [handle] = true },
        activeCount = 1,
        fading = false,
        fadeElapsed = 0,
        fadeDuration = fadeOut,
        fadeStartVolume = baseVolume,
        timedRemaining = autoFade and (opts and opts.duration or 0) or nil,
        loop = loop,
        notify = notify,
    }
    sustainedStates[name] = state

    if source then
        source:stop()
        if source.setLooping then source:setLooping(loop) end
        source:setVolume(baseVolume)
        source:setPitch(pitch)
        source:play()
    end

    if notify and listener then
        listener(name, effectiveScale, pitch, {
            action = "start",
            id = state.id,
            duration = opts and opts.duration,
            fadeOut = fadeOut,
            loop = loop,
        })
    end
    return handle
end

function Sfx.stopSustained(handle, fadeOut)
    if not handle or not handle.cue then return end
    local state = sustainedStates[handle.cue]
    if not state or not state.activeHandles[handle] then return end

    state.activeHandles[handle] = nil
    state.activeCount = math.max(0, state.activeCount - 1)
    if state.activeCount > 0 then return end

    local fade = (fadeOut ~= nil) and fadeOut or handle.fadeOut or state.fadeDuration or Sfx.SUSTAINED_FADE_OUT
    if state.notify and listener then
        listener(state.cueName, 1, nil, {
            action = "fadeOut",
            id = state.id,
            fadeOut = fade,
        })
    end

    if fade <= 0 or not state.source then
        stopSourceImmediately(state.source)
        sustainedStates[state.cueName] = nil
        return
    end

    state.fading = true
    state.fadeElapsed = 0
    state.fadeDuration = fade
    state.fadeStartVolume = state.currentVolume or state.baseVolume
end

function Sfx.playReplaySustained(name, recordedPitch, speedPitchScale, opts)
    return Sfx.startSustained(name, {
        pitchScale = speedPitchScale or 1,
        exactPitch = recordedPitch,
        noJitter = true,
        duration = opts and opts.duration or 0,
        fadeOut = opts and opts.fadeOut,
        loop = not (opts and opts.loop == false),
        autoFade = true,
        notify = false,
    })
end

function Sfx.update(dt)
    if not dt or dt <= 0 then return end
    for name, state in pairs(sustainedStates) do
        if not state.fading and state.timedRemaining ~= nil then
            state.timedRemaining = state.timedRemaining - dt
            if state.timedRemaining <= 0 then
                state.timedRemaining = nil
                state.activeHandles = {}
                state.activeCount = 0
                local fade = state.fadeDuration or Sfx.SUSTAINED_FADE_OUT
                if fade <= 0 or not state.source then
                    stopSourceImmediately(state.source)
                    sustainedStates[name] = nil
                else
                    state.fading = true
                    state.fadeElapsed = 0
                    state.fadeDuration = fade
                    state.fadeStartVolume = state.currentVolume or state.baseVolume
                end
            end
        end
        if sustainedStates[name] == state and state.fading then
            state.fadeElapsed = state.fadeElapsed + dt
            local t = math.min(1, state.fadeElapsed / math.max(1e-6, state.fadeDuration))
            local nextVol = state.fadeStartVolume * (1 - t)
            state.currentVolume = nextVol
            if state.source then
                state.source:setVolume(nextVol)
            end
            if t >= 1 or nextVol <= 1e-4 then
                stopSourceImmediately(state.source)
                sustainedStates[name] = nil
            end
        end
    end
end

function Sfx.stop(opts)
    local except = opts and opts.except or nil
    for name, pool in pairs(pools) do
        if not (except and except[name]) then
            lastPlayed[name] = nil
            for _, source in ipairs(pool.list) do
                source:stop()
                if source.setLooping then source:setLooping(false) end
            end
        end
    end
    for name, state in pairs(sustainedStates) do
        if not (except and except[name]) then
            stopSourceImmediately(state.source)
            sustainedStates[name] = nil
        end
    end
    if not except then
        lastPlayed = {}
        sustainedStates = {}
    end
end

return Sfx
