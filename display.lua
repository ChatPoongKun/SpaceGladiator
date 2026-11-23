-- Resolution-independent virtual viewport, display mode, and resolution manager.
-- Keeps the logical arena and UI fixed at 1280x720 (16:9) across every window size,
-- resolution, and aspect ratio while allowing deep-space backdrops to fill the full window.

local Display = {}

Display.VIRTUAL_WIDTH = 1280
Display.VIRTUAL_HEIGHT = 720
Display.MIN_WINDOW_WIDTH = 800
Display.MIN_WINDOW_HEIGHT = 450

Display.SETTINGS_FILE = "display_settings.txt"
Display.LEGACY_FULLSCREEN_FILE = "fullscreen.txt"

Display.MODES = { "windowed", "borderless", "fullscreen" }
Display.MODE_LABELS = {
    windowed = "창 모드",
    borderless = "테두리 없는 전체 화면",
    fullscreen = "전체 화면",
}

Display.PRESET_RESOLUTIONS = {
    { w = 800,  h = 600,  aspect = "4:3" },
    { w = 1024, h = 768,  aspect = "4:3" },
    { w = 1280, h = 720,  aspect = "16:9" },
    { w = 1280, h = 800,  aspect = "16:10" },
    { w = 1366, h = 768,  aspect = "16:9" },
    { w = 1600, h = 900,  aspect = "16:9" },
    { w = 1920, h = 1080, aspect = "16:9" },
    { w = 1920, h = 1200, aspect = "16:10" },
    { w = 2560, h = 1080, aspect = "21:9" },
    { w = 2560, h = 1440, aspect = "16:9" },
    { w = 3440, h = 1440, aspect = "21:9" },
    { w = 3840, h = 2160, aspect = "16:9" },
}

Display.windowWidth = Display.VIRTUAL_WIDTH
Display.windowHeight = Display.VIRTUAL_HEIGHT
Display.scale = 1
Display.offsetX = 0
Display.offsetY = 0
Display.mode = "windowed"
Display.selectedWidth = Display.VIRTUAL_WIDTH
Display.selectedHeight = Display.VIRTUAL_HEIGHT

local function gcd(a, b)
    a, b = math.abs(math.floor(a)), math.abs(math.floor(b))
    while b ~= 0 do
        a, b = b, a % b
    end
    return math.max(1, a)
end

function Display.formatAspect(w, h)
    if not w or not h or w <= 0 or h <= 0 then return "16:9" end
    local ratio = w / h
    if math.abs(ratio - 16 / 9) < 0.02 then return "16:9" end
    if math.abs(ratio - 16 / 10) < 0.02 then return "16:10" end
    if math.abs(ratio - 4 / 3) < 0.02 then return "4:3" end
    if math.abs(ratio - 21 / 9) < 0.06 then return "21:9" end
    if math.abs(ratio - 32 / 9) < 0.06 then return "32:9" end
    local d = gcd(w, h)
    return string.format("%d:%d", math.floor(w / d + 0.5), math.floor(h / d + 0.5))
end

function Display.formatResolution(w, h)
    return string.format("%dx%d (%s)", math.floor(w + 0.5), math.floor(h + 0.5), Display.formatAspect(w, h))
end

function Display.computeViewport(windowW, windowH, virtualW, virtualH)
    virtualW = virtualW or Display.VIRTUAL_WIDTH
    virtualH = virtualH or Display.VIRTUAL_HEIGHT
    windowW = math.max(1, windowW or virtualW)
    windowH = math.max(1, windowH or virtualH)
    local scale = math.min(windowW / virtualW, windowH / virtualH)
    local offsetX = (windowW - virtualW * scale) * 0.5
    local offsetY = (windowH - virtualH * scale) * 0.5
    return scale, offsetX, offsetY
end

function Display.resize(windowW, windowH)
    if not windowW or not windowH or windowW <= 0 or windowH <= 0 then return end
    Display.windowWidth = windowW
    Display.windowHeight = windowH
    Display.scale, Display.offsetX, Display.offsetY = Display.computeViewport(
        windowW, windowH, Display.VIRTUAL_WIDTH, Display.VIRTUAL_HEIGHT
    )
end

function Display.windowToVirtual(wx, wy)
    local s = Display.scale
    if not s or s <= 0 then return wx or 0, wy or 0 end
    return ((wx or 0) - Display.offsetX) / s, ((wy or 0) - Display.offsetY) / s
end

function Display.virtualToWindow(vx, vy)
    local s = Display.scale or 1
    return Display.offsetX + (vx or 0) * s, Display.offsetY + (vy or 0) * s
end

function Display.virtualRectToWindow(vx, vy, vw, vh)
    local s = Display.scale or 1
    return Display.offsetX + (vx or 0) * s, Display.offsetY + (vy or 0) * s, (vw or 0) * s, (vh or 0) * s
end

