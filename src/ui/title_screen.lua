-- Dedicated commercial-grade title screen renderer & motion controller for SPACE GLADIATOR.
-- Layout: Centered heroic title logo in upper-center; sleek panel-less menu gathered on the left;
-- atmospheric readability scrim preserving the ringed planet & nebula backdrop; bottom info bar.
-- Motion: Cinematic intro sequence, smooth exponential selection indicator, subtle mouse parallax,
-- periodic specular light sweep, and launch dissolve overlay bridging into the opening entry warp.

local Display = require("src.core.display")
local Theme = require("src.ui.theme")

local TitleScreen = {}
TitleScreen.__index = TitleScreen

TitleScreen.GAME_VERSION = "v0.1.0"
TitleScreen.TITLE_TOP = "SPACE"
TitleScreen.TITLE_MAIN = "GLADIATOR"
TitleScreen.EYEBROW = "DEEP SPACE ARENA"
TitleScreen.TAGLINE = "INERTIAL COMBAT SYSTEM"

TitleScreen.INTRO_FULL_DURATION = 1.25
TitleScreen.INTRO_QUICK_DURATION = 0.42
TitleScreen.LAUNCH_DURATION = 0.38
TitleScreen.SHIMMER_PERIOD = 4.8
TitleScreen.SHIMMER_DURATION = 0.85
TitleScreen.PARALLAX_BG_MAX_PX = 7.0
TitleScreen.PARALLAX_UI_MAX_PX = 2.6

local MENU_LEFT = 86
local MENU_TOP = 388
local MENU_WIDTH = 278
local PRIMARY_ROW_H = 58
local REGULAR_ROW_H = 46
local PRIMARY_GAP = 14
local REGULAR_GAP = 10

local function buildMeshes()
    local deep = Theme.colors.bgOverlay
    local acc = Theme.colors.accent
    local bright = Theme.colors.accentBright
    return {
        -- Left-to-right readability scrim (keeps right planet & central nebula bright)
        leftScrim = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.86 },
            { pos = 0.24, deep[1], deep[2], deep[3], 0.62 },
            { pos = 0.44, deep[1], deep[2], deep[3], 0.22 },
            { pos = 0.62, deep[1], deep[2], deep[3], 0.00 },
            { pos = 1.00, deep[1], deep[2], deep[3], 0.00 },
        }, true),
        -- Subtle top cinematic vignette
        topVignette = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.48 },
            { pos = 0.55, deep[1], deep[2], deep[3], 0.14 },
            { pos = 1.00, deep[1], deep[2], deep[3], 0.00 },
        }, false),
        -- Bottom cinematic vignette anchoring the footer info bar
        bottomVignette = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.00 },
            { pos = 0.45, deep[1], deep[2], deep[3], 0.34 },
            { pos = 1.00, deep[1], deep[2], deep[3], 0.82 },
        }, false),
        -- Soft elliptical radial halo behind the centered title (zero rectangular seams)
        titleHalo = Theme.createRadialGradientMesh(deep[1], deep[2], deep[3], 0.52, nil, 40),
        -- Active menu item horizontal highlight wash
        activeWash = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.26 },
            { pos = 0.32, acc[1], acc[2], acc[3], 0.14 },
            { pos = 0.75, acc[1], acc[2], acc[3], 0.04 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.00 },
        }, true),
        -- Active menu item fading hairline edge
        activeRule = Theme.createGradientMesh({
            { pos = 0.00, bright[1], bright[2], bright[3], 0.80 },
            { pos = 0.45, acc[1],    acc[2],    acc[3],    0.34 },
            { pos = 1.00, acc[1],    acc[2],    acc[3],    0.00 },
        }, true),
        -- Symmetrical glowing accent rule under the centered title
        centerRule = Theme.createGradientMesh({
            { pos = 0.00, acc[1],    acc[2],    acc[3],    0.00 },
            { pos = 0.22, acc[1],    acc[2],    acc[3],    0.52 },
            { pos = 0.50, bright[1], bright[2], bright[3], 0.95 },
            { pos = 0.78, acc[1],    acc[2],    acc[3],    0.52 },
            { pos = 1.00, acc[1],    acc[2],    acc[3],    0.00 },
        }, true),
        -- Specular shimmer highlight band
        shimmerBand = Theme.createGradientMesh({
            { pos = 0.00, 1.0, 1.0, 1.0, 0.00 },
            { pos = 0.42, bright[1], bright[2], bright[3], 0.65 },
            { pos = 0.50, 1.0, 1.0, 1.0, 0.98 },
            { pos = 0.58, bright[1], bright[2], bright[3], 0.65 },
            { pos = 1.00, 1.0, 1.0, 1.0, 0.00 },
        }, true),
        -- Subtle fading footer hairline
        footerRule = Theme.createGradientMesh({
            { pos = 0.00, acc[1], acc[2], acc[3], 0.00 },
            { pos = 0.08, acc[1], acc[2], acc[3], 0.26 },
            { pos = 0.92, acc[1], acc[2], acc[3], 0.26 },
            { pos = 1.00, acc[1], acc[2], acc[3], 0.00 },
        }, true),
    }
