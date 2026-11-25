-- Armored Core-inspired Armory screen for assembling the player's ship.
-- Left: categorized module catalog (weapon, defense, thruster, generator).
-- Right-top: hover/drag module inspector (or assembled ship spec when idle).
-- Right-bottom: chassis selector (Striker MK-I + ??? placeholder), ship silhouette
-- with 5x3 triangle grid overlay, mandatory part checks, and battery warnings.

local Display = require("src.core.display")
local ChassisData = require("src.data.chassis_data")
local ModulesData = require("src.data.modules_data")
local Rarity = require("src.data.rarity")
local Inventory = require("src.progression.inventory")
local Ship = require("src.combat.ship")
local Theme = require("src.ui.theme")
local Sfx = require("src.audio.sfx")

local ArmoryUI = {}
ArmoryUI.__index = ArmoryUI

local imageCache = {}

local function getDefImage(def)
    if not (love and love.graphics and def and def.image) then
        return nil
    end
    local path = def.image
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

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function drawArrowTriangle(x, y, size, dir)
    local g = love.graphics
    if dir < 0 then
        g.polygon("fill", x - size * 0.65, y, x + size * 0.45, y - size * 0.72, x + size * 0.45, y + size * 0.72)
    else
        g.polygon("fill", x + size * 0.65, y, x - size * 0.45, y - size * 0.72, x - size * 0.45, y + size * 0.72)
    end
end

local function drawCheckIcon(cx, cy, r, ok)
    local g = love.graphics
    g.setLineWidth(2.0)
    if ok then
        g.line(cx - r * 0.55, cy + r * 0.05, cx - r * 0.12, cy + r * 0.48, cx + r * 0.60, cy - r * 0.45)
    else
        g.line(cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45)
        g.line(cx + r * 0.45, cy - r * 0.45, cx - r * 0.45, cy + r * 0.45)
    end
end

local function drawWarningTriangle(cx, cy, r)
    local g = love.graphics
    g.polygon("fill", cx, cy - r, cx + r * 0.95, cy + r * 0.75, cx - r * 0.95, cy + r * 0.75)
end

local function isPointOverShape(item, originX, originY, cellSize, gap, mx, my, rotation)
    local step = cellSize + gap
    local rot = Inventory.normalizeRotation(rotation ~= nil and rotation or item.rotation)
    local shapeCells = Inventory.getShapeCells(item, rot)
    local occupied = {}
    for _, coord in ipairs(shapeCells) do
        occupied[coord[1] .. "," .. coord[2]] = true
    end
    for _, coord in ipairs(shapeCells) do
        local dr, dc = coord[1], coord[2]
        local cx = originX + dc * step
        local cy = originY + dr * step
        if pointInRect(mx, my, cx, cy, cellSize, cellSize) then
            return true
        end
        if occupied[dr .. "," .. (dc + 1)] and pointInRect(mx, my, cx + cellSize, cy, gap, cellSize) then
            return true
        end
        if occupied[(dr + 1) .. "," .. dc] and pointInRect(mx, my, cx, cy + cellSize, cellSize, gap) then
            return true
        end
    end
    return false
end

