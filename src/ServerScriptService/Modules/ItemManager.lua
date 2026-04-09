-- ServerScriptService/Modules/ItemManager
local ItemManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local activeItems = {}  -- {part=Part, type=string} のリスト
local activeSmokes = {}  -- [player] = smokeModel (클라이언트 취소 대기)

local graffitiCount = 0  -- 현재 스테이지 낙서 수

-- 플레이어 Backpack에 4개 Tool을 순서대로 생성 (당근→함정→연막탄→스프레이)
local function createToolsForPlayer(player)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    -- 기존 게임 툴 초기화
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then item:Destroy() end
    end
    local toolDefs = {
        { typeName = "carrot", display = "당근",    count = 0 },
        { typeName = "trap",   display = "함정",    count = 0 },
        { typeName = "smoke",  display = "연막탄",  count = 0 },
        { typeName = "spray",  display = "스프레이", count = 1 },
    }
    for _, def in ipairs(toolDefs) do
        local tool = Instance.new("Tool")
        tool.Name = def.display .. " ×" .. def.count
        tool.CanBeDropped = false
        tool.RequiresHandle = false
        local tag = Instance.new("StringValue")
        tag.Name  = "ToolType"
        tag.Value = def.typeName
        tag.Parent = tool
        tool.Parent = backpack
        task.wait()  -- 순서 보장을 위한 짧은 대기
    end
end

-- 플레이어의 특정 타입 Tool 이름을 카운트로 업데이트
local function updateToolName(player, toolType, count)
    local displayNames = { carrot="당근", trap="함정", smoke="연막탄", spray="스프레이" }
    local display = displayNames[toolType] or toolType
    local newName = display .. " ×" .. count
    -- Backpack 탐색
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local tag = item:FindFirstChild("ToolType")
            if tag and tag.Value == toolType then
                item.Name = newName
                return
            end
        end
    end
    -- 장착 중인 경우 Character 탐색
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            local tag = item:FindFirstChild("ToolType")
            if tag and tag.Value == toolType then
                item.Name = newName
                return
            end
        end
    end
end

-- 팔레트에서 가장 가까운 색 반환
local function snapToGraffitiPalette(color)
    local Constants = require(game.ReplicatedStorage.Shared.Constants)
    local best, bestDist = Constants.GRAFFITI_PALETTE[1], math.huge
    for _, c in ipairs(Constants.GRAFFITI_PALETTE) do
        local d = (color.R - c.R)^2 + (color.G - c.G)^2 + (color.B - c.B)^2
        if d < bestDist then best, bestDist = c, d end
    end
    return best
end