end

local function computeMenuLayout(menu)
    local items = {}
    local buttons = (menu and menu.buttons) or {}
    local y = MENU_TOP
    for i, button in ipairs(buttons) do
        local isPrimary = (button.primary == true) or (i == 1 and button.primary ~= false)
        local h = isPrimary and PRIMARY_ROW_H or REGULAR_ROW_H
        local gap = isPrimary and PRIMARY_GAP or REGULAR_GAP
        items[i] = {
            index = i,
            button = button,
            primary = isPrimary,
            x = MENU_LEFT,
            y = y,
            w = MENU_WIDTH,
            h = h,
        }
        y = y + h + gap
    end
    local totalH = #items > 0 and (items[#items].y + items[#items].h - MENU_TOP) or 0
    return items, MENU_TOP, totalH
end

local function measureTrackedText(font, text, tracking)
    if not text or #text == 0 then return 0 end
    local total = 0
    local len = #text
    for i = 1, len do
        local ch = text:sub(i, i)
        total = total + font:getWidth(ch)
        if i < len then
            total = total + tracking
        end
    end
    return total
end

local function drawTrackedText(font, text, cx, y, tracking, align)
    local g = love.graphics
    g.setFont(font)
    local totalW = measureTrackedText(font, text, tracking)
    local x = cx
    if align == "center" then
        x = cx - totalW * 0.5
    elseif align == "right" then
        x = cx - totalW
    end
    local cursorX = math.floor(x + 0.5)
    local drawY = math.floor(y + 0.5)
    local len = #text
    for i = 1, len do
        local ch = text:sub(i, i)
        if ch ~= " " then
            g.print(ch, cursorX, drawY)
        end
        cursorX = cursorX + font:getWidth(ch) + tracking
    end
    return totalW, x
end

local function drawDiamond(x, y, r)
    love.graphics.polygon("fill", x, y - r, x + r, y, x, y + r, x - r, y)
end

local function drawChevron(x, y, size)
    love.graphics.polygon(
        "fill",
        x, y - size * 0.65,
        x + size * 0.92, y,
        x, y + size * 0.65,
        x + size * 0.28, y
    )
end

local function drawKeycap(x, y, w, h, label, font, alpha, iconKind)
    local g = love.graphics
    local c = Theme.colors
    Theme.setColor(c.panelBg, 0.72 * alpha)
    g.rectangle("fill", x, y, w, h, 3, 3)
    Theme.setColor(c.panelBorder, 0.68 * alpha)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)

    if iconKind == "up" or iconKind == "down" then
        Theme.setColor(c.accentBright, 0.85 * alpha)
        local cx, cy = x + w * 0.5, y + h * 0.5
        if iconKind == "up" then
            g.polygon("fill", cx, cy - 3.2, cx + 3.6, cy + 2.4, cx - 3.6, cy + 2.4)
        else
            g.polygon("fill", cx, cy + 3.2, cx + 3.6, cy - 2.4, cx - 3.6, cy - 2.4)
        end
    elseif label and font then
        g.setFont(font)
        Theme.setColor(c.textPrimary, 0.86 * alpha)
        local tw = font:getWidth(label)
        local th = font:getHeight()
        g.print(label, math.floor(x + (w - tw) * 0.5 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5))
    end
end

function TitleScreen.new()
    local self = setmetatable({
        meshes = buildMeshes(),
        elapsed = 0,
        introTime = 0,
        introDuration = TitleScreen.INTRO_FULL_DURATION,
        introQuick = false,
        introSkipped = false,
        launching = false,
        launchTime = 0,
        launchDuration = TitleScreen.LAUNCH_DURATION,
        launchMenu = nil,
        launchSelected = 1,
        selected = 1,
        selectPulse = 0,
        indicatorY = MENU_TOP,
        indicatorH = PRIMARY_ROW_H,
        indicatorInit = false,
        hoverMix = {},
        targetParallaxX = 0,
        targetParallaxY = 0,
        parallaxX = 0,
        parallaxY = 0,
    }, TitleScreen)
    return self
