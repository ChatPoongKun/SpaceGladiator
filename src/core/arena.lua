local Arena = { width = 1280, height = 720, baseWidth = 1280, baseHeight = 720 }

-- Keep the playable arena fixed in logical world units so ship speeds, wrap distances,
-- weapon ranges, and combat geometry remain identical across all resolutions and aspect ratios.
function Arena.resize()
    Arena.width = Arena.baseWidth
    Arena.height = Arena.baseHeight
end

function Arena.wrapOffsets(position, extent, reachNeg, reachPos, viewMin, viewMax)
    local neg = reachNeg or 0
    local pos = reachPos ~= nil and reachPos or neg
    local minVisible = viewMin ~= nil and viewMin or 0
    local maxVisible = viewMax ~= nil and viewMax or extent
    local offsets = { 0 }
    if extent > 0 then
        if position - neg <= maxVisible - extent then
            offsets[#offsets + 1] = extent
        end
        if position + pos >= extent + minVisible then
            offsets[#offsets + 1] = -extent
        end
    end
    return offsets
end

function Arena.playerWrapOffsets(ship, turret, camera, screenWidth, screenHeight)
    local destroyed = ship and ship.isDestroyed and ship:isDestroyed()
    local shipReach = destroyed and 90 or (75 + 70 * ((ship and ship.boostLevel) or 0))
    local reachLeft, reachRight, reachTop, reachBottom = shipReach, shipReach, shipReach, shipReach
    if not destroyed and turret then
        local aimLength = turret.aimLineLength and turret:aimLineLength(screenWidth) or 0
        if aimLength > 0 then
            local angle = turret.angle or 0
            local aimDx, aimDy = math.sin(angle), -math.cos(angle)
            if aimDx < 0 then
                reachLeft = math.max(reachLeft, -aimDx * aimLength + 8)
            else
                reachRight = math.max(reachRight, aimDx * aimLength + 8)
            end
            if aimDy < 0 then
                reachTop = math.max(reachTop, -aimDy * aimLength + 8)
            else
                reachBottom = math.max(reachBottom, aimDy * aimLength + 8)
            end
        end
    end
    local viewLeft, viewTop, viewRight, viewBottom = 0, 0, Arena.width, Arena.height
    if camera and camera.screenToWorld and screenWidth and screenHeight then
        viewLeft, viewTop = camera:screenToWorld(0, 0, screenWidth, screenHeight)
        viewRight, viewBottom = camera:screenToWorld(screenWidth, screenHeight, screenWidth, screenHeight)
    end
    local xOffsets = Arena.wrapOffsets(ship.x, Arena.width, reachLeft, reachRight, viewLeft, viewRight)
    local yOffsets = Arena.wrapOffsets(ship.y, Arena.height, reachTop, reachBottom, viewTop, viewBottom)
    return xOffsets, yOffsets, viewLeft, viewTop, viewRight, viewBottom
end

function Arena.draw()
end

return Arena
