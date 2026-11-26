-- Armored Core VI-inspired Holo-Glass Armory screen for assembling the player's ship.
-- Layout (1280x720 virtual canvas):
--   Left column:   MODULE LIST (category filter + flat catalog) & PART SPEC (AC6 key-value readout)
--   Center column: Chassis switcher + holographic ship silhouette & 5x3 triangle hardpoint grid
--   Right column:  SHIP SPEC (AC6 4-section tabular telemetry with live before/after delta bars,
--                  PEAK EN LOAD / TOTAL MASS meters, mandatory checks, and sortie status)

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

local MENU_FONT_PATH = "assets/fonts/DriftMenu.ttf"

local MODULE_CODES = {
    projectile = "WPN-01",
    missile    = "WPN-02",
    laser      = "WPN-03",
    shield     = "DEF-01",
    armor      = "DEF-02",
    thruster   = "THR-01",
    battery    = "GEN-01",
}

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

local function formatNum(val, decimals)
    local n = tonumber(val) or 0
    if math.abs(n) < 1e-6 then n = 0 end
    if decimals and decimals > 0 then
        return string.format("%." .. decimals .. "f", n)
    end
    if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
        return tostring(math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

local function formatStatValue(val, opts)
    opts = opts or {}
    local n = tonumber(val) or 0
    if math.abs(n) < 1e-6 then n = 0 end
    local numStr = formatNum(n, opts.decimals)
    if opts.signed and n > 0 then
        numStr = "+" .. numStr
    end
    return numStr .. (opts.unit or "")
end

local function getModuleCode(def)
    if not def then return "MOD-00" end
    if MODULE_CODES[def.id] then return MODULE_CODES[def.id] end
    local cat = ModulesData.categoryById[def.category]
    return (cat and cat.tag or "MOD") .. "-00"
end

-- Vector geometric primitives (avoids missing glyphs in DriftMenu.ttf)
local function drawDiamond(cx, cy, r)
    love.graphics.polygon("fill", cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy)
end

local function drawHollowDiamond(cx, cy, r)
    love.graphics.polygon("line", cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy)
end

local function drawDeltaTriangle(cx, cy, size, up)
    local g = love.graphics
    if up then
        g.polygon("fill", cx, cy - size * 0.72, cx + size * 0.72, cy + size * 0.52, cx - size * 0.72, cy + size * 0.52)
    else
        g.polygon("fill", cx, cy + size * 0.72, cx + size * 0.72, cy - size * 0.52, cx - size * 0.72, cy - size * 0.52)
    end
end

local function drawChevron(cx, cy, size, dir)
    local g = love.graphics
    local s = size
    if dir < 0 then
        g.line(cx + s * 0.4, cy - s * 0.75, cx - s * 0.45, cy, cx + s * 0.4, cy + s * 0.75)
    else
        g.line(cx - s * 0.4, cy - s * 0.75, cx + s * 0.45, cy, cx - s * 0.4, cy + s * 0.75)
    end
end

local function drawStatusMark(cx, cy, r, ok)
    local g = love.graphics
    if ok then
        g.circle("fill", cx, cy, r * 0.72)
    else
        g.setLineWidth(1.5)
        g.line(cx - r * 0.65, cy - r * 0.65, cx + r * 0.65, cy + r * 0.65)
        g.line(cx + r * 0.65, cy - r * 0.65, cx - r * 0.65, cy + r * 0.65)
    end
end

local function drawWarningTriangle(cx, cy, r)
    love.graphics.polygon("fill", cx, cy - r, cx + r * 0.95, cy + r * 0.75, cx - r * 0.95, cy + r * 0.75)
end

local function drawFootprint(rightX, centerY, itemOrDef, rotation, col, alpha)
    local g = love.graphics
    local cells, bw, bh = Inventory.getShapeCells(itemOrDef, rotation or 0)
    local cellSz, gap = 5, 1.5
    local step = cellSz + gap
    local totalW = bw * cellSz + math.max(0, bw - 1) * gap
    local totalH = bh * cellSz + math.max(0, bh - 1) * gap
    local x0 = rightX - totalW
    local y0 = centerY - totalH * 0.5
    g.setColor(col[1], col[2], col[3], (alpha or 0.9))
    for _, coord in ipairs(cells) do
        g.rectangle("fill", x0 + coord[2] * step, y0 + coord[1] * step, cellSz, cellSz, 1, 1)
    end
    return totalW
end

local function drawKeycap(x, y, w, h, label, font, alpha)
    local g = love.graphics
    local c = Theme.colors
    g.setColor(0.045, 0.105, 0.165, 0.65 * alpha)
    g.rectangle("fill", x, y, w, h, 2, 2)
    Theme.setColor(c.accent, 0.36 * alpha)
    g.setLineWidth(1)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 2, 2)
    g.setFont(font)
    Theme.setColor(c.textHero, 0.90 * alpha)
    local tw = font:getWidth(label)
    local th = font:getHeight()
    g.print(label, math.floor(x + (w - tw) * 0.5 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5))
end

local function drawGlassPlane(self, x, y, w, h, title, rightText, rightColor)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes

    if m and m.planeFill then
        Theme.drawGradientRect(m.planeFill, x, y, w, h, 1)
    else
        g.setColor(0.028, 0.062, 0.104, 0.62)
        g.rectangle("fill", x, y, w, h)
    end

    -- Hairline top & bottom edges (panel-less sides)
    Theme.setColor(c.accent, 0.30)
    g.setLineWidth(1)
    g.line(x, y + 0.5, x + w, y + 0.5)
    Theme.setColor(c.accent, 0.14)
    g.line(x, y + h - 0.5, x + w, y + h - 0.5)

    -- Precision corner ticks
    g.setLineWidth(2)
    Theme.setColor(c.accentBright, 0.92)
    g.line(x, y + 0.5, x + 7, y + 0.5)
    Theme.setColor(c.accentBright, 0.55)
    g.line(x + w - 7, y + 0.5, x + w, y + 0.5)

    -- Header bar (28px)
    local hdrH = 28
    if m and m.planeHdrWash then
        Theme.drawGradientRect(m.planeHdrWash, x, y + 1, w, hdrH - 1, 1)
    end
    Theme.setColor(c.accent, 0.16)
    g.setLineWidth(1)
    g.line(x, y + hdrH, x + w, y + hdrH)

    local fMicro = self.localFonts.micro10
    g.setFont(fMicro)
    Theme.setColor(c.accentBright, 0.94)
    g.print(title, x + 10, y + math.floor((hdrH - fMicro:getHeight()) * 0.5))
    if rightText and rightText ~= "" then
        if rightColor then
            g.setColor(rightColor[1], rightColor[2], rightColor[3], 0.92)
        else
            Theme.setColor(c.textMuted, 0.90)
        end
        g.printf(rightText, x + 10, y + math.floor((hdrH - fMicro:getHeight()) * 0.5), w - 20, "right")
    end
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