-- Returns the full physical window rectangle expressed in virtual coordinates,
-- so full-screen dimmers/shutters seamlessly span 4:3, 16:10, and 21:9 margins.
function Display.virtualOverscanBounds()
    local s = Display.scale
    if not s or s <= 0 then
        return 0, 0, Display.VIRTUAL_WIDTH, Display.VIRTUAL_HEIGHT
    end
    return -Display.offsetX / s, -Display.offsetY / s,
        Display.windowWidth / s, Display.windowHeight / s
end

function Display.getMousePosition()
    if not (love and love.mouse and love.mouse.getPosition) then
        return Display.VIRTUAL_WIDTH * 0.5, Display.VIRTUAL_HEIGHT * 0.5
    end
    local mx, my = love.mouse.getPosition()
    return Display.windowToVirtual(mx, my)
end

function Display.applyTransform()
    if not (love and love.graphics) then return end
    local g = love.graphics
    g.origin()
    g.translate(Display.offsetX, Display.offsetY)
    g.scale(Display.scale, Display.scale)
end

-- Quantized DPI scale for font rasterization so text remains razor-sharp at 1080p/1440p/4K
-- without regenerating font atlases on tiny 1px window drags.
function Display.fontDpiScale()
    local osDpi = (love and love.window and love.window.getDPIScale) and love.window.getDPIScale() or 1
    local raw = math.max(1, math.min(4, (Display.scale or 1) * osDpi))
    return math.floor(raw * 4 + 0.5) / 4
end

function Display.getDesktopDimensions()
    if love and love.window and love.window.getDesktopDimensions then
        local _, _, flags = love.window.getMode()
        local displayIdx = (flags and flags.display) or 1
        local dw, dh = love.window.getDesktopDimensions(displayIdx)
        if dw and dh and dw > 0 and dh > 0 then
            return dw, dh
        end
    end
    return 1920, 1080
end

function Display.getAvailableResolutions(deskW, deskH)
    if not deskW or not deskH then
        deskW, deskH = Display.getDesktopDimensions()
    end
    local list = {}
    local seen = {}
    local function addRes(w, h, aspect)
        w, h = math.floor(w + 0.5), math.floor(h + 0.5)
        if w < Display.MIN_WINDOW_WIDTH or h < Display.MIN_WINDOW_HEIGHT then return end
        local key = w .. "x" .. h
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = { w = w, h = h, aspect = aspect or Display.formatAspect(w, h) }
    end

    for _, preset in ipairs(Display.PRESET_RESOLUTIONS) do
        if preset.w <= deskW and preset.h <= deskH then
            addRes(preset.w, preset.h, preset.aspect)
        end
    end
    addRes(deskW, deskH, Display.formatAspect(deskW, deskH))

    if #list == 0 then
        list[1] = { w = Display.VIRTUAL_WIDTH, h = Display.VIRTUAL_HEIGHT, aspect = "16:9" }
    end

    table.sort(list, function(a, b)
        if a.w ~= b.w then return a.w < b.w end
        return a.h < b.h
    end)
    return list
end

function Display.isValidMode(mode)
    return mode == "windowed" or mode == "borderless" or mode == "fullscreen"
end

function Display.serializeSettings(mode, w, h)
    mode = Display.isValidMode(mode) and mode or "windowed"
    w = math.max(Display.MIN_WINDOW_WIDTH, math.floor((w or Display.VIRTUAL_WIDTH) + 0.5))
    h = math.max(Display.MIN_WINDOW_HEIGHT, math.floor((h or Display.VIRTUAL_HEIGHT) + 0.5))
    return string.format("mode=%s\nwidth=%d\nheight=%d\n", mode, w, h)
end

function Display.parseSettings(content)
    if type(content) ~= "string" then return nil end
    local mode, w, h = nil, nil, nil
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "mode" and Display.isValidMode(v) then
            mode = v
        elseif k == "width" then
            w = tonumber(v)
        elseif k == "height" then
            h = tonumber(v)
        end
    end
    if not mode and not w and not h then return nil end
    return {
        mode = mode or "windowed",
        width = (w and w >= Display.MIN_WINDOW_WIDTH) and math.floor(w) or Display.VIRTUAL_WIDTH,
        height = (h and h >= Display.MIN_WINDOW_HEIGHT) and math.floor(h) or Display.VIRTUAL_HEIGHT,
    }
end

function Display.loadSettings()
    if not (love and love.filesystem) then
        return { mode = "windowed", width = Display.VIRTUAL_WIDTH, height = Display.VIRTUAL_HEIGHT }
    end
    if love.filesystem.getInfo(Display.SETTINGS_FILE) then
        local content = love.filesystem.read(Display.SETTINGS_FILE)
        local parsed = Display.parseSettings(content)
        if parsed then return parsed end
    end
    -- Migrate legacy fullscreen.txt cleanly
    if love.filesystem.getInfo(Display.LEGACY_FULLSCREEN_FILE) then
        local legacy = love.filesystem.read(Display.LEGACY_FULLSCREEN_FILE)
        if legacy == "1" then
            return { mode = "borderless", width = Display.VIRTUAL_WIDTH, height = Display.VIRTUAL_HEIGHT }
        end
    end
    return { mode = "windowed", width = Display.VIRTUAL_WIDTH, height = Display.VIRTUAL_HEIGHT }
