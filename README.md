# Space Gladiator

LÖVE2D (`11.5`, Lua/LuaJIT) 기반의 관성 비행 아레나 슈터 & 섀시 그리드 빌드 게임입니다.

---

## 빠른 파일 찾기 (Agent Quick Lookup)

작업하려는 기능에 따라 아래 파일을 바로 열어 확인하세요.

| 작업 / 수정 대상 | 먼저 볼 파일 |
| --- | --- |
| 게임 루프, 화면 상태 머신(`title`/`armory`/`warping`/`playing`/`pause`/`settings`/`stageClear`/`inventory`/`warpSelect`/`gameOver`/`results`/`replay`), 입력 라우팅, 테스트 CLI 진입점 | `main.lua` |
| LÖVE 창 크기·타이틀·VSync·MSAA·활성화 모듈 설정 | `conf.lua` |
| 플레이어 기체 관성 이동, 추력·중량 기반 속도/부스트, 실드 재생/아머/선체, 기체 렌더링 | `src/combat/ship.lua` |
| 플레이어 포탑 조준, 확산탄/6발 일제 사격 미사일/1초 지속 레이저 발사, 서포트 칩 효과 | `src/combat/turret.lua` |
| 적 기체 아키타입(`SPINNER` 포함), 어택 디렉터, 워프·경계 등장 텔레그래프, 조향 AI, 상호 충돌·파괴 | `src/combat/enemies.lua` |
| 적 투사체, 버스트 레이저, 탄막 패턴(`curtain`/`spiral`/`ring`), 그레이즈 연동 및 피격 이펙트 | `src/combat/enemy_fire.lua` |
| 글래디에이터 점수(격파/미사일 회피/곡예 비행), 근접 회피 판정, 피버 모드, 팝업 | `src/combat/gladiator.lua` |
| 스테이지 타이머, 편대 스케줄, 클리어 조건, 레벨 진행 | `src/progression/stage.lua` |
| 스테이지 클리어 배너, 블래스트 셔터, 3개 워프 게이트 보상 선택, 하이퍼스페이스 워프 연출 | `src/progression/stage_transition.lua` |
| 섀시 기반 그리드(5×3 삼각 등) 인벤토리 로직, 장착/소켓/중복 배터리 할증/출격 검증/로드아웃 저장(순수 Lua) | `src/progression/inventory.lua` |
| 기체 섀시 정의(그리드 마스크, 기본 스탯, 잠금 슬롯) | `src/data/chassis_data.lua` |
| 기체 모듈 목록·그리드 형태·소켓·무기/방호/추진기/제너레이터 스탯·발사/피격 SFX 데이터 | `src/data/modules_data.lua` |
| 서포트 칩 목록·대상·수정치(멀티샷/유도/도탄 등) 데이터 | `src/data/chips_data.lua` |
| 4단계 등급(`NORMAL`/`UNCOMMON`/`RARE`/`LEGENDARY`) 정의 및 통합 색상 팔레트 | `src/data/rarity.lua` |
| 전투 원형 HUD(자원 링, 근접 페이드, 상태 표시) | `src/ui/hud.lua` |
| UI 공용 테마 토큰, 이징, 그라데이션 메시 헬퍼 | `src/ui/theme.lua` |
| 타이틀 화면 전용 렌더러, 인트로·선택 보간·워프 전환 모션 | `src/ui/title_screen.lua` |
| 타이틀 화면 배경 실시간 AI 전투 데모(아머리 조립 기체 연동) | `src/ui/title_demo.lua` |
| 일시정지/설정/결과 메뉴 레이아웃 및 버튼 히트 테스트 | `src/ui/menu.lua` |
| AC6 스타일 Holo-Glass 아머리(기체 조립, 스펙 텔레메트리, 출격 검증) UI | `src/ui/armory_ui.lua` |
| 행거(인벤토리) 클릭-앤-드롭 배치·소켓 장착·툴팁 UI(회전 잠금 해제 시 `R` 회전) | `src/ui/inventory_ui.lua` |
| 인게임·리플레이 공용 전투 씬/배경/오버레이 렌더러 및 확장 레이어 레지스트리 | `src/visual/battle_scene.lua` |
| 레벨별 성운 셰이더 배경, 패럴랙스, 부스트/워프 줌·진동 | `src/visual/stage_background.lua` |
| 다층 패럴랙스 별빛 필드 및 워프 스타라이트 | `src/visual/starfield.lua` |
| 논리 아레나 크기(`1280×720`) 상수 | `src/core/arena.lua` |
| 카메라 추적, 부스트 풀백 줌, 화면 흔들림 | `src/core/camera.lua` |
| 연속 원형 진입 충돌 및 축/선분 충돌 수학 | `src/core/collision.lua` |
| 회전 추진(`classic`) / 방향 추진 WASD(`directional`) 조작 방식 관리 및 설정 저장 | `src/core/controls.lua` |
| 가상 해상도(`1280×720`) 16:9 레터박스 뷰포트, 전체창/창/전체화면 모드 전환 및 설정 저장 | `src/core/display.lua` |
| 효과음(SFX) 큐 정의, 보이스 풀, 무기별 피격음·레이저 지속음·선체 피격 순차 큐·리플레이 훅 | `src/audio/sfx.lua` |
| 레벨별 배경음악(BGM) 루프·전환 제어 | `src/audio/bgm.lua` |
| 확장 가능한 레이어 스냅샷 녹화, 하이라이트 구간 선정, 인게임 그래픽·SFX/BGM 연동 리플레이 재생 | `src/replay/replay.lua` |
| 리플레이 영상 렌더링, WAV 오디오 믹싱, FFmpeg MP4 내보내기 | `src/replay/replay_export.lua` |

