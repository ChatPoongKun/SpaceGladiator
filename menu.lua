local Menu = {}
local panelWidth, inset, buttonHeight, buttonStep, rowHeight = 432, 28, 44, 54, 29

local function rowStep(menu)
    return menu.rows and #menu.rows > 11 and 26 or rowHeight
end

local function layout(menu, width, height)
    local step = rowStep(menu)
    local rowsHeight = menu.rows and #menu.rows * step + 16 or 0
    local buttonCount = menu.buttons and #menu.buttons or 0
    local buttonsHeight = buttonCount > 0 and buttonCount * buttonStep - (buttonStep - buttonHeight) or 0
    local headerHeight = menu.subtitle and 108 or 86
    local panelHeight = headerHeight + rowsHeight + buttonsHeight + inset
    local x = math.floor((width - panelWidth) / 2)
    local y = math.floor((height - panelHeight) / 2)
    return x, y, panelHeight, y + headerHeight, y + headerHeight + rowsHeight, step
end

function Menu.buttonAt(menu, width, height, mouseX, mouseY)
    local x, _, _, _, buttonsY = layout(menu, width, height)
    if mouseX < x + inset or mouseX >= x + panelWidth - inset then return end
    for i = 1, #menu.buttons do
        local y = buttonsY + (i - 1) * buttonStep
        if mouseY >= y and mouseY < y + buttonHeight then return i end
    end
end

function Menu.draw(menu, fonts, selected, width, height, overlay)
    local g = love.graphics
    local x, y, panelHeight, rowsY, buttonsY, step = layout(menu, width, height)
    local left, contentWidth = x + inset, panelWidth - 2 * inset
    g.push("all")
    g.setLineWidth(1)
    if overlay then
        g.setColor(0.012, 0.021, 0.045, 0.72)
        g.rectangle("fill", 0, 0, width, height)
    end
    g.setColor(0.035, 0.061, 0.10, 0.98)
    g.rectangle("fill", x, y, panelWidth, panelHeight, 8, 8)
    g.setColor(0.23, 0.40, 0.47, 1)
    g.rectangle("line", x + 0.5, y + 0.5, panelWidth - 1, panelHeight - 1, 8, 8)
    g.setColor(0.36, 0.86, 0.82, 1)
    g.rectangle("fill", left, y, 46, 2)
    g.setFont(fonts.menuTitle)
    g.setColor(0.85, 0.94, 0.97, 1)
    g.print(menu.title, left, y + 24)

    if menu.subtitle then
        g.setFont(fonts.menuBody)
        g.setColor(0.66, 0.78, 0.83, 1)
        g.print(menu.subtitle, left, y + 75)
    end

    for i, row in ipairs(menu.rows or {}) do
        local rowY = rowsY + (i - 1) * step
        local textX = left + 12
        g.setFont(fonts.menuBody)
        if row.heading then
            g.setColor(0.065, 0.15, 0.19, 1)
            g.rectangle("fill", left, rowY, contentWidth, step, 3, 3)
            g.setColor(0.55, 0.91, 0.89, 1)
        else
            if row.vertices then
                g.push()
                g.translate(textX + 8, rowY + step / 2)
                g.scale(0.36)
                g.setLineWidth(2.8)
                g.setColor(1, 0.48, 0.36, 1)
                g.polygon("line", row.vertices)
                g.pop()
                g.setLineWidth(1)
                textX = textX + 27
            end
            g.setColor(0.70, 0.80, 0.85, 1)
        end
        local textY = rowY + math.floor((step - fonts.menuBody:getHeight()) / 2)
        g.print(row.label, textX, textY)
        g.printf(row.value, left, textY, contentWidth - 12, "right")
    end

    for i, button in ipairs(menu.buttons or {}) do
        local buttonY = buttonsY + (i - 1) * buttonStep
        if i == selected then g.setColor(0.12, 0.32, 0.34, 1)
        else g.setColor(0.066, 0.13, 0.18, 1) end
        g.rectangle("fill", left, buttonY, contentWidth, buttonHeight, 5, 5)
        if i == selected then g.setColor(0.36, 0.86, 0.82, 1)
        else g.setColor(0.25, 0.43, 0.49, 1) end
        g.rectangle("line", left, buttonY, contentWidth, buttonHeight, 5, 5)
        g.setFont(fonts.menuButton)
        g.setColor(0.85, 0.94, 0.97, 1)
        local text = type(button.label) == "function" and button.label() or button.label
        g.print(text, left + 15, buttonY + math.floor((buttonHeight - fonts.menuButton:getHeight()) / 2))
    end
    g.pop()
end

return Menu