local function buildPartSpecRows(def, penaltyPct)
    if not def then return {} end
    local cat = def.category
    local s = def.stats or {}
    local rows = {}
    local mult = (penaltyPct and penaltyPct > 0) and (1 + penaltyPct / 100) or 1
    local penTag = (penaltyPct and penaltyPct > 0) and string.format(" (+%d%%)", penaltyPct) or ""

    if cat == "weapon" then
        local damage = def.damage or 0
        local shotCount = def.shotCount or 1
        local dmgStr = shotCount > 1
            and string.format("%s x %d발", formatNum(damage), shotCount)
            or string.format("%s (%d발)", formatNum(damage), shotCount)
        local interval = def.fireInterval or 0
        local rof = interval > 0 and (1 / interval) or 0
        local enCost = math.floor((def.baseBatteryCost or 0) * mult + 0.5)
        rows = {
            { k = "피해 / 발사수", v = dmgStr },
            { k = "발사 간격 / 공속", v = string.format("%.2f s  (%.1f /s)", interval, rof) },
            { k = "발사 EN 소비", v = tostring(enCost) .. penTag, warn = (penaltyPct or 0) > 0 and enCost > 0 },
            { k = "중량", v = string.format("%d t", def.weight or 0) },
            { k = "점유 격자 / 소켓", v = string.format("%dx%d  ·  %d 슬롯", def.w or 1, def.h or 1, def.maxSockets or 0) },
        }
    elseif cat == "defense" then
        if (s.maxShield or 0) > 0 then
            local drain = (s.shieldRegenBatteryCost or 0) * mult
            rows = {
                { k = "실드 내구도", v = string.format("+%d", s.maxShield) },
                { k = "실드 재생률", v = string.format("+%s /s  (지연 %ss)", formatNum(s.shieldRegen or 0), formatNum(s.shieldRegenDelay or 2)) },
                { k = "재생 EN 부하", v = formatNum(drain, (drain % 1 ~= 0) and 1 or 0) .. "/s" .. penTag, warn = (penaltyPct or 0) > 0 and drain > 0 },
                { k = "중량", v = string.format("%d t", def.weight or 0) },
                { k = "점유 격자 / 소켓", v = string.format("%dx%d  ·  %d 슬롯", def.w or 1, def.h or 1, def.maxSockets or 0) },
            }
        else
            rows = {
                { k = "장갑 내구도", v = string.format("+%d", s.maxArmor or 0) },
                { k = "지속 EN 부하", v = "0" },
                { k = "중량", v = string.format("%d t", def.weight or 0) },
                { k = "점유 격자 / 소켓", v = string.format("%dx%d  ·  %d 슬롯", def.w or 1, def.h or 1, def.maxSockets or 0) },
                { k = "중복 장착 특성", v = "페널티 없음" },
            }
        end
    elseif cat == "thruster" then
        local accelDrain = (s.thrustBatteryCost or 0) * mult
        local boostCost = math.floor((s.boostCost or 0) * mult + 0.5)
        rows = {
            { k = "순항 / 부스트 추력", v = string.format("+%d  /  +%d", s.thrust or 0, s.boostThrust or 0) },
            { k = "가속 EN 부하", v = formatNum(accelDrain, (accelDrain % 1 ~= 0) and 1 or 0) .. "/s" .. penTag, warn = (penaltyPct or 0) > 0 },
            { k = "부스트 소비 EN", v = tostring(boostCost) .. penTag, warn = (penaltyPct or 0) > 0 },
            { k = "워프 가속 보너스", v = string.format("+%d", s.wrapBonusSpeed or 0) },
            { k = "중량 / 격자", v = string.format("%d t  ·  %dx%d (소켓 %d)", def.weight or 0, def.w or 1, def.h or 1, def.maxSockets or 0) },
        }
    else
        rows = {
            { k = "EN 총 용량", v = string.format("+%d", s.maxBattery or 0) },
            { k = "EN 충전 출력", v = string.format("+%s /s", formatNum(s.batteryRecharge or 0)) },
            { k = "중량", v = string.format("%d t", def.weight or 0) },
            { k = "점유 격자 / 소켓", v = string.format("%dx%d  ·  %d 슬롯", def.w or 1, def.h or 1, def.maxSockets or 0) },
            { k = "중복 장착 특성", v = "페널티 없음" },
        }
    end
    return rows
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

        g.setColor(0.028 + col[1] * 0.13, 0.052 + col[2] * 0.13, 0.088 + col[3] * 0.13, 0.88 * alpha)
        g.rectangle("fill", cx, cy, cw, ch, 3, 3)
    end

    local totalW = bw * cellSize + (bw - 1) * gap
    local totalH = bh * cellSize + (bh - 1) * gap
    if img then
        local pad = 4
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

    -- Hover glow halo + crisp rarity outline
    if isHovered or isDragging then
        g.setColor(col[1], col[2], col[3], 0.18 * alpha)
        g.rectangle("fill", originX + 1.5, originY + 1.5, totalW - 3, totalH - 3, 3, 3)
    end
    g.setColor(col[1], col[2], col[3], (isDragging and 0.98 or (isHovered and 0.96 or 0.78)) * alpha)
    g.setLineWidth(isDragging and 2.2 or (isHovered and 1.8 or 1.2))
    g.rectangle("line", originX + 1.5, originY + 1.5, totalW - 3, totalH - 3, 3, 3)

    -- Hollow socket diamonds in top-right corner
    local sockCount = mod.maxSockets or def.maxSockets or 0
    if sockCount > 0 then
        g.setLineWidth(1)
        for sIdx = 1, sockCount do
            local sx = originX + totalW - 7 - (sIdx - 1) * 8
            local sy = originY + 7
            g.setColor(0.03, 0.07, 0.12, 0.85 * alpha)
            drawDiamond(sx, sy, 2.8)
            g.setColor(col[1], col[2], col[3], 0.92 * alpha)
            drawHollowDiamond(sx, sy, 2.8)
        end
    end
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
        specMode = "full",
        localFonts = nil,
        localFontScale = nil,
        meshes = nil,
        simCache = nil,
    }, ArmoryUI)
end

function ArmoryUI:_ensureFonts(fallbackFonts)
    local scale = math.max(1, Display.fontDpiScale())
    if self.localFonts and self.localFontScale == scale then
        return self.localFonts
    end
    self.localFontScale = scale
    local function mk(size, fb)
        local ok, f = pcall(love.graphics.newFont, MENU_FONT_PATH, size, "normal", scale)
        if ok and f then return f end
        return fb
    end
    local fb = fallbackFonts or {}
    self.localFonts = {
        micro10 = mk(10, fb.titleMicro or fb.menuSmall),
        spec12  = mk(12, fb.menuSmall or fb.menuBody),
        row13   = mk(13, fb.menuBody or fb.menuSmall),
        title21 = mk(21, fb.titlePrimary or fb.menuTitle),
    }
    return self.localFonts
end

function ArmoryUI:_ensureMeshes()
    if self.meshes then return self.meshes end
    local deep = Theme.colors.bgDeep
    local acc = Theme.colors.accent
    local bright = Theme.colors.accentBright
    local danger = Theme.colors.danger
    self.meshes = {
        leftScrim = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.84 },
            { pos = 0.60, deep[1], deep[2], deep[3], 0.56 },
            { pos = 1.00, deep[1], deep[2], deep[3], 0.00 },
        }, true),
        rightScrim = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.00 },
            { pos = 0.36, deep[1], deep[2], deep[3], 0.58 },
            { pos = 1.00, deep[1], deep[2], deep[3], 0.86 },
        }, true),
        centerHalo = Theme.createRadialGradientMesh(acc[1], acc[2], acc[3], 0.16, nil, 40),
        planeFill = Theme.createGradientMesh({
            { pos = 0.00, 0.032, 0.070, 0.118, 0.66 },
            { pos = 1.00, 0.018, 0.042, 0.076, 0.48 },
        }, false),
        planeHdrWash = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.14 },
            { pos = 0.85, acc[1], acc[2], acc[3], 0.00 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.00 },
        }, true),
        rowWash = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.18 },
            { pos = 0.85, acc[1], acc[2], acc[3], 0.02 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.00 },
        }, true),
        fadingRule = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.00 },
            { pos = 0.10, acc[1], acc[2], acc[3], 0.24 },
            { pos = 0.90, acc[1], acc[2], acc[3], 0.24 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.00 },
        }, true),
        sortieWash = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.34 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.10 },
        }, true),
        dangerWash = Theme.createGradientMesh({
            { pos = 0.00, danger[1], danger[2], danger[3], 0.38 },
            { pos = 1.00, danger[1], danger[2], danger[3], 0.10 },
        }, true),
    }
    return self.meshes
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
    self.simCache = nil
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
    self.simCache = nil
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

function ArmoryUI:_buildCatalogModules()
    if self.activeCategory == "all" then
        return ModulesData.list
    end
    return ModulesData.getByCategory(self.activeCategory)
end

function ArmoryUI:_extractMetrics(inv, build, extraDef, removeMod)
    local weaponCount = 0
    local fireRate = 0
    local totalSockets = 0
    local usedCells = 0

    for _, mod in ipairs(inv.placed or {}) do
        if mod ~= removeMod and mod.def then
            local cells = Inventory.getShapeCells(mod, mod.rotation)
            usedCells = usedCells + #cells
            totalSockets = totalSockets + (mod.maxSockets or mod.def.maxSockets or 0)
            if Inventory.isWeaponModule(mod) and not mod.disabled then
                weaponCount = weaponCount + 1
                local iv = mod.def.fireInterval or 0
                if iv > 0 then fireRate = fireRate + 1 / iv end
            end
        end
    end
    if extraDef then
        local cells = Inventory.getShapeCells(extraDef, 0)
        usedCells = usedCells + #cells
        totalSockets = totalSockets + (extraDef.maxSockets or 0)
        if extraDef.category == "weapon" then
            weaponCount = weaponCount + 1
            local iv = extraDef.fireInterval or 0
            if iv > 0 then fireRate = fireRate + 1 / iv end
        end
    end

    local continuousDrain = (build.thrustBatteryCost or 0) + (build.shieldRegenBatteryCost or 0)
    local recharge = build.batteryRecharge or 0
    return {
        maxHull = build.maxHull or 0,
        maxArmor = build.maxArmor or 0,
        maxShield = build.maxShield or 0,
        shieldRegen = build.shieldRegen or 0,
        weaponCount = weaponCount,
        fireRate = fireRate,
        maxWeaponBatteryCost = build.maxWeaponBatteryCost or 0,
        totalSockets = totalSockets,
        maxSpeed = build.maxSpeed or 0,
        boostSpeed = build.boostSpeed or 0,
        thrust = build.thrust or 0,
        wrapBonusSpeed = build.wrapBonusSpeed or 0,
        maxBattery = build.maxBattery or 0,
        batteryRecharge = recharge,
        boostCost = build.boostCost or 0,
        continuousDrain = continuousDrain,
        netSupply = recharge - continuousDrain,
        peakCost = build.maxSingleActionBatteryCost or 0,
        totalWeight = build.totalWeight or 0,
        usedCells = usedCells,
        totalCells = inv:maxCellCount(),
    }
