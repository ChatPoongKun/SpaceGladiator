pcall(function()
    local ffi = require("ffi")
    if ffi.os == "Windows" then
        ffi.cdef[[
            int SetProcessDpiAwareness(int value);
        ]]
        ffi.load("shcore").SetProcessDpiAwareness(2)
    end
end)

function love.conf(t)
    local isTest = false
    for _, v in ipairs(arg or {}) do
        if type(v) == "string" and v:sub(1, 6) == "--test" then
            isTest = true
            break
        end
    end

    t.identity = "drift-flight"
    t.version = "11.5"
    t.window.title = "SPACE GLADIATOR"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 800
    t.window.minheight = 450
    t.window.resizable = true
    if not isTest then
        t.window.fullscreen = true
        t.window.fullscreentype = "desktop"
    end
    t.window.vsync = 1
    t.window.msaa = 4
    t.modules.joystick = false
    t.modules.physics = false
end
