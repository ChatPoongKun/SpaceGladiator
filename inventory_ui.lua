-- Interactive Hangar / 4x4 -> 6x6 Diamond Grid Inventory Overlay for LÖVE.
-- All items (modules and support chips) are drawn in their actual grid shapes
-- and moved/equipped via click-and-drop. Pressing R while holding an item
-- rotates it 90 degrees clockwise. No separate permanent stash exists: stage-end
-- rewards appear in a temporary tray and are discarded if not placed into the
-- main diamond inventory before advancing to the next stage.

local Inventory = require("inventory")
local ChipsData = require("chips_data")
local Sfx = require("sfx")

local InventoryUI = {}
InventoryUI.__index = InventoryUI

local imageCache = {}

local function getItemImage(item)
    if not (love and love.graphics and item and item.def and item.def.image) then
        return nil
    end
    local path = item.def.image
    local cached = imageCache[path]
    if cached ~= nil then
        return cached or nil
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("linear", "linear")
        imageCache[path] = img
        return img
    end
    imageCache[path] = false
    return nil
end

local targetShortTag = {
    weapon = "WPN",
    defense = "DEF",
    battery = "BAT",
    thruster = "THR",
    any = "ANY",
}

local targetKoreanLabel = {
    weapon = "무기 모듈",
    defense = "방어 모듈",
    battery = "배터리 모듈",
    thruster = "추진 모듈",
    any = "모든 모듈",
}

function InventoryUI.new()
    return setmetatable({
        selectedItem = nil,
        selectedModule = nil,
        dragging = nil,
        mouseX = 0,
        mouseY = 0,
        message = "아이템을 클릭·드래그해 격자에 배치하세요. (클릭 유지 + R: 회전, 우클릭: 취소)",
        hitRegions = {},
        hoveredIndex = nil,
        hoveredItem = nil,
        gridRect = nil,
        pendingTrayRect = nil,
        discardRect = nil,
    }, InventoryUI)