end

function ArmoryUI:_computeCompareMetrics(activeInv)
    local ch = activeInv.chassis or ChassisData.get(activeInv.chassisId)
    if ch and ch.locked then return nil end

    local simMode, simTarget = nil, nil
    if self.dragging then
        if self.dragging.origin == "catalog" and self.dragging.item and self.dragging.item.def then
            simMode = "add"
            simTarget = self.dragging.item.def
        end
    elseif self.hoveredCatalogDef then
        simMode = "add"
        simTarget = self.hoveredCatalogDef
    elseif self.hoveredGridItem then
        simMode = "rem"
        simTarget = self.hoveredGridItem
    end

    if not simMode or not simTarget then
        return nil
    end

    local sigParts = { tostring(activeInv.chassisId or "") }
    for _, mod in ipairs(activeInv.placed or {}) do
        sigParts[#sigParts + 1] = tostring(mod.id) .. ":" .. tostring(mod.defId) .. ":" .. (mod.disabled and "1" or "0")
    end
    local simKey = simMode .. ":" .. tostring(simMode == "add" and simTarget.id or simTarget.id)
    local fullKey = table.concat(sigParts, ";") .. "|" .. simKey

    if self.simCache and self.simCache.key == fullKey then
        return self.simCache.metrics
    end

    local simInv = activeInv:clone()
    if simMode == "add" then
        local added = simInv:createModule(simTarget.id)
        simInv.placed[#simInv.placed + 1] = added
    else
        for i = #simInv.placed, 1, -1 do
            local m = simInv.placed[i]
            if m.defId == simTarget.defId and m.row == simTarget.row and m.col == simTarget.col then
                table.remove(simInv.placed, i)
                break
            end
        end
    end
    local simBuild = simInv:computeBuild(false)
    local metrics = self:_extractMetrics(simInv, simBuild)
    self.simCache = { key = fullKey, metrics = metrics }
    return metrics
end

function ArmoryUI:_drawHeader(fonts, width, isValid)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local fMicro = self.localFonts.micro10
    local fTitle = self.localFonts.title21
    local fSpec = self.localFonts.spec12

    -- Eyebrow + Title
    Theme.setColor(c.accentBright, 0.88)
    drawDiamond(28, 20, 2.8)
    g.setFont(fMicro)
    g.print("ASSEMBLY // ARMORY", 37, 14)

    g.setFont(fTitle)
    Theme.setColor(c.textHero, 0.98)
    g.print("기체 조립", 24, 26)

    -- Bottom header hairline
    Theme.setColor(c.accent, 0.22)
    g.setLineWidth(1)
    g.line(24, 55.5, width - 24, 55.5)

    -- Reset to Starter ghost holo button
    local resetW, resetH = 104, 32
    local exitW, exitH = 168, 32
    local exitX, exitY = width - 24 - exitW, 14
    local resetX, resetY = exitX - 10 - resetW, 14
    local hoverReset = (not self.exitModal) and pointInRect(self.mouseX, self.mouseY, resetX, resetY, resetW, resetH)

    g.setColor(hoverReset and 0.08 or 0.03, hoverReset and 0.22 or 0.08, hoverReset and 0.28 or 0.14, hoverReset and 0.62 or 0.44)
    g.rectangle("fill", resetX, resetY, resetW, resetH)
    Theme.setColor(hoverReset and c.accentBright or c.accent, hoverReset and 0.85 or 0.30)
    g.setLineWidth(1)
    g.rectangle("line", resetX + 0.5, resetY + 0.5, resetW - 1, resetH - 1)
    g.setFont(fSpec)
    Theme.setColor(hoverReset and c.textHero or c.textPrimary, 0.96)
    g.printf("기본 세팅", resetX, resetY + math.floor((resetH - fSpec:getHeight()) * 0.5), resetW, "center")
    self:addRegion(resetX, resetY, resetW, resetH, { type = "resetStarter" })

    -- Save & Exit CTA button
    local hoverExit = (not self.exitModal) and pointInRect(self.mouseX, self.mouseY, exitX, exitY, exitW, exitH)
    if isValid then
        if m and m.sortieWash then
            Theme.drawGradientRect(m.sortieWash, exitX, exitY, exitW, exitH, hoverExit and 1.25 or 0.90)
        end
        Theme.setColor(hoverExit and c.accentBright or c.accent, hoverExit and 0.98 or 0.72)
        g.setLineWidth(1)
        g.rectangle("line", exitX + 0.5, exitY + 0.5, exitW - 1, exitH - 1)
        Theme.setColor(c.accentBright, 0.98)
        g.rectangle("fill", exitX, exitY, 3, exitH)
    else
        if m and m.dangerWash then
            Theme.drawGradientRect(m.dangerWash, exitX, exitY, exitW, exitH, hoverExit and 1.25 or 0.95)
        end
        Theme.setColor(c.dangerBright, hoverExit and 0.98 or 0.78)
        g.setLineWidth(1)
        g.rectangle("line", exitX + 0.5, exitY + 0.5, exitW - 1, exitH - 1)
        Theme.setColor(c.dangerBright, 0.98)
        g.rectangle("fill", exitX, exitY, 3, exitH)
    end
    g.setFont(fSpec)
    Theme.setColor(isValid and c.textHero or c.dangerSelectedText, 1)
    local exitLabel = isValid and "저장 후 나가기" or "출격 불가"
    g.printf(exitLabel, exitX + 4, exitY + math.floor((exitH - fSpec:getHeight()) * 0.5), exitW - 4, "center")
    self:addRegion(exitX, exitY, exitW, exitH, { type = "saveAndExit" })
end

function ArmoryUI:_drawCatalogPanel(inv)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local fMicro = self.localFonts.micro10
    local fSpec = self.localFonts.spec12
    local fRow = self.localFonts.row13

    local px, py, pw, ph = 24, 66, 344, 398
    local defs = self:_buildCatalogModules()

    drawGlassPlane(self, px, py, pw, ph, "MODULE LIST", string.format("%d UNITS", #defs))

    -- 5 Category tabs (underline style)
    local tabs = {
        { id = "all", name = "전체" },
        { id = "weapon", name = "무기" },
        { id = "defense", name = "방호" },
        { id = "thruster", name = "추진" },
        { id = "generator", name = "동력" },
    }
    local tabY, tabH = py + 28, 28
    local tabW = math.floor((pw - 12) / #tabs)
    local tabX0 = px + 6
    Theme.setColor(c.accent, 0.16)
    g.setLineWidth(1)
    g.line(px, tabY + tabH, px + pw, tabY + tabH)

    for i, tab in ipairs(tabs) do
        local tx = tabX0 + (i - 1) * tabW
        local active = (self.activeCategory == tab.id)
        local hovered = (not self.exitModal) and pointInRect(self.mouseX, self.mouseY, tx, tabY, tabW, tabH)
        g.setFont(fSpec)
        if active then
            Theme.setColor(c.textHero, 1)
        elseif hovered then
            Theme.setColor(c.textPrimary, 0.92)
        else
            Theme.setColor(c.textMuted, 0.85)
        end
        g.printf(tab.name, tx, tabY + math.floor((tabH - fSpec:getHeight()) * 0.5), tabW, "center")
        if active then
            Theme.setColor(c.accentBright, 0.96)
            g.rectangle("fill", tx + 8, tabY + tabH - 2, tabW - 16, 2)
        end
        self:addRegion(tx, tabY, tabW, tabH, { type = "selectCategory", category = tab.id })
    end

    -- Count equipped per defId
    local eqCounts = {}
    for _, placedMod in ipairs(inv.placed or {}) do
        eqCounts[placedMod.defId] = (eqCounts[placedMod.defId] or 0) + 1
    end

    -- Flat module list (all 7 visible at once without vertical scroll)
    local listX, listY = px, tabY + tabH + 4
    local listW, listH = pw, (py + ph - 4) - listY
    self.catalogListRect = { x = listX, y = listY, w = listW, h = listH }

    local rowH = 44
    local rowStep = 46
    local totalH = #defs * rowStep
    self.catalogMaxScroll = math.max(0, totalH - listH)
    self.catalogScroll = Theme.clamp(self.catalogScroll, 0, self.catalogMaxScroll)

    g.push("all")
    local sx, sy, sw, sh = Display.virtualRectToWindow(listX, listY, listW, listH)
    g.intersectScissor(sx, sy, sw, sh)

    local drawY = listY - self.catalogScroll
    for _, def in ipairs(defs) do
        if drawY + rowH >= listY and drawY <= listY + listH then
            local rc = Rarity.getColor(def.rarity)
            local inList = pointInRect(self.mouseX, self.mouseY, listX, listY, listW, listH)
            local isHovered = (not self.exitModal) and inList and pointInRect(self.mouseX, self.mouseY, listX, drawY, listW, rowH)
            local isDraggedDef = self.dragging and self.dragging.item and self.dragging.item.defId == def.id

            if isHovered or isDraggedDef then
                if m and m.rowWash then
                    Theme.drawGradientRect(m.rowWash, listX, drawY, listW, rowH, 1.0)
                end
                g.setColor(rc[1], rc[2], rc[3], 0.95)
                g.rectangle("fill", listX, drawY + 2, 2.5, rowH - 4)
            else
                g.setColor(rc[1], rc[2], rc[3], 0.14)
                g.rectangle("fill", listX, drawY + 6, 1.5, rowH - 12)
            end

            -- Faint hairline separator
            Theme.setColor(c.accent, 0.07)
            g.setLineWidth(1)
            g.line(listX + 10, drawY + rowH + 0.5, listX + listW - 10, drawY + rowH + 0.5)

            -- Sprite
            local img = getDefImage(def)
            local iconBox = 32
            local ix, iy = listX + 12, drawY + math.floor((rowH - iconBox) * 0.5)
            if img then
                local iw, ih = img:getDimensions()
                local sc = math.min(iconBox / iw, iconBox / ih)
                g.setColor(1, 1, 1, 0.98)
                g.draw(img, ix + iconBox * 0.5, iy + iconBox * 0.5, 0, sc, sc, iw * 0.5, ih * 0.5)
            end

            -- Rarity diamond + Name + Equipped count tag
            local nameX = ix + iconBox + 10
            g.setColor(rc[1], rc[2], rc[3], 0.95)
            drawDiamond(nameX + 3, drawY + rowH * 0.5, 2.6)

            g.setFont(fRow)
            Theme.setColor((isHovered or isDraggedDef) and c.textHero or c.textPrimary, 0.96)
            local textY = drawY + math.floor((rowH - fRow:getHeight()) * 0.5)
            g.print(def.name, nameX + 11, textY)

            local eq = eqCounts[def.id] or 0
            if eq > 0 then
                local tagX = nameX + 11 + fRow:getWidth(def.name) + 7
                local tagStr = "x" .. eq
                g.setFont(fMicro)
                local tagW = math.max(20, fMicro:getWidth(tagStr) + 8)
                local tagY = drawY + math.floor((rowH - 16) * 0.5)
                g.setColor(0.08, 0.25, 0.30, 0.45)
                g.rectangle("fill", tagX, tagY, tagW, 16)
                Theme.setColor(c.accentBright, 0.50)
                g.setLineWidth(1)
                g.rectangle("line", tagX + 0.5, tagY + 0.5, tagW - 1, 15)
                Theme.setColor(c.accentBright, 0.95)
                g.printf(tagStr, tagX, tagY + math.floor((16 - fMicro:getHeight()) * 0.5), tagW, "center")
            end

            -- Right side: mini footprint + weight
            g.setFont(fMicro)
            Theme.setColor(c.textMuted, 0.92)
            local wtText = string.format("%dt", def.weight or 0)
            g.printf(wtText, listX + listW - 44, drawY + math.floor((rowH - fMicro:getHeight()) * 0.5), 34, "right")
            drawFootprint(listX + listW - 48, drawY + rowH * 0.5, def, 0, rc, 0.90)

            local visTop = math.max(listY, drawY)
            local visBot = math.min(drawY + rowH, listY + listH)
            if visBot > visTop then
                self:addRegion(listX, visTop, listW, visBot - visTop, { type = "catalogItem", def = def })
            end
        end
        drawY = drawY + rowStep
    end
    g.pop()

    if self.catalogMaxScroll > 0 then
        local trackX = px + pw - 5
        local trackH = listH
        local thumbH = math.max(24, trackH * (listH / totalH))
        local thumbY = listY + (trackH - thumbH) * (self.catalogScroll / self.catalogMaxScroll)
        g.setColor(0.10, 0.20, 0.28, 0.45)
        g.rectangle("fill", trackX, listY, 3, trackH)
        Theme.setColor(c.accent, 0.72)
        g.rectangle("fill", trackX, thumbY, 3, thumbH)
    end
end

function ArmoryUI:_drawPartSpecPanel(inv, validationSummary)
    local g = love.graphics
    local c = Theme.colors
    local fMicro = self.localFonts.micro10
    local fSpec = self.localFonts.spec12
    local fRow = self.localFonts.row13

    local px, py, pw, ph = 24, 474, 344, 206

    local inspectItem = (self.dragging and self.dragging.item) or self.hoveredGridItem
    local inspectDef = (inspectItem and inspectItem.def) or self.hoveredCatalogDef
    if not inspectDef then
        if inv.placed and inv.placed[1] and inv.placed[1].def then
            inspectItem = inv.placed[1]
            inspectDef = inv.placed[1].def
        else
            inspectDef = ModulesData.list[1]
        end
    end

    local rarity = (inspectItem and inspectItem.rarity) or (inspectDef and inspectDef.rarity) or "NORMAL"
    local rc = Rarity.getColor(rarity)
    local rarityLabel = Rarity.getLabel(rarity)
    local code = getModuleCode(inspectDef)

    drawGlassPlane(self, px, py, pw, ph, "PART SPEC", string.format("[%s] %s", rarityLabel, code), rc)

    if not inspectDef then return end

    -- Top identity band (48px)
    local headY = py + 32
    local artSize = 40
    local ax, ay = px + 10, headY + 4
    g.setColor(0.02, 0.045, 0.08, 0.72)
    g.rectangle("fill", ax, ay, artSize, artSize)
    Theme.setColor(c.accent, 0.22)
    g.setLineWidth(1)
    g.rectangle("line", ax + 0.5, ay + 0.5, artSize - 1, artSize - 1)
    g.setColor(rc[1], rc[2], rc[3], 0.92)
    g.rectangle("fill", ax, ay, 2.5, artSize)

    local img = getDefImage(inspectDef)
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min((artSize - 8) / iw, (artSize - 8) / ih)
        g.setColor(1, 1, 1, 0.98)
        g.draw(img, ax + artSize * 0.5, ay + artSize * 0.5, 0, sc, sc, iw * 0.5, ih * 0.5)
    end

    local tx = ax + artSize + 12
    g.setFont(fRow)
    Theme.setColor(c.textHero, 0.98)
    g.print(inspectDef.name, tx, ay + 2)

    local catInfo = ModulesData.categoryById[inspectDef.category]
    local tag = catInfo and catInfo.tag or "MOD"
    g.setFont(fMicro)
    Theme.setColor(c.textMuted, 0.92)
    g.print(tag, tx, ay + 22)

    local sockStartX = tx + fMicro:getWidth(tag) + 12
    local sockY = ay + 22 + fMicro:getHeight() * 0.5
    local sockCount = inspectDef.maxSockets or 0
    g.setColor(rc[1], rc[2], rc[3], 0.90)
    g.setLineWidth(1.1)
    for i = 1, sockCount do
        drawHollowDiamond(sockStartX + (i - 1) * 9, sockY, 2.8)
    end

    local rot = inspectItem and inspectItem.rotation or 0
    drawFootprint(px + pw - 12, ay + artSize * 0.5, inspectItem or inspectDef, rot, rc, 0.92)

    -- Divider hairline
    Theme.setColor(c.accent, 0.14)
    g.setLineWidth(1)
    g.line(px + 10, headY + 50.5, px + pw - 10, headY + 50.5)

    -- Duplicate category surcharge check for equipped module
    local penaltyPct = 0
    if inspectItem and inspectItem.row and validationSummary and validationSummary.categoryPenalties then
        local catKey = inspectDef.category == "battery" and "generator" or inspectDef.category
        local pen = validationSummary.categoryPenalties[catKey]
        if pen and (pen.addPct or 0) > 0 then
            penaltyPct = pen.addPct
        end
    end

    -- 5 AC6 Key-Value Spec Rows
    local specRows = buildPartSpecRows(inspectDef, penaltyPct)
    local rowY = headY + 56
    local rowH = 22
    g.setFont(fSpec)
    for idx, row in ipairs(specRows) do
        Theme.setColor(c.textMuted, 0.92)
        g.print(row.k, px + 10, rowY + 3)

        if row.warn then
            g.setColor(1.0, 0.80, 0.34, 0.98)
        else
            Theme.setColor(c.textHero, 0.96)
        end
        g.printf(row.v, px + 10, rowY + 3, pw - 20, "right")

        if idx < #specRows then
            g.setColor(1, 1, 1, 0.045)
            g.setLineWidth(1)
            g.line(px + 10, rowY + rowH - 0.5, px + pw - 10, rowY + rowH - 0.5)
        end
        rowY = rowY + rowH
    end
end

function ArmoryUI:_drawCenterHangar(inv)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local fMicro = self.localFonts.micro10
    local fRow = self.localFonts.row13

    local px, py, pw = 388, 66, 456
    local ch = inv.chassis or ChassisData.get(inv.chassisId)

    -- 1. Chassis Switcher Header (y = 66..104)
    local barH = 38
    if m and m.planeFill then
        Theme.drawGradientRect(m.planeFill, px, py, pw, barH, 0.72)
    end
    Theme.setColor(c.accent, 0.28)
    g.setLineWidth(1)
    g.line(px, py + 0.5, px + pw, py + 0.5)
    Theme.setColor(c.accent, 0.16)
    g.line(px, py + barH - 0.5, px + pw, py + barH - 0.5)

    local navW, navH = 28, 24
    local prevX, nextX = px + 8, px + pw - 8 - navW
    local navY = py + math.floor((barH - navH) * 0.5)
    for _, nav in ipairs({ { x = prevX, dir = -1 }, { x = nextX, dir = 1 } }) do
        local hover = (not self.exitModal) and pointInRect(self.mouseX, self.mouseY, nav.x, navY, navW, navH)
        if hover then
            Theme.setColor(c.accent, 0.22)
            g.rectangle("fill", nav.x, navY, navW, navH)
        end
        Theme.setColor(hover and c.accentBright or c.accent, hover and 0.90 or 0.30)
        g.setLineWidth(1)
        g.rectangle("line", nav.x + 0.5, navY + 0.5, navW - 1, navH - 1)
        Theme.setColor(hover and c.textHero or c.accentBright, 0.95)
        g.setLineWidth(1.5)
        drawChevron(nav.x + navW * 0.5, navY + navH * 0.5, 5, nav.dir)
        self:addRegion(nav.x, navY, navW, navH, { type = "switchChassis", dir = nav.dir })
    end

    -- Centered chassis code + name + index
    local codeStr = ch.code or "STR-01"
    local nameStr = ch.name or ""
    local idxStr = string.format("%02d/%02d", self.chassisIndex, #ChassisData.list)
    g.setFont(fMicro)
    local cw = fMicro:getWidth(codeStr)
    local iw = fMicro:getWidth(idxStr)
    g.setFont(fRow)
    local nw = fRow:getWidth(nameStr)
    local gapText = 10
    local totalTitleW = cw + gapText + nw + gapText + iw
    local tx = math.floor(px + (pw - totalTitleW) * 0.5)

    g.setFont(fMicro)
    Theme.setColor(c.accentBright, 0.95)
    g.print(codeStr, tx, py + math.floor((barH - fMicro:getHeight()) * 0.5))

    g.setFont(fRow)
    Theme.setColor(ch.locked and c.textMuted or c.textHero, 0.98)
    g.print(nameStr, tx + cw + gapText, py + math.floor((barH - fRow:getHeight()) * 0.5))

    g.setFont(fMicro)
    Theme.setColor(c.textMuted, 0.86)
    g.print(idxStr, tx + cw + gapText + nw + gapText, py + math.floor((barH - fMicro:getHeight()) * 0.5))

    -- 2. Holographic Hangar Stage (y = 108..680)
    local shipCx = px + pw * 0.5
    local shipCy = 392

    -- Subtle radial halo behind ship
    if m and m.centerHalo then
        Theme.drawRadialHalo(m.centerHalo, shipCx, shipCy, 220, 210, 0.85)
    end

    -- Concentric hairline calibration rings (HUD-matched)
    g.setLineWidth(1)
    Theme.setColor(c.accent, 0.14)
    local ringSegs = 60
    for i = 0, ringSegs - 1 do
        local a0 = (i / ringSegs) * math.pi * 2
        local a1 = a0 + (math.pi * 2 / ringSegs) * 0.35
        g.arc("line", "open", shipCx, shipCy, 184, a0, a1)
    end
    Theme.setColor(c.accent, 0.10)
    g.circle("line", shipCx, shipCy, 158)
    Theme.setColor(c.accentBright, 0.40)
    g.line(shipCx, shipCy - 196, shipCx, shipCy - 186)
    g.line(shipCx - 196, shipCy, shipCx - 186, shipCy)
    g.line(shipCx + 186, shipCy, shipCx + 196, shipCy)

    Ship.drawChassis(ch.id, shipCx, shipCy + 14, 0, 6.4, self.time, { locked = ch.locked })

    if ch.locked then
        self.gridRect = nil
        local bw, bh = 250, 38
        local bx, by = math.floor(shipCx - bw * 0.5), math.floor(shipCy - bh * 0.5)
        g.setColor(0.02, 0.045, 0.085, 0.84)
        g.rectangle("fill", bx, by, bw, bh)
        Theme.setColor(c.accent, 0.45)
        g.setLineWidth(1)
        g.line(bx, by + 0.5, bx + bw, by + 0.5)
        Theme.setColor(c.accent, 0.24)
        g.line(bx, by + bh - 0.5, bx + bw, by + bh - 0.5)
        g.setFont(fSpec or self.localFonts.spec12)
        Theme.setColor(c.accentBright, 0.95)
        g.printf("LOCKED // ???", bx, by + math.floor((bh - self.localFonts.spec12:getHeight()) * 0.5), bw, "center")
        return
    end

    -- 5x3 Triangle Hardpoint Grid
    local cellSize = 64
    local gap = 8
    local step = cellSize + gap
    local gridW = inv.cols * cellSize + (inv.cols - 1) * gap
    local gridH = inv.rows * cellSize + (inv.rows - 1) * gap
    local gx = math.floor(shipCx - gridW * 0.5)
    local gy = math.floor(shipCy - gridH * 0.5)
    self.gridRect = {
        x = gx, y = gy, w = gridW, h = gridH,
        cellSize = cellSize, gap = gap, rows = inv.rows, cols = inv.cols,
    }

    local rowTags = { "A", "B", "C", "D", "E" }
    g.setFont(fMicro)
    for r = 1, inv.rows do
        for cIdx = 1, inv.cols do
            if inv:isValidCell(r, cIdx) then
                local cx = gx + (cIdx - 1) * step
                local cy = gy + (r - 1) * step
                local hoveredCell = (not self.exitModal) and (not self.dragging) and pointInRect(self.mouseX, self.mouseY, cx, cy, cellSize, cellSize)

                g.setColor(0.035, 0.105, 0.17, hoveredCell and 0.56 or 0.36)
                g.rectangle("fill", cx, cy, cellSize, cellSize, 2, 2)
                Theme.setColor(hoveredCell and c.accentBright or c.accent, hoveredCell and 0.72 or 0.38)
                g.setLineWidth(1)
                g.rectangle("line", cx + 0.5, cy + 0.5, cellSize - 1, cellSize - 1, 2, 2)

                -- Top-left & bottom-right L-ticks
                Theme.setColor(c.accentBright, 0.88)
                g.setLineWidth(1.5)
                g.line(cx, cy + 5, cx, cy, cx + 5, cy)
                g.line(cx + cellSize - 5, cy + cellSize, cx + cellSize, cy + cellSize, cx + cellSize, cy + cellSize - 5)

                -- Subtle coordinate tag
                Theme.setColor(c.accentBright, 0.34)
                local coordStr = (rowTags[r] or tostring(r)) .. tostring(cIdx)
                g.print(coordStr, cx + 4, cy + cellSize - fMicro:getHeight() - 2)
            end
        end
    end

    -- Ghost at original cell while dragging from grid
    if self.dragging and self.dragging.origin == "grid" and self.dragging.origRow then
        local origCells = Inventory.getShapeCells(self.dragging.item, self.dragging.origRotation)
        for _, coord in ipairs(origCells) do
            local cx = gx + (self.dragging.origCol + coord[2] - 1) * step + 3
            local cy = gy + (self.dragging.origRow + coord[1] - 1) * step + 3
            g.setColor(0.65, 0.88, 1.0, 0.14)
            g.rectangle("fill", cx, cy, cellSize - 6, cellSize - 6, 2, 2)
            g.setColor(0.65, 0.88, 1.0, 0.45)
            g.setLineWidth(1)
            g.rectangle("line", cx, cy, cellSize - 6, cellSize - 6, 2, 2)
        end
    end

    -- Placed modules
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
                        g.setColor(0.32, 0.96, 0.68, 0.30)
                        g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 2, 2)
                        g.setColor(0.42, 1.0, 0.74, 0.96)
                        g.setLineWidth(2.0)
                        g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 2, 2)
                    else
                        g.setColor(1.0, 0.28, 0.32, 0.30)
                        g.rectangle("fill", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 2, 2)
                        g.setColor(1.0, 0.38, 0.42, 0.96)
                        g.setLineWidth(2.0)
                        g.rectangle("line", cx + 2, cy + 2, cellSize - 4, cellSize - 4, 2, 2)
                    end
                end
            end
        end
    end
end

function ArmoryUI:_drawACStatRow(x, y, w, rowH, label, curVal, simVal, maxScale, opts)
    local g = love.graphics
    local c = Theme.colors
    opts = opts or {}
    local fSpec = self.localFonts.spec12
    local hasSim = (simVal ~= nil)
    local diff = hasSim and (simVal - curVal) or 0
    local changed = hasSim and math.abs(diff) > 0.05
    local improved = changed and (opts.lowerBetter and (diff < 0) or (diff > 0)) or false

    if changed then
        g.setColor(0.24, 0.76, 0.96, 0.07)
        g.rectangle("fill", x, y, w, rowH)
    end

    local textAlpha = (hasSim and not changed) and 0.48 or 0.96
    local textY = y + math.floor((rowH - fSpec:getHeight()) * 0.5)

    -- Col 1: Label (x .. x+118)
    g.setFont(fSpec)
    Theme.setColor(c.textSecondary, textAlpha)
    g.print(label, x, textY)

    -- Col 2: Micro Comparative Gauge (x+122 .. x+210, w=88)
    local barX, barW = x + 122, 88
    local barY = y + math.floor(rowH * 0.5) - 1
    g.setColor(0.45, 0.68, 0.78, hasSim and not changed and 0.08 or 0.15)
    g.rectangle("fill", barX, barY, barW, 3)

    local pCur = Theme.clamp(math.max(0, curVal) / math.max(1, maxScale), 0, 1)
    local pSim = hasSim and Theme.clamp(math.max(0, simVal) / math.max(1, maxScale), 0, 1) or pCur
    local pMin = math.min(pCur, pSim)
    if pMin > 0 then
        g.setColor(0.84, 0.94, 0.98, hasSim and not changed and 0.36 or 0.76)
        g.rectangle("fill", barX, barY, barW * pMin, 3)
    end
    if changed then
        local segStart = barX + barW * pMin
        local segW = math.max(2, barW * math.abs(pSim - pCur))
        if improved then
            g.setColor(0.35, 0.85, 1.0, 0.98)
        else
            g.setColor(1.0, 0.39, 0.39, 0.98)
        end
        g.rectangle("fill", segStart, barY, segW, 3)
    end

    -- Col 3: Current Value (x+214 .. x+274, w=60)
    Theme.setColor(c.textHero, textAlpha)
    g.printf(formatStatValue(curVal, opts), x + 214, textY, 60, "right")

    -- Col 4: Simulated Value + Triangle (x+278 .. x+372, w=94)
    if hasSim then
        local simX = x + 278
        local simStr = formatStatValue(simVal, opts)
        g.setColor(0.36, 0.52, 0.60, changed and 0.95 or 0.50)
        g.setLineWidth(1.2)
        drawChevron(simX + 6, y + rowH * 0.5, 3.2, 1)

        if changed then
            if improved then
                g.setColor(0.35, 0.85, 1.0, 1.0)
            else
                g.setColor(1.0, 0.39, 0.39, 1.0)
            end
            g.printf(simStr, simX + 12, textY, 70, "right")
            drawDeltaTriangle(simX + 89, y + rowH * 0.5, 4.2, diff > 0)
        else
            Theme.setColor(c.textMuted, 0.48)
            g.printf(simStr, simX + 12, textY, 70, "right")
        end
    end

    g.setColor(1, 1, 1, 0.03)
    g.setLineWidth(1)
    g.line(x, y + rowH - 0.5, x + w, y + rowH - 0.5)
end

function ArmoryUI:_drawShipSpecPanel(inv, isValid, summary)
    local g = love.graphics
    local c = Theme.colors
    local fMicro = self.localFonts.micro10
    local fSpec = self.localFonts.spec12

    local px, py, pw, ph = 864, 66, 392, 614
    local ch = inv.chassis or ChassisData.get(inv.chassisId)
    local build = summary.build or inv:computeBuild(false)
    local cur = self:_extractMetrics(inv, build)
    local sim = self:_computeCompareMetrics(inv)

    drawGlassPlane(self, px, py, pw, ph, "SHIP SPEC", nil)

    -- Header right controls: COMPARE tag + [TAB] toggle button
    local togW, togH = 74, 18
    local togX, togY = px + pw - 10 - togW, py + 5
    local hoverTog = (not self.exitModal) and pointInRect(self.mouseX, self.mouseY, togX, togY, togW, togH)
    g.setColor(0.07, 0.19, 0.26, hoverTog and 0.78 or 0.48)
    g.rectangle("fill", togX, togY, togW, togH)
    Theme.setColor(hoverTog and c.accentBright or c.accent, hoverTog and 0.90 or 0.34)
    g.setLineWidth(1)
    g.rectangle("line", togX + 0.5, togY + 0.5, togW - 1, togH - 1)
    g.setFont(fMicro)
    Theme.setColor(c.accentBright, 0.96)
    local togLabel = (self.specMode == "full") and "[TAB] 전체" or "[TAB] 요약"
    g.printf(togLabel, togX, togY + math.floor((togH - fMicro:getHeight()) * 0.5), togW, "center")
    self:addRegion(togX, togY, togW, togH, { type = "toggleSpecMode" })

    if sim then
        g.setFont(fMicro)
        g.setColor(0.35, 0.85, 1.0, 0.96)
        g.printf("COMPARE", px + 10, py + math.floor((28 - fMicro:getHeight()) * 0.5), togX - px - 18, "right")
    end

    -- Spec Sections Table
    local sx, sw = px + 10, pw - 20
    local curY = py + 34
    local isFull = (self.specMode ~= "compact")
    local rowH = isFull and 21 or 29
    local secGap = isFull and 7 or 14

    local sections
    if isFull then
        sections = {
            {
                en = "DEFENSE PERFORMANCE", kr = "방호 성능",
                rows = {
                    { "선체 구조 (HULL)", "maxHull", 6 },
                    { "장갑 내구 (ARMOR)", "maxArmor", 240 },
                    { "펄스 실드", "maxShield", 150 },
                    { "실드 재생률", "shieldRegen", 20, { decimals = 1, unit = "/s" } },
                },
            },
            {
                en = "FIREPOWER & SOCKETS", kr = "화력 관제",
                rows = {
                    { "가동 무장 수", "weaponCount", 5 },
                    { "통합 연사율", "fireRate", 12, { decimals = 1, unit = "/s" } },
                    { "사격 피크 EN", "maxWeaponBatteryCost", 20, { lowerBetter = true } },
                    { "확장 칩 소켓", "totalSockets", 16 },
                },
            },
            {
                en = "MOBILITY", kr = "기동 성능",
                rows = {
                    { "순항 속력", "maxSpeed", 600 },
                    { "부스트 속력", "boostSpeed", 3000 },
                    { "추진 출력", "thrust", 1050 },
                    { "워프 가속 보너스", "wrapBonusSpeed", 330 },
                },
            },
            {
                en = "ENERGY & REACTOR", kr = "에너지 수지",
                rows = {
                    { "EN 총 용량", "maxBattery", 300 },
                    { "EN 충전 출력", "batteryRecharge", 36, { decimals = 1, unit = "/s" } },
                    { "부스트 소비 EN", "boostCost", 100, { lowerBetter = true } },
                    { "EN 공급 효율", "netSupply", 30, { decimals = 1, unit = "/s", signed = true } },
                },
            },
        }
    else
        sections = {
            {
                en = "DEFENSE", kr = "방호",
                rows = {
                    { "장갑 내구 (ARMOR)", "maxArmor", 240 },
                    { "펄스 실드", "maxShield", 150 },
                },
            },
            {
                en = "FIREPOWER", kr = "화력",
                rows = {
                    { "통합 연사율", "fireRate", 12, { decimals = 1, unit = "/s" } },
                    { "확장 칩 소켓", "totalSockets", 16 },
                },
            },
            {
                en = "MOBILITY", kr = "기동",
                rows = {
                    { "순항 속력", "maxSpeed", 600 },
                    { "부스트 속력", "boostSpeed", 3000 },
                },
            },
            {
                en = "ENERGY", kr = "동력",
                rows = {
                    { "EN 총 용량", "maxBattery", 300 },
                    { "부스트 소비 EN", "boostCost", 100, { lowerBetter = true } },
                    { "EN 공급 효율", "netSupply", 30, { decimals = 1, unit = "/s", signed = true } },
                },
            },
        }
    end

    for sIdx, sec in ipairs(sections) do
        g.setFont(fMicro)
        Theme.setColor(c.accent, 0.90)
        g.print(sec.en, sx, curY)
        Theme.setColor(c.textMuted, 0.80)
        g.printf(sec.kr, sx, curY, sw, "right")
        curY = curY + 14
        Theme.setColor(c.accent, 0.20)
        g.setLineWidth(1)
        g.line(sx, curY + 0.5, sx + sw, curY + 0.5)
        curY = curY + 3

        for _, rDef in ipairs(sec.rows) do
            local key = rDef[2]
            self:_drawACStatRow(sx, curY, sw, rowH, rDef[1], cur[key], sim and sim[key] or nil, rDef[3], rDef[4])
            curY = curY + rowH
        end

        if sIdx < #sections then
            curY = curY + secGap
        end
    end

    -- Bottom Load & Sortie Readiness Deck (y = 544..680, h = 136)
    local deckY = py + ph - 136
    g.setColor(0.015, 0.035, 0.062, 0.65)
    g.rectangle("fill", px, deckY, pw, 136)
    Theme.setColor(c.accent, 0.24)
    g.setLineWidth(1)
    g.line(px, deckY + 0.5, px + pw, deckY + 0.5)

    -- Meter 1: PEAK EN LOAD / CAPACITOR
    local peakCost = cur.peakCost
    local maxBat = cur.maxBattery
    local enShortage = peakCost > maxBat
    local peakFrac = maxBat > 0 and math.min(1, peakCost / maxBat) or (peakCost > 0 and 1 or 0)

    local m1Y = deckY + 10
    g.setFont(fMicro)
    Theme.setColor(c.textMuted, 0.95)
    g.print("PEAK EN LOAD / CAPACITOR", sx, m1Y)
    g.setFont(fSpec)
    if enShortage then
        Theme.setColor(c.dangerBright, 0.98)
    else
        Theme.setColor(c.textHero, 0.96)
    end
    g.printf(string.format("%d / %d", peakCost, maxBat), sx, m1Y - 1, sw, "right")

    local bar1Y = m1Y + 18
    g.setColor(0.43, 0.66, 0.75, 0.16)
    g.rectangle("fill", sx, bar1Y, sw, 5)
    if enShortage then
        Theme.setColor(c.dangerBright, 0.95)
    elseif peakFrac > 0.75 then
        g.setColor(1.0, 0.82, 0.40, 0.95)
    else
        Theme.setColor(c.accentBright, 0.92)
    end
    g.rectangle("fill", sx, bar1Y, sw * peakFrac, 5)
    -- Right limit tick
    g.setColor(1, 1, 1, 0.90)
    g.rectangle("fill", sx + sw - 2, bar1Y - 2, 2, 9)

    -- Meter 2: TOTAL MASS / HARDPOINTS
    local m2Y = deckY + 50
    local cautions = summary.cautions or {}
    local hasPenalty = #cautions > 0
    local slotFrac = cur.totalCells > 0 and math.min(1, cur.usedCells / cur.totalCells) or 0

    g.setFont(fMicro)
    Theme.setColor(c.textMuted, 0.95)
    g.print("TOTAL MASS / HARDPOINTS", sx, m2Y)
    g.setFont(fSpec)
    Theme.setColor(c.textHero, 0.96)
    g.printf(string.format("%d t  /  %d · %d", cur.totalWeight, cur.usedCells, cur.totalCells), sx, m2Y - 1, sw, "right")

    local bar2Y = m2Y + 18
    g.setColor(0.43, 0.66, 0.75, 0.16)
    g.rectangle("fill", sx, bar2Y, sw, 5)
    if hasPenalty then
        g.setColor(1.0, 0.82, 0.40, 0.90)
    else
        Theme.setColor(c.accent, 0.88)
    end
    g.rectangle("fill", sx, bar2Y, sw * slotFrac, 5)

    -- Status Strip 1 (y = deckY + 88): Mandatory checks + Sortie Readiness Tag
    local stY = deckY + 86
    Theme.setColor(c.accent, 0.14)
    g.setLineWidth(1)
    g.line(sx, stY, sx + sw, stY)

    local reqItems = {
        { label = "WPN", ok = (summary.weaponCount or 0) >= 1 },
        { label = "THR", ok = (summary.thrusterCount or 0) >= 1 },
        { label = "GEN", ok = (summary.generatorCount or 0) >= 1 },
    }
    local rx = sx
    g.setFont(fMicro)
    for _, req in ipairs(reqItems) do
        local col = req.ok and c.accentBright or c.dangerBright
        g.setColor(col[1], col[2], col[3], 0.96)
        drawStatusMark(rx + 4, stY + 14, 4.2, req.ok)
        g.print(req.label, rx + 12, stY + 14 - fMicro:getHeight() * 0.5)
        rx = rx + 50
    end

    local flagText, flagCol
    if ch.locked then
        flagText, flagCol = "CHASSIS LOCKED", c.dangerBright
    elseif not isValid then
        flagText = enShortage and "EN SHORTAGE" or "REQ MISSING"
        flagCol = c.dangerBright
    elseif hasPenalty then
        flagText, flagCol = "OVERLOAD CAUTION", { 1.0, 0.82, 0.40 }
    else
        flagText, flagCol = "SORTIE STANDBY", c.accentBright
    end
    local flagW = math.max(114, fMicro:getWidth(flagText) + 16)
    local flagH = 18
    local flagX, flagY = sx + sw - flagW, stY + 5
    g.setColor(flagCol[1] * 0.20, flagCol[2] * 0.20, flagCol[3] * 0.20, 0.65)
    g.rectangle("fill", flagX, flagY, flagW, flagH)
    g.setColor(flagCol[1], flagCol[2], flagCol[3], 0.68)
    g.setLineWidth(1)
    g.rectangle("line", flagX + 0.5, flagY + 0.5, flagW - 1, flagH - 1)
    g.setColor(flagCol[1], flagCol[2], flagCol[3], 0.98)
    g.printf(flagText, flagX, flagY + math.floor((flagH - fMicro:getHeight()) * 0.5), flagW, "center")

    -- Status Strip 2 (y = deckY + 114): Overload surcharge tags (only when active)
    local penY = deckY + 113
    g.setFont(fMicro)
    local penalties = summary.categoryPenalties or {}
    local penList = {}
    for _, catId in ipairs({ "weapon", "defense", "thruster" }) do
        local pen = penalties[catId]
        if pen and (pen.addPct or 0) > 0 then
            local catDef = ModulesData.categoryById[catId]
            local tag = (catDef and catDef.tag) or string.upper(catId)
            penList[#penList + 1] = string.format("%s x%d +%d%%", tag, pen.count, pen.addPct)
        end
    end
    if #penList > 0 then
        g.setColor(1.0, 0.82, 0.40, 0.96)
        g.print("SURCHARGE: " .. table.concat(penList, "  /  "), sx, penY)
    else
        Theme.setColor(c.textMuted, 0.60)
        g.print("SYSTEM NOMINAL", sx, penY)
    end
end

function ArmoryUI:_drawFooter(inv, width)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local fMicro = self.localFonts.micro10

    local fy = 690
    if m and m.fadingRule then
        Theme.drawGradientRect(m.fadingRule, 24, fy, width - 48, 1, 1)
    else
        Theme.setColor(c.accent, 0.16)
        g.line(24, fy + 0.5, width - 24, fy + 0.5)
    end

    local ch = inv.chassis or ChassisData.get(inv.chassisId)
    local usedCells = 0
    for _, mod in ipairs(inv.placed or {}) do
        usedCells = usedCells + #Inventory.getShapeCells(mod, mod.rotation)
    end

    g.setFont(fMicro)
    Theme.setColor(c.textMuted, 0.85)
    g.print(string.format("UNIT // %s  ·  SLOTS %d/%d", ch.code or "STR-01", usedCells, inv:maxCellCount()), 24, fy + 7)

    -- Right-aligned keycaps (zero prose)
    local guides = {
        { key = "LMB", label = "장착" },
        { key = "RMB", label = "해제" },
    }
    if inv.rotationUnlocked then
        guides[#guides + 1] = { key = "R", label = "회전" }
    end
    guides[#guides + 1] = { key = "TAB", label = "제원" }
    guides[#guides + 1] = { key = "ESC", label = "나가기" }

    local totalW = 0
    for i, item in ipairs(guides) do
        local kw = math.max(22, fMicro:getWidth(item.key) + 10)
        local lw = fMicro:getWidth(item.label)
        item.kw = kw
        item.lw = lw
        totalW = totalW + kw + 5 + lw + (i < #guides and 14 or 0)
    end

    local gx = width - 24 - totalW
    local ky = fy + 5
    for _, item in ipairs(guides) do
        drawKeycap(gx, ky, item.kw, 16, item.key, fMicro, 0.92)
        g.setFont(fMicro)
        Theme.setColor(c.textMuted, 0.90)
        g.print(item.label, gx + item.kw + 5, ky + math.floor((16 - fMicro:getHeight()) * 0.5))
        gx = gx + item.kw + 5 + item.lw + 14
    end
end

function ArmoryUI:_drawExitModal(width, height)
    if not self.exitModal then return end
    local g = love.graphics
    local c = Theme.colors
    local fSpec = self.localFonts.spec12
    local fRow = self.localFonts.row13
    local ox, oy, ow, oh = Display.virtualOverscanBounds()

    g.setColor(0.01, 0.015, 0.03, 0.80)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    local mw, mh = 520, 248
    local mx = math.floor((width - mw) * 0.5)
    local my = math.floor((height - mh) * 0.5)

    g.setColor(0.035, 0.025, 0.042, 0.96)
    g.rectangle("fill", mx, my, mw, mh)
    Theme.setColor(c.dangerBright, 0.90)
    g.setLineWidth(1.5)
    g.line(mx, my + 0.5, mx + mw, my + 0.5)
    Theme.setColor(c.danger, 0.45)
    g.setLineWidth(1)
    g.line(mx, my + mh - 0.5, mx + mw, my + mh - 0.5)

    g.setColor(c.dangerBright[1], c.dangerBright[2], c.dangerBright[3], 0.95)
    drawWarningTriangle(mx + 30, my + 30, 8)

    g.setFont(fRow)
    Theme.setColor(c.dangerText, 1)
    g.print("이대로는 출격할 수 없습니다", mx + 50, my + 21)

    g.setFont(fSpec)
    Theme.setColor(c.textPrimary, 0.94)
    local y = my + 62
    for i = 1, math.min(4, #(self.exitModal.warnings or {})) do
        g.print("· " .. self.exitModal.warnings[i].message, mx + 24, y)
        y = y + 24
    end

    local btnY = my + mh - 52
    local btnW = 216
    local stayX = mx + 26
    local revertX = mx + mw - btnW - 26

    local hoverStay = pointInRect(self.mouseX, self.mouseY, stayX, btnY, btnW, 34)
    g.setColor(hoverStay and 0.09 or 0.04, hoverStay and 0.24 or 0.12, hoverStay and 0.30 or 0.18, 0.92)
    g.rectangle("fill", stayX, btnY, btnW, 34)
    Theme.setColor(hoverStay and c.accentBright or c.accent, 0.85)
    g.setLineWidth(1)
    g.rectangle("line", stayX + 0.5, btnY + 0.5, btnW - 1, 33)
    Theme.setColor(c.accentBright, 0.96)
    g.rectangle("fill", stayX, btnY, 3, 34)
    g.setFont(fSpec)
    Theme.setColor(c.textHero, 1)
    g.printf("계속 조립", stayX, btnY + math.floor((34 - fSpec:getHeight()) * 0.5), btnW, "center")
    self:addRegion(stayX, btnY, btnW, 34, { type = "modalStay" })

    local hoverRevert = pointInRect(self.mouseX, self.mouseY, revertX, btnY, btnW, 34)
    Theme.setColor(hoverRevert and c.dangerSelectedBg or c.dangerBg, 0.96)
    g.rectangle("fill", revertX, btnY, btnW, 34)
    Theme.setColor(hoverRevert and c.dangerBright or c.dangerBorder, 0.92)
    g.setLineWidth(1)
    g.rectangle("line", revertX + 0.5, btnY + 0.5, btnW - 1, 33)
    Theme.setColor(c.dangerBright, 0.96)
    g.rectangle("fill", revertX, btnY, 3, 34)
    Theme.setColor(c.dangerSelectedText, 1)
    g.printf("이전 세팅 복원 후 나가기", revertX, btnY + math.floor((34 - fSpec:getHeight()) * 0.5), btnW, "center")
    self:addRegion(revertX, btnY, btnW, 34, { type = "modalRevertExit" })
end

function ArmoryUI:draw(inv, fonts, width, height)
    self:_ensureFonts(fonts)
    local m = self:_ensureMeshes()
    local activeInv = self:activeInventory(inv)
    local isValid, warnings, summary = activeInv:validateLoadout(false)
    local g = love.graphics
    self.hitRegions = {}

    g.push("all")
    local ox, oy, ow, oh = Display.virtualOverscanBounds()
    g.setColor(0.012, 0.022, 0.044, 0.80)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    -- Left & right readability scrims preserving center cosmic backdrop
    if m.leftScrim then
        Theme.drawGradientRect(m.leftScrim, math.min(0, ox), math.min(0, oy), 460 - math.min(0, ox), math.max(height, oh), 1)
    end
    if m.rightScrim then
        local rStart = 760
        Theme.drawGradientRect(m.rightScrim, rStart, math.min(0, oy), math.max(width, ox + ow) - rStart, math.max(height, oh), 1)
    end

    self:_drawHeader(fonts, width, isValid)
    self:_drawCatalogPanel(activeInv)
    self:_drawPartSpecPanel(activeInv, summary)
    self:_drawCenterHangar(activeInv)
    self:_drawShipSpecPanel(activeInv, isValid, summary)
    self:_drawFooter(activeInv, width)

    -- Floating dragged module
    if self.dragging then
        local d = self.dragging
        local cs = self.gridRect and self.gridRect.cellSize or 64
        local gp = self.gridRect and self.gridRect.gap or 8
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
            local fMicro = self.localFonts.micro10
            g.setFont(fMicro)
            local tipW = 82
            local tipX = self.mouseX - tipW * 0.5
            local tipY = drawY + itemH + 6
            g.setColor(0.03, 0.07, 0.12, 0.90)
            g.rectangle("fill", tipX, tipY, tipW, 18)
            Theme.setColor(Theme.colors.accentBright, 0.80)
            g.setLineWidth(1)
            g.rectangle("line", tipX + 0.5, tipY + 0.5, tipW - 1, 17)
            Theme.setColor(Theme.colors.textHero, 1)
            g.printf("R: ROTATE", tipX, tipY + math.floor((18 - fMicro:getHeight()) * 0.5), tipW, "center")
        end
    end

    self:_drawExitModal(width, height)
    g.pop()
    return activeInv
end

function ArmoryUI:finishDrop(inv, x, y)
    local d = self.dragging
    if not d then return inv, nil end
    self.dragging = nil
    self.simCache = nil

    if self.gridRect and not (inv.chassis and inv.chassis.locked) then
        local snapR, snapC = self:computeSnappedOrigin(d.item, d.rotation, x, y)
        if snapR and snapC then
            local ok = inv:placeItem(d.item, snapR, snapC, d.rotation)
            if ok then
                Sfx.play("ui_equip")
                return inv, "changed"
            else
                if d.origin == "grid" then
                    inv:placeItem(d.item, d.origRow, d.origCol, d.origRotation)
                end
                Sfx.play("ui_error")
                return inv, nil
            end
        end
    end

    if d.origin == "grid" then
        Sfx.play("ui_click")
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
            self.simCache = nil
            Sfx.play("ui_click")
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
                self.simCache = nil
                Sfx.play("ui_equip")
                return resetInv, "changed"
            elseif a.type == "selectCategory" then
                self.activeCategory = a.category
                self.catalogScroll = 0
                Sfx.play("ui_click")
                return activeInv, nil
            elseif a.type == "toggleSpecMode" then
                self.specMode = (self.specMode == "full") and "compact" or "full"
                Sfx.play("ui_click")
                return activeInv, nil
            elseif a.type == "switchChassis" then
                local nextInv = self:switchChassis(activeInv, a.dir)
                return nextInv, "chassisChanged"
            elseif a.type == "catalogItem" then
                if activeInv.chassis and activeInv.chassis.locked then
                    Sfx.play("ui_error")
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
    if gridHitMod and not self.exitModal then
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
    elseif key == "tab" then
        self.specMode = (self.specMode == "full") and "compact" or "full"
        Sfx.play("ui_click")
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
