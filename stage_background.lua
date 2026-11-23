-- Level backdrop renderer with slow velocity-driven parallax.
-- Each image corresponds to Level 1, 2, and 3; drawn at the bottom-most layer
-- beneath the Starfield, Arena, and gameplay entities.

local StageBackground = {}
StageBackground.__index = StageBackground

StageBackground.LEVEL_PATHS = {
    [1] = "assets/backgrounds/level_1.jpg",
    [2] = "assets/backgrounds/level_2.jpg",
    [3] = "assets/backgrounds/level_3.jpg",
}
StageBackground.DEFAULT_LEVEL = 1

-- Overscan factor ensures every viewport aspect ratio retains smooth parallax
-- travel margin on all four sides without ever exposing image borders.
StageBackground.OVERSCAN = 1.24
-- Slow parallax relative to player velocity (significantly slower than Starfield layers).
StageBackground.PARALLAX = 0.09
-- Exponential velocity smoothing for weighty deep-space drift.
StageBackground.SMOOTHING = 5.0
-- Subtle atmospheric tint so foreground ships, bullets, and HUD stay legible.
StageBackground.TINT = { 0.88, 0.90, 0.94 }
StageBackground.FALLBACK_COLOR = { 0.018, 0.025, 0.065 }
StageBackground.DEFAULT_IMG_W = 1024
StageBackground.DEFAULT_IMG_H = 571

local function finite(value, fallback)
    if type(value) == "number" and value == value and math.abs(value) < math.huge then
        return value
    end
    return fallback
end

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

-- Frame-rate independent bounded integration in [-1, 1]:
-- Moving toward an edge decelerates smoothly via exponential approach (never clips);
-- moving back toward center responds immediately at full linear speed.
local function advanceBounded(u, du)
    if du == 0 then return u end
    if u * du >= 0 then
        local s = du > 0 and 1 or -1
        local dist = math.max(0, 1 - s * u)
        return clamp(s * (1 - dist * math.exp(-math.abs(du))), -1, 1)
    end
    if math.abs(du) <= math.abs(u) then
        return clamp(u + du, -1, 1)
    end
    local remaining = u + du
    local s = remaining > 0 and 1 or -1
    return clamp(s * (1 - math.exp(-math.abs(remaining))), -1, 1)
end

