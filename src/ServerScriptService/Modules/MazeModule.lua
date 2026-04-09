-- ServerScriptService/Modules/MazeModule
local MazeModule = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

-- 방향 벡터 (상/하/좌/우)
local DIRECTIONS = {
    {r = -1, c = 0},  -- 위
    {r =  1, c = 0},  -- 아래
    {r =  0, c = -1}, -- 왼쪽
    {r =  0, c = 1},  -- 오른쪽
}

-- 시드 기반 난수 생성기 (LCG, 재현 가능한 미로)
local function makeRNG(seed)
    local s = seed
    return function()
        s = (s * 1664525 + 1013904223) % (2^32)
        return s / (2^32)
    end
end

-- 리스트 무작위 섞기 (Fisher-Yates)
local function shuffle(list, rng)
    local n = #list
    for i = n, 2, -1 do
        local j = math.floor(rng() * i) + 1
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- Recursive Backtracker 미로 생성
-- 반환값: grid[r][c] = { visited=bool, walls={top, bottom, left, right} }
function MazeModule.generate(size, seed)
    local rng = makeRNG(seed)

    -- 그리드 초기화 (모든 벽 있음, 미방문)
    local grid = {}
    for r = 1, size do
        grid[r] = {}
        for c = 1, size do
            grid[r][c] = {
                visited = false,
                walls = {top = true, bottom = true, left = true, right = true}
            }
        end
    end

    -- 재귀 DFS
    local function carve(r, c)
        grid[r][c].visited = true
        local dirs = shuffle({1, 2, 3, 4}, rng)
        for _, di in ipairs(dirs) do
            local d = DIRECTIONS[di]
            local nr, nc = r + d.r, c + d.c
            if nr >= 1 and nr <= size and nc >= 1 and nc <= size
                and not grid[nr][nc].visited then
                -- 현재 셀과 다음 셀 사이의 벽 제거
                if d.r == -1 then
                    grid[r][c].walls.top = false
                    grid[nr][nc].walls.bottom = false
                elseif d.r == 1 then
                    grid[r][c].walls.bottom = false
                    grid[nr][nc].walls.top = false
                elseif d.c == -1 then
                    grid[r][c].walls.left = false
                    grid[nr][nc].walls.right = false
                else
                    grid[r][c].walls.right = false
                    grid[nr][nc].walls.left = false
                end
                carve(nr, nc)
            end
        end
    end

    carve(1, 1)  -- 항상 (1,1)에서 시작 (입구 = 좌상단)
    return grid
end

-- 스테이지 번호로 미로 크기 반환
function MazeModule.getSizeForStage(floor)
    if Constants.MAZE_SIZES[floor] then
        return Constants.MAZE_SIZES[floor]
    end
    -- 5층+: 매 층 +1, 최대 MAZE_SIZE_MAX
    local base = Constants.MAZE_SIZES[4] or 9
    local extra = (floor - 4) * Constants.MAZE_SIZE_INCREMENT
    return math.min(base + extra, Constants.MAZE_SIZE_MAX)
end

-- 출구 위치 반환 (미로 우하단 코너)
-- grid 좌표 (size, size) → 월드 좌표
function MazeModule.getExitPosition(size)
    local ws = Constants.WALL_SIZE.X  -- 셀 한 변의 길이 (4 studs)
    return Vector3.new(
        (size - 1) * ws + ws / 2,
        Constants.FLOOR_SIZE.Y + 0.5,
        (size - 1) * ws + ws / 2
    )
end

