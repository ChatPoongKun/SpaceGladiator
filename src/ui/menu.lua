local Display = require("src.core.display")
local Theme = require("src.ui.theme")
local Menu = {}
local defaultPanelWidth, inset, buttonHeight, buttonStep, rowHeight = 432, 28, 44, 54, 29

local function rowStep(menu)
    return menu.rows and #menu.rows > 11 and 26 or rowHeight
end

local function layout(menu, width, height)
    local panelWidth = menu.panelWidth or defaultPanelWidth
    local step = rowStep(menu)
    local rowsHeight = menu.rows and #menu.rows * step + 16 or 0
    local buttonCount = menu.buttons and #menu.buttons or 0
    local buttonsHeight = buttonCount > 0 and buttonCount * buttonStep - (buttonStep - buttonHeight) or 0
    local headerHeight = menu.subtitle and 108 or 86
    local panelHeight = headerHeight + rowsHeight + buttonsHeight + inset
    local x = math.floor((width - panelWidth) / 2)
    local y = math.floor((height - panelHeight) / 2)
    return x, y, panelWidth, panelHeight, y + headerHeight, y + headerHeight + rowsHeight, step
end

function Menu.buttonAt(menu, width, height, mouseX, mouseY)
    local x, _, panelWidth, _, _, buttonsY = layout(menu, width, height)
    if mouseX < x + inset or mouseX >= x + panelWidth - inset then return end
    for i = 1, #menu.buttons do
        local y = buttonsY + (i - 1) * buttonStep
        if mouseY >= y and mouseY < y + buttonHeight then return i end
    end
end

function Menu.draw(menu, fonts, selected, width, height, overlay)
    local g = love.graphics
    local c = Theme.colors
    local x, y, panelWidth, panelHeight, rowsY, buttonsY, step = layout(menu, width, height)
    local left, contentWidth = x + inset, panelWidth - 2 * inset
    g.push("all")
    g.setLineWidth(1)
    if overlay then
        local ox, oy, ow, oh = Display.virtualOverscanBounds()
        Theme.setColor(c.bgDeep, 0.72)
        g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))
    end
    Theme.setColor(c.panelBg, 0.96)
    g.rectangle("fill", x, y, panelWidth, panelHeight, 8, 8)
    Theme.setColor(c.panelBorder, 0.95)
    g.rectangle("line", x + 0.5, y + 0.5, panelWidth - 1, panelHeight - 1, 8, 8)
    Theme.setColor(c.accent, 1)
    g.rectangle("fill", left, y, 52, 2)
    -- Subtle corner telemetry accents for visual cohesion with the title screen
    Theme.setColor(c.accent, 0.45)
    g.line(x + panelWidth - 16, y + 1, x + panelWidth - 5, y + 1)
    g.line(x + panelWidth - 1, y + 5, x + panelWidth - 1, y + 16)
    g.setFont(fonts.menuTitle)
    Theme.setColor(c.textHeading, 1)
    g.print(menu.title, left, y + 24)

    if menu.subtitle then
        g.setFont(fonts.menuBody)
        Theme.setColor(c.textSecondary, 1)
        g.print(menu.subtitle, left, y + 75)
    end

    for i, row in ipairs(menu.rows or {}) do
        local rowY = rowsY + (i - 1) * step
        local textX = left + 12
        g.setFont(fonts.menuBody)
        if row.heading then
            Theme.setColor(c.headingBg, 1)
            g.rectangle("fill", left, rowY, contentWidth, step, 3, 3)
            Theme.setColor(c.headingText, 1)
        else
            if row.enemyKind then
                local Enemies = require("src.combat.enemies")
                g.push("all")
                g.translate(textX + 8, rowY + step / 2)
                g.scale(0.38)
                Enemies.drawHull(row.enemyKind, false, 0)
                g.pop()
                textX = textX + 27
            elseif row.vertices then
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
            Theme.setColor(c.rowText, 1)
        end
        local textY = rowY + math.floor((step - fonts.menuBody:getHeight()) / 2)
        g.print(row.label, textX, textY)
        g.printf(row.value, left, textY, contentWidth - 12, "right")
    end

    for i, button in ipairs(menu.buttons or {}) do
        local buttonY = buttonsY + (i - 1) * buttonStep
        local isSelected = (i == selected)
        if isSelected then
            Theme.setColor(c.buttonSelectedBg, 1)
        else
            Theme.setColor(c.buttonBg, 1)
        end
        g.rectangle("fill", left, buttonY, contentWidth, buttonHeight, 5, 5)
        if isSelected then
            Theme.setColor(c.accent, 1)
            g.rectangle("fill", left, buttonY + 6, 3, buttonHeight - 12, 1.5, 1.5)
        end
        if isSelected then
            Theme.setColor(c.accent, 1)
        else
            Theme.setColor(c.buttonBorder, 1)
        end
        g.rectangle("line", left, buttonY, contentWidth, buttonHeight, 5, 5)
        g.setFont(fonts.menuButton)
        local textY = buttonY + math.floor((buttonHeight - fonts.menuButton:getHeight()) / 2)
        local text = type(button.label) == "function" and button.label() or button.label
        Theme.setColor(isSelected and c.textHero or c.textHeading, 1)
        g.print(text, left + (isSelected and 18 or 15), textY)
        if button.value then
            local val = type(button.value) == "function" and button.value() or button.value
            if val and val ~= "" then
                if isSelected then
                    Theme.setColor(c.buttonSelectedValue, 1)
                else
                    Theme.setColor(c.buttonValue, 0.95)
                end
                g.printf(val, left + 15, textY, contentWidth - 30, "right")
            end
        end
    end
    g.pop()
end

return Menu
