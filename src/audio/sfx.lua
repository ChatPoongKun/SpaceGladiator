local Sfx = {}
local pools = {}
local lastPlayed = {}
local listener = nil

-- Cue format: { asset, volume, basePitch, voices, minInterval, jitter }
local cues = {
    -- Combat (upgraded & separated)
    projectile      = { "projectile",   0.48, 1.00, 3, 0.03, 0.04 },
    missile         = { "rocket",       0.64, 1.00, 3, 0.04, 0.04 },
    laser           = { "laser",        0.54, 1.00, 2, 0.04, 0.03 },
    enemyProjectile = { "projectile",   0.22, 1.24, 3, 0.05, 0.05 },
    enemyMissile    = { "rocket",       0.34, 0.86, 2, 0.06, 0.04 },
    enemyLaser      = { "laser",        0.30, 0.82, 2, 0.06, 0.03 },
    impact          = { "impact",       0.68, 1.00, 3, 0.03, 0.06 },
    player_hit      = { "player_hit",   0.74, 1.00, 2, 0.05, 0.03 },
    boost           = { "boost",        0.60, 1.00, 1, 0.08, 0.02 },
    ship_destroy    = { "ship_destroy", 0.82, 1.00, 1, 0.10, 0.00 },

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

    -- Plinko machine
    plinko_drop     = { "plinko_drop",  0.58, 1.00, 2, 0.06, 0.04 },
    plinko_peg      = { "plinko_peg",   0.34, 1.00, 6, 0.025, 0.09 },
    plinko_slot     = { "plinko_slot",  0.52, 1.00, 4, 0.03, 0.03 },
    plinko_claim    = { "plinko_claim", 0.78, 1.00, 2, 0.08, 0.00 },
}

Sfx.cues = cues

local function now()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.clock()
end

function Sfx.load()
    if not (love and love.audio) then return end
    pools = {}
    lastPlayed = {}
    local loaded = {}
    for name, cue in pairs(cues) do
        local asset, volume, basePitch, voices = cue[1], cue[2], cue[3] or 1, cue[4] or 1
        local base = loaded[asset]
        if not base then
            base = love.audio.newSource("assets/audio/" .. asset .. ".wav", "static")
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

function Sfx.setListener(fn)
    listener = fn
end

local function playCue(name, pitchScale, notify)
    if notify and listener then listener(name) end
    local pool = pools[name]
    if not pool then return end
    local cue = pool.cue
    local minInterval = cue[5] or 0
    local t = now()
    if minInterval > 0 and lastPlayed[name] and (t - lastPlayed[name]) < minInterval then
        return
    end
    lastPlayed[name] = t

    local list = pool.list
    local source = list[pool.cursor]
    pool.cursor = (pool.cursor % #list) + 1

    local basePitch = cue[3] or 1
    local jitter = cue[6] or 0
    local offset = jitter > 0 and ((math.random() * 2 - 1) * jitter) or 0
    local pitch = math.max(0.35, (basePitch + offset) * (pitchScale or 1))
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

function Sfx.stop()
    for _, pool in pairs(pools) do
        for _, source in ipairs(pool.list) do
            source:stop()
        end
    end
end

return Sfx
