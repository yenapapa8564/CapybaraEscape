-- ServerScriptService/Modules/HunterAI
local HunterAI = {}

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local hunterModel = nil
local difficulty = "Normal"
local isStunned = false
local aiThread = nil     -- task.spawn 반환 스레드
local currentStage = 1   -- stun 회복 후 속도 복원에 사용
local lastDetected = nil -- 현재 추적 중인 플레이어 (BGM 이벤트용)

-- 추가 헌터 목록 (1분마다 스폰)
local extraHunters = {}          -- {model, thread}
local storedTouchCallback = nil  -- onTouched 에서 받은 콜백 저장

-- ── 공통 파트 생성 헬퍼 ──────────────────────────────────────────────────
local function makePart(model, name, sz, color, collide)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = sz
    p.Color = color
    p.Material = Enum.Material.SmoothPlastic
    p.Anchored = false
    p.CanCollide = collide or false
    p.CastShadow = true
    p.Parent = model
    return p
end

local function weldPart(a, b, offset)
    b.CFrame = a.CFrame * CFrame.new(offset)
    local w = Instance.new("WeldConstraint")
    w.Part0 = a
    w.Part1 = b
    w.Parent = a
end

-- ── 연막 안에 있는지 확인 ────────────────────────────────────────────────────
local function isInSmoke(hrp)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Folder") then
            for _, child in ipairs(obj:GetChildren()) do
                if child.Name == "SmokeCloud" and child:IsA("Model") then
                    local cloud = child:FindFirstChild("SmokeCloud")
                    if cloud and (hrp.Position - cloud.Position).Magnitude < cloud.Size.X / 2 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ── 터치 감지 공통 설정 ────────────────────────────────────────────────────
local function setupTouchDetection(model, callback)
    if not model then return end
    local root = model.PrimaryPart
    if not root then return end

    local debounce = {}
    root.Touched:Connect(function(hit)
        local char = hit.Parent
        if not char then return end
        local player = game.Players:GetPlayerFromCharacter(char)
        if not player then return end
        if debounce[player] then return end

        local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
        if PlayerManager.getState(player) == "alive" then
            -- 연막 안에 있으면 접촉해도 잡히지 않음
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp and isInSmoke(hrp) then return end
            debounce[player] = true
            callback(player)
            task.delay(0.5, function()
                debounce[player] = nil
            end)
        end
    end)
end

