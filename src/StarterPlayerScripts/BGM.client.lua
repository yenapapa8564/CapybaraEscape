-- StarterPlayerScripts/BGM.client.lua
-- 헌터 발견 상태 + 40 studs 이내일 때만 긴박한 BGM 전환
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Events = game.ReplicatedStorage.Events

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ⚠️ SoundId를 실제 Roblox 오디오 에셋 ID로 교체하세요
-- Toolbox → 오디오 탭 → 검색 → 에셋 ID 복사
local PEACEFUL_ID = 0   -- 평화로운 BGM 에셋 ID
local TENSE_ID    = 0   -- 긴박한 BGM 에셋 ID
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local BGM_VOLUME    = 0.45   -- 기본 볼륨
local DETECT_RADIUS = 40     -- 긴박 전환 거리 (studs)
local FADE_TIME     = 1.5    -- 크로스페이드 시간 (초)

-- Sound 오브젝트 생성 (ID = 0 이면 nil 반환 → 에러 방지)
local function makeSound(id)
    if not id or id == 0 then return nil end
    local s = Instance.new("Sound")
    s.SoundId  = "rbxassetid://" .. id
    s.Volume   = 0
    s.Looped   = true
    s.RollOffMaxDistance = 0  -- 글로벌 2D 사운드
    s.Parent   = SoundService
    return s
end

local peacefulSound = makeSound(PEACEFUL_ID)
local tenseSound    = makeSound(TENSE_ID)

local function fade(sound, toVolume)
    if not sound then return end
    TweenService:Create(
        sound,
        TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine),
        { Volume = toVolume }
    ):Play()
end

local currentMode = nil   -- "peaceful" | "tense"

local function setMode(mode)
    if currentMode == mode then return end
    currentMode = mode
    if mode == "peaceful" then
        if peacefulSound and not peacefulSound.IsPlaying then peacefulSound:Play() end
        fade(peacefulSound, BGM_VOLUME)
        fade(tenseSound, 0)
    else  -- "tense"
        if tenseSound and not tenseSound.IsPlaying then tenseSound:Play() end
        fade(tenseSound, BGM_VOLUME)
        fade(peacefulSound, 0)
    end
end

-- 시작: 평화로운 BGM (사운드 ID가 설정된 경우만)
if peacefulSound then peacefulSound:Play() end
setMode("peaceful")

-- ── 헌터 발견 상태 추적 ───────────────────────────
local isDetected = false

Events.HunterAlert.OnClientEvent:Connect(function(detected)
    isDetected = detected
    -- 발견 해제 시 즉시 평화로운 BGM (거리 무관)
    if not detected then
        setMode("peaceful")
    end
end)

-- ── 매 프레임: 발견 중 + 40 studs 이내일 때만 긴박 ──
RunService.Heartbeat:Connect(function()
    if not isDetected then return end  -- 미발견이면 체크 안 함

    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hunter = workspace:FindFirstChild("Hunter")
    if not hunter then
        isDetected = false
        setMode("peaceful")
        return
    end

    -- Hunter 모델에서 HumanoidRootPart 탐색
    local hunterHRP = hunter:FindFirstChild("HumanoidRootPart")
    if not hunterHRP then
        for _, child in ipairs(hunter:GetDescendants()) do
            if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
                hunterHRP = child
                break
            end
        end
    end
    if not hunterHRP then return end

    local dist = (hrp.Position - hunterHRP.Position).Magnitude
    if dist <= DETECT_RADIUS then
        setMode("tense")
    else
        setMode("peaceful")
    end
end)
