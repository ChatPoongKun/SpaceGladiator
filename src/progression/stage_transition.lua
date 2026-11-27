-- Stage-end visual transitions & inter-stage warp gate selection for SpaceGladiator.
-- 1. 2.0-second Stage Clear celebration with "STAGE CLEAR" banner + left/right blast
--    shutters closing over the battlefield and reopening to reveal Warp Gates.
-- 2. Three random boundary warp gates on the cleared battlefield displaying major
--    next-stage rewards.
-- 3. Hyperspace starlight warp animation accelerating out of the arena through
--    streaming starlight and decelerating smoothly into the next stage.

local Arena = require("src.core.arena")
local Display = require("src.core.display")
local Sfx = require("src.audio.sfx")

local StageTransition = {}

StageTransition.CLEAR_HOLD = 1.25
StageTransition.SHUTTER_CLOSE = 0.75
StageTransition.CLEAR_TOTAL = StageTransition.CLEAR_HOLD + StageTransition.SHUTTER_CLOSE -- 2.0s
StageTransition.SHUTTER_OPEN = 0.55
StageTransition.WARP_DURATION = 2.40
StageTransition.ENTRY_WARP_DURATION = 2.95
StageTransition.WARP_ALIGN_SPEED = 7.5
StageTransition.WARP_ALIGN_MIN_DURATION = 0.08
StageTransition.WARP_ALIGN_MAX_DURATION = 0.50
StageTransition.GATE_COUNT = 3
StageTransition.GATE_WIDTH = 116
StageTransition.GATE_TRIGGER_DEPTH = 48