---

## 디렉터리 구조

```text
Space Gladiator/
├── conf.lua                  # LÖVE 런타임 설정 (루트 필수)
├── main.lua                  # 게임 진입점 및 메인 오케스트레이터 (루트 필수)
├── README.md                 # 프로젝트 구조 및 파일 안내
├── AGENTS.md                 # 에이전트 작업 지침
├── credits.md                # 서드파티 오디오 라이선스 크레딧
├── src/                      # 기능별 게임 소스 코드
│   ├── core/                 # 월드 좌표, 카메라, 충돌 수학, 조작 방식, 디스플레이/뷰포트
│   ├── combat/               # 플레이어 기체, 포탑, 적 AI, 적 탄막, 글래디에이터 스코어/피버
│   ├── progression/          # 스테이지 진행, 셔터/워프 전환, 섀시 그리드 인벤토리 로직
│   ├── data/                 # 섀시, 모듈, 서포트 칩, 등급 정적 데이터 정의
│   ├── ui/                   # HUD, 테마, 타이틀/데모, 메뉴, 아머리 UI, 인벤토리 UI
│   ├── visual/               # 공용 전투 씬 렌더러, 레벨 배경 셰이더/패럴랙스, 별빛 필드
│   ├── audio/                # SFX 및 BGM 컨트롤러
│   └── replay/               # 하이라이트 리플레이 녹화/재생 및 FFmpeg 내보내기
├── assets/                   # 게임 리소스
│   ├── audio/                # SFX(.wav) 및 BGM/(.mp3)
│   ├── backgrounds/          # 타이틀 및 레벨 1~3 배경 이미지
│   ├── fonts/                # UI 폰트 (DriftMenu.ttf, OFL.txt)
│   └── items/                # 모듈(modules/) 및 칩(chips/) 아이콘 이미지
└── tests/                    # 테스트 스크립트 및 UI/기체 목업 (Git 무시)
```

---

## 모듈별 상세 인덱스

모든 모듈은 프로젝트 루트 기준 점 표기법(`require("src.<분류>.<파일명>")`)으로 로드합니다.