end

function TitleScreen:reset(opts)
    opts = opts or {}
    self.elapsed = 0
    self.introQuick = (opts.quick == true)
    self.introDuration = self.introQuick and TitleScreen.INTRO_QUICK_DURATION or TitleScreen.INTRO_FULL_DURATION
    self.introTime = opts.skipIntro and self.introDuration or 0
    self.introSkipped = (opts.skipIntro == true)
    self.launching = false
    self.launchTime = 0
    self.launchMenu = nil
    self.selected = opts.selected or 1
    self.selectPulse = 0
    self.indicatorInit = false
    self.hoverMix = {}
    self.hoverMix[self.selected] = 1
    if not opts.keepParallax then
        self.parallaxX, self.parallaxY = 0, 0
        self.targetParallaxX, self.targetParallaxY = 0, 0
    end
end

function TitleScreen:isIntroActive()
    return (not self.introSkipped) and (self.introTime < self.introDuration)
end

function TitleScreen:skipIntro()
    self.introSkipped = true
    self.introTime = self.introDuration
end

function TitleScreen:beginLaunch(menu, selected)
    self:skipIntro()
    self.launching = true
    self.launchTime = 0
    self.launchMenu = menu
    self.launchSelected = selected or self.selected or 1
end

function TitleScreen:isLaunching()
    return self.launching == true
end

function TitleScreen:setMouse(vx, vy, width, height)
    width = width or Display.VIRTUAL_WIDTH
    height = height or Display.VIRTUAL_HEIGHT
    local nx = Theme.clamp(((vx or width * 0.5) / math.max(1, width)) * 2 - 1, -1, 1)
    local ny = Theme.clamp(((vy or height * 0.5) / math.max(1, height)) * 2 - 1, -1, 1)
    self.targetParallaxX = -nx
    self.targetParallaxY = -ny
end

function TitleScreen:getBackgroundParallax()
    return self.parallaxX * TitleScreen.PARALLAX_BG_MAX_PX,
           self.parallaxY * TitleScreen.PARALLAX_BG_MAX_PX
end

function TitleScreen:update(dt, menu, selected)
    dt = math.max(0, dt or 0)
    if dt <= 0 then return end
    self.elapsed = self.elapsed + dt

    -- Smooth mouse parallax
    self.parallaxX = Theme.expLerp(self.parallaxX, self.targetParallaxX, 5.5, dt)
    self.parallaxY = Theme.expLerp(self.parallaxY, self.targetParallaxY, 5.5, dt)

    if self.launching then
        self.launchTime = self.launchTime + dt
        if self.launchTime >= self.launchDuration then
            self.launching = false
            self.launchMenu = nil
        end
        return
    end

    if not self.introSkipped and self.introTime < self.introDuration then
        self.introTime = math.min(self.introDuration, self.introTime + dt)
    end

    local activeIdx = selected or self.selected or 1
    if activeIdx ~= self.selected then
        self.selected = activeIdx
        self.selectPulse = 1
    end
    if self.selectPulse > 0 then
        self.selectPulse = math.max(0, self.selectPulse - dt / 0.26)
    end

    local items = computeMenuLayout(menu)
    local targetItem = items[activeIdx] or items[1]
    if targetItem then
        if not self.indicatorInit then
            self.indicatorY = targetItem.y
            self.indicatorH = targetItem.h
            self.indicatorInit = true
        else
            self.indicatorY = Theme.expLerp(self.indicatorY, targetItem.y, 18, dt)
            self.indicatorH = Theme.expLerp(self.indicatorH, targetItem.h, 18, dt)
        end
    end

    for i = 1, #items do
        local cur = self.hoverMix[i]
        local target = (i == activeIdx) and 1 or 0
        if cur == nil then
            self.hoverMix[i] = target
        else
            self.hoverMix[i] = Theme.expLerp(cur, target, 16, dt)
        end
    end
end

