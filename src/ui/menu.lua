local Display = require("src.core.display")
local Theme = require("src.ui.theme")
local Menu = {}
local defaultPanelWidth, inset, buttonHeight, buttonGap, rowHeight = 432, 28, 44, 10, 29
local compactButtonHeight, dividerGap = 34, 20

local function rowStep(menu)
    return menu.rows and #menu.rows > 11 and 26 or rowHeight
end

local function computeButtonRects(menu, left, contentWidth, buttonsY)
    local rects = {}
    local dividers = {}
    local curY = buttonsY
    local buttons = menu.buttons or {}
    for i, button in ipairs(buttons) do
        if i > 1 then
            if button.dividerBefore then
                dividers[#dividers + 1] = curY + math.floor(dividerGap * 0.5)
                curY = curY + dividerGap
            else
                curY = curY + buttonGap
            end
        end
        local isCompact = (button.compact == true)
        local bh = isCompact and compactButtonHeight or buttonHeight
        local bw = contentWidth
        local bx = left
        if isCompact then
            bw = math.min(contentWidth, math.max(196, math.floor(contentWidth * 0.48)))
            bx = left + contentWidth - bw
        end
        rects[i] = {
            x = bx,
            y = curY,
            w = bw,
            h = bh,
            compact = isCompact,
        }
        curY = curY + bh
    end
    local totalHeight = #rects > 0 and (curY - buttonsY) or 0
    return rects, dividers, totalHeight
end

local function layout(menu, width, height)
    local panelWidth = menu.panelWidth or defaultPanelWidth
    local step = rowStep(menu)
    local rowsHeight = menu.rows and #menu.rows * step + 16 or 0
    local left, contentWidth = 0, panelWidth - 2 * inset
    local _, _, buttonsHeight = computeButtonRects(menu, left, contentWidth, 0)
    local headerHeight = menu.subtitle and 108 or 86
    local panelHeight = headerHeight + rowsHeight + buttonsHeight + inset
    local x = math.floor((width - panelWidth) / 2)
    local y = math.floor((height - panelHeight) / 2)
    local rowsY = y + headerHeight
    local buttonsY = rowsY + rowsHeight
    local buttonRects, dividers = computeButtonRects(menu, x + inset, contentWidth, buttonsY)
    return x, y, panelWidth, panelHeight, rowsY, buttonsY, step, buttonRects, dividers
end

function Menu.buttonAt(menu, width, height, mouseX, mouseY)
    local _, _, _, _, _, _, _, buttonRects = layout(menu, width, height)
    for i, rect in ipairs(buttonRects) do
        if mouseX >= rect.x and mouseX < rect.x + rect.w
            and mouseY >= rect.y and mouseY < rect.y + rect.h then
            return i
        end
    end
end

function Menu.draw(menu, fonts, selected, width, height, overlay)
    local g = love.graphics
    local c = Theme.colors
    local x, y, panelWidth, panelHeight, rowsY, _, step, buttonRects, dividers = layout(menu, width, height)
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
        Theme.setColor(menu.subtitleColor or c.textSecondary, 1)
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

    for _, divY in ipairs(dividers) do
        Theme.setColor(c.panelBorder, 0.38)
        g.line(left, divY + 0.5, left + contentWidth, divY + 0.5)
    end

    for i, button in ipairs(menu.buttons or {}) do
        local rect = buttonRects[i]
        local isSelected = (i == selected)
        local isDanger = (button.danger == true)
        local isCompact = rect.compact

        if isDanger then
            Theme.setColor(isSelected and c.dangerSelectedBg or c.dangerBg, 1)
        else
            Theme.setColor(isSelected and c.buttonSelectedBg or c.buttonBg, 1)
        end
        g.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 5, 5)

        if isSelected then
            Theme.setColor(isDanger and c.dangerBright or c.accent, 1)
            g.rectangle("fill", rect.x, rect.y + 5, 3, rect.h - 10, 1.5, 1.5)
        end

        if isDanger then
            Theme.setColor(isSelected and c.dangerBright or c.dangerBorder, 1)
        else
            Theme.setColor(isSelected and c.accent or c.buttonBorder, 1)
        end
        g.rectangle("line", rect.x, rect.y, rect.w, rect.h, 5, 5)

        local font = isCompact and (fonts.menuBody or fonts.menuSmall) or fonts.menuButton
        g.setFont(font)
        local textY = rect.y + math.floor((rect.h - font:getHeight()) / 2)
        local text = type(button.label) == "function" and button.label() or button.label
        if isDanger then
            Theme.setColor(isSelected and c.dangerSelectedText or c.dangerText, 1)
        else
            Theme.setColor(isSelected and c.textHero or c.textHeading, 1)
        end
        if isCompact then
            local textX = rect.x + math.floor((rect.w - font:getWidth(text)) * 0.5)
            g.print(text, textX, textY)
        else
            g.print(text, rect.x + (isSelected and 18 or 15), textY)
        end
        if button.value then
            local val = type(button.value) == "function" and button.value() or button.value
            if val and val ~= "" then
                if isSelected then
                    Theme.setColor(c.buttonSelectedValue, 1)
                else
                    Theme.setColor(c.buttonValue, 0.95)
                end
                g.printf(val, rect.x + 15, textY, rect.w - 30, "right")
            end
        end
    end
    g.pop()
end

