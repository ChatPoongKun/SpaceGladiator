local Sfx = {}
local sources = {}
local cues = {
    projectile = {"rocket", 0.52, 1.30},
    missile = {"rocket", 0.65},
    laser = {"laser", 0.55},
    enemyProjectile = {"rocket", 0.24, 1.46},
    enemyMissile = {"rocket", 0.37, 0.86},
    enemyLaser = {"laser", 0.32, 0.84},
    impact = {"impact", 0.70},
    boost = {"boost", 0.62},
}

function Sfx.load()
    if not love.audio then return end
    local loaded = {}
    for name, cue in pairs(cues) do
        local asset, volume, pitch = unpack(cue)
        local source = loaded[asset]
        if source then
            source = source:clone()
        else
            source = love.audio.newSource("assets/audio/" .. asset .. ".wav", "static")
            loaded[asset] = source
        end
        source:setVolume(volume)
        source:setPitch(pitch or 1)
        sources[name] = source
    end
end

function Sfx.play(name)
    local source = sources[name]
    if source then
        -- Reuse one voice per cue so simultaneous hits cannot stack the same sample.
        source:stop()
        source:play()
    end
end

function Sfx.stop()
    for _, source in pairs(sources) do source:stop() end
end

return Sfx
