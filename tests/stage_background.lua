-- Focused tests for Level 1/2/3 backdrop assignment, staying on Level 1 across stages,
-- slow velocity-driven parallax, overscan bounds, and lowest-layer draw ordering beneath Starfield.

local StageBackground = require("stage_background")
local Stage = require("stage")
local Starfield = require("starfield")

local checks = 0
local function check(cond, msg)
    assert(cond, msg)
    checks = checks + 1
end
local function near(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-4)
end

-- 1. All 3 level background images (Level 1, 2, 3) exist and load cleanly
local bg = StageBackground.new(1280, 800)
check(#bg.images == 3, "Expected all 3 level background images to load, got " .. tostring(#bg.images))
check(StageBackground.LEVEL_PATHS[1] == "assets/backgrounds/level_1.jpg"
    and StageBackground.LEVEL_PATHS[2] == "assets/backgrounds/level_2.jpg"
    and StageBackground.LEVEL_PATHS[3] == "assets/backgrounds/level_3.jpg",
    "Each attached image must be registered as Level 1, 2, and 3")
for i = 1, 3 do
    local iw, ih = bg:imageDimensions(i)
    check(iw > 0 and ih > 0, "Level " .. i .. " background must have positive image dimensions")
end

-- 2. Level-to-background mapping selects Level 1, 2, and 3 explicitly
for levelNum = 1, 3 do
    bg:setLevel(levelNum, true)
    check(bg.level == levelNum and bg.index == levelNum,
        string.format("Level %d must select background %d (got level=%d index=%d)", levelNum, levelNum, bg.level, bg.index))
end

-- 3. Active stage progression stays in Level 1 so the player experiences the same level across stages
local s1 = Stage.new(1)
local s2 = s1:nextStage()
local s3 = s2:nextStage()
check(s1.level == 1 and s2.level == 1 and s3.level == 1,
    "Stages 1, 2, and 3 must currently remain on Level 1")
bg:setLevel(s1.level, true)
bg:update(0.5, 160, 0, 1280, 800)
local savedU = bg.u
bg:setLevel(s2.level, bg.level ~= s2.level)
check(bg.level == 1 and bg.index == 1 and near(bg.u, savedU),
    "Advancing to Stage 2 within Level 1 must keep Level 1 background seamlessly without jumping")
bg:setLevel(1, true)

-- 4. Stationary player produces zero parallax drift
for _ = 1, 60 do
    bg:update(1 / 60, 0, 0, 1280, 800)
end
local ox0, oy0 = bg:currentOffset()
check(near(ox0, 0) and near(oy0, 0), "Stationary ship must not drift the level background")

-- 5. Moving player shifts background slowly in the opposite direction (slower than Starfield layer 1)
local stars = Starfield.new(1280, 800, function() return 0.5 end)
local starStartX = stars.layers[1].stars[1].x
for _ = 1, 60 do
    bg:update(1 / 60, 180, -120, 1280, 800)
    stars:update(1 / 60, 180 * 2.8, -120 * 2.8, 0, 1280, 800, 0)
end
local ox1, oy1 = bg:currentOffset()
local starTravelX = math.abs(starStartX - stars.layers[1].stars[1].x)
check(ox1 < -5 and oy1 > 3,
    string.format("Moving right/up must drift background left/down (got %.2f, %.2f)", ox1, oy1))
check(math.abs(ox1) < starTravelX,
    string.format("Level background parallax (%.2f px) must be slower than Starfield layer 1 (%.2f px)",
        math.abs(ox1), starTravelX))

-- 6. Stopping smoothly eases background velocity back to rest
for _ = 1, 240 do
    bg:update(1 / 60, 0, 0, 1280, 800)
end
local restX, restY = bg:currentOffset()
bg:update(0.5, 0, 0, 1280, 800)
local restX2, restY2 = bg:currentOffset()
check(near(restX, restX2, 1e-3) and near(restY, restY2, 1e-3),
    "Background must settle cleanly once player stops moving")

-- 7. Sustained extreme flight stays strictly within overscan bounds and reverses immediately
for _ = 1, 1800 do
    bg:update(1 / 60, 600, 600, 1280, 800)
end
check(bg.u >= -1 and bg.u <= 1 and bg.v >= -1 and bg.v <= 1,
    "Normalized parallax offset must remain strictly within [-1, 1]")
local edgeX, edgeY = bg:currentOffset()
for _ = 1, 30 do
    bg:update(1 / 60, -240, -240, 1280, 800)
end
local revX, revY = bg:currentOffset()
check(revX > edgeX and revY > edgeY,
    "Reversing flight direction near the parallax edge must respond immediately without deadzone")

-- 8. Overscan covers the entire viewport with zero gaps at all aspect ratios and extreme offsets
for _, vp in ipairs({ { 1280, 800 }, { 1920, 1080 }, { 2560, 1080 }, { 800, 600 } }) do
    local w, h = vp[1], vp[2]
    local iw, ih = bg:imageDimensions(1)
    for _, uv in ipairs({ { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { 0, 0 } }) do
        local layout = bg:computeLayout(iw, ih, w, h, uv[1], uv[2])
        check(layout.x <= 0.001 and layout.y <= 0.001
            and layout.x + layout.drawW >= w - 0.001
            and layout.y + layout.drawH >= h - 0.001,
            string.format("Background must cover full viewport %dx%d at u=%d v=%d", w, h, uv[1], uv[2]))
    end
end

-- 9. Draw ordering & transparent Starfield layering: background image renders beneath stars without opaque overwrite
if love and love.graphics then
    local g = love.graphics
    local origDraw = g.draw
    local origRect = g.rectangle
    local origCircle = g.circle
    local events = {}
    g.draw = function(...)
        events[#events + 1] = "image"
        return origDraw(...)
    end
    g.rectangle = function(...)
        events[#events + 1] = "rect"
        return origRect(...)
    end
    g.circle = function(...)
        events[#events + 1] = "star"
        return origCircle(...)
    end
    local ok, err = pcall(function()
        bg:draw(1280, 800)
        stars:draw({ transparent = true })
    end)
    g.draw, g.rectangle, g.circle = origDraw, origRect, origCircle
    check(ok, "StageBackground + transparent Starfield draw must succeed: " .. tostring(err))

    local firstImage, firstStar, rectAfterImage = nil, nil, false
    for idx, kind in ipairs(events) do
        if kind == "image" and not firstImage then firstImage = idx end
        if kind == "star" and not firstStar then firstStar = idx end
        if firstImage and idx > firstImage and kind == "rect" then rectAfterImage = true end
    end
    check(firstImage ~= nil and firstStar ~= nil and firstImage < firstStar,
        "Level background image must draw beneath Starfield stars")
    check(not rectAfterImage,
        "Transparent Starfield must not draw an opaque rectangle over the level background")

    -- 10. Default image opacity is 80% (StageBackground.ALPHA)
    local drawnAlpha = nil
    g.draw = function(...)
        local _, _, _, a = g.getColor()
        drawnAlpha = a
        return origDraw(...)
    end
    local okAlpha, errAlpha = pcall(function()
        bg:draw(1280, 800)
    end)
    g.draw = origDraw
    check(okAlpha and drawnAlpha ~= nil and near(drawnAlpha, 0.80) and near(StageBackground.ALPHA, 0.80),
        "Stage background image must render at 80% opacity (got " .. tostring(drawnAlpha) .. "): " .. tostring(errAlpha))

    -- 11. Same-level warp draws only Level 1 (no crossfade); different-level warp crossfades cleanly
    local sameLevelDraws = 0
    g.draw = function(...)
        sameLevelDraws = sameLevelDraws + 1
        return origDraw(...)
    end
    local okSame, errSame = pcall(function()
        bg:draw(1280, 800, { nextLevel = 1, blend = 0.5 })
    end)
    g.draw = origDraw
    check(okSame and sameLevelDraws == 1,
        "Same-level warp must keep Level 1 background without crossfading: " .. tostring(errSame))

    local diffLevelDraws = 0
    g.draw = function(...)
        diffLevelDraws = diffLevelDraws + 1
        return origDraw(...)
    end
    local okDiff, errDiff = pcall(function()
        bg:draw(1280, 800, { nextLevel = 2, blend = 0.5 })
    end)
    g.draw = origDraw
    check(okDiff and diffLevelDraws == 2,
        "Different-level warp must crossfade between current and next level backgrounds: " .. tostring(errDiff))
end

print(string.format("PASS: %d level background parallax, bounds, and layering checks", checks))
