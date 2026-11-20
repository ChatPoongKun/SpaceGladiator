function love.conf(t)
    t.identity = "drift-flight"
    t.version = "11.5"
    t.window.title = "DRIFT - Inertial Flight"
    t.window.width = 1280
    t.window.height = 800
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 4
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.physics = false
end