-- 미로 바닥 파트에서 랜덤 위치 선택
-- excludePositions: 이미 사용된 위치 목록 (간단히 앞에서 뽑은 위치)
local function getRandomFloorPositions(mazeFolder, count, rng)
    local floors = {}
    local ws = Constants.WALL_SIZE.X
    -- 스폰 영역 (첫 번째 셀) 제외 반경
    local spawnExclude = ws * 1.5
    for _, part in ipairs(mazeFolder:GetChildren()) do
        if part:IsA("BasePart")
            and part.Name ~= "Exit"
            and part.Name ~= "Spawn"
            and part.Size.Y <= 1  -- 바닥 판별: 두께 1 이하
            and not (part.Position.X < spawnExclude and part.Position.Z < spawnExclude)
        then
            table.insert(floors, part.Position + Vector3.new(0, 2, 0))
        end
    end

    -- Fisher-Yates 셔플
    for i = #floors, 2, -1 do
        local j = math.floor(rng() * i) + 1
        floors[i], floors[j] = floors[j], floors[i]
    end

    local result = {}
    for i = 1, math.min(count, #floors) do
        result[i] = floors[i]
    end
    return result
end

-- 아이템 파트 생성
local function spawnItem(position, itemType, mazeFolder)
    -- 당근: ReplicatedStorage의 CarrotModel 클론 사용
    if itemType == "Carrot" then
        local template = game.ReplicatedStorage:FindFirstChild("CarrotModel")

        -- 히트박스 (터치 감지용 투명 파트)
        local hitbox = Instance.new("Part")
        hitbox.Name = "Carrot"
        hitbox.Size = Vector3.new(3, 3, 3)
        hitbox.Anchored = true
        hitbox.CanCollide = false
        hitbox.CastShadow = false
        hitbox.Transparency = 1
        hitbox.Position = position
        hitbox.Parent = mazeFolder

        if template then
            -- 3D 모델 클론
            local model = template:Clone()
            model.Name = "CarrotVisual"
            if model:IsA("BasePart") or model:IsA("UnionOperation") then
                model.Anchored = true
                model.CanCollide = false
                model.Size = model.Size * 0.25  -- 크기 축소
                model.CFrame = CFrame.new(position.X, position.Y + 0.5, position.Z)
                              * CFrame.Angles(0, math.random(0, 6), 0)
                model.Parent = mazeFolder
                -- 히트박스가 파괴될 때 모델도 같이 제거
                hitbox.AncestryChanged:Connect(function()
                    if not hitbox.Parent then model:Destroy() end
                end)
            elseif model:IsA("Model") then
                model:SetPrimaryPartCFrame(CFrame.new(position))
                model.Parent = mazeFolder
                hitbox.AncestryChanged:Connect(function()
                    if not hitbox.Parent then model:Destroy() end
                end)
            end
        else
            -- fallback: 이모지 빌보드
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 80, 0, 80)
            billboard.StudsOffset = Vector3.new(0, 1, 0)
            billboard.Parent = hitbox
            local lbl = Instance.new("TextLabel")
            lbl.Text = "🥕"
            lbl.TextScaled = true
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.Parent = billboard
        end

        table.insert(activeItems, {part = hitbox, type = "Carrot"})
        return hitbox
    end

    if itemType == "Smoke" then
        local container = Instance.new("Model")
        container.Name = "SmokeItem"
        container.Parent = mazeFolder

        -- 히트박스 (투명 감지용)
        local hitbox = Instance.new("Part")
        hitbox.Name = "Smoke"
        hitbox.Size = Vector3.new(3, 3, 3)
        hitbox.Transparency = 1
        hitbox.CanCollide = false
        hitbox.Anchored = true
        hitbox.Position = position
        hitbox.Parent = container

        -- SmokeModel 클론 (ReplicatedStorage 우선)
        local smokeTemplate = game.ReplicatedStorage:FindFirstChild("SmokeModel")
        if smokeTemplate then
            local smokeVisual = smokeTemplate:Clone()
            smokeVisual.Name = "SmokeVisual"
            smokeVisual:PivotTo(CFrame.new(position.X, position.Y, position.Z))
            smokeVisual.Parent = container
            hitbox.AncestryChanged:Connect(function()
                if not hitbox.Parent then pcall(function() smokeVisual:Destroy() end) end
            end)
        else
            -- fallback: 회색 캔 + 이모지
            local body = Instance.new("Part")
            body.Shape    = Enum.PartType.Cylinder
            body.Size     = Vector3.new(1.8, 1.0, 1.0)
            body.Color    = Color3.fromRGB(90, 105, 115)
            body.Material = Enum.Material.Metal
            body.Anchored = true
            body.CanCollide = false
            body.CFrame   = CFrame.new(position.X, position.Y + 0.9, position.Z)
                            * CFrame.Angles(0, 0, math.pi / 2)
            body.Parent   = container
            local bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 50, 0, 50)
            bb.StudsOffset = Vector3.new(0, 2.2, 0)
            bb.Parent = hitbox
            local lbl = Instance.new("TextLabel")
            lbl.Text = "💨"; lbl.TextScaled = true
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.Parent = bb
        end

        table.insert(activeItems, {part = hitbox, type = "Smoke"})
        return hitbox
    end

    -- Trap (pickup) — TrapModel 클론 사용
    local container = Instance.new("Model")
    container.Name   = "Trap"
    container.Parent = mazeFolder

    -- 투명 감지 박스
    local hitbox = Instance.new("Part")
    hitbox.Name        = "TrapHitbox"
    hitbox.Size        = Vector3.new(3.5, 3.5, 3.5)
    hitbox.Position    = position
    hitbox.Transparency = 1
    hitbox.Anchored    = true
    hitbox.CanCollide  = false
    hitbox.CastShadow  = false
    hitbox.Parent      = container

    -- TrapModel 클론 (ReplicatedStorage)
    local trapTemplate = game.ReplicatedStorage:FindFirstChild("TrapModel")
    if trapTemplate then
        local trapVisual = trapTemplate:Clone()
        trapVisual.Name = "TrapVisual"
        -- 내부 HitBox 제거 (우리 hitbox 사용)
        local innerHB = trapVisual:FindFirstChild("HitBox")
        if innerHB then innerHB:Destroy() end
        -- Close 파트 숨기기 (Open만 표시)
        local closePart = trapVisual:FindFirstChild("Close")
        if closePart and closePart:IsA("BasePart") then
            closePart.Transparency = 1
            closePart.CanCollide   = false
        end
        -- 위치 이동
        trapVisual:PivotTo(CFrame.new(position.X, position.Y, position.Z))
        trapVisual.Parent = container
        -- hitbox 제거 시 visual도 제거
        hitbox.AncestryChanged:Connect(function()
            if not hitbox.Parent then pcall(function() trapVisual:Destroy() end) end
        end)
    else
        -- fallback 이모지
        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.new(0, 60, 0, 48)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.Parent = hitbox
        local lbl = Instance.new("TextLabel")
        lbl.Text = "🪤"; lbl.TextScaled = true
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Parent = bb
    end

    table.insert(activeItems, {part = container, type = itemType})
    return hitbox   -- Touched 연결용으로 hitbox 반환