function TitleScreen:buttonAt(menu, width, height, mouseX, mouseY)
    if not menu or not menu.buttons then return nil end
    local items = computeMenuLayout(menu)
    local hitLeft = MENU_LEFT - 28
    local hitRight = MENU_LEFT + MENU_WIDTH + 18
    if mouseX < hitLeft or mouseX > hitRight then return nil end
    for _, item in ipairs(items) do
        if mouseY >= item.y - 4 and mouseY <= item.y + item.h + 4 then
            return item.index
        end
    end
    return nil
end

function TitleScreen:_introProgress()
    if self.introSkipped or self.introTime >= self.introDuration then
        return 1, 1, 1, 0
    end
    if self.introQuick then
        local p = Theme.easeOutCubic(self.introTime / self.introDuration)
        return p, p, p, (1 - p) * 0.28
    end
    local t = self.introTime
    -- 0.00 -> 0.45: veil lifts
    local veilAlpha = 1 - Theme.easeOutCubic(t / 0.45)
    -- 0.14 -> 0.84: centered hero title arrives & letter spacing tightens
    local logoP = Theme.easeOutQuart((t - 0.14) / 0.70)
    -- 0.36 -> 0.92: accent rule expands
    local ruleP = Theme.easeOutCubic((t - 0.36) / 0.56)
    -- 0.62 -> 1.15: footer fades in
    local footerP = Theme.easeOutCubic((t - 0.62) / 0.53)
    return logoP, ruleP, footerP, veilAlpha
end

function TitleScreen:_menuItemIntro(index)
    if self.introSkipped or self.introTime >= self.introDuration then
        return 1, 0
    end
    if self.introQuick then
        local p = Theme.easeOutCubic((self.introTime - (index - 1) * 0.04) / 0.28)
        return p, (1 - p) * -12
    end
    local startT = 0.46 + (index - 1) * 0.075
    local p = Theme.easeOutQuart((self.introTime - startT) / 0.42)
    return p, (1 - p) * -20
end

function TitleScreen:_drawScrims(width, height, alpha)
    if alpha <= 0.001 then return end
    local ox, oy, ow, oh = Display.virtualOverscanBounds()
    local leftX = math.min(0, ox)
    local topY = math.min(0, oy)
    local fullW = math.max(width, ow)
    local fullH = math.max(height, oh)
    local m = self.meshes

    -- Left gradient scrim extending seamlessly across left overscan
    local scrimRight = width * 0.64
    Theme.drawGradientRect(m.leftScrim, leftX, topY, scrimRight - leftX, fullH, alpha)
    -- Top & bottom cinematic vignettes
    Theme.drawGradientRect(m.topVignette, leftX, topY, fullW, math.max(130, 130 - topY), alpha)
    local botH = 128 + math.max(0, (oy + oh) - height)
    Theme.drawGradientRect(m.bottomVignette, leftX, height - 128, fullW, botH, alpha)
    -- Soft elliptical atmospheric halo behind hero title (seam-free)
    Theme.drawRadialHalo(m.titleHalo, width * 0.5, 194, width * 0.38, 138, alpha * 0.92)
end

