-- Flight control scheme manager and directional WASD steering resolver.
-- Supports both the default rotation-and-thrust ("classic") controls and
-- directional WASD steering ("directional") while keeping Ship physics intact.

local Controls = {}

Controls.SETTINGS_FILE = "control_settings.txt"
Controls.DEFAULT_MODE = "classic"
Controls.MODES = { "classic", "directional" }
Controls.MODE_LABELS = {
    classic = "기본 (회전 추진)",
    directional = "방향 추진 (WASD)",
}

Controls.mode = Controls.DEFAULT_MODE

-- Input-layer thresholds for directional WASD steering (Ship physics remain unchanged).
Controls.THRUST_ANGLE_THRESHOLD = math.rad(55)
Controls.REVERSE_THRUST_ANGLE = math.rad(30)
Controls.OPPOSITE_DOT_THRESHOLD = -0.4
Controls.MIN_BRAKE_SPEED = 15

local TAU = 2 * math.pi

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

function Controls.isValidMode(mode)
    return mode == "classic" or mode == "directional"
end

function Controls.setMode(mode)
    if Controls.isValidMode(mode) then
        Controls.mode = mode
    else
        Controls.mode = Controls.DEFAULT_MODE
    end
    return Controls.mode
end

function Controls.getMode()
    return Controls.isValidMode(Controls.mode) and Controls.mode or Controls.DEFAULT_MODE
end

function Controls.getModeLabel(mode)
    local resolved = Controls.isValidMode(mode) and mode or Controls.getMode()
    return Controls.MODE_LABELS[resolved] or Controls.MODE_LABELS[Controls.DEFAULT_MODE]
end

function Controls.nextMode(dir)
    dir = (dir and dir < 0) and -1 or 1
    local current = Controls.getMode()
    local idx = 1
    for i, m in ipairs(Controls.MODES) do
        if m == current then
            idx = i
            break
        end
    end
    local nextIdx = ((idx - 1 + dir) % #Controls.MODES) + 1
    return Controls.MODES[nextIdx]
end

function Controls.serializeSettings(mode)
    mode = Controls.isValidMode(mode) and mode or Controls.DEFAULT_MODE
    return string.format("mode=%s\n", mode)
end

function Controls.parseSettings(content)
    if type(content) ~= "string" then return nil end
    local mode = nil
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "mode" and Controls.isValidMode(v) then
            mode = v
        end
    end
    if not mode then return nil end
    return { mode = mode }
end

function Controls.loadSettings()
    if not (love and love.filesystem) then
        return { mode = Controls.DEFAULT_MODE }
    end
    if love.filesystem.getInfo(Controls.SETTINGS_FILE) then
        local content = love.filesystem.read(Controls.SETTINGS_FILE)
        local parsed = Controls.parseSettings(content)
        if parsed then return parsed end
    end
    return { mode = Controls.DEFAULT_MODE }
end

function Controls.saveSettings()
    if not (love and love.filesystem and love.filesystem.write) then return false end
    local payload = Controls.serializeSettings(Controls.getMode())
    return love.filesystem.write(Controls.SETTINGS_FILE, payload) == true
end

function Controls.resolveFlightInput(ship, dt, keys, mode)
    keys = keys or {}
    local activeMode = mode ~= nil and mode or Controls.getMode()
    if activeMode ~= "directional" then
        local turn = (keys.d and 1 or 0) - (keys.a and 1 or 0)
        local thrust = keys.w == true
        local brake = keys.s == true
        return turn, thrust, brake
    end

    local ix = (keys.d and 1 or 0) - (keys.a and 1 or 0)
    local iy = (keys.s and 1 or 0) - (keys.w and 1 or 0)
    if ix == 0 and iy == 0 then
        return 0, false, false
    end

    local inputLen = math.sqrt(ix * ix + iy * iy)
    local dirX, dirY = ix / inputLen, iy / inputLen
    -- Ship angle 0 points up (dx = sin(angle), dy = -cos(angle)).
    local targetAngle = math.atan2(dirX, -dirY) % TAU
    local currentAngle = (ship and ship.angle) or 0
    local angleError = (targetAngle - currentAngle + math.pi) % TAU - math.pi

    local turnSpeed = (ship and ship.turnSpeed) or 4.5
    local maxStep = turnSpeed * math.max(0, dt or 0)
    local turn = 0
    if maxStep > 1e-9 then
        turn = clamp(angleError / maxStep, -1, 1)
    elseif math.abs(angleError) > 1e-6 then
        turn = angleError > 0 and 1 or -1
    end

    local postError = angleError - turn * maxStep
    local absPostError = math.abs(postError)

    local vx = (ship and ship.vx) or 0
    local vy = (ship and ship.vy) or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    local isOpposite = false
    if speed > Controls.MIN_BRAKE_SPEED then
        local forwardDot = (vx * dirX + vy * dirY) / speed
        isOpposite = forwardDot < Controls.OPPOSITE_DOT_THRESHOLD
    end

    local thrust = false
    local brake = false
    if isOpposite then
        local shipBrake = (ship and ship.brake) or 2.5
        local shipThrust = (ship and ship.thrust) or 0
        local alignedThrust = absPostError <= Controls.REVERSE_THRUST_ANGLE and (shipThrust * math.cos(postError)) or 0
        if absPostError > Controls.REVERSE_THRUST_ANGLE or (shipBrake * speed) > alignedThrust then
            brake = true
            thrust = false
        else
            brake = false
            thrust = true
        end
    else
        brake = false
        thrust = absPostError <= Controls.THRUST_ANGLE_THRESHOLD
    end

    return turn, thrust, brake
end

return Controls