end

-- 스테이지 시작 시 아이템 스폰
-- rng: makeRNG(seed) 반환값 (시드 기반 재현 가능한 위치)
function ItemManager.spawnItems(mazeFolder, rng)
    activeItems = {}

    -- 한 번에 전체 위치 뽑아서 겹침 방지
    local totalCount = Constants.CARROT_COUNT + Constants.TRAP_COUNT + Constants.SMOKE_COUNT
    local allPositions = getRandomFloorPositions(mazeFolder, totalCount, rng)
    local carrotPositions, trapPositions, smokePositions2 = {}, {}, {}
    for i = 1, Constants.CARROT_COUNT do carrotPositions[i] = allPositions[i] end
    for i = 1, Constants.TRAP_COUNT do trapPositions[i] = allPositions[Constants.CARROT_COUNT + i] end
    for i = 1, Constants.SMOKE_COUNT do smokePositions2[i] = allPositions[Constants.CARROT_COUNT + Constants.TRAP_COUNT + i] end

    -- 당근 스폰 및 획득 감지
    for _, pos in ipairs(carrotPositions) do
        local part = spawnItem(pos, "Carrot", mazeFolder)
        local debounce = false
        part.Touched:Connect(function(hit)
            if debounce then return end
            if not part.Parent then return end
            local char = hit.Parent
            local player = game.Players:GetPlayerFromCharacter(char)
            if not player then return end
            local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
            if PlayerManager.getState(player) == "alive"
                and PlayerManager.getCarrotCount(player) < 3 then
                debounce = true
                part:Destroy()
                local newCount = PlayerManager.addCarrot(player)
                updateToolName(player, "carrot", newCount)
                game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, {
                    type = "carrotPickup", count = newCount
                })
            end
        end)
    end

    -- 함정 아이템 스폰 및 획득 감지
    -- spawnItem("Trap") 은 hitbox(Part) 를 반환, parent 는 container(Model)
    for _, pos in ipairs(trapPositions) do
        local hitbox = spawnItem(pos, "Trap", mazeFolder)
        local debounce = false
        hitbox.Touched:Connect(function(hit)
            if debounce then return end
            local container = hitbox.Parent
            if not container then return end
            local char = hit.Parent
            local player = game.Players:GetPlayerFromCharacter(char)
            if not player then return end
            local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
            if PlayerManager.getState(player) == "alive" then
                debounce = true
                container:Destroy()   -- Model 전체 제거
                PlayerManager.giveTrap(player)
                updateToolName(player, "trap", PlayerManager.getTrapCount(player))
                game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, {
                    type  = "trapPickup",
                    count = PlayerManager.getTrapCount(player),
                })
            end
        end)
    end

    -- 연막탄 스폰
    for _, pos in ipairs(smokePositions2) do
        local part = spawnItem(pos, "Smoke", mazeFolder)
        local debounce = false
        part.Touched:Connect(function(hit)
            if debounce then return end
            local char = hit.Parent
            local player = game.Players:GetPlayerFromCharacter(char)
            if not player then return end
            local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
            if PlayerManager.getState(player) == "alive" then
                debounce = true
                part:Destroy()
                PlayerManager.addSmoke(player)
                updateToolName(player, "smoke", PlayerManager.getSmokeCount(player))
                game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, {
                    type = "smokePickup", count = PlayerManager.getSmokeCount(player)
                })
            end
        end)
    end

    -- 핫바 툴 생성 + 스프레이 지급 + 캐릭터 능력 적용
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    local Events = game.ReplicatedStorage.Events
    local alivePlayers = PlayerManager.getAlivePlayers()
    for _, p in ipairs(alivePlayers) do
        -- 4개 툴을 순서대로 Backpack에 생성
        createToolsForPlayer(p)
        -- 스프레이 캔 지급 (createToolsForPlayer에서 ×1로 이미 표시됨)
        for _ = 1, Constants.SPRAY_COUNT do
            PlayerManager.addSpray(p)
        end
        Events.UpdateHUD:FireClient(p, {
            type  = "sprayPickup",
            count = PlayerManager.getSprayCount(p),
        })

        -- ── 아빠 능력: 층 시작 시 함정 +1 보너스 ──────────────────────────
        local charType = PlayerManager.getCharType(p)
        if charType == "Dad" then
            PlayerManager.giveTrap(p)
            updateToolName(p, "trap", PlayerManager.getTrapCount(p))
        end

        -- 능력 알림 HUD
        local abilityDesc = {
            Dad      = "🎩 아빠 능력: 함정 +1 보너스",
            Mom      = "👒 엄마 능력: 당근 속도 2배 지속",
            Son      = "⚡ 아들 능력: 이동속도 +2",
            Daughter = "🎀 딸 능력: 연막탄 범위 1.5배",
        }
        if abilityDesc[charType] then
            Events.UpdateHUD:FireClient(p, {
                type = "charAbility",
                desc = abilityDesc[charType],
            })
        end
    end