### `src/core/` — 엔진 기반 & 수학
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/core/arena.lua` | `src.core.arena` | 논리 전장 크기(`1280×720`) 고정 및 경계 기준 제공 |
| `src/core/camera.lua` | `src.core.camera` | 기체 추적, 부스트 풀백 줌, 셰이크, 랩어라운드 오프셋 |
| `src/core/collision.lua` | `src.core.collision` | Swept circle entry 및 구간 교차 충돌 계산 |
| `src/core/controls.lua` | `src.core.controls` | 회전 추진(`classic`)·방향 추진 WASD(`directional`) 조작 해석 및 `control_settings.txt` 저장 |
| `src/core/display.lua` | `src.core.display` | 16:9 레터박스 가상 뷰포트 변환, 전체창(기본)/창/전체화면 모드 및 설정 저장 |

### `src/combat/` — 전투 & 점수 시스템
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/combat/ship.lua` | `src.combat.ship` | 플레이어 물리(추력·중량 기반 속도/추력 가산 부스트/드리프트), 실드 재생·아머·선체, 모듈 스탯 반영, 렌더링 |
| `src/combat/turret.lua` | `src.combat.turret` | 포탑 회전, 확산탄·6발 각도 일제 사격 미사일·1초 지속 추적 레이저 발사, 서포트 칩 수정치 처리 |
| `src/combat/enemies.lua` | `src.combat.enemies` | 적 기체 정의(`SPINNER` 포함), 어택 디렉터, 워프·경계 등장 텔레그래프, 조향 AI, 질량·속도 상호 충돌 및 파괴 처리 |
| `src/combat/enemy_fire.lua` | `src.combat.enemy_fire` | 적 탄환/버스트 레이저/탄막 패턴(`curtain`/`spiral`/`ring`) 발사, 그레이즈 연동 및 충돌 업데이트 |
| `src/combat/gladiator.lua` | `src.combat.gladiator` | 격파·근접 회피·곡예 비행 점수 계산, 피버(오버드라이브) 게이지 및 시각 효과 |

### `src/progression/` — 스테이지 & 보상·빌드 로직
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/progression/stage.lua` | `src.progression.stage` | 스테이지 타이머, 잔여 적 가드, 편대 수 및 보상 배율 관리 |
| `src/progression/stage_transition.lua` | `src.progression.stage_transition` | 클리어 배너, 블래스트 셔터 개폐, 경계 워프 게이트 3종, 하이퍼스페이스 워프 연출 |
| `src/progression/inventory.lua` | `src.progression.inventory` | 섀시 기반 그리드(5×3 삼각 등) 배치/소켓/중복 카테고리 배터리 할증/출격 검증/임시 보상 트레이/로드아웃 직렬화 순수 로직 |

### `src/data/` — 정적 아이템 데이터
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/data/chassis_data.lua` | `src.data.chassis_data` | 기체 섀시(스트라이커 MK-I 5×3 삼각 그리드 및 잠금 섀시) 기본 스탯과 그리드 마스크 정의 |
| `src/data/modules_data.lua` | `src.data.modules_data` | 무기·방호·추진기·제너레이터 모듈의 형태(`shape`), 소켓 수, 전투/성능 스탯, 발사/피격 SFX·스타일, 등급, 아이콘 경로 |
| `src/data/chips_data.lua` | `src.data.chips_data` | 1×1 서포트 칩(멀티샷, 유도, 도탄, 회피 트리거 등) 정의, 등급 및 수정치 |
| `src/data/rarity.lua` | `src.data.rarity` | 4단계 등급(`NORMAL`/`UNCOMMON`/`RARE`/`LEGENDARY`) 정의 및 통합 색상 팔레트 |

### `src/ui/` — 인터페이스 & 오버레이
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/ui/hud.lua` | `src.ui.hud` | 하단 중앙 원형 네온 글래스 HUD 및 개체 근접 투명화(Proximity Fade) |
| `src/ui/theme.lua` | `src.ui.theme` | UI 공용 색상 토큰, 이징 함수 및 그라데이션 메시 헬퍼 |
| `src/ui/title_screen.lua` | `src.ui.title_screen` | 타이틀 화면 전용 렌더러, 인트로·선택 보간·워프 전환 모션 |
| `src/ui/title_demo.lua` | `src.ui.title_demo` | 타이틀 화면 배경에서 아머리 조립 기체로 진행되는 실시간 AI 전투 데모 |
| `src/ui/menu.lua` | `src.ui.menu` | 공통 패널/버튼 메뉴 렌더러 및 마우스 히트 테스트 |
| `src/ui/armory_ui.lua` | `src.ui.armory_ui` | AC6 스타일 Holo-Glass 아머리(섀시 선택, 모듈 조립, 델타 스펙 텔레메트리, 출격 검증) UI |
| `src/ui/inventory_ui.lua` | `src.ui.inventory_ui` | 행거 섀시 그리드 클릭-앤-드롭, 소켓 장착, 상세 툴팁 UI(회전 잠금 해제 시 `R` 회전) |

### `src/visual/` — 배경 & 공간 연출
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/visual/battle_scene.lua` | `src.visual.battle_scene` | 인게임·리플레이 공용 전투 씬/배경/오버레이 렌더러 및 확장 레이어 레지스트리 |
| `src/visual/stage_background.lua` | `src.visual.stage_background` | 레벨 1~3 배경 이미지 + 성운 모션 셰이더, 속도 기반 패럴랙스, 워프 줌/흔들림 |
| `src/visual/starfield.lua` | `src.visual.starfield` | 다층 별빛 패럴랙스 및 부스트/워프 시 별빛 스트리밍 연출 |

