local function runTests(Replay, ReplayExport)
    Replay = Replay or require("replay")
    ReplayExport = ReplayExport or require("replay_export")

    local function approx(a, b, eps)
        return math.abs(a - b) <= (eps or 1e-3)
    end

    -- 1. Below MIN_PEAK_RATE (30 base pts/s) threshold => no highlight (including Fever x2 50 awarded = 25 base)
    do
        local events = {
            { time = 5.0, category = "destroy", points = 10, x = 100, y = 100, fever = false },
            { time = 5.4, category = "missileDodge", points = 15, x = 120, y = 110, fever = false },
            { time = 12.0, category = "destroy", points = 50, x = 200, y = 200, fever = true },
        }
        local win = Replay.selectHighlightWindow(events, 0, 20)
        assert(win == nil, "Expected nil highlight when base peak rate < 30 pts/s (even with Fever x2 50 awarded)")
    end

    -- 1b. Non-Fever 30 pts (base 30) must beat Fever x2 50 pts (base 25)
    do
        local events = {
            { time = 5.0, category = "destroy", points = 50, x = 150, y = 150, fever = true },
            { time = 14.0, category = "aerobatics", points = 30, x = 300, y = 300, fever = false },
        }
        local win = Replay.selectHighlightWindow(events, 0, 22)
        assert(win ~= nil, "Expected valid highlight for non-Fever 30 base pts/s")
        assert(approx(win.peakTime, 14.0, 0.55), "Expected peak around t=14.0 (30 base), got " .. tostring(win.peakTime))
        assert(win.peakRate == 30, "Expected base peakRate 30, got " .. tostring(win.peakRate))
    end

    -- 2. Peak >= 30 base pts/s => best 6s window containing [peak - 1, peak + 1], output ~7.0s
    do
        local events = {
            -- Secondary cluster right before peak (t = 7..9, 100 base pts total, 70 max in 1s)
            { time = 7.2, category = "destroy", points = 30, x = 200, y = 200, fever = false },
            { time = 8.0, category = "destroy", points = 40, x = 210, y = 200, fever = false },
            { time = 8.8, category = "aerobatics", points = 30, x = 220, y = 200, fever = false },
            -- Peak burst around t = 11.0 (total 200 awarded / 100 base pts in 1s during Fever x2)
            { time = 10.7, category = "destroy", points = 60, x = 300, y = 250, fever = true },
            { time = 11.0, category = "missileDodge", points = 80, x = 310, y = 260, fever = true },
            { time = 11.3, category = "destroy", points = 60, x = 320, y = 270, fever = true },
            -- Trailing low activity after peak
            { time = 14.0, category = "destroy", points = 10, x = 400, y = 270, fever = false },
        }
        local win = Replay.selectHighlightWindow(events, 0, 25)
        assert(win ~= nil, "Expected valid highlight for >= 30 base pts/s burst")
        assert(win.peakRate >= 100, "Expected base peakRate >= 100, got " .. tostring(win.peakRate))
        assert(approx(win.clipDuration, 6.0, 0.01), "Expected 6.0s clipDuration, got " .. tostring(win.clipDuration))
        assert(win.clipStart <= win.peakTime - 1.0 + 1e-6, "Must include at least 1s before peak")
        assert(win.clipEnd >= win.peakTime + 1.0 - 1e-6, "Must include at least 1s after peak")
        -- Should bias window earlier to capture the t=7..9 cluster while keeping 1s after peak
        assert(win.clipBasePoints >= 200, "Expected optimal 6s window to capture >= 200 base pts, got " .. tostring(win.clipBasePoints))
        assert(win.clipPoints >= 300, "Expected optimal 6s window to capture >= 300 awarded pts, got " .. tostring(win.clipPoints))
        assert(approx(win.playbackDuration, 7.0, 0.05), "Expected ~7.0s output playback, got " .. tostring(win.playbackDuration))

        -- Verify forward & inverse time mapping consistency
        for pb = 0, win.playbackDuration, 0.25 do
            local src, spd = Replay.mapPlaybackTime(win, pb)
            local pbBack, spdBack = Replay.mapSourceTime(win, src)
            assert(approx(pb, pbBack, 1e-3), string.format("Time map roundtrip mismatch: %f vs %f", pb, pbBack))
            assert(approx(spd, spdBack, 1e-3), string.format("Speed map roundtrip mismatch: %f vs %f", spd, spdBack))
        end

        -- Verify slow-mo actually hits 0.5x at center of slow block
        local midSlowPb = (win.slowPlaybackStart + win.slowPlaybackEnd) * 0.5
        local _, midSpeed = Replay.mapPlaybackTime(win, midSlowPb)
        assert(approx(midSpeed, 0.5, 1e-3), "Expected 0.5x speed at peak center, got " .. tostring(midSpeed))
    end

    -- 3. Multi-stage run ranks by base points (excluding Fever x2 & chip/stage scoreMultiplier) and records FFI snapshots + SFX + popups
    do
        local Ship = require("ship")
        local Camera = require("camera")
        local Turret = require("turret")
        local Enemies = require("enemies")
        local Gladiator = require("gladiator")
        local Stage = require("stage")

        local r = Replay.new()
        local ship = Ship.new(1080, 540)
        local cam = Camera.new(ship.x, ship.y)
        local turret = Turret.new(0)
        local glad = Gladiator.new()
        glad.onAward = function(category, points, x, y, fever, basePoints)
            r:recordPointEvent(category, points, x, y, fever, basePoints)
        end
        local enemies = Enemies.new(function() return 0.5 end, glad)
        local stage = Stage.new(1)

        -- Stage 1: Fever x2 + 1.5x scoreMultiplier => 80 base pts becomes 240 awarded, but peakRate must be 80
        glad.scoreMultiplier = 1.5
        glad.feverActive = true
        for step = 1, 300 do
            r:recordFrame(1 / 30, ship, cam, turret, enemies, glad, stage)
            if step == 150 then
                glad:award("destroy", 40, "DESTROY", 500, 260)
                glad:award("missileDodge", 40, "MISSILE DODGE", 510, 250)
                r:recordSfxEvent("laser")
                r:recordSfxEvent("impact")
            end
        end
        local c1 = r:finalizeStage()
        assert(c1 ~= nil and c1.peakRate == 80, "Stage 1 should produce 80 base pts/s clip, got " .. tostring(c1 and c1.peakRate))
        assert(c1.clipPoints == 240, "Stage 1 clipPoints should keep awarded 240 pts, got " .. tostring(c1.clipPoints))
        assert(r:hasHighlight(), "Run should have highlight after stage 1")

        -- Stage 2: no multipliers, 100 base pts (100 awarded) => must replace Stage 1 (240 awarded / 80 base)
        stage = Stage.new(2)
        glad.scoreMultiplier = 1
        glad.feverActive = false
        for step = 1, 300 do
            r:recordFrame(1 / 30, ship, cam, turret, enemies, glad, stage)
            if step == 180 then
                glad:award("destroy", 50, "DESTROY", 520, 270)
                glad:award("aerobatics", 50, "AEROBATICS", 530, 270)
                r:recordSfxEvent("boost")
                r:recordSfxEvent("missile")
                r:recordSfxEvent("impact")
            end
        end
        local c2 = r:finalizeStage()
        assert(c2 ~= nil and c2.peakRate == 100, "Stage 2 should produce 100 base pts/s clip, got " .. tostring(c2 and c2.peakRate))
        assert(r.bestClip.stageNumber == 2 and r.bestClip.peakRate == 100, "Run best clip should be Stage 2")
        assert(#r.bestClip.sfxEvents == 3, "Expected 3 SFX events in Stage 2 clip")
        assert(#r.bestClip.pointEvents == 2, "Expected 2 point events in Stage 2 clip")

        -- 4. Offline WAV audio mixing test using real assets/audio/*.wav
        local tmpDir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
        local tmpWav = tmpDir .. "/sg_test_highlight_audio.wav"
        local okWav, mixedCount = ReplayExport.mixAudioToWav(r.bestClip, tmpWav, ".")
        assert(okWav, "mixAudioToWav failed: " .. tostring(mixedCount))
        assert(mixedCount == 3, "Expected 3 mixed SFX voices, got " .. tostring(mixedCount))
        local wf = assert(io.open(tmpWav, "rb"))
        local wavBytes = wf:read("*a")
        wf:close()
        os.remove(tmpWav)
        assert(wavBytes:sub(1, 4) == "RIFF" and wavBytes:sub(9, 12) == "WAVE", "Invalid WAV header")
        -- 7.0s * 44100 * 4 bytes/frame ~= 1,234,800 bytes
        assert(#wavBytes > 1200000, "WAV output unexpectedly short: " .. tostring(#wavBytes))
    end

    print("PASS: replay highlight selection, slow-mo timing, FFI snapshots, and WAV mixing")
end

-- Allow running standalone via `luajit tests/replay.lua`
if not love then
    runTests()
end

return runTests
