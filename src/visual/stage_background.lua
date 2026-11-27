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
StageBackground.TITLE_PATH = "assets/backgrounds/GameTitle.jpg"
StageBackground.DEFAULT_LEVEL = 1

-- Overscan factor ensures every viewport aspect ratio retains smooth parallax
-- travel margin on all four sides without ever exposing image borders.
StageBackground.OVERSCAN = 1.24
StageBackground.TITLE_OVERSCAN = 1.0
-- Subtle zoom-out factor for the farthest backdrop when camera pulls back during boost.
StageBackground.BOOST_ZOOM_OUT = 0.045
-- Maximum pixel shake amplitude for the backdrop during hyperspace warp.
StageBackground.WARP_SHAKE_PX = 8.0
-- Slow parallax relative to player velocity (significantly slower than Starfield layers).
StageBackground.PARALLAX = 0.09
-- Exponential velocity smoothing for weighty deep-space drift.
StageBackground.SMOOTHING = 5.0
-- Subtle atmospheric tint and opacity so foreground ships, bullets, and HUD stay legible.
StageBackground.TINT = { 0.88, 0.90, 0.94 }
StageBackground.ALPHA = 0.80
StageBackground.TITLE_TINT = { 1, 1, 1 }
StageBackground.TITLE_ALPHA = 0.5
StageBackground.TITLE_PLANET_UV = { x = 0.67, y = 0.36, innerRadius = 0.21, outerRadius = 0.32 }
StageBackground.FALLBACK_COLOR = { 0.005, 0.008, 0.015 }
StageBackground.DEFAULT_IMG_W = 1024
StageBackground.DEFAULT_IMG_H = 571

StageBackground.TITLE_FX = {
    mask1 = { 0.67, 0.36, 0.18 }, -- ringed planet
    mask2 = { 0.86, 0.17, 0.10 }, -- spiral galaxy
    amp = 0.0032,
    shimmer = 0.10,
    swirl = 0.0,
}

StageBackground.LEVEL_FX = {
    [1] = {
        mask1 = { 0.17, 0.78, 0.11 }, -- lower-left crescent planet
        mask2 = { 0.0, 0.0, 0.0 },
        amp = 0.0022,
        shimmer = 0.06,
        swirl = 0.0,
    },
    [2] = {
        mask1 = { 0.0, 0.0, 0.0 },
        mask2 = { 0.0, 0.0, 0.0 },
        amp = 0.0028,
        shimmer = 0.08,
        swirl = 0.0,
    },
    [3] = {
        mask1 = { 0.27, 0.56, 0.08 }, -- black hole event horizon core
        mask2 = { 0.0, 0.0, 0.0 },
        amp = 0.0024,
        shimmer = 0.09,
        swirl = 0.0035,
    },
}

local NEBULA_SHADER_CODE = [[
extern number u_time;
extern vec2 u_aspect;
extern vec3 u_mask1;
extern vec3 u_mask2;
extern number u_amp;
extern number u_shimmer;
extern number u_swirl;

float bodyMask(vec2 tc, vec3 mask) {
    if (mask.z <= 0.0) return 1.0;
    float d = length((tc - mask.xy) * u_aspect);
    return smoothstep(mask.z, mask.z + 0.11, d);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float edgeMask = smoothstep(0.0, 0.05, tc.x) * smoothstep(1.0, 0.95, tc.x)
                   * smoothstep(0.0, 0.05, tc.y) * smoothstep(1.0, 0.95, tc.y);
    float nebulaMask = bodyMask(tc, u_mask1) * bodyMask(tc, u_mask2) * edgeMask;

    float wave1 = sin(tc.y * 11.0 + u_time * 0.42 + cos(tc.x * 7.0 - u_time * 0.25));
    float wave2 = cos(tc.x * 9.5 - u_time * 0.36 + sin(tc.y * 8.0 + u_time * 0.29));
    vec2 offset = vec2(wave1, wave2) * (u_amp * nebulaMask);

    if (u_swirl > 0.0 && u_mask1.z > 0.0) {
        vec2 rel = (tc - u_mask1.xy) * u_aspect;
        float r = length(rel);
        float ring = smoothstep(u_mask1.z, u_mask1.z + 0.06, r)
                   * (1.0 - smoothstep(u_mask1.z + 0.14, u_mask1.z + 0.28, r));
        vec2 tang = r > 0.0001 ? vec2(-rel.y, rel.x) / r : vec2(0.0);
        offset += tang * (u_swirl * ring * edgeMask * (0.65 + 0.35 * sin(u_time * 0.6 + r * 28.0)));
    }

    vec2 uv = clamp(tc + offset, vec2(0.0), vec2(1.0));
    vec4 pixel = Texel(tex, uv);

    float luma = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    float shimmer = 0.5 + 0.5 * sin(u_time * 1.15 + tc.x * 13.0 + tc.y * 8.0);
    float boost = 1.0 + u_shimmer * smoothstep(0.38, 0.88, luma) * shimmer * nebulaMask;
    pixel.rgb = min(pixel.rgb * boost, vec3(1.0));

    return pixel * color;
}
]]