function TitleScreen:_drawHeroTitle(fonts, width, logoP, ruleP, launchP)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes

    local logoAlpha = logoP
    local launchScale = 1
    local launchFlare = 0
    if launchP > 0 then
        local easeOut = Theme.easeOutCubic(launchP)
        logoAlpha = logoAlpha * (1 - Theme.smoothstep(0.06, 0.95, launchP))
        launchScale = 1 + 0.075 * easeOut
        -- Brief cyan flare peaking near t = 0.25 of launch
        launchFlare = math.sin(Theme.clamp(launchP / 0.55, 0, 1) * math.pi)
    end
    if logoAlpha <= 0.002 then return end

    local px = -self.parallaxX * TitleScreen.PARALLAX_UI_MAX_PX * 0.85
    local py = -self.parallaxY * TitleScreen.PARALLAX_UI_MAX_PX * 0.85
    local cx = width * 0.5 + px
    local centerY = 188 + py

    local heroFont = fonts.titleHero or fonts.menuTitle
    local subFont = fonts.titleSub or fonts.menuTitle
    local microFont = fonts.titleMicro or fonts.menuSmall

    local extraTrack = (1 - logoP) * 14
    local shimmerPhase = (self.elapsed % TitleScreen.SHIMMER_PERIOD) / TitleScreen.SHIMMER_DURATION
    local shimmerActive = shimmerPhase >= 0 and shimmerPhase <= 1
    local breathe = 0.86 + 0.14 * math.sin(self.elapsed * 2.1)

    g.push("all")
    g.translate(cx, centerY)
    g.scale(launchScale, launchScale)
    g.translate(-cx, -centerY)

    -- 1. Eyebrow line with symmetrical hairline rails and diamond pips
    local eyebrowY = 98 + py
    local eyebrowAlpha = logoAlpha * ruleP
    if eyebrowAlpha > 0.01 then
        local eyTrack = 5.5 + extraTrack * 0.25
        local eyW = measureTrackedText(microFont, TitleScreen.EYEBROW, eyTrack)
        local halfGap = eyW * 0.5 + 22
        local wingLen = 96 * ruleP
        Theme.setColor(c.accent, 0.42 * eyebrowAlpha)
        g.setLineWidth(1)
        g.line(cx - halfGap - wingLen, eyebrowY + 7, cx - halfGap, eyebrowY + 7)
        g.line(cx + halfGap, eyebrowY + 7, cx + halfGap + wingLen, eyebrowY + 7)
        Theme.setColor(c.accentBright, 0.82 * eyebrowAlpha)
        drawDiamond(cx - halfGap + 4, eyebrowY + 7, 2.4)
        drawDiamond(cx + halfGap - 4, eyebrowY + 7, 2.4)
        Theme.setColor(c.accentBright, 0.78 * eyebrowAlpha)
        drawTrackedText(microFont, TitleScreen.EYEBROW, cx, eyebrowY, eyTrack, "center")
    end

    -- 2. Upper title word: "SPACE"
    local topTrack = 17 + extraTrack * 0.85
    local topY = 122 + py + (1 - logoP) * -8
    -- Subtle dark drop shadow
    Theme.setColor(c.bgDeep, 0.75 * logoAlpha)
    drawTrackedText(subFont, TitleScreen.TITLE_TOP, cx, topY + 2, topTrack, "center")
    -- Soft cyan additive glow
    g.setBlendMode("add")
    Theme.setColor(c.accent, (0.26 * breathe + 0.30 * launchFlare) * logoAlpha)
    drawTrackedText(subFont, TitleScreen.TITLE_TOP, cx, topY, topTrack, "center")
    g.setBlendMode("alpha")
    -- Crisp ice-white core
    Theme.setColor(c.textPrimary, 0.92 * logoAlpha)
    drawTrackedText(subFont, TitleScreen.TITLE_TOP, cx, topY, topTrack, "center")

    -- 3. Hero title word: "GLADIATOR"
    local mainTrack = 9.5 + extraTrack * 0.65
    local mainY = 160 + py + (1 - logoP) * 6
    -- Crisp dark depth shadow
    Theme.setColor(c.bgDeep, 0.85 * logoAlpha)
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY + 4, mainTrack, "center")
    Theme.setColor(c.bgDeep, 0.50 * logoAlpha)
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY + 2, mainTrack, "center")
    -- Multi-pass additive cyan halo bloom
    g.setBlendMode("add")
    local haloAlpha = (0.14 * breathe + 0.24 * launchFlare) * logoAlpha
    Theme.setColor(c.accent, haloAlpha)
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx - 2, mainY, mainTrack, "center")
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx + 2, mainY, mainTrack, "center")
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY - 2, mainTrack, "center")
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY + 2, mainTrack, "center")
    Theme.setColor(c.accentCool, (0.10 * breathe + 0.16 * launchFlare) * logoAlpha)
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY, mainTrack, "center")
    g.setBlendMode("alpha")
    -- Bright platinum-white core text (subtle 0.6px horizontal fill for commanding display weight)
    Theme.setColor(c.textHero, 0.42 * logoAlpha)
    drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx + 0.6, mainY, mainTrack, "center")
    Theme.setColor(c.textHero, logoAlpha)
    local mainW = drawTrackedText(heroFont, TitleScreen.TITLE_MAIN, cx, mainY, mainTrack, "center")

    -- 4. Symmetrical glowing lower accent rule + specular light sweep
    local ruleY = 264 + py
    local ruleFullW = math.max(460, mainW * 0.92)
    local ruleW = ruleFullW * ruleP
    if ruleW > 4 then
        local ruleX = cx - ruleW * 0.5
        -- Soft glow strip behind rule
        g.setBlendMode("add")
        Theme.drawGradientRect(m.centerRule, ruleX, ruleY - 3, ruleW, 7, (0.28 * breathe + 0.35 * launchFlare) * logoAlpha)
        g.setBlendMode("alpha")
        -- Core hairline
        Theme.drawGradientRect(m.centerRule, ruleX, ruleY, ruleW, 1.5, 0.92 * logoAlpha)
        -- Center diamond emblem
        Theme.setColor(c.accentBright, 0.95 * logoAlpha)
        drawDiamond(cx, ruleY + 0.75, 3.4)
        -- End bracket ticks
        Theme.setColor(c.accent, 0.55 * logoAlpha * ruleP)
        g.setLineWidth(1)
        g.line(ruleX + 8, ruleY - 4, ruleX + 3, ruleY + 0.75, ruleX + 8, ruleY + 5.5)
        g.line(ruleX + ruleW - 8, ruleY - 4, ruleX + ruleW - 3, ruleY + 0.75, ruleX + ruleW - 8, ruleY + 5.5)

        -- Periodic specular glint sweeping across the rule
        if shimmerActive and launchP == 0 then
            local sweepW = 110
            local sweepX = ruleX - sweepW + (ruleW + sweepW) * Theme.easeOutCubic(shimmerPhase)
            local clipL = math.max(ruleX, sweepX)
            local clipR = math.min(ruleX + ruleW, sweepX + sweepW)
            if clipR > clipL then
                g.setBlendMode("add")
                Theme.drawGradientRect(m.shimmerBand, clipL, ruleY - 2, clipR - clipL, 5.5, 0.85 * logoAlpha)
                g.setBlendMode("alpha")
            end
        end
    end

    -- 5. Subtle micro-tagline under accent rule
    local tagAlpha = logoAlpha * ruleP * 0.78
    if tagAlpha > 0.01 then
        Theme.setColor(c.textSecondary, tagAlpha)
        drawTrackedText(microFont, TitleScreen.TAGLINE, cx, ruleY + 15, 5.2, "center")
    end

    g.pop()