local function confirmLayout(dialog, width, height)
    local mw = math.min(dialog.panelWidth or 480, width - 64)
    local mh = dialog.panelHeight or 214
    local mx = math.floor((width - mw) * 0.5)
    local my = math.floor((height - mh) * 0.5)
    local buttons = dialog.buttons or {}
    local count = #buttons
    local btnW, btnH, gap = 152, 38, 16
    local totalW = count > 0 and (count * btnW + (count - 1) * gap) or 0
    local startX = mx + math.floor((mw - totalW) * 0.5)
    local btnY = my + mh - btnH - 22
    local rects = {}
    for i = 1, count do
        rects[i] = {
            x = startX + (i - 1) * (btnW + gap),
            y = btnY,
            w = btnW,
            h = btnH,
        }
    end
    return mx, my, mw, mh, rects
end

function Menu.confirmButtonAt(dialog, width, height, mouseX, mouseY)
    if not dialog then return nil end
    local _, _, _, _, rects = confirmLayout(dialog, width, height)
    for i, rect in ipairs(rects) do
        if mouseX >= rect.x and mouseX < rect.x + rect.w
            and mouseY >= rect.y and mouseY < rect.y + rect.h then
            return i
        end
    end
    return nil
end

function Menu.drawConfirm(dialog, fonts, selected, width, height)
    if not dialog then return end
    local g = love.graphics
    local c = Theme.colors
    local mx, my, mw, mh, rects = confirmLayout(dialog, width, height)
    local ox, oy, ow, oh = Display.virtualOverscanBounds()

    g.push("all")
    -- Dark modal scrim blocking background UI
    Theme.setColor(c.bgDeep, 0.78)
    g.rectangle("fill", math.min(0, ox), math.min(0, oy), math.max(width, ow), math.max(height, oh))

    -- Modal container
    g.setColor(0.055, 0.036, 0.058, 0.98)
    g.rectangle("fill", mx, my, mw, mh, 10, 10)
    Theme.setColor(c.dangerBright, 0.92)
    g.setLineWidth(1.8)
    g.rectangle("line", mx + 0.5, my + 0.5, mw - 1, mh - 1, 10, 10)
    Theme.setColor(c.danger, 1)
    g.rectangle("fill", mx + 24, my, 56, 2)

    -- Warning badge + title
    local iconX, iconY = mx + 36, my + 34
    Theme.setColor(c.danger, 0.24)
    g.circle("fill", iconX, iconY, 14)
    Theme.setColor(c.dangerBright, 0.95)
    g.setLineWidth(1.5)
    g.circle("line", iconX, iconY, 14)

    local headerFont = fonts.menuButton or fonts.menuBody
    g.setFont(headerFont)
    Theme.setColor(c.dangerSelectedText, 1)
    local bangW = headerFont:getWidth("!")
    g.print("!", math.floor(iconX - bangW * 0.5), math.floor(iconY - headerFont:getHeight() * 0.5))

    Theme.setColor(c.dangerBright, 1)
    g.print(dialog.title or "경고", mx + 60, math.floor(iconY - headerFont:getHeight() * 0.5))

    Theme.setColor(c.dangerBorder, 0.55)
    g.setLineWidth(1)
    g.line(mx + 20, my + 58, mx + mw - 20, my + 58)

    -- Body lines (centered with g.print for consistent glyph checks)
    local bodyFont = fonts.menuBody or fonts.body
    g.setFont(bodyFont)
    local msgY = my + 78
    if dialog.message then
        Theme.setColor(c.textPrimary, 1)
        local msgX = mx + math.floor((mw - bodyFont:getWidth(dialog.message)) * 0.5)
        g.print(dialog.message, msgX, msgY)
        msgY = msgY + bodyFont:getHeight() + 10
    end
    if dialog.warning then
        Theme.setColor(c.dangerBright, 0.96)
        local warnX = mx + math.floor((mw - bodyFont:getWidth(dialog.warning)) * 0.5)
        g.print(dialog.warning, warnX, msgY)
    end

    -- Confirm / Cancel buttons
    local btnFont = fonts.menuBody or fonts.menuButton
    g.setFont(btnFont)
    for i, button in ipairs(dialog.buttons or {}) do
        local rect = rects[i]
        local isSelected = (i == selected)
        local isDanger = (button.danger == true)
        if isDanger then
            Theme.setColor(isSelected and c.dangerSelectedBg or c.dangerBg, 1)
        else
            Theme.setColor(isSelected and c.buttonSelectedBg or c.buttonBg, 1)
        end
        g.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)

        if isDanger then
            Theme.setColor(isSelected and c.dangerBright or c.dangerBorder, 1)
        else
            Theme.setColor(isSelected and c.accent or c.buttonBorder, 1)
        end
        g.setLineWidth(isSelected and 1.6 or 1.1)
        g.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6, 6)

        local label = type(button.label) == "function" and button.label() or button.label
        if isDanger then
            Theme.setColor(isSelected and c.dangerSelectedText or c.dangerText, 1)
        else
            Theme.setColor(isSelected and c.textHero or c.textHeading, 1)
        end
        local tx = rect.x + math.floor((rect.w - btnFont:getWidth(label)) * 0.5)
        local ty = rect.y + math.floor((rect.h - btnFont:getHeight()) * 0.5)
        g.print(label, tx, ty)
    end
    g.pop()
end

return Menu
