-- Interactive Gladiator Coin Plinko UI overlay shown at the end of each stage.
-- Supports investing 10 / 25 / 50 / ALL coins (dropped randomly across the full
-- top width), opening the diamond grid inventory to equip newly won items,
-- and advancing straight to the next stage.

local PlinkoUI = {}
PlinkoUI.__index = PlinkoUI

function PlinkoUI.new()
    return setmetatable({
        hitRegions = {},
    }, PlinkoUI)
end

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function PlinkoUI:addRegion(x, y, w, h, action)
    self.hitRegions[#self.hitRegions + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function PlinkoUI:draw(plinko, stage, fonts, width, height)
    local g = love.graphics
    self.hitRegions = {}

    g.push("all")
    g.origin()
    g.setColor(0.014, 0.024, 0.048, 0.92)
    g.rectangle("fill", 0, 0, width, height)

    local panelW = math.min(980, width - 64)
    local panelH = math.min(640, height - 64)
    local px = math.floor((width - panelW) / 2)
    local py = math.floor((height - panelH) / 2)

    g.setColor(0.030, 0.054, 0.088, 0.98)
    g.rectangle("fill", px, py, panelW, panelH, 10, 10)
    g.setColor(1.0, 0.78, 0.32, 0.55)
    g.setLineWidth(1.5)
    g.rectangle("line", px, py, panelW, panelH, 10, 10)

    -- Header
    g.setFont(fonts.menuTitle)
    g.setColor(1.0, 0.88, 0.48, 1)
    g.print(string.format("STAGE %d 클리어 · 스폰서 플링코", stage and stage.number or 1), px + 26, py + 16)

    g.setFont(fonts.menuBody)
    g.setColor(0.72, 0.88, 0.96, 1)
    local reasonText = (stage and stage.clearReason == "ALL HOSTILES CLEARED")
        and "모든 적 섬멸 조기 클리어!" or "스테이지 제한 시간 종료"
    g.print(reasonText .. "  ·  상단 전체에서 무작위로 코인이 떨어집니다.", px + 28, py + 58)

    -- Left: Plinko Board
    local bx = px + 32
    local by = py + 100
    local bw, bh = plinko.boardW, plinko.boardH

    g.setColor(0.020, 0.036, 0.062, 0.98)
    g.rectangle("fill", bx, by, bw, bh, 8, 8)
    g.setColor(0.32, 0.68, 0.82, 0.55)
    g.setLineWidth(1.5)
    g.rectangle("line", bx, by, bw, bh, 8, 8)

    -- Top random-drop zone indicator
    g.setColor(1.0, 0.82, 0.36, 0.14)
    g.rectangle("fill", bx + 16, by + 6, bw - 32, 18, 4, 4)
    g.setFont(fonts.small)
    g.setColor(1.0, 0.86, 0.48, 0.85)
    g.printf("RANDOM DROP ZONE", bx, by + 9, bw, "center")

    -- Pegs
    for _, peg in ipairs(plinko.pegs) do
        g.setColor(0.42, 0.82, 0.94, 0.85)
        g.circle("fill", bx + peg.x, by + peg.y, peg.radius)
        g.setColor(0.84, 0.97, 1.0, 0.9)
        g.circle("fill", bx + peg.x - 1, by + peg.y - 1, peg.radius * 0.4)
    end

    -- Falling Gladiator Coins
    for _, c in ipairs(plinko.activeCoins) do
        g.setColor(1.0, 0.78, 0.24, 0.95)
        g.circle("fill", bx + c.x, by + c.y, c.radius)
        g.setColor(1.0, 0.95, 0.70, 0.95)
        g.circle("line", bx + c.x, by + c.y, c.radius)
    end

    -- 5 Bottom Reward Slots
    local slotY = by + plinko.slotTopY
    local slotH = bh - plinko.slotTopY - 6
    for i, slot in ipairs(plinko.slots) do
        local sx = bx + slot.x + 3
        local sw = slot.w - 6
        local rc = slot.reward.color or { 0.45, 0.85, 0.95 }
        local ratio = math.min(1, slot.filled / math.max(1, slot.required))

        g.setColor(0.05, 0.08, 0.13, 0.96)
        g.rectangle("fill", sx, slotY, sw, slotH, 5, 5)

        -- Vertical fill progress gauge
        if ratio > 0 then
            local fillH = math.floor((slotH - 4) * ratio)
            g.setColor(rc[1], rc[2], rc[3], slot.claimed and 0.45 or 0.26)
            g.rectangle("fill", sx + 2, slotY + slotH - 2 - fillH, sw - 4, fillH, 4, 4)
        end

        g.setColor(rc[1], rc[2], rc[3], slot.claimed and 1.0 or (slot.tier == "high" and 0.90 or 0.55))
        g.setLineWidth(slot.claimed and 2.5 or 1.3)
        g.rectangle("line", sx, slotY, sw, slotH, 5, 5)

        g.setFont(fonts.small)
        g.setColor(rc[1], rc[2], rc[3], 0.95)
        g.printf(slot.reward.short, sx + 2, slotY + 7, sw - 4, "center")

        g.setFont(fonts.body)
        if slot.claimed then
            g.setColor(0.48, 0.98, 0.66, 1)
            g.printf("GET!", sx + 2, slotY + 25, sw - 4, "center")
        else
            g.setColor(0.95, 0.97, 1, 1)
            g.printf(string.format("%d/%d", slot.filled, slot.required), sx + 2, slotY + 25, sw - 4, "center")
        end

        g.setFont(fonts.small)
        g.setColor(0.66, 0.78, 0.86, 0.85)
        g.printf(slot.reward.rarity, sx + 2, slotY + 45, sw - 4, "center")
    end

    -- Slot detailed legend below board
    local legY = by + bh + 12
    g.setFont(fonts.menuBody)
    for i, slot in ipairs(plinko.slots) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local lx = bx + col * 278
        local ly = legY + row * 24
        local rc = slot.reward.color or { 0.7, 0.85, 0.95 }
        g.setColor(rc[1], rc[2], rc[3], slot.claimed and 1.0 or 0.85)
        local status = slot.claimed and "[획득]" or string.format("(%d/%d)", slot.filled, slot.required)
        g.print(string.format("%d. %s %s", i, slot.reward.title, status), lx, ly)
    end

    -- Right: Coin Wallet, Investment Buttons, Claimed Log & Next Stage
    local rx = bx + bw + 26
    local rw = px + panelW - rx - 26
    local ry = by

    -- Wallet box
    g.setColor(0.05, 0.09, 0.14, 0.95)
    g.rectangle("fill", rx, ry, rw, 108, 8, 8)
    g.setColor(1.0, 0.80, 0.34, 0.6)
    g.setLineWidth(1.2)
    g.rectangle("line", rx, ry, rw, 108, 8, 8)

    g.setFont(fonts.menuBody)
    g.setColor(1.0, 0.84, 0.44, 1)
    g.printf("보유 글래디에이터 코인", rx + 12, ry + 12, rw - 24, "center")
    g.setFont(fonts.title)
    g.setColor(1.0, 0.93, 0.62, 1)
    g.printf(tostring(plinko.coins), rx + 12, ry + 38, rw - 24, "center")
    g.setFont(fonts.small)
    g.setColor(0.68, 0.80, 0.88, 0.9)
    g.printf(string.format("INVESTED: %d   QUEUED: %d", plinko.invested, plinko.dropQueue),
        rx + 12, ry + 82, rw - 24, "center")

    -- Investment buttons
    local invY = ry + 124
    local dropButtons = {
        { label = "+10 코인 투하", amount = 10 },
        { label = "+25 코인 투하", amount = 25 },
        { label = "+50 코인 투하", amount = 50 },
        { label = "남은 코인 올인", amount = plinko.coins },
    }
    for i, b in ipairs(dropButtons) do
        local byBtn = invY + (i - 1) * 44
        local enabled = plinko.coins > 0 and b.amount > 0
        g.setColor(enabled and 0.18 or 0.07, enabled and 0.22 or 0.10, enabled and 0.12 or 0.14, 0.95)
        g.rectangle("fill", rx, byBtn, rw, 36, 6, 6)
        g.setColor(1.0, 0.80, 0.34, enabled and 0.85 or 0.25)
        g.setLineWidth(1.2)
        g.rectangle("line", rx, byBtn, rw, 36, 6, 6)
        g.setFont(fonts.menuButton)
        g.setColor(enabled and 1.0 or 0.45, enabled and 0.92 or 0.50, enabled and 0.64 or 0.56, 1)
        g.printf(b.label, rx, byBtn + 8, rw, "center")
        if enabled then
            self:addRegion(rx, byBtn, rw, 36, { type = "invest", amount = b.amount })
        end
    end

    -- Claimed rewards box
    local logY = invY + 186
    g.setColor(0.04, 0.08, 0.12, 0.95)
    g.rectangle("fill", rx, logY, rw, 114, 8, 8)
    g.setColor(0.32, 0.64, 0.76, 0.45)
    g.rectangle("line", rx, logY, rw, 114, 8, 8)
    g.setFont(fonts.menuBody)
    g.setColor(0.56, 0.92, 0.76, 1)
    g.print("획득한 보상 (" .. #plinko.claimedLog .. ")", rx + 12, logY + 8)
    g.setColor(0.88, 0.95, 0.98, 0.95)
    for i = 1, math.min(3, #plinko.claimedLog) do
        g.print("· " .. plinko.claimedLog[#plinko.claimedLog - i + 1], rx + 14, logY + 34 + (i - 1) * 24)
    end

    -- Bottom action buttons: Inventory + Next Stage
    local actY = py + panelH - 58
    local halfW = math.floor((rw - 10) / 2)

    g.setColor(0.10, 0.20, 0.28, 0.95)
    g.rectangle("fill", rx, actY, halfW, 40, 6, 6)
    g.setColor(0.42, 0.84, 0.94, 0.8)
    g.rectangle("line", rx, actY, halfW, 40, 6, 6)
    g.setFont(fonts.menuBody)
    g.setColor(0.92, 0.98, 1, 1)
    g.printf("인벤토리 (I)", rx, actY + 11, halfW, "center")
    self:addRegion(rx, actY, halfW, 40, { type = "openInventory" })

    local nx = rx + halfW + 10
    g.setColor(0.14, 0.30, 0.22, 0.95)
    g.rectangle("fill", nx, actY, halfW, 40, 6, 6)
    g.setColor(0.46, 0.94, 0.68, 0.9)
    g.rectangle("line", nx, actY, halfW, 40, 6, 6)
    g.setFont(fonts.menuBody)
    g.setColor(0.92, 1, 0.95, 1)
    g.printf("다음 스테이지 →", nx, actY + 11, halfW, "center")
    self:addRegion(nx, actY, halfW, 40, { type = "nextStage" })

    g.pop()
end

function PlinkoUI:mousepressed(plinko, x, y, button)
    if button ~= 1 then return nil end
    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            local a = r.action
            if a.type == "invest" then
                plinko:invest(a.amount)
                return "invested"
            elseif a.type == "openInventory" then
                return "openInventory"
            elseif a.type == "nextStage" then
                return "nextStage"
            end
        end
    end
    return nil
end

return PlinkoUI