end

function TitleScreen:_drawLeftMenu(menu, fonts, selected, launchP)
    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local items, topY, totalH = computeMenuLayout(menu)
    if #items == 0 then return end

    local px = self.parallaxX * TitleScreen.PARALLAX_UI_MAX_PX * 0.55
    local py = self.parallaxY * TitleScreen.PARALLAX_UI_MAX_PX * 0.55

    local launchMenuAlpha = 1
    local launchSlideX = 0
    if launchP > 0 then
        local lp = Theme.easeInCubic(Theme.clamp(launchP / 0.62, 0, 1))
        launchMenuAlpha = 1 - lp
        launchSlideX = -38 * lp
    end
    if launchMenuAlpha <= 0.002 then return end

    local primaryFont = fonts.titlePrimary or fonts.menuButton
    local buttonFont = fonts.titleButton or fonts.menuButton
    local microFont = fonts.titleMicro or fonts.menuSmall

    local firstIntroA = self:_menuItemIntro(1)
    local railAlpha = firstIntroA * launchMenuAlpha
    local railX = MENU_LEFT - 18 + px + launchSlideX
    local railTop = topY + py
    local breathe = 0.84 + 0.16 * math.sin(self.elapsed * 2.6)

    g.push("all")

    -- Micro section header above menu
    if railAlpha > 0.01 then
        local hdrY = railTop - 32
        Theme.setColor(c.accent, 0.72 * railAlpha)
        g.rectangle("fill", railX, hdrY + 5, 14, 2)
        g.setFont(microFont)
        Theme.setColor(c.accentBright, 0.58 * railAlpha)
        g.print("COMMAND // MENU", math.floor(railX + 22), math.floor(hdrY))

        -- Subtle vertical structural guide rail
        Theme.setColor(c.panelBorder, 0.34 * railAlpha)
        g.setLineWidth(1)
        g.line(railX + 1.5, railTop - 4, railX + 1.5, railTop + totalH + 4)
        Theme.setColor(c.accent, 0.50 * railAlpha)
        g.rectangle("fill", railX, railTop - 5, 4, 1.5)
        g.rectangle("fill", railX, railTop + totalH + 4, 4, 1.5)
    end

    -- Smoothly interpolated sliding indicator bar + active horizontal wash
    local activeItem = items[selected] or items[1]
    local indY = (self.indicatorInit and self.indicatorY or activeItem.y) + py
    local indH = self.indicatorInit and self.indicatorH or activeItem.h
    local indA = self:_menuItemIntro(selected) * launchMenuAlpha

    if indA > 0.01 then
        local washX = railX + 4
        local washW = MENU_WIDTH + 22
        -- Gradient horizontal wash behind active item
        Theme.drawGradientRect(m.activeWash, washX, indY + 1, washW, indH - 2, (0.95 + 0.25 * self.selectPulse) * indA)
        -- Top & bottom fading cyan accent rules
        Theme.drawGradientRect(m.activeRule, washX, indY, washW * 0.85, 1.2, 0.65 * indA)
        Theme.drawGradientRect(m.activeRule, washX, indY + indH - 1.2, washW * 0.65, 1.2, 0.38 * indA)
        -- Additive glow halo behind sliding indicator pill
        g.setBlendMode("add")
        Theme.setColor(c.accent, (0.34 * breathe + 0.35 * self.selectPulse) * indA)
        g.rectangle("fill", railX - 3, indY + 3, 9, indH - 6, 4, 4)
        g.setBlendMode("alpha")
        -- Crisp glowing indicator bar
        Theme.setColor(c.accentBright, indA)
        g.rectangle("fill", railX, indY + 5, 3.5, indH - 10, 1.8, 1.8)
    end

    -- Menu items
    for _, item in ipairs(items) do
        local introA, introShiftX = self:_menuItemIntro(item.index)
        local itemLaunchP = launchP > 0 and Theme.easeInCubic(Theme.clamp((launchP - (item.index - 1) * 0.08) / 0.55, 0, 1)) or 0
        local itemAlpha = introA * (1 - itemLaunchP)
        local focus = self.hoverMix[item.index]
        if focus == nil then
            focus = (item.index == selected) and 1 or 0
        end
        local itemShiftX = introShiftX - 36 * itemLaunchP + px
        local baseX = item.x + itemShiftX
        local itemY = item.y + py

        local font = item.primary and primaryFont or buttonFont
        local label = type(item.button.label) == "function" and item.button.label() or item.button.label
        local textShift = focus * 11
        local textX = math.floor(baseX + textShift + 0.5)
        local textY = math.floor(itemY + (item.h - font:getHeight()) * 0.5 + 0.5)

        if itemAlpha > 0.005 then
            -- Small active chevron marker sliding in to the left of the text
            if focus > 0.05 then
                Theme.setColor(c.accentBright, focus * 0.92 * itemAlpha)
                drawChevron(baseX - 4 + focus * 3, itemY + item.h * 0.5, 5.2)
            end

            -- Subtle dark drop shadow for sharp legibility over bright nebula wisps
            g.setFont(font)
            Theme.setColor(c.bgDeep, 0.72 * itemAlpha)
            g.print(label, textX, textY + 1)

            -- Soft additive highlight behind focused label
            if focus > 0.05 then
                g.setBlendMode("add")
                Theme.setColor(c.accent, (0.24 * focus + 0.22 * self.selectPulse * focus) * itemAlpha)
                g.print(label, textX, textY)
                g.setBlendMode("alpha")
            end
        end

        -- Main label (bright pure white when selected, cool translucent slate when idle)
        -- Always invoked during title mode (even at alpha 0 on frame 0) so UI label queries stay deterministic.
        g.setFont(font)
        local r = Theme.lerp(c.textSecondary[1], c.textHero[1], focus)
        local gr = Theme.lerp(c.textSecondary[2], c.textHero[2], focus)
        local b = Theme.lerp(c.textSecondary[3], c.textHero[3], focus)
        local a = Theme.lerp(item.primary and 0.78 or 0.66, 1.0, focus) * itemAlpha
        g.setColor(r, gr, b, a)
        g.print(label, textX, textY)

        if itemAlpha > 0.005 then
            -- Right-aligned English sub-label (LAUNCH / SETTINGS / EXIT)
            if item.button.sublabel and item.button.sublabel ~= "" then
                local subAlpha = Theme.lerp(0.36, 0.92, focus) * itemAlpha
                local subColor = focus > 0.5 and c.accentBright or c.textSecondary
                Theme.setColor(subColor, subAlpha)
                local subX = baseX + MENU_WIDTH - (1 - focus) * 6
                local subY = math.floor(itemY + (item.h - microFont:getHeight()) * 0.5 + 1)
                drawTrackedText(microFont, item.button.sublabel, subX, subY, 2.4, "right")
            end
        end
    end

    g.pop()