local function createTitleShader()
    if not (love and love.graphics and love.graphics.newShader) then
        return nil
    end
    local ok, shader = pcall(love.graphics.newShader, NEBULA_SHADER_CODE)
    if ok and shader then
        return shader
    end
    return nil
end

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

local function loadSingleImage(path)
    if not path or not (love and love.graphics and love.graphics.newImage) then
        return nil
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        if img.setFilter then
            img:setFilter("linear", "linear")
        end
        return img
    end
    return nil
end

local function loadImages(paths)
    local images = {}
    if not (love and love.graphics and love.graphics.newImage) then
        return images
    end
    for i = 1, #paths do
        local img = loadSingleImage(paths[i])
        if img then
            images[i] = img
        end
    end
    return images
end

function StageBackground.new(width, height, opts)
    opts = opts or {}
    local paths = opts.paths or StageBackground.LEVEL_PATHS
    local images = opts.images or loadImages(paths)
    local titlePath = opts.titlePath or StageBackground.TITLE_PATH
    local titleImage = opts.titleImage
    if titleImage == nil then
        titleImage = loadSingleImage(titlePath)
    end
    local self = setmetatable({
        width = math.max(1, finite(width, 1280)),
        height = math.max(1, finite(height, 800)),
        paths = paths,
        images = images,
        titlePath = titlePath,
        titleImage = titleImage,
        titleShader = createTitleShader(),
        titleActive = false,
        time = 0,
        level = StageBackground.DEFAULT_LEVEL,
        index = 1,
        u = 0,
        v = 0,
        velX = 0,
        velY = 0,
        overscan = finite(opts.overscan, StageBackground.OVERSCAN),
        titleOverscan = finite(opts.titleOverscan, StageBackground.TITLE_OVERSCAN),
        parallax = finite(opts.parallax, StageBackground.PARALLAX),
        smoothing = finite(opts.smoothing, StageBackground.SMOOTHING),
        alpha = clamp(finite(opts.alpha, StageBackground.ALPHA), 0, 1),
        titleAlpha = clamp(finite(opts.titleAlpha, StageBackground.TITLE_ALPHA), 0, 1),
    }, StageBackground)
    self:setLevel(opts.level or StageBackground.DEFAULT_LEVEL, true)
    if opts.title then
        self:setTitle(true)
    end
    return self
end

function StageBackground:count()
    local n = #self.images
    if n > 0 then return n end
    return #self.paths
end

function StageBackground:setTitle(resetOffset)
    self.titleActive = true
    if resetOffset ~= false then
        self.u, self.v = 0, 0
        self.velX, self.velY = 0, 0
    end
end

function StageBackground:setLevel(levelNumber, resetOffset)
    local num = math.max(1, math.floor(finite(levelNumber, StageBackground.DEFAULT_LEVEL)))
    self.titleActive = false
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

local function dimensionsOf(img)
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

function StageBackground:imageDimensions(index)
    return dimensionsOf(self.images[index or self.index])
end

function StageBackground:titleDimensions()
    return dimensionsOf(self.titleImage)
end

