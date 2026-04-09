-- ReplicatedStorage/Shared/Constants
local Constants = {}

-- 미로 크기 (층별)
Constants.MAZE_SIZES = {
    [1] = 6,
    [2] = 7,
    [3] = 8,
    [4] = 9,
}
Constants.MAZE_SIZE_INCREMENT = 1   -- 5층+부터 매 층 +1
Constants.MAZE_SIZE_MAX = 20
Constants.MAX_FLOOR = 100           -- 탑 최대 층 수

-- 플레이어 속도
Constants.PLAYER_BASE_SPEED = 16   -- Roblox 기본값 (studs/s)
Constants.CARROT_SPEED = 24        -- 당근 효과 시 속도
Constants.CARROT_DURATION = 3      -- 당근 효과 지속시간 (초)
Constants.POOP_DURATION   = 15     -- 💩 바닥 표시 지속시간 (초)

-- 추가 헌터
Constants.HUNTER_EXTRA_INTERVAL = 60  -- 추가 헌터 스폰 주기 (초)

-- 사냥꾼 속도 (난이도별)
Constants.HUNTER = {
    Easy   = { baseSpeed = 8,  increment = 0, maxSpeed = 8  },
    Normal = { baseSpeed = 10, increment = 1, maxSpeed = 16 },
    Hard   = { baseSpeed = 13, increment = 2, maxSpeed = 22 },
}
Constants.HUNTER_SIGHT_RANGE = 999 -- (AI 루프 내부에서 난이도별 오버라이드)
Constants.TRAP_STUN_DURATION = 3   -- 함정 스턴 지속시간 (초)
Constants.TRAP_EXCLUSION_RADIUS = 3 -- 출구 근처 함정 설치 불가 반경 (studs)

-- 아이템 스폰 수량
Constants.CARROT_COUNT = 3
Constants.TRAP_COUNT = 2

-- 미로 렌더링
Constants.WALL_SIZE = Vector3.new(30, 10, 30)    -- 통로 유효 폭 ~22 studs (산 모델 두께 고려)
Constants.FLOOR_SIZE = Vector3.new(30, 0.5, 30)  -- 바닥 파트 크기
Constants.WALL_THICKNESS = 6                     -- 벽 두께

-- 색상 팔레트
Constants.COLORS = {
    Wall   = Color3.fromRGB(160, 110, 65),   -- 나무벽 (밝은 목재색)
    Floor  = Color3.fromRGB(120, 90,  55),   -- 흙바닥 (중간 갈색)
    Exit   = Color3.fromRGB(178, 235, 201),  -- 민트 (출구)
    Carrot = Color3.fromRGB(255, 179, 102),  -- 주황 (당근)
    Trap   = Color3.fromRGB(255, 204, 213),  -- 연분홍 (함정)
    Hunter = Color3.fromRGB(30,  20,  20),   -- 거의 검정 (사냥꾼)
    Smoke  = Color3.fromRGB(200, 200, 220),  -- 연막 (연보라-흰색)
}

-- 게임 인원
Constants.MIN_PLAYERS = 2
Constants.MAX_PLAYERS = 8

-- 결과 표시 대기 시간 (초)
Constants.RESULT_DISPLAY_DURATION = 3

-- 연막탄
Constants.SMOKE_COUNT = 1
Constants.SMOKE_DURATION = 10  -- 연막 지속시간 (초)

-- 그래피티 (스프레이 캔)
Constants.SPRAY_COUNT          = 1     -- 시작 시 지급 수량
Constants.GRAFFITI_RANGE       = 14    -- 사용 가능 거리 (studs)
Constants.GRAFFITI_MAX_STAGE   = 20    -- 스테이지당 최대 낙서 수
Constants.GRAFFITI_CANVAS_SIZE = 500   -- SurfaceGui CanvasSize 및 클라이언트 캔버스 공통
Constants.GRAFFITI_PALETTE     = {
    Color3.fromRGB(220,  50,  50),  -- 빨강
    Color3.fromRGB(240, 130,  30),  -- 주황
    Color3.fromRGB(240, 210,  30),  -- 노랑
    Color3.fromRGB( 60, 180,  60),  -- 초록
    Color3.fromRGB( 50, 120, 230),  -- 파랑
    Color3.fromRGB(140,  60, 200),  -- 보라
    Color3.fromRGB(230,  80, 160),  -- 핑크
    Color3.fromRGB(140,  80,  30),  -- 갈색
    Color3.fromRGB( 30,  30,  30),  -- 검정
    Color3.fromRGB(240, 240, 240),  -- 흰색
}

return Constants