end

-- 함정 설치 (TrapPlaced RemoteEvent 수신 후 GameManager가 호출)
-- exitPosition: 출구 위치 Vector3 (이 반경 내에는 설치 불가)
function ItemManager.placeTrap(player, exitPosition, mazeFolder)
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    if not PlayerManager.consumeTrap(player) then return end

    local char = player.Character
    if not char then
        -- 함정 반환 (캐릭터 없음)
        PlayerManager.giveTrap(player)
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        PlayerManager.giveTrap(player)
        return
    end

    -- 출구 근처 설치 금지
    if (hrp.Position - exitPosition).Magnitude <= Constants.TRAP_EXCLUSION_RADIUS then
        PlayerManager.giveTrap(player)  -- 함정 반환
        return
    end

    local HunterAI = require(game.ServerScriptService.Modules.HunterAI)

    -- 함정 묶음 (충돌 감지 박스 + 진흙 시각 파트)
    local trapModel = Instance.new("Model")
    trapModel.Name   = "PlacedTrap"
    trapModel.Parent = mazeFolder

    -- 투명 충돌 감지 박스 (헌터 감지용)
    local trapPart = Instance.new("Part")
    trapPart.Name        = "TrapHitbox"
    trapPart.Size        = Vector3.new(4, 3, 4)
    trapPart.Position    = Vector3.new(hrp.Position.X, hrp.Position.Y - 1, hrp.Position.Z)
    trapPart.Transparency = 1
    trapPart.Anchored    = true
    trapPart.CanCollide  = false
    trapPart.CastShadow  = false
    trapPart.Parent      = trapModel

    -- 바닥 Y: Raycast로 실제 바닥 위치 탐지
    local rayResult = workspace:Raycast(
        hrp.Position, Vector3.new(0, -10, 0), RaycastParams.new()
    )
    local floorY = rayResult and (rayResult.Position.Y + 0.15) or (hrp.Position.Y - 2.5)

    -- 설치 함정 시각 — TrapModel 클론 (Open 상태로 바닥에 배치)
    local trapTemplate2 = game.ReplicatedStorage:FindFirstChild("TrapModel")
    if trapTemplate2 then
        local tv = trapTemplate2:Clone()
        -- 내부 HitBox 제거
        local ib = tv:FindFirstChild("HitBox")
        if ib then ib:Destroy() end
        -- Close 파트/모델 전체 숨기기 (BasePart 또는 하위 파트 재귀)
        local cp = tv:FindFirstChild("Close")
        if cp then
            for _, desc in ipairs(cp:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.Transparency = 1
                    desc.CanCollide   = false
                end
            end
            if cp:IsA("BasePart") then
                cp.Transparency = 1
                cp.CanCollide   = false
            end
        end
        -- Open 파트 앵커 확인
        for _, desc in ipairs(tv:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Anchored   = true
                desc.CanCollide = false
            end
        end
        -- 바닥 위 1 stud 위치로 배치
        tv:PivotTo(CFrame.new(hrp.Position.X, floorY + 1, hrp.Position.Z))
        tv.Parent = trapModel
    end

    -- 사냥꾼 충돌 감지 (단발 트리거)
    local triggered = false
    trapPart.Touched:Connect(function(hit)
        if triggered then return end
        if not trapModel.Parent then return end
        local model = hit.Parent
        while model and model ~= workspace do
            if model.Name == "Hunter" then
                triggered = true
                trapModel:Destroy()
                HunterAI.stun()
                return
            end
            model = model.Parent
        end
    end)

    -- HUD 업데이트 + 클라이언트 전용 시각 위치 전달
    local remaining = PlayerManager.getTrapCount(player)
    updateToolName(player, "trap", remaining)
    game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, {
        type     = "trapUsed",
        count    = remaining,
        trapPos  = Vector3.new(hrp.Position.X, floorY, hrp.Position.Z),
    })
end


-- 연막탄 설치 (SmokePlaced RemoteEvent 수신 후 GameManager가 호출)
function ItemManager.placeSmoke(player, mazeFolder)
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    if not PlayerManager.consumeSmoke(player) then return end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- 연막 모델 (플레이어명 포함 → 클라이언트 로컬 제거 시 식별용)
    local smokeModel = Instance.new("Model")
    smokeModel.Name = "SmokeCloud_" .. player.Name
    smokeModel.Parent = mazeFolder

    -- 딸 능력: 연막 범위 1.5배
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    local smokeScale = (PlayerManager.getCharType(player) == "Daughter") and 1.5 or 1.0

    -- 연막 앵커 파트 (투명, HunterAI 감지용)
    local cloud = Instance.new("Part")
    cloud.Name = "SmokeCloud"
    cloud.Size = Vector3.new(120 * smokeScale, 60, 120 * smokeScale)
    cloud.Position = hrp.Position
    cloud.Transparency = 1
    cloud.Anchored = true
    cloud.CanCollide = false
    cloud.CastShadow = false
    cloud.Parent = smokeModel

    -- SmokeModel 비주얼 클론 (설치 위치에 크게 표시)
    local smokeTemplate = game.ReplicatedStorage:FindFirstChild("SmokeModel")
    if smokeTemplate then
        local sv = smokeTemplate:Clone()
        sv.Name = "SmokeVisualPlaced"

        -- 10배 확대 (딸이면 15배)
        local visualScale = 10 * smokeScale
        if sv:IsA("Model") then
            -- 방법1: ScaleTo
            local ok = pcall(function() sv:ScaleTo(visualScale) end)
            if not ok then
                -- 방법2: 피벗 기준 수동 스케일
                local pivotCF = sv:GetPivot()
                for _, p in ipairs(sv:GetDescendants()) do
                    if p:IsA("BasePart") then
                        local offset = p.CFrame.Position - pivotCF.Position
                        p.Size   = p.Size * visualScale
                        p.CFrame = CFrame.new(pivotCF.Position + offset * visualScale) * p.CFrame.Rotation
                    end
                end
            end
        elseif sv:IsA("BasePart") then
            sv.Size = sv.Size * visualScale
        end

        -- 파트 고정 + ParticleEmitter/Smoke 크기도 10배 (ScaleTo로는 안 됨)
        for _, p in ipairs(sv:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored   = true
                p.CanCollide = false
            elseif p:IsA("ParticleEmitter") then
                -- Size 키포인트 × 5, Rate는 원본 유지
                local kps = p.Size.Keypoints
                local newKps = {}
                for _, kp in ipairs(kps) do
                    table.insert(newKps, NumberSequenceKeypoint.new(
                        kp.Time,
                        math.min(kp.Value * 5, 1000),
                        math.min(kp.Envelope * 5, 1000)
                    ))
                end
                p.Size = NumberSequence.new(newKps)
            elseif p:IsA("Smoke") then
                p.Size = math.min(p.Size * 5, 100)
            end
        end
        if sv:IsA("BasePart") then
            sv.Anchored   = true
            sv.CanCollide = false
        end

        sv:PivotTo(CFrame.new(hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        sv.Parent = smokeModel
    end

    -- 연기 파티클 효과
    local smokeEffect = Instance.new("Smoke")
    smokeEffect.Color = Color3.fromRGB(180, 180, 180)
    smokeEffect.Density = 1
    smokeEffect.Opacity = 0.8
    smokeEffect.Size = 100
    smokeEffect.RiseVelocity = 1
    smokeEffect.Parent = cloud

    local particles = Instance.new("ParticleEmitter")
    particles.Rate = 60
    particles.Lifetime = NumberRange.new(3, 5)
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   120),
        NumberSequenceKeypoint.new(0.4, 260),
        NumberSequenceKeypoint.new(1,   360),
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.1),
        NumberSequenceKeypoint.new(0.6, 0.5),
        NumberSequenceKeypoint.new(1,   1),
    })
    particles.Color = ColorSequence.new(Color3.fromRGB(220, 220, 220))
    particles.SpreadAngle = Vector2.new(60, 60)
    particles.Speed = NumberRange.new(1, 3)
    particles.Parent = cloud

    -- activeSmokes에 등록 (클라이언트 SmokeCanceled 수신 시 빠른 취소)
    activeSmokes[player] = smokeModel

    -- 서버 폴링: 플레이어 이동 감지 시 즉시 제거
    local startPos = hrp.Position
    task.spawn(function()
        local deadline = tick() + 30
        while tick() < deadline do
            task.wait(0.2)
            if not activeSmokes[player] then return end  -- 이미 취소됨
            if not hrp or not hrp.Parent then
                ItemManager.cancelSmoke(player); return
            end
            if (hrp.Position - startPos).Magnitude > 2 then
                ItemManager.cancelSmoke(player); return
            end
        end
        ItemManager.cancelSmoke(player)  -- 30초 타임아웃
    end)

    -- 잔여 연막탄 수 반환
    local remaining = PlayerManager.getSmokeCount(player)
    updateToolName(player, "smoke", remaining)
    game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, {
        type = "smokeUsed", count = remaining
    })
