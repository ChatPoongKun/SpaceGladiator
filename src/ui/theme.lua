-- Shared UI theme tokens, easing functions, and reusable gradient mesh helpers.
-- Keeps the title screen and modal menus (pause, settings, results) visually cohesive.

local Theme = {}

Theme.colors = {
    bgDeep              = { 0.012, 0.021, 0.045 },
    bgOverlay           = { 0.010, 0.018, 0.040 },
    panelBg             = { 0.035, 0.061, 0.100 },
    panelBorder         = { 0.23,  0.40,  0.47  },
    panelBorderGlow     = { 0.36,  0.86,  0.82  },

    accent              = { 0.36,  0.86,  0.82  },
    accentBright        = { 0.56,  0.97,  0.94  },
    accentSoft          = { 0.18,  0.56,  0.64  },
    accentCool          = { 0.42,  0.74,  0.96  },

    textHero            = { 0.95,  0.99,  1.00  },
    textPrimary         = { 0.88,  0.95,  0.98  },
    textHeading         = { 0.85,  0.94,  0.97  },
    textSecondary       = { 0.66,  0.78,  0.83  },
    textMuted           = { 0.56,  0.70,  0.78  },
    rowText             = { 0.70,  0.80,  0.85  },

    headingBg           = { 0.065, 0.150, 0.190 },
    headingText         = { 0.55,  0.91,  0.89  },

    buttonBg            = { 0.066, 0.130, 0.180 },
    buttonBorder        = { 0.25,  0.43,  0.49  },
    buttonSelectedBg    = { 0.12,  0.32,  0.34  },
    buttonValue         = { 0.58,  0.80,  0.86  },
    buttonSelectedValue = { 0.46,  0.95,  0.90  },

    danger              = { 0.88,  0.26,  0.28  },
    dangerBright        = { 1.00,  0.44,  0.42  },
    dangerBg            = { 0.16,  0.045, 0.060 },
    dangerSelectedBg    = { 0.34,  0.085, 0.105 },
    dangerBorder        = { 0.62,  0.21,  0.24  },
    dangerText          = { 0.96,  0.66,  0.66  },
    dangerSelectedText  = { 1.00,  0.92,  0.92  },
}

function Theme.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Theme.lerp(a, b, t)
    return a + (b - a) * t
end

function Theme.expLerp(current, target, speed, dt)
    if not dt or dt <= 0 then return current end
    local factor = 1 - math.exp(-speed * dt)
    return current + (target - current) * factor
end

function Theme.easeOutCubic(t)
    t = Theme.clamp(t, 0, 1)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

function Theme.easeOutQuart(t)
    t = Theme.clamp(t, 0, 1)
    local inv = 1 - t
    return 1 - inv * inv * inv * inv
end

function Theme.easeInCubic(t)
    t = Theme.clamp(t, 0, 1)
    return t * t * t
end

function Theme.smoothstep(edge0, edge1, x)
    if edge1 == edge0 then return x < edge0 and 0 or 1 end
    local t = Theme.clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
end

function Theme.setColor(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], alpha == nil and 1 or alpha)
end

-- Creates a normalized [0..1]x[0..1] gradient Mesh from color stops:
-- stops = { { pos = 0..1, r, g, b, a }, ... }
-- horizontal = true builds left->right gradient; false builds top->bottom.
function Theme.createGradientMesh(stops, horizontal)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    local verts = {}
    for _, s in ipairs(stops) do
        local p = Theme.clamp(s.pos or 0, 0, 1)
        local r, g, b, a = s[1] or 0, s[2] or 0, s[3] or 0, s[4] == nil and 1 or s[4]
        if horizontal then
            verts[#verts + 1] = { p, 0, p, 0, r, g, b, a }
            verts[#verts + 1] = { p, 1, p, 1, r, g, b, a }
        else
            verts[#verts + 1] = { 0, p, 0, p, r, g, b, a }
            verts[#verts + 1] = { 1, p, 1, p, r, g, b, a }
        end
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "strip", "static")
    if ok then return mesh end
    return nil
end

function Theme.drawGradientRect(mesh, x, y, w, h, alpha)
    if not mesh or w <= 0 or h <= 0 then return end
    local g = love.graphics
    g.setColor(1, 1, 1, alpha == nil and 1 or alpha)
    g.draw(mesh, x, y, 0, w, h)
end

-- Creates a soft 2D radial/elliptical gradient fan mesh centered at (0, 0) with radius 1,
-- so atmospheric halos behind text have zero visible rectangular seams on any edge.
function Theme.createRadialGradientMesh(r, g, b, centerAlpha, midAlpha, segments)
    if not (love and love.graphics and love.graphics.newMesh) then
        return nil
    end
    segments = math.max(16, segments or 36)
    local verts = {
        { 0, 0, 0.5, 0.5, r, g, b, centerAlpha or 0.45 },
    }
    for i = 0, segments do
        local ang = (i / segments) * math.pi * 2
        local cx, cy = math.cos(ang), math.sin(ang)
        verts[#verts + 1] = { cx, cy, 0.5 + cx * 0.5, 0.5 + cy * 0.5, r, g, b, 0 }
    end
    local ok, mesh = pcall(love.graphics.newMesh, verts, "fan", "static")
    if ok then return mesh end
    return nil
end

function Theme.drawRadialHalo(mesh, cx, cy, rx, ry, alpha)
    if not mesh or rx <= 0 or ry <= 0 then return end
    local g = love.graphics
    g.setColor(1, 1, 1, alpha == nil and 1 or alpha)
    g.draw(mesh, cx, cy, 0, rx, ry)
end

return Theme
