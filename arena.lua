local Arena = { width = 1080, height = 540 }

function Arena.draw(boost)
    local g = love.graphics
    g.push("all")
    g.setColor(0.045, 0.105, 0.15, 0.30)
    g.rectangle("fill", 0, 0, Arena.width, Arena.height)

    g.setLineWidth(1)
    g.setColor(0.24, 0.46, 0.60, 0.14)
    for x = 60, Arena.width - 1, 60 do g.line(x, 0, x, Arena.height) end
    for y = 60, Arena.height - 1, 60 do g.line(0, y, Arena.width, y) end

    g.setColor(0.26, 0.65, 0.78, 0.42 + boost * 0.30)
    g.setLineWidth(2)
    g.rectangle("line", 0, 0, Arena.width, Arena.height)
    g.setColor(0.38, 0.78, 0.88, 0.22)
    g.rectangle("line", -5, -5, Arena.width + 10, Arena.height + 10)
    g.setColor(0.49, 0.87, 0.97, 0.9)
    g.setLineWidth(3)
    for _, x in ipairs({0, Arena.width}) do
        for _, y in ipairs({0, Arena.height}) do
            g.line(x + (x == 0 and 28 or -28), y, x, y, x, y + (y == 0 and 28 or -28))
        end
    end
    g.pop()
end

return Arena