local function formatNum(val)
    local n = tonumber(val) or 0
    if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
        return tostring(math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

local function formatModuleStatLines(def)
    if not def then return {} end
    local lines = {}
    local cat = def.category
    if cat == "weapon" then
        lines[#lines + 1] = string.format("발사 배터리 %d  ·  발사 간격 %.2f초",
            def.baseBatteryCost or 0, def.fireInterval or 0)
        lines[#lines + 1] = string.format("점유 크기 %dx%d  ·  서포트 칩 소켓 %d개",
            def.w or 1, def.h or 1, def.maxSockets or 0)
    elseif cat == "defense" then
        local s = def.stats or {}
        if (s.maxShield or 0) > 0 then
            lines[#lines + 1] = string.format("실드 +%d  ·  회복 +%s/s (지연 %s초)  ·  배터리 %s/s",
                s.maxShield, formatNum(s.shieldRegen or 0), formatNum(s.shieldRegenDelay or 2), formatNum(s.shieldRegenBatteryCost or 0))
            lines[#lines + 1] = string.format("점유 크기 %dx%d  ·  서포트 칩 소켓 %d개  ·  중복 합산",
                def.w or 1, def.h or 1, def.maxSockets or 0)
        else
            local parts = {}
            if (s.maxArmor or 0) > 0 then parts[#parts + 1] = string.format("아머 +%d", s.maxArmor) end
            if #parts == 0 then parts[1] = "방호 모듈" end
            lines[#lines + 1] = table.concat(parts, "  ·  ") .. "  ·  중복 장착 시 합산"
            lines[#lines + 1] = string.format("점유 크기 %dx%d  ·  서포트 칩 소켓 %d개",
                def.w or 1, def.h or 1, def.maxSockets or 0)
        end
    elseif cat == "thruster" then
        local s = def.stats or {}
        lines[#lines + 1] = string.format("가속 소모 %d/s  ·  부스트 소모 %d  ·  최고속도 +%d",
            s.thrustBatteryCost or 0, s.boostCost or 0, s.maxSpeed or 0)
        lines[#lines + 1] = string.format("추진력 +%d  ·  부스트속도 +%d  ·  중복 장착 시 합산",
            s.thrust or 0, s.boostSpeed or 0)
    elseif cat == "generator" or cat == "battery" then
        local s = def.stats or {}
        lines[#lines + 1] = string.format("배터리 총량 +%d  ·  초당 충전 +%d/s  ·  중복 합산",
            s.maxBattery or 0, s.batteryRecharge or 0)
        lines[#lines + 1] = string.format("점유 크기 %dx%d  ·  서포트 칩 소켓 %d개",
            def.w or 1, def.h or 1, def.maxSockets or 0)
    end
    return lines
end

local function formatBriefCatalogStats(def)
    if not def then return "" end
    local s = def.stats or {}
    if def.category == "weapon" then
        return string.format("발사 %d · %.2fs · 소켓 %d",
            def.baseBatteryCost or 0, def.fireInterval or 0, def.maxSockets or 0)
    elseif def.category == "defense" then
        if (s.maxShield or 0) > 0 then
            return string.format("실드 +%d · 회복 %s/s · 배터리 %s/s",
                s.maxShield, formatNum(s.shieldRegen or 0), formatNum(s.shieldRegenBatteryCost or 0))
        end
        return string.format("아머 +%d · 소켓 %d", s.maxArmor or 0, def.maxSockets or 0)
    elseif def.category == "thruster" then
        return string.format("속도 +%d · 가속 %d/s · 부스트 %d",
            s.maxSpeed or 0, s.thrustBatteryCost or 0, s.boostCost or 0)
    elseif def.category == "generator" or def.category == "battery" then
        return string.format("총량 +%d · 충전 +%d/s",
            s.maxBattery or 0, s.batteryRecharge or 0)
    end
    return ""
end

local function drawGridModule(mod, originX, originY, cellSize, gap, opts)
    opts = opts or {}
    local g = love.graphics
    local step = cellSize + gap
    local rot = Inventory.normalizeRotation(opts.rotation ~= nil and opts.rotation or mod.rotation)
    local shapeCells, bw, bh = Inventory.getShapeCells(mod, rot)
    local def = mod.def or mod
    local col = Rarity.getColor(mod.rarity or def.rarity)
    local alpha = opts.alpha or 1.0
    local isHovered = opts.hovered == true
    local isDragging = opts.dragging == true
    local img = getDefImage(def)

    local occupied = {}
    for _, coord in ipairs(shapeCells) do
        occupied[coord[1] .. "," .. coord[2]] = true
    end

    for _, coord in ipairs(shapeCells) do
        local dr, dc = coord[1], coord[2]
        local cx = originX + dc * step + 1
        local cy = originY + dr * step + 1
        local cw = cellSize - 2
        local ch = cellSize - 2

        if occupied[dr .. "," .. (dc + 1)] then
            g.setColor(0.03 + col[1] * 0.12, 0.05 + col[2] * 0.12, 0.08 + col[3] * 0.12, 0.88 * alpha)
            g.rectangle("fill", cx + cw - 2, cy + 2, gap + 6, ch - 4)
        end
        if occupied[(dr + 1) .. "," .. dc] then
            g.setColor(0.03 + col[1] * 0.12, 0.05 + col[2] * 0.12, 0.08 + col[3] * 0.12, 0.88 * alpha)
            g.rectangle("fill", cx + 2, cy + ch - 2, cw - 4, gap + 6)
        end

        g.setColor(0.03 + col[1] * 0.14, 0.05 + col[2] * 0.14, 0.08 + col[3] * 0.14, 0.90 * alpha)
        g.rectangle("fill", cx, cy, cw, ch, 6, 6)
    end

    local totalW = bw * cellSize + (bw - 1) * gap
    local totalH = bh * cellSize + (bh - 1) * gap
    if img then
        local pad = 3
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
    end

    g.setColor(col[1], col[2], col[3], (isDragging and 0.98 or (isHovered and 0.96 or 0.72)) * alpha)
    g.setLineWidth(isDragging and 2.4 or (isHovered and 2.0 or 1.3))
    g.rectangle("line", originX + 1.5, originY + 1.5, totalW - 3, totalH - 3, 6, 6)
end

function ArmoryUI.new()
    return setmetatable({
        time = 0,
        activeCategory = "all",
        catalogScroll = 0,
        catalogMaxScroll = 0,
        chassisIndex = 1,
        chassisDrafts = {},
        baselineInventory = nil,
        dragging = nil,
        hoveredCatalogDef = nil,
        hoveredGridItem = nil,
        hoveredRegionIndex = nil,
        mouseX = 0,
        mouseY = 0,
        hitRegions = {},
        gridRect = nil,
        catalogListRect = nil,
        exitModal = nil,
        statusMessage = "좌측 부품을 우측 기체 그리드에 드래그해 조립하세요. (우클릭: 배치 해제)",
    }, ArmoryUI)
end

local function defaultStatusText(inv)
    if inv and inv.rotationUnlocked then
        return "좌측 부품을 우측 기체 그리드에 드래그해 조립하세요. (R: 회전, 우클릭: 배치 해제)"
    end
    return "좌측 부품을 우측 기체 그리드에 드래그해 조립하세요. (우클릭: 배치 해제)"
end

function ArmoryUI:open(sourceInventory)
    local base = sourceInventory and sourceInventory:clone() or Inventory.newStarter()
    self.baselineInventory = base:clone()
    self.chassisDrafts = {}
    self.chassisDrafts[base.chassisId] = base:clone()

    local ch = ChassisData.get(base.chassisId)
    self.chassisIndex = (ch and ch.index) or 1
    self.activeCategory = "all"
    self.catalogScroll = 0
    self.dragging = nil
    self.hoveredCatalogDef = nil
    self.hoveredGridItem = nil
    self.hoveredRegionIndex = nil
    self.exitModal = nil
    self.statusMessage = defaultStatusText(base)
    return base
end

function ArmoryUI:findPlacedModuleAt(inv, x, y)
    local gr = self.gridRect
    if not (gr and inv and inv.placed) then return nil end
    local step = gr.cellSize + gr.gap
    for i = #inv.placed, 1, -1 do
        local mod = inv.placed[i]
        if mod.row and mod.col then
            local ox = gr.x + (mod.col - 1) * step
            local oy = gr.y + (mod.row - 1) * step
            if isPointOverShape(mod, ox, oy, gr.cellSize, gr.gap, x, y) then
                return mod
            end
        end
    end
    return nil
end

function ArmoryUI:activeInventory(inv)
    local ch = ChassisData.list[self.chassisIndex] or ChassisData.getUnlockedDefault()
    if inv and inv.chassisId == ch.id then
        self.chassisDrafts[ch.id] = inv
        return inv
    end
    if self.chassisDrafts[ch.id] then
        return self.chassisDrafts[ch.id]
    end
    local draft = Inventory.new({ chassisId = ch.id })
    self.chassisDrafts[ch.id] = draft
    return draft
end

function ArmoryUI:switchChassis(inv, dir)
    if inv then
        self.chassisDrafts[inv.chassisId] = inv
    end
    self.dragging = nil
    self.hoveredGridItem = nil
    self.chassisIndex = ChassisData.nextIndex(self.chassisIndex, dir)
    local ch = ChassisData.list[self.chassisIndex]
    local nextInv = self.chassisDrafts[ch.id]
    if not nextInv then
        nextInv = Inventory.new({ chassisId = ch.id })
        self.chassisDrafts[ch.id] = nextInv
    end
    Sfx.play("ui_click")
    return nextInv
end

function ArmoryUI:addRegion(x, y, w, h, action)
    self.hitRegions[#self.hitRegions + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function ArmoryUI:computeSnappedOrigin(item, rotation, px, py)
    local gr = self.gridRect
    if not gr then return nil, nil end
    local _, w, h = Inventory.getShapeCells(item, rotation)
    local step = gr.cellSize + gr.gap
    local itemW = w * gr.cellSize + (w - 1) * gr.gap
    local itemH = h * gr.cellSize + (h - 1) * gr.gap
    local margin = gr.cellSize * 0.70
    if not pointInRect(px, py, gr.x - margin, gr.y - margin, gr.w + margin * 2, gr.h + margin * 2) then
        return nil, nil
    end
    local topLeftX = px - itemW * 0.5
    local topLeftY = py - itemH * 0.5
    local col = math.floor((topLeftX - gr.x + step * 0.5) / step) + 1
    local row = math.floor((topLeftY - gr.y + step * 0.5) / step) + 1
    return row, col
end

function ArmoryUI:cancelDrag(inv)
    local d = self.dragging
    if not d then return false end
    self.dragging = nil
    if d.origin == "grid" and inv then
        inv:placeItem(d.item, d.origRow, d.origCol, d.origRotation)
    end
    return true
end

function ArmoryUI:startCatalogDrag(inv, def, x, y)
    if self.dragging then
        self:cancelDrag(inv)
    end
    local mod = inv:createModule(def.id)
    self.dragging = {
        item = mod,
        origin = "catalog",
        startX = x,
        startY = y,
        moved = false,
        rotated = false,
        rotation = 0,
    }
    Sfx.play("ui_click")
end

function ArmoryUI:startGridDrag(inv, mod, x, y)
    if self.dragging then
        self:cancelDrag(inv)
    end
    local origRow, origCol, origRot = mod.row, mod.col, mod.rotation or 0
    inv:removeItem(mod, false)
    self.dragging = {
        item = mod,
        origin = "grid",
        origRow = origRow,
        origCol = origCol,
        origRotation = origRot,
        startX = x,
        startY = y,
        moved = false,
        rotated = false,
        rotation = origRot,
    }
    Sfx.play("ui_click")
end

function ArmoryUI:update(dt)
    if dt and dt > 0 then
        self.time = self.time + dt
    end
end

function ArmoryUI:_buildCatalogRows()
    local rows = {}
    if self.activeCategory == "all" then
        for _, cat in ipairs(ModulesData.categories) do
            rows[#rows + 1] = { kind = "header", category = cat }
            for _, def in ipairs(ModulesData.getByCategory(cat.id)) do
                rows[#rows + 1] = { kind = "module", def = def }
            end
        end
    else
        local cat = ModulesData.categoryById[self.activeCategory]
        if cat then
            rows[#rows + 1] = { kind = "header", category = cat }
            for _, def in ipairs(ModulesData.getByCategory(cat.id)) do
                rows[#rows + 1] = { kind = "module", def = def }
            end
        end
    end
    return rows
end

function ArmoryUI:_drawHeader(fonts, width, isValid)
    local g = love.graphics
    local c = Theme.colors

    g.setFont(fonts.titleMicro or fonts.menuSmall)
    Theme.setColor(c.accentBright, 0.78)
    g.print("ARMORY // ASSEMBLY BAY", 26, 14)

    g.setFont(fonts.menuTitle)
    Theme.setColor(c.textHero, 0.98)
    g.print("기체 조립 격납고", 24, 28)

    -- Reset to Starter preset button
    local resetW, resetH = 138, 36
    local resetX, resetY = width - 24 - 196 - 12 - resetW, 20
    local hoverReset = pointInRect(self.mouseX, self.mouseY, resetX, resetY, resetW, resetH)
    Theme.setColor(hoverReset and c.buttonSelectedBg or c.buttonBg, 0.95)
    g.rectangle("fill", resetX, resetY, resetW, resetH, 6, 6)
    Theme.setColor(hoverReset and c.accentBright or c.buttonBorder, 0.90)
    g.setLineWidth(1.2)
    g.rectangle("line", resetX, resetY, resetW, resetH, 6, 6)
    g.setFont(fonts.menuBody)
    Theme.setColor(c.textPrimary, 1)
    g.printf("기본 세팅", resetX, resetY + 9, resetW, "center")
    self:addRegion(resetX, resetY, resetW, resetH, { type = "resetStarter" })

    -- Save & Exit button
    local exitW, exitH = 196, 36
    local exitX, exitY = width - 24 - exitW, 20
    local hoverExit = pointInRect(self.mouseX, self.mouseY, exitX, exitY, exitW, exitH)
    if isValid then
        g.setColor(hoverExit and 0.14 or 0.09, hoverExit and 0.36 or 0.25, hoverExit and 0.38 or 0.28, 0.96)
        g.rectangle("fill", exitX, exitY, exitW, exitH, 6, 6)
        Theme.setColor(hoverExit and c.accentBright or c.accent, 0.95)
    else
        g.setColor(hoverExit and 0.34 or 0.22, hoverExit and 0.12 or 0.08, hoverExit and 0.14 or 0.09, 0.96)
        g.rectangle("fill", exitX, exitY, exitW, exitH, 6, 6)
        Theme.setColor(c.dangerBright, 0.92)
    end
    g.setLineWidth(1.5)
    g.rectangle("line", exitX, exitY, exitW, exitH, 6, 6)
    g.setFont(fonts.menuBody)
    Theme.setColor(c.textHero, 1)
    g.printf(isValid and "저장 후 나가기" or "나가기 (경고)", exitX, exitY + 9, exitW, "center")
    self:addRegion(exitX, exitY, exitW, exitH, { type = "saveAndExit" })
end

function ArmoryUI:_drawCatalogPanel(fonts)
    local g = love.graphics
    local c = Theme.colors
    local px, py, pw, ph = 24, 70, 446, 626

    Theme.setColor(c.panelBg, 0.94)
    g.rectangle("fill", px, py, pw, ph, 8, 8)
    Theme.setColor(c.panelBorder, 0.72)
    g.setLineWidth(1.3)
    g.rectangle("line", px, py, pw, ph, 8, 8)

    -- Category filter tabs
    local tabs = {
        { id = "all", name = "전체" },
        { id = "weapon", name = "무기" },
        { id = "defense", name = "방호" },
        { id = "thruster", name = "추진기" },
        { id = "generator", name = "제너레이터" },
    }
    local tabX = px + 12
    local tabY = py + 12
    local tabGap = 6
    local tabW = math.floor((pw - 24 - (#tabs - 1) * tabGap) / #tabs)
    local tabH = 30
    for i, tab in ipairs(tabs) do
        local tx = tabX + (i - 1) * (tabW + tabGap)
        local active = (self.activeCategory == tab.id)
        local hovered = pointInRect(self.mouseX, self.mouseY, tx, tabY, tabW, tabH)
        if active then
            Theme.setColor(c.buttonSelectedBg, 0.98)
        elseif hovered then
            Theme.setColor(c.buttonBg, 0.96)
        else
            g.setColor(0.026, 0.048, 0.082, 0.92)
        end
        g.rectangle("fill", tx, tabY, tabW, tabH, 5, 5)
        Theme.setColor(active and c.accentBright or c.panelBorder, active and 0.95 or 0.65)
        g.setLineWidth(active and 1.5 or 1.0)
        g.rectangle("line", tx, tabY, tabW, tabH, 5, 5)

        g.setFont(fonts.menuSmall or fonts.menuBody)
        Theme.setColor(active and c.textHero or c.textSecondary, 1)
        g.printf(tab.name, tx, tabY + 8, tabW, "center")
        self:addRegion(tx, tabY, tabW, tabH, { type = "selectCategory", category = tab.id })
    end

    -- Scrollable module list
    local listX, listY = px + 12, tabY + tabH + 10
    local listW, listH = pw - 24, ph - (tabH + 34)
    self.catalogListRect = { x = listX, y = listY, w = listW, h = listH }

    local rows = self:_buildCatalogRows()
    local totalH = 0
    for _, row in ipairs(rows) do
        totalH = totalH + (row.kind == "header" and 24 or 61)
    end
    self.catalogMaxScroll = math.max(0, totalH - listH)
    self.catalogScroll = Theme.clamp(self.catalogScroll, 0, self.catalogMaxScroll)

    g.push("all")
    local sx, sy, sw, sh = Display.virtualRectToWindow(listX, listY, listW, listH)
    g.intersectScissor(sx, sy, sw, sh)

    local drawY = listY - self.catalogScroll
    for _, row in ipairs(rows) do
        if row.kind == "header" then
            local hdrH = 21
            if drawY + hdrH >= listY and drawY <= listY + listH then
                g.setColor(0.055, 0.115, 0.175, 0.86)
                g.rectangle("fill", listX, drawY + 1, listW, hdrH - 1, 4, 4)
                Theme.setColor(c.accent, 0.72)
                g.rectangle("fill", listX, drawY + 3, 3, hdrH - 5, 1.5, 1.5)
                g.setFont(fonts.menuSmall or fonts.menuBody)
                Theme.setColor(c.accentBright, 0.94)
                g.print(row.category.name .. "  [" .. row.category.tag .. "]", listX + 10, drawY + 3)
            end
            drawY = drawY + 24
        else
            local def = row.def
            local rowH = 56
            if drawY + rowH >= listY and drawY <= listY + listH then
                local rc = Rarity.getColor(def.rarity)
                local inList = pointInRect(self.mouseX, self.mouseY, listX, listY, listW, listH)
                local isHovered = (not self.exitModal) and inList and pointInRect(self.mouseX, self.mouseY, listX, drawY, listW, rowH)
                local isDraggedDef = self.dragging and self.dragging.item and self.dragging.item.defId == def.id

                g.setColor(isHovered and 0.085 or 0.032, isHovered and 0.155 or 0.060, isHovered and 0.225 or 0.100, 0.96)
                g.rectangle("fill", listX, drawY, listW, rowH, 6, 6)
                g.setColor(rc[1], rc[2], rc[3], (isHovered or isDraggedDef) and 0.95 or 0.55)
                g.setLineWidth((isHovered or isDraggedDef) and 1.8 or 1.1)
                g.rectangle("line", listX, drawY, listW, rowH, 6, 6)

                -- Image thumbnail box
                local thumbSize = 44
                local tx, ty = listX + 7, drawY + 6
                g.setColor(0.02, 0.04, 0.07, 0.95)
                g.rectangle("fill", tx, ty, thumbSize, thumbSize, 5, 5)
                g.setColor(rc[1], rc[2], rc[3], 0.58)
                g.setLineWidth(1)
                g.rectangle("line", tx, ty, thumbSize, thumbSize, 5, 5)
                local img = getDefImage(def)
                if img then
                    local iw, ih = img:getDimensions()
                    local sc = math.min((thumbSize - 6) / iw, (thumbSize - 6) / ih)
                    g.setColor(1, 1, 1, 0.98)
                    g.draw(img, tx + thumbSize * 0.5, ty + thumbSize * 0.5, 0, sc, sc, iw * 0.5, ih * 0.5)
                end

                -- Name + Size + Brief stats
                local textX = tx + thumbSize + 12
                local textW = listW - (textX - listX) - 10
                g.setFont(fonts.menuBody)
                g.setColor(rc[1], rc[2], rc[3], 1)
                g.print(def.name, textX, drawY + 6)

                g.setFont(fonts.menuSmall or fonts.menuBody)
                Theme.setColor(c.textSecondary, 0.92)
                local sizeTag = string.format("%dx%d", def.w or 1, def.h or 1)
                g.printf(sizeTag, textX, drawY + 8, textW, "right")

                Theme.setColor(c.textMuted, 0.95)
                g.print(formatBriefCatalogStats(def), textX, drawY + 30)

                local visTop = math.max(listY, drawY)
                local visBot = math.min(drawY + rowH, listY + listH)
                if visBot > visTop then
                    self:addRegion(listX, visTop, listW, visBot - visTop,
                        { type = "catalogItem", def = def })
                end
            end
            drawY = drawY + 61
        end
    end
    g.pop()

    -- Scrollbar indicator when list overflows
    if self.catalogMaxScroll > 0 then
        local trackX = px + pw - 8
        local trackY = listY
        local trackH = listH
        local thumbH = math.max(28, trackH * (listH / totalH))
        local thumbY = trackY + (trackH - thumbH) * (self.catalogScroll / self.catalogMaxScroll)
        g.setColor(0.10, 0.18, 0.25, 0.55)
        g.rectangle("fill", trackX, trackY, 4, trackH, 2, 2)
        Theme.setColor(c.accent, 0.78)
        g.rectangle("fill", trackX, thumbY, 4, thumbH, 2, 2)
    end
end

function ArmoryUI:_drawInspectorPanel(inv, fonts, validationSummary)
    local g = love.graphics
    local c = Theme.colors
    local px, py, pw, ph = 486, 70, 770, 186

    Theme.setColor(c.panelBg, 0.94)
    g.rectangle("fill", px, py, pw, ph, 8, 8)
    Theme.setColor(c.panelBorder, 0.72)
    g.setLineWidth(1.3)
    g.rectangle("line", px, py, pw, ph, 8, 8)

    local inspectItem = (self.dragging and self.dragging.item) or self.hoveredGridItem
    local inspectDef = (inspectItem and inspectItem.def) or self.hoveredCatalogDef

    if inspectDef then
        local rarity = (inspectItem and inspectItem.rarity) or inspectDef.rarity
        local rc = Rarity.getColor(rarity)
        local rarityLabel = Rarity.getLabel(rarity)
        local rot = inspectItem and inspectItem.rotation or 0
        local shapeCells, iw, ih = Inventory.getShapeCells(inspectItem or inspectDef, rot)

        -- Artwork box
        local boxSize = 112
        local bx, by = px + 18, py + 18
        g.setColor(0.022, 0.042, 0.075, 0.96)
        g.rectangle("fill", bx, by, boxSize, boxSize, 7, 7)
        g.setColor(rc[1], rc[2], rc[3], 0.78)
        g.setLineWidth(1.4)
        g.rectangle("line", bx, by, boxSize, boxSize, 7, 7)
        local img = getDefImage(inspectDef)
        if img then
            local imgW, imgH = img:getDimensions()
            local sc = math.min((boxSize - 14) / imgW, (boxSize - 14) / imgH)
            g.setColor(1, 1, 1, 0.98)
            g.draw(img, bx + boxSize * 0.5, by + boxSize * 0.5, 0, sc, sc, imgW * 0.5, imgH * 0.5)
        end

        -- Mini grid shape preview under thumbnail
        local miniCell = 11
        local miniGap = 2
        local shapeW = iw * miniCell + (iw - 1) * miniGap
        local sx0 = bx + math.floor((boxSize - shapeW) * 0.5)
        local sy0 = by + boxSize + 10
        for _, coord in ipairs(shapeCells) do
            local cx = sx0 + coord[2] * (miniCell + miniGap)
            local cy = sy0 + coord[1] * (miniCell + miniGap)
            g.setColor(rc[1], rc[2], rc[3], 0.38)
            g.rectangle("fill", cx, cy, miniCell, miniCell, 2, 2)
            g.setColor(rc[1], rc[2], rc[3], 0.92)
            g.setLineWidth(1)
            g.rectangle("line", cx, cy, miniCell, miniCell, 2, 2)
        end

        -- Header & detailed stats
        local tx = bx + boxSize + 20
        local tw = px + pw - tx - 18
        g.setFont(fonts.menuButton or fonts.menuBody)
        g.setColor(rc[1], rc[2], rc[3], 1)
        g.print(string.format("[%s] %s", rarityLabel, inspectDef.name), tx, py + 16)

        g.setFont(fonts.menuSmall or fonts.menuBody)
        Theme.setColor(c.accentBright, 0.90)
        local catLabel = ModulesData.getCategoryLabel(inspectDef.category)
        g.printf(catLabel .. string.format("  ·  %dx%d", iw, ih), tx, py + 19, tw, "right")

        local statLines = formatModuleStatLines(inspectDef)
        g.setFont(fonts.menuBody)
        Theme.setColor(c.textPrimary, 0.96)
        for i, line in ipairs(statLines) do
            g.print(line, tx, py + 50 + (i - 1) * 24)
        end

        g.setFont(fonts.menuBody)
        Theme.setColor(c.textSecondary, 0.94)
        g.printf(inspectDef.description or "", tx, py + 104, tw, "left")

        g.setFont(fonts.menuSmall or fonts.menuBody)
        local inspectCat = inspectDef.category == "battery" and "generator" or inspectDef.category
        local pen = (inspectItem and inspectItem.row and validationSummary.categoryPenalties)
            and validationSummary.categoryPenalties[inspectCat]
            or nil
        if pen and pen.addPct > 0 then
            g.setColor(1.0, 0.78, 0.28, 0.96)
            drawWarningTriangle(tx + 7, py + ph - 19, 5.5)
            g.print(string.format("주의: %s %d개 장착 — 이 모듈 배터리 사용량 +%d%% (우클릭: 배치 해제)",
                pen.label, pen.count, pen.addPct), tx + 18, py + ph - 26)
        else
            Theme.setColor(c.textMuted, 0.85)
            local hint
            if inspectItem and inspectItem.row then
                hint = inv.rotationUnlocked
                    and "드래그해 이동 · R: 회전 · 우클릭: 배치 해제"
                    or "드래그해 이동 · 우클릭: 배치 해제"
            else
                hint = inv.rotationUnlocked
                    and "그리드로 드래그해 장착 · 드래그 중 R: 회전"
                    or "그리드로 드래그해 장착"
            end
            g.print(hint, tx, py + ph - 26)
        end
        return
    end

    -- Idle state: full assembled ship spec summary
    local ch = inv.chassis or ChassisData.get(inv.chassisId)
    local build = validationSummary.build
    local cautions = validationSummary.cautions or {}
    local penalties = validationSummary.categoryPenalties or {}
    local hasThrPenalty = penalties.thruster and penalties.thruster.addPct > 0

    g.setFont(fonts.menuButton or fonts.menuBody)
    Theme.setColor(c.accentBright, 0.98)
    g.print("현재 기체 종합 스펙", px + 20, py + 14)

    g.setFont(fonts.menuSmall or fonts.menuBody)
    Theme.setColor(c.textMuted, 0.90)
    g.printf("부품 위에 마우스를 올리면 상세 정보가 표시됩니다", px + 20, py + 18, pw - 40, "right")

    if ch and ch.locked then
        g.setFont(fonts.menuBody)
        Theme.setColor(c.textSecondary, 0.95)
        g.print("섀시: ??? (미해금)", px + 20, py + 54)
        g.print("특수 효과: ???", px + 20, py + 84)
        g.print(ch.description or "", px + 20, py + 118)
        return
    end

    local col1X, col2X, col3X = px + 20, px + 278, px + 532
    local rowY = #cautions > 0 and (py + 46) or (py + 52)
    local rowStep = #cautions > 0 and 26 or 28
    local hasDefPenalty = penalties.defense and penalties.defense.addPct > 0
    g.setFont(fonts.menuBody)
    if hasDefPenalty and (build.shieldRegen or 0) > 0 then
        g.setColor(1.0, 0.80, 0.34, 0.98)
    else
        Theme.setColor(c.textPrimary, 0.96)
    end
    if (build.shieldRegen or 0) > 0 then
        g.print(string.format("실드: %d (+%s/s, -%s/s)",
            build.maxShield or 0, formatNum(build.shieldRegen), formatNum(build.shieldRegenBatteryCost or 0)), col1X, rowY)
    else
        g.print(string.format("실드: %d", build.maxShield or 0), col1X, rowY)
    end
    Theme.setColor(c.textPrimary, 0.96)
    g.print(string.format("아머: %d", build.maxArmor or 0), col1X, rowY + rowStep)
    g.print(string.format("헐: %d", build.maxHull or 0), col1X, rowY + rowStep * 2)
    g.print(string.format("장착 무기: %d개", validationSummary.weaponCount or 0), col1X, rowY + rowStep * 3)

    g.print(string.format("배터리 총량: %d", build.maxBattery or 0), col2X, rowY)
    g.print(string.format("초당 충전: +%.0f/s", build.batteryRecharge or 0), col2X, rowY + rowStep)
    if hasThrPenalty then g.setColor(1.0, 0.80, 0.34, 0.98) else Theme.setColor(c.textPrimary, 0.96) end
    g.print(string.format("가속 소모: %.0f/s", build.thrustBatteryCost or 0), col2X, rowY + rowStep * 2)
    g.print(string.format("부스트 소모: %d", build.boostCost or 0), col2X, rowY + rowStep * 3)

    Theme.setColor(c.textPrimary, 0.96)
    g.print(string.format("최고속도: %d", build.maxSpeed or 0), col3X, rowY)
    g.print(string.format("부스트속도: %d", build.boostSpeed or 0), col3X, rowY + rowStep)
    g.print(string.format("추진력: %d", build.thrust or 0), col3X, rowY + rowStep * 2)
    g.print("특수 효과: " .. (ch and ch.specialEffect or "없음"), col3X, rowY + rowStep * 3)

    if #cautions > 0 then
        local stripX, stripY, stripW, stripH = px + 18, py + ph - 30, pw - 36, 22
        g.setColor(0.24, 0.16, 0.04, 0.86)
        g.rectangle("fill", stripX, stripY, stripW, stripH, 4, 4)
        g.setColor(1.0, 0.78, 0.28, 0.55)
        g.setLineWidth(1.0)
        g.rectangle("line", stripX, stripY, stripW, stripH, 4, 4)
        g.setColor(1.0, 0.80, 0.30, 0.98)
        drawWarningTriangle(stripX + 14, stripY + 11, 5.5)
        local msgs = {}
        for i = 1, math.min(2, #cautions) do
            msgs[#msgs + 1] = cautions[i].message
        end
        local text = "주의: " .. table.concat(msgs, "  /  ")
        if #cautions > 2 then
            text = text .. string.format(" (외 %d건)", #cautions - 2)
        end
        g.setFont(fonts.menuSmall or fonts.menuBody)
        g.print(text, stripX + 26, stripY + 3)
    end
end

function ArmoryUI:_drawChassisAndGridPanel(inv, fonts, isValid, warnings, summary)
    local g = love.graphics
    local c = Theme.colors
    local px, py, pw, ph = 486, 268, 770, 428

    Theme.setColor(c.panelBg, 0.94)
    g.rectangle("fill", px, py, pw, ph, 8, 8)
    Theme.setColor(c.panelBorder, 0.72)
    g.setLineWidth(1.3)
    g.rectangle("line", px, py, pw, ph, 8, 8)

    local ch = inv.chassis or ChassisData.get(inv.chassisId)

    -- 1. Chassis Selector Header Bar (y = 268..310)
    local barH = 44
    g.setColor(0.024, 0.046, 0.080, 0.94)
    g.rectangle("fill", px + 1, py + 1, pw - 2, barH, 7, 7)
    Theme.setColor(c.panelBorder, 0.55)
    g.line(px + 8, py + barH, px + pw - 8, py + barH)

    local prevX, prevY, navW, navH = px + 12, py + 7, 36, 30
    local nextX = px + 362
    local hoverPrev = pointInRect(self.mouseX, self.mouseY, prevX, prevY, navW, navH)
    local hoverNext = pointInRect(self.mouseX, self.mouseY, nextX, prevY, navW, navH)

    for _, nav in ipairs({ { x = prevX, hover = hoverPrev, dir = -1 }, { x = nextX, hover = hoverNext, dir = 1 } }) do
        Theme.setColor(nav.hover and c.buttonSelectedBg or c.buttonBg, 0.96)
        g.rectangle("fill", nav.x, prevY, navW, navH, 5, 5)
        Theme.setColor(nav.hover and c.accentBright or c.panelBorder, 0.90)
        g.setLineWidth(1.2)
        g.rectangle("line", nav.x, prevY, navW, navH, 5, 5)
        Theme.setColor(nav.hover and c.textHero or c.accentBright, 1)
        drawArrowTriangle(nav.x + navW * 0.5, prevY + navH * 0.5, 6.5, nav.dir)
        self:addRegion(nav.x, prevY, navW, navH, { type = "switchChassis", dir = nav.dir })
    end

    g.setFont(fonts.menuButton or fonts.menuBody)
    Theme.setColor(ch.locked and c.textMuted or c.textHero, 1)
    local chassisTitle = string.format("%s  %s", ch.code or "", ch.name or "")
    g.printf(chassisTitle, prevX + navW + 8, py + 12, nextX - (prevX + navW + 16), "center")

    g.setFont(fonts.menuSmall or fonts.menuBody)
    Theme.setColor(c.textSecondary, 0.92)
    local baseInfo = ch.locked
        and string.format("섀시 %d/%d  ·  미해금 기체", self.chassisIndex, #ChassisData.list)
        or string.format("섀시 %d/%d  ·  기본 장갑 %d · 선체 %d · 실드 %d",
            self.chassisIndex, #ChassisData.list,
            ch.baseStats.maxArmor or 0, ch.baseStats.maxHull or 0, ch.baseStats.maxShield or 0)
    g.printf(baseInfo, nextX + navW + 14, py + 15, px + pw - (nextX + navW + 26), "right")

    -- 2. Hangar Ship Silhouette + 5x3 Triangle Grid Overlay (y = 314..610)
    local vpX, vpY, vpW, vpH = px + 14, py + barH + 8, pw - 28, 288
    g.setColor(0.016, 0.032, 0.058, 0.95)
    g.rectangle("fill", vpX, vpY, vpW, vpH, 6, 6)
    g.setColor(0.16, 0.34, 0.44, 0.42)
    g.setLineWidth(1)
    g.rectangle("line", vpX, vpY, vpW, vpH, 6, 6)

    -- Subtle blueprint crosshairs
    g.setColor(0.14, 0.30, 0.42, 0.16)
    for gx = vpX + 48, vpX + vpW - 24, 48 do
        g.line(gx, vpY + 6, gx, vpY + vpH - 6)
    end
    for gy = vpY + 48, vpY + vpH - 24, 48 do
        g.line(vpX + 6, gy, vpX + vpW - 6, gy)
    end

    local shipCx = vpX + vpW * 0.5
    local shipCy = vpY + vpH * 0.5 + 12
    Ship.drawChassis(ch.id, shipCx, shipCy, 0, 6.0, self.time, { locked = ch.locked })

    if ch.locked then
        self.gridRect = nil
        g.setColor(0.02, 0.04, 0.07, 0.65)
        g.rectangle("fill", shipCx - 170, shipCy - 26, 340, 56, 8, 8)
        Theme.setColor(c.panelBorder, 0.85)
        g.rectangle("line", shipCx - 170, shipCy - 26, 340, 56, 8, 8)
        g.setFont(fonts.menuButton or fonts.menuBody)
        Theme.setColor(c.textHero, 0.96)
        g.printf("???", shipCx - 160, shipCy - 18, 320, "center")
        g.setFont(fonts.menuSmall or fonts.menuBody)
        Theme.setColor(c.textSecondary, 0.92)
        g.printf("추후 신규 섀시 및 특수 효과가 추가됩니다", shipCx - 160, shipCy + 6, 320, "center")
    else
        local cellSize = 58
        local gap = 6
        local step = cellSize + gap
        local gridW = inv.cols * cellSize + (inv.cols - 1) * gap
        local gridH = inv.rows * cellSize + (inv.rows - 1) * gap
        local gx = math.floor(shipCx - gridW * 0.5)
        local gy = math.floor(vpY + (vpH - gridH) * 0.5 + 8)
        self.gridRect = {
            x = gx, y = gy, w = gridW, h = gridH,
            cellSize = cellSize, gap = gap, rows = inv.rows, cols = inv.cols,
        }

        -- Semi-transparent glass cells overlaid on the ship silhouette
        for r = 1, inv.rows do
            for cIdx = 1, inv.cols do
                if inv:isValidCell(r, cIdx) then
                    local cx = gx + (cIdx - 1) * step
                    local cy = gy + (r - 1) * step
                    g.setColor(0.03, 0.09, 0.15, 0.54)
                    g.rectangle("fill", cx, cy, cellSize, cellSize, 6, 6)
                    Theme.setColor(c.accent, 0.62)
                    g.setLineWidth(1.2)
                    g.rectangle("line", cx, cy, cellSize, cellSize, 6, 6)
                end
            end
        end

        -- Ghost at original cell while dragging from grid
        if self.dragging and self.dragging.origin == "grid" and self.dragging.origRow then
            local origCells = Inventory.getShapeCells(self.dragging.item, self.dragging.origRotation)
            for _, coord in ipairs(origCells) do
                local cx = gx + (self.dragging.origCol + coord[2] - 1) * step + 3
                local cy = gy + (self.dragging.origRow + coord[1] - 1) * step + 3
                g.setColor(0.65, 0.88, 1.0, 0.16)
                g.rectangle("fill", cx, cy, cellSize - 6, cellSize - 6, 5, 5)
                g.setColor(0.65, 0.88, 1.0, 0.45)
                g.setLineWidth(1.2)
                g.rectangle("line", cx, cy, cellSize - 6, cellSize - 6, 5, 5)
            end
        end

        -- Placed modules on the 5x3 triangle grid
        for _, mod in ipairs(inv.placed) do
            local ox = gx + (mod.col - 1) * step
            local oy = gy + (mod.row - 1) * step
            local isHovered = (not self.exitModal) and (not self.dragging)
                and isPointOverShape(mod, ox, oy, cellSize, gap, self.mouseX, self.mouseY)
            drawGridModule(mod, ox, oy, cellSize, gap, {
                hovered = isHovered,
                alpha = 0.94,
            })

            local shapeCells = Inventory.getShapeCells(mod, mod.rotation)
            for _, coord in ipairs(shapeCells) do
                local cx = ox + coord[2] * step
                local cy = oy + coord[1] * step
                self:addRegion(cx, cy, cellSize, cellSize, { type = "gridModule", mod = mod })
            end
        end

        -- Drop preview highlight
        if self.dragging then
            local d = self.dragging
            local snapR, snapC = self:computeSnappedOrigin(d.item, d.rotation, self.mouseX, self.mouseY)
            if snapR and snapC then
                local valid = inv:canPlace(d.item, snapR, snapC, d.rotation)
                local shapeCells = Inventory.getShapeCells(d.item, d.rotation)
                for _, coord in ipairs(shapeCells) do
                    local tr, tc = snapR + coord[1], snapC + coord[2]
                    if tr >= 1 and tr <= inv.rows and tc >= 1 and tc <= inv.cols then
                        local cx = gx + (tc - 1) * step
                        local cy = gy + (tr - 1) * step
                        if valid then
                            g.setColor(0.32, 0.96, 0.68, 0.34)
                            g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                            g.setColor(0.42, 1.0, 0.74, 0.96)
                            g.setLineWidth(2.2)
                            g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                        else
                            g.setColor(1.0, 0.28, 0.32, 0.34)
                            g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                            g.setColor(1.0, 0.38, 0.42, 0.96)
                            g.setLineWidth(2.2)
                            g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 6, 6)
                        end
                    end
                end
            end
        end
    end

    -- 3. Bottom Power & Mandatory Validation Bar (y = 612..694)
    local footX, footY, footW, footH = px + 14, vpY + vpH + 8, pw - 28, 76
    g.setColor(0.022, 0.042, 0.072, 0.95)
    g.rectangle("fill", footX, footY, footW, footH, 6, 6)
    g.setColor(isValid and c.panelBorder[1] or c.danger[1],
        isValid and c.panelBorder[2] or c.danger[2],
        isValid and c.panelBorder[3] or c.danger[3],
        isValid and 0.65 or 0.85)
    g.setLineWidth(1.2)
    g.rectangle("line", footX, footY, footW, footH, 6, 6)

    -- Mandatory parts indicators
    local reqItems = {
        { label = "무기", ok = (summary.weaponCount or 0) >= 1 },
        { label = "추진기", ok = (summary.thrusterCount or 0) >= 1 },
        { label = "제너레이터", ok = (summary.generatorCount or 0) >= 1 },
    }
    local reqX = footX + 14
    local reqY = footY + 10
    g.setFont(fonts.menuSmall or fonts.menuBody)
    for _, req in ipairs(reqItems) do
        local col = req.ok and { 0.42, 0.95, 0.72 } or c.dangerBright
        g.setColor(col[1], col[2], col[3], 0.95)
        drawCheckIcon(reqX + 6, reqY + 8, 6, req.ok)
        g.print(req.label, reqX + 17, reqY + 1)
        reqX = reqX + 92
    end

    -- Battery capacity check vs single-action peak consumption (weapon shot / boost)
    local peakCost = summary.maxSingleActionBatteryCost or 0
    local maxBatVal = summary.maxBattery or 0
    local rechargeVal = summary.batteryRecharge or 0
    local capOver = peakCost > maxBatVal

    local meterX = footX + 298
    local meterW = 240
    local meterY = footY + 12
    g.setColor(0.08, 0.14, 0.20, 0.95)
    g.rectangle("fill", meterX, meterY + 14, meterW, 6, 3, 3)
    local ratio = maxBatVal > 0 and math.min(1, peakCost / maxBatVal) or (peakCost > 0 and 1 or 0)
    g.setColor(capOver and c.dangerBright[1] or c.accent[1],
        capOver and c.dangerBright[2] or c.accent[2],
        capOver and c.dangerBright[3] or c.accent[3], 0.95)
    g.rectangle("fill", meterX, meterY + 14, meterW * ratio, 6, 3, 3)

    g.setFont(fonts.menuSmall or fonts.menuBody)
    Theme.setColor(capOver and c.dangerBright or c.textPrimary, 0.96)
    g.print(string.format("최대 1회 소모 / 배터리 총량: %d / %d", peakCost, maxBatVal), meterX, footY + 6)

    Theme.setColor(c.textPrimary, 0.96)
    g.printf(string.format("초당 충전: +%.0f/s", rechargeVal), footX + 550, footY + 10, footW - 564, "right")

    -- Bottom warning / caution / status line
    local warnY = footY + 42
    local cautions = summary.cautions or {}
    g.setFont(fonts.menuBody)
    if not isValid then
        local pulse = 0.78 + 0.22 * math.sin(self.time * 6.0)
        g.setColor(0.28, 0.06, 0.08, 0.88 * pulse)
        g.rectangle("fill", footX + 8, warnY - 3, footW - 16, 26, 4, 4)
        g.setColor(c.dangerBright[1], c.dangerBright[2], c.dangerBright[3], pulse)
        drawWarningTriangle(footX + 22, warnY + 10, 7)
        local primaryMsg = warnings[1] and warnings[1].message or "이대로 출격할 수 없습니다."
        if #warnings > 1 then
            primaryMsg = primaryMsg .. string.format(" (외 %d건)", #warnings - 1)
        end
        g.print("출격 불가: " .. primaryMsg, footX + 36, warnY)
    elseif #cautions > 0 then
        g.setColor(0.24, 0.16, 0.04, 0.88)
        g.rectangle("fill", footX + 8, warnY - 3, footW - 16, 26, 4, 4)
        g.setColor(1.0, 0.78, 0.28, 0.96)
        drawWarningTriangle(footX + 22, warnY + 10, 7)
        local cautionMsg = cautions[1].message
        if #cautions > 1 then
            cautionMsg = cautionMsg .. string.format(" (외 %d건)", #cautions - 1)
        end
        g.print("주의: " .. cautionMsg .. " · 출격 가능", footX + 36, warnY)
    else
        g.setColor(0.44, 0.95, 0.72, 0.96)
        g.print("출격 가능 · " .. self.statusMessage, footX + 14, warnY)
    end
end

function ArmoryUI:_drawExitModal(fonts, width, height)
    if not self.exitModal then return end
    local g = love.graphics
    local c = Theme.colors
    local ox, oy, ow, oh = Display.virtualOverscanBounds()

    g.setColor(0.01, 0.015, 0.03, 0.76)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    local mw, mh = 540, 268
    local mx = math.floor((width - mw) * 0.5)
    local my = math.floor((height - mh) * 0.5)

    g.setColor(0.055, 0.038, 0.058, 0.98)
    g.rectangle("fill", mx, my, mw, mh, 10, 10)
    Theme.setColor(c.dangerBright, 0.95)
    g.setLineWidth(2)
    g.rectangle("line", mx, my, mw, mh, 10, 10)

    g.setColor(c.dangerBright[1], c.dangerBright[2], c.dangerBright[3], 0.95)
    drawWarningTriangle(mx + 34, my + 34, 10)

    g.setFont(fonts.menuButton or fonts.menuBody)
    Theme.setColor(c.dangerText, 1)
    g.print("이대로는 출격할 수 없습니다", mx + 56, my + 24)

    g.setFont(fonts.menuBody)
    Theme.setColor(c.textPrimary, 0.95)
    local y = my + 66
    for i = 1, math.min(4, #(self.exitModal.warnings or {})) do
        g.print("· " .. self.exitModal.warnings[i].message, mx + 26, y)
        y = y + 26
    end

    local btnY = my + mh - 56
    local btnW = 224
    local stayX = mx + 28
    local revertX = mx + mw - btnW - 28

    local hoverStay = pointInRect(self.mouseX, self.mouseY, stayX, btnY, btnW, 38)
    Theme.setColor(hoverStay and c.buttonSelectedBg or c.buttonBg, 0.98)
    g.rectangle("fill", stayX, btnY, btnW, 38, 6, 6)
    Theme.setColor(hoverStay and c.accentBright or c.accent, 0.92)
    g.setLineWidth(1.4)
    g.rectangle("line", stayX, btnY, btnW, 38, 6, 6)
    g.setFont(fonts.menuBody)
    Theme.setColor(c.textHero, 1)
    g.printf("계속 조립", stayX, btnY + 10, btnW, "center")
    self:addRegion(stayX, btnY, btnW, 38, { type = "modalStay" })

    local hoverRevert = pointInRect(self.mouseX, self.mouseY, revertX, btnY, btnW, 38)
    Theme.setColor(hoverRevert and c.dangerSelectedBg or c.dangerBg, 0.98)
    g.rectangle("fill", revertX, btnY, btnW, 38, 6, 6)
    Theme.setColor(hoverRevert and c.dangerBright or c.dangerBorder, 0.95)
    g.setLineWidth(1.4)
    g.rectangle("line", revertX, btnY, btnW, 38, 6, 6)
    Theme.setColor(c.dangerSelectedText, 1)
    g.printf("이전 세팅 복원 후 나가기", revertX, btnY + 10, btnW, "center")
    self:addRegion(revertX, btnY, btnW, 38, { type = "modalRevertExit" })
end

function ArmoryUI:draw(inv, fonts, width, height)
    local activeInv = self:activeInventory(inv)
    local isValid, warnings, summary = activeInv:validateLoadout(false)
    local g = love.graphics
    self.hitRegions = {}

    g.push("all")
    local ox, oy, ow, oh = Display.virtualOverscanBounds()
    g.setColor(0.012, 0.021, 0.042, 0.92)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    self:_drawHeader(fonts, width, isValid)
    self:_drawCatalogPanel(fonts)
    self:_drawInspectorPanel(activeInv, fonts, summary)
    self:_drawChassisAndGridPanel(activeInv, fonts, isValid, warnings, summary)

    -- Floating dragged module
    if self.dragging and self.gridRect then
        local d = self.dragging
        local cs, gp = self.gridRect.cellSize, self.gridRect.gap
        local _, dw, dh = Inventory.getShapeCells(d.item, d.rotation)
        local itemW = dw * cs + (dw - 1) * gp
        local itemH = dh * cs + (dh - 1) * gp
        local drawX = self.mouseX - itemW * 0.5
        local drawY = self.mouseY - itemH * 0.5
        drawGridModule(d.item, drawX, drawY, cs, gp, {
            rotation = d.rotation,
            dragging = true,
            alpha = 0.92,
        })
        if activeInv.rotationUnlocked then
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
    elseif self.dragging then
        local d = self.dragging
        local cs, gp = 58, 6
        local _, dw, dh = Inventory.getShapeCells(d.item, d.rotation)
        local itemW = dw * cs + (dw - 1) * gp
        local itemH = dh * cs + (dh - 1) * gp
        drawGridModule(d.item, self.mouseX - itemW * 0.5, self.mouseY - itemH * 0.5, cs, gp, {
            rotation = d.rotation,
            dragging = true,
            alpha = 0.92,
        })
    end

    self:_drawExitModal(fonts, width, height)
    g.pop()
    return activeInv
end

function ArmoryUI:finishDrop(inv, x, y)
    local d = self.dragging
    if not d then return inv, nil end
    self.dragging = nil

    if self.gridRect and not (inv.chassis and inv.chassis.locked) then
        local snapR, snapC = self:computeSnappedOrigin(d.item, d.rotation, x, y)
        if snapR and snapC then
            local ok, reason = inv:placeItem(d.item, snapR, snapC, d.rotation)
            if ok then
                Sfx.play("ui_equip")
                self.statusMessage = d.item.def.name .. "을(를) 장착했습니다."
                return inv, "changed"
            else
                if d.origin == "grid" then
                    inv:placeItem(d.item, d.origRow, d.origCol, d.origRotation)
                end
                Sfx.play("ui_error")
                self.statusMessage = "배치 불가 (" .. tostring(reason) .. ")"
                return inv, nil
            end
        end
    end

    if d.origin == "grid" then
        Sfx.play("ui_click")
        self.statusMessage = d.item.def.name .. "을(를) 해제했습니다."
        return inv, "changed"
    end

    Sfx.play("ui_click")
    return inv, nil
end

function ArmoryUI:tryExit(inv)
    local activeInv = self:activeInventory(inv)
    self:cancelDrag(activeInv)
    local isValid, warnings = activeInv:validateLoadout(false)
    if isValid then
        Sfx.play("ui_click")
        return activeInv, "saveAndExit"
    end
    Sfx.play("ui_error")
    self.exitModal = { warnings = warnings }
    return activeInv, nil
end

function ArmoryUI:mousemoved(inv, x, y)
    self.mouseX, self.mouseY = x, y
    local activeInv = self:activeInventory(inv)

    if self.exitModal then
        self.hoveredCatalogDef = nil
        self.hoveredGridItem = nil
        return
    end

    if self.dragging then
        local dx = x - self.dragging.startX
        local dy = y - self.dragging.startY
        if dx * dx + dy * dy > 36 then
            self.dragging.moved = true
        end
        return
    end

    local foundIdx = nil
    local foundCatalogDef = nil
    local foundGridMod = nil
    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            foundIdx = i
            if r.action then
                if r.action.type == "catalogItem" then
                    foundCatalogDef = r.action.def
                elseif r.action.type == "gridModule" then
                    foundGridMod = r.action.mod
                end
            end
            break
        end
    end
    if foundIdx and foundIdx ~= self.hoveredRegionIndex then
        Sfx.play("ui_hover")
    end
    if not foundGridMod then
        foundGridMod = self:findPlacedModuleAt(activeInv, x, y)
    end
    self.hoveredRegionIndex = foundIdx
    self.hoveredCatalogDef = foundCatalogDef
    self.hoveredGridItem = foundGridMod
end

function ArmoryUI:mousepressed(inv, x, y, button)
    self.mouseX, self.mouseY = x, y
    local activeInv = self:activeInventory(inv)

    if self.exitModal then
        if button == 2 then
            self.exitModal = nil
            Sfx.play("ui_click")
            return activeInv, nil
        end
        if button == 1 then
            for i = #self.hitRegions, 1, -1 do
                local r = self.hitRegions[i]
                if pointInRect(x, y, r.x, r.y, r.w, r.h) and r.action then
                    if r.action.type == "modalStay" then
                        self.exitModal = nil
                        Sfx.play("ui_click")
                        return activeInv, nil
                    elseif r.action.type == "modalRevertExit" then
                        self.exitModal = nil
                        Sfx.play("ui_click")
                        return self.baselineInventory:clone(), "cancelExit"
                    end
                end
            end
        end
        return activeInv, nil
    end

    if button == 2 then
        if self:cancelDrag(activeInv) then
            Sfx.play("ui_click")
            self.statusMessage = "이동을 취소했습니다."
            return activeInv, nil
        end
        local targetMod = self:findPlacedModuleAt(activeInv, x, y)
        if not targetMod then
            for i = #self.hitRegions, 1, -1 do
                local r = self.hitRegions[i]
                if pointInRect(x, y, r.x, r.y, r.w, r.h) and r.action and r.action.type == "gridModule" then
                    targetMod = r.action.mod
                    break
                end
            end
        end
        if targetMod then
            activeInv:removeItem(targetMod, false)
            self.hoveredGridItem = nil
            self.hoveredRegionIndex = nil
            Sfx.play("ui_click")
            self.statusMessage = targetMod.def.name .. "을(를) 배치 해제했습니다."
            return activeInv, "changed"
        end
        return activeInv, nil
    end

    if button ~= 1 then return activeInv, nil end

    if self.dragging then
        return self:finishDrop(activeInv, x, y)
    end

    for i = #self.hitRegions, 1, -1 do
        local r = self.hitRegions[i]
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
            local a = r.action
            if a.type == "saveAndExit" then
                return self:tryExit(activeInv)
            elseif a.type == "resetStarter" then
                local resetInv = Inventory.newStarter({ chassisId = ChassisData.DEFAULT_ID })
                self.chassisDrafts[resetInv.chassisId] = resetInv
                self.chassisIndex = ChassisData.get(resetInv.chassisId).index or 1
                self.hoveredGridItem = nil
                Sfx.play("ui_equip")
                self.statusMessage = "기본 세팅으로 초기화했습니다."
                return resetInv, "changed"
            elseif a.type == "selectCategory" then
                self.activeCategory = a.category
                self.catalogScroll = 0
                Sfx.play("ui_click")
                return activeInv, nil
            elseif a.type == "switchChassis" then
                local nextInv = self:switchChassis(activeInv, a.dir)
                return nextInv, "chassisChanged"
            elseif a.type == "catalogItem" then
                if activeInv.chassis and activeInv.chassis.locked then
                    Sfx.play("ui_error")
                    self.statusMessage = "미해금 섀시에는 부품을 장착할 수 없습니다."
                    return activeInv, nil
                end
                self:startCatalogDrag(activeInv, a.def, x, y)
                return activeInv, nil
            elseif a.type == "gridModule" then
                self:startGridDrag(activeInv, a.mod, x, y)
                return activeInv, nil
            end
        end
    end

    local gridHitMod = self:findPlacedModuleAt(activeInv, x, y)
    if gridHitMod and not (self.exitModal) then
        local hitUiControl = false
        for i = #self.hitRegions, 1, -1 do
            local r = self.hitRegions[i]
            if pointInRect(x, y, r.x, r.y, r.w, r.h) and r.action and r.action.type ~= "gridModule" then
                hitUiControl = true
                break
            end
        end
        if not hitUiControl then
            self:startGridDrag(activeInv, gridHitMod, x, y)
            return activeInv, nil
        end
    end

    return activeInv, nil
end

function ArmoryUI:mousereleased(inv, x, y, button)
    self.mouseX, self.mouseY = x, y
    local activeInv = self:activeInventory(inv)
    if self.exitModal or button ~= 1 or not self.dragging then
        return activeInv, nil
    end
    local d = self.dragging
    if d.moved or d.rotated then
        return self:finishDrop(activeInv, x, y)
    end
    if d.origin == "catalog" then
        self.statusMessage = activeInv.rotationUnlocked
            and (d.item.def.name .. " 선택됨 — 그리드 위치를 클릭해 배치하세요. (R: 회전)")
            or (d.item.def.name .. " 선택됨 — 그리드 위치를 클릭해 배치하세요.")
        return activeInv, nil
    end
    self:cancelDrag(activeInv)
    return activeInv, nil
end

function ArmoryUI:wheelmoved(x, y, wx, wy)
    if self.exitModal or not self.catalogListRect then return end
    if pointInRect(self.mouseX, self.mouseY,
            self.catalogListRect.x, self.catalogListRect.y,
            self.catalogListRect.w, self.catalogListRect.h) then
        self.catalogScroll = Theme.clamp(self.catalogScroll - (wy or 0) * 44, 0, self.catalogMaxScroll)
    end
end

function ArmoryUI:keypressed(inv, key)
    local activeInv = self:activeInventory(inv)
    if self.exitModal then
        if key == "escape" or key == "return" or key == "kpenter" then
            self.exitModal = nil
            Sfx.play("ui_click")
        end
        return activeInv, nil
    end

    if key == "r" and self.dragging then
        if activeInv.rotationUnlocked then
            self.dragging.rotation = (self.dragging.rotation + 1) % 4
            self.dragging.rotated = true
            Sfx.play("ui_hover")
        end
        return activeInv, nil
    elseif key == "escape" then
        if self.dragging then
            self:cancelDrag(activeInv)
            Sfx.play("ui_click")
            return activeInv, nil
        end
        return self:tryExit(activeInv)
    end

    return activeInv, nil
end

return ArmoryUI
