local Replay = require("src.replay.replay")
local Ship = require("src.combat.ship")
local Starfield = require("src.visual.starfield")
local StageBackground = require("src.visual.stage_background")
local BattleScene = require("src.visual.battle_scene")
local Sfx = require("src.audio.sfx")
local Bgm = require("src.audio.bgm")

local okFfi, ffi = pcall(require, "ffi")

local ReplayExport = {}
ReplayExport.__index = ReplayExport

ReplayExport.WIDTH = 1280
ReplayExport.HEIGHT = 720
ReplayExport.FPS = 60
ReplayExport.SAMPLE_RATE = 44100
ReplayExport.CHANNELS = 2
ReplayExport.FRAMES_PER_STEP = 6

local function isWindows()
    return package.config:sub(1, 1) == "\\"
end

local function quotePath(path)
    if isWindows() then
        return '"' .. path:gsub('"', '\\"') .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

function ReplayExport.detectFfmpeg()
    local nullDev = isWindows() and "NUL" or "/dev/null"
    local ok = os.execute("ffmpeg -version >" .. nullDev .. " 2>&1")
    return ok == 0 or ok == true
end

local function readU16LE(str, pos)
    local b1, b2 = str:byte(pos, pos + 1)
    return b1 + b2 * 256
end

local function readU32LE(str, pos)
    local b1, b2, b3, b4 = str:byte(pos, pos + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function writeU16LE(val)
    val = math.floor(val) % 65536
    return string.char(val % 256, math.floor(val / 256) % 256)
end

local function writeU32LE(val)
    val = math.floor(val) % 4294967296
    return string.char(
        val % 256,
        math.floor(val / 256) % 256,
        math.floor(val / 65536) % 256,
        math.floor(val / 16777216) % 256
    )
end

-- Parse a PCM WAV file directly (used as fallback when love.sound is unavailable, e.g. headless tests).
local function loadWavFallback(filepath)
    local f = io.open(filepath, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    if not data or #data < 44 or data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WAVE" then
        return nil
    end
    local channels, sampleRate, bitsPerSample = 1, 44100, 16
    local pcmStart, pcmLen = nil, 0
    local pos = 13
    while pos + 8 <= #data do
        local chunkId = data:sub(pos, pos + 3)
        local chunkSize = readU32LE(data, pos + 4)
        local chunkData = pos + 8
        if chunkId == "fmt " and chunkSize >= 16 then
            channels = readU16LE(data, chunkData + 2)
            sampleRate = readU32LE(data, chunkData + 4)
            bitsPerSample = readU16LE(data, chunkData + 14)
        elseif chunkId == "data" then
            pcmStart = chunkData
            pcmLen = math.min(chunkSize, #data - chunkData + 1)
            break
        end
        pos = chunkData + chunkSize + (chunkSize % 2)
    end
    if not pcmStart or pcmLen <= 0 or bitsPerSample ~= 16 then return nil end

    local frameBytes = channels * 2
    local sampleCount = math.floor(pcmLen / frameBytes)
    local samples = {}
    local idx = pcmStart
    for i = 0, sampleCount - 1 do
        local sum = 0
        for _ = 1, channels do
            local v = readU16LE(data, idx)
            if v >= 32768 then v = v - 65536 end
            sum = sum + (v / 32768)
            idx = idx + 2
        end
        samples[i] = sum / channels
    end
    return {
        sampleRate = sampleRate,
        sampleCount = sampleCount,
        samples = samples,
    }
end

local function loadAudioAsset(relPath, baseDir)
    if not relPath then return nil end
    if love and love.sound and love.sound.newSoundData then
        local ok, sd = pcall(love.sound.newSoundData, relPath)
        if ok and sd then
            local sampleRate = sd:getSampleRate()
            local channels = sd:getChannelCount()
            local sampleCount = sd:getSampleCount()
            local samples = {}
            for i = 0, sampleCount - 1 do
                if channels == 1 then
                    samples[i] = sd:getSample(i)
                else
                    local sum = 0
                    for c = 1, channels do
                        sum = sum + sd:getSample(i, c)
                    end
                    samples[i] = sum / channels
                end
            end
            sd:release()
            return {
                sampleRate = sampleRate,
                sampleCount = sampleCount,
                samples = samples,
            }
        end
    end
    local path = baseDir and (baseDir .. "/" .. relPath) or relPath
    return loadWavFallback(path)
end

local function decodeBgmSegment(bgmPath, startOffsetSec, neededSourceSec)
    if not bgmPath or not (love and love.sound and love.sound.newDecoder) then
        return nil
    end
    local ok, dec = pcall(love.sound.newDecoder, bgmPath, 4096)
    if not ok or not dec then
        return nil
    end
    local sr = dec:getSampleRate()
    local ch = dec:getChannelCount()
    local dur = dec:getDuration() or 0
    if dur <= 0 or sr <= 0 then
        if dec.release then dec:release() end
        return nil
    end

    local pos = (startOffsetSec or 0) % dur
    pcall(dec.seek, dec, pos)

    local targetSamples = math.ceil((neededSourceSec + 0.25) * sr)
    local samples = {}
    local count = 0
    local loops = 0
    while count < targetSamples and loops < 4 do
        local sd = dec:decode()
        if not sd then
            loops = loops + 1
            pcall(dec.seek, dec, 0)
        else
            local n = sd:getSampleCount()
            for i = 0, n - 1 do
                if count >= targetSamples then break end
                local v
                if ch == 1 then
                    v = sd:getSample(i)
                else
                    local sum = 0
                    for c = 1, ch do
                        sum = sum + sd:getSample(i, c)
                    end
                    v = sum / ch
                end
                samples[count] = v
                count = count + 1
            end
            sd:release()
        end
    end
    if dec.release then dec:release() end
    if count <= 1 then return nil end
    return {
        sampleRate = sr,
        sampleCount = count,
        samples = samples,
    }
end

-- Offline audio mixer: mixes clip.sfxEvents (via Sfx.getCueSpec) and clip BGM
-- into a 44.1kHz stereo 16-bit PCM WAV file matching live in-game audio behavior.
function ReplayExport.mixAudioToWav(clip, wavPath, baseDir)
    local sampleRate = ReplayExport.SAMPLE_RATE
    local duration = math.max(0.1, clip.playbackDuration or 7.0)
    local totalFrames = math.ceil(duration * sampleRate)

    local mixBuf
    if okFfi then
        mixBuf = ffi.new("float[?]", totalFrames)
    else
        mixBuf = {}
        for i = 0, totalFrames - 1 do mixBuf[i] = 0 end
    end

    local assetCache = {}
    local events = clip.sfxEvents or {}

    -- Group events enforcing exact per-cue minInterval and voice pool polyphony from Sfx
    local lastCueTime = {}
    local voiceSlots = {}
    local voiceCursor = {}
    local activeList = {}

    for i = 1, #events do
        local ev = events[i]
        local spec = Sfx.getCueSpec and Sfx.getCueSpec(ev.cue) or nil
        if spec and ev.playbackTime >= 0 and ev.playbackTime < duration then
            local minInterval = spec.minInterval or 0
            local prev = lastCueTime[ev.cue]
            if minInterval <= 0 or not prev or (ev.playbackTime - prev) >= minInterval then
                lastCueTime[ev.cue] = ev.playbackTime
                local voices = math.max(1, spec.voices or 1)
                local slots = voiceSlots[ev.cue]
                if not slots then
                    slots = {}
                    voiceSlots[ev.cue] = slots
                    voiceCursor[ev.cue] = 1
                end
                local cursor = voiceCursor[ev.cue]
                local prevInSlot = slots[cursor]
                if prevInSlot then
                    prevInSlot.cutoffTime = ev.playbackTime
                end
                local basePitch = ev.pitch or (spec.basePitch * (ev.pitchScale or 1.0))
                local item = {
                    cueName = ev.cue,
                    path = spec.path,
                    volume = spec.volume,
                    basePitch = basePitch,
                    startTime = ev.playbackTime,
                    speed = ev.speed or 1.0,
                }
                slots[cursor] = item
                voiceCursor[ev.cue] = (cursor % voices) + 1
                activeList[#activeList + 1] = item
            end
        end
    end

    -- Mix each SFX voice into mixBuf
    local mixedCount = 0
    for i = 1, #activeList do
        local item = activeList[i]
        local asset = assetCache[item.path]
        if asset == nil then
            asset = loadAudioAsset(item.path, baseDir) or false
            assetCache[item.path] = asset
        end
        if asset and asset.sampleCount > 1 then
            mixedCount = mixedCount + 1
            local speedPitch = Replay.slowMoPitchScale(item.speed)
            local effectivePitch = math.max(0.35, item.basePitch * speedPitch)
            local step = (asset.sampleRate / sampleRate) * effectivePitch
            local startFrame = math.floor(item.startTime * sampleRate)
            local maxOutFrame = totalFrames - 1
            if item.cutoffTime then
                maxOutFrame = math.min(maxOutFrame, math.floor(item.cutoffTime * sampleRate) - 1)
            end
            local srcSamples = asset.samples
            local srcMax = asset.sampleCount - 1
            local vol = item.volume
            local srcPos = 0
            local outIdx = startFrame
            while outIdx <= maxOutFrame and srcPos < srcMax do
                local i0 = math.floor(srcPos)
                local frac = srcPos - i0
                local s = srcSamples[i0] + (srcSamples[i0 + 1] - srcSamples[i0]) * frac
                mixBuf[outIdx] = mixBuf[outIdx] + s * vol
                srcPos = srcPos + step
                outIdx = outIdx + 1
            end
        end
    end

    -- Mix in-game level BGM if recorded in clip and decoder is available
    local bgmPath = clip.bgmLevel and Bgm.getTrackPath and Bgm.getTrackPath(clip.bgmLevel) or nil
    if bgmPath then
        local bgmData = decodeBgmSegment(bgmPath, clip.bgmOffset or 0, clip.clipDuration or duration)
        if bgmData and bgmData.sampleCount > 1 then
            local bgmVol = Bgm.getVolume and Bgm.getVolume() or Bgm.DEFAULT_VOLUME or 0.45
            local bgmSamples = bgmData.samples
            local bgmMax = bgmData.sampleCount - 1
            local baseRateRatio = bgmData.sampleRate / sampleRate
            local bgmPos = 0
            for outIdx = 0, totalFrames - 1 do
                if bgmPos >= bgmMax then break end
                local i0 = math.floor(bgmPos)
                local frac = bgmPos - i0
                local s = bgmSamples[i0] + (bgmSamples[i0 + 1] - bgmSamples[i0]) * frac
                mixBuf[outIdx] = mixBuf[outIdx] + s * bgmVol
                local _, speed = Replay.mapPlaybackTime(clip, outIdx / sampleRate)
                bgmPos = bgmPos + baseRateRatio * Replay.slowMoPitchScale(speed)
            end
        end
    end

    -- Write 16-bit stereo PCM WAV with soft limiting
    local f, err = io.open(wavPath, "wb")
    if not f then
        return false, "오디오 임시 파일 생성 실패: " .. tostring(err)
    end

    local numChannels = ReplayExport.CHANNELS
    local bitsPerSample = 16
    local byteRate = sampleRate * numChannels * (bitsPerSample / 8)
    local blockAlign = numChannels * (bitsPerSample / 8)
    local dataSize = totalFrames * blockAlign

    f:write("RIFF")
    f:write(writeU32LE(36 + dataSize))
    f:write("WAVE")
    f:write("fmt ")
    f:write(writeU32LE(16))
    f:write(writeU16LE(1))
    f:write(writeU16LE(numChannels))
    f:write(writeU32LE(sampleRate))
    f:write(writeU32LE(byteRate))
    f:write(writeU16LE(blockAlign))
    f:write(writeU16LE(bitsPerSample))
    f:write("data")
    f:write(writeU32LE(dataSize))

    local chunk = {}
    local chunkLen = 0
    for i = 0, totalFrames - 1 do
        local v = mixBuf[i]
        local limited = v / (1 + math.abs(v) * 0.35)
        if limited > 1 then limited = 1 elseif limited < -1 then limited = -1 end
        local pcm = math.floor(limited * 32767 + 0.5)
        if pcm < 0 then pcm = pcm + 65536 end
        local lo = pcm % 256
        local hi = math.floor(pcm / 256) % 256
        local sampleBytes = string.char(lo, hi, lo, hi)
        chunkLen = chunkLen + 1
        chunk[chunkLen] = sampleBytes
        if chunkLen >= 4096 then
            f:write(table.concat(chunk))
            chunk = {}
            chunkLen = 0
        end
    end
    if chunkLen > 0 then
        f:write(table.concat(chunk))
    end
    f:close()
    return true, mixedCount
end

local function getDocumentsDir()
    if isWindows() then
        local pipe = io.popen('powershell -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; [Environment]::GetFolderPath(\'MyDocuments\')"')
        if pipe then
            local line = pipe:read("*l")
            pipe:close()
            if line then
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" then return line end
            end
        end
        local onedrive = os.getenv("OneDrive")
        if onedrive and onedrive ~= "" then
            return onedrive .. "\\Documents"
        end
        local profile = os.getenv("USERPROFILE")
        if profile and profile ~= "" then
            return profile .. "\\Documents"
        end
    else
        local home = os.getenv("HOME")
        if home and home ~= "" then
            return home .. "/Documents"
        end
    end
    return nil
end

local function ensureDir(path)
    local nullDev = isWindows() and "NUL" or "/dev/null"
    local cmd = isWindows()
        and ("mkdir " .. quotePath(path) .. " >" .. nullDev .. " 2>&1")
        or ("mkdir -p " .. quotePath(path) .. " >" .. nullDev .. " 2>&1")
    os.execute(cmd)
end

function ReplayExport.resolveOutputDir()
    local docs = getDocumentsDir()
    if docs and docs ~= "" then
        local sep = isWindows() and "\\" or "/"
        local cleanDocs = docs:gsub("[/\\]+$", "")
        local targetDir = cleanDocs .. sep .. "SpaceGladiator"
        ensureDir(targetDir)
        return targetDir
    end
    if love and love.filesystem then
        love.filesystem.createDirectory("replays")
        return love.filesystem.getSaveDirectory() .. "/replays"
    end
    return "."
end

function ReplayExport.start(clip, fonts)
    if not clip or not clip.frames or #clip.frames == 0 then
        return nil, "내보낼 하이라이트 데이터가 없습니다."
    end
    if not ReplayExport.detectFfmpeg() then
        return nil, "FFmpeg를 찾을 수 없습니다. PATH에 ffmpeg를 설치해 주세요."
    end

    local outDir = ReplayExport.resolveOutputDir()
    local sep = isWindows() and "\\" or "/"
    local stamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("highlight_stage%02d_%s.mp4", clip.stageNumber or 1, stamp)
    local mp4Path = outDir .. sep .. filename
    local wavPath = outDir .. sep .. "_temp_highlight_audio.wav"

    local okWav, wavErr = ReplayExport.mixAudioToWav(clip, wavPath)
    if not okWav then
        return nil, wavErr
    end

    local w, h, fps = ReplayExport.WIDTH, ReplayExport.HEIGHT, ReplayExport.FPS
    local totalFrames = math.max(1, math.ceil(clip.playbackDuration * fps))

    local nullDev = isWindows() and "NUL" or "/dev/null"
    local cmd = string.format(
        "ffmpeg -y -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - -i %s " ..
        "-c:v libx264 -pix_fmt yuv420p -preset fast -crf 20 " ..
        "-c:a aac -b:a 192k -shortest -movflags +faststart %s >%s 2>&1",
        w, h, fps, quotePath(wavPath), quotePath(mp4Path), nullDev
    )

    local mode = isWindows() and "wb" or "w"
    local pipe = io.popen(cmd, mode)
    if not pipe then
        os.remove(wavPath)
        return nil, "FFmpeg 프로세스를 시작할 수 없습니다."
    end

    local canvas = love.graphics.newCanvas(w, h, { msaa = 4 })
    local stars = Starfield.new(w, h)
    local stageBackground = StageBackground.new(w, h, { level = clip.level or StageBackground.DEFAULT_LEVEL })
    Replay.syncBackgroundToClip(stageBackground, clip)

    return setmetatable({
        clip = clip,
        fonts = fonts,
        width = w,
        height = h,
        fps = fps,
        totalFrames = totalFrames,
        frameIndex = 0,
        pipe = pipe,
        canvas = canvas,
        stars = stars,
        stageBackground = stageBackground,
        mp4Path = mp4Path,
        filename = filename,
        wavPath = wavPath,
        done = false,
        error = nil,
    }, ReplayExport)
end

function ReplayExport:progress()
    if self.totalFrames <= 0 then return 1 end
    return math.min(1, self.frameIndex / self.totalFrames)
end

function ReplayExport:finish(errMsg)
    if self.done then return end
    self.done = true
    if self.pipe then
        self.pipe:close()
        self.pipe = nil
    end
    if self.canvas then
        self.canvas:release()
        self.canvas = nil
    end
    if self.wavPath then
        os.remove(self.wavPath)
    end
    if errMsg then
        self.error = errMsg
    end
end

-- Renders & pipes a small batch of frames per love.update tick so the UI stays responsive.
function ReplayExport:step(maxFrames)
    if self.done then return true end
    local batch = maxFrames or ReplayExport.FRAMES_PER_STEP
    local dt = 1 / self.fps

    for _ = 1, batch do
        if self.frameIndex >= self.totalFrames then
            self:finish(nil)
            return true
        end

        local pbTime = self.frameIndex * dt
        local srcTime, speed = Replay.mapPlaybackTime(self.clip, pbTime)
        local f0, f1, alpha = Replay.sampleClipFrame(self.clip, srcTime)
        local shipProxy = Ship.buildReplayProxy(
            f0.layers and f0.layers.ship,
            f1.layers and f1.layers.ship,
            alpha)
        BattleScene.updateEnvironment(dt * speed, {
            ship = shipProxy,
            stageBackground = self.stageBackground,
            stars = self.stars,
        }, self.width, self.height, { scale = 1 })

        love.graphics.push("all")
        love.graphics.setCanvas(self.canvas)
        love.graphics.origin()
        love.graphics.clear(0.018, 0.028, 0.055, 1)
        love.graphics.setLineStyle("smooth")
        Replay.renderClipFrame(self.clip, pbTime, self.width, self.height, self.fonts, self.stars, true, self.stageBackground)
        love.graphics.setCanvas()
        love.graphics.pop()

        local imgData = self.canvas:newImageData()
        local raw = imgData:getString()
        imgData:release()

        local ok = self.pipe:write(raw)
        if not ok then
            self:finish("FFmpeg 인코딩 중 파이프 오류가 발생했습니다.")
            return true
        end

        self.frameIndex = self.frameIndex + 1
    end

    if self.frameIndex >= self.totalFrames then
        self:finish(nil)
        return true
    end
    return false
end

return ReplayExport
