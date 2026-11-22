-- Interactive Hangar / Diamond Grid Inventory Overlay for LÖVE.
-- Lets players test placing/rotating modules on the 3x3 -> 5x5 diamond grid,
-- expanding locked outer diamond cells, unlocking core-connected links, and
-- plugging support chips into module sockets.

local Inventory = require("inventory")
local Sfx = require("sfx")

local InventoryUI = {}
InventoryUI.__index = InventoryUI

function InventoryUI.new()
    return setmetatable({
        selectedModule = nil,
        selectedChip = nil,
        selectedSocket = 1,
        message = "모듈이나 칩을 클릭해 배치·장착하세요. (R: 회전, TAB/ESC: 닫기)",
        hitRegions = {},
        hoveredIndex = nil,
    }, InventoryUI)
end

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function socketPositions(mod, x, y, w, h)
    local positions = {}
    local n = mod.maxSockets or 1
    if n == 1 then
        positions[1] = { x + w * 0.5, y + h * 0.5 }
    elseif n == 2 then
        if w >= h then
            positions[1] = { x + w * 0.30, y + h * 0.55 }
            positions[2] = { x + w * 0.70, y + h * 0.55 }
        else
            positions[1] = { x + w * 0.50, y + h * 0.34 }
            positions[2] = { x + w * 0.50, y + h * 0.72 }
        end
    elseif n == 3 then
        if w >= h then
            positions[1] = { x + w * 0.22, y + h * 0.56 }
            positions[2] = { x + w * 0.50, y + h * 0.56 }
            positions[3] = { x + w * 0.78, y + h * 0.56 }
        else
            positions[1] = { x + w * 0.50, y + h * 0.24 }
            positions[2] = { x + w * 0.50, y + h * 0.54 }
            positions[3] = { x + w * 0.50, y + h * 0.82 }
        end
    else
        positions[1] = { x + w * 0.30, y + h * 0.34 }
        positions[2] = { x + w * 0.70, y + h * 0.34 }
        positions[3] = { x + w * 0.70, y + h * 0.72 }
        positions[4] = { x + w * 0.30, y + h * 0.72 }
    end
    return positions
end