end

function TitleScreen:_drawBottomBar(fonts, width, height, footerP, launchP)
    local alpha = footerP
    if launchP > 0 then
        alpha = alpha * (1 - Theme.easeInCubic(Theme.clamp(launchP / 0.45, 0, 1)))
    end
    if alpha <= 0.005 then return end

    local g = love.graphics
    local c = Theme.colors
    local m = self.meshes
    local smallFont = fonts.menuSmall or fonts.small
    local microFont = fonts.titleMicro or smallFont

    local ruleY = height - 54
    local barY = height - 34
    local leftX = MENU_LEFT - 18
    local rightX = width - 68

    g.push("all")
    -- Hairline bottom divider
    Theme.drawGradientRect(m.footerRule, leftX - 16, ruleY, (rightX - leftX) + 32, 1, alpha)

    -- Left: pulsing status dot + title/version metadata
    local dotPulse = 0.62 + 0.38 * math.sin(self.elapsed * 3.0)
    Theme.setColor(c.accentBright, dotPulse * 0.85 * alpha)
    g.circle("fill", leftX + 4, barY + 6, 2.6)
    g.setBlendMode("add")
    Theme.setColor(c.accent, dotPulse * 0.35 * alpha)
    g.circle("fill", leftX + 4, barY + 6, 6.2)
    g.setBlendMode("alpha")

    g.setFont(smallFont)
    Theme.setColor(c.textMuted, 0.72 * alpha)
    g.print("SPACE GLADIATOR  /  " .. TitleScreen.GAME_VERSION, leftX + 16, math.floor(barY - 1))

    -- Right: clean keycap badges with procedural vector arrow icons (100% glyph-safe)
    local capH = 19
    local capY = math.floor(barY - 3)
    local curX = rightX
    local labelY = math.floor(barY - 1)

    local function pushHint(text, capLabel, capW, iconKind)
        g.setFont(smallFont)
        local tw = smallFont:getWidth(text)
        curX = curX - tw
        Theme.setColor(c.textMuted, 0.72 * alpha)
        g.print(text, math.floor(curX), labelY)
        curX = curX - 7 - capW
        drawKeycap(curX, capY, capW, capH, capLabel, microFont, alpha, iconKind)
        curX = curX - 20
    end

    pushHint("선택", "CLICK", 44, nil)
    pushHint("확인", "ENTER", 48, nil)

    -- Up/Down vector arrow keycap pair + "이동"
    g.setFont(smallFont)
    local moveW = smallFont:getWidth("이동")
    curX = curX - moveW
    Theme.setColor(c.textMuted, 0.72 * alpha)
    g.print("이동", math.floor(curX), labelY)
    curX = curX - 7 - 20
    drawKeycap(curX, capY, 20, capH, nil, nil, alpha, "down")
    curX = curX - 4 - 20
    drawKeycap(curX, capY, 20, capH, nil, nil, alpha, "up")

    g.pop()
