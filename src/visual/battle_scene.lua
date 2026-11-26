-- Shared combat scene update & rendering pipeline used by both live gameplay
-- and highlight replay playback/export, keeping visuals 1:1 with in-game.

local Arena = require("src.core.arena")
local StageBackground = require("src.visual.stage_background")

local BattleScene = {}

BattleScene.worldLayers = {}
BattleScene.overlayLayers = {}

local function registerLayer(list, spec)
    if not spec or not spec.id or type(spec.draw) ~= "function" then
        return
    end
    for i = #list, 1, -1 do
        if list[i].id == spec.id then
            table.remove(list, i)
        end
    end
    list[#list + 1] = {
        id = spec.id,
        order = spec.order or 0,
        draw = spec.draw,
    }
    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
end

local function unregisterLayer(list, id)
    for i = #list, 1, -1 do
        if list[i].id == id then
            table.remove(list, i)
        end
    end
end

function BattleScene.registerWorldLayer(spec)
    registerLayer(BattleScene.worldLayers, spec)
end

function BattleScene.unregisterWorldLayer(id)
    unregisterLayer(BattleScene.worldLayers, id)
end

function BattleScene.registerOverlayLayer(spec)
    registerLayer(BattleScene.overlayLayers, spec)
end

function BattleScene.unregisterOverlayLayer(id)
    unregisterLayer(BattleScene.overlayLayers, id)
end

function BattleScene.updateEnvironment(dt, state, bgW, bgH, opts)
    if not state or not dt or dt <= 0 then return end
    local ship = state.ship
    if not ship then return end
    local scale = (opts and opts.scale) or 1
    local vx, vy
    if ship.worldVelocity then
        vx, vy = ship:worldVelocity()
    else
        vx = (ship.vx or 0) + (ship.wrapVx or 0) + (ship.knockVx or 0)
        vy = (ship.vy or 0) + (ship.wrapVy or 0) + (ship.knockVy or 0)
    end
    local boostLevel = ship.boostLevel or 0
    local boostX = ship.boostX or 0
    local boostY = ship.boostY or -1
    local surge = 1050 * boostLevel
    local bgBoost = 120 * boostLevel

    if state.stageBackground then
        state.stageBackground:update(dt,
            (vx + boostX * bgBoost) * scale,
            (vy + boostY * bgBoost) * scale,
            bgW, bgH)
    end
    if state.stars then
        state.stars:update(dt,
            (120 + vx * 2.8 + boostX * surge) * scale,
            (-290 + vy * 2.8 + boostY * surge) * scale,
            ship.accelerating and 1 or 0,
            bgW, bgH, boostLevel)
    end
end

function BattleScene.drawBackground(state, viewport, opts)
    local g = love.graphics
    local vpX = viewport and viewport.x or 0
    local vpY = viewport and viewport.y or 0
    local bgW = viewport and viewport.w or 1280
    local bgH = viewport and viewport.h or 720
    local stageBackground = state and state.stageBackground
    local stars = state and state.stars
    local camera = state and state.camera

    if stageBackground then
        local pullback = (opts and opts.pullback ~= nil) and opts.pullback
            or (camera and camera.pullback) or 0
        local shake = (opts and opts.shake ~= nil) and opts.shake
            or (camera and camera.shakeIntensity and camera:shakeIntensity()) or 0
        local bgOpts = {
            originX = vpX,
            originY = vpY,
            pullback = pullback,
            shake = shake,
        }
        if opts then
            if opts.nextLevel ~= nil then bgOpts.nextLevel = opts.nextLevel end
            if opts.blend ~= nil then bgOpts.blend = opts.blend end
            if opts.fadeThroughBlack ~= nil then bgOpts.fadeThroughBlack = opts.fadeThroughBlack end
            if opts.titleParallaxX ~= nil then bgOpts.titleParallaxX = opts.titleParallaxX end
            if opts.titleParallaxY ~= nil then bgOpts.titleParallaxY = opts.titleParallaxY end
        end
        stageBackground:draw(bgW, bgH, bgOpts)
        if stars then
            stars:draw({
                transparent = true,
                originX = vpX,
                originY = vpY,
                excludeZone = opts and opts.excludeZone or nil,
            })
        end
    elseif stars then
        stars:draw({ originX = vpX, originY = vpY })
    else
        local fb = StageBackground.FALLBACK_COLOR
        g.push("all")
        g.origin()
        g.setColor(fb[1], fb[2], fb[3], 1)
        g.rectangle("fill", vpX, vpY, bgW, bgH)
        g.pop()
    end
end

function BattleScene.drawPlayer(ship, turret, width, time)
    if not ship then return end
    local g = love.graphics
    g.push("all")
    if ship:isDestroyed() then
        ship:drawDestruction()
    else
        ship:drawBoostPulse()
        if turret then
            turret:drawMount(ship, time, width)
        end
        ship:draw(time)
    end
    g.pop()
