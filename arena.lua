local Arena = { width = 1280, height = 800, baseWidth = 1280, baseHeight = 800 }

function Arena.resize(w, h)
    if not w or not h or w <= 0 or h <= 0 then return end
    local scale = math.min(w / Arena.baseWidth, h / Arena.baseHeight)
    Arena.width = w / scale
    Arena.height = h / scale
end

function Arena.draw(boost, fever)
    local g = love.graphics
    local f = fever or 0
    g.push("all")
    g.setColor(0.045 + f * 0.05, 0.105 + f * 0.01, 0.15 - f * 0.04, 0.30 + f * 0.06)
    g.rectangle("fill", 0, 0, Arena.width, Arena.height)

    g.setLineWidth(1)
    g.setColor(0.24 + f * 0.72, 0.46 + f * 0.28, 0.60 - f * 0.36, 0.14 + f * 0.10)
    for x = 60, Arena.width - 1, 60 do g.line(x, 0, x, Arena.height) end
    for y = 60, Arena.height - 1, 60 do g.line(0, y, Arena.width, y) end

    g.setColor(0.26 + f * 0.74, 0.65 + f * 0.18, 0.78 - f * 0.48, 0.42 + boost * 0.30 + f * 0.24)
    g.setLineWidth(2 + f * 1.2)
    g.rectangle("line", 0, 0, Arena.width, Arena.height)
    g.setColor(0.38 + f * 0.62, 0.78 - f * 0.36, 0.88 - f * 0.24, 0.22 + f * 0.24)
    g.rectangle("line", -5, -5, Arena.width + 10, Arena.height + 10)
    g.setColor(0.49 + f * 0.51, 0.87 + f * 0.07, 0.97 - f * 0.52, 0.9 + f * 0.1)
    g.setLineWidth(3)
    for _, x in ipairs({0, Arena.width}) do
        for _, y in ipairs({0, Arena.height}) do
            g.line(x + (x == 0 and 28 or -28), y, x, y, x, y + (y == 0 and 28 or -28))
        end
    end
    g.pop()
end

return Arena
