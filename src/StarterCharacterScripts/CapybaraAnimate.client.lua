-- StarterCharacterScripts/CapybaraAnimate.client.lua
-- Bone.Transform 직접 조작 방식 — 카피바라 스킨드 메시 전용
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid", 10)
if not humanoid then return end

-- 기본 Animate 스크립트 제거 (충돌 방지)
local defaultAnimate = character:FindFirstChild("Animate")
if defaultAnimate then defaultAnimate:Destroy() end

-- ── Bone 오브젝트 수집 ────────────────────────────────────────────────────
local bones = {}
for _, v in ipairs(character:GetDescendants()) do
    if v:IsA("Bone") then
        bones[v.Name] = v
    end
end

-- ── 애니메이션에 사용할 핵심 뼈대 ────────────────────────────────────────
local B = {
    -- 앞다리 (fore)
    FL1 = bones["fore_leg_1.L"],  -- 앞왼 어깨 (주 스윙)
    FL2 = bones["fore_leg_2.L"],  -- 앞왼 팔꿈치
    FL3 = bones["fore_leg_3.L"],  -- 앞왼 손목
    FR1 = bones["fore_leg_1.R"],  -- 앞오 어깨 (주 스윙)
    FR2 = bones["fore_leg_2.R"],  -- 앞오 팔꿈치
    FR3 = bones["fore_leg_3.R"],  -- 앞오 손목
    -- 뒷다리 (rear)
    RL1 = bones["rear_leg_1.L"],  -- 뒤왼 엉덩이 (주 스윙)
    RL2 = bones["rear_leg_2.L"],  -- 뒤왼 무릎
    RR1 = bones["rear_leg_1.R"],  -- 뒤오 엉덩이 (주 스윙)
    RR2 = bones["rear_leg_2.R"],  -- 뒤오 무릎
    -- 척추·머리
    spine = bones["spine_2"],
    neck  = bones["neck_1"],
    -- 꼬리
    tail1 = bones["tail_1"],
    tail2 = bones["tail_2"],
}

-- ── 파라미터 ─────────────────────────────────────────────────────────────
-- 다리가 앞뒤 대신 좌우로 흔들리면 AXIS_IDX 를 3 으로 바꿔보세요
-- (1 = X축, 3 = Z축)
local AXIS_IDX = 1     -- 스윙 회전축 (1=X축, 3=Z축)

-- 이동 거리 기반 속도 동기화
-- 값 낮추면 보폭 느리게, 높이면 빠르게
local STEPS_PER_STUD = 0.9

local SWING   = 0.45   -- 어깨/엉덩이 최대 각도 (rad ≈ 26°)
local KNEE    = 0.30   -- 팔꿈치/무릎 굽힘 각도
local WRIST   = 0.15   -- 손목 각도
local BOB     = 0.035  -- 몸통 상하 진폭 (studs)

local function swingCF(angle)
    if AXIS_IDX == 1 then
        return CFrame.Angles(angle, 0, 0)
    else
        return CFrame.Angles(0, 0, angle)
    end
end

local walkPhase = 0
local hrp = character:FindFirstChild("HumanoidRootPart")

-- ── 메인 루프 ─────────────────────────────────────────────────────────────
local conn = RunService.Heartbeat:Connect(function(dt)
    if not humanoid.Parent then conn:Disconnect(); return end

    -- 실제 이동 속도(velocity)로 walkPhase 증가 → 이동 거리와 보폭 완벽 동기화
    local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
    local groundSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    local moving = groundSpeed > 0.5

    walkPhase += dt * groundSpeed * STEPS_PER_STUD

    -- 대각선 보행 (trot): FL+RR 동위상 / FR+RL 역위상
    local s  = moving and math.sin(walkPhase) or 0
    local s2 = -s

    local bob = moving and (math.abs(math.sin(walkPhase * 2)) * BOB) or 0

    -- 앞다리 ─────────────────────────────────────────────────────────────
    if B.FL1 then B.FL1.Transform = swingCF( s  * SWING) end
    if B.FR1 then B.FR1.Transform = swingCF( s2 * SWING) end
    -- 팔꿈치: 앞으로 나올 때 살짝 구부림
    if B.FL2 then B.FL2.Transform = swingCF(math.max(0,  s) * KNEE)  end
    if B.FR2 then B.FR2.Transform = swingCF(math.max(0, s2) * KNEE)  end
    -- 손목: 미세 굽힘
    if B.FL3 then B.FL3.Transform = swingCF(math.max(0,  s) * WRIST) end
    if B.FR3 then B.FR3.Transform = swingCF(math.max(0, s2) * WRIST) end

    -- 뒷다리 (앞다리 대각선 반대) ─────────────────────────────────────────
    if B.RR1 then B.RR1.Transform = swingCF( s  * SWING) end
    if B.RL1 then B.RL1.Transform = swingCF( s2 * SWING) end
    if B.RR2 then B.RR2.Transform = swingCF(math.max(0,  s) * KNEE) end
    if B.RL2 then B.RL2.Transform = swingCF(math.max(0, s2) * KNEE) end

    -- 척추 상하 흔들림 ────────────────────────────────────────────────────
    if B.spine then B.spine.Transform = CFrame.new(0, -bob, 0) end

    -- 머리 고개 끄덕임 (미세) ─────────────────────────────────────────────
    if B.neck then
        B.neck.Transform = CFrame.Angles(math.sin(walkPhase * 2) * 0.04, 0, 0)
    end

    -- 꼬리 좌우 흔들기 ────────────────────────────────────────────────────
    if B.tail1 then
        B.tail1.Transform = CFrame.Angles(0, math.sin(walkPhase * 0.8) * 0.25, 0)
    end
    if B.tail2 then
        B.tail2.Transform = CFrame.Angles(0, math.sin(walkPhase * 0.8 + 0.5) * 0.2, 0)
    end
end)

humanoid.Died:Connect(function()
    conn:Disconnect()
    for _, b in pairs(B) do
        if b then b.Transform = CFrame.identity end
    end
end)