end

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function InventoryUI:addRegion(x, y, w, h, action)
    self.hitRegions[#self.hitRegions + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function InventoryUI:cancelDrag(inv)
    local d = self.dragging
    if not d then return false end
    self.dragging = nil
    local item = d.item
    if d.origin == "grid" then
        inv:placeItem(item, d.origRow, d.origCol, d.origRotation)
    elseif d.origin == "socket" then
        inv:equipChip(d.origMod, d.origSocketIndex, item)
    elseif d.origin == "tray" then
        local rot = Inventory.normalizeRotation(d.origRotation)
        local _, w, h = Inventory.getShapeCells(item, rot)
        item.rotation = rot
        item.rotated = (rot % 2 == 1)
        item.w, item.h = w, h
        inv:addPendingItem(item)
    end
    return true
end

function InventoryUI:startDrag(inv, item, origin, x, y, extra)
    if self.dragging then
        self:cancelDrag(inv)
    end
    extra = extra or {}
    local origRow, origCol = item.row, item.col
    local origRotation = item.rotation or 0
    local origMod, origSocketIndex = extra.mod, extra.socketIndex

    if origin == "grid" then
        inv:removeItem(item, false)
    elseif origin == "socket" then
        inv:unequipChip(origMod, origSocketIndex)
    elseif origin == "tray" then
        inv:removePendingItem(item)
    end

    self.dragging = {
        item = item,
        kind = item.kind,
        origin = origin,
        origRow = origRow,
        origCol = origCol,
        origRotation = origRotation,
        origMod = origMod,
        origSocketIndex = origSocketIndex,
        startX = x,
        startY = y,
        moved = false,
        rotated = false,
        sticky = false,
        rotation = origRotation,
    }
    self.selectedItem = item
    if item.kind == "module" then
        self.selectedModule = item
    end
    Sfx.play("ui_click")
end

-- Computes the grid cell (r, c) directly under pixel (px, py)
function InventoryUI:pixelToDirectCell(px, py)
    local gr = self.gridRect
    if not gr then return nil, nil end
    local step = gr.cellSize + gr.gap
    if not pointInRect(px, py, gr.x - 4, gr.y - 4, gr.span + 8, gr.span + 8) then
        return nil, nil
    end
    local col = math.floor((px - gr.x) / step) + 1
    local row = math.floor((py - gr.y) / step) + 1
    if row < 1 or row > gr.gridSize or col < 1 or col > gr.gridSize then
        return nil, nil
    end
    return row, col
end

-- Computes the snapped top-left grid cell (row, col) for a dragged item centered at (px, py)
function InventoryUI:computeSnappedOrigin(item, rotation, px, py)
    local gr = self.gridRect
    if not gr then return nil, nil end
    local _, w, h = Inventory.getShapeCells(item, rotation)
    local step = gr.cellSize + gr.gap
    local itemW = w * gr.cellSize + (w - 1) * gr.gap
    local itemH = h * gr.cellSize + (h - 1) * gr.gap
    local margin = gr.cellSize * 0.65
    if not pointInRect(px, py, gr.x - margin, gr.y - margin, gr.span + margin * 2, gr.span + margin * 2) then
        return nil, nil
    end
    local topLeftX = px - itemW * 0.5
    local topLeftY = py - itemH * 0.5
    local col = math.floor((topLeftX - gr.x + step * 0.5) / step) + 1
    local row = math.floor((topLeftY - gr.y + step * 0.5) / step) + 1
    return row, col
end

local function isPointOverShape(item, originX, originY, cellSize, gap, mx, my, rotation)
    local step = cellSize + gap
    local rot = Inventory.normalizeRotation(rotation ~= nil and rotation or item.rotation)
    local shapeCells = Inventory.getShapeCells(item, rot)
    for _, coord in ipairs(shapeCells) do
        local cx = originX + coord[2] * step
        local cy = originY + coord[1] * step
        if pointInRect(mx, my, cx, cy, cellSize, cellSize) then
            return true
        end
    end
    return false
end

-- Draws any item (module or support chip) as its visual grid cell shape
-- with grid-proportioned artwork rotated to match the item's orientation.
-- Slot/socket overlays are hidden by default so the artwork stays prominent,
-- and are revealed when hovered (opts.showSlots = true).
local function drawItemGridShape(inv, item, originX, originY, cellSize, gap, fonts, opts)
    opts = opts or {}
    local g = love.graphics
    local step = cellSize + gap
    local rot = Inventory.normalizeRotation(opts.rotation ~= nil and opts.rotation or item.rotation)
    local shapeCells, bw, bh = Inventory.getShapeCells(item, rot)
    local col = item.def.color or { 0.4, 0.8, 0.9 }
    local alpha = opts.alpha or 1.0
    local isSel = opts.selected == true
    local isHovered = opts.hovered == true
    local showSlots = opts.showSlots == true
    local compact = cellSize < 42
    local img = getItemImage(item)

    -- Build lookup for cell adjacency so multi-cell modules look cohesive.
    local occupied = {}
    for _, coord in ipairs(shapeCells) do
        occupied[coord[1] .. "," .. coord[2]] = true
    end

    -- 1. Draw clean dark backing so detailed artwork stands out clearly
    for _, coord in ipairs(shapeCells) do
        local dr, dc = coord[1], coord[2]
        local cx = originX + dc * step + 1
        local cy = originY + dr * step + 1
        local cw = cellSize - 2
        local ch = cellSize - 2

        if occupied[dr .. "," .. (dc + 1)] then
            g.setColor(0.03 + col[1] * 0.09, 0.05 + col[2] * 0.09, 0.08 + col[3] * 0.09, 0.94 * alpha)
            g.rectangle("fill", cx + cw - 2, cy + 2, gap + 6, ch - 4)
        end
        if occupied[(dr + 1) .. "," .. dc] then
            g.setColor(0.03 + col[1] * 0.09, 0.05 + col[2] * 0.09, 0.08 + col[3] * 0.09, 0.94 * alpha)
            g.rectangle("fill", cx + 2, cy + ch - 2, cw - 4, gap + 6)
        end

        g.setColor(0.03 + col[1] * 0.10, 0.05 + col[2] * 0.10, 0.08 + col[3] * 0.10, 0.95 * alpha)
        g.rectangle("fill", cx, cy, cw, ch, 6, 6)
    end

    -- 2. Draw full-brightness grid-sized item artwork rotated to match orientation
    local totalW = bw * cellSize + (bw - 1) * gap
    local totalH = bh * cellSize + (bh - 1) * gap
    if img then
        local pad = compact and 1 or 2
        local drawW = math.max(4, totalW - pad * 2)
        local drawH = math.max(4, totalH - pad * 2)
        local imgW, imgH = img:getDimensions()
        local targetW, targetH = drawW, drawH
        if rot % 2 == 1 then
            targetW, targetH = drawH, drawW
        end
        local centerX = originX + totalW * 0.5
        local centerY = originY + totalH * 0.5

        g.setColor(1, 1, 1, alpha)
        g.draw(img, centerX, centerY, rot * (math.pi * 0.5),
            targetW / imgW, targetH / imgH, imgW * 0.5, imgH * 0.5)
    elseif item.kind == "chip" then
        -- Fallback diamond motif when artwork isn't available (e.g. headless mode)
        local cx = originX + 2
        local cy = originY + 2
        local cw, ch = cellSize - 4, cellSize - 4
        local midX, midY = cx + cw * 0.5, cy + ch * 0.5
        local dR = math.min(cw, ch) * 0.34
        g.setColor(col[1], col[2], col[3], 0.26 * alpha)
        g.polygon("fill", midX, midY - dR, midX + dR, midY, midX, midY + dR, midX - dR, midY)
        g.setColor(col[1], col[2], col[3], 0.85 * alpha)
        g.setLineWidth(1.2)
        g.polygon("line", midX, midY - dR, midX + dR, midY, midX, midY + dR, midX - dR, midY)
    end

    -- 3. Draw per-cell grid dividers only when slot overlay is visible;
    --    keep a clean unobtrusive outer frame at rest.
    if showSlots then
        for _, coord in ipairs(shapeCells) do
            local dr, dc = coord[1], coord[2]
            local cx = originX + dc * step + 2
            local cy = originY + dr * step + 2
            local cw = cellSize - 4
            local ch = cellSize - 4

            g.setColor(col[1], col[2], col[3], (isSel and 0.58 or 0.34) * alpha)
            g.setLineWidth(1.0)
            g.rectangle("line", cx, cy, cw, ch, 6, 6)
        end
    end

    g.setColor(col[1], col[2], col[3], (isSel and 0.96 or (isHovered and 0.86 or 0.58)) * alpha)
    g.setLineWidth(isSel and 2.2 or (isHovered and 1.8 or 1.2))
    g.rectangle("line", originX + 1.5, originY + 1.5, totalW - 3, totalH - 3, 6, 6)

    -- 4. Labels / tags (shown only on hover or when artwork is missing)
    if showSlots or not img then
        if item.kind == "chip" then
            if not compact then
                local cx = originX + 2
                local cy = originY + 2
                local cw = cellSize - 4
                local ch = cellSize - 4
                g.setColor(0.02, 0.05, 0.09, 0.68 * alpha)
                g.rectangle("fill", cx + 3, cy + ch - 18, cw - 6, 15, 3, 3)
                g.setFont(fonts.small)
                g.setColor(col[1], col[2], col[3], 0.98 * alpha)
                g.printf(targetShortTag[item.def.target] or "ANY", cx + 3, cy + ch - 17, cw - 6, "center")
            end
        else
            if not compact and shapeCells[1] then
                local cx = originX + shapeCells[1][2] * step + 4
                local cy = originY + shapeCells[1][1] * step + 4
                g.setColor(0.02, 0.05, 0.09, 0.68 * alpha)
                g.rectangle("fill", cx, cy, 40, 15, 3, 3)
                g.setFont(fonts.small)
                g.setColor(0.95, 0.98, 1.0, 0.96 * alpha)
                g.printf(item.def.shortName, cx + 2, cy + 1, 36, "center")
            end
        end
    end

    -- 5. For modules, draw per-cell sockets only on hover so the artwork
    --    remains unobstructed at rest, and keep the hover overlay semi-transparent.
    if item.kind == "module" and showSlots then
        local centers = {}
        for i, coord in ipairs(shapeCells) do
            local cx = originX + coord[2] * step + cellSize * 0.5
            local cy = originY + coord[1] * step + cellSize * (compact and 0.50 or 0.56)
            centers[i] = { cx, cy }
        end

        local rSock = compact and math.max(4.0, cellSize * 0.20) or 11.5
        for i = 1, (item.maxSockets or 0) do
            local p = centers[i]
            if p then
                local chip = item.sockets[i]
                g.setColor(0.02, 0.05, 0.09, 0.56 * alpha)
                g.circle("fill", p[1], p[2], rSock + 1.2)

                if chip then
                    local cc = chip.def.color or { 1, 0.8, 0.3 }
                    local chipImg = not compact and getItemImage(chip) or nil
                    if chipImg then
                        local cW, cH = chipImg:getDimensions()
                        local side = rSock * 1.48
                        g.setColor(1, 1, 1, 0.96 * alpha)
                        g.draw(chipImg, p[1], p[2], 0, side / cW, side / cH, cW * 0.5, cH * 0.5)
                    else
                        g.setColor(cc[1], cc[2], cc[3], 0.92 * alpha)
                        g.circle("fill", p[1], p[2], rSock)
                    end
                else
                    g.setColor(0.04, 0.08, 0.13, 0.62 * alpha)
                    g.circle("fill", p[1], p[2], rSock)
                end

                g.setColor(0.45, 0.92, 1.0, 0.92 * alpha)
                g.setLineWidth(compact and 1.1 or 1.5)
                g.circle("line", p[1], p[2], rSock)

                if not compact and chip and not getItemImage(chip) then
                    g.setFont(fonts.small)
                    g.setColor(0.05, 0.08, 0.12, alpha)
                    g.printf(string.sub(chip.def.shortName, 1, 2), p[1] - 12, p[2] - 6, 24, "center")
                end
            end
        end
    end
end

function InventoryUI:draw(inv, fonts, width, height, feverActive, opts)
    opts = opts or {}
    local stageEndMode = opts.stageEndMode == true
    local returnTarget = opts.returnTarget or "playing"
    local g = love.graphics
    self.hitRegions = {}

    g.push("all")
    g.origin()
    g.setColor(0.015, 0.025, 0.050, 0.92)
    g.rectangle("fill", 0, 0, width, height)

    local panelW = math.min(1100, width - 48)
    local panelH = math.min(684, height - 44)
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
    local titleText = stageEndMode and "스테이지 장비 배치" or "함선 격자 정비소"
    g.print(titleText, px + 24, py + 14)

    g.setFont(fonts.menuBody)
    g.setColor(0.62, 0.84, 0.92, 1)
    local cellInfo = string.format("확장 슬롯 %d / %d  (4x4 > 6x6 다이아몬드)  ·  드래그 배치 · 클릭 유지+R 회전",
        inv:unlockedCellCount(), inv:maxCellCount())
    g.print(cellInfo, px + 26, py + 56)

    -- Close / Proceed button
    local closeLabel = "전투 복귀"
    local closeW = 136
    if returnTarget == "warpSelect" or returnTarget == "nextStage" or stageEndMode then
        closeLabel = inv:pendingCount() > 0 and "미배치 포기·전장 복귀" or "전장으로 복귀"
        closeW = inv:pendingCount() > 0 and 196 or 152
    end
    local closeX, closeY, closeH = px + panelW - closeW - 22, py + 18, 36
    if returnTarget == "warpSelect" or returnTarget == "nextStage" or stageEndMode then
        g.setColor(inv:pendingCount() > 0 and 0.28 or 0.14, inv:pendingCount() > 0 and 0.18 or 0.30, 0.16, 0.96)
        g.rectangle("fill", closeX, closeY, closeW, closeH, 6, 6)
        g.setColor(inv:pendingCount() > 0 and 1.0 or 0.46, inv:pendingCount() > 0 and 0.72 or 0.94, inv:pendingCount() > 0 and 0.36 or 0.68, 0.92)
    else
        g.setColor(0.14, 0.24, 0.32, 0.95)
        g.rectangle("fill", closeX, closeY, closeW, closeH, 6, 6)
        g.setColor(0.45, 0.86, 0.95, 0.8)
    end
    g.rectangle("line", closeX, closeY, closeW, closeH, 6, 6)
    g.setFont(fonts.menuBody)
    g.setColor(0.95, 0.98, 1, 1)
    g.printf(closeLabel, closeX, closeY + 9, closeW, "center")
    self:addRegion(closeX, closeY, closeW, closeH, { type = "close" })

    -- Left: 6x6 Diamond Grid
    local gap = 5
    local maxGridH = panelH - 156
    local cellSize = math.min(72, math.floor((maxGridH - (inv.gridSize - 1) * gap) / inv.gridSize))
    local step = cellSize + gap
    local gridSpan = inv.gridSize * cellSize + (inv.gridSize - 1) * gap
    local gx = px + 28
    local gy = py + 94
    self.gridRect = {
        x = gx, y = gy, span = gridSpan,
        cellSize = cellSize, gap = gap, gridSize = inv.gridSize,
    }

    for r = 1, inv.gridSize do
        for c = 1, inv.gridSize do
            local cx = gx + (c - 1) * step
            local cy = gy + (r - 1) * step
            if Inventory.isInDiamond(r, c, Inventory.MAX_RADIUS) then
                local isCore4x4 = Inventory.isInDiamond(r, c, Inventory.START_RADIUS)
                if inv:isUnlocked(r, c) then
                    g.setColor(isCore4x4 and 0.065 or 0.052, isCore4x4 and 0.135 or 0.115, isCore4x4 and 0.205 or 0.175, 0.96)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    g.setColor(isCore4x4 and 0.36 or 0.28, isCore4x4 and 0.78 or 0.66, isCore4x4 and 0.92 or 0.80, 0.55)
                    g.setLineWidth(1.2)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                elseif inv:canUnlockCell(r, c) then
                    g.setColor(0.12, 0.14, 0.08, 0.68)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    g.setColor(0.96, 0.76, 0.34, 0.78)
                    g.setLineWidth(1.2)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                    g.setFont(fonts.small)
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

    -- Faint ghost at original cell(s) when dragging from grid
    if self.dragging and self.dragging.origin == "grid" and self.dragging.origRow then
        local origCells = Inventory.getShapeCells(self.dragging.item, self.dragging.origRotation)
        for _, coord in ipairs(origCells) do
            local cx = gx + (self.dragging.origCol + coord[2] - 1) * step + 3
            local cy = gy + (self.dragging.origRow + coord[1] - 1) * step + 3
            g.setColor(0.65, 0.88, 1.0, 0.14)
            g.rectangle("fill", cx, cy, cellSize - 6, cellSize - 6, 5, 5)
            g.setColor(0.65, 0.88, 1.0, 0.38)
            g.setLineWidth(1.2)
            g.rectangle("line", cx, cy, cellSize - 6, cellSize - 6, 5, 5)
        end
    end

    -- Draw placed modules on the diamond grid
    for _, mod in ipairs(inv.placed) do
        local ox = gx + (mod.col - 1) * step
        local oy = gy + (mod.row - 1) * step
        local isHovered = isPointOverShape(mod, ox, oy, cellSize, gap, self.mouseX, self.mouseY)
        local showSlots = isHovered and not (self.dragging and self.dragging.kind == "module")
        drawItemGridShape(inv, mod, ox, oy, cellSize, gap, fonts, {
            selected = (self.selectedItem == mod),
            hovered = isHovered,
            showSlots = showSlots,
        })

        local shapeCells = Inventory.getShapeCells(mod, mod.rotation)
        -- Register per-cell module pickup regions
        for _, coord in ipairs(shapeCells) do
            local cx = ox + coord[2] * step
            local cy = oy + coord[1] * step
            self:addRegion(cx, cy, cellSize, cellSize, { type = "placedModule", mod = mod, item = mod })
        end
        -- Register equipped chip socket regions ON TOP of module cells so clicking
        -- directly on an equipped chip picks up that chip!
        for i, coord in ipairs(shapeCells) do
            if i <= (mod.maxSockets or 0) and mod.sockets[i] then
                local sx = ox + coord[2] * step + cellSize * 0.5
                local sy = oy + coord[1] * step + cellSize * 0.56
                local rSock = 14
                self:addRegion(sx - rSock, sy - rSock, rSock * 2, rSock * 2, {
                    type = "equippedChip",
                    mod = mod,
                    socketIndex = i,
                    chip = mod.sockets[i],
                    item = mod.sockets[i],
                })
            end
        end
    end

    -- Draw placed support chips stored directly on diamond grid cells
    for _, chip in ipairs(inv.placedChips) do
        local ox = gx + (chip.col - 1) * step
        local oy = gy + (chip.row - 1) * step
        local isHovered = not self.dragging and isPointOverShape(chip, ox, oy, cellSize, gap, self.mouseX, self.mouseY)
        drawItemGridShape(inv, chip, ox, oy, cellSize, gap, fonts, {
            selected = (self.selectedItem == chip),
            hovered = isHovered,
            showSlots = isHovered,
        })
        local shapeCells = Inventory.getShapeCells(chip, chip.rotation)
        for _, coord in ipairs(shapeCells) do
            local cx = ox + coord[2] * step
            local cy = oy + coord[1] * step
            self:addRegion(cx, cy, cellSize, cellSize, { type = "placedChip", chip = chip, item = chip })
        end
    end

    -- Draw drop-preview highlight on the grid when dragging
    if self.dragging then
        local d = self.dragging
        local handledSocketPreview = false
        if d.kind == "chip" then
            local dr, dc = self:pixelToDirectCell(self.mouseX, self.mouseY)
            if dr and dc then
                local occ = inv.cells[dr][dc]
                if occ and occ.kind == "module" then
                    local sIdx = inv:getSocketAtGridCell(occ, dr, dc)
                    if sIdx then
                        handledSocketPreview = true
                        local compatible = ChipsData.isCompatible(d.item.def, occ.def)
                        local sx = gx + (dc - 1) * step + cellSize * 0.5
                        local sy = gy + (dr - 1) * step + cellSize * 0.56
                        if compatible then
                            g.setColor(0.36, 1.0, 0.68, 0.34)
                            g.circle("fill", sx, sy, 22)
                            g.setColor(0.45, 1.0, 0.72, 0.98)
                            g.setLineWidth(2.6)
                            g.circle("line", sx, sy, 22)
                        else
                            g.setColor(1.0, 0.32, 0.36, 0.32)
                            g.circle("fill", sx, sy, 22)
                            g.setColor(1.0, 0.38, 0.42, 0.98)
                            g.setLineWidth(2.6)
                            g.circle("line", sx, sy, 22)
                        end
                    end
                end
            end
        end

        if not handledSocketPreview then
            local snapR, snapC = self:computeSnappedOrigin(d.item, d.rotation, self.mouseX, self.mouseY)
            if snapR and snapC then
                local valid = inv:canPlace(d.item, snapR, snapC, d.rotation)
                local shapeCells = Inventory.getShapeCells(d.item, d.rotation)
                for _, coord in ipairs(shapeCells) do
                    local tr, tc = snapR + coord[1], snapC + coord[2]
                    if tr >= 1 and tr <= inv.gridSize and tc >= 1 and tc <= inv.gridSize then
                        local cx = gx + (tc - 1) * step
                        local cy = gy + (tr - 1) * step
                        if valid then
                            g.setColor(0.32, 0.96, 0.68, 0.30)
                            g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                            g.setColor(0.42, 1.0, 0.74, 0.95)
                            g.setLineWidth(2.2)
                            g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                        else
                            g.setColor(1.0, 0.28, 0.32, 0.30)
                            g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                            g.setColor(1.0, 0.38, 0.42, 0.95)
                            g.setLineWidth(2.2)
                            g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                        end
                    end
                end
            end
        end
    end

    -- Right Panel: Inspector + (Stage Reward Tray OR Build Summary) + Discard Zone
    local rx = gx + gridSpan + 24
    local rw = px + panelW - rx - 22
    local curY = py + 94

    -- 1. Inspector box
    local inspectItem = (self.dragging and self.dragging.item) or self.hoveredItem or self.selectedItem
    local inspectH = 132
    g.setColor(0.05, 0.09, 0.14, 0.96)
    g.rectangle("fill", rx, curY, rw, inspectH, 8, 8)
    g.setColor(0.28, 0.56, 0.68, 0.55)
    g.setLineWidth(1.2)
    g.rectangle("line", rx, curY, rw, inspectH, 8, 8)

    g.setFont(fonts.menuBody)
    if inspectItem then
        local rot = (self.dragging and self.dragging.item == inspectItem) and self.dragging.rotation or inspectItem.rotation
        local _, iw, ih = Inventory.getShapeCells(inspectItem, rot)
        local textX = rx + 12
        local textW = rw - 24
        local thumbImg = getItemImage(inspectItem)
        if thumbImg then
            local boxSize = 72
            local bx, by = rx + 12, curY + 10
            local ic = inspectItem.def.color or { 0.4, 0.8, 0.9 }
            g.setColor(0.03, 0.06, 0.10, 0.96)
            g.rectangle("fill", bx, by, boxSize, boxSize, 6, 6)
            g.setColor(ic[1], ic[2], ic[3], 0.65)
            g.setLineWidth(1.2)
            g.rectangle("line", bx, by, boxSize, boxSize, 6, 6)
            local imgW, imgH = thumbImg:getDimensions()
            local scale = math.min((boxSize - 8) / imgW, (boxSize - 8) / imgH)
            g.setColor(1, 1, 1, 0.98)
            g.draw(thumbImg, bx + boxSize * 0.5, by + boxSize * 0.5, 0, scale, scale, imgW * 0.5, imgH * 0.5)
            textX = bx + boxSize + 12
            textW = rx + rw - textX - 12
        end
        g.setColor(0.95, 0.98, 1.0, 1)
        if inspectItem.kind == "module" then
            g.print(string.format("%s (%dx%d) · 소켓 %d/%d",
                inspectItem.def.name, iw, ih, inv:equippedSocketCount(inspectItem), inspectItem.maxSockets),
                textX, curY + 10)
        else
            local targetTxt = targetKoreanLabel[inspectItem.def.target] or inspectItem.def.target
            g.print(string.format("%s (1x1 칩) · 대상: %s",
                inspectItem.def.name, targetTxt), textX, curY + 10)
        end
        g.setColor(0.70, 0.84, 0.90, 0.95)
        g.printf(inspectItem.def.description, textX, curY + 36, textW, "left")

        if self.selectedModule and self.selectedModule.row and not self.dragging then
            local btnY = curY + 92
            local btns = {
                { label = "회전 (R)", action = { type = "rotateSelected" } },
            }
            local bw = math.floor((rw - 24 - (#btns - 1) * 8) / #btns)
            for i, b in ipairs(btns) do
                local bx = rx + 12 + (i - 1) * (bw + 8)
                g.setColor(0.12, 0.22, 0.30, 0.95)
                g.rectangle("fill", bx, btnY, bw, 30, 5, 5)
                g.setColor(0.42, 0.80, 0.92, 0.78)
                g.rectangle("line", bx, btnY, bw, 30, 5, 5)
                g.setFont(fonts.menuBody)
                g.setColor(0.92, 0.97, 1, 1)
                g.printf(b.label, bx, btnY + 6, bw, "center")
                self:addRegion(bx, btnY, bw, 30, b.action)
            end
        end
    else
        g.setColor(0.62, 0.74, 0.82, 0.95)
        g.printf("모듈이나 서포트 칩을 클릭·드래그해 다이아몬드 격자에 배치하세요.", rx + 12, curY + 46, rw - 24, "center")
    end

    curY = curY + inspectH + 14

    -- Reserve bottom area for Discard Drop Zone + footer
    local discardH = 54
    local discardY = py + panelH - 46 - discardH
    local middleH = discardY - curY - 12

    -- 2. Middle Box: Stage Reward Tray (stage-end only) OR Build Summary (during combat)
    if stageEndMode then
        self.pendingTrayRect = { x = rx, y = curY, w = rw, h = middleH }
        local overTray = self.dragging and pointInRect(self.mouseX, self.mouseY, rx, curY, rw, middleH)

        g.setColor(overTray and 0.14 or 0.05, overTray and 0.13 or 0.08, overTray and 0.06 or 0.12, 0.96)
        g.rectangle("fill", rx, curY, rw, middleH, 8, 8)
        g.setColor(1.0, 0.78, 0.34, overTray and 0.95 or 0.58)
        g.setLineWidth(overTray and 2.2 or 1.3)
        g.rectangle("line", rx, curY, rw, middleH, 8, 8)

        g.setFont(fonts.menuBody)
        g.setColor(1.0, 0.86, 0.44, 1)
        g.print("스테이지 획득 장비 (" .. #inv.pendingRewards .. ")", rx + 12, curY + 10)
        g.setColor(0.96, 0.62, 0.44, 0.95)
        g.printf("미배치 시 다음 스테이지에서 소멸", rx + 12, curY + 10, rw - 24, "right")

        local trayInnerY = curY + 38
        if #inv.pendingRewards == 0 then
            g.setColor(0.56, 0.86, 0.72, 0.92)
            g.printf("획득한 장비를 모두 인벤토리에 배치했습니다!", rx + 16, curY + middleH * 0.46, rw - 32, "center")
        else
            -- Render every pending item in its actual visual grid shape!
            local miniCell = 26
            local miniGap = 3
            local padX, padY = 12, 8
            local cursorX = rx + padX
            local cursorY = trayInnerY
            local rowMaxH = 0

            for _, item in ipairs(inv.pendingRewards) do
                local _, iw, ih = Inventory.getShapeCells(item, item.rotation)
                local shapeW = iw * miniCell + (iw - 1) * miniGap
                local shapeH = ih * miniCell + (ih - 1) * miniGap
                local cardW = math.max(96, shapeW + 24)
                local cardH = math.max(76, shapeH + 34)

                if cursorX + cardW > rx + rw - padX then
                    cursorX = rx + padX
                    cursorY = cursorY + rowMaxH + padY
                    rowMaxH = 0
                end

                if cursorY + cardH <= curY + middleH - 6 then
                    local ic = item.def.color or { 0.45, 0.85, 0.95 }
                    local isSel = (self.selectedItem == item)
                    g.setColor(0.035, 0.060, 0.098, 0.96)
                    g.rectangle("fill", cursorX, cursorY, cardW, cardH, 6, 6)
                    g.setColor(ic[1], ic[2], ic[3], isSel and 0.95 or 0.45)
                    g.setLineWidth(isSel and 2.0 or 1.1)
                    g.rectangle("line", cursorX, cursorY, cardW, cardH, 6, 6)

                    local drawX = cursorX + math.floor((cardW - shapeW) * 0.5)
                    local drawY = cursorY + 8
                    local cardHovered = not self.dragging and pointInRect(self.mouseX, self.mouseY, cursorX, cursorY, cardW, cardH)
                    drawItemGridShape(inv, item, drawX, drawY, miniCell, miniGap, fonts, {
                        selected = isSel,
                        hovered = cardHovered,
                        showSlots = cardHovered,
                    })

                    g.setFont(fonts.small)
                    g.setColor(0.92, 0.96, 1.0, 0.95)
                    local tag = item.kind == "chip"
                        and (item.def.shortName .. " [" .. (targetShortTag[item.def.target] or "ANY") .. "]")
                        or string.format("%s (%dx%d)", item.def.shortName, iw, ih)
                    g.printf(tag, cursorX + 4, cursorY + cardH - 18, cardW - 8, "center")

                    self:addRegion(cursorX, cursorY, cardW, cardH, { type = "pendingItem", item = item })
                    cursorX = cursorX + cardW + 8
                    if cardH > rowMaxH then rowMaxH = cardH end
                end
            end
        end
    else
        self.pendingTrayRect = nil
        g.setColor(0.042, 0.075, 0.115, 0.95)
        g.rectangle("fill", rx, curY, rw, middleH, 8, 8)
        g.setColor(0.28, 0.56, 0.70, 0.48)
        g.setLineWidth(1.2)
        g.rectangle("line", rx, curY, rw, middleH, 8, 8)

        local build = inv:computeBuild(feverActive)
        g.setFont(fonts.menuBody)
        g.setColor(0.75, 0.92, 0.98, 1)
        g.print("장착 스펙 요약 (별도 보관함 없음)", rx + 14, curY + 12)

        local lines = {
            string.format("· 배치 모듈: %d개   · 격자 보관 칩: %d개", #inv.placed, #inv.placedChips),
            string.format("· 실드 보너스: +%d   · 장갑 보너스: +%d", build.maxShieldBonus, build.maxArmorBonus),
            string.format("· 배터리 보너스: +%d   · 점수 배율: x%.2f", build.maxBatteryBonus, build.scoreMultiplier),
            string.format("· 속도 보너스: +%d   · 부스트 보너스: +%d", build.maxSpeedBonus, build.boostSpeedBonus),
        }
        g.setColor(0.84, 0.92, 0.96, 0.95)
        for i, line in ipairs(lines) do
            g.print(line, rx + 14, curY + 42 + (i - 1) * 26)
        end

        g.setColor(0.62, 0.80, 0.88, 0.90)
        local helpY = curY + 158
        if helpY + 70 < curY + middleH then
            g.print("조작 안내", rx + 14, helpY)
            g.print("· 좌클릭 드래그: 모듈·칩 이동 및 소켓 장착", rx + 14, helpY + 24)
            g.print("· 클릭 유지 + R: 아이템 90도 회전", rx + 14, helpY + 46)
            g.print("· 우클릭: 이동 취소  /  +OPEN: 격자 확장", rx + 14, helpY + 68)
        end
    end

    -- 3. Discard Drop Zone
    self.discardRect = { x = rx, y = discardY, w = rw, h = discardH }
    local overDiscard = self.dragging and pointInRect(self.mouseX, self.mouseY, rx, discardY, rw, discardH)
    g.setColor(overDiscard and 0.34 or 0.12, overDiscard and 0.08 or 0.05, overDiscard and 0.10 or 0.07, 0.95)
    g.rectangle("fill", rx, discardY, rw, discardH, 8, 8)
    g.setColor(1.0, 0.36, 0.42, overDiscard and 0.98 or 0.50)
    g.setLineWidth(overDiscard and 2.2 or 1.2)
    g.rectangle("line", rx, discardY, rw, discardH, 8, 8)
    g.setFont(fonts.menuBody)
    g.setColor(overDiscard and 1.0 or 0.88, overDiscard and 0.88 or 0.62, overDiscard and 0.88 or 0.66, 0.96)
    local discardLabel = overDiscard and "마우스를 놓아 이 장비를 폐기합니다" or "장비 폐기 구역 (여기에 드롭해 버리기)"
    g.printf(discardLabel, rx + 10, discardY + 17, rw - 20, "center")

    -- Footer status bar
    local build = inv:computeBuild(feverActive)
    g.setFont(fonts.menuBody)
    g.setColor(0.84, 0.93, 0.98, 1)
    g.print(self.message, px + 26, py + panelH - 34)
    g.setFont(fonts.small)
    g.setColor(0.60, 0.82, 0.90, 0.9)
    local summary = string.format("SHIELD +%d  ARMOR +%d  BATT +%d  SCORE x%.1f",
        build.maxShieldBonus, build.maxArmorBonus, build.maxBatteryBonus, build.scoreMultiplier)
    g.printf(summary, px + panelW - 360, py + panelH - 30, 336, "right")

    -- 4. Floating Dragged Item (drawn on top of everything, at full grid scale!)
    if self.dragging then
        local d = self.dragging
        local _, dw, dh = Inventory.getShapeCells(d.item, d.rotation)
        local itemW = dw * cellSize + (dw - 1) * gap
        local itemH = dh * cellSize + (dh - 1) * gap
        local drawX = self.mouseX - itemW * 0.5
        local drawY = self.mouseY - itemH * 0.5
        drawItemGridShape(inv, d.item, drawX, drawY, cellSize, gap, fonts, {
            rotation = d.rotation,
            selected = true,
            alpha = 0.92,
        })
        g.setFont(fonts.small)
        local tipW = 86
        local tipX = self.mouseX - tipW * 0.5
        local tipY = drawY + itemH + 6
        g.setColor(0.04, 0.08, 0.14, 0.92)
        g.rectangle("fill", tipX, tipY, tipW, 18, 4, 4)
        g.setColor(0.50, 0.92, 1.0, 0.85)
        g.setLineWidth(1)
        g.rectangle("line", tipX, tipY, tipW, 18, 4, 4)
        g.setColor(0.92, 0.98, 1.0, 1)
        g.printf("R: ROTATE", tipX, tipY + 3, tipW, "center")
    end

    g.pop()
end

function InventoryUI:finishDrop(inv, x, y, opts)
    opts = opts or {}
    local stageEndMode = opts.stageEndMode == true
    local d = self.dragging
    if not d then return nil end

    local item = d.item
    self.dragging = nil

    -- 1. Check Discard Drop Zone
    if self.discardRect and pointInRect(x, y, self.discardRect.x, self.discardRect.y, self.discardRect.w, self.discardRect.h) then
        -- If discarding a module during stage-end that has chips socketed, return chips to temporary tray
        if item.kind == "module" and stageEndMode then
            for i = 1, (item.maxSockets or 0) do
                if item.sockets[i] then
                    inv:addPendingItem(item.sockets[i])
                    item.sockets[i] = nil
                end
            end
        end
        if self.selectedItem == item then self.selectedItem = nil end
        if self.selectedModule == item then self.selectedModule = nil end
        Sfx.play("ui_click")
        self.message = item.def.name .. "을(를) 폐기했습니다."
        return "changed"
    end

    -- 2. Check Temporary Stage Reward Tray (stage-end mode only)
    if stageEndMode and self.pendingTrayRect and pointInRect(x, y,
            self.pendingTrayRect.x, self.pendingTrayRect.y,
            self.pendingTrayRect.w, self.pendingTrayRect.h) then
        local rot = Inventory.normalizeRotation(d.rotation)
        local _, w, h = Inventory.getShapeCells(item, rot)
        item.rotation = rot
        item.rotated = (rot % 2 == 1)
        item.w, item.h = w, h
        inv:addPendingItem(item)
        Sfx.play("ui_click")
        self.message = item.def.name .. "을(를) 임시 트레이에 두었습니다. (출격 시 미배치 장비 소멸)"
        return "changed"
    end

    -- 3. If dragging a Support Chip, first check drop onto a placed module's socket cell
    if d.kind == "chip" then
        local dr, dc = self:pixelToDirectCell(x, y)
        if dr and dc then
            local occ = inv.cells[dr][dc]
            if occ and occ.kind == "module" then
                local sIdx = inv:getSocketAtGridCell(occ, dr, dc)
                if sIdx then
                    local ok, prevOrReason = inv:equipChip(occ, sIdx, item)
                    if ok then
                        local prevChip = prevOrReason
                        if prevChip then
                            -- Place displaced chip cleanly without any hidden stash
                            if d.origin == "grid" and inv:canPlace(prevChip, d.origRow, d.origCol, 0) then
                                inv:placeItem(prevChip, d.origRow, d.origCol, 0)
                            elseif d.origin == "socket" and ChipsData.isCompatible(prevChip.def, d.origMod.def) then
                                inv:equipChip(d.origMod, d.origSocketIndex, prevChip)
                            elseif stageEndMode then
                                inv:addPendingItem(prevChip)
                            else
                                -- Hold displaced chip on cursor so player can place it in a free cell or discard it
                                self.dragging = {
                                    item = prevChip,
                                    kind = "chip",
                                    origin = "tray",
                                    origRow = nil,
                                    origCol = nil,
                                    origRotation = 0,
                                    startX = x,
                                    startY = y,
                                    moved = true,
                                    rotated = false,
                                    sticky = true,
                                    rotation = 0,
                                }
                            end
                        end
                        self.selectedItem = occ
                        self.selectedModule = occ
                        Sfx.play("ui_equip")
                        self.message = item.def.name .. " 장착 완료! (" .. occ.def.name .. " 소켓 #" .. sIdx .. ")"
                        return "changed"
                    else
                        -- Incompatible module: restore chip to origin
                        self.dragging = d
                        self:cancelDrag(inv)
                        Sfx.play("ui_error")
                        self.message = "장착 불가: 대상 카테고리가 일치하지 않습니다."
                        return nil
                    end
                end
            end
        end
    end

    -- 4. Check snapped grid placement (works for both modules and 1x1 support chips!)
    local snapR, snapC = self:computeSnappedOrigin(item, d.rotation, x, y)
    if snapR and snapC then
        local ok, reason = inv:placeItem(item, snapR, snapC, d.rotation)
        if ok then
            self.selectedItem = item
            if item.kind == "module" then
                self.selectedModule = item
            end
            Sfx.play("ui_equip")
            if item.kind == "chip" then
                self.message = item.def.name .. " 칩을 격자 칸에 보관했습니다."
            else
                self.message = item.def.name .. " 배치 완료!"
            end
            return "changed"
        else
            self.dragging = d
            self:cancelDrag(inv)
            Sfx.play("ui_error")
            self.message = "배치 불가: 공간이 부족하거나 잠긴 칸입니다 (" .. tostring(reason) .. ")"
            return nil
        end
    end

    -- 5. Dropped outside any valid zone -> restore to origin safely
    self.dragging = d
    self:cancelDrag(inv)
    Sfx.play("ui_error")
    self.message = "유효한 격자 위치에 놓아주세요. (폐기하려면 우측 하단 폐기 구역에 드롭)"
    return nil
end

function InventoryUI:mousepressed(inv, x, y, button, opts)
    self.mouseX, self.mouseY = x, y

    -- Right-click cancels active drag
    if button == 2 then
        if self:cancelDrag(inv) then
            Sfx.play("ui_click")
            self.message = "이동을 취소했습니다."
        end
        return nil
    end
    if button ~= 1 then return nil end

    -- If already holding an item (sticky click-and-drop mode), drop it now!
    if self.dragging then
        return self:finishDrop(inv, x, y, opts)
    end

    -- Iterate in reverse so top-most elements win
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
            elseif a.type == "equippedChip" then
                self:startDrag(inv, a.chip, "socket", x, y, { mod = a.mod, socketIndex = a.socketIndex })
                self.message = a.chip.def.name .. " 드래그 중 — 다른 소켓이나 빈 격자에 놓으세요."
                return nil
            elseif a.type == "placedModule" then
                self:startDrag(inv, a.mod, "grid", x, y)
                self.message = a.mod.def.name .. " 드래그 중 — 원하는 위치에 놓으세요. (R: 회전)"
                return nil
            elseif a.type == "placedChip" then
                self:startDrag(inv, a.chip, "grid", x, y)
                self.message = a.chip.def.name .. " 드래그 중 — 모듈 소켓 또는 빈 칸에 놓으세요."
                return nil
            elseif a.type == "pendingItem" then
                self:startDrag(inv, a.item, "tray", x, y)
                self.message = a.item.def.name .. " 획득 배치 중 — 격자에 놓으세요. (R: 회전)"
                return nil
            elseif a.type == "rotateSelected" and self.selectedModule then
                if inv:rotateModule(self.selectedModule) then
                    Sfx.play("ui_equip")
                    self.message = self.selectedModule.def.name .. " 회전 완료"
                    return "changed"
                else
                    Sfx.play("ui_error")
                    self.message = "현재 위치에서는 회전할 공간이 부족합니다. 드래그하며 R을 눌러보세요."
                end
                return nil
            end
        end
    end
    return nil
end

function InventoryUI:mousereleased(inv, x, y, button, opts)
    self.mouseX, self.mouseY = x, y
    if button ~= 1 or not self.dragging then return nil end
    local d = self.dragging

    if d.moved or d.rotated then
        return self:finishDrop(inv, x, y, opts)
    end

    -- Quick click without dragging:
    -- For tray items, enter sticky pickup mode so click -> move -> R -> click works too!
    if d.origin == "tray" then
        d.sticky = true
        self.message = d.item.def.name .. " 집어듦 — 격자 위치를 클릭해 배치하세요. (R: 회전, 우클릭: 취소)"
        return nil
    end

    -- Quick tap on an already placed item: restore cleanly and keep it selected in inspector
    self:cancelDrag(inv)
    self.message = d.item.def.name .. " 선택됨 (드래그해 이동하거나 R로 회전)"
    return nil
end

function InventoryUI:keypressed(inv, key)
    if key == "r" then
        if self.dragging then
            self.dragging.rotation = (self.dragging.rotation + 1) % 4
            self.dragging.rotated = true
            Sfx.play("ui_hover")
            self.message = string.format("%s 회전 (%d도)", self.dragging.item.def.name, self.dragging.rotation * 90)
            return nil
        elseif self.selectedModule and self.selectedModule.row then
            if inv:rotateModule(self.selectedModule) then
                Sfx.play("ui_equip")
                self.message = self.selectedModule.def.name .. " 회전 완료"
                return "changed"
            else
                Sfx.play("ui_error")
                self.message = "현재 위치에서는 회전할 공간이 부족합니다. 클릭·드래그 상태에서 R을 눌러 회전하세요."
            end
        end
    end
    return nil
end

function InventoryUI:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    if self.dragging then
        local dx = x - self.dragging.startX
        local dy = y - self.dragging.startY
        if dx * dx + dy * dy > 36 then
            self.dragging.moved = true
        end
        return
    end

    local found, foundItem = nil, nil
    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            found = i
            foundItem = r.action and r.action.item or nil
            break
        end
    end
    if found and found ~= self.hoveredIndex then
        Sfx.play("ui_hover")
    end
    self.hoveredIndex = found
    self.hoveredItem = foundItem
end

return InventoryUI