### `src/audio/` — 사운드
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/audio/sfx.lua` | `src.audio.sfx` | `assets/audio/*.wav` 기반 효과음 큐, 폴리포니 풀, 무기별 피격음, 레이저 지속음 페이드아웃, 선체 피격 순차 큐, 리플레이 훅 |
| `src/audio/bgm.lua` | `src.audio.bgm` | `assets/audio/BGM/` 레벨별 BGM 연속 재생 및 일시정지/전환 제어 |

### `src/replay/` — 하이라이트 리플레이
| 파일 | Require 경로 | 역할 |
| --- | --- | --- |
| `src/replay/replay.lua` | `src.replay.replay` | 확장 가능한 레이어 스냅샷 기록, 하이라이트 구간 추출, 인게임 그래픽·SFX/BGM 연동 재생 |
| `src/replay/replay_export.lua` | `src.replay.replay_export` | `BattleScene` 기반 오프라인 프레임 렌더링, `Sfx`/`Bgm` 기반 WAV 믹싱, FFmpeg MP4 내보내기 |

---

## 실행 및 테스트

### 게임 실행
```powershell
& "C:\Program Files\LOVE\love.exe" .
```

### 테스트 실행 (CLI 플래그)
`main.lua`의 `love.load(args)`에서 아래 테스트 플래그를 지원합니다. 변경된 모듈과 직접 관련된 테스트만 선택해 실행하세요.

```powershell
& "C:\Program Files\LOVE\lovec.exe" . --test-inventory   # 섀시 그리드 인벤토리·모듈·칩·기체/포탑 연동
& "C:\Program Files\LOVE\lovec.exe" . --test-armory      # 아머리 UI·섀시·모듈 조립 검증
& "C:\Program Files\LOVE\lovec.exe" . --test-replay      # 리플레이 하이라이트·레이어 스냅샷·인게임 렌더링·WAV 믹싱
& "C:\Program Files\LOVE\lovec.exe" . --test-sfx         # 효과음 큐·지속음·선체 피격 큐잉
& "C:\Program Files\LOVE\lovec.exe" . --test-fullscreen  # 고정 16:9 아레나 뷰포트·해상도 설정
& "C:\Program Files\LOVE\lovec.exe" . --test-controls    # 기본/방향 WASD 조작 방식 전환·조향
& "C:\Program Files\LOVE\lovec.exe" . --test-background  # 레벨 배경 패럴랙스·경계·레이어링
& "C:\Program Files\LOVE\lovec.exe" . --test-title       # 타이틀 화면 레이아웃·모션·AI 데모
& "C:\Program Files\LOVE\lovec.exe" . --test-combat      # 전투 감각·충돌·피격 피드백
& "C:\Program Files\LOVE\lovec.exe" . --test-gladiator   # 글래디에이터 점수·회피·피버
& "C:\Program Files\LOVE\lovec.exe" . --test-flow        # 메뉴·BGM·스테이지·워프 흐름 통합
& "C:\Program Files\LOVE\lovec.exe" . --test             # 일반 아레나 시뮬레이션 및 check.lua (--test-compact / --test-damaged 지원)
```

---

## 코드 배치 규칙

1. `main.lua`와 `conf.lua`는 LÖVE2D 요구사항에 따라 **프로젝트 루트**에 유지합니다.
2. 신규 게임 스크립트는 역할에 맞는 `src/<분류>/` 폴더에 추가하고 `require("src.<분류>.<모듈>")` 형식으로 참조합니다.
3. 테스트 스크립트 및 목업/임시 파일은 `tests/` 폴더 안에 생성합니다(`AGENTS.md` 참조).