end

-- 플레이어 연막 취소 (클라이언트 SmokeCanceled 수신 또는 30초 타임아웃)
function ItemManager.cancelSmoke(player)
    local model = activeSmokes[player]
    if not model then return end
    activeSmokes[player] = nil

    -- 클라이언트에게 즉시 로컬 제거 지시 (파티클 잔상 방지)
    pcall(function()
        game.ReplicatedStorage.Events.UpdateHUD:FireClient(player, { type = "smokeCleared" })
    end)

    -- 서버측 파티클 즉시 정리 (다른 플레이어에게 보이는 것도 제거)
    pcall(function()
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("Smoke") then
                desc.Opacity = 0
                desc.RiseVelocity = 0
            elseif desc:IsA("ParticleEmitter") then
                desc.Enabled = false
                desc:Clear()
            end
        end
    end)
    -- 즉시 파괴
    pcall(function()
        if model.Parent then model:Destroy() end
    end)
end

-- 모든 아이템 제거 (스테이지 전환 시)
function ItemManager.clear(mazeFolder)
    for _, item in ipairs(activeItems) do
        if item.part and item.part.Parent then
            item.part:Destroy()
        end
    end
    activeItems = {}
    graffitiCount = 0

    -- 똥 오브젝트 제거 (workspace에 직접 배치됨)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "CapyPoop" then obj:Destroy() end
    end
    -- PlacedTrap도 제거
    if mazeFolder then
        for _, obj in ipairs(mazeFolder:GetChildren()) do
            if obj.Name == "PlacedTrap" then
                obj:Destroy()
            end
        end
    end
    -- SmokeCloud 제거
    if mazeFolder then
        for _, obj in ipairs(mazeFolder:GetChildren()) do
            if obj.Name == "SmokeCloud" then obj:Destroy() end
        end
    end