-- ── 가장 가까운 생존 플레이어 ──────────────────────────────────────────────
local function getNearestAlivePlayer(fromModel)
    local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
    local alivePlayers = PlayerManager.getAlivePlayers()
    if #alivePlayers == 0 then return nil, math.huge end

    local srcModel = fromModel or hunterModel
    local root = srcModel and srcModel.PrimaryPart
    if not root then return nil, math.huge end

    local nearest, minDist = nil, math.huge
    for _, player in ipairs(alivePlayers) do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- 연막 안 플레이어는 감지 불가
                if isInSmoke(hrp) then continue end
                local dist = (hrp.Position - root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    nearest = player
                end
            end
        end
    end
    return nearest, minDist
end

-- ── 메인 헌터 생성 ────────────────────────────────────────────────────────
function HunterAI.spawn(spawnPosition, diff)
    difficulty = diff or "Normal"
    currentStage = 1

    if hunterModel then
        hunterModel:Destroy()
        hunterModel = nil
    end

    local dark  = Constants.COLORS.Hunter
    local red   = Color3.fromRGB(220, 40, 40)

    local model = Instance.new("Model")
    model.Name = "Hunter"

    local hrp = makePart(model, "HumanoidRootPart", Vector3.new(2.5, 3, 1.5), dark, true)
    hrp.CFrame = CFrame.new(spawnPosition)
    model.PrimaryPart = hrp

    local head = makePart(model, "Head", Vector3.new(2.2, 2.2, 2.2), dark)
    weldPart(hrp, head, Vector3.new(0, 2.6, 0))

    local eyeL = makePart(model, "EyeL", Vector3.new(0.5, 0.5, 0.15), red)
    weldPart(head, eyeL, Vector3.new(-0.55, 0.15, -1.1))
    local eyeR = makePart(model, "EyeR", Vector3.new(0.5, 0.5, 0.15), red)
    weldPart(head, eyeR, Vector3.new( 0.55, 0.15, -1.1))

    local armL = makePart(model, "ArmL", Vector3.new(0.9, 2.8, 0.9), dark)
    weldPart(hrp, armL, Vector3.new(-1.7, 0.1, 0))
    local armR = makePart(model, "ArmR", Vector3.new(0.9, 2.8, 0.9), dark)
    weldPart(hrp, armR, Vector3.new( 1.7, 0.1, 0))

    local legL = makePart(model, "LegL", Vector3.new(1, 2.8, 1), dark)
    weldPart(hrp, legL, Vector3.new(-0.75, -2.9, 0))
    local legR = makePart(model, "LegR", Vector3.new(1, 2.8, 1), dark)
    weldPart(hrp, legR, Vector3.new( 0.75, -2.9, 0))

    local humanoid = Instance.new("Humanoid")
    humanoid.WalkSpeed = Constants.HUNTER[difficulty].baseSpeed
    humanoid.MaxHealth = math.huge
    humanoid.Health = math.huge
    humanoid.Parent = model

    model.Parent = workspace
    hunterModel = model
    isStunned = false
    return model
end

-- ── 추가 헌터 생성 (1분마다 스폰, 단순 추적 AI) ─────────────────────────
function HunterAI.spawnExtra(position)
    -- 심홍색(진한 빨강)으로 메인 헌터와 구별
    local crimson = Color3.fromRGB(120, 10, 10)
    local orange  = Color3.fromRGB(255, 80, 0)

    local model = Instance.new("Model")
    model.Name = "HunterExtra"

    local hrp = makePart(model, "HumanoidRootPart", Vector3.new(2.5, 3, 1.5), crimson, true)
    -- 바닥 Raycast로 유효 Y 위치 보정 (벽 안 스폰 방지)
    local rayResult = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -30, 0))
    local safeY = rayResult and (rayResult.Position.Y + 2.5) or (position.Y + 2.5)
    hrp.CFrame = CFrame.new(position.X, safeY, position.Z)
    model.PrimaryPart = hrp

    local head = makePart(model, "Head", Vector3.new(2.2, 2.2, 2.2), crimson)
    weldPart(hrp, head, Vector3.new(0, 2.6, 0))

    -- 주황 눈 (메인 헌터의 빨간 눈과 구별)
    local eyeL = makePart(model, "EyeL", Vector3.new(0.5, 0.5, 0.15), orange)
    weldPart(head, eyeL, Vector3.new(-0.55, 0.15, -1.1))
    local eyeR = makePart(model, "EyeR", Vector3.new(0.5, 0.5, 0.15), orange)
    weldPart(head, eyeR, Vector3.new( 0.55, 0.15, -1.1))

    local armL = makePart(model, "ArmL", Vector3.new(0.9, 2.8, 0.9), crimson)
    weldPart(hrp, armL, Vector3.new(-1.7, 0.1, 0))
    local armR = makePart(model, "ArmR", Vector3.new(0.9, 2.8, 0.9), crimson)
    weldPart(hrp, armR, Vector3.new( 1.7, 0.1, 0))

    local legL = makePart(model, "LegL", Vector3.new(1, 2.8, 1), crimson)
    weldPart(hrp, legL, Vector3.new(-0.75, -2.9, 0))
    local legR = makePart(model, "LegR", Vector3.new(1, 2.8, 1), crimson)
    weldPart(hrp, legR, Vector3.new( 0.75, -2.9, 0))

    -- 머리 위 "⚠" 표시
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 60, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = false
    bb.Parent = head
    local lbl = Instance.new("TextLabel")
    lbl.Text = "⚠"
    lbl.TextScaled = true
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextColor3 = Color3.fromRGB(255, 200, 0)
    lbl.Parent = bb

    -- 몇 번째 추가 헌터인지 (0-based)
    local tier = #extraHunters  -- 0=첫 번째, 1=두 번째 ...

    local humanoid = Instance.new("Humanoid")
    -- 티어마다 속도 +3, 최대 50
    local config = Constants.HUNTER[difficulty]
    local baseSpd = math.min(config.baseSpeed + config.increment * (currentStage - 1), config.maxSpeed)
    local spd = math.min(baseSpd + (tier + 1) * 3, 50)
    humanoid.WalkSpeed = spd
    humanoid.MaxHealth = math.huge
    humanoid.Health = math.huge
    humanoid.Parent = model

    -- 티어 표시: ⚠ 개수로 강도 표현
    lbl.Text = string.rep("⚠", tier + 1)
    lbl.TextColor3 = tier == 0 and Color3.fromRGB(255, 200, 0)
                  or tier == 1 and Color3.fromRGB(255, 120, 0)
                  or Color3.fromRGB(255, 40, 40)

    -- 티어별 몸 색상도 점점 밝아짐 (더 위협적으로)
    local tierColor = tier == 0 and Color3.fromRGB(140, 10, 10)
                   or tier == 1 and Color3.fromRGB(180, 10, 10)
                   or Color3.fromRGB(220, 10, 10)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p.Color == crimson then
            p.Color = tierColor
        end
    end

    model.Parent = workspace

    -- 터치 감지 (저장된 콜백 사용)
    if storedTouchCallback then
        setupTouchDetection(model, storedTouchCallback)
    end

    -- 티어별 AI 업그레이드
    -- tier 0: 직선 이동 (단순)
    -- tier 1+: PathfindingService 사용 (스마트)
    local updateInterval = math.max(0.15, 0.35 - tier * 0.08)

    local thread = task.spawn(function()
        while model and model.Parent do
            local nearest, _ = getNearestAlivePlayer(model)
            if nearest then
                local char = nearest.Character
                local hrp2 = char and char:FindFirstChild("HumanoidRootPart")
                local hum = model:FindFirstChild("Humanoid")
                if hrp2 and hum then
                    if tier >= 1 then
                        -- PathfindingService로 스마트 이동
                        local path = PathfindingService:CreatePath({
                            AgentRadius = 2, AgentHeight = 5,
                            AgentCanJump = false,
                        })
                        local ok, err = pcall(function()
                            path:ComputeAsync(model.PrimaryPart.Position, hrp2.Position)
                        end)
                        if ok and path.Status == Enum.PathStatus.Success then
                            local wps = path:GetWaypoints()
                            if wps[2] then hum:MoveTo(wps[2].Position) end
                        else
                            hum:MoveTo(hrp2.Position)
                        end
                    else
                        -- 직선 이동 (tier 0)
                        hum:MoveTo(hrp2.Position)
                    end
                end
            end
            task.wait(updateInterval)
        end
    end)

    table.insert(extraHunters, {model = model, thread = thread})
    return model
