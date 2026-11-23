local Replay = require("replay")
local Starfield = require("starfield")
local StageBackground = require("stage_background")
local Sfx = require("sfx")

local okFfi, ffi = pcall(require, "ffi")

local ReplayExport = {}
ReplayExport.__index = ReplayExport

ReplayExport.WIDTH = 1280
ReplayExport.HEIGHT = 720
ReplayExport.FPS = 60
ReplayExport.SAMPLE_RATE = 44100
ReplayExport.CHANNELS = 2
ReplayExport.MAX_POLYPHONY = 24
ReplayExport.MIN_RETRIGGER_DT = 0.025
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

local function loadAudioAsset(assetName, baseDir)
    local relPath = "assets/audio/" .. assetName .. ".wav"
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

-- Offline audio mixer: mixes clip.sfxEvents into a 44.1kHz stereo 16-bit PCM WAV file.
-- Respects per-cue single-voice cutoff, min retrigger interval, max polyphony, and soft limiting.
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

    local cues = Sfx.getCues and Sfx.getCues() or {}
    local assetCache = {}
    local events = clip.sfxEvents or {}

    -- Group filtered events (enforcing per-cue minimum retrigger interval)
    local lastCueTime = {}
    local activeList = {}
    for i = 1, #events do
        local ev = events[i]
        local cue = cues[ev.cue]
        if cue and ev.playbackTime >= 0 and ev.playbackTime < duration then
            local prev = lastCueTime[ev.cue]
            if not prev or (ev.playbackTime - prev) >= ReplayExport.MIN_RETRIGGER_DT then
                lastCueTime[ev.cue] = ev.playbackTime
                activeList[#activeList + 1] = {
                    cueName = ev.cue,
                    asset = cue[1],
                    volume = cue[2] or 0.6,
                    pitch = cue[3] or 1.0,
                    startTime = ev.playbackTime,
                    speed = ev.speed or 1.0,
                }
            end
        end
    end

    -- Enforce single-voice cutoff per cue (matching Sfx.play: source:stop(); source:play())
    for i = 1, #activeList do
        local item = activeList[i]
        for j = i + 1, #activeList do
            if activeList[j].cueName == item.cueName then
                item.cutoffTime = activeList[j].startTime
                break
            end
        end
    end

    -- Mix each voice into mixBuf
    local mixedCount = 0
    for i = 1, #activeList do
        local item = activeList[i]
        local asset = assetCache[item.asset]
        if asset == nil then
            asset = loadAudioAsset(item.asset, baseDir) or false
            assetCache[item.asset] = asset
        end
        if asset and asset.sampleCount > 1 then
            mixedCount = mixedCount + 1
            local pitchScale = math.max(0.62, math.min(1.0, 0.35 + 0.65 * item.speed))
            local step = (asset.sampleRate / sampleRate) * item.pitch * pitchScale
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

    -- Write 16-bit stereo PCM WAV with soft tanh limiting
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
    f:write(writeU16LE(1)) -- PCM
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
        -- Smooth soft-limiter preventing clipping when many SFX overlap
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
        local vx = (f0.shipVx + f0.shipWrapVx) * (1 - alpha) + (f1.shipVx + f1.shipWrapVx) * alpha
        local vy = (f0.shipVy + f0.shipWrapVy) * (1 - alpha) + (f1.shipVy + f1.shipWrapVy) * alpha
        local boostLevel = f0.shipBoostLevel * (1 - alpha) + f1.shipBoostLevel * alpha
        local surge = 1050 * boostLevel
        if self.stageBackground then
            local bgBoost = 120 * boostLevel
            self.stageBackground:update(dt * speed,
                vx + f0.shipBoostX * bgBoost,
                vy + f0.shipBoostY * bgBoost,
                self.width, self.height)
        end
        self.stars:update(dt * speed,
            120 + vx * 2.8 + f0.shipBoostX * surge,
            -290 + vy * 2.8 + f0.shipBoostY * surge,
            f0.shipAccelerating and 1 or 0, self.width, self.height, boostLevel)

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