end

-- 두 점 사이의 선분을 회전된 Frame으로 SurfaceGui 위에 그린다
local function drawSegment(parent, x1, y1, x2, y2, color, thickness, cs)
    local dx   = x2 - x1
    local dy   = y2 - y1
    local len  = math.sqrt(dx*dx + dy*dy)
    local px   = ({[1]=6, [2]=11, [3]=18})[thickness] or 11
    local cx   = (x1 + x2) * 0.5
    local cy   = (y1 + y2) * 0.5
    local ang  = math.deg(math.atan2(dy, dx))
    local lenPx = len * cs + px

    local function makeStroke(offY, w, alpha, cornerR)
        local f = Instance.new("Frame")
        f.BackgroundColor3       = color
        f.BackgroundTransparency = alpha
        f.BorderSizePixel        = 0
        f.Size     = UDim2.new(0, lenPx, 0, w)
        f.Position = UDim2.new(0, cx*cs - lenPx*0.5, 0, cy*cs - w*0.5 + offY)
        f.Rotation = ang
        f.ZIndex   = 2
        f.Parent   = parent
        Instance.new("UICorner", f).CornerRadius = UDim.new(cornerR, 0)
    end

    makeStroke(0, px, 0.05, 0.25)                           -- 메인 크레파스
    makeStroke(0, math.max(2, px * 0.35), 0.45, 0.3)       -- 하이라이트

    -- 끝점 도트
    local dot = Instance.new("Frame")
    dot.BackgroundColor3       = color
    dot.BackgroundTransparency = 0.05
    dot.BorderSizePixel        = 0
    dot.Size     = UDim2.new(0, px, 0, px)
    dot.Position = UDim2.new(0, x2*cs - px*0.5, 0, y2*cs - px*0.5)
    dot.ZIndex   = 2
    dot.Parent   = parent
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)
end

