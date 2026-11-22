-- Module definitions for the 3x3 -> 5x5 diamond ship grid inventory.
-- Each module has a grid footprint (w x h), a socket layout with Socket 1 as the
-- Core Socket, and an initial set of linked edges. Only sockets reachable from
-- Socket 1 via unlocked links activate their equipped support chips.

local ModulesData = {}

ModulesData.list = {
    {
        id = "projectile",
        name = "확산탄 포탑",
        shortName = "PROJ",
        category = "weapon",
        weaponIndex = 1,
        w = 1,
        h = 2,
        maxSockets = 2,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 } },
        baseBatteryCost = 0,
        color = { 0.34, 0.80, 0.94 },
        description = "기본 3발 확산탄. 가볍고 기본 배터리 소모가 없어 보조 화력으로 유리합니다.",
    },
    {
        id = "missile",
        name = "중형 미사일 포드",
        shortName = "MISL",
        category = "weapon",
        weaponIndex = 2,
        w = 2,
        h = 2,
        maxSockets = 4,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 1, 4 } },
        baseBatteryCost = 4,
        color = { 0.98, 0.56, 0.24 },
        description = "곡선 궤적 폭발 로켓. 2x2 공간을 차지하지만 최대 4소켓 풀링크 포텐셜을 가집니다.",
    },
    {
        id = "laser",
        name = "레이저 이미터",
        shortName = "LASR",
        category = "weapon",
        weaponIndex = 3,
        w = 1,
        h = 3,
        maxSockets = 3,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 }, { 2, 3 } },
        baseBatteryCost = 3,
        color = { 0.38, 0.95, 1.00 },
        description = "즉시 타격 레이저 빔. 일렬 3소켓 구조로 굴절·연발 콤보에 특화됩니다.",
    },
    {
        id = "shield",
        name = "펄스 실드",
        shortName = "SHLD",
        category = "defense",
        w = 2,
        h = 1,
        maxSockets = 2,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 } },
        stats = { maxShield = 40 },
        color = { 0.28, 0.62, 1.00 },
        description = "최대 실드 +40. 피격 반응형 방어 칩을 장착할 수 있습니다.",
    },
    {
        id = "armor",
        name = "반응 장갑",
        shortName = "ARMR",
        category = "defense",
        w = 1,
        h = 2,
        maxSockets = 2,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 } },
        stats = { maxArmor = 50 },
        color = { 0.88, 0.80, 0.58 },
        description = "최대 장갑 +50. 노실드·피격 반격 빌드에서 생존력을 높입니다.",
    },
    {
        id = "battery",
        name = "코어 배터리",
        shortName = "BATT",
        category = "battery",
        w = 1,
        h = 2,
        maxSockets = 2,
        defaultLinks = { { 1, 2 } },
        allLinks = { { 1, 2 } },
        stats = { maxBattery = 40, batteryRecharge = 5 },
        color = { 1.00, 0.74, 0.30 },
        description = "최대 배터리 +40, 초당 충전 +5. 배터리 수급용 칩을 장착할 수 있습니다.",
    },
    {
        id = "thruster",
        name = "드리프트 부스터",
        shortName = "THRS",
        category = "thruster",
        w = 1,
        h = 1,
        maxSockets = 1,
        defaultLinks = {},
        allLinks = {},
        stats = { maxSpeed = 25, boostSpeed = 60, wrapBonusSpeed = 35 },
        color = { 0.42, 0.94, 0.74 },
        description = "1x1 기동 특화 모듈. 최고 속도·부스트·래핑 가속을 강화합니다.",
    },
}

ModulesData.byId = {}
for _, def in ipairs(ModulesData.list) do
    ModulesData.byId[def.id] = def
end

function ModulesData.get(id)
    return ModulesData.byId[id]
end

return ModulesData