end

-- ── 속도 갱신 ─────────────────────────────────────────────────────────────
function HunterAI.updateSpeedForStage(stage)
    currentStage = stage
    if not hunterModel then return end
    local config = Constants.HUNTER[difficulty]
    local speed = math.min(
        config.baseSpeed + config.increment * (stage - 1),
        config.maxSpeed
    )
    local humanoid = hunterModel:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = speed
    end
end

function HunterAI.getCurrentStageSpeed(stage)
    local config = Constants.HUNTER[difficulty]
    return math.min(config.baseSpeed + config.increment * (stage - 1), config.maxSpeed)
end

-- ── 스턴 시각 효과 ────────────────────────────────────────────────────────
local function applyStunVisual()
    if not hunterModel then return end
    local stunColor  = Color3.fromRGB(255, 220, 50)
    local eyeColor   = Color3.fromRGB(255, 255, 255)

    for _, part in ipairs(hunterModel:GetDescendants()) do
        if part:IsA("BasePart") then
            part:SetAttribute("OrigColor", tostring(part.Color.R)..","..tostring(part.Color.G)..","..tostring(part.Color.B))
            if part.Name == "EyeL" or part.Name == "EyeR" then
                part.Color = eyeColor
            else
                part.Color = stunColor
            end
        end
    end

    local head = hunterModel:FindFirstChild("Head")
    if head then
        local bb = Instance.new("BillboardGui")
        bb.Name = "StunBillboard"
        bb.Size = UDim2.new(0, 80, 0, 80)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.Parent = head

        local label = Instance.new("TextLabel")
        label.Text = "💫"
        label.TextScaled = true
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Parent = bb
    end
