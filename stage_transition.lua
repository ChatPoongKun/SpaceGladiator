-- Stage-end visual transitions & inter-stage warp gate selection for SpaceGladiator.
-- 1. 2.0-second Stage Clear celebration with "STAGE CLEAR" banner + left/right blast
--    shutters closing over the battlefield and reopening to reveal Plinko.
-- 2. Three random boundary warp gates on the cleared battlefield displaying major
--    next-stage rewards.
-- 3. Hyperspace starlight warp animation accelerating out of the arena through
--    streaming starlight and decelerating smoothly into the next stage.

local Arena = require("arena")
local Sfx = require("sfx")

local StageTransition = {}

StageTransition.CLEAR_HOLD = 1.25
StageTransition.SHUTTER_CLOSE = 0.75
StageTransition.CLEAR_TOTAL = StageTransition.CLEAR_HOLD + StageTransition.SHUTTER_CLOSE -- 2.0s
StageTransition.SHUTTER_OPEN = 0.55
StageTransition.WARP_DURATION = 2.40
StageTransition.GATE_COUNT = 3
StageTransition.GATE_WIDTH = 116
StageTransition.GATE_TRIGGER_DEPTH = 48

StageTransition.WARP_REWARDS = {
    {
        id = "weapon_module",
        title = "희귀 무기 모듈",
        short = "WEAPON+",
        subtitle = "플링코 무기 슬롯 · 코인 +30",
        color = { 0.98, 0.56, 0.24 },
    },
    {
        id = "support_chip",
        title = "희귀 서포트 칩",
        short = "CHIP+",
        subtitle = "플링코 희귀 칩 · 코인 +30",
        color = { 0.44, 0.94, 1.00 },
    },
    {
        id = "defense_module",
        title = "방어·추진 모듈",
        short = "DEFENSE+",
        subtitle = "플링코 방어 슬롯 · 실드 +35",
        color = { 0.36, 0.78, 1.00 },
    },
    {
        id = "coin_jackpot",
        title = "글래디에이터 x1.5",
        short = "COINS x1.5",
        subtitle = "다음 스테이지 포인트 1.5배",
        color = { 1.00, 0.84, 0.32 },
    },
    {
        id = "link_boost",
        title = "배선 링크 강화",
        short = "LINK+",
        subtitle = "즉시 링크 +1 · 플링코 링크권",
        color = { 0.72, 0.56, 1.00 },
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
    local halfW = width * 0.5
    local doorW = halfW * closure + 2
    local rightX = width - doorW

    g.push("all")
    g.origin()

    -- Left & Right heavy sci-fi bulkhead doors
    g.setColor(0.022, 0.036, 0.064, 0.98)
    g.rectangle("fill", 0, 0, doorW, height)
    g.rectangle("fill", rightX, 0, doorW, height)

    -- Subtle inner armor paneling stripes
    g.setColor(0.050, 0.095, 0.150, 0.85)
    g.rectangle("fill", 0, height * 0.14, math.max(0, doorW - 22), height * 0.72)
    g.rectangle("fill", rightX + 22, height * 0.14, math.max(0, doorW - 22), height * 0.72)

    -- Horizontal tech ribs on both shutters
    g.setLineWidth(1)
    g.setColor(0.28, 0.58, 0.74, 0.22)
    for y = 60, height - 60, 60 do
        g.line(0, y, math.max(0, doorW - 14), y)
        g.line(math.min(width, rightX + 14), y, width, y)
    end

    -- Glowing leading edge bevels where left & right shutters meet
    local seamGlow = 0.65 + 0.35 * closure
    g.setColor(1.0, 0.82, 0.36, 0.22 * seamGlow)
    g.rectangle("fill", doorW - 12, 0, 12, height)
    g.rectangle("fill", rightX, 0, 12, height)

    g.setLineWidth(2.5)
    g.setColor(1.0, 0.86, 0.44, 0.92 * seamGlow)
    g.line(doorW, 0, doorW, height)
    g.line(rightX, 0, rightX, height)

    g.setLineWidth(1.2)
    g.setColor(0.45, 0.92, 1.0, 0.75 * seamGlow)
    g.line(math.max(0, doorW - 16), 0, math.max(0, doorW - 16), height)
    g.line(math.min(width, rightX + 16), 0, math.min(width, rightX + 16), height)

    -- Center lock flash right as the shutters seal
    if closure > 0.92 then
        local lockAlpha = (closure - 0.92) / 0.08
        g.setColor(1.0, 0.94, 0.70, lockAlpha * 0.55)
        g.rectangle("fill", halfW - 3, 0, 6, height)
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

    g.push("all")
    g.origin()

    -- Subtle atmospheric dim + expanding victory shockwave ring
    g.setColor(0.015, 0.028, 0.055, 0.34 * enter)
    g.rectangle("fill", 0, 0, width, height)

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
        and "모든 적 섬멸 완료 · 스폰서 플링코로 이동합니다"
        or "스테이지 클리어 · 스폰서 플링코로 이동합니다"
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
    }
end

function StageTransition.updateWarpGates(warpGates, dt)
    if not warpGates or dt <= 0 then return end
    warpGates.age = warpGates.age + dt
end

function StageTransition.checkGateTrigger(warpGates, ship)
    if not warpGates or not ship then return nil end
    if warpGates.age < (warpGates.readyDelay or 0) then return nil end
    local w = warpGates.arenaW or Arena.width
    local h = warpGates.arenaH or Arena.height
    local depth = StageTransition.GATE_TRIGGER_DEPTH

    for _, gate in ipairs(warpGates.gates) do
        local halfSpan = gate.width * 0.5 + 18
        if gate.edge == "top" then
            if ship.y <= depth and math.abs(ship.x - gate.x) <= halfSpan then
                return gate
            end
        elseif gate.edge == "bottom" then
            if ship.y >= h - depth and math.abs(ship.x - gate.x) <= halfSpan then
                return gate
            end
        elseif gate.edge == "left" then
            if ship.x <= depth and math.abs(ship.y - gate.y) <= halfSpan then
                return gate
            end
        elseif gate.edge == "right" then
            if ship.x >= w - depth and math.abs(ship.y - gate.y) <= halfSpan then
                return gate
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
    elseif reward.id == "link_boost" and inventory then
        for _, mod in ipairs(inventory.placed or {}) do
            if inventory:unlockNextLink(mod) then
                break
            end
        end
    elseif reward.id == "hull_repair" and ship then
        ship.shield = ship.maxShield
        ship.armor = ship.maxArmor
        ship.hull = math.min(ship.maxHull, ship.hull + 1)
    end
    return bonusCoins
end

function StageTransition.drawWarpGates(warpGates, ship, time, fonts)
    if not warpGates or not warpGates.gates then return end
    local g = love.graphics
    local fade = easeOutCubic(clamp(warpGates.age / 0.35, 0, 1))
    local w = warpGates.arenaW or Arena.width
    local h = warpGates.arenaH or Arena.height

    g.push("all")
    for _, gate in ipairs(warpGates.gates) do
        local rc = gate.reward.color or { 0.45, 0.92, 1.0 }
        local halfW = gate.width * 0.5
        local horizontal = (gate.edge == "top" or gate.edge == "bottom")
        local pulse = 0.72 + 0.28 * math.sin(time * 5.2 + gate.index * 1.9)

        -- Proximity boost when ship flies near this gate
        local nearFactor = 0
        if ship then
            local dx, dy = ship.x - gate.x, ship.y - gate.y
            local dist = math.sqrt(dx * dx + dy * dy)
            nearFactor = clamp(1 - dist / 200, 0, 1)
        end

        -- 1. Glowing energy portal aperture on the arena boundary
        local glowDepth = 22 + 12 * nearFactor
        if horizontal then
            local gy = gate.edge == "top" and -4 or (h - glowDepth + 4)
            g.setColor(rc[1], rc[2], rc[3], (0.20 + 0.16 * nearFactor) * pulse * fade)
            g.rectangle("fill", gate.x - halfW, gy, gate.width, glowDepth, 6, 6)
            -- Crisp bright beam right along boundary edge
            g.setColor(rc[1], rc[2], rc[3], (0.85 + 0.15 * nearFactor) * fade)
            g.setLineWidth(4 + 2 * nearFactor)
            g.line(gate.x - halfW, gate.y, gate.x + halfW, gate.y)
            g.setColor(1, 1, 1, 0.85 * pulse * fade)
            g.setLineWidth(1.8)
            g.line(gate.x - halfW * 0.72, gate.y, gate.x + halfW * 0.72, gate.y)
            -- End pylons
            g.setColor(rc[1], rc[2], rc[3], 0.95 * fade)
            g.circle("fill", gate.x - halfW, gate.y, 5)
            g.circle("fill", gate.x + halfW, gate.y, 5)
        else
            local gx = gate.edge == "left" and -4 or (w - glowDepth + 4)
            g.setColor(rc[1], rc[2], rc[3], (0.20 + 0.16 * nearFactor) * pulse * fade)
            g.rectangle("fill", gx, gate.y - halfW, glowDepth, gate.width, 6, 6)
            g.setColor(rc[1], rc[2], rc[3], (0.85 + 0.15 * nearFactor) * fade)
            g.setLineWidth(4 + 2 * nearFactor)
            g.line(gate.x, gate.y - halfW, gate.x, gate.y + halfW)
            g.setColor(1, 1, 1, 0.85 * pulse * fade)
            g.setLineWidth(1.8)
            g.line(gate.x, gate.y - halfW * 0.72, gate.x, gate.y + halfW * 0.72)
            g.setColor(rc[1], rc[2], rc[3], 0.95 * fade)
            g.circle("fill", gate.x, gate.y - halfW, 5)
            g.circle("fill", gate.x, gate.y + halfW, 5)
        end

        -- 2. Animated directional chevrons pulling toward the warp boundary
        for c = 0, 2 do
            local phase = (time * 1.9 + c * 0.33) % 1
            local distIn = (1 - phase) * 46 + 8
            local cx = gate.x - gate.dirX * distIn
            local cy = gate.y - gate.dirY * distIn
            local cAlpha = math.sin(phase * math.pi) * (0.78 + 0.22 * nearFactor) * fade
            g.push()
            g.translate(cx, cy)
            g.rotate(gate.angle)
            g.setColor(rc[1], rc[2], rc[3], cAlpha)
            g.setLineWidth(2.2)
            g.line(-12, 6, 0, -6, 12, 6)
            g.pop()
        end

        -- 3. Holographic major reward card anchored neatly inside the arena
        local cardW, cardH = 196, 62
        local anchorDistX = horizontal and 0 or 118
        local anchorDistY = horizontal and 66 or 0
        local cardCx = clamp(gate.x - gate.dirX * anchorDistX, cardW * 0.5 + 14, w - cardW * 0.5 - 14)
        local cardCy = clamp(gate.y - gate.dirY * anchorDistY, cardH * 0.5 + 12, h - cardH * 0.5 - 12)
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

function StageTransition.newWarp(gate, nextStageNumber, ship, width, height, rng)
    rng = rng or (love and love.math and love.math.random or math.random)
    local streaks = {}
    local rc = gate.reward and gate.reward.color or { 0.45, 0.92, 1.0 }

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

    return {
        gate = gate,
        nextStageNumber = nextStageNumber or 2,
        elapsed = 0,
        duration = StageTransition.WARP_DURATION,
        startX = ship and ship.x or (Arena.width * 0.5),
        startY = ship and ship.y or (Arena.height * 0.5),
        startAngle = ship and ship.angle or gate.angle,
        speedFactor = 0,
        arriveSfxPlayed = false,
        streaks = streaks,
        done = false,
    }
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
        -- Smooth deceleration as we approach the next stage
        local decelT = (p - 0.58) / 0.42
        return math.pow(1 - decelT, 2.4)
    end
end

function StageTransition.updateWarp(warp, dt, ship, stars, camera, width, height)
    if not warp or warp.done or dt <= 0 then return warp and warp.done or false end
    warp.elapsed = warp.elapsed + dt
    local p = clamp(warp.elapsed / math.max(1e-6, warp.duration), 0, 1)
    local speedFactor = StageTransition.warpSpeedFactor(p)
    warp.speedFactor = speedFactor

    if p >= 0.60 and not warp.arriveSfxPlayed then
        warp.arriveSfxPlayed = true
        Sfx.play("warp_arrive")
    end

    local dirX, dirY = warp.gate.dirX, warp.gate.dirY

    -- Drive Starfield along warp direction so stars stretch & then calm down cleanly
    if stars then
        local starSpeed = 240 + 4600 * speedFactor
        stars:update(dt, dirX * starSpeed, dirY * starSpeed, speedFactor, width, height, speedFactor)
    end

    -- Stream hyperspace starlight streaks in opposite direction of ship flight
    local streakTravel = (0.18 + 3.2 * speedFactor) * dt
    for _, st in ipairs(warp.streaks) do
        st.nx = (st.nx - dirX * streakTravel * st.depth) % 1
        st.ny = (st.ny - dirY * streakTravel * st.depth) % 1
    end

    -- Smoothly align ship heading & engine plume with warp state
    if ship then
        local alignT = easeOutCubic(clamp(p / 0.22, 0, 1))
        local diff = shortestAngleDiff(warp.startAngle, warp.gate.angle)
        ship.angle = (warp.startAngle + diff * alignT) % (math.pi * 2)
        ship.boostLevel = speedFactor
        ship.accelerating = speedFactor > 0.05
        ship.braking = false
        ship.boostX, ship.boostY = dirX, dirY
        ship.boostRemaining = speedFactor * (ship.boostHold + ship.boostFalloff)
    end

    if camera and ship then
        camera:update(dt, ship, width, height)
    end

    if warp.elapsed >= warp.duration then
        warp.elapsed = warp.duration
        warp.done = true
        if ship then
            ship.x = Arena.width * 0.5
            ship.y = Arena.height * 0.5
            ship.angle = warp.gate.angle
            ship.vx = dirX * 42
            ship.vy = dirY * 42
            ship.wrapVx, ship.wrapVy = 0, 0
            ship.boostLevel = 0
            ship.boostRemaining = 0
            ship.accelerating = false
            ship.braking = false
        end
        return true
    end
    return false
end

function StageTransition.drawWarp(warp, ship, camera, width, height, time, fonts)
    if not warp then return end
    local g = love.graphics
    local p = clamp(warp.elapsed / math.max(1e-6, warp.duration), 0, 1)
    local sf = warp.speedFactor or StageTransition.warpSpeedFactor(p)
    local dirX, dirY = warp.gate.dirX, warp.gate.dirY
    local rc = warp.gate.reward and warp.gate.reward.color or { 0.45, 0.92, 1.0 }

    g.push("all")
    g.origin()

    -- 1. Hyperspace starlight streaks streaming past the ship
    local streakVisibility = clamp(sf * 1.25, 0, 1)
    if streakVisibility > 0.01 then
        for _, st in ipairs(warp.streaks) do
            local sx = st.nx * width
            local sy = st.ny * height
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
        g.rectangle("fill", 0, 0, width, height)
    end

    -- 2. Old arena sliding behind & fading out during initial warp departure (p < 0.36)
    local originX, originY = camera:worldToScreen(0, 0, width, height)
    if p < 0.36 then
        local departT = p / 0.36
        local slide = easeInCubic(departT) * 950
        local alpha = 1 - departT
        g.push("all")
        g.translate(originX - dirX * slide, originY - dirY * slide)
        g.scale(camera.zoom)
        Arena.draw(sf, 0)
        -- Fade mask to darken retiring arena smoothly
        g.setColor(0.018, 0.025, 0.065, 1 - alpha)
        g.rectangle("fill", -16, -16, Arena.width + 32, Arena.height + 32)
        g.pop()
    end

    -- 3. Next stage arena sliding smoothly in from ahead during deceleration (p > 0.58)
    if p > 0.58 then
        local arriveT = (p - 0.58) / 0.42
        local eased = easeOutCubic(arriveT)
        local slide = (1 - eased) * 820
        g.push("all")
        g.translate(originX + dirX * slide, originY + dirY * slide)
        g.scale(camera.zoom)
        Arena.draw(sf * 0.7, 0)
        g.pop()
    end

    -- 4. Draw ship gliding from departure point -> screen center during cruise -> new arena center on arrival
    if ship then
        local centerX, centerY = camera:worldToScreen(Arena.width * 0.5, Arena.height * 0.5, width, height)
        local startSx, startSy = camera:worldToScreen(warp.startX, warp.startY, width, height)
        local shipSx, shipSy

        if p < 0.30 then
            local t1 = easeInOutCubic(p / 0.30)
            shipSx = startSx + (centerX - startSx) * t1
            shipSy = startSy + (centerY - startSy) * t1
        elseif p < 0.62 then
            -- Subtle forward lunge + micro vibration at peak hyperspace cruise
            local vibX = math.sin(time * 64) * 1.8 * sf
            local vibY = math.cos(time * 73) * 1.8 * sf
            shipSx = centerX + dirX * 18 * sf + vibX
            shipSy = centerY + dirY * 18 * sf + vibY
        else
            -- Decelerate smoothly into the center of the incoming arena from the entry side
            local arriveT = (p - 0.62) / 0.38
            local eased = easeOutCubic(arriveT)
            local entryOffset = (1 - eased) * 150
            shipSx = centerX - dirX * entryOffset
            shipSy = centerY - dirY * entryOffset
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

    -- 5. Brief ignition & arrival light flashes
    if p < 0.16 then
        local flash = (1 - p / 0.16)
        g.setColor(rc[1], rc[2], rc[3], flash * flash * 0.42)
        g.rectangle("fill", 0, 0, width, height)
    elseif p > 0.90 then
        local flash = math.sin(((p - 0.90) / 0.10) * math.pi)
        g.setColor(0.75, 0.95, 1.0, flash * 0.18)
        g.rectangle("fill", 0, 0, width, height)
    end

    -- 6. Sleek Warp Telemetry HUD Banner
    local hudAlpha = math.sin(clamp(p, 0, 1) * math.pi)
    hudAlpha = clamp(hudAlpha * 2.1, 0, 1)
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
    local speedC = 0.2 + sf * 9.8
    g.setColor(0.62, 0.88, 0.98, 0.95 * hudAlpha)
    g.printf(string.format("HYPERDRIVE  %.1fc  /  STARLIGHT TRANSIT", speedC), px + 10, py + 10, panelW - 20, "center")

    g.setFont(fonts.menuButton or fonts.menuBody)
    g.setColor(1.0, 0.96, 0.80, hudAlpha)
    g.printf(string.format("STAGE %02d 워프 진입 중", warp.nextStageNumber), px + 10, py + 28, panelW - 20, "center")

    g.setFont(fonts.menuSmall or fonts.menuBody)
    g.setColor(rc[1], rc[2], rc[3], 0.95 * hudAlpha)
    g.printf("선택 보상: " .. (warp.gate.reward and warp.gate.reward.title or ""), px + 10, py + 54, panelW - 20, "center")

    g.pop()
end

return StageTransition
