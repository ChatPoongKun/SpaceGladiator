-- Module definitions for the ship chassis grid inventory.
-- Categories: weapon (무기), defense (방호), thruster (추진기), generator (제너레이터).
-- Each module has a grid shape (list of 0-indexed {dr, dc} cells), a bounding
-- box (w x h), batteryLoad (output draw), and a socket layout (1 open socket per cell).

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
        fireInterval = 0.18,
        w = 1,
        h = 2,
        shape = { { 0, 0 }, { 1, 0 } },
        maxSockets = 2,
        batteryLoad = 8,
        baseBatteryCost = 0,
        description = "기본 3발 확산탄 (0.18초 간격). 발사 시 배터리 소모가 없고 출력 부하가 낮아 안정적입니다.",
    },
    {
        id = "missile",
        name = "중형 미사일 포드",
        category = "weapon",
        rarity = "RARE",
        weaponIndex = 2,
        fireInterval = 0.55,
        w = 2,
        h = 2,
        shape = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 } },
        maxSockets = 4,
        batteryLoad = 18,
        baseBatteryCost = 4,
        description = "곡선 궤적 폭발 로켓 (0.55초 간격). 2x2 공간을 차지하지만 광역 폭발과 최대 4소켓 포텐셜을 가집니다.",
    },
    {
        id = "laser",
        name = "레이저 이미터",
        category = "weapon",
        rarity = "RARE",
        weaponIndex = 3,
        fireInterval = 0.34,
        w = 1,
        h = 3,
        shape = { { 0, 0 }, { 1, 0 }, { 2, 0 } },
        maxSockets = 3,
        batteryLoad = 16,
        baseBatteryCost = 3,
        description = "즉시 타격 레이저 빔 (0.34초 간격). 일렬 3소켓 구조로 굴절·연발 조합에 특화됩니다.",
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
        batteryLoad = 14,
        stats = { maxShield = 50 },
        description = "최대 실드 +50. 선체와 장갑을 보호하는 에너지 실드를 생성합니다.",
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
        batteryLoad = 4,
        stats = { maxArmor = 50 },
        description = "최대 장갑 +50. 낮은 전력 부하로 기체의 내구력을 크게 보강합니다.",
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
        batteryLoad = 10,
        activationBatteryCost = 25,
        stats = { maxSpeed = 250, thrust = 350, boostSpeed = 450, wrapBonusSpeed = 110, boostCost = 25 },
        stackStats = { maxSpeed = 35, thrust = 45, boostSpeed = 65, wrapBonusSpeed = 35 },
        description = "1x1 메인 추진 모듈. 기본 기동·부스트(소모 25)를 제공하며 추가 장착 시 기동력이 상승합니다.",
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
        batteryLoad = 0,
        stats = { maxBattery = 100, batteryOutput = 50, batteryRecharge = 12 },
        description = "출력 +50, 배터리 총량 +100, 초당 충전 +12. 기체 전체 부품에 전력을 공급합니다.",
    },
}

ModulesData.byId = {}
for _, def in ipairs(ModulesData.list) do
    def.rarity = Rarity.normalize(def.rarity)
    def.batteryLoad = def.batteryLoad or 0
    def.image = def.image or ("assets/items/modules/" .. def.id .. ".png")
    ModulesData.byId[def.id] = def
end

function ModulesData.get(id)
    if id == "generator" then
        return ModulesData.byId["battery"]
    end
    return ModulesData.byId[id]
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