function InventoryUI:addRegion(x, y, w, h, action)
    self.hitRegions[#self.hitRegions + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function InventoryUI:draw(inv, fonts, width, height, feverActive)
    local g = love.graphics
    self.hitRegions = {}

    g.push("all")
    g.origin()
    g.setColor(0.015, 0.025, 0.050, 0.90)
    g.rectangle("fill", 0, 0, width, height)

    local panelW = math.min(1040, width - 64)
    local panelH = math.min(660, height - 64)
    local px = math.floor((width - panelW) / 2)
    local py = math.floor((height - panelH) / 2)

    g.setColor(0.032, 0.058, 0.092, 0.98)
    g.rectangle("fill", px, py, panelW, panelH, 10, 10)
    g.setColor(0.32, 0.72, 0.84, 0.55)
    g.setLineWidth(1.5)
    g.rectangle("line", px, py, panelW, panelH, 10, 10)

    -- Header
    g.setFont(fonts.menuTitle)
    g.setColor(0.88, 0.96, 1.0, 1)
    g.print("함선 격자 정비소", px + 24, py + 16)

    g.setFont(fonts.menuBody)
    g.setColor(0.62, 0.84, 0.92, 1)
    local cellInfo = string.format("확장 슬롯 %d / %d  (3x3 → 5x5 다이아몬드)",
        inv:unlockedCellCount(), inv:maxCellCount())
    g.print(cellInfo, px + 26, py + 58)

    -- Close button
    local closeX, closeY, closeW, closeH = px + panelW - 126, py + 20, 102, 34
    g.setColor(0.14, 0.24, 0.32, 0.95)
    g.rectangle("fill", closeX, closeY, closeW, closeH, 6, 6)
    g.setColor(0.45, 0.86, 0.95, 0.8)
    g.rectangle("line", closeX, closeY, closeW, closeH, 6, 6)
    g.setFont(fonts.menuBody)
    g.setColor(0.92, 0.98, 1, 1)
    g.printf("전투 복귀", closeX, closeY + 8, closeW, "center")
    self:addRegion(closeX, closeY, closeW, closeH, { type = "close" })

    -- Left: 5x5 Diamond Grid
    local cellSize = 78
    local gap = 6
    local gridSpan = inv.gridSize * cellSize + (inv.gridSize - 1) * gap
    local gx = px + 34
    local gy = py + 102

    for r = 1, inv.gridSize do
        for c = 1, inv.gridSize do
            local cx = gx + (c - 1) * (cellSize + gap)
            local cy = gy + (r - 1) * (cellSize + gap)
            if Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then
                if inv:isUnlocked(r, c) then
                    g.setColor(0.06, 0.13, 0.19, 0.95)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    g.setColor(0.32, 0.72, 0.86, 0.55)
                    g.setLineWidth(1.2)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                    self:addRegion(cx, cy, cellSize, cellSize, { type = "gridCell", r = r, c = c })
                elseif inv:canUnlockCell(r, c) then
                    g.setColor(0.12, 0.14, 0.08, 0.65)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    g.setColor(0.96, 0.76, 0.34, 0.72)
                    g.setLineWidth(1.2)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                    g.setFont(fonts.body)
                    g.setColor(1.0, 0.84, 0.44, 0.95)
                    g.printf("+ OPEN", cx, cy + cellSize * 0.40, cellSize, "center")
                    self:addRegion(cx, cy, cellSize, cellSize, { type = "unlockCell", r = r, c = c })
                else
                    g.setColor(0.03, 0.05, 0.08, 0.55)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    g.setColor(0.22, 0.30, 0.38, 0.35)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                end
            end
        end
    end

    -- Draw placed modules on top of the diamond grid
    for _, mod in ipairs(inv.placed) do
        local mx = gx + (mod.col - 1) * (cellSize + gap) + 3
        local my = gy + (mod.row - 1) * (cellSize + gap) + 3
        local mw = mod.w * cellSize + (mod.w - 1) * gap - 6
        local mh = mod.h * cellSize + (mod.h - 1) * gap - 6
        local col = mod.def.color or { 0.4, 0.8, 0.9 }
        local isSel = (self.selectedModule == mod)

        g.setColor(col[1] * 0.28, col[2] * 0.28, col[3] * 0.28, 0.95)
        g.rectangle("fill", mx, my, mw, mh, 7, 7)
        g.setColor(col[1], col[2], col[3], isSel and 1.0 or 0.78)
        g.setLineWidth(isSel and 2.8 or 1.6)
        g.rectangle("line", mx, my, mw, mh, 7, 7)

        g.setFont(fonts.small)
        g.setColor(0.95, 0.98, 1.0, 0.95)
        g.printf(mod.def.shortName, mx + 4, my + 4, mw - 8, "left")

        -- Draw internal links & sockets
        local pos = socketPositions(mod, mx, my, mw, mh)
        local active = inv:getActiveSockets(mod)
        for _, edge in ipairs(mod.def.allLinks or {}) do
            local p1, p2 = pos[edge[1]], pos[edge[2]]
            if p1 and p2 then
                local linked = inv:hasLink(mod, edge[1], edge[2])
                if linked then
                    g.setColor(0.45, 0.95, 1.0, 0.92)
                    g.setLineWidth(3)
                else
                    g.setColor(0.35, 0.42, 0.50, 0.35)
                    g.setLineWidth(1.5)
                end
                g.line(p1[1], p1[2], p2[1], p2[2])
            end
        end

        for i = 1, mod.maxSockets do
            local p = pos[i]
            local chip = mod.sockets[i]
            local rSock = 11
            if chip then
                local cc = chip.def.color or { 1, 0.8, 0.3 }
                g.setColor(cc[1], cc[2], cc[3], active[i] and 0.95 or 0.35)
                g.circle("fill", p[1], p[2], rSock)
            else
                g.setColor(0.05, 0.08, 0.12, 0.95)
                g.circle("fill", p[1], p[2], rSock)
            end
            if i == 1 then
                g.setColor(1.0, 0.86, 0.36, 1.0)
                g.setLineWidth(2.2)
            elseif active[i] then
                g.setColor(0.45, 0.92, 1.0, 0.95)
                g.setLineWidth(1.6)
            else
                g.setColor(0.45, 0.50, 0.56, 0.55)
                g.setLineWidth(1.2)
            end
            g.circle("line", p[1], p[2], rSock)

            g.setFont(fonts.small)
            g.setColor(0.05, 0.08, 0.12, 1)
            if chip then
                g.printf(string.sub(chip.def.shortName, 1, 2), p[1] - 11, p[2] - 6, 22, "center")
            elseif i == 1 then
                g.setColor(1.0, 0.88, 0.42, 1)
                g.printf("C", p[1] - 8, p[2] - 6, 16, "center")
            end
            self:addRegion(p[1] - rSock, p[2] - rSock, rSock * 2, rSock * 2,
                { type = "socket", mod = mod, socketIndex = i })
        end

        self:addRegion(mx, my, mw, mh, { type = "placedModule", mod = mod })
    end

    -- Right Panel: Selected Module Controls + Stash Modules + Stash Chips
    local rx = gx + gridSpan + 28
    local rw = px + panelW - rx - 24
    local curY = py + 102

    -- Selected module inspector
    g.setColor(0.05, 0.09, 0.14, 0.95)
    g.rectangle("fill", rx, curY, rw, 132, 8, 8)
    g.setColor(0.28, 0.56, 0.68, 0.5)
    g.setLineWidth(1)
    g.rectangle("line", rx, curY, rw, 132, 8, 8)

    g.setFont(fonts.menuBody)
    if self.selectedModule then
        local m = self.selectedModule
        g.setColor(0.94, 0.98, 1.0, 1)
        g.print(string.format("%s (%dx%d) · 활성 소켓 %d/%d",
            m.def.name, m.w, m.h, inv:activeSocketCount(m), m.maxSockets), rx + 12, curY + 10)
        g.setFont(fonts.menuBody)
        g.setColor(0.68, 0.82, 0.88, 0.95)
        g.printf(m.def.description, rx + 12, curY + 36, rw - 24, "left")

        local btnY = curY + 90
        local btns = {
            { label = "회전(R)", action = { type = "rotateSelected" } },
            { label = "링크 연결", action = { type = "unlockLink" } },
            { label = m.row and "보관함으로" or "선택 해제", action = { type = "unplaceSelected" } },
        }
        local bw = math.floor((rw - 40) / #btns)
        for i, b in ipairs(btns) do
            local bx = rx + 12 + (i - 1) * (bw + 8)
            g.setColor(0.12, 0.22, 0.30, 0.95)
            g.rectangle("fill", bx, btnY, bw, 30, 5, 5)
            g.setColor(0.42, 0.80, 0.92, 0.75)
            g.rectangle("line", bx, btnY, bw, 30, 5, 5)
            g.setFont(fonts.menuBody)
            g.setColor(0.92, 0.97, 1, 1)
            g.printf(b.label, bx, btnY + 6, bw, "center")
            self:addRegion(bx, btnY, bw, 30, b.action)
        end
    else
        g.setColor(0.62, 0.74, 0.82, 0.95)
        g.printf("좌측 그리드 또는 아래 보관함에서 모듈을 선택하세요.", rx + 12, curY + 46, rw - 24, "center")
    end

    curY = curY + 146

    -- Stash Modules
    g.setFont(fonts.menuBody)
    g.setColor(0.75, 0.90, 0.96, 1)
    g.print("모듈 보관함 (" .. #inv.stashModules .. ")", rx, curY)
    curY = curY + 26
    local modCols = 3
    local itemW = math.floor((rw - (modCols - 1) * 8) / modCols)
    local itemH = 34
    for i, mod in ipairs(inv.stashModules) do
        local colIdx = (i - 1) % modCols
        local rowIdx = math.floor((i - 1) / modCols)
        local ix = rx + colIdx * (itemW + 8)
        local iy = curY + rowIdx * (itemH + 6)
        local isSel = (self.selectedModule == mod)
        local mc = mod.def.color or { 0.4, 0.8, 0.9 }
        g.setColor(mc[1] * 0.24, mc[2] * 0.24, mc[3] * 0.24, 0.95)
        g.rectangle("fill", ix, iy, itemW, itemH, 5, 5)
        g.setColor(mc[1], mc[2], mc[3], isSel and 1 or 0.65)
        g.setLineWidth(isSel and 2.2 or 1.2)
        g.rectangle("line", ix, iy, itemW, itemH, 5, 5)
        g.setFont(fonts.small)
        g.setColor(0.94, 0.98, 1, 1)
        g.printf(string.format("%s (%dx%d)", mod.def.shortName, mod.w, mod.h), ix + 4, iy + 10, itemW - 8, "center")
        self:addRegion(ix, iy, itemW, itemH, { type = "stashModule", mod = mod })
    end

    curY = curY + math.max(1, math.ceil(#inv.stashModules / modCols)) * (itemH + 6) + 14

    -- Stash Support Chips
    g.setFont(fonts.menuBody)
    g.setColor(1.0, 0.86, 0.46, 1)
    g.print("서포트 칩 보관함 (" .. #inv.stashChips .. ")", rx, curY)
    curY = curY + 26
    for i, chip in ipairs(inv.stashChips) do
        local colIdx = (i - 1) % modCols
        local rowIdx = math.floor((i - 1) / modCols)
        local ix = rx + colIdx * (itemW + 8)
        local iy = curY + rowIdx * (itemH + 6)
        if iy + itemH < py + panelH - 46 then
            local isSel = (self.selectedChip == chip)
            local cc = chip.def.color or { 1, 0.8, 0.3 }
            g.setColor(cc[1] * 0.22, cc[2] * 0.22, cc[3] * 0.22, 0.95)
            g.rectangle("fill", ix, iy, itemW, itemH, 5, 5)
            g.setColor(cc[1], cc[2], cc[3], isSel and 1 or 0.65)
            g.setLineWidth(isSel and 2.2 or 1.2)
            g.rectangle("line", ix, iy, itemW, itemH, 5, 5)
            g.setFont(fonts.small)
            g.setColor(0.96, 0.98, 1, 1)
            g.printf(chip.def.shortName .. " [" .. chip.def.target .. "]", ix + 4, iy + 10, itemW - 8, "center")
            self:addRegion(ix, iy, itemW, itemH, { type = "stashChip", chip = chip })
        end
    end

    -- Build summary footer
    local build = inv:computeBuild(feverActive)
    g.setFont(fonts.menuBody)
    g.setColor(0.84, 0.93, 0.98, 1)
    g.print(self.message, px + 26, py + panelH - 36)
    g.setFont(fonts.small)
    g.setColor(0.60, 0.82, 0.90, 0.9)
    local summary = string.format("SHIELD +%d  ARMOR +%d  BATT +%d  SCORE x%.1f",
        build.maxShieldBonus, build.maxArmorBonus, build.maxBatteryBonus, build.scoreMultiplier)
    g.printf(summary, px + panelW - 360, py + panelH - 32, 336, "right")

    g.pop()
end

function InventoryUI:mousepressed(inv, x, y, button)
    if button ~= 1 then return nil end
    -- Iterate in reverse so top-most elements (sockets > modules > cells) win
    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            local a = r.action
            if a.type == "close" then
                Sfx.play("ui_click")
                return "close"
            elseif a.type == "unlockCell" then
                local ok = inv:unlockCell(a.r, a.c)
                if ok then
                    Sfx.play("ui_equip")
                    self.message = string.format("그리드 (%d,%d) 칸을 확장했습니다!", a.r, a.c)
                    return "changed"
                end
            elseif a.type == "socket" then
                if self.selectedChip then
                    local ok, reason = inv:equipChip(a.mod, a.socketIndex, self.selectedChip)
                    if ok then
                        Sfx.play("ui_equip")
                        self.message = self.selectedChip.def.name .. " 장착 완료!"
                        self.selectedChip = nil
                        self.selectedModule = a.mod
                        return "changed"
                    else
                        Sfx.play("ui_error")
                        self.message = "장착 불가: 대상 카테고리 불일치 (" .. tostring(reason) .. ")"
                    end
                elseif a.mod.sockets[a.socketIndex] then
                    local removed = inv:unequipChip(a.mod, a.socketIndex)
                    Sfx.play("ui_click")
                    self.message = removed.def.name .. " 칩을 분리했습니다."
                    self.selectedModule = a.mod
                    return "changed"
                else
                    self.selectedModule = a.mod
                    self.selectedSocket = a.socketIndex
                    self.message = string.format("%s 소켓 #%d 선택됨 (장착할 칩을 고르세요)", a.mod.def.name, a.socketIndex)
                end
                return nil
            elseif a.type == "placedModule" then
                self.selectedModule = a.mod
                self.selectedChip = nil
                self.message = a.mod.def.name .. " 선택됨"
                return nil
            elseif a.type == "stashModule" then
                self.selectedModule = a.mod
                self.selectedChip = nil
                Sfx.play("ui_click")
                self.message = a.mod.def.name .. " 선택됨 — 그리드 빈 칸을 클릭해 배치하세요."
                return nil
            elseif a.type == "stashChip" then
                self.selectedChip = a.chip
                Sfx.play("ui_click")
                self.message = a.chip.def.name .. " 선택됨 — 모듈 안의 소켓 원을 클릭해 장착하세요."
                return nil
            elseif a.type == "gridCell" then
                if self.selectedModule then
                    local ok, reason = inv:placeModule(self.selectedModule, a.r, a.c)
                    if ok then
                        Sfx.play("ui_equip")
                        self.message = self.selectedModule.def.name .. " 배치 완료!"
                        return "changed"
                    else
                        Sfx.play("ui_error")
                        self.message = "배치 불가: 공간이 부족하거나 잠긴 칸입니다 (" .. tostring(reason) .. ")"
                    end
                end
                return nil
            elseif a.type == "rotateSelected" and self.selectedModule then
                if inv:rotateModule(self.selectedModule) then
                    Sfx.play("ui_equip")
                    self.message = self.selectedModule.def.name .. " 회전 완료"
                    return "changed"
                else
                    Sfx.play("ui_error")
                    self.message = "현재 위치에서는 회전할 공간이 부족합니다."
                end
                return nil
            elseif a.type == "unlockLink" and self.selectedModule then
                local ok = inv:unlockNextLink(self.selectedModule)
                if ok then
                    Sfx.play("ui_equip")
                    self.message = self.selectedModule.def.name .. " 링크 1개 연결 완료!"
                    return "changed"
                else
                    Sfx.play("ui_error")
                    self.message = "이미 모든 링크가 연결되어 있습니다."
                end
                return nil
            elseif a.type == "unplaceSelected" and self.selectedModule then
                if self.selectedModule.row then
                    Sfx.play("ui_click")
                    inv:removeModule(self.selectedModule, true)
                    self.message = self.selectedModule.def.name .. "을(를) 보관함으로 이동했습니다."
                    return "changed"
                else
                    self.selectedModule = nil
                    self.message = "선택을 해제했습니다."
                end
                return nil
            end
        end
    end
    return nil
end

function InventoryUI:keypressed(inv, key)
    if key == "r" and self.selectedModule then
        if inv:rotateModule(self.selectedModule) then
            self.message = self.selectedModule.def.name .. " 회전 완료"
            return "changed"
        else
            self.message = "현재 위치에서는 회전할 공간이 부족합니다."
        end
    end
    return nil
end

function InventoryUI:mousemoved(x, y)
    local found = nil
    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            found = i
            break
        end
    end
    if found and found ~= self.hoveredIndex then
        Sfx.play("ui_hover")
    end
    self.hoveredIndex = found
end

return InventoryUI