-- 미로 렌더링: BasePart로 벽/바닥/출구 생성
-- mazeFolder: Workspace 안의 Folder 인스턴스
function MazeModule.render(grid, size, mazeFolder)
    local ws = Constants.WALL_SIZE.X        -- 셀 크기
    local wh = Constants.WALL_SIZE.Y        -- 벽 높이
    local fw = Constants.FLOOR_SIZE.Y       -- 바닥 두께
    local wallThickness = Constants.WALL_THICKNESS  -- 벽 두께 (Constants에서 관리)
    local CollectionService = game:GetService("CollectionService")

    local function makePart(name, size3, pos, color, transparent, material)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size3
        p.Position = pos
        p.Anchored = true
        p.BrickColor = BrickColor.new(color)
        p.Color = color
        p.Material = material or Enum.Material.SmoothPlastic
        p.Transparency = transparent or 0
        p.CastShadow = false
        p.Parent = mazeFolder
        return p
    end

    -- Mountain 템플릿 로드
    local wallsFolder = ReplicatedStorage:FindFirstChild("walls")
    local wallTemplates = wallsFolder and wallsFolder:GetChildren() or {}

    -- 첫 템플릿으로 스케일/타일 크기 사전 계산
    local TILE_SCALE = 1
    local TILE_W = wallThickness  -- X 방향 타일 폭
    local TILE_D = wallThickness  -- Z 방향 타일 폭
    if #wallTemplates > 0 then
        local _, sz = wallTemplates[1]:GetBoundingBox()
        TILE_SCALE = wh / sz.Y
        TILE_W = sz.X * TILE_SCALE
        TILE_D = sz.Z * TILE_SCALE
    end

    -- 돌 템플릿 로드 (타입 필터 없음 — 모든 자식 허용)
    local rocksFolder = ReplicatedStorage:FindFirstChild("Rocks")
    local rockTemplates = rocksFolder and rocksFolder:GetChildren() or {}

    -- Mountain 템플릿 타일링으로 벽 생성
    -- axis "X" = 가로벽(길이가 X방향), "Z" = 세로벽(길이가 Z방향)
    -- scaleMult: 높이 스케일 배율 (기본 1.0, 크로스바 등 작게 할 때 사용)
    local function makeTemplateWall(name, length, axis, cx, cy, cz, scaleMult)
        scaleMult = scaleMult or 1.0
        if #wallTemplates == 0 then
            local bodySize = axis == "X"
                and Vector3.new(length, wh * scaleMult, wallThickness)
                or  Vector3.new(wallThickness, wh * scaleMult, length)
            local part = makePart(name, bodySize, Vector3.new(cx, cy, cz),
                Constants.COLORS.Wall, nil, Enum.Material.WoodPlanks)
            CollectionService:AddTag(part, "MazeWall")
            return
        end

        local baseScale = TILE_SCALE * scaleMult
        local tileSize  = axis == "X" and (TILE_W * scaleMult) or (TILE_D * scaleMult)
        local tileCount = math.max(1, math.ceil(length / tileSize))
        local spacing   = length / tileCount
        local fillScale = baseScale * (spacing / tileSize) * 1.15

        for i = 0, tileCount - 1 do
            local tmpl = wallTemplates[math.random(1, #wallTemplates)]
            local tile = tmpl:Clone()
            tile:ScaleTo(fillScale)

            local offset = -length / 2 + spacing * (i + 0.5)
            local tileCF
            if axis == "X" then
                tileCF = CFrame.new(cx + offset, cy, cz)
                       * CFrame.Angles(0, math.random(0,1) * math.pi, 0)
            else
                tileCF = CFrame.new(cx, cy, cz + offset)
                       * CFrame.Angles(0, math.pi/2 + math.random(0,1) * math.pi, 0)
            end
            tile:PivotTo(tileCF)
            tile.Parent = mazeFolder
            -- 태그는 DataModel에 들어간 후에 추가해야 클라이언트에 복제됨
            for _, desc in ipairs(tile:GetDescendants()) do
                if desc:IsA("BasePart") then
                    CollectionService:AddTag(desc, "MazeWall")
                end
            end
        end
    end

    -- 미로 원점 (월드 좌표)
    local originX = 0
    local originZ = 0
    local groundY = 0.6

    for r = 1, size do
        for c = 1, size do
            local cell = grid[r][c]
            local cx = originX + (c - 1) * ws + ws / 2
            local cz = originZ + (r - 1) * ws + ws / 2

            -- 바닥 타일 (Mountain 벽과 동일한 느낌 - Grass 재질)
            local floorColors = {
                Color3.fromRGB(106, 127, 63),  -- 진한 초록
                Color3.fromRGB(115, 135, 68),  -- 중간 초록
                Color3.fromRGB(98,  118, 58),  -- 어두운 초록
                Color3.fromRGB(110, 130, 65),  -- 밝은 초록
            }
            local fc = floorColors[math.random(1, #floorColors)]
            makePart("Floor",
                Vector3.new(ws, fw, ws),
                Vector3.new(cx, groundY - fw / 2, cz),
                fc, nil, Enum.Material.Grass
            )

            if cell.walls.top then
                makeTemplateWall("WallTop", ws, "X",
                    cx, groundY + wh / 2, originZ + (r - 1) * ws)
            end

            if cell.walls.left then
                makeTemplateWall("WallLeft", ws, "Z",
                    originX + (c - 1) * ws, groundY + wh / 2, cz)
            end

            -- 마지막 셀(size, size) 아래벽은 출구 개구부로 생략
            if r == size and cell.walls.bottom and not (r == size and c == size) then
                makeTemplateWall("WallBottom", ws, "X",
                    cx, groundY + wh / 2, originZ + size * ws)
            end

            if c == size and cell.walls.right then
                makeTemplateWall("WallRight", ws, "Z",
                    originX + size * ws, groundY + wh / 2, cz)
            end
        end
    end

    -- 코너 기둥 제거 (Mountain 타일로 대체)

    -- 미로 내부 돌 랜덤 배치 (장식용)
    do
        local ROCK_CHANCE = 0.25
        for r = 1, size do
            for c = 1, size do
                if not (r == 1 and c == 1) and not (r == size and c == size) then
                    if math.random() < ROCK_CHANCE then
                        local cx = originX + (c - 1) * ws + ws / 2
                        local cz = originZ + (r - 1) * ws + ws / 2
                        local count = math.random(1, 2)

                        for _ = 1, count do
                            local ox = (math.random() - 0.5) * ws * 0.5
                            local oz = (math.random() - 0.5) * ws * 0.5
                            local ry = math.random() * math.pi * 2

                            if #rockTemplates > 0 then
                                -- 템플릿 사용
                                local tmpl = rockTemplates[math.random(1, #rockTemplates)]
                                local rock = tmpl:Clone()
                                rock.Parent = mazeFolder

                                -- 모든 하위 파트 고정
                                for _, p in ipairs(rock:GetDescendants()) do
                                    if p:IsA("BasePart") then
                                        p.Anchored    = true
                                        p.CanCollide  = true
                                        p.CastShadow  = false
                                        p.Transparency = 0
                                    end
                                end
                                if rock:IsA("BasePart") then
                                    rock.Anchored   = true
                                    rock.CanCollide = true
                                end

                                -- 아주 작은 돌 (0.015~0.03 studs)
                                local targetStuds = 3 + math.random() * 3

                                if rock:IsA("BasePart") then
                                    -- 템플릿이 BasePart/MeshPart인 경우: Size 직접 변경
                                    local maxDim = math.max(rock.Size.X, rock.Size.Y, rock.Size.Z)
                                    if maxDim > 0.01 then
                                        rock.Size = rock.Size * (targetStuds / maxDim)
                                    end
                                else
                                    -- Model인 경우: ScaleTo 시도
                                    -- GetScale()로 현재 스케일 보정 (ScaleTo는 원본 기준 절대값)
                                    pcall(function()
                                        local _, bsz = rock:GetBoundingBox()
                                        local curH = math.max(bsz.X, bsz.Y, bsz.Z)
                                        if curH > 0.01 then
                                            local currentScale = rock:GetScale()
                                            rock:ScaleTo(currentScale * targetStuds / curH)
                                        end
                                    end)
                                    -- ScaleTo 후에도 너무 크면 각 파트 직접 축소
                                    pcall(function()
                                        local _, bsz = rock:GetBoundingBox()
                                        local curH = math.max(bsz.X, bsz.Y, bsz.Z)
                                        if curH > targetStuds * 2 then
                                            local s = targetStuds / curH
                                            for _, p in ipairs(rock:GetDescendants()) do
                                                if p:IsA("BasePart") then
                                                    p.Size = p.Size * s
                                                end
                                            end
                                        end
                                    end)
                                end
                                -- 1단계: 임시 위치로 배치
                                pcall(function()
                                    rock:PivotTo(CFrame.new(cx+ox, groundY, cz+oz) * CFrame.Angles(0, ry, 0))
                                end)
                                -- 2단계: 실제 바운딩박스 bottom 측정 후 groundY에 밀착
                                pcall(function()
                                    local bbCF, bsz = rock:GetBoundingBox()
                                    local actualBottomY = bbCF.Position.Y - bsz.Y * 0.5
                                    local correction = groundY - actualBottomY
                                    rock:PivotTo(CFrame.new(cx+ox, groundY + correction, cz+oz) * CFrame.Angles(0, ry, 0))
                                end)
                            else
                                -- 폴백: 단순 회색 돌 파트
                                local p = Instance.new("Part")
                                p.Shape    = Enum.PartType.Block
                                p.Size     = Vector3.new(
                                    2 + math.random()*2, 1.5 + math.random(), 1.5 + math.random()*2)
                                p.Color    = Color3.fromRGB(130 + math.random(30), 120 + math.random(20), 110 + math.random(20))
                                p.Material = Enum.Material.SmoothPlastic
                                p.Anchored    = true
                                p.CanCollide  = false
                                p.CastShadow  = false
                                p.CFrame = CFrame.new(cx+ox, groundY + p.Size.Y*0.5, cz+oz) * CFrame.Angles(0, ry, 0)
                                p.Parent = mazeFolder
                            end
                        end
                    end
                end
            end
        end
    end

    -- 출구: 마지막 셀 중앙(X), 미로 외부(Z 방향으로 한 칸 밖)
    local exitX = originX + (size - 1) * ws + ws / 2
    local exitZ = originZ + size * ws + ws / 2   -- 미로 외부

    -- 감지용 투명 바닥 파트
    local exitPart = makePart("Exit",
        Vector3.new(ws, 2, ws),
        Vector3.new(exitX, groundY + 1, exitZ),
        Color3.fromRGB(80, 255, 150)
    )
    exitPart.Transparency = 1
    exitPart.CanCollide   = false

    -- 외부 바닥 타일 (미로 밖 출구 영역)
    makePart("ExitFloor",
        Vector3.new(ws, fw, ws),
        Vector3.new(exitX, groundY - fw / 2, exitZ),
        Constants.COLORS.Floor, nil, Enum.Material.Ground
    )

    local gateColor = Constants.COLORS.Wall
    local gateMat   = Enum.Material.WoodPlanks
    local pillarW   = wallThickness
    local gateH     = wh + 4
    -- 게이트는 외벽 경계(originZ + size*ws)에 배치
    local gateZ     = originZ + size * ws

    -- Mountain 타일로 기둥 생성 (벽과 동일한 TILE_SCALE 사용, 타일 1개)
    local function makeGatePillar(px, pz)
        if #wallTemplates == 0 then
            -- 폴백: 기본 Part
            makePart("GatePillar",
                Vector3.new(pillarW, gateH, pillarW),
                Vector3.new(px, groundY + gateH / 2, pz),
                gateColor, nil, gateMat)
            return
        end
        local t1 = wallTemplates[math.random(1, #wallTemplates)]:Clone()
        local pillarScale = TILE_SCALE * 0.35   -- 벽의 35% 크기로 작게
        t1:ScaleTo(pillarScale)
        t1:PivotTo(CFrame.new(px, groundY + (wh * 0.35) / 2, pz)
                   * CFrame.Angles(0, math.random(0, 1) * math.pi, 0))
        t1.Parent = mazeFolder
    end

    -- 왼쪽 기둥
    makeGatePillar(exitX - ws / 2 + pillarW / 2, gateZ)

    -- 오른쪽 기둥
    makeGatePillar(exitX + ws / 2 - pillarW / 2, gateZ)

    -- 상단 가로대: Mountain 타일, 벽의 35% 크기로 작게
    makeTemplateWall("GateCrossbar", ws, "X",
        exitX, groundY + wh * 1.18, gateZ, 0.35)

    -- GOAL 바닥 (초록, SurfaceGui 없이 색상만으로 구분)
    makePart("GoalFloor",
        Vector3.new(ws, fw, ws),
        Vector3.new(exitX, groundY - fw / 2, exitZ),
        Color3.fromRGB(40, 180, 100), nil, Enum.Material.SmoothPlastic
    )

    -- GOAL 수직 간판: 미로 입구 방향(-Z)을 향하는 Front 면에 SurfaceGui
    -- 파트의 Front(-Z)가 항상 미로 안쪽을 향하므로 회전 없이 고정
    local signPart = Instance.new("Part")
    signPart.Name        = "GoalSign"
    signPart.Size        = Vector3.new(ws, wh * 0.6, 0.3)
    signPart.Anchored    = true
    signPart.CanCollide  = false
    signPart.Transparency = 1          -- 파트 자체는 투명
    -- gateZ(외벽) 위치에서 미로 방향으로 약간 앞에 배치
    signPart.CFrame      = CFrame.new(exitX, groundY + wh * 0.3, gateZ - 0.2)
    signPart.Parent      = mazeFolder

    local surfGui = Instance.new("SurfaceGui")
    surfGui.Face       = Enum.NormalId.Front   -- -Z 방향 = 미로 안쪽
    surfGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    surfGui.CanvasSize = Vector2.new(512, 200)
    surfGui.Parent     = signPart

    local surfLbl = Instance.new("TextLabel")
    surfLbl.Text               = "GOAL"
    surfLbl.Size               = UDim2.new(1, 0, 1, 0)
    surfLbl.BackgroundTransparency = 1
    surfLbl.Font               = Enum.Font.GothamBold
    surfLbl.TextScaled         = true
    surfLbl.TextColor3         = Color3.fromRGB(80, 255, 150)
    surfLbl.TextStrokeColor3   = Color3.fromRGB(0, 80, 40)
    surfLbl.TextStrokeTransparency = 0.2
    surfLbl.Parent             = surfGui

    -- 스폰 위치: 미로 입구 첫 번째 셀 (1,1) 중앙, 바닥에서 3 studs 위
    local spawnPosition = Vector3.new(originX + ws / 2, groundY + 3, originZ + ws / 2)

    return {
        exitPart      = exitPart,
        spawnPosition = spawnPosition,
        exitPosition  = Vector3.new(exitX, groundY + 0.1, exitZ),
    }
end

-- 미로 파트 전체 삭제
function MazeModule.clear(mazeFolder)
    for _, child in ipairs(mazeFolder:GetChildren()) do
        child:Destroy()
    end
end

return MazeModule
