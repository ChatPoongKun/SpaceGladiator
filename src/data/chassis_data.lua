-- Ship chassis definitions for the Armory assembly system.
-- Each chassis defines its base hull/armor (and optional future shield or special
-- effects) plus the grid shape overlaid on top of the ship silhouette.

local ChassisData = {}

ChassisData.DEFAULT_ID = "striker"

ChassisData.list = {
    {
        id = "striker",
        code = "STR-01",
        name = "스트라이커 MK-I",
        locked = false,
        description = "균형 잡힌 삼각 날개 구조의 표준 글래디에이터 섀시. 기본 장갑과 선체만 제공하며 모듈 조립으로 완성됩니다.",
        specialEffect = nil,
        baseStats = {
            maxShield = 0,
            maxArmor = 40,
            maxHull = 3,
            maxBattery = 0,
            batteryRecharge = 0,
            maxSpeed = 0,
            thrust = 0,
            boostThrust = 0,
            boostSpeed = 0,
            boostCost = 0,
            thrustBatteryCost = 0,
            shieldRegen = 0,
            shieldRegenBatteryCost = 0,
            shieldRegenDelay = 2.0,
            wrapBonusSpeed = 0,
            turnSpeed = 4.5,
            brake = 2.5,
        },
        grid = {
            rows = 3,
            cols = 5,
            mask = {
                { 0, 0, 1, 0, 0 },
                { 0, 1, 1, 1, 0 },
                { 1, 1, 1, 1, 1 },
            },
        },
    },
    {
        id = "mystery_1",
        code = "???",
        name = "???",
        locked = true,
        description = "미확인 섀시 데이터. 추후 특수 효과 및 실드 특화 기체가 추가될 예정입니다.",
        specialEffect = "???",
        baseStats = nil,
        grid = {
            rows = 3,
            cols = 5,
            mask = {
                { 0, 0, 1, 0, 0 },
                { 0, 1, 1, 1, 0 },
                { 1, 1, 1, 1, 1 },
            },
        },
    },
}

ChassisData.byId = {}
for i, def in ipairs(ChassisData.list) do
    def.index = i
    ChassisData.byId[def.id] = def
end

function ChassisData.get(id)
    if id and ChassisData.byId[id] then
        return ChassisData.byId[id]
    end
    return ChassisData.byId[ChassisData.DEFAULT_ID]
end

function ChassisData.getUnlockedDefault()
    for _, def in ipairs(ChassisData.list) do
        if not def.locked then
            return def
        end
    end
    return ChassisData.list[1]
end

function ChassisData.nextIndex(currentIndex, dir)
    local count = #ChassisData.list
    if count == 0 then return 1 end
    local idx = math.floor(tonumber(currentIndex) or 1)
    local step = (dir and dir < 0) and -1 or 1
    return ((idx - 1 + step) % count) + 1
end

return ChassisData