function StageBackground:computeLayout(imgW, imgH, viewW, viewH, u, v, overscanOverride, shakeX, shakeY)
    viewW = math.max(1, finite(viewW, self.width))
    viewH = math.max(1, finite(viewH, self.height))
    imgW = math.max(1, finite(imgW, StageBackground.DEFAULT_IMG_W))
    imgH = math.max(1, finite(imgH, StageBackground.DEFAULT_IMG_H))
    u = clamp(finite(u, self.u), -1, 1)
    v = clamp(finite(v, self.v), -1, 1)

    local coverScale = math.max(viewW / imgW, viewH / imgH)
    local overscan = math.max(1, finite(overscanOverride, self.overscan))
    local scale = coverScale * overscan
    local drawW = imgW * scale
    local drawH = imgH * scale
    local marginX = math.max(0, (drawW - viewW) * 0.5)
    local marginY = math.max(0, (drawH - viewH) * 0.5)
    -- Keep a 1px inset inside the overscan margin so bilinear filtering never samples out of bounds.
    local maxShiftX = math.max(0, marginX - 1)
    local maxShiftY = math.max(0, marginY - 1)

    local offsetX = clamp(u * maxShiftX + finite(shakeX, 0), -maxShiftX, maxShiftX)
    local offsetY = clamp(v * maxShiftY + finite(shakeY, 0), -maxShiftY, maxShiftY)
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
    self.time = (self.time or 0) + dt

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

local function drawWithShader(self, img, layout, imgW, imgH, fx)
    local g = love.graphics
    local shader = self.titleShader
    if shader and g.setShader and fx then
        if shader.send then
            shader:send("u_time", finite(self.time, 0))
            shader:send("u_aspect", { imgW / math.max(1, imgH), 1 })
            shader:send("u_mask1", fx.mask1 or { 0, 0, 0 })
            shader:send("u_mask2", fx.mask2 or { 0, 0, 0 })
            shader:send("u_amp", finite(fx.amp, 0.0024))
            shader:send("u_shimmer", finite(fx.shimmer, 0.07))
            shader:send("u_swirl", finite(fx.swirl, 0.0))
        end
        g.setShader(shader)
        g.draw(img, layout.x, layout.y, 0, layout.scale, layout.scale)
        g.setShader()
    else
        g.draw(img, layout.x, layout.y, 0, layout.scale, layout.scale)
    end
end

function StageBackground:drawImageAt(index, viewW, viewH, u, v, alpha, overscanOverride, shakeX, shakeY)
    local img = self.images[index]
    if not img then return false end
    local imgW, imgH = self:imageDimensions(index)
    local layout = self:computeLayout(imgW, imgH, viewW, viewH, u, v, overscanOverride, shakeX, shakeY)
    local g = love.graphics
    local tint = StageBackground.TINT
    g.setColor(tint[1], tint[2], tint[3], clamp(finite(alpha, 1), 0, 1))
    local fx = StageBackground.LEVEL_FX[index] or StageBackground.LEVEL_FX[1]
    drawWithShader(self, img, layout, imgW, imgH, fx)
    return true
end

function StageBackground:titlePlanetMask(viewW, viewH, parallaxX, parallaxY)
    if not (self.titleActive and self.titleImage) then
        return nil
    end
    local imgW, imgH = self:titleDimensions()
    local px, py = finite(parallaxX, 0), finite(parallaxY, 0)
    local overscan = (px ~= 0 or py ~= 0) and math.max(self.titleOverscan, 1.024) or self.titleOverscan
    local layout = self:computeLayout(imgW, imgH, viewW, viewH, 0, 0, overscan, px, py)
    local spec = StageBackground.TITLE_PLANET_UV
    return {
        x = layout.x + spec.x * layout.drawW,
        y = layout.y + spec.y * layout.drawH,
        innerRadius = layout.drawH * spec.innerRadius,
        outerRadius = layout.drawH * spec.outerRadius,
    }
end

function StageBackground:drawTitle(viewW, viewH, alpha, parallaxX, parallaxY)
    local img = self.titleImage
    if not img then return false end
    local imgW, imgH = self:titleDimensions()
    local px, py = finite(parallaxX, 0), finite(parallaxY, 0)
    local overscan = (px ~= 0 or py ~= 0) and math.max(self.titleOverscan, 1.024) or self.titleOverscan
    local layout = self:computeLayout(imgW, imgH, viewW, viewH, 0, 0, overscan, px, py)
    local g = love.graphics
    local tint = StageBackground.TITLE_TINT
    g.setColor(tint[1], tint[2], tint[3], clamp(finite(alpha, 1), 0, 1))
    drawWithShader(self, img, layout, imgW, imgH, StageBackground.TITLE_FX)
    return true
end