end

local function removeStunVisual()
    if not hunterModel then return end
    local dark = Constants.COLORS.Hunter
    local red  = Color3.fromRGB(220, 40, 40)

    for _, part in ipairs(hunterModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name == "EyeL" or part.Name == "EyeR" then
                part.Color = red
            else
                part.Color = dark
            end
        end
    end

    local head = hunterModel:FindFirstChild("Head")
    if head then
        local bb = head:FindFirstChild("StunBillboard")
        if bb then bb:Destroy() end
    end
end

function HunterAI.stun()
    if not hunterModel or isStunned then return end
    isStunned = true
    local humanoid = hunterModel:FindFirstChild("Humanoid")
    if humanoid then humanoid.WalkSpeed = 0 end

    applyStunVisual()

    task.delay(Constants.TRAP_STUN_DURATION, function()
        isStunned = false
        removeStunVisual()
        HunterAI.updateSpeedForStage(currentStage)
    end)
end

-- ── 경로 추적 ─────────────────────────────────────────────────────────────
-- 벽에 막혔을 때 헌터를 약간 밀어내는 헬퍼
local function nudgeOutOfWall(root)
    local offsets = {
        Vector3.new( 4, 0,  0), Vector3.new(-4, 0,  0),
        Vector3.new( 0, 0,  4), Vector3.new( 0, 0, -4),
        Vector3.new( 3, 0,  3), Vector3.new(-3, 0, -3),
    }
    for _, offset in ipairs(offsets) do
        local testPos = root.Position + offset
        local ray = workspace:Raycast(testPos + Vector3.new(0,3,0), Vector3.new(0,-6,0))
        if ray then
            root.CFrame = CFrame.new(testPos.X, ray.Position.Y + 2.5, testPos.Z)
            return
        end
    end
end

local function followPath(targetPos, maxWP)
    if not hunterModel or isStunned then return end
    local humanoid = hunterModel:FindFirstChild("Humanoid")
    local root     = hunterModel.PrimaryPart
    if not humanoid or not root then return end

    local path = PathfindingService:CreatePath({
        AgentHeight   = 5,
        AgentRadius   = 1.0,  -- 반경 줄여서 좁은 통로 통과율 향상
        AgentCanJump  = false,
        Costs         = { Water = 20 },
    })
    local ok = pcall(function()
        path:ComputeAsync(root.Position, targetPos)
    end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        -- 경로 실패 시 직선 이동 대신 잠시 대기 후 재시도 유도
        task.wait(0.4)
        return
    end

    local wps   = path:GetWaypoints()
    local count = 0
    for _, wp in ipairs(wps) do
        if isStunned or not hunterModel then return end

        local prePos = root.Position
        humanoid:MoveTo(wp.Position)

        local moved, conn = false, nil
        conn = humanoid.MoveToFinished:Connect(function()
            moved = true
            conn:Disconnect()
        end)
        local t = 0
        while not moved and t < 1.5 do
            task.wait(0.1)
            t += 0.1
        end
        if conn then pcall(function() conn:Disconnect() end) end

        -- stuck 감지: 1.5초 대기 후 위치가 1 stud 미만으로 변했으면 벽에 박힌 것
        if (root.Position - prePos).Magnitude < 1.0 then
            nudgeOutOfWall(root)
            break  -- 경로 재계산을 위해 이번 followPath 종료
        end

        count += 1
        if count >= maxWP then break end
    end
end

-- ── 똥(CapyPoop) 위치 탐지 ────────────────────────────────────────────────
local function getNearestPoopPosition()
    if not hunterModel then return nil end
    local root = hunterModel.PrimaryPart
    if not root then return nil end

    local nearest, minDist = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "CapyPoop" then
            local base = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if base then
                local dist = (base.Position - root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    nearest = { pos = base.Position, model = obj }
                end
            end
        end
    end
    return nearest
end

-- ── 순찰 포인트 ────────────────────────────────────────────────────────────
local patrolPoints = {}
local patrolIndex  = 1

function HunterAI.setPatrolPoints(points)
    patrolPoints = points
    patrolIndex  = 1
end

-- ── 메인 AI 루프 ──────────────────────────────────────────────────────────
function HunterAI.startAI()
    if aiThread then
        pcall(task.cancel, aiThread)
        aiThread = nil
    end

    local sightRange, maxWP, patrolWait
    if difficulty == "Easy" then
        sightRange  = 40
        maxWP       = 2
        patrolWait  = 0.8
    elseif difficulty == "Normal" then
        sightRange  = 999
        maxWP       = 3
        patrolWait  = 0.5
    else  -- Hard
        sightRange  = 999
        maxWP       = 5
        patrolWait  = 0.2
    end

    local Events = ReplicatedStorage.Events

    local function updateDetected(newTarget)
        if newTarget == lastDetected then return end
        if lastDetected then
            pcall(function()
                Events.HunterAlert:FireClient(lastDetected, false)
            end)
        end
        if newTarget then
            pcall(function()
                Events.HunterAlert:FireClient(newTarget, true)
            end)
        end
        lastDetected = newTarget
    end

    aiThread = task.spawn(function()
        while hunterModel and hunterModel.Parent do
            if isStunned then
                task.wait(0.3)
            else
                local nearest, dist = getNearestAlivePlayer()

                -- 똥 유인: 플레이어가 멀리 있을 때 CapyPoop 우선 추적
                local poopInfo = getNearestPoopPosition()
                if poopInfo and (not nearest or dist > 30) then
                    updateDetected(nil)
                    -- 똥 위치로 이동 (끝까지 따라감)
                    followPath(poopInfo.pos, 999)
                    -- 도착 후 무조건 똥 제거 (ws 미정의 버그 수정 → 거리 무관 제거)
                    if poopInfo.model and poopInfo.model.Parent then
                        poopInfo.model:Destroy()
                    end
                elseif nearest and dist <= sightRange then
                    updateDetected(nearest)
                    local char = nearest.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        followPath(hrp.Position, maxWP)
                    else
                        task.wait(0.2)
                    end
                else
                    updateDetected(nil)
                    if #patrolPoints > 0 then
                        local pt = patrolPoints[patrolIndex]
                        followPath(pt, 6)
                        patrolIndex = (patrolIndex % #patrolPoints) + 1
                    else
                        local root = hunterModel.PrimaryPart
                        if root then
                            local offset = Vector3.new(
                                math.random(-20, 20), 0, math.random(-20, 20)
                            )
                            followPath(root.Position + offset, 4)
                        else
                            task.wait(0.5)
                        end
                    end
                    task.wait(patrolWait)
                end
            end
        end
    end)
end

-- ── AI 중지 + 헌터 전체 제거 ─────────────────────────────────────────────
function HunterAI.stop()
    if aiThread then
        pcall(task.cancel, aiThread)
        aiThread = nil
    end
    -- 추적 대상에게 미발견 알림
    if lastDetected then
        pcall(function()
            ReplicatedStorage.Events.HunterAlert:FireClient(lastDetected, false)
        end)
        lastDetected = nil
    end
    if hunterModel then
        hunterModel:Destroy()
        hunterModel = nil
    end
    -- 추가 헌터 전체 정리
    for _, extra in ipairs(extraHunters) do
        if extra.thread then pcall(task.cancel, extra.thread) end
        if extra.model and extra.model.Parent then
            extra.model:Destroy()
        end
    end
    extraHunters = {}
    isStunned = false
end

-- ── 현재 모든 헌터 위치 반환 ─────────────────────────────────────────────
function HunterAI.getHunterPositions()
    local positions = {}
    local function addPos(model)
        if not model or not model.Parent then return end
        local hrp = model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChildWhichIsA("BasePart")
        if hrp then
            table.insert(positions, hrp.Position)
        end
    end
    addPos(hunterModel)
    for _, extra in ipairs(extraHunters) do
        addPos(extra.model)
    end
    return positions
end

-- ── 터치 콜백 등록 ────────────────────────────────────────────────────────
function HunterAI.onTouched(callback)
    storedTouchCallback = callback
    setupTouchDetection(hunterModel, callback)
end

return HunterAI
