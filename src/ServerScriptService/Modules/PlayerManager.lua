-- ServerScriptService/Modules/PlayerManager
local PlayerManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

-- 상태: "alive" | "escaped" | "spectator"
local playerStates    = {}   -- [Player] = string
local hasTrapTable    = {}   -- [Player] = int
local carrotThreads   = {}   -- [Player] = thread (task.delay 취소용)
local playerCharTypes = {}   -- [Player] = "Dad"|"Mom"|"Son"|"Daughter"
local pendingCarrots  = {}   -- [Player] = int 0~3 (보유 당근 수)
local MAX_CARROTS     = 3
local smokeTable      = {}   -- [Player] = int 0~N
local sprayTable      = {}   -- [Player] = count

-- ── 캐릭터 타입 저장 ──────────────────────────────────────────────────────
function PlayerManager.setCharType(player, charType)
    playerCharTypes[player] = charType
end

function PlayerManager.getCharType(player)
    return playerCharTypes[player] or "Mom"
end

-- ── 리본(보우타이) 파트를 HRP에 용접하는 헬퍼 ────────────────────────────
local function makeWeldedPart(char, hrp, sz, color, offsetCF)
    local part = Instance.new("Part")
    part.Name     = "ColorRibbon"
    part.Size     = sz
    part.Color    = color
    part.Material = Enum.Material.SmoothPlastic
    part.Massless = true
    part.CanCollide  = false
    part.CastShadow  = false
    part.Parent   = char

    local w = Instance.new("Weld")
    w.Part0 = hrp
    w.Part1 = part
    w.C0    = offsetCF
    w.C1    = CFrame.identity
    w.Parent = hrp
    return part
end

-- 캐릭터 악세서리 파트를 HRP에 용접하는 헬퍼
local function makeAccessoryPart(char, hrp, sz, color, offsetCF)
    local part = Instance.new("Part")
    part.Name     = "CharAccessory"
    part.Size     = sz
    part.Color    = color
    part.Material = Enum.Material.SmoothPlastic
    part.Massless = true
    part.CanCollide  = false
    part.CastShadow  = false
    part.Parent   = char

    local w = Instance.new("Weld")
    w.Part0 = hrp
    w.Part1 = part
    w.C0    = offsetCF
    w.C1    = CFrame.identity
    w.Parent = hrp
    return part
end

-- ── Accessories 폴더 모델을 HRP에 용접하는 헬퍼 ──────────────────────────
-- modelName : ReplicatedStorage.Accessories 안의 모델 이름
-- offsetCF  : HRP 기준 위치/회전
-- scale     : 모델 전체 크기 배율 (1.0 = 원본)
local accFolder = ReplicatedStorage:FindFirstChild("Accessories")

local function attachModelAccessory(char, hrp, modelName, offsetCF, scale)
    if not accFolder then return end
    local template = accFolder:FindFirstChild(modelName)
    if not template then
        warn("[Accessory] 모델 없음:", modelName)
        return
    end

    local model = template:Clone()
    model.Name  = "CharAccessory"
    model.Parent = char

    -- 모든 BasePart 수집 및 물리 설정
    local parts = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored   = false
            desc.CanCollide = false
            desc.CastShadow = false
            desc.Massless   = true
            table.insert(parts, desc)
        end
    end
    if #parts == 0 then return end

    -- 스케일 적용 (크기 + 상대 위치 비례 축소)
    scale = scale or 1.0
    if scale ~= 1.0 then
        -- 모델 중심 기준으로 상대 위치 스케일
        local modelCF = model:GetBoundingBox()
        for _, part in ipairs(parts) do
            local relPos = modelCF:PointToObjectSpace(part.Position)
            part.Size    = part.Size * scale
            part.CFrame  = modelCF * CFrame.new(relPos * scale)
        end
    end

    -- 루트 파트 결정 (PrimaryPart 우선, 없으면 첫 번째 Handle, 없으면 parts[1])
    local root = model.PrimaryPart
        or model:FindFirstChild("Handle")
        or parts[1]

    -- 루트 → HRP 용접
    local w0 = Instance.new("Weld")
    w0.Part0  = hrp
    w0.Part1  = root
    w0.C0     = offsetCF
    w0.C1     = CFrame.identity
    w0.Parent = hrp

    -- 나머지 파트 → 루트 용접 (상대 위치 유지)
    for _, part in ipairs(parts) do
        if part ~= root then
            local w = Instance.new("Weld")
            w.Part0  = root
            w.Part1  = part
            w.C0     = root.CFrame:ToObjectSpace(part.CFrame)
            w.C1     = CFrame.identity
            w.Parent = root
        end
    end
end

-- ── 캐릭터 크기 스케일 적용 (R15 NumberValue 방식) ───────────────────────
local function applyBodyScale(char, scale)
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end
    local scaleNames = {
        "BodyDepthScale", "BodyHeightScale",
        "BodyWidthScale", "HeadScale"
    }
    for _, sn in ipairs(scaleNames) do
        local sv = humanoid:FindFirstChild(sn)
        if sv and sv:IsA("NumberValue") then
            sv.Value = sv.Value * scale
        end
    end