-- Draws the active level (or main title) backdrop at the lowest layer.
-- Optional opts: { nextLevel = number, blend = 0..1 } crossfades when transitioning to a different level or leaving the title screen.
function StageBackground:draw(width, height, opts)
    local viewW = math.max(1, finite(width, self.width))
    local viewH = math.max(1, finite(height, self.height))
    if not (love and love.graphics) then return end

    local g = love.graphics
    g.push("all")
    g.origin()
    local ox = opts and finite(opts.originX, 0) or 0
    local oy = opts and finite(opts.originY, 0) or 0
    if ox ~= 0 or oy ~= 0 then
        g.translate(ox, oy)
    end

    -- Solid deep-space floor underneath in case images are absent or alpha-blended.
    local fb = StageBackground.FALLBACK_COLOR
    g.setColor(fb[1], fb[2], fb[3], 1)
    g.rectangle("fill", 0, 0, viewW, viewH)

    local blend = opts and clamp(finite(opts.blend, 0), 0, 1) or 0
    local pullback = opts and clamp(finite(opts.pullback, 0), 0, 1) or 0
    local shake = opts and clamp(finite(opts.shake, 0), 0, 1) or 0
    local overscanOverride = pullback > 0 and (self.overscan * (1 - StageBackground.BOOST_ZOOM_OUT * pullback)) or nil
    local shakeX, shakeY = 0, 0
    if shake > 0.001 then
        local t = finite(self.time, 0)
        local amp = StageBackground.WARP_SHAKE_PX * shake
        shakeX = (math.sin(t * 47.0) * 0.65 + math.sin(t * 83.0 + 1.1) * 0.35) * amp
        shakeY = (math.cos(t * 53.0 + 0.7) * 0.65 + math.cos(t * 91.0 + 2.3) * 0.35) * amp
    end
    local nextLevel = opts and opts.nextLevel or nil
    local nextIndex = nextLevel and StageBackground.indexForLevel(nextLevel, self:count()) or nil

    local baseAlpha = clamp(finite(self.alpha, StageBackground.ALPHA), 0, 1)
    local titleAlpha = clamp(finite(self.titleAlpha, StageBackground.TITLE_ALPHA), 0, 1)
    local titlePx = opts and finite(opts.titleParallaxX, 0) or 0
    local titlePy = opts and finite(opts.titleParallaxY, 0) or 0
    local useTitle = self.titleActive and self.titleImage ~= nil
    if useTitle then
        if opts and opts.fadeThroughBlack and nextIndex then
            -- Fade title out to deep-space black first, hold briefly, then fade in the Level 1 backdrop.
            if blend < 0.35 then
                local currAlpha = titleAlpha * (1 - clamp(blend / 0.35, 0, 1))
                if currAlpha > 0.001 then
                    self:drawTitle(viewW, viewH, currAlpha, titlePx, titlePy)
                end
            elseif blend > 0.55 then
                local nextAlpha = baseAlpha * clamp((blend - 0.55) / 0.45, 0, 1)
                if nextAlpha > 0.001 then
                    self:drawImageAt(nextIndex, viewW, viewH, 0, 0, nextAlpha, overscanOverride, shakeX, shakeY)
                end
            end
        elseif nextIndex and blend > 0.001 then
            local nextAlpha = baseAlpha * blend
            if blend < 0.999 then
                local denom = math.max(1e-6, 1 - nextAlpha)
                local currAlpha = clamp((titleAlpha * (1 - blend)) / denom, 0, 1)
                self:drawTitle(viewW, viewH, currAlpha, titlePx, titlePy)
            end
            self:drawImageAt(nextIndex, viewW, viewH, 0, 0, nextAlpha, overscanOverride, shakeX, shakeY)
        else
            self:drawTitle(viewW, viewH, titleAlpha, titlePx, titlePy)
        end
    elseif nextIndex and nextIndex ~= self.index and blend > 0.001 then
        local nextAlpha = baseAlpha * blend
        if blend < 0.999 then
            local denom = math.max(1e-6, 1 - nextAlpha)
            local currAlpha = clamp((baseAlpha * (1 - blend)) / denom, 0, 1)
            self:drawImageAt(self.index, viewW, viewH, self.u, self.v, currAlpha, overscanOverride, shakeX, shakeY)
        end
        self:drawImageAt(nextIndex, viewW, viewH, 0, 0, nextAlpha, overscanOverride, shakeX, shakeY)
    else
        self:drawImageAt(self.index, viewW, viewH, self.u, self.v, baseAlpha, overscanOverride, shakeX, shakeY)
    end

    g.pop()
end

return StageBackground