end

function Display.saveSettings()
    if not (love and love.filesystem and love.filesystem.write) then return false end
    local payload = Display.serializeSettings(Display.mode, Display.selectedWidth, Display.selectedHeight)
    return love.filesystem.write(Display.SETTINGS_FILE, payload) == true
end

function Display.syncFromWindow()
    if not (love and love.graphics) then return end
    local w, h = love.graphics.getDimensions()
    Display.resize(w, h)
    if love.window and love.window.getFullscreen then
        local isFull, fullType = love.window.getFullscreen()
        if isFull then
            Display.mode = (fullType == "exclusive") and "fullscreen" or "borderless"
        else
            Display.mode = "windowed"
        end
    end
end

function Display.applyMode(mode, resW, resH)
    mode = Display.isValidMode(mode) and mode or Display.mode or "windowed"
    resW = math.max(Display.MIN_WINDOW_WIDTH, math.floor((resW or Display.selectedWidth or Display.VIRTUAL_WIDTH) + 0.5))
    resH = math.max(Display.MIN_WINDOW_HEIGHT, math.floor((resH or Display.selectedHeight or Display.VIRTUAL_HEIGHT) + 0.5))

    if not (love and love.window and love.window.updateMode) then
        Display.mode = mode
        Display.selectedWidth, Display.selectedHeight = resW, resH
        Display.resize(resW, resH)
        return true
    end

    local _, _, curFlags = love.window.getMode()
    local displayIdx = (curFlags and curFlags.display) or 1
    local vsync = (curFlags and curFlags.vsync ~= nil) and curFlags.vsync or 1
    local msaa = (curFlags and curFlags.msaa ~= nil) and curFlags.msaa or 4
    local deskW, deskH = love.window.getDesktopDimensions(displayIdx)
    if not deskW or deskW <= 0 then deskW, deskH = 1920, 1080 end

    local targetW, targetH, flags
    if mode == "borderless" then
        targetW, targetH = deskW, deskH
        flags = {
            fullscreen = true,
            fullscreentype = "desktop",
            resizable = true,
            vsync = vsync,
            msaa = msaa,
            minwidth = Display.MIN_WINDOW_WIDTH,
            minheight = Display.MIN_WINDOW_HEIGHT,
            display = displayIdx,
        }
    elseif mode == "fullscreen" then
        targetW, targetH = math.min(resW, deskW), math.min(resH, deskH)
        flags = {
            fullscreen = true,
            fullscreentype = "exclusive",
            resizable = false,
            vsync = vsync,
            msaa = msaa,
            display = displayIdx,
        }
    else
        targetW, targetH = math.min(resW, deskW), math.min(resH, deskH)
        flags = {
            fullscreen = false,
            resizable = true,
            vsync = vsync,
            msaa = msaa,
            minwidth = Display.MIN_WINDOW_WIDTH,
            minheight = Display.MIN_WINDOW_HEIGHT,
            centered = true,
            display = displayIdx,
        }
    end

    local ok = love.window.updateMode(targetW, targetH, flags)
    if not ok then
        return false, "화면 모드를 변경할 수 없습니다."
    end

    Display.mode = mode
    Display.selectedWidth = resW
    Display.selectedHeight = resH
    Display.resize(love.graphics.getDimensions())
    return true
end

function Display.findResolutionIndex(list, w, h)
    for i, item in ipairs(list) do
        if item.w == w and item.h == h then return i end
    end
    -- Nearest fallback by pixel area
    local bestIdx, bestDiff = 1, math.huge
    local targetArea = (w or Display.VIRTUAL_WIDTH) * (h or Display.VIRTUAL_HEIGHT)
    for i, item in ipairs(list) do
        local diff = math.abs(item.w * item.h - targetArea)
        if diff < bestDiff then
            bestDiff, bestIdx = diff, i
        end
    end
    return bestIdx
end

function Display.nextMode(dir)
    dir = (dir and dir < 0) and -1 or 1
    local idx = 1
    for i, m in ipairs(Display.MODES) do
        if m == Display.mode then idx = i; break end
    end
    local nextIdx = ((idx - 1 + dir) % #Display.MODES) + 1
    return Display.MODES[nextIdx]
end

function Display.nextResolution(dir, deskW, deskH)
    dir = (dir and dir < 0) and -1 or 1
    local list = Display.getAvailableResolutions(deskW, deskH)
    local idx = Display.findResolutionIndex(list, Display.selectedWidth, Display.selectedHeight)
    local nextIdx = ((idx - 1 + dir) % #list) + 1
    return list[nextIdx], list
end

return Display