end

function BattleScene.drawWorld(state, width, height, time, opts)
    if not state or not state.camera then return end
    local g = love.graphics
    local camera = state.camera
    local ship = state.ship
    local turret = state.turret
    local enemies = state.enemies
    local gladiator = state.gladiator

    g.push()
    local originX, originY = camera:worldToScreen(0, 0, width, height)
    g.translate(originX, originY)
    g.scale(camera.zoom)

    Arena.draw(ship and ship.boostLevel or 0, gladiator and gladiator.feverAura or 0)
    if enemies then
        enemies:draw(time)
    end
    if gladiator and ship then
        gladiator:drawFeverWorld(ship, time)
    end
    if ship then
        BattleScene.drawPlayer(ship, turret, width, time)
    end
    if turret then
        turret:drawEffects(camera, width, height)
    end
    for i = 1, #BattleScene.worldLayers do
        BattleScene.worldLayers[i].draw(state, width, height, time, opts)
    end
    g.pop()
end

function BattleScene.drawLowArmorAura(lowArmorAura, width, height, time)
    if not lowArmorAura or lowArmorAura <= 0 then return end
    local g = love.graphics
    local t = time or 0
    local pulse = math.min(1.1, 0.55 + 0.45 * math.sin(t * 4.2) + 0.12 * math.max(0, math.sin(t * 8.4)))
    g.push("all")
    g.setColor(0.88, 0.05, 0.07, 0.11 * lowArmorAura * pulse)
    g.rectangle("fill", 0, 0, width, height)
    local bands = { 14, 30, 50, 74, 102 }
    for idx, thickness in ipairs(bands) do
        local alpha = (0.20 / idx) * lowArmorAura * pulse
        g.setColor(0.95, 0.06, 0.08, alpha)
        g.rectangle("fill", 0, 0, width, thickness)
        g.rectangle("fill", 0, height - thickness, width, thickness)
        g.rectangle("fill", 0, thickness, thickness, height - thickness * 2)
        g.rectangle("fill", width - thickness, thickness, thickness, height - thickness * 2)
    end
    g.setLineWidth(2.0)
    g.setColor(1.0, 0.18, 0.20, 0.52 * lowArmorAura * pulse)
    g.rectangle("line", 4, 4, width - 8, height - 8)
    local span = 28 + math.sin(t * 4.2) * 4
    g.setLineWidth(2.5)
    g.setColor(1.0, 0.22, 0.24, 0.72 * lowArmorAura * pulse)
    for _, cx in ipairs({ 12, width - 12 }) do
        local sx = cx == 12 and 1 or -1
        for _, cy in ipairs({ 12, height - 12 }) do
            local sy = cy == 12 and 1 or -1
            g.line(cx + sx * span, cy, cx, cy, cx, cy + sy * span)
        end
    end
    g.pop()
end

function BattleScene.drawHullFlash(hullFlashTimer, hullFlashDuration, width, height)
    if not hullFlashTimer or hullFlashTimer <= 0 or not hullFlashDuration or hullFlashDuration <= 0 then
        return
    end
    local g = love.graphics
    local p = math.max(0, math.min(1, hullFlashTimer / hullFlashDuration))
    g.push("all")
    if p > 0.70 then
        local peak = (p - 0.70) / 0.30
        g.setColor(1.0, 0.94, 0.86, 0.56 * peak)
        g.rectangle("fill", 0, 0, width, height)
    end
    g.setColor(0.95, 0.14, 0.10, 0.34 * p * p)
    g.rectangle("fill", 0, 0, width, height)
    for band = 1, 3 do
        local thickness = band * 14
        local alpha = (0.30 / band) * p
        g.setColor(1.0, 0.20, 0.14, alpha)
        g.rectangle("fill", 0, 0, width, thickness)
        g.rectangle("fill", 0, height - thickness, width, thickness)
        g.rectangle("fill", 0, thickness, thickness, height - thickness * 2)
        g.rectangle("fill", width - thickness, thickness, thickness, height - thickness * 2)
    end
    g.pop()
end

function BattleScene.drawScreenEffects(state, width, height, time, fonts, opts)
    if not state then return end
    local gladiator = state.gladiator
    local camera = state.camera

    if gladiator then
        gladiator:drawFeverOverlay(width, height, time)
    end
    BattleScene.drawLowArmorAura(state.lowArmorAura or 0, width, height, time)
    BattleScene.drawHullFlash(state.hullFlashTimer or 0, state.hullFlashDuration or 0.34, width, height)
    if gladiator and fonts and fonts.small then
        gladiator:drawPopups(camera, width, height, fonts.small)
    end
    for i = 1, #BattleScene.overlayLayers do
        BattleScene.overlayLayers[i].draw(state, width, height, time, fonts, opts)
    end
end

return BattleScene