end

-- ── 캐릭터 타입 악세서리 적용 ─────────────────────────────────────────────
function PlayerManager.applyCharType(player)
    local charType = playerCharTypes[player] or "Mom"
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- 기존 악세서리 제거
    for _, child in ipairs(char:GetChildren()) do
        if child.Name == "CharAccessory" then child:Destroy() end
    end

    -- 아이 캐릭터는 50% 크기
    local isChild = (charType == "Son" or charType == "Daughter")
    local s = isChild and 0.5 or 1.0   -- 스케일 배율

    if isChild then
        applyBodyScale(char, 0.5)
    end

    -- HRP 기준 악세서리 위치 (스케일 반영)
    local HY =  1.8 * s   -- 위쪽
    local HZ = -2.2 * s   -- 앞쪽

    if charType == "Dad" then
        -- ⛑️ 안전모: 머리 위 (앞쪽 -Z, 위쪽 +Y)
        attachModelAccessory(char, hrp, "DadHelmet",
            CFrame.new(0, HY + 0.5, HZ + 1.0), 1.0)

    elseif charType == "Mom" then
        -- 👒 챙모자: 머리 위 (얼굴 덮지 않게 뒤로 + 위로)
        attachModelAccessory(char, hrp, "MomHat",
            CFrame.new(0, HY + 0.8, HZ + 1.5), 1.0)

    elseif charType == "Son" then
        -- 🛡️ 방패: ReplicatedStorage.Accessories.SonCap 모델 사용 (등 뒤)
        attachModelAccessory(char, hrp, "SonCap",
            CFrame.new(0, 0, 2.0) * CFrame.Angles(math.rad(90), 0, 0), s)

    elseif charType == "Daughter" then
        -- 🎀 리본: ReplicatedStorage.Accessories.DaughterRibbon 모델 사용 (머리 위)
        attachModelAccessory(char, hrp, "DaughterRibbon",
            CFrame.new(0, HY, HZ), s)
    end

    -- ── 아이 공통 능력: 이동속도 +20% ────────────────────────────────────────
    if isChild then
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = Constants.PLAYER_BASE_SPEED * 1.2
        end
    end
end

-- ── 초기화 ────────────────────────────────────────────────────────────────
function PlayerManager.init(players)
    playerStates = {}
    hasTrapTable = {}
    pendingCarrots = {}
    smokeTable = {}
    sprayTable = {}
    for player, thread in pairs(carrotThreads) do
        pcall(task.cancel, thread)
    end
    carrotThreads = {}

    for _, player in ipairs(players) do
        playerStates[player] = "alive"
        hasTrapTable[player] = 0
        sprayTable[player] = 0
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = Constants.PLAYER_BASE_SPEED
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide  = true
                    part.Transparency = 0
                end
            end
        end
    end
end

function PlayerManager.getState(player)
    return playerStates[player]
end

function PlayerManager.setEscaped(player)
    playerStates[player] = "escaped"
end

function PlayerManager.eliminate(player)
    playerStates[player] = "spectator"
    local char = player.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide   = false
                part.Transparency = 0.8
            end
        end
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 0
        end
    end
    local Events = game.ReplicatedStorage.Events
    Events.PlayerEliminated:FireClient(player)
end

function PlayerManager.getAliveCount()
    local count = 0
    for _, state in pairs(playerStates) do
        if state == "alive" then count += 1 end
    end
    return count
end

function PlayerManager.getSurvivorCount()
    local count = 0
    for _, state in pairs(playerStates) do
        if state == "alive" or state == "escaped" then count += 1 end
    end
    return count
end

function PlayerManager.getEscapedCount()
    local count = 0
    for _, state in pairs(playerStates) do
        if state == "escaped" then count += 1 end
    end
    return count
end

function PlayerManager.getAlivePlayers()
    local list = {}
    for player, state in pairs(playerStates) do
        if state == "alive" then table.insert(list, player) end
    end
    return list
end

function PlayerManager.getSurvivorPlayers()
    local list = {}
    for player, state in pairs(playerStates) do
        if state == "alive" or state == "escaped" then
            table.insert(list, player)
        end
    end
    return list
end

function PlayerManager.giveTrap(player)
    hasTrapTable[player] = (hasTrapTable[player] or 0) + 1
end

function PlayerManager.consumeTrap(player)
    local count = hasTrapTable[player] or 0
    if count > 0 then
        hasTrapTable[player] = count - 1
        return true
    end
    return false
end

function PlayerManager.hasTrap(player)
    return (hasTrapTable[player] or 0) > 0
end

function PlayerManager.getTrapCount(player)
    return hasTrapTable[player] or 0
end

-- ── 당근 대기 상태 ────────────────────────────────────────────────────────
-- 당근 1개 추가 (최대 MAX_CARROTS). 추가 후 보유 수 반환
function PlayerManager.addCarrot(player)
    local cur = pendingCarrots[player] or 0
    if cur >= MAX_CARROTS then return cur end
    pendingCarrots[player] = cur + 1
    return pendingCarrots[player]