StageTransition.WARP_REWARDS = {
    {
        id = "weapon_module",
        title = "희귀 무기 모듈",
        short = "WEAPON+",
        subtitle = "추가 무기 보급 · 코인 +30",
        color = { 0.98, 0.56, 0.24 },
    },
    {
        id = "support_chip",
        title = "희귀 서포트 칩",
        short = "CHIP+",
        subtitle = "추가 칩 보급 · 코인 +30",
        color = { 0.44, 0.94, 1.00 },
    },
    {
        id = "defense_module",
        title = "방어·추진 모듈",
        short = "DEFENSE+",
        subtitle = "실드 +35 즉시 회복",
        color = { 0.36, 0.78, 1.00 },
    },
    {
        id = "coin_jackpot",
        title = "글래디에이터 x1.5",
        short = "GP x1.5",
        subtitle = "다음 스테이지 정산 GP 1.5배",
        color = { 1.00, 0.84, 0.32 },
    },
    {
        id = "hull_repair",
        title = "긴급 선체 정비",
        short = "REPAIR+",
        subtitle = "실드·장갑 100% · 선체 +1",
        color = { 0.44, 0.96, 0.66 },
    },
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function easeInOutCubic(t)
    t = clamp(t, 0, 1)
    if t < 0.5 then
        return 4 * t * t * t
    end
    local f = -2 * t + 2
    return 1 - (f * f * f) * 0.5
end

local function easeOutCubic(t)
    t = clamp(t, 0, 1)
    local f = 1 - t
    return 1 - f * f * f
end

local function easeInCubic(t)
    t = clamp(t, 0, 1)
    return t * t * t
end

local function shuffle(list, rng)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    for i = #copy, 2, -1 do
        local j = math.floor(rng() * i) + 1
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function shortestAngleDiff(from, to)
    local tau = math.pi * 2
    return (to - from + math.pi) % tau - math.pi
end

local function slewTurretAngle(turret, targetAngle, dt)
    if not turret or targetAngle == nil then return end
    local tau = math.pi * 2
    local diff = shortestAngleDiff(turret.angle or 0, targetAngle)
    local turnSpeed = turret.turnSpeed or tau
    local limit = turnSpeed * dt
    if math.abs(diff) <= limit then
        turret.angle = targetAngle % tau
    else
        turret.angle = ((turret.angle or 0) + (diff > 0 and limit or -limit)) % tau
    end
end

--------------------------------------------------------------------------------
-- 1. Stage Clear + Left/Right Blast Shutter Transition
--------------------------------------------------------------------------------

function StageTransition.newStageClear(stage)
    return {
        elapsed = 0,
        holdDuration = StageTransition.CLEAR_HOLD,
        closeDuration = StageTransition.SHUTTER_CLOSE,
        totalDuration = StageTransition.CLEAR_TOTAL,
        stageNumber = stage and stage.number or 1,
        clearReason = stage and stage.clearReason or "ALL HOSTILES CLEARED",
        closeSfxPlayed = false,
        done = false,
    }
end

function StageTransition.stageClearCloseProgress(state)
    if not state then return 0 end
    if state.elapsed <= state.holdDuration then return 0 end
    return clamp((state.elapsed - state.holdDuration) / math.max(1e-6, state.closeDuration), 0, 1)
end

function StageTransition.updateStageClear(state, dt)
    if not state or state.done or dt <= 0 then return state and state.done or false end
    state.elapsed = state.elapsed + dt
    if state.elapsed >= state.holdDuration and not state.closeSfxPlayed then
        state.closeSfxPlayed = true
        Sfx.play("shutter_close")
    end
    if state.elapsed >= state.totalDuration then
        state.elapsed = state.totalDuration
        state.done = true
        return true
    end
    return false
end

function StageTransition.newShutterOpen()
    return {
        elapsed = 0,
        duration = StageTransition.SHUTTER_OPEN,
        openSfxPlayed = false,
        done = false,
    }
end

function StageTransition.updateShutterOpen(state, dt)
    if not state or state.done or dt <= 0 then return state and state.done or false end
    if not state.openSfxPlayed then
        state.openSfxPlayed = true
        Sfx.play("shutter_open")
    end
    state.elapsed = state.elapsed + dt
    if state.elapsed >= state.duration then
        state.elapsed = state.duration
        state.done = true
        return true
    end
    return false
end

local function drawShutters(closure, width, height)
    if closure <= 0.001 then return end
    local g = love.graphics
    local ox, oy, ow, oh = Display.virtualOverscanBounds()
    local leftX = math.min(0, ox)
    local topY = math.min(0, oy)
    local fullW = math.max(width, ow)
    local fullH = math.max(height, oh)
    local rightEdge = leftX + fullW
    local centerX = leftX + fullW * 0.5
    local halfW = fullW * 0.5
    local doorW = halfW * closure + 2
    local leftSeam = leftX + doorW
    local rightX = rightEdge - doorW

    g.push("all")

    -- Left & Right heavy sci-fi bulkhead doors
    g.setColor(0.022, 0.036, 0.064, 0.98)
    g.rectangle("fill", leftX, topY, doorW, fullH)
    g.rectangle("fill", rightX, topY, doorW, fullH)

    -- Subtle inner armor paneling stripes
    g.setColor(0.050, 0.095, 0.150, 0.85)
    g.rectangle("fill", leftX, topY + fullH * 0.14, math.max(0, doorW - 22), fullH * 0.72)
    g.rectangle("fill", rightX + 22, topY + fullH * 0.14, math.max(0, doorW - 22), fullH * 0.72)

    -- Horizontal tech ribs on both shutters
    g.setLineWidth(1)
    g.setColor(0.28, 0.58, 0.74, 0.22)
    for y = topY + 60, topY + fullH - 60, 60 do
        g.line(leftX, y, math.max(leftX, leftSeam - 14), y)
        g.line(math.min(rightEdge, rightX + 14), y, rightEdge, y)
    end

    -- Glowing leading edge bevels where left & right shutters meet
    local seamGlow = 0.65 + 0.35 * closure
    g.setColor(1.0, 0.82, 0.36, 0.22 * seamGlow)
    g.rectangle("fill", leftSeam - 12, topY, 12, fullH)
    g.rectangle("fill", rightX, topY, 12, fullH)

    g.setLineWidth(2.5)
    g.setColor(1.0, 0.86, 0.44, 0.92 * seamGlow)
    g.line(leftSeam, topY, leftSeam, topY + fullH)
    g.line(rightX, topY, rightX, topY + fullH)

    g.setLineWidth(1.2)
    g.setColor(0.45, 0.92, 1.0, 0.75 * seamGlow)
    g.line(math.max(leftX, leftSeam - 16), topY, math.max(leftX, leftSeam - 16), topY + fullH)
    g.line(math.min(rightEdge, rightX + 16), topY, math.min(rightEdge, rightX + 16), topY + fullH)

    -- Center lock flash right as the shutters seal
    if closure > 0.92 then
        local lockAlpha = (closure - 0.92) / 0.08
        g.setColor(1.0, 0.94, 0.70, lockAlpha * 0.55)
        g.rectangle("fill", centerX - 3, topY, 6, fullH)
    end

    g.pop()
end

function StageTransition.drawStageClearOverlay(state, width, height, fonts)
    if not state then return end
    local g = love.graphics
    local t = state.elapsed
    local enter = easeOutCubic(clamp(t / 0.32, 0, 1))
    local rawClose = StageTransition.stageClearCloseProgress(state)
    local closure = easeInOutCubic(rawClose)
    local ox, oy, ow, oh = Display.virtualOverscanBounds()

    g.push("all")

    -- Subtle atmospheric dim + expanding victory shockwave ring
    g.setColor(0.015, 0.028, 0.055, 0.34 * enter)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    if t < 0.95 then
        local ringT = t / 0.95
        local r = 40 + easeOutCubic(ringT) * math.min(width, height) * 0.44
        g.setLineWidth(3.5 * (1 - ringT))
        g.setColor(1.0, 0.86, 0.42, (1 - ringT) * 0.75)
        g.circle("line", width * 0.5, height * 0.5, r)
    end

    -- Draw closing left/right shutters
    drawShutters(closure, width, height)

    -- Draw "STAGE CLEAR" banner centered on top of the shutters so it stays vivid across all 2.0s
    local cx, cy = width * 0.5, height * 0.5
    local bannerW = math.min(620, width - 80) * (0.86 + 0.14 * enter)
    local bannerH = 128
    local bx = cx - bannerW * 0.5
    local by = cy - bannerH * 0.5

    g.setColor(0.025, 0.048, 0.086, 0.90 * enter)
    g.rectangle("fill", bx, by, bannerW, bannerH, 10, 10)
    g.setColor(1.0, 0.84, 0.38, 0.90 * enter)
    g.setLineWidth(2)
    g.rectangle("line", bx, by, bannerW, bannerH, 10, 10)

    -- Accent horizontal lines flanking the banner
    local wingLen = 90 * enter
    g.setColor(0.45, 0.92, 1.0, 0.75 * enter)
    g.setLineWidth(2)
    g.line(bx - wingLen - 12, cy, bx - 12, cy)
    g.line(bx + bannerW + 12, cy, bx + bannerW + wingLen + 12, cy)

    -- Main English headline
    g.setFont(fonts.title)
    g.setColor(1.0, 0.92, 0.56, enter)
    g.printf("STAGE CLEAR", bx, by + 20, bannerW, "center")

    -- Korean stage + reason subtitle
    g.setFont(fonts.menuButton or fonts.menuBody)
    g.setColor(0.84, 0.96, 1.0, enter)
    local reasonKo = state.clearReason == "ALL HOSTILES CLEARED"
        and "모든 적 섬멸 완료 · 스테이지 정산으로 이동합니다"
        or "스테이지 클리어 · 스테이지 정산으로 이동합니다"
    g.printf(string.format("STAGE %02d  ·  %s", state.stageNumber, reasonKo), bx + 16, by + 70, bannerW - 32, "center")

    -- Subtle countdown bar along bottom of banner
    local prog = clamp(t / state.totalDuration, 0, 1)
    local barW = bannerW - 72
    local barX = cx - barW * 0.5
    local barY = by + bannerH - 18
    g.setColor(0.14, 0.22, 0.30, 0.85 * enter)
    g.rectangle("fill", barX, barY, barW, 4, 2, 2)
    g.setColor(1.0, 0.82, 0.36, 0.95 * enter)
    g.rectangle("fill", barX, barY, barW * prog, 4, 2, 2)

    g.pop()
end

function StageTransition.drawClosedShutters(width, height)
    drawShutters(1, width, height)
end

function StageTransition.drawShutterOpen(state, width, height)
    if not state or state.done then return end
    local openT = clamp(state.elapsed / math.max(1e-6, state.duration), 0, 1)
    local closure = 1 - easeOutCubic(openT)
    drawShutters(closure, width, height)
end

--------------------------------------------------------------------------------
-- 2. Battlefield Boundary Warp Gates (3 random boundaries with major rewards)
--------------------------------------------------------------------------------

local edgeSpecs = {
    { edge = "top",    dirX = 0,  dirY = -1, angle = 0 },
    { edge = "bottom", dirX = 0,  dirY = 1,  angle = math.pi },
    { edge = "left",   dirX = -1, dirY = 0,  angle = math.pi * 1.5 },
    { edge = "right",  dirX = 1,  dirY = 0,  angle = math.pi * 0.5 },
}

function StageTransition.generateWarpGates(arenaW, arenaH, rng)
    arenaW = arenaW or Arena.width
    arenaH = arenaH or Arena.height
    rng = rng or (love and love.math and love.math.random or math.random)

    local chosenEdges = shuffle(edgeSpecs, rng)
    local chosenRewards = shuffle(StageTransition.WARP_REWARDS, rng)
    local gates = {}

    for i = 1, StageTransition.GATE_COUNT do
        local spec = chosenEdges[i]
        local reward = chosenRewards[i]
        local t = 0.24 + rng() * 0.52
        local x, y
        if spec.edge == "top" then
            x, y = t * arenaW, 0
        elseif spec.edge == "bottom" then
            x, y = t * arenaW, arenaH
        elseif spec.edge == "left" then
            x, y = 0, t * arenaH
        else
            x, y = arenaW, t * arenaH
        end

        gates[i] = {
            index = i,
            edge = spec.edge,
            x = x,
            y = y,
            dirX = spec.dirX,
            dirY = spec.dirY,
            angle = spec.angle,
            width = StageTransition.GATE_WIDTH,
            reward = reward,
        }
    end

    return {
        gates = gates,
        age = 0,
        readyDelay = 0.25,
        arenaW = arenaW,
        arenaH = arenaH,
        blockedEdges = {},
        lastShipX = nil,
        lastShipY = nil,
    }
end

function StageTransition.updateWarpGates(warpGates, dt)
    if not warpGates or dt <= 0 then return end
    warpGates.age = warpGates.age + dt
end

local function distanceFromEdge(edge, x, y, w, h)
    if edge == "top" then return y end
    if edge == "bottom" then return h - y end
    if edge == "left" then return x end
    return w - x
end

local function lateralFromGate(gate, x, y)
    if gate.edge == "top" or gate.edge == "bottom" then
        return math.abs(x - gate.x)
    end
    return math.abs(y - gate.y)
end

function StageTransition.checkGateTrigger(warpGates, ship)
    if not warpGates or not ship then return nil end
    local w = warpGates.arenaW or Arena.width
    local h = warpGates.arenaH or Arena.height
    local depth = StageTransition.GATE_TRIGGER_DEPTH

    warpGates.blockedEdges = warpGates.blockedEdges or {}
    local blocked = warpGates.blockedEdges

    -- Detect boundary wraps so emerging from the opposite edge into a gate zone
    -- never triggers stage transition until the ship re-enters the stage interior.
    local prevX = warpGates.lastShipX
    if prevX == nil then prevX = ship.prevX end
    local prevY = warpGates.lastShipY
    if prevY == nil then prevY = ship.prevY end

    local wrappedThisStep = false
    if prevY ~= nil then
        local dy = ship.y - prevY
        if dy < -h * 0.5 then
            blocked.top = true
            wrappedThisStep = true
        elseif dy > h * 0.5 then
            blocked.bottom = true
            wrappedThisStep = true
        end
    end
    if prevX ~= nil then
        local dx = ship.x - prevX
        if dx < -w * 0.5 then
            blocked.left = true
            wrappedThisStep = true
        elseif dx > w * 0.5 then
            blocked.right = true
            wrappedThisStep = true
        end
    end

    -- Active inward boundary-crossing velocity also marks a boundary entry on that edge.
    local wrapVx, wrapVy = ship.wrapVx or 0, ship.wrapVy or 0
    if ship.y <= depth and wrapVy > 0 then blocked.top = true end
    if ship.y >= h - depth and wrapVy < 0 then blocked.bottom = true end
    if ship.x <= depth and wrapVx > 0 then blocked.left = true end
    if ship.x >= w - depth and wrapVx < 0 then blocked.right = true end

    -- Clear an edge's block once the ship moves cleanly back into the stage interior.
    if blocked.top and ship.y > depth then blocked.top = false end
    if blocked.bottom and ship.y < h - depth then blocked.bottom = false end
    if blocked.left and ship.x > depth then blocked.left = false end
    if blocked.right and ship.x < w - depth then blocked.right = false end

    warpGates.lastShipX = ship.x
    warpGates.lastShipY = ship.y

    if warpGates.age < (warpGates.readyDelay or 0) then return nil end
    if wrappedThisStep then return nil end

    local vx, vy = ship.vx or 0, ship.vy or 0
    local wvx, wvy = vx + wrapVx, vy + wrapVy
    if ship.worldVelocity then
        wvx, wvy = ship:worldVelocity()
    end

    for _, gate in ipairs(warpGates.gates) do
        if not blocked[gate.edge] then
            local dist = distanceFromEdge(gate.edge, ship.x, ship.y, w, h)
            local halfSpan = gate.width * 0.5 + 18
            if dist <= depth and lateralFromGate(gate, ship.x, ship.y) <= halfSpan then
                local approachVel = vx * gate.dirX + vy * gate.dirY
                local worldApproachVel = wvx * gate.dirX + wvy * gate.dirY
                if approachVel > 1e-3 and worldApproachVel > 1e-3 then
                    return gate
                end
            end
        end
    end
    return nil
end

function StageTransition.applyRewardOnArrival(reward, inventory, ship, coinWallet)
    local bonusCoins = 0
    if not reward then return bonusCoins end
    if reward.id == "weapon_module" or reward.id == "support_chip" then
        bonusCoins = 30
    elseif reward.id == "defense_module" and ship then
        ship.shield = math.min(ship.maxShield, ship.shield + 35)
    elseif reward.id == "hull_repair" and ship then
        ship.shield = ship.maxShield
        ship.armor = ship.maxArmor
        ship.hull = math.min(ship.maxHull, ship.hull + 1)
    end
    return bonusCoins
end

function StageTransition.drawWarpGates(warpGates, ship, time, fonts, screenW, screenH)
    if not warpGates or not warpGates.gates then return end
    local g = love.graphics
    local fade = easeOutCubic(clamp(warpGates.age / 0.35, 0, 1))
    local arenaW = warpGates.arenaW or Arena.width
    local arenaH = warpGates.arenaH or Arena.height
    local w = screenW or arenaW
    local h = screenH or arenaH
    local scaleX = arenaW > 0 and (w / arenaW) or 1
    local scaleY = arenaH > 0 and (h / arenaH) or 1

    g.push("all")
    for _, gate in ipairs(warpGates.gates) do
        local rc = gate.reward.color or { 0.45, 0.92, 1.0 }
        local halfW = gate.width * 0.5
        local horizontal = (gate.edge == "top" or gate.edge == "bottom")
        local gateX = gate.x * scaleX
        local gateY = gate.y * scaleY
        local pulse = 0.72 + 0.28 * math.sin(time * 5.2 + gate.index * 1.9)

        -- Proximity boost when ship flies near this gate
        local nearFactor = 0
        if ship then
            local dx, dy = ship.x - gate.x, ship.y - gate.y
            local dist = math.sqrt(dx * dx + dy * dy)
            nearFactor = clamp(1 - dist / 200, 0, 1)
        end

        -- 1. Glowing energy portal aperture on the screen/arena boundary
        local glowDepth = 22 + 12 * nearFactor
        if horizontal then
            local gy = gate.edge == "top" and -4 or (h - glowDepth + 4)
            g.setColor(rc[1], rc[2], rc[3], (0.20 + 0.16 * nearFactor) * pulse * fade)
            g.rectangle("fill", gateX - halfW, gy, gate.width, glowDepth, 6, 6)
            -- Crisp bright beam right along boundary edge
            g.setColor(rc[1], rc[2], rc[3], (0.85 + 0.15 * nearFactor) * fade)
            g.setLineWidth(4 + 2 * nearFactor)
            g.line(gateX - halfW, gateY, gateX + halfW, gateY)
            g.setColor(1, 1, 1, 0.85 * pulse * fade)
            g.setLineWidth(1.8)
            g.line(gateX - halfW * 0.72, gateY, gateX + halfW * 0.72, gateY)
            -- End pylons
            g.setColor(rc[1], rc[2], rc[3], 0.95 * fade)
            g.circle("fill", gateX - halfW, gateY, 5)
            g.circle("fill", gateX + halfW, gateY, 5)
        else
            local gx = gate.edge == "left" and -4 or (w - glowDepth + 4)
            g.setColor(rc[1], rc[2], rc[3], (0.20 + 0.16 * nearFactor) * pulse * fade)
            g.rectangle("fill", gx, gateY - halfW, glowDepth, gate.width, 6, 6)
            g.setColor(rc[1], rc[2], rc[3], (0.85 + 0.15 * nearFactor) * fade)
            g.setLineWidth(4 + 2 * nearFactor)
            g.line(gateX, gateY - halfW, gateX, gateY + halfW)
            g.setColor(1, 1, 1, 0.85 * pulse * fade)
            g.setLineWidth(1.8)
            g.line(gateX, gateY - halfW * 0.72, gateX, gateY + halfW * 0.72)
            g.setColor(rc[1], rc[2], rc[3], 0.95 * fade)
            g.circle("fill", gateX, gateY - halfW, 5)
            g.circle("fill", gateX, gateY + halfW, 5)
        end

        -- 2. Animated directional chevrons pulling toward the warp boundary
        for c = 0, 2 do
            local phase = (time * 1.9 + c * 0.33) % 1
            local distIn = (1 - phase) * 46 + 8
            local cx = gateX - gate.dirX * distIn
            local cy = gateY - gate.dirY * distIn
            local cAlpha = math.sin(phase * math.pi) * (0.78 + 0.22 * nearFactor) * fade
            g.push()
            g.translate(cx, cy)
            g.rotate(gate.angle)
            g.setColor(rc[1], rc[2], rc[3], cAlpha)
            g.setLineWidth(2.2)
            g.line(-12, 6, 0, -6, 12, 6)
            g.pop()
        end

        -- 3. Holographic major reward card anchored neatly inside the screen
        local cardW, cardH = 196, 62
        local anchorDistX = horizontal and 0 or 118
        local anchorDistY = horizontal and 66 or 0
        local cardCx = clamp(gateX - gate.dirX * anchorDistX, cardW * 0.5 + 14, w - cardW * 0.5 - 14)
        local cardCy = clamp(gateY - gate.dirY * anchorDistY, cardH * 0.5 + 12, h - cardH * 0.5 - 12)
        local cardX = cardCx - cardW * 0.5
        local cardY = cardCy - cardH * 0.5

        g.setColor(0.025, 0.048, 0.086, (0.86 + 0.10 * nearFactor) * fade)
        g.rectangle("fill", cardX, cardY, cardW, cardH, 7, 7)
        g.setColor(rc[1], rc[2], rc[3], (0.68 + 0.32 * nearFactor) * fade)
        g.setLineWidth(1.5 + nearFactor)
        g.rectangle("line", cardX, cardY, cardW, cardH, 7, 7)

        -- Top colored accent strip
        g.setColor(rc[1], rc[2], rc[3], 0.90 * fade)
        g.rectangle("fill", cardX + 6, cardY + 2, cardW - 12, 3, 2, 2)

        -- Reward short badge + Korean title + subtitle
        g.setFont(fonts.small)
        g.setColor(rc[1], rc[2], rc[3], 0.98 * fade)
        g.printf("WARP  /  " .. gate.reward.short, cardX + 6, cardY + 8, cardW - 12, "center")

        g.setFont(fonts.menuBody)
        g.setColor(0.96, 0.99, 1.0, fade)
        g.printf(gate.reward.title, cardX + 6, cardY + 22, cardW - 12, "center")

        g.setFont(fonts.menuSmall or fonts.menuBody)
        g.setColor(0.72, 0.86, 0.94, 0.92 * fade)
        g.printf(gate.reward.subtitle, cardX + 6, cardY + 42, cardW - 12, "center")
    end
    g.pop()
end

--------------------------------------------------------------------------------
-- 3. Hyperspace Starlight Warp Animation
--------------------------------------------------------------------------------

local function buildWarpStreaks(rc, rng)
    local streaks = {}
    for i = 1, 96 do
        local tint = rng()
        local col
        if tint < 0.56 then
            col = { 0.92, 0.97, 1.00 }
        elseif tint < 0.82 then
            col = { 0.48, 0.86, 1.00 }
        else
            col = { rc[1], rc[2], rc[3] }
        end
        streaks[i] = {
            nx = rng(),
            ny = rng(),
            depth = 0.35 + rng() * 0.85,
            len = 90 + rng() * 210,
            width = 0.8 + rng() * 1.8,
            alpha = 0.35 + rng() * 0.60,
            color = col,
        }
    end
    return streaks
end

function StageTransition.newWarp(gate, nextStageNumber, ship, width, height, rng)
    rng = rng or (love and love.math and love.math.random or math.random)
    local rc = gate.reward and gate.reward.color or { 0.45, 0.92, 1.0 }
    local streaks = buildWarpStreaks(rc, rng)

    local tau = math.pi * 2
    local startAngle = (ship and ship.angle or (gate and gate.angle) or 0) % tau
    local vx, vy = ship and (ship.vx or 0) or 0, ship and (ship.vy or 0) or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    local warpAngle, dirX, dirY
    if speed > 1e-3 then
        dirX, dirY = vx / speed, vy / speed
        warpAngle = math.atan2(dirX, -dirY) % tau
    else
        local wvx, wvy = 0, 0
        if ship and ship.worldVelocity then
            wvx, wvy = ship:worldVelocity()
        end
        local wSpeed = math.sqrt(wvx * wvx + wvy * wvy)
        if wSpeed > 1e-3 then
            dirX, dirY = wvx / wSpeed, wvy / wSpeed
            warpAngle = math.atan2(dirX, -dirY) % tau
            speed = wSpeed
        else
            warpAngle = ((gate and gate.angle) or startAngle) % tau
            dirX, dirY = math.sin(warpAngle), -math.cos(warpAngle)
        end
    end

    local angleDiff = shortestAngleDiff(startAngle, warpAngle)
    local absDiff = math.abs(angleDiff)
    local alignDuration = 0
    if absDiff > 1e-3 then
        alignDuration = clamp(
            StageTransition.WARP_ALIGN_MIN_DURATION + absDiff / StageTransition.WARP_ALIGN_SPEED,
            StageTransition.WARP_ALIGN_MIN_DURATION,
            StageTransition.WARP_ALIGN_MAX_DURATION
        )
    end
    local warpDuration = StageTransition.WARP_DURATION

    return {
        mode = "stage",
        gate = gate,
        nextStageNumber = nextStageNumber or 2,
        elapsed = 0,
        alignDuration = alignDuration,
        warpDuration = warpDuration,
        duration = alignDuration + warpDuration,
        phase = alignDuration > 0 and "align" or "warp",
        startX = ship and ship.x or (Arena.width * 0.5),
        startY = ship and ship.y or (Arena.height * 0.5),
        startAngle = startAngle,
        angleDiff = angleDiff,
        angle = warpAngle,
        dirX = dirX,
        dirY = dirY,
        entrySpeed = math.max(42, speed),
        speedFactor = 0,
        jumpSfxPlayed = false,
        arriveSfxPlayed = false,
        streaks = streaks,
        done = false,
    }
end

function StageTransition.newEntryWarp(stageNumber, ship, width, height, rng, entryPose)
    rng = rng or (love and love.math and love.math.random or math.random)
    local rc = { 0.45, 0.92, 1.0 }
    local streaks = buildWarpStreaks(rc, rng)
    local tau = math.pi * 2
    local directional = (entryPose ~= nil)
    local warpAngle = directional and ((entryPose.angle or 0) % tau) or 0
    local dirX, dirY = math.sin(warpAngle), -math.cos(warpAngle)
    local warpDuration = StageTransition.ENTRY_WARP_DURATION
    local startX = directional and (entryPose.x or Arena.width * 0.5) or (Arena.width * 0.5)
    local startY = directional and (entryPose.y or Arena.height * 0.5) or (Arena.height + 140)
    local initialSpeed = StageTransition.entryWarpSpeedFactor(0)

    if ship then
        ship.x = startX
        ship.y = startY
        ship.angle = warpAngle
        local visualSpeed = 42 + (math.max(42, ship.maxSpeed or 180) - 42) * initialSpeed
        ship.vx = directional and (entryPose.vx or dirX * visualSpeed) or (dirX * visualSpeed)
        ship.vy = directional and (entryPose.vy or dirY * visualSpeed) or (dirY * visualSpeed)
        ship.wrapVx, ship.wrapVy = 0, 0
        ship.boostX, ship.boostY = dirX, dirY
        ship.boostLevel = initialSpeed
        ship.accelerating = true
        ship.braking = false
        ship.boostRemaining = initialSpeed * (ship.boostHold + ship.boostFalloff)
    end

    return {
        mode = "entry",
        directional = directional,
        gate = { reward = { color = rc, title = "" } },
        nextStageNumber = stageNumber or 1,
        elapsed = 0,
        alignDuration = 0,
        warpDuration = warpDuration,
        duration = warpDuration,
        phase = "warp",
        startX = startX,
        startY = startY,
        startAngle = warpAngle,
        angleDiff = 0,
        angle = warpAngle,
        dirX = dirX,
        dirY = dirY,
        entrySpeed = ship and (ship.maxSpeed or 180) or 180,
        speedFactor = initialSpeed,
        jumpSfxPlayed = false,
        arriveSfxPlayed = false,
        streaks = streaks,
        done = false,
    }
end

function StageTransition.warpProgress(warp)
    if not warp then return 0 end
    local alignDuration = warp.alignDuration or 0
    local warpDuration = warp.warpDuration or math.max(1e-6, (warp.duration or StageTransition.WARP_DURATION) - alignDuration)
    if warp.elapsed <= alignDuration then return 0 end
    return clamp((warp.elapsed - alignDuration) / math.max(1e-6, warpDuration), 0, 1)
end

function StageTransition.entryWarpSpeedFactor(progress)
    local p = clamp(progress, 0, 1)
    if p < 0.14 then
        return 0.78 + 0.22 * easeOutCubic(p / 0.14)
    elseif p < 0.42 then
        return 1.0
    else
        local decelT = clamp((p - 0.42) / 0.58, 0, 1)
        return math.pow(math.max(0, 1 - decelT), 2.2)
    end
end

function StageTransition.warpSpeedFactor(progress)
    local p = clamp(progress, 0, 1)
    if p < 0.24 then
        -- Rapid ignition ramp-up into warp
        return 0.14 + 0.86 * easeInOutCubic(p / 0.24)
    elseif p < 0.58 then
        -- Sustained hyperspace starlight cruise
        return 1.0
    else
        -- Smooth deceleration as we approach the next stage (guard against tiny negative FP drift at p == 1)
        local decelT = clamp((p - 0.58) / 0.42, 0, 1)
        return math.pow(math.max(0, 1 - decelT), 2.4)
    end
end

function StageTransition.updateWarp(warp, dt, ship, stars, camera, width, height, turret)
    if not warp or warp.done or dt <= 0 then return warp and warp.done or false end
    warp.elapsed = warp.elapsed + dt

    local dirX, dirY = warp.dirX, warp.dirY
    local viewW = math.max(1, width or Display.VIRTUAL_WIDTH)
    local viewH = math.max(1, height or Display.VIRTUAL_HEIGHT)
    local alignDuration = warp.alignDuration or 0

    -- Phase 1: Rotate ship nose cleanly onto its travel direction before engaging hyperspace warp
    if warp.elapsed < alignDuration then
        warp.phase = "align"
        warp.speedFactor = 0
        local alignT = easeInOutCubic(clamp(warp.elapsed / math.max(1e-6, alignDuration), 0, 1))
        local currentAngle = (warp.startAngle + (warp.angleDiff or 0) * alignT) % (math.pi * 2)

        if stars then
            local _, _, bgW, bgH = Display.viewportRect()
            local bgScale = Display.scale or 1
            stars:update(dt, dirX * 180 * bgScale, dirY * 180 * bgScale, 0, bgW, bgH, 0)
        end

        if ship then
            ship.angle = currentAngle
            local alignSpeed = math.max(42, (warp.entrySpeed or 42) * (1 - 0.35 * alignT))
            ship.vx = dirX * alignSpeed
            ship.vy = dirY * alignSpeed
            ship.wrapVx, ship.wrapVy = 0, 0
            ship.boostLevel = 0
            ship.accelerating = false
            ship.braking = false
            ship.boostX, ship.boostY = dirX, dirY
            ship.boostRemaining = 0
        end
        slewTurretAngle(turret, warp.angle, dt)

        if camera and ship then
            camera:update(dt, ship, viewW, viewH)
        end
        return false
    end

    -- Phase 2: Hyperspace warp along the ship's travel direction
    warp.phase = "warp"
    if not warp.jumpSfxPlayed then
        warp.jumpSfxPlayed = true
        Sfx.play("warp_jump")
    end

    local isEntry = (warp.mode == "entry")
    local p = StageTransition.warpProgress(warp)
    local speedFactor = isEntry and StageTransition.entryWarpSpeedFactor(p) or StageTransition.warpSpeedFactor(p)
    warp.speedFactor = speedFactor

    local arriveSfxAt = isEntry and 0.42 or 0.60
    if p >= arriveSfxAt and not warp.arriveSfxPlayed then
        warp.arriveSfxPlayed = true
        Sfx.play("warp_arrive")
    end

    -- Drive Starfield along travel direction so stars stretch & then calm down cleanly
    if stars then
        local _, _, bgW, bgH = Display.viewportRect()
        local bgScale = Display.scale or 1
        local starSpeed = (240 + 4600 * speedFactor) * bgScale
        stars:update(dt, dirX * starSpeed, dirY * starSpeed, speedFactor, bgW, bgH, speedFactor)
    end

    -- Stream hyperspace starlight streaks opposite the ship's travel direction at uniform pixel speed
    local refSize = math.sqrt(viewW * viewH)
    local travelPx = (0.18 + 3.2 * speedFactor) * refSize * dt
    local stepNx = dirX * travelPx / viewW
    local stepNy = dirY * travelPx / viewH
    for _, st in ipairs(warp.streaks) do
        st.nx = (st.nx - stepNx * st.depth) % 1
        st.ny = (st.ny - stepNy * st.depth) % 1
    end

    -- Keep ship heading & engine plume aligned with its travel direction throughout warp
    if ship then
        if isEntry then
            if warp.directional then
                local travelT = easeInOutCubic(clamp(p / 0.34, 0, 1))
                ship.x = warp.startX + (Arena.width * 0.5 - warp.startX) * travelT
                ship.y = warp.startY + (Arena.height * 0.5 - warp.startY) * travelT
            else
                local travelT = easeOutCubic(clamp(p / 0.88, 0, 1))
                ship.x = Arena.width * 0.5
                ship.y = warp.startY + (Arena.height * 0.5 - warp.startY) * travelT
            end
        end
        ship.angle = warp.angle
        local visualSpeed = 42 + (math.max(42, ship.maxSpeed or 180) - 42) * speedFactor
        ship.vx = dirX * visualSpeed
        ship.vy = dirY * visualSpeed
        ship.wrapVx, ship.wrapVy = 0, 0
        ship.boostLevel = speedFactor
        ship.accelerating = speedFactor > 0.05
        ship.braking = false
        ship.boostX, ship.boostY = dirX, dirY
        ship.boostRemaining = speedFactor * (ship.boostHold + ship.boostFalloff)
    end
    slewTurretAngle(turret, warp.angle, dt)

    if camera and ship then
        camera:update(dt, ship, viewW, viewH)
    end

    if warp.elapsed >= warp.duration then
        warp.elapsed = warp.duration
        warp.phase = "done"
        warp.done = true
        if ship then
            ship.x = Arena.width * 0.5
            ship.y = Arena.height * 0.5
            ship.angle = warp.angle
            ship.vx = dirX * 42
            ship.vy = dirY * 42
            ship.wrapVx, ship.wrapVy = 0, 0
            ship.invulnTimer, ship.invulnDuration = 0, 0
            ship.boostLevel = 0
            ship.boostRemaining = 0
            ship.accelerating = false
            ship.braking = false
        end
        if turret then
            turret.angle = warp.angle % (math.pi * 2)
        end
        return true
    end
    return false
end

function StageTransition.drawWarp(warp, ship, camera, width, height, time, fonts, turret)
    if not warp then return end
    local g = love.graphics
    local isEntry = (warp.mode == "entry")
    local aligning = warp.elapsed < (warp.alignDuration or 0)
    local p = StageTransition.warpProgress(warp)
    local sf = aligning and 0 or (warp.speedFactor or (isEntry and StageTransition.entryWarpSpeedFactor(p) or StageTransition.warpSpeedFactor(p)))
    local dirX, dirY = warp.dirX, warp.dirY
    local rc = warp.gate and warp.gate.reward and warp.gate.reward.color or { 0.45, 0.92, 1.0 }

    local ox, oy, ow, oh = Display.virtualOverscanBounds()
    local fillX, fillY = math.min(0, ox), math.min(0, oy)
    local fillW, fillH = math.max(width, ow), math.max(height, oh)

    g.push("all")

    -- 1. Hyperspace starlight streaks streaming past the ship
    local streakVisibility = clamp(sf * 1.25, 0, 1)
    if streakVisibility > 0.01 then
        for _, st in ipairs(warp.streaks) do
            local sx = fillX + st.nx * fillW
            local sy = fillY + st.ny * fillH
            local len = st.len * (0.18 + 1.25 * sf) * st.depth
            local tx = sx - dirX * len
            local ty = sy - dirY * len
            local a = st.alpha * streakVisibility

            -- Soft outer glow line
            g.setLineWidth(st.width * 2.4)
            g.setColor(st.color[1], st.color[2], st.color[3], a * 0.22)
            g.line(sx, sy, tx, ty)
            -- Bright starlight core streak
            g.setLineWidth(st.width)
            g.setColor(st.color[1], st.color[2], st.color[3], a)
            g.line(sx, sy, tx, ty)
        end

        -- Subtle starlight tunnel edge glow
        g.setColor(0.32, 0.72, 1.0, 0.09 * sf)
        g.rectangle("fill", fillX, fillY, fillW, fillH)
    end

    -- 2. Draw ship streaking in from below (entry) or rotating & gliding into arrival center (stage warp)
    if ship then
        local centerX, centerY = camera:worldToScreen(Arena.width * 0.5, Arena.height * 0.5, width, height)
        local startSx, startSy = camera:worldToScreen(warp.startX, warp.startY, width, height)
        local vibScale = sf * sf
        local vibX = math.sin(time * 64) * 1.8 * vibScale
        local vibY = math.cos(time * 73) * 1.8 * vibScale
        local targetSx = centerX + dirX * 18 * sf + vibX
        local targetSy = centerY + dirY * 18 * sf + vibY
        local shipSx, shipSy

        if isEntry then
            if warp.directional then
                local travelT = easeInOutCubic(clamp(p / 0.34, 0, 1))
                shipSx = startSx + (targetSx - startSx) * travelT
                shipSy = startSy + (targetSy - startSy) * travelT
            else
                local entryStartSy = math.max(height + 110, startSy)
                local travelT = easeOutCubic(clamp(p / 0.88, 0, 1))
                shipSx = centerX + vibX
                shipSy = entryStartSy + (targetSy - entryStartSy) * travelT
            end
        elseif aligning then
            shipSx, shipSy = startSx, startSy
        elseif p < 0.30 then
            local t1 = easeInOutCubic(p / 0.30)
            shipSx = startSx + (targetSx - startSx) * t1
            shipSy = startSy + (targetSy - startSy) * t1
        else
            shipSx = targetSx
            shipSy = targetSy
        end

        g.push("all")
        g.translate(shipSx, shipSy)
        g.scale(camera.zoom)
        -- Warp energy bow-wave around ship at high speed
        if sf > 0.08 then
            g.push()
            g.rotate(ship.angle)
            g.setColor(rc[1], rc[2], rc[3], 0.32 * sf)
            g.setLineWidth(2.5)
            g.arc("line", "open", 0, -4, 34 + 10 * sf, -math.pi * 0.85, -math.pi * 0.15)
            g.setColor(0.85, 0.98, 1.0, 0.45 * sf)
            g.setLineWidth(1.5)
            g.arc("line", "open", 0, -6, 26 + 6 * sf, -math.pi * 0.80, -math.pi * 0.20)
            g.pop()
        end
        g.translate(-ship.x, -ship.y)
        ship:draw(time)
        g.pop()
    end

    -- 5. Brief ignition & arrival light flashes (only after alignment finishes and warp engages)
    if not aligning and p < 0.16 then
        local flash = (1 - p / 0.16)
        local peakAlpha = isEntry and 0.28 or 0.42
        g.setColor(rc[1], rc[2], rc[3], flash * flash * peakAlpha)
        g.rectangle("fill", fillX, fillY, fillW, fillH)
    elseif p > 0.90 then
        local flash = math.sin(((p - 0.90) / 0.10) * math.pi)
        g.setColor(0.75, 0.95, 1.0, flash * 0.18)
        g.rectangle("fill", fillX, fillY, fillW, fillH)
    end

    -- 6. Sleek Warp Telemetry HUD Banner
    local hudAlpha = clamp(math.min(warp.elapsed / 0.15, (warp.duration - warp.elapsed) / 0.35), 0, 1)
    local panelW = 420
    local panelH = 82
    local px = math.floor((width - panelW) * 0.5)
    local py = 28

    g.setColor(0.020, 0.038, 0.072, 0.82 * hudAlpha)
    g.rectangle("fill", px, py, panelW, panelH, 8, 8)
    g.setColor(rc[1], rc[2], rc[3], 0.78 * hudAlpha)
    g.setLineWidth(1.5)
    g.rectangle("line", px, py, panelW, panelH, 8, 8)

    g.setFont(fonts.small)
    g.setColor(0.62, 0.88, 0.98, 0.95 * hudAlpha)
    if aligning then
        g.printf("HYPERDRIVE  ALIGNING  /  VECTOR LOCK", px + 10, py + 10, panelW - 20, "center")
    elseif isEntry then
        local speedC = 0.2 + sf * 9.8
        g.printf(string.format("HYPERDRIVE  %.1fc  /  ARENA ENTRY", speedC), px + 10, py + 10, panelW - 20, "center")
    else
        local speedC = 0.2 + sf * 9.8
        g.printf(string.format("HYPERDRIVE  %.1fc  /  STARLIGHT TRANSIT", speedC), px + 10, py + 10, panelW - 20, "center")
    end

    g.setFont(fonts.menuButton or fonts.menuBody)
    g.setColor(1.0, 0.96, 0.80, hudAlpha)
    g.printf(string.format("STAGE %02d 워프 진입 중", warp.nextStageNumber), px + 10, py + 28, panelW - 20, "center")

    g.setFont(fonts.menuSmall or fonts.menuBody)
    g.setColor(rc[1], rc[2], rc[3], 0.95 * hudAlpha)
    if isEntry then
        g.printf("전투 구역 진입 · 시스템 온라인", px + 10, py + 54, panelW - 20, "center")
    else
        g.printf("선택 보상: " .. (warp.gate and warp.gate.reward and warp.gate.reward.title or ""), px + 10, py + 54, panelW - 20, "center")
    end

    g.pop()
end

return StageTransition
