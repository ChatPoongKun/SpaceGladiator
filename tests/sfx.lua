-- Verification test for SFX asset files, voice pooling, throttle, and pitch scaling.
-- Runnable via `luajit tests/sfx.lua`.

package.path = "./?.lua;./?/init.lua;" .. package.path
local Sfx = require("sfx")

-- 1. Verify every cue maps to an existing, valid RIFF/WAVE file in assets/audio/
local checkedAssets = {}
local cueCount = 0
for name, cue in pairs(Sfx.cues) do
    cueCount = cueCount + 1
    local asset = cue[1]
    if not checkedAssets[asset] then
        local path = "assets/audio/" .. asset .. ".wav"
        local f = assert(io.open(path, "rb"), "Missing audio asset for cue " .. name .. ": " .. path)
        local header = f:read(12)
        f:close()
        assert(header and header:sub(1, 4) == "RIFF" and header:sub(9, 12) == "WAVE",
            "Invalid WAV header in " .. path)
        checkedAssets[asset] = true
    end
end
assert(cueCount >= 20, "Expected full SFX cue roster")

-- 2. Exercise Sfx.load, voice pooling, pitchScale, throttle, and Sfx.stop with mock love.audio
local fakeTime = 1.0
local plays = 0
local lastPitch = nil
local function makeSource(path)
    local s = { path = path, volume = 1, pitch = 1 }
    function s:clone() return makeSource(self.path) end
    function s:setVolume(v) self.volume = v end
    function s:setPitch(p) self.pitch = p; lastPitch = p end
    function s:stop() end
    function s:play() plays = plays + 1 end
    return s
end

_G.love = {
    audio = { newSource = function(path) return makeSource(path) end },
    timer = { getTime = function() return fakeTime end },
}

Sfx.load()
Sfx.play("plinko_slot", 1.25)
assert(plays == 1 and lastPitch >= 1.15 and lastPitch <= 1.35, "Pitch scale must apply cleanly")

-- Retrigger within minInterval (0.03s) should be throttled
fakeTime = fakeTime + 0.005
Sfx.play("plinko_slot", 1.25)
assert(plays == 1, "Rapid retrigger inside minInterval must be throttled")

-- After minInterval elapses, next voice in pool plays
fakeTime = fakeTime + 0.05
Sfx.play("plinko_slot", 1.35)
assert(plays == 2)

Sfx.stop()
_G.love = nil

print("PASS: All " .. cueCount .. " SFX cues verified with valid WAV assets, voice pooling, throttle, and pitch scaling")