end

function TitleScreen:draw(menu, fonts, selected, width, height)
    local logoP, ruleP, footerP, veilAlpha = self:_introProgress()
    local scrimAlpha = 1 - veilAlpha * 0.65

    self:_drawScrims(width, height, scrimAlpha)
    self:_drawHeroTitle(fonts, width, logoP, ruleP, 0)
    self:_drawLeftMenu(menu, fonts, selected, 0)
    self:_drawBottomBar(fonts, width, height, footerP, 0)

    -- Cinematic intro fade-from-black veil
    if veilAlpha > 0.004 then
        local g = love.graphics
        local ox, oy, ow, oh = Display.virtualOverscanBounds()
        g.push("all")
        g.setColor(0.008, 0.012, 0.026, veilAlpha)
        g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))
        g.pop()
    end
end

function TitleScreen:drawLaunchOverlay(fonts, width, height)
    if not self.launching or not self.launchMenu then return end
    local launchP = Theme.clamp(self.launchTime / math.max(0.001, self.launchDuration), 0, 1)
    local scrimAlpha = 1 - Theme.easeOutCubic(Theme.clamp(launchP / 0.78, 0, 1))

    self:_drawScrims(width, height, scrimAlpha)
    self:_drawHeroTitle(fonts, width, 1, 1, launchP)
    self:_drawLeftMenu(self.launchMenu, fonts, self.launchSelected, launchP)
    self:_drawBottomBar(fonts, width, height, 1, launchP)
end

return TitleScreen