-- 벽 파트에 SurfaceGui를 생성하고 스트로크를 렌더링
local function _renderGraffiti(wallPart, normal, strokes, authorName)
    local Constants = require(game.ReplicatedStorage.Shared.Constants)
    local cs = Constants.GRAFFITI_CANVAS_SIZE  -- 500

    -- 월드 노멀을 파트 로컬 공간으로 변환해야 올바른 면 선택 가능
    -- (파트가 회전된 경우 월드 공간 매핑은 틀림)
    local localNormal = wallPart.CFrame:VectorToObjectSpace(normal)
    local faceMap = {
        [Vector3.new( 0, 0,-1)] = Enum.NormalId.Front,
        [Vector3.new( 0, 0, 1)] = Enum.NormalId.Back,
        [Vector3.new(-1, 0, 0)] = Enum.NormalId.Left,
        [Vector3.new( 1, 0, 0)] = Enum.NormalId.Right,
        [Vector3.new( 0, 1, 0)] = Enum.NormalId.Top,
        [Vector3.new( 0,-1, 0)] = Enum.NormalId.Bottom,
    }
    local bestFace, bestDot = Enum.NormalId.Front, -math.huge
    for vec, face in pairs(faceMap) do
        local d = localNormal:Dot(vec)
        if d > bestDot then bestDot, bestFace = d, face end
    end

    local sg = Instance.new("SurfaceGui")
    sg.Name           = "GraffitiGui"
    sg.Face           = bestFace
    sg.CanvasSize     = Vector2.new(cs, cs)
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.LightInfluence = 0
    sg.Parent         = wallPart

    local bg = Instance.new("Frame")
    bg.BackgroundTransparency = 1
    bg.Size   = UDim2.new(1, 0, 1, 0)
    bg.ZIndex = 1
    bg.Parent = sg

    for _, stroke in ipairs(strokes) do
        local pts = stroke.points
        for i = 1, #pts - 1 do
            drawSegment(bg,
                pts[i].x, pts[i].y,
                pts[i+1].x, pts[i+1].y,
                stroke.color, stroke.thickness, cs)
        end
    end

    local sig = Instance.new("TextLabel")
    sig.Text                   = authorName
    sig.Font                   = Enum.Font.Gotham
    sig.TextSize               = 14
    sig.TextColor3             = Color3.fromRGB(220, 220, 220)
    sig.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    sig.TextStrokeTransparency = 0.4
    sig.BackgroundTransparency = 1
    sig.AnchorPoint            = Vector2.new(1, 1)
    sig.Position               = UDim2.new(1, -6, 1, -4)
    sig.Size                   = UDim2.new(0, 120, 0, 20)
    sig.TextXAlignment         = Enum.TextXAlignment.Right
    sig.ZIndex                 = 3
    sig.Parent                 = bg
end

-- GameManager 등 외부 모듈에서 updateToolName을 호출하기 위한 public 래퍼
function ItemManager.updateToolNamePublic(player, toolType, count)
    updateToolName(player, toolType, count)
end

