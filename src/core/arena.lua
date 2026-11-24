local Arena = { width = 1280, height = 720, baseWidth = 1280, baseHeight = 720 }

-- Keep the playable arena fixed in logical world units so ship speeds, wrap distances,
-- weapon ranges, and combat geometry remain identical across all resolutions and aspect ratios.
function Arena.resize()
    Arena.width = Arena.baseWidth
    Arena.height = Arena.baseHeight
end

function Arena.draw()
end

return Arena
