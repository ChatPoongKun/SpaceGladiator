-- Support chip definitions (1x1 grid items).
-- Chips can be dropped directly onto a compatible module's socket to
-- modify its behavior, or stored as a 1x1 item on an empty diamond grid cell.

local Rarity = require("src.data.rarity")

local ChipsData = {}

ChipsData.list = {
    -- Weapon firing modifiers (4)
    {
        id = "splitter",
        name = "스플리터 (멀티샷)",
        target = "weapon",
        rarity = "UNCOMMON",
        modifiers = {
            extraCount = 2,
            extraSpreadDeg = 10,
            damageMult = 0.75,
            batteryCost = 5,
        },
        description = "발사체/빔 +2, 확산각 +10도 (피해 x0.75, 배터리 +5)",
    },
    {
        id = "burst",
        name = "버스트 코어 (연발)",
        target = "weapon",
        rarity = "UNCOMMON",
        modifiers = {
            extraBurst = 2,
            cooldownMult = 1.35,
            batteryCost = 6,
        },
        description = "1회 발사 시 3점사 연속 사격 (쿨다운 x1.35, 배터리 +6)",
    },
    {
        id = "ricochet",
        name = "리코셰 프리즘 (굴절)",
        target = "weapon",
        rarity = "UNCOMMON",
        modifiers = {
            bounces = 1,
            batteryCost = 4,
        },
        description = "적 명중 시 가장 가까운 다른 적으로 1회 굴절 (배터리 +4)",
    },
    {
        id = "homing",
        name = "호밍 시커 (유도)",
        target = "weapon",
        rarity = "UNCOMMON",
        modifiers = {
            homing = true,
            homingTurnRate = 4.2,
            batteryCost = 5,
        },
        description = "투사체에 적 유도 부여 및 미사일 선회 강화 (배터리 +5)",
    },

    -- Weapon triggers (3)
    {
        id = "dodge_trigger",
        name = "곡예 트리거",
        target = "weapon",
        rarity = "RARE",
        modifiers = {
            triggerOnDodge = true,
            autoBatteryZero = true,
            manualCooldownMult = 1.5,
        },
        description = "미사일 회피/곡예비행 성공 시 무료 자동 발사 (수동 쿨다운 x1.5)",
    },
    {
        id = "wrap_trigger",
        name = "래핑 콘덴서",
        target = "weapon",
        rarity = "UNCOMMON",
        modifiers = {
            triggerOnWrap = true,
            wrapTriggerCooldown = 1.5,
            areaMult = 1.3,
        },
        description = "아레나 경계 통과 시 자동 발사 + 폭발/범위 +30% (쿨다운 1.5초)",
    },
    {
        id = "hit_trigger",
        name = "피격 반격기",
        target = "weapon",
        rarity = "RARE",
        modifiers = {
            triggerOnHit = true,
            hitTriggerBattery = 15,
            radialCount = 6,
        },
        description = "실드/장갑 피격 시 연결 무기를 360도로 방출 (발동 시 배터리 15)",
    },

    -- Defense / Battery / Thruster chips (3)
    {
        id = "shockwave",
        name = "충격파 방출",
        target = "defense",
        rarity = "NORMAL",
        modifiers = {
            shockwaveOnHit = true,
            shockwaveRadius = 180,
            shockwaveCooldown = 4.0,
        },
        description = "피격 시 반경 180px 적 탄막 제거 및 넉백 (쿨다운 4초)",
    },
    {
        id = "dodge_charge",
        name = "곡예 충전기",
        target = "battery",
        rarity = "NORMAL",
        modifiers = {
            onDodgeBattery = 15,
            rechargeMult = 0.8,
        },
        description = "회피/곡예 성공 시 배터리 +15 즉시 회복 (자연 충전 x0.8)",
    },
    {
        id = "wrap_phase",
        name = "래핑 위상변위",
        target = "thruster",
        rarity = "NORMAL",
        modifiers = {
            wrapSpeedMult = 1.4,
            wrapInvuln = 0.4,
            boostCostAdd = 5,
        },
        description = "경계 통과 시 보너스 속도 +40% 및 0.4초 무적 (부스트 소모 +5)",
    },

    -- Universal / Risk chips (2)
    {
        id = "fever_overdrive",
        name = "피버 과부하",
        target = "any",
        rarity = "LEGENDARY",
        modifiers = {
            feverChipMult = 2.0,
            nonFeverBatteryMult = 1.3,
        },
        description = "FEVER 중 같은 모듈의 다른 칩 수치 효과 2배 (비피버 배터리 x1.3)",
    },
    {
        id = "limiter_off",
        name = "리미터 해제",
        target = "any",
        rarity = "LEGENDARY",
        modifiers = {
            noShield = true,
            cooldownMult = 0.6,
            scoreMult = 1.5,
        },
        description = "실드 최대치 0 고정 대신 쿨다운 -40%, 글래디에이터 포인트 +50%",
    },
}

ChipsData.byId = {}
for _, def in ipairs(ChipsData.list) do
    def.rarity = Rarity.normalize(def.rarity)
    def.w = def.w or 1
    def.h = def.h or 1
    def.shape = def.shape or { { 0, 0 } }
    def.image = def.image or ("assets/items/chips/" .. def.id .. ".png")
    ChipsData.byId[def.id] = def
end

function ChipsData.get(id)
    return ChipsData.byId[id]
end

function ChipsData.isCompatible(chipDef, moduleDef)
    if not chipDef or not moduleDef then return false end
    if chipDef.target == "any" then return true end
    return chipDef.target == moduleDef.category
end

return ChipsData