function ItemManager.placeGraffiti(player, data, mazeFolder)
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    local Constants     = require(game.ReplicatedStorage.Shared.Constants)
    local Events        = game.ReplicatedStorage.Events
    local function dbg(msg)
        warn("[Graffiti:" .. player.Name .. "] " .. msg)
        pcall(function()
            Events.UpdateHUD:FireClient(player, { type = "hudMsg", msg = "낙서: " .. msg })
        end)
    end

    -- 1. mazeFolder nil 체크
    if not mazeFolder or not mazeFolder.Parent then dbg("mazeFolder 없음"); return end

    -- 2. 스테이지 낙서 수 제한
    if graffitiCount >= Constants.GRAFFITI_MAX_STAGE then dbg("낙서 수 초과"); return end

    -- 3. 데이터 기본 검증
    if type(data) ~= "table" then dbg("data 타입 오류"); return end
    if type(data.strokes) ~= "table" then dbg("strokes 없음"); return end
    if #data.strokes == 0 or #data.strokes > 20 then dbg("strokes 수 오류:" .. #data.strokes); return end
    if typeof(data.originPos) ~= "Vector3" then dbg("originPos 없음:" .. typeof(data.originPos)); return end
    if typeof(data.lookVector) ~= "Vector3" then dbg("lookVector 없음"); return end
    if data.lookVector.Magnitude < 0.001 then dbg("lookVector 0"); return end

    -- 4. consumeSpray 원자적 처리
    if not PlayerManager.consumeSpray(player) then dbg("스프레이 없음"); return end
    local function refund() PlayerManager.addSpray(player) end

    -- 5. 서버측 거리 재검증 (mazeFolder 소속 Anchored 파트면 허용)
    local nearbyParts = workspace:GetPartBoundsInRadius(data.originPos, Constants.GRAFFITI_RANGE + 4)
    local wallFound = false
    for _, p in ipairs(nearbyParts) do
        if p:IsA("BasePart") and p.Anchored and p:IsDescendantOf(mazeFolder) then
            wallFound = true
            break
        end
    end
    if not wallFound then dbg("근처 벽 없음 (pos=" .. tostring(data.originPos) .. ")"); refund(); return end

    -- 6. 스트로크 서버 검증 및 정규화
    local validatedStrokes = {}
    for si, stroke in ipairs(data.strokes) do
        if type(stroke) ~= "table" then dbg("stroke["..si.."] 타입 오류"); refund(); return end
        if type(stroke.points) ~= "table" then dbg("stroke["..si.."] points 없음"); refund(); return end
        if #stroke.points == 0 or #stroke.points > 200 then dbg("stroke["..si.."] 포인트 수 오류:" .. #stroke.points); refund(); return end
        if typeof(stroke.color) ~= "Color3" then dbg("stroke["..si.."] color 타입:" .. typeof(stroke.color)); refund(); return end

        local thickness = tonumber(stroke.thickness) or 2
        thickness = math.clamp(math.floor(thickness), 1, 3)

        local snappedColor = snapToGraffitiPalette(stroke.color)
        local cleanPoints = {}
        for _, pt in ipairs(stroke.points) do
            if type(pt) == "table" and type(pt.x) == "number" and type(pt.y) == "number" then
                table.insert(cleanPoints, {
                    x = math.clamp(pt.x, 0, 1),
                    y = math.clamp(pt.y, 0, 1),
                })
            end
        end
        if #cleanPoints < 2 then dbg("stroke["..si.."] 유효 포인트 부족:" .. #cleanPoints); refund(); return end

        table.insert(validatedStrokes, {
            color     = snappedColor,
            thickness = thickness,
            points    = cleanPoints,
        })
    end

    -- 7. 가장 가까운 수직 벽 탐색 (수평 방향만 → 바닥/천장 원천 차단)
    local searchDirs = {
        Vector3.new( 1, 0,  0), Vector3.new(-1, 0,  0),
        Vector3.new( 0, 0,  1), Vector3.new( 0, 0, -1),
        Vector3.new( 1, 0,  1).Unit, Vector3.new(-1, 0,  1).Unit,
        Vector3.new( 1, 0, -1).Unit, Vector3.new(-1, 0, -1).Unit,
    }
    local bestResult, bestDist = nil, math.huge
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {mazeFolder}
    rayParams.FilterType = Enum.RaycastFilterType.Include
    for _, dir in ipairs(searchDirs) do
        local hit = workspace:Raycast(data.originPos, dir * (Constants.GRAFFITI_RANGE + 4), rayParams)
        if hit and hit.Instance and hit.Instance:IsA("BasePart") then
            -- 수직 벽만 허용 (법선 Y 절댓값이 작아야 수직면)
            if math.abs(hit.Normal.Y) <= 0.5 then
                local d = (hit.Position - data.originPos).Magnitude
                if d < bestDist then bestDist = d; bestResult = hit end
            end
        end
    end
    if not bestResult then dbg("수직 벽 없음"); refund(); return end

    dbg("벽 발견: " .. bestResult.Instance.Name .. " 거리=" .. math.floor(bestDist))
    local targetPart = bestResult.Instance

    -- 8. SurfaceGui 렌더링
    graffitiCount += 1
    local ok, err = pcall(_renderGraffiti, targetPart, bestResult.Normal, validatedStrokes, player.Name)
    if not ok then
        graffitiCount -= 1
        refund()
        dbg("렌더링 실패: " .. tostring(err))
        return
    end
    dbg("렌더링 성공!")

    -- 9. 클라이언트 HUD 업데이트
    local Events = game.ReplicatedStorage.Events
    updateToolName(player, "spray", PlayerManager.getSprayCount(player))
    Events.UpdateHUD:FireClient(player, {
        type  = "sprayUsed",
        count = PlayerManager.getSprayCount(player),
    })
end

return ItemManager