function StageBackground.indexForLevel(levelNumber, count)
    local total = math.max(1, math.floor(finite(count, #StageBackground.LEVEL_PATHS)))
    local num = math.max(1, math.floor(finite(levelNumber, StageBackground.DEFAULT_LEVEL)))
    return ((num - 1) % total) + 1
end

local function loadImages(paths)
    local images = {}
    if not (love and love.graphics and love.graphics.newImage) then
        return images
    end
    for i = 1, #paths do
        local ok, img = pcall(love.graphics.newImage, paths[i])
        if ok and img then
            if img.setFilter then
                img:setFilter("linear", "linear")
            end
            images[i] = img
        end
    end
    return images
end

function StageBackground.new(width, height, opts)
    opts = opts or {}
    local paths = opts.paths or StageBackground.LEVEL_PATHS
    local images = opts.images or loadImages(paths)
    local self = setmetatable({
        width = math.max(1, finite(width, 1280)),
        height = math.max(1, finite(height, 800)),
        paths = paths,
        images = images,
        level = StageBackground.DEFAULT_LEVEL,
        index = 1,
        u = 0,
        v = 0,
        velX = 0,
        velY = 0,
        overscan = finite(opts.overscan, StageBackground.OVERSCAN),
        parallax = finite(opts.parallax, StageBackground.PARALLAX),
        smoothing = finite(opts.smoothing, StageBackground.SMOOTHING),
    }, StageBackground)
    self:setLevel(opts.level or StageBackground.DEFAULT_LEVEL, true)
    return self
end

function StageBackground:count()
    local n = #self.images
    if n > 0 then return n end
    return #self.paths
end

function StageBackground:setLevel(levelNumber, resetOffset)
    local num = math.max(1, math.floor(finite(levelNumber, StageBackground.DEFAULT_LEVEL)))
    self.level = num
    self.index = StageBackground.indexForLevel(num, self:count())
    if resetOffset then
        self.u, self.v = 0, 0
        self.velX, self.velY = 0, 0
    end
end

function StageBackground:resize(width, height)
    self.width = math.max(1, finite(width, self.width))
    self.height = math.max(1, finite(height, self.height))
end

function StageBackground:imageDimensions(index)
    local img = self.images[index or self.index]
    if img and img.getDimensions then
        local iw, ih = img:getDimensions()
        if iw and ih and iw > 0 and ih > 0 then
            return iw, ih
        end
    elseif type(img) == "table" and img.width and img.height then
        return img.width, img.height
    end
    return StageBackground.DEFAULT_IMG_W, StageBackground.DEFAULT_IMG_H
end

function StageBackground:computeLayout(imgW, imgH, viewW, viewH, u, v)
    viewW = math.max(1, finite(viewW, self.width))
    viewH = math.max(1, finite(viewH, self.height))
    imgW = math.max(1, finite(imgW, StageBackground.DEFAULT_IMG_W))
    imgH = math.max(1, finite(imgH, StageBackground.DEFAULT_IMG_H))
    u = clamp(finite(u, self.u), -1, 1)
    v = clamp(finite(v, self.v), -1, 1)

    local coverScale = math.max(viewW / imgW, viewH / imgH)
    local scale = coverScale * math.max(1, self.overscan)
    local drawW = imgW * scale
    local drawH = imgH * scale
    local marginX = math.max(0, (drawW - viewW) * 0.5)
    local marginY = math.max(0, (drawH - viewH) * 0.5)
    -- Keep a 1px inset inside the overscan margin so bilinear filtering never samples out of bounds.
    local maxShiftX = math.max(0, marginX - 1)
    local maxShiftY = math.max(0, marginY - 1)

    local offsetX = u * maxShiftX
    local offsetY = v * maxShiftY
    local x = (viewW - drawW) * 0.5 + offsetX
    local y = (viewH - drawH) * 0.5 + offsetY

    return {
        x = x,
        y = y,
        scale = scale,
        drawW = drawW,
        drawH = drawH,
        marginX = marginX,
        marginY = marginY,
        maxShiftX = maxShiftX,
        maxShiftY = maxShiftY,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

-- Update slow parallax offset from player world velocity (vx, vy in px/s).
function StageBackground:update(dt, vx, vy, width, height)
    if width or height then
        self:resize(width, height)
    end
    dt = math.max(0, finite(dt, 0))
    if dt <= 0 then return end

    local targetVx = finite(vx, 0)
    local targetVy = finite(vy, 0)
    if self.smoothing > 0 then
        local ease = 1 - math.exp(-self.smoothing * dt)
        self.velX = self.velX + (targetVx - self.velX) * ease
        self.velY = self.velY + (targetVy - self.velY) * ease
        if targetVx == 0 and math.abs(self.velX) < 0.05 then self.velX = 0 end
        if targetVy == 0 and math.abs(self.velY) < 0.05 then self.velY = 0 end
    else
        self.velX, self.velY = targetVx, targetVy
    end

    local imgW, imgH = self:imageDimensions(self.index)
    local layout = self:computeLayout(imgW, imgH, self.width, self.height, self.u, self.v)
    local dx = -self.velX * self.parallax * dt
    local dy = -self.velY * self.parallax * dt
    local du = layout.maxShiftX > 0 and (dx / layout.maxShiftX) or 0
    local dv = layout.maxShiftY > 0 and (dy / layout.maxShiftY) or 0

    self.u = advanceBounded(self.u, du)
    self.v = advanceBounded(self.v, dv)
end

function StageBackground:currentOffset()
    local imgW, imgH = self:imageDimensions(self.index)
    local layout = self:computeLayout(imgW, imgH, self.width, self.height, self.u, self.v)
    return layout.offsetX, layout.offsetY
end

function StageBackground:drawImageAt(index, viewW, viewH, u, v, alpha)
    local img = self.images[index]
    if not img then return false end
    local imgW, imgH = self:imageDimensions(index)
    local layout = self:computeLayout(imgW, imgH, viewW, viewH, u, v)
    local g = love.graphics
    local tint = StageBackground.TINT
    g.setColor(tint[1], tint[2], tint[3], clamp(finite(alpha, 1), 0, 1))
    g.draw(img, layout.x, layout.y, 0, layout.scale, layout.scale)
    return true
end

-- Draws the active level backdrop at the lowest layer.
-- Optional opts: { nextLevel = number, blend = 0..1 } crossfades only when transitioning to a different level.
function StageBackground:draw(width, height, opts)
    local viewW = math.max(1, finite(width, self.width))
    local viewH = math.max(1, finite(height, self.height))
    if not (love and love.graphics) then return end

    local g = love.graphics
    g.push("all")
    g.origin()

    -- Solid deep-space floor underneath in case images are absent or alpha-blended.
    local fb = StageBackground.FALLBACK_COLOR
    g.setColor(fb[1], fb[2], fb[3], 1)
    g.rectangle("fill", 0, 0, viewW, viewH)

    local blend = opts and clamp(finite(opts.blend, 0), 0, 1) or 0
    local nextLevel = opts and opts.nextLevel or nil
    local nextIndex = nextLevel and StageBackground.indexForLevel(nextLevel, self:count()) or nil

    if nextIndex and nextIndex ~= self.index and blend > 0.001 then
        if blend < 0.999 then
            self:drawImageAt(self.index, viewW, viewH, self.u, self.v, 1)
        end
        self:drawImageAt(nextIndex, viewW, viewH, 0, 0, blend)
    else
        self:drawImageAt(self.index, viewW, viewH, self.u, self.v, 1)
    end

    g.pop()
end

return StageBackground
