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

local MENU_LEFT = 62
local MENU_TOP = 424
local MENU_WIDTH = 314
local ROW_H = 38
local ROW_GAP = 10
local TRI_W = 22
local BEVEL_STEP = 5
local BEVEL_SHELF = 22
local BEVEL_TOP_TIP = 2.5

local MENU_PALETTE = {
    iceWhite   = { 0.94, 0.99, 1.00 },
    iceBright  = { 0.74, 0.90, 1.00 },
    iceGlow    = { 0.36, 0.74, 1.00 },
    iceDeep    = { 0.16, 0.44, 0.76 },
    plateDark  = { 0.028, 0.050, 0.088 },
    plateLeft  = { 0.095, 0.205, 0.330 },
    railLine   = { 0.56, 0.72, 0.86 },
    idleText   = { 0.60, 0.70, 0.80 },
    idleIcon   = { 0.54, 0.66, 0.78 },
}

local function createActivePlateMesh(w, h)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    local p = MENU_PALETTE
    local slash = h - (BEVEL_TOP_TIP + BEVEL_STEP)
    local xBevelBottom = w - slash
    local xNotchRight = xBevelBottom - BEVEL_SHELF
    local xNotchLeft = xNotchRight - BEVEL_STEP
    local yShelf = h - BEVEL_STEP

    local function colorAt(x)
        local tLeft = Theme.clamp(1 - x / 90, 0, 1)
        local tRight = Theme.clamp((x - (w - 85)) / 85, 0, 1)
        local r = Theme.lerp(p.plateDark[1], p.plateLeft[1], tLeft) + tRight * 0.025
        local g = Theme.lerp(p.plateDark[2], p.plateLeft[2], tLeft) + tRight * 0.055
        local b = Theme.lerp(p.plateDark[3], p.plateLeft[3], tLeft) + tRight * 0.090
        local a = 0.84 + 0.08 * tLeft
        return r, g, b, a
    end

    local verts = {}
    local function pushTri(x1, y1, x2, y2, x3, y3)
        local r1, g1, b1, a1 = colorAt(x1)
        local r2, g2, b2, a2 = colorAt(x2)
        local r3, g3, b3, a3 = colorAt(x3)
        verts[#verts + 1] = { x1, y1, x1 / w, y1 / h, r1, g1, b1, a1 }
        verts[#verts + 1] = { x2, y2, x2 / w, y2 / h, r2, g2, b2, a2 }
        verts[#verts + 1] = { x3, y3, x3 / w, y3 / h, r3, g3, b3, a3 }
    end
    local function pushQuad(x0, y0, x1, y1)
        pushTri(x0, y0, x1, y0, x1, y1)
        pushTri(x0, y0, x1, y1, x0, y1)
    end

    -- Top thin strip (0 .. BEVEL_TOP_TIP)
    local xsTop = { 0, 26, 62, 160, xNotchLeft, xNotchRight, xBevelBottom, w }
    for i = 1, #xsTop - 1 do
        pushQuad(xsTop[i], 0, xsTop[i + 1], BEVEL_TOP_TIP)
    end

    -- Middle main body (BEVEL_TOP_TIP .. yShelf)
    local xsMid = { 0, 26, 62, 160, xNotchLeft, xNotchRight, xBevelBottom }
    for i = 1, #xsMid - 1 do
        pushQuad(xsMid[i], BEVEL_TOP_TIP, xsMid[i + 1], yShelf)
    end
    pushTri(xBevelBottom, BEVEL_TOP_TIP, w, BEVEL_TOP_TIP, xBevelBottom, yShelf)

    -- Bottom strip left of the 45-degree notch (yShelf .. h)
    local xsBot = { 0, 26, 62, 160, xNotchLeft }
    for i = 1, #xsBot - 1 do
        pushQuad(xsBot[i], yShelf, xsBot[i + 1], h)
    end
    pushTri(xNotchLeft, yShelf, xNotchRight, yShelf, xNotchLeft, h)

    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function createActiveInnerGlowMesh(w, h)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    local p = MENU_PALETTE
    local slash = h - (BEVEL_TOP_TIP + BEVEL_STEP)
    local xBevelBottom = w - slash
    local xNotchRight = xBevelBottom - BEVEL_SHELF
    local xNotchLeft = xNotchRight - BEVEL_STEP
    local yShelf = h - BEVEL_STEP
    local yInnerTop = 6.5
    local yInnerBot = h - 6.5
    local xInnerRightAtTop = w - (yInnerTop - BEVEL_TOP_TIP)
    local xInnerRightAtBot = w - (yInnerBot - BEVEL_TOP_TIP)

    local function glowAt(x, y)
        local tLeft = Theme.clamp(1 - x / 85, 0, 1)
        local dEdge = math.min(y, h - y)
        local tEdge = Theme.clamp(1 - dEdge / 6.5, 0, 1)
        local rightSlopeX = (y <= BEVEL_TOP_TIP) and w or (w - (y - BEVEL_TOP_TIP))
        local tDiag = (y <= yShelf) and Theme.clamp(1 - (rightSlopeX - x) / 14, 0, 1) or 0
        local intensity = math.max(tLeft * 0.26, tEdge * 0.16, tDiag * 0.22)
        return p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], intensity
    end

    local verts = {}
    local function pushTri(x1, y1, x2, y2, x3, y3)
        local r1, g1, b1, a1 = glowAt(x1, y1)
        local r2, g2, b2, a2 = glowAt(x2, y2)
        local r3, g3, b3, a3 = glowAt(x3, y3)
        verts[#verts + 1] = { x1, y1, x1 / w, y1 / h, r1, g1, b1, a1 }
        verts[#verts + 1] = { x2, y2, x2 / w, y2 / h, r2, g2, b2, a2 }
        verts[#verts + 1] = { x3, y3, x3 / w, y3 / h, r3, g3, b3, a3 }
    end
    local function pushQuadPts(x0, y0, x1, y1, x2, y2, x3, y3)
        pushTri(x0, y0, x1, y1, x2, y2)
        pushTri(x0, y0, x2, y2, x3, y3)
    end

    -- Band 1: 0 .. BEVEL_TOP_TIP
    local xs1 = { 0, 32, 85, xNotchLeft, xBevelBottom, w }
    for i = 1, #xs1 - 1 do
        pushQuadPts(xs1[i], 0, xs1[i + 1], 0, xs1[i + 1], BEVEL_TOP_TIP, xs1[i], BEVEL_TOP_TIP)
    end
    -- Band 2: BEVEL_TOP_TIP .. yInnerTop
    local xs2 = { 0, 32, 85, xNotchLeft, xInnerRightAtTop }
    for i = 1, #xs2 - 1 do
        pushQuadPts(xs2[i], BEVEL_TOP_TIP, xs2[i + 1], BEVEL_TOP_TIP, xs2[i + 1], yInnerTop, xs2[i], yInnerTop)
    end
    pushTri(xInnerRightAtTop, BEVEL_TOP_TIP, w, BEVEL_TOP_TIP, xInnerRightAtTop, yInnerTop)
    -- Band 3: yInnerTop .. yInnerBot
    local xs3 = { 0, 32, 85, xNotchLeft, xInnerRightAtBot }
    for i = 1, #xs3 - 1 do
        pushQuadPts(xs3[i], yInnerTop, xs3[i + 1], yInnerTop, xs3[i + 1], yInnerBot, xs3[i], yInnerBot)
    end
    pushTri(xInnerRightAtBot, yInnerTop, xInnerRightAtTop, yInnerTop, xInnerRightAtBot, yInnerBot)
    -- Band 4: yInnerBot .. yShelf
    local xs4 = { 0, 32, 85, xNotchLeft, xBevelBottom }
    for i = 1, #xs4 - 1 do
        pushQuadPts(xs4[i], yInnerBot, xs4[i + 1], yInnerBot, xs4[i + 1], yShelf, xs4[i], yShelf)
    end
    pushTri(xBevelBottom, yInnerBot, xInnerRightAtBot, yInnerBot, xBevelBottom, yShelf)
    -- Band 5: yShelf .. h
    local xs5 = { 0, 32, 85, xNotchLeft }
    for i = 1, #xs5 - 1 do
        pushQuadPts(xs5[i], yShelf, xs5[i + 1], yShelf, xs5[i + 1], h, xs5[i], h)
    end
    pushTri(xNotchLeft, yShelf, xNotchRight, yShelf, xNotchLeft, h)

    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function createTriangleMesh(triW, h)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    local midY = h * 0.5
    local verts = {
        -- Top half
        { 0,    0,    0, 0,   0.76, 0.88, 0.97, 0.94 },
        { triW, midY, 1, 0.5, 0.58, 0.76, 0.90, 0.88 },
        { 0,    midY, 0, 0.5, 0.97, 0.99, 1.00, 1.00 },
        -- Bottom half
        { 0,    midY, 0, 0.5, 0.97, 0.99, 1.00, 1.00 },
        { triW, midY, 1, 0.5, 0.58, 0.76, 0.90, 0.88 },
        { 0,    h,    0, 1,   0.76, 0.88, 0.97, 0.94 },
    }
    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local SOFT_GAUSS_Y = {
    { 0.00, 0.00 },
    { 0.14, 0.04 },
    { 0.26, 0.18 },
    { 0.38, 0.54 },
    { 0.50, 1.00 },
    { 0.62, 0.54 },
    { 0.74, 0.18 },
    { 0.86, 0.04 },
    { 1.00, 0.00 },
}

local function createSoftBeam2DMesh(xStops, yProfile, transpose)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    yProfile = yProfile or SOFT_GAUSS_Y
    local verts = {}
    local function pushVert(u, v, s, mult)
        local a = (s[4] == nil and 1 or s[4]) * mult
        local x = transpose and v or u
        local y = transpose and u or v
        verts[#verts + 1] = { x, y, x, y, s[1] or 0, s[2] or 0, s[3] or 0, a }
    end
    for ix = 1, #xStops - 1 do
        local s0, s1 = xStops[ix], xStops[ix + 1]
        local u0 = Theme.clamp(s0.pos or 0, 0, 1)
        local u1 = Theme.clamp(s1.pos or 0, 0, 1)
        for iy = 1, #yProfile - 1 do
            local v0, m0 = yProfile[iy][1], yProfile[iy][2]
            local v1, m1 = yProfile[iy + 1][1], yProfile[iy + 1][2]
            pushVert(u0, v0, s0, m0)
            pushVert(u1, v0, s1, m0)
            pushVert(u1, v1, s1, m1)
            pushVert(u0, v0, s0, m0)
            pushVert(u1, v1, s1, m1)
            pushVert(u0, v1, s0, m1)
        end
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function createSoftRadialMesh(r, g, b, centerAlpha, segments)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    segments = math.max(16, segments or 40)
    centerAlpha = centerAlpha or 0.85
    local rings = {
        { 0.00, 1.00 },
        { 0.16, 0.84 },
        { 0.32, 0.56 },
        { 0.50, 0.28 },
        { 0.68, 0.10 },
        { 0.85, 0.025 },
        { 1.00, 0.00 },
    }
    local verts = {}
    local function pushRingVert(radius, mult)
        local a = centerAlpha * mult
        return function(cosA, sinA)
            local x, y = cosA * radius, sinA * radius
            verts[#verts + 1] = { x, y, 0.5 + x * 0.5, 0.5 + y * 0.5, r, g, b, a }
        end
    end
    for i = 0, segments - 1 do
        local a0 = (i / segments) * math.pi * 2
        local a1 = ((i + 1) / segments) * math.pi * 2
        local c0, s0 = math.cos(a0), math.sin(a0)
        local c1, s1 = math.cos(a1), math.sin(a1)
        -- Inner core triangle
        local r1, m1 = rings[2][1], rings[2][2]
        verts[#verts + 1] = { 0, 0, 0.5, 0.5, r, g, b, centerAlpha }
        pushRingVert(r1, m1)(c0, s0)
        pushRingVert(r1, m1)(c1, s1)
        -- Outer Gaussian falloff rings
        for k = 2, #rings - 1 do
            local rIn, mIn = rings[k][1], rings[k][2]
            local rOut, mOut = rings[k + 1][1], rings[k + 1][2]
            local vIn = pushRingVert(rIn, mIn)
            local vOut = pushRingVert(rOut, mOut)
            vIn(c0, s0); vOut(c0, s0); vOut(c1, s1)
            vIn(c0, s0); vOut(c1, s1); vIn(c1, s1)
        end
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "static")
    if ok then return mesh end
    return nil
end

local function buildMeshes()
    local deep = Theme.colors.bgOverlay
    local acc = Theme.colors.accent
    local bright = Theme.colors.accentBright
    local p = MENU_PALETTE
    return {
        -- Left-to-right readability scrim (keeps live ship combat and planet bright)
        leftScrim = Theme.createGradientMesh({
            { pos = 0.00, deep[1], deep[2], deep[3], 0.78 },
            { pos = 0.24, deep[1], deep[2], deep[3], 0.52 },
            { pos = 0.44, deep[1], deep[2], deep[3], 0.16 },
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
        -- Reference-style left menu optical flares & 2D soft-feathered plumes
        menuFlareHalo = createSoftRadialMesh(p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.85, 40),
        menuFlareCore = createSoftRadialMesh(0.95, 0.99, 1.00, 1.00, 32),
        menuRightBeamAura = createSoftBeam2DMesh({
            { pos = 0.00, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.00 },
            { pos = 0.09, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.07 },
            { pos = 0.16, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.22 },
            { pos = 0.20, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.34 },
            { pos = 0.28, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.20 },
            { pos = 0.42, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.09 },
            { pos = 0.62, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.032 },
            { pos = 0.82, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.008 },
            { pos = 1.00, p.iceDeep[1], p.iceDeep[2], p.iceDeep[3], 0.00 },
        }, SOFT_GAUSS_Y, false),
        menuRightBeamSoft = createSoftBeam2DMesh({
            { pos = 0.00, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.00 },
            { pos = 0.08, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.08 },
            { pos = 0.15, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.28 },
            { pos = 0.20, p.iceBright[1], p.iceBright[2], p.iceBright[3], 0.58 },
            { pos = 0.26, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.36 },
            { pos = 0.38, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.16 },
            { pos = 0.56, p.iceDeep[1],   p.iceDeep[2],   p.iceDeep[3],   0.055 },
            { pos = 0.78, p.iceDeep[1],   p.iceDeep[2],   p.iceDeep[3],   0.012 },
            { pos = 1.00, p.iceDeep[1],   p.iceDeep[2],   p.iceDeep[3],   0.00 },
        }, SOFT_GAUSS_Y, false),
        menuRightBeamCore = createSoftBeam2DMesh({
            { pos = 0.00, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.00 },
            { pos = 0.08, p.iceBright[1], p.iceBright[2], p.iceBright[3], 0.14 },
            { pos = 0.16, p.iceBright[1], p.iceBright[2], p.iceBright[3], 0.56 },
            { pos = 0.20, 0.96,           0.99,           1.00,           1.00 },
            { pos = 0.25, p.iceBright[1], p.iceBright[2], p.iceBright[3], 0.68 },
            { pos = 0.35, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.30 },
            { pos = 0.52, p.iceGlow[1],   p.iceGlow[2],   p.iceGlow[3],   0.09 },
            { pos = 0.74, p.iceDeep[1],   p.iceDeep[2],   p.iceDeep[3],   0.018 },
            { pos = 1.00, p.iceDeep[1],   p.iceDeep[2],   p.iceDeep[3],   0.00 },
        }, SOFT_GAUSS_Y, false),
        menuStreak = createSoftBeam2DMesh({
            { pos = 0.00, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.00 },
            { pos = 0.25, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.22 },
            { pos = 0.50, 0.96, 0.99, 1.00, 1.00 },
            { pos = 0.75, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.22 },
            { pos = 1.00, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.00 },
        }, SOFT_GAUSS_Y, false),
        menuVertStreak = createSoftBeam2DMesh({
            { pos = 0.00, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.00 },
            { pos = 0.25, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.22 },
            { pos = 0.50, 0.96, 0.99, 1.00, 1.00 },
            { pos = 0.75, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.22 },
            { pos = 1.00, p.iceGlow[1], p.iceGlow[2], p.iceGlow[3], 0.00 },
        }, SOFT_GAUSS_Y, true),
        menuDivider = Theme.createGradientMesh({
            { pos = 0.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.32 },
            { pos = 0.38, p.railLine[1], p.railLine[2], p.railLine[3], 0.20 },
            { pos = 0.78, p.railLine[1], p.railLine[2], p.railLine[3], 0.07 },
            { pos = 1.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.00 },
        }, true),
        menuSpineFadeTop = Theme.createGradientMesh({
            { pos = 0.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.00 },
            { pos = 0.45, p.railLine[1], p.railLine[2], p.railLine[3], 0.24 },
            { pos = 1.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.34 },
        }, false),
        menuSpineFadeBottom = Theme.createGradientMesh({
            { pos = 0.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.30 },
            { pos = 1.00, p.railLine[1], p.railLine[2], p.railLine[3], 0.00 },
        }, false),
        menuActivePlateMesh = createActivePlateMesh(MENU_WIDTH, ROW_H),
        menuActiveInnerGlowMesh = createActiveInnerGlowMesh(MENU_WIDTH, ROW_H),
        menuTriangleMesh = createTriangleMesh(TRI_W, ROW_H),
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
    }
end

local function computeMenuLayout(menu)
    local items = {}
    local buttons = (menu and menu.buttons) or {}
    local y = MENU_TOP
    for i, button in ipairs(buttons) do
        items[i] = {
            index = i,
            button = button,
            x = MENU_LEFT,
            y = y,
            w = MENU_WIDTH,
            h = ROW_H,
        }
        y = y + ROW_H + ROW_GAP
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

local function drawMenuTickIcon(ix, cy, focus, alpha)
    local g = love.graphics
    local p = MENU_PALETTE
    local r = Theme.lerp(p.idleIcon[1], p.iceWhite[1], focus)
    local gr = Theme.lerp(p.idleIcon[2], p.iceWhite[2], focus)
    local b = Theme.lerp(p.idleIcon[3], p.iceWhite[3], focus)
    local pts = {
        ix,        cy - 4.5,
        ix + 3.5,  cy - 4.5,
        ix + 11.5, cy + 4.5,
        ix + 19.0, cy + 4.5,
    }
    if focus > 0.05 then
        g.setBlendMode("add")
        g.setLineWidth(3.2)
        Theme.setColor(p.iceGlow, 0.38 * focus * alpha)
        g.line(pts)
        g.setBlendMode("alpha")
    end
    g.setLineWidth(Theme.lerp(1.15, 1.85, focus))
    g.setColor(r, gr, b, Theme.lerp(0.62, 0.96, focus) * alpha)
    g.line(pts)
end

local function getFrameAnchors(width, height, px, py)
    local spineX = MENU_LEFT + px
    local outerX = spineX - 38
    local farX = spineX - 48
    local shelfY = height - 58 + py
    local nodeY = shelfY - 16
    local outerCornerY = nodeY - 38
    local splitX = spineX + 130
    local baseY = shelfY + 12
    return {
        spineX = spineX,
        outerX = outerX,
        farX = farX,
        shelfY = shelfY,
        nodeY = nodeY,
        outerCornerY = outerCornerY,
        splitX = splitX,
        baseY = baseY,
        rightStepX1 = width - 134 + px,
        rightStepX2 = width - 126 + px,
        rightShelfY = baseY - 8,
    }
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
        indicatorH = ROW_H,
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
    local hitLeft = MENU_LEFT - 14
    local hitRight = MENU_LEFT + MENU_WIDTH + 14
    if mouseX < hitLeft or mouseX > hitRight then return nil end
    for _, item in ipairs(items) do
        if mouseY >= item.y - 2 and mouseY <= item.y + item.h + 2 then
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

function TitleScreen:_drawLeftMenu(menu, fonts, selected, width, height, launchP)
    local g = love.graphics
    local c = Theme.colors
    local p = MENU_PALETTE
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

    local buttonFont = fonts.titleButton or fonts.menuButton
    local firstIntroA = self:_menuItemIntro(1)
    local railAlpha = firstIntroA * launchMenuAlpha
    local fa = getFrameAnchors(width, height, px, py)
    local frameSpineX = fa.spineX
    local spineX = frameSpineX + launchSlideX
    local railTop = topY + py
    local breathe = 0.88 + 0.12 * math.sin(self.elapsed * 2.5)

    local activeItem = items[selected] or items[1]
    local indY = (self.indicatorInit and self.indicatorY or activeItem.y) + py
    local indH = self.indicatorInit and self.indicatorH or activeItem.h
    local indA = self:_menuItemIntro(selected) * launchMenuAlpha

    g.push("all")

    -- 1. Rotating dotted circular orbital quadrant framing the left menu
    if railAlpha > 0.01 then
        local arcCx = frameSpineX - 2
        local arcCy = railTop + 60
        local arcR = 166
        local dotCount = 120
        local rotAngle = self.elapsed * 0.16
        local minAng = -math.pi * 0.50
        local maxAng = math.pi * 0.45

        for i = 0, dotCount - 1 do
            local rawAng = (i / dotCount) * (math.pi * 2) + rotAngle
            local ang = ((rawAng + math.pi) % (math.pi * 2)) - math.pi
            if ang >= minAng and ang <= maxAng then
                local edgeFade = Theme.smoothstep(-math.pi * 0.50, -math.pi * 0.42, ang)
                    * (1 - Theme.smoothstep(math.pi * 0.34, math.pi * 0.45, ang))
                local cosA = math.cos(ang)
                local sinA = math.sin(ang)
                local dx = arcCx + cosA * arcR
                local dy = arcCy + sinA * arcR
                if i % 30 == 0 then
                    Theme.setColor(p.iceBright, 0.36 * edgeFade * railAlpha)
                    g.setLineWidth(1)
                    g.line(
                        arcCx + cosA * (arcR - 3.5), arcCy + sinA * (arcR - 3.5),
                        arcCx + cosA * (arcR + 1.5), arcCy + sinA * (arcR + 1.5)
                    )
                end
                if i % 10 == 0 then
                    Theme.setColor(p.iceBright, 0.48 * edgeFade * railAlpha)
                    g.circle("fill", dx, dy, 1.35)
                else
                    Theme.setColor(p.railLine, 0.24 * edgeFade * railAlpha)
                    g.circle("fill", dx, dy, 0.9)
                end
            end
        end

        -- Stationary subtle anchor pip where the arc meets the spine at top
        Theme.setColor(p.iceBright, 0.55 * railAlpha)
        g.circle("fill", frameSpineX, arcCy - arcR, 1.35)
    end

    -- 2. Left structural telemetry frame (full outer perimeter rails, upper spine, lower corner node)
    if railAlpha > 0.01 then
        local upperSpineTop = 103 + py
        local upperArcTop = railTop + 60 - 166

        -- Far-left faint full-height hairline
        Theme.setColor(p.railLine, 0.11 * railAlpha)
        g.setLineWidth(1)
        g.line(fa.farX, -10, fa.farX, height + 10)

        -- Upper outer left rail & diagonal chamfer branches
        Theme.setColor(p.railLine, 0.22 * railAlpha)
        g.setLineWidth(1)
        g.line(fa.outerX, -10, fa.outerX, railTop - 120, frameSpineX, railTop - 82)
        Theme.setColor(p.railLine, 0.14 * railAlpha)
        g.line(fa.outerX, 65 + py, frameSpineX, upperSpineTop)

        -- Upper fading spine segment + telemetry dashed ticks between arc top and menu top
        Theme.drawGradientRect(m.menuSpineFadeTop, frameSpineX - 0.5, upperSpineTop, 1, railTop - upperSpineTop, railAlpha)
        Theme.setColor(p.iceBright, 0.28 * railAlpha)
        g.setLineWidth(1)
        for tickY = upperArcTop + 14, railTop - 12, 16 do
            g.line(frameSpineX, tickY, frameSpineX, tickY + 5)
        end
        Theme.setColor(p.railLine, 0.24 * railAlpha)
        g.line(frameSpineX - 3, upperArcTop, frameSpineX + 3, upperArcTop)

        -- Main solid vertical spine through menu rows down to bottom shelf
        Theme.setColor(p.railLine, 0.30 * railAlpha)
        g.setLineWidth(1)
        g.line(frameSpineX, railTop, frameSpineX, fa.shelfY)
        Theme.drawGradientRect(m.menuSpineFadeBottom, frameSpineX - 0.5, fa.shelfY, 1, 26, railAlpha)

        -- Subtle additive highlight along spine behind active button
        if indA > 0.01 then
            g.setBlendMode("add")
            Theme.drawGradientRect(m.menuVertStreak, spineX - 0.9, indY - 16, 1.8, indH + 32, 0.42 * indA)
            g.setBlendMode("alpha")
        end

        -- Lower outer left rail & 45-degree chamfer through glowing node to bottom shelf
        Theme.setColor(p.railLine, 0.28 * railAlpha)
        g.setLineWidth(1)
        g.line(
            fa.outerX,    railTop - 88,
            fa.outerX,    fa.outerCornerY,
            frameSpineX,  fa.nodeY,
            frameSpineX + 16, fa.shelfY
        )

        -- Glowing intersection corner node at (frameSpineX, fa.nodeY)
        g.setBlendMode("add")
        Theme.drawRadialHalo(m.menuFlareHalo, frameSpineX, fa.nodeY, 7, 7, 0.60 * railAlpha)
        Theme.drawRadialHalo(m.menuFlareCore, frameSpineX, fa.nodeY, 3.5, 3.5, 0.72 * railAlpha)
        g.setBlendMode("alpha")
        Theme.setColor(p.iceWhite, 0.90 * railAlpha)
        g.circle("fill", frameSpineX, fa.nodeY, 2.0)

        -- Subtle cross pip at spine/shelf intersection
        Theme.setColor(p.railLine, 0.35 * railAlpha)
        g.circle("fill", frameSpineX, fa.shelfY, 1.1)
    end

    -- 3. Unselected row dividers & spine intersection pips (including top rule above first item)
    if railAlpha > 0.01 then
        local topDivY = items[1].y - ROW_GAP * 0.5 + py
        local topNearActive = (topDivY >= indY - 2) and (topDivY <= indY + indH + 2)
        local topDamp = topNearActive and 0.25 or 1.0
        Theme.drawGradientRect(m.menuDivider, spineX + 1, topDivY, MENU_WIDTH - 22, 1, topDamp * railAlpha)
        g.setBlendMode("add")
        Theme.drawRadialHalo(m.menuFlareHalo, spineX, topDivY, 4.5, 4.5, 0.45 * topDamp * railAlpha)
        g.setBlendMode("alpha")
        Theme.setColor(p.iceBright, 0.85 * topDamp * railAlpha)
        g.circle("fill", spineX, topDivY, 1.25)

        for i = 1, #items do
            local item = items[i]
            local divY = item.y + item.h + ROW_GAP * 0.5 + py
            local nearActive = (divY >= indY - 2) and (divY <= indY + indH + 2)
            local damp = nearActive and 0.25 or 1.0
            local lineScale = (i == #items) and 0.62 or 1.0
            Theme.drawGradientRect(m.menuDivider, spineX + 1, divY, MENU_WIDTH - 22, 1, lineScale * damp * railAlpha)

            if i < #items then
                g.setBlendMode("add")
                Theme.drawRadialHalo(m.menuFlareHalo, spineX, divY, 4.5, 4.5, 0.45 * damp * railAlpha)
                g.setBlendMode("alpha")
                Theme.setColor(p.iceBright, 0.85 * damp * railAlpha)
                g.circle("fill", spineX, divY, 1.25)
            end
        end
    end

    -- 4. Sliding active button frame + multi-layer optical glows
    if indA > 0.01 then
        local bx = spineX
        local by = indY
        local bw = MENU_WIDTH
        local bh = indH
        local slash = bh - (BEVEL_TOP_TIP + BEVEL_STEP)
        local xBevelBottom = bx + bw - slash
        local xNotchRight = xBevelBottom - BEVEL_SHELF
        local xNotchLeft = xNotchRight - BEVEL_STEP
        local yShelf = by + bh - BEVEL_STEP
        local scaleY = bh / ROW_H

        -- Dark translucent glass interior plate
        if m.menuActivePlateMesh then
            g.setColor(1, 1, 1, indA)
            g.draw(m.menuActivePlateMesh, bx, by, 0, 1, scaleY)
        end
        -- Soft additive inner bezel glow
        if m.menuActiveInnerGlowMesh then
            g.setBlendMode("add")
            g.setColor(1, 1, 1, (0.78 + 0.22 * self.selectPulse) * indA)
            g.draw(m.menuActiveInnerGlowMesh, bx, by, 0, 1, scaleY)
            g.setBlendMode("alpha")
        end

        local outline = {
            bx,           by,
            bx + bw,      by,
            bx + bw,      by + BEVEL_TOP_TIP,
            xBevelBottom, yShelf,
            xNotchRight,  yShelf,
            xNotchLeft,   by + bh,
            bx,           by + bh,
        }

        -- Outer beveled outline in 4 passes (wide bloom -> mid glow -> crisp core -> top/slash highlight)
        g.setBlendMode("add")
        g.setLineWidth(5.5)
        Theme.setColor(p.iceDeep, (0.28 * breathe + 0.20 * self.selectPulse) * indA)
        g.polygon("line", outline)

        g.setLineWidth(2.6)
        Theme.setColor(p.iceGlow, (0.44 * breathe + 0.26 * self.selectPulse) * indA)
        g.polygon("line", outline)
        g.setBlendMode("alpha")

        g.setLineWidth(1.25)
        Theme.setColor(p.iceBright, 0.94 * indA)
        g.polygon("line", outline)

        g.setBlendMode("add")
        g.setLineWidth(1.2)
        Theme.setColor(p.iceWhite, 0.56 * indA)
        g.line(bx, by, bx + bw, by, bx + bw, by + BEVEL_TOP_TIP, xBevelBottom, yShelf)
        g.setBlendMode("alpha")

        -- Inner top-left & bottom-left stepped bezel flanges
        Theme.setColor(p.iceGlow, 0.16 * indA)
        g.polygon("fill", bx + 1, by + 1, bx + 55.5, by + 1, bx + 51.5, by + 4.5, bx + 1, by + 4.5)
        g.polygon("fill", bx + 1, by + bh - 4.5, bx + 51.5, by + bh - 4.5, bx + 55.5, by + bh - 1, bx + 1, by + bh - 1)

        g.setLineWidth(1)
        Theme.setColor(p.iceBright, 0.54 * indA)
        g.line(bx + 2, by + 4.5, bx + 52, by + 4.5, bx + 56.5, by + 0.5)
        Theme.setColor(p.iceBright, 0.48 * indA)
        g.line(bx + 2, by + bh - 4.5, bx + 52, by + bh - 4.5, bx + 56.5, by + bh - 0.5)

        -- Bottom-right micro tech recess tab left of the 45-degree notch
        local tabX = xNotchLeft - 24
        local tabY = by + bh - 3.5
        Theme.setColor(p.iceDeep, 0.34 * indA)
        g.rectangle("fill", tabX, tabY, 22, 3)
        Theme.setColor(p.iceBright, 0.45 * indA)
        g.line(tabX + 1, tabY, tabX + 21, tabY)

        -- Left glowing right-pointing triangle + subtle diagonal rim sheen
        if m.menuTriangleMesh then
            g.setColor(1, 1, 1, indA)
            g.draw(m.menuTriangleMesh, bx, by, 0, 1, scaleY)
        end
        g.setLineWidth(1)
        Theme.setColor(p.iceWhite, 0.20 * indA)
        g.line(bx, by, bx + TRI_W, by + bh * 0.5, bx, by + bh)

        -- Left starburst flare centered on the triangle spine (2D feathered & Gaussian halos)
        local leftFlareY = by + bh * 0.5
        g.setBlendMode("add")
        Theme.drawRadialHalo(m.menuFlareHalo, bx, leftFlareY, 42, 48, (0.54 * breathe + 0.22 * self.selectPulse) * indA)
        Theme.drawRadialHalo(m.menuFlareHalo, bx, leftFlareY, 20, 30, (0.74 * breathe + 0.24 * self.selectPulse) * indA)
        Theme.drawRadialHalo(m.menuFlareCore, bx, leftFlareY, 8.5, 11, 0.94 * indA)
        Theme.drawGradientRect(m.menuVertStreak, bx - 2.75, leftFlareY - 34, 5.5, 68, 0.86 * indA)
        Theme.drawGradientRect(m.menuStreak, bx - 20, leftFlareY - 2.2, 40, 4.4, 0.64 * indA)

        -- Top-right tip seamless 2D feathered optical plume & anamorphic lens flare
        local tipX = bx + bw
        local tipY = by + 1.5
        Theme.drawGradientRect(m.menuRightBeamAura, tipX - 460 * 0.20, tipY - 23, 460, 46, (0.85 * breathe + 0.25 * self.selectPulse) * indA)
        Theme.drawGradientRect(m.menuRightBeamSoft, tipX - 400 * 0.20, tipY - 9, 400, 18, (0.88 * breathe + 0.22 * self.selectPulse) * indA)
        Theme.drawGradientRect(m.menuRightBeamCore, tipX - 340 * 0.20, tipY - 2.3, 340, 4.6, (0.95 * breathe + 0.18 * self.selectPulse) * indA)
        Theme.drawRadialHalo(m.menuFlareHalo, tipX, tipY, 26, 18, (0.62 * breathe + 0.22 * self.selectPulse) * indA)
        Theme.drawRadialHalo(m.menuFlareCore, tipX, tipY, 7.5, 6.0, 0.92 * indA)
        Theme.drawGradientRect(m.menuVertStreak, tipX - 2.0, tipY - 12, 4.0, 24, 0.64 * indA)
        g.setBlendMode("alpha")
    end

    -- 5. Menu items (bent-tick icons + Korean labels)
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

        local label = type(item.button.label) == "function" and item.button.label() or item.button.label
        local textX = math.floor(baseX + 70 + focus * 3 + 0.5)
        local textY = math.floor(itemY + (item.h - buttonFont:getHeight()) * 0.5 + 0.5)

        if itemAlpha > 0.005 then
            drawMenuTickIcon(baseX + 36, itemY + item.h * 0.5, focus, itemAlpha)

            -- Subtle dark drop shadow for crisp legibility over nebula background
            g.setFont(buttonFont)
            Theme.setColor(c.bgDeep, 0.78 * itemAlpha)
            g.print(label, textX, textY + 1)

            -- Soft additive icy-blue bloom behind focused label
            if focus > 0.05 then
                g.setBlendMode("add")
                Theme.setColor(p.iceGlow, (0.28 * focus + 0.22 * self.selectPulse * focus) * itemAlpha)
                g.print(label, textX, textY)
                g.setBlendMode("alpha")
            end
        end

        -- Main label (always invoked during title mode so UI label queries stay deterministic)
        g.setFont(buttonFont)
        local r = Theme.lerp(p.idleText[1], p.iceWhite[1], focus)
        local gr = Theme.lerp(p.idleText[2], p.iceWhite[2], focus)
        local b = Theme.lerp(p.idleText[3], p.iceWhite[3], focus)
        local a = Theme.lerp(0.72, 1.0, focus) * itemAlpha
        if focus > 0.25 and itemAlpha > 0.005 then
            g.setColor(r, gr, b, a * 0.38 * focus)
            g.print(label, textX + 0.55, textY)
        end
        g.setColor(r, gr, b, a)
        g.print(label, textX, textY)
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
    local p = MENU_PALETTE
    local m = self.meshes
    local microFont = fonts.titleMicro or fonts.menuSmall or fonts.small
    local px = self.parallaxX * TitleScreen.PARALLAX_UI_MAX_PX * 0.55
    local py = self.parallaxY * TitleScreen.PARALLAX_UI_MAX_PX * 0.55
    local fa = getFrameAnchors(width, height, px, py)

    g.push("all")

    -- 1. Seamless lower perimeter frame continuing from (fa.spineX + 16, fa.shelfY)
    Theme.setColor(p.railLine, 0.30 * alpha)
    g.setLineWidth(1)
    g.line(fa.spineX + 16, fa.shelfY, fa.splitX, fa.shelfY)
    -- Fading upper horizontal continuation rightward
    Theme.drawGradientRect(m.menuDivider, fa.splitX, fa.shelfY, 270, 1, 0.85 * alpha)
    -- Step down and run across the entire bottom edge to the stepped-up right corner
    Theme.setColor(p.railLine, 0.30 * alpha)
    g.line(
        fa.splitX,      fa.shelfY,
        fa.splitX + 12, fa.baseY,
        fa.rightStepX1, fa.baseY,
        fa.rightStepX2, fa.rightShelfY,
        width + 10,     fa.rightShelfY
    )

    -- Small luminous node at the shelf split point
    g.setBlendMode("add")
    Theme.drawRadialHalo(m.menuFlareHalo, fa.splitX, fa.shelfY, 4.5, 4.5, 0.48 * alpha)
    g.setBlendMode("alpha")
    Theme.setColor(p.iceWhite, 0.86 * alpha)
    g.circle("fill", fa.splitX, fa.shelfY, 1.4)

    -- 2. Bottom-left tracked version text + 3 slanted diagonal bars
    Theme.setColor(p.idleText, 0.68 * alpha)
    drawTrackedText(microFont, TitleScreen.GAME_VERSION, fa.spineX + 10, fa.baseY + 5, 3.6, "left")

    local barStartX = fa.spineX + 82
    local barTopY = fa.baseY + 5
    local barW = 7.5
    local barH = 9.5
    local barSkew = 9.5
    local barStride = 14
    g.setColor(0.36, 0.48, 0.60, 0.38 * alpha)
    for i = 0, 2 do
        local bx = barStartX + i * barStride
        g.polygon(
            "fill",
            bx,                barTopY,
            bx + barW,         barTopY,
            bx + barW + barSkew, barTopY + barH,
            bx + barSkew,      barTopY + barH
        )
    end

    -- 3. Bottom-right 4 subtle indicator dots
    local dotY = fa.baseY + 9
    local dotXs = {
        width - 88 + px,
        width - 68 + px,
        width - 48 + px,
        width - 28 + px,
    }
    g.setBlendMode("add")
    Theme.drawRadialHalo(m.menuFlareHalo, dotXs[1], dotY, 4.5, 4.5, 0.36 * alpha)
    g.setBlendMode("alpha")
    Theme.setColor(p.iceBright, 0.52 * alpha)
    g.circle("fill", dotXs[1], dotY, 2.0)

    Theme.setColor(p.railLine, 0.24 * alpha)
    for i = 2, 4 do
        g.circle("fill", dotXs[i], dotY, 1.25)
    end

    g.pop()
end

function TitleScreen:draw(menu, fonts, selected, width, height)
    local logoP, ruleP, footerP, veilAlpha = self:_introProgress()
    local scrimAlpha = 1 - veilAlpha * 0.65

    self:_drawScrims(width, height, scrimAlpha)
    self:_drawHeroTitle(fonts, width, logoP, ruleP, 0)
    self:_drawLeftMenu(menu, fonts, selected, width, height, 0)
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
    self:_drawLeftMenu(self.launchMenu, fonts, self.launchSelected, width, height, launchP)
    self:_drawBottomBar(fonts, width, height, 1, launchP)
end

return TitleScreen
