-- Unified 4-tier item rarity definitions and color palette.
-- All modules and support chips share a single color system driven strictly by rarity.

local Rarity = {}

Rarity.order = { "NORMAL", "UNCOMMON", "RARE", "LEGENDARY" }

Rarity.defs = {
    NORMAL = {
        id = "NORMAL",
        name = "노멀",
        color = { 0.72, 0.76, 0.82 }, -- #B8C2D1 (Gray)
    },
    UNCOMMON = {
        id = "UNCOMMON",
        name = "언커먼",
        color = { 0.38, 0.74, 1.00 }, -- #61BDFF (Blue)
    },
    RARE = {
        id = "RARE",
        name = "레어",
        color = { 1.00, 0.85, 0.30 }, -- #FFD94D (Yellow)
    },
    LEGENDARY = {
        id = "LEGENDARY",
        name = "레전드리",
        color = { 1.00, 0.38, 0.38 }, -- #FF6161 (Red)
    },
}

local aliases = {
    COMMON = "NORMAL",
}

function Rarity.normalize(id)
    local key = type(id) == "string" and string.upper(id) or "NORMAL"
    key = aliases[key] or key
    if Rarity.defs[key] then
        return key
    end
    return "NORMAL"
end

function Rarity.get(id)
    return Rarity.defs[Rarity.normalize(id)]
end

function Rarity.getColor(id)
    return Rarity.get(id).color
end

function Rarity.getLabel(id)
    return Rarity.get(id).name
end

return Rarity