end

function PlayerManager.getCarrotCount(player)
    return pendingCarrots[player] or 0
end

function PlayerManager.hasPendingCarrot(player)
    return (pendingCarrots[player] or 0) > 0
end

-- 하위 호환용 (ItemManager에서 직접 호출 시)
function PlayerManager.setPendingCarrot(player, value)
    if value then
        PlayerManager.addCarrot(player)
    else
        pendingCarrots[player] = 0
    end
end

-- ── 당근 효과 1: 속도 증가 ────────────────────────────────────────────────
-- 엄마 능력: 지속시간 2배
function PlayerManager.applySpeedBoost(player)
    pendingCarrots[player] = math.max((pendingCarrots[player] or 1) - 1, 0)
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end

    humanoid.WalkSpeed = Constants.CARROT_SPEED

    if carrotThreads[player] then
        pcall(task.cancel, carrotThreads[player])
        carrotThreads[player] = nil
    end

    -- 엄마: 지속시간 2배 / 아들: 복귀 속도도 +2 유지
    local charType = playerCharTypes[player] or "Mom"
    local duration = (charType == "Mom") and (Constants.CARROT_DURATION * 2) or Constants.CARROT_DURATION
    local restoreSpeed = (charType == "Son") and (Constants.PLAYER_BASE_SPEED + 2) or Constants.PLAYER_BASE_SPEED

    carrotThreads[player] = task.delay(duration, function()
        carrotThreads[player] = nil
        local c = player.Character
        if c then
            local h = c:FindFirstChild("Humanoid")
            if h then h.WalkSpeed = restoreSpeed end
        end
    end)
end

-- ── 당근 효과 2: 💩 위치 표시 (쌓인 구체 더미 모양) ──────────────────────
function PlayerManager.applyPoop(player)
    pendingCarrots[player] = math.max((pendingCarrots[player] or 1) - 1, 0)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local bx = hrp.Position.X
    local bz = hrp.Position.Z

    -- Raycast로 실제 바닥 Y 탐지
    local rayResult = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0))
    local floorY = rayResult and rayResult.Position.Y or (hrp.Position.Y - 2.5)

    local model = Instance.new("Model")
    model.Name   = "CapyPoop"
    model.Parent = workspace

    local template = game.ReplicatedStorage:FindFirstChild("PoopModel")
    local base

    if template then
        local mesh = template:Clone()
        mesh.Name       = "PoopMesh"
        mesh.Anchored   = true
        mesh.CanCollide = false
        mesh.CastShadow = true
        mesh.Size       = Vector3.new(2.5, 2.5, 2.5)  -- 고정 크기
        mesh.CFrame     = CFrame.new(bx, floorY + 1.25, bz)
                          * CFrame.Angles(0, math.random(0, 6), 0)
        mesh.Parent     = model
        base = mesh
    else
        -- fallback: 쌓인 구체 더미
        local function addSphere(sz, oy)
            local s = Instance.new("Part")
            s.Shape    = Enum.PartType.Ball
            s.Size     = Vector3.new(sz, sz, sz)
            s.Color    = Color3.fromRGB(101, 67, 33)
            s.Material = Enum.Material.SmoothPlastic
            s.Anchored = true
            s.CanCollide = false
            s.CastShadow = false
            s.Position = Vector3.new(bx, floorY + oy, bz)
            s.Parent   = model
            return s
        end
        base = addSphere(1.6, 0.8)
               addSphere(1.2, 1.8)
               addSphere(0.85, 2.6)
               addSphere(0.45, 3.2)
    end

    -- 스테이지 종료까지 유지 (ItemManager.clear 에서 제거됨)
end

-- 하위 호환용 (기존 코드에서 applyCarrot 호출 시 속도 증가로 처리)
function PlayerManager.applyCarrot(player)
    PlayerManager.applySpeedBoost(player)
end

-- ── 연막탄 상태 ────────────────────────────────────────────────────────────
function PlayerManager.addSmoke(player)
    smokeTable[player] = (smokeTable[player] or 0) + 1
    return smokeTable[player]
end

function PlayerManager.getSmokeCount(player)
    return smokeTable[player] or 0
end

function PlayerManager.consumeSmoke(player)
    if (smokeTable[player] or 0) <= 0 then return false end
    smokeTable[player] -= 1
    return true
end

-- ── 스프레이 캔 상태 ────────────────────────────────────────────────────────
function PlayerManager.addSpray(player)
    sprayTable[player] = (sprayTable[player] or 0) + 1
    return sprayTable[player]
end

function PlayerManager.consumeSpray(player)
    if (sprayTable[player] or 0) < 1 then return false end
    sprayTable[player] = sprayTable[player] - 1
    return true
end

function PlayerManager.getSprayCount(player)
    return sprayTable[player] or 0
end

return PlayerManager
