-- Level background music (BGM) controller.
-- Plays the matching level track during active combat screens and keeps
-- non-combat screens (such as Plinko, title, transitions, and menus) silent.

local Bgm = {}

Bgm.LEVEL_PATHS = {
    [1] = "assets/audio/BGM/BGM_Level_1.mp3",
}
Bgm.DEFAULT_VOLUME = 0.45

local tracks = {}
local currentLevel = nil
local playing = false
local paused = false
local volume = Bgm.DEFAULT_VOLUME

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

function Bgm.load()
    Bgm.stop()
    tracks = {}
    if not (love and love.audio and love.audio.newSource) then return end
    for level, path in pairs(Bgm.LEVEL_PATHS) do
        local ok, src = pcall(love.audio.newSource, path, "stream")
        if ok and src then
            if src.setLooping then src:setLooping(true) end
            if src.setVolume then src:setVolume(volume) end
            tracks[level] = src
        end
    end
end

function Bgm.hasTrack(level)
    return level ~= nil and tracks[level] ~= nil
end

function Bgm.getVolume()
    return volume
end

function Bgm.setVolume(nextVolume)
    if type(nextVolume) ~= "number" or nextVolume ~= nextVolume then return end
    volume = clamp(nextVolume, 0, 1)
    for _, src in pairs(tracks) do
        if src.setVolume then src:setVolume(volume) end
    end
end

function Bgm.playForLevel(level, opts)
    opts = opts or {}
    local track = level and tracks[level] or nil
    if not track then
        Bgm.stop()
        return false
    end

    if currentLevel and currentLevel ~= level then
        local prev = tracks[currentLevel]
        if prev and prev.stop then prev:stop() end
        playing = false
        paused = false
    end

    if currentLevel == level and playing and not opts.restart then
        if track.isPlaying and not track:isPlaying() and track.play then
            track:play()
        end
        return true
    end

    if opts.restart or not (currentLevel == level and paused) then
        if track.stop then track:stop() end
    end

    if track.setLooping then track:setLooping(true) end
    if track.setVolume then track:setVolume(volume) end
    if track.play then track:play() end

    currentLevel = level
    playing = true
    paused = false
    return true
end

function Bgm.pause()
    if not (currentLevel and playing) then return end
    local track = tracks[currentLevel]
    if track and track.pause then
        track:pause()
    end
    playing = false
    paused = true
end

function Bgm.resume()
    if not (currentLevel and paused) then return false end
    local track = tracks[currentLevel]
    if not track then
        Bgm.stop()
        return false
    end
    if track.setLooping then track:setLooping(true) end
    if track.setVolume then track:setVolume(volume) end
    if track.play then track:play() end
    playing = true
    paused = false
    return true
end

function Bgm.stop()
    for _, track in pairs(tracks) do
        if track.stop then track:stop() end
    end
    currentLevel = nil
    playing = false
    paused = false
end

function Bgm.isPlaying(level)
    if level ~= nil then
        return playing and currentLevel == level
    end
    return playing
end

function Bgm.isPaused(level)
    if level ~= nil then
        return paused and currentLevel == level
    end
    return paused
end

function Bgm.getCurrentLevel()
    return currentLevel
end

-- Synchronizes BGM state to the active game screen and stage level.
-- Active combat ("playing") plays the level's BGM; overlay screens opened from
-- combat ("pause", "settings", "inventory") pause it; Plinko and all other
-- non-combat screens stop it.
function Bgm.syncScreen(screen, stageLevel, opts)
    opts = opts or {}
    local isFocused = (opts.focused ~= false)
    if screen == "playing" then
        if not stageLevel or not tracks[stageLevel] then
            Bgm.stop()
            return false
        end
        if not isFocused then
            if currentLevel == stageLevel and playing then
                Bgm.pause()
            elseif currentLevel ~= stageLevel then
                Bgm.stop()
            end
            return false
        end
        return Bgm.playForLevel(stageLevel, { restart = opts.restart })
    elseif screen == "pause" or screen == "settings" or screen == "inventory" then
        Bgm.pause()
        return false
    else
        Bgm.stop()
        return false
    end
end

return Bgm
