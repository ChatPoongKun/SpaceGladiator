-- Module definitions for the ship chassis grid inventory.
-- Categories: weapon (무기), defense (방호), thruster (추진기), generator (제너레이터).
-- Each module has a grid shape (list of 0-indexed {dr, dc} cells), a bounding
-- box (w x h), and a socket layout (1 open socket per cell).

local Rarity = require("src.data.rarity")

local ModulesData = {}

ModulesData.categories = {
    { id = "weapon", name = "무기", tag = "WPN" },
    { id = "defense", name = "방호", tag = "DEF" },
    { id = "thruster", name = "추진기", tag = "THR" },
    { id = "generator", name = "제너레이터", tag = "GEN" },
}

ModulesData.categoryById = {}
for i, cat in ipairs(ModulesData.categories) do
    cat.order = i
    ModulesData.categoryById[cat.id] = cat
end

ModulesData.list = {
    {
        id = "projectile",
        name = "확산탄 포탑",
        category = "weapon",
        rarity = "NORMAL",
        weaponIndex = 1,
        fireMode = "projectile",
        projectileStyle = "twin_dart",
        impactStyle = "scatter_ring",
        fireSfx = "projectile",
        impactSfx = "impact",
        damage = 5,
        shotCount = 3,
        fireInterval = 0.18,
        spreadDeg = 5,
        projectileSpeed = 900,
        projectileRange = 600,
        w = 1,
        h = 2,
        shape = { { 0, 0 }, { 1, 0 } },
        maxSockets = 2,
        weight = 20,
        baseBatteryCost = 0,
        description = "기본 3발 확산탄 (피해 5, 0.18초 간격). 발사 시 배터리 소모 없이 안정적으로 사격합니다.",
    },
    {
        id = "missile",
        name = "중형 미사일 포드",
        category = "weapon",
        rarity = "RARE",
        weaponIndex = 2,
        fireMode = "rocket",
        projectileStyle = "salvo_lance",
        impactStyle = "salvo_spark",
        fireSfx = "missile",
        impactSfx = "impact",
        damage = 5,
        shotCount = 1,
        burstCount = 6,
        burstInterval = 0.1,
        ejectAnglesDeg = { 85, -85, 50, -50, 120, -120 },
        ejectBend = 48,
        fireInterval = 3.0,
        spreadDeg = 10,
        projectileSpeed = 600,
        blastRadius = 90,
        w = 2,
        h = 2,
        shape = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 } },
        maxSockets = 4,
        weight = 45,
        baseBatteryCost = 4,
        description = "3초마다 0.1초 간격으로 6발의 곡선 폭발 로켓을 서로 다른 각도로 사출합니다 (피해 5, 반경 90). 2x2 공간을 차지하지만 광역 폭발과 최대 4소켓 포텐셜을 가집니다.",
    },
    {
        id = "laser",
        name = "레이저 이미터",
        category = "weapon",
        rarity = "RARE",
        weaponIndex = 3,
        fireMode = "beam",
        projectileStyle = "snap_beam",
        impactStyle = "beam_impact",
        fireSfx = "laser",
        impactSfx = "impact",
        damage = 5,
        shotCount = 1,
        fireInterval = 0.34,
        spreadDeg = 7,
        w = 1,
        h = 3,
        shape = { { 0, 0 }, { 1, 0 }, { 2, 0 } },
        maxSockets = 3,
        weight = 35,
        baseBatteryCost = 3,
        description = "즉시 타격 레이저 빔 (피해 5, 0.34초 간격). 일렬 3소켓 구조로 굴절·연발 조합에 특화됩니다.",
    },
    {
        id = "shield",
        name = "펄스 실드",
        category = "defense",
        rarity = "UNCOMMON",
        w = 2,
        h = 1,
        shape = { { 0, 0 }, { 0, 1 } },
        maxSockets = 2,
        weight = 25,
        stats = {
            maxShield = 50,
            shieldRegen = 5,
            shieldRegenBatteryCost = 5,
            shieldRegenDelay = 2.0,
        },
        description = "최대 실드 +50, 피격 2초 후 초당 5 실드 회복(배터리 5/s 소모). 선체와 장갑을 보호합니다.",
    },
    {
        id = "armor",
        name = "반응 장갑",
        category = "defense",
        rarity = "UNCOMMON",
        w = 1,
        h = 2,
        shape = { { 0, 0 }, { 1, 0 } },
        maxSockets = 2,
        weight = 40,
        stats = { maxArmor = 70 },
        description = "최대 장갑 +70. 배터리 소모 없이 기체의 내구력을 크게 보강합니다.",
    },
    {
        id = "thruster",
        name = "드리프트 부스터",
        category = "thruster",
        rarity = "NORMAL",
        w = 1,
        h = 1,
        shape = { { 0, 0 } },
        maxSockets = 1,
        weight = 15,
        stats = { thrust = 350, boostThrust = 1800, wrapBonusSpeed = 110, boostCost = 25, thrustBatteryCost = 2 },
        description = "1x1 메인 추진 모듈. 추진력과 부스트 추진력을 제공하며(최대속력 = 추진력 - 총 무게), 가속 시 2/s, 부스트 시 25의 배터리를 소모합니다.",
    },
    {
        id = "battery",
        name = "코어 제너레이터",
        category = "generator",
        rarity = "UNCOMMON",
        w = 1,
        h = 2,
        shape = { { 0, 0 }, { 1, 0 } },
        maxSockets = 2,
        weight = 25,
        stats = { maxBattery = 100, batteryRecharge = 12 },
        description = "배터리 총량 +100, 초당 충전 +12. 기체 무기와 추진기에 전력을 공급합니다.",
    },
}

ModulesData.byId = {}
ModulesData.byWeaponIndex = {}
for _, def in ipairs(ModulesData.list) do
    def.rarity = Rarity.normalize(def.rarity)
    def.image = def.image or ("assets/items/modules/" .. def.id .. ".png")
    ModulesData.byId[def.id] = def
    if def.weaponIndex then
        ModulesData.byWeaponIndex[def.weaponIndex] = def
    end
end

function ModulesData.get(id)
    if id == "generator" then
        return ModulesData.byId["battery"]
    end
    return ModulesData.byId[id]
end

function ModulesData.getByWeaponIndex(weaponIndex)
    return ModulesData.byWeaponIndex[weaponIndex]
end

function ModulesData.getByCategory(categoryId)
    local result = {}
    for _, def in ipairs(ModulesData.list) do
        if def.category == categoryId then
            result[#result + 1] = def
        end
    end
    return result
end

function ModulesData.getCategoryLabel(categoryId)
    local cat = ModulesData.categoryById[categoryId]
    return cat and cat.name or tostring(categoryId or "")
end

return ModulesData
