-- StarterPlayerScripts/LobbyUI
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

-- ── 캐릭터 데이터 ─────────────────────────────────────────────────────────────
-- 부모/아이 공통 능력
local PARENT_STATS = { { label = "속도", color = Color3.fromRGB(80, 160, 240), value = 0.55 },
                       { label = "특기", color = Color3.fromRGB(180, 130, 255), value = 0.90 } }
local CHILD_STATS  = { { label = "속도", color = Color3.fromRGB(80, 160, 240), value = 0.90 },
                       { label = "특기", color = Color3.fromRGB(180, 130, 255), value = 0.75 } }

local CHAR_OPTIONS = {
    {
        name    = "아빠",
        type    = "Dad",
        image   = "rbxassetid://105074816410243",
        color   = Color3.fromRGB(72, 108, 196),
        tagline = "든든한 발판",
        ability = "아이템 효과 2배  |  탑승 시 속도 유지",
        desc    = "아들·딸이 등에 타도 이동속도가\n줄어들지 않는다. 스모크·함정 등\n모든 아이템 효과가 두 배가 된다.",
        stats   = PARENT_STATS,
    },
    {
        name    = "엄마",
        type    = "Mom",
        image   = "rbxassetid://85018450386389",
        color   = Color3.fromRGB(196, 88, 148),
        tagline = "가족의 중심",
        ability = "아이템 효과 2배  |  탑승 시 속도 유지",
        desc    = "아들·딸이 등에 타도 이동속도가\n줄어들지 않는다. 스모크·함정 등\n모든 아이템 효과가 두 배가 된다.",
        stats   = PARENT_STATS,
    },
    {
        name    = "아들",
        type    = "Son",
        image   = "rbxassetid://119075418626992",
        color   = Color3.fromRGB(60, 172, 96),
        tagline = "빠른 정찰대",
        ability = "이동속도 +20%  |  열쇠 감지 +40%",
        desc    = "누구보다 빠르게 미로를 누빈다.\n근처의 열쇠 아이템을 남들보다\n일찍 감지해 팀원을 구출할 수 있다.",
        stats   = CHILD_STATS,
    },
    {
        name    = "딸",
        type    = "Daughter",
        image   = "rbxassetid://77387992913413",
        color   = Color3.fromRGB(220, 140, 50),
        tagline = "지름길을 찾는 눈",
        ability = "이동속도 +20%  |  열쇠 감지 +40%",
        desc    = "누구보다 빠르게 미로를 누빈다.\n근처의 열쇠 아이템을 남들보다\n일찍 감지해 팀원을 구출할 수 있다.",
        stats   = CHILD_STATS,
    },
}

-- ── 색상 상수 ──────────────────────────────────────────────────────────────
local C_BG      = Color3.fromRGB(14, 14, 18)
local C_PANEL   = Color3.fromRGB(22, 22, 28)
local C_CARD    = Color3.fromRGB(32, 32, 40)
local C_CARD_ON = Color3.fromRGB(42, 42, 54)
local C_BORDER  = Color3.fromRGB(50, 50, 64)
local C_ACCENT  = Color3.fromRGB(100, 180, 255)
local C_TEXT    = Color3.fromRGB(235, 235, 245)
local C_MUTED   = Color3.fromRGB(120, 120, 140)
local C_BLACK   = Color3.fromRGB(0, 0, 0)

local selectedCharType = "Mom"
local isReady          = false

-- ── ScreenGui ──────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.ResetOnSpawn = false
screenGui.Name         = "LobbyUI"
screenGui.Parent       = player.PlayerGui

-- ══════════════════════════════════════════════════════════════════════════
--  인트로 시퀀스
-- ══════════════════════════════════════════════════════════════════════════
local introScreen = Instance.new("Frame")
introScreen.Size                   = UDim2.new(1, 0, 1, 0)
introScreen.BackgroundColor3       = C_BLACK
introScreen.BackgroundTransparency = 0
introScreen.BorderSizePixel        = 0
introScreen.ZIndex                 = 50
introScreen.Parent                 = screenGui

local mainLabel = Instance.new("TextLabel")
mainLabel.Size               = UDim2.new(0.78, 0, 0, 60)
mainLabel.AnchorPoint        = Vector2.new(0.5, 0.5)
mainLabel.Position           = UDim2.new(0.5, 0, 0.5, 0)
mainLabel.BackgroundTransparency = 1
mainLabel.Font               = Enum.Font.Gotham
mainLabel.TextSize           = 22
mainLabel.TextColor3         = C_TEXT
mainLabel.TextXAlignment     = Enum.TextXAlignment.Center
mainLabel.TextYAlignment     = Enum.TextYAlignment.Center
mainLabel.TextTransparency   = 1
mainLabel.TextWrapped        = true
mainLabel.ZIndex             = 52
mainLabel.Parent             = introScreen
Instance.new("UIStroke", mainLabel).Color     = C_BLACK
Instance.new("UIStroke", mainLabel).Thickness = 2

local dotsLabel = Instance.new("TextLabel")
dotsLabel.Size               = UDim2.new(0, 140, 0, 24)
dotsLabel.AnchorPoint        = Vector2.new(0.5, 0)
dotsLabel.Position           = UDim2.new(0.5, 0, 0.5, 48)
dotsLabel.BackgroundTransparency = 1
dotsLabel.Font               = Enum.Font.Gotham
dotsLabel.TextSize           = 13
dotsLabel.TextColor3         = Color3.fromRGB(90, 90, 110)
dotsLabel.TextXAlignment     = Enum.TextXAlignment.Center
dotsLabel.TextTransparency   = 1
dotsLabel.ZIndex             = 52
dotsLabel.Parent             = introScreen

local skipBtn = Instance.new("TextButton")
skipBtn.Text               = "SKIP ▶"
skipBtn.Size               = UDim2.new(0, 90, 0, 28)
skipBtn.AnchorPoint        = Vector2.new(1, 1)
skipBtn.Position           = UDim2.new(1, -24, 1, -24)
skipBtn.BackgroundColor3   = Color3.fromRGB(30, 30, 40)
skipBtn.BackgroundTransparency = 0.3
skipBtn.TextColor3         = C_MUTED
skipBtn.Font               = Enum.Font.Gotham
skipBtn.TextSize           = 13
skipBtn.BorderSizePixel    = 0
skipBtn.ZIndex             = 53
skipBtn.Parent             = introScreen
Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 6)

local introLines = {
    { text = "잠드는 순간, 세상이 바뀌었다.",               size = 22, bold = false, color = Color3.fromRGB(200,200,215), hold = 2.2 },
    { text = "작고 둥근 몸. 낯선 발. 긴 수염.",             size = 22, bold = false, color = Color3.fromRGB(200,200,215), hold = 2.2 },
    { text = "온 가족이 카피바라가 되어 있었다.",             size = 22, bold = false, color = Color3.fromRGB(215,215,230), hold = 2.4 },
    { text = "하늘 끝까지 닿은 탑이 눈앞에 서 있었다.",       size = 22, bold = false, color = Color3.fromRGB(215,215,230), hold = 2.5 },
    { text = "아빠, 엄마, 아들, 딸 — 넷이서 손을 맞잡았다.", size = 21, bold = false, color = Color3.fromRGB(220,220,240), hold = 2.8 },
    { text = "우리는 정확히는 알 수 없었지만...",             size = 19, bold = false, color = Color3.fromRGB(160,160,180), hold = 2.5 },
    { text = "꼭대기까지 가야, 무언가 일어날 것 같았다.",        size = 26, bold = true,  color = Color3.fromRGB(255,228,100), hold = 3.2 },
}

-- ══════════════════════════════════════════════════════════════════════════
--  로비 패널
-- ══════════════════════════════════════════════════════════════════════════
local PANEL_W = 660
local PANEL_H = 510


local overlay = Instance.new("Frame")
overlay.Size                  = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3      = C_BG
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel       = 0
overlay.ZIndex                = 1
overlay.Parent                = screenGui

local bg = Instance.new("Frame")
bg.Name             = "LobbyBG"
bg.Size             = UDim2.new(0, PANEL_W, 0, PANEL_H)
bg.AnchorPoint      = Vector2.new(0.5, 0.5)
bg.Position         = UDim2.new(0.5, 0, 0.5, 0)
bg.BackgroundColor3 = C_PANEL
bg.BorderSizePixel  = 0
bg.ZIndex           = 2
bg.Visible          = false
bg.Parent           = screenGui
Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 16)
local bgStroke = Instance.new("UIStroke", bg)
bgStroke.Color     = C_BORDER
bgStroke.Thickness = 1.5

-- 헤더
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = bg
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)
-- 헤더 아래 모서리 직각
local hdrFix = Instance.new("Frame")
hdrFix.Size             = UDim2.new(1, 0, 0.5, 0)
hdrFix.Position         = UDim2.new(0, 0, 0.5, 0)
hdrFix.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
hdrFix.BorderSizePixel  = 0
hdrFix.ZIndex           = 3
hdrFix.Parent           = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Text               = "CAPYBARA ESCAPE"
titleLbl.Size               = UDim2.new(1, -24, 1, 0)
titleLbl.Position           = UDim2.new(0, 20, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 17
titleLbl.TextColor3         = C_TEXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

-- 섹션 레이블
local secLbl = Instance.new("TextLabel")
secLbl.Text               = "캐릭터를 선택하세요"
secLbl.Size               = UDim2.new(1, -32, 0, 22)
secLbl.Position           = UDim2.new(0, 16, 0, 60)
secLbl.BackgroundTransparency = 1
secLbl.Font               = Enum.Font.Gotham
secLbl.TextSize           = 12
secLbl.TextColor3         = C_MUTED
secLbl.TextXAlignment     = Enum.TextXAlignment.Left
secLbl.ZIndex             = 3
secLbl.Parent             = bg

-- ── 캐릭터 카드 (ViewportFrame 포함) ──────────────────────────────────────
local CARD_Y    = 88
local CARD_H    = 210
local CARD_VP_H = 130          -- ViewportFrame 높이
local GAP       = 10
local CARD_W    = math.floor((PANEL_W - 32 - GAP * 3) / 4)  -- 4장
local CARD_X0   = 16

-- 악세서리 이름 + HRP 기준 오프셋 (게임 내 실제 값과 동일)
-- viewport 전용 오프셋: bbTop(머리 상단) 기준
-- 캐릭터는 -Z 방향을 바라봄, 카메라는 -Z 쪽에서 +Z를 향해 봄
-- viewport 전용 ACC_INFO
-- 카메라가 -Z 방향(캐릭터 정면)에 있으므로
-- Z+는 캐릭터 등쪽, Z-는 카메라쪽
local ACC_INFO = {
    Dad      = { name = "DadHelmet",      offset = CFrame.new(0,  0.2,  0.0), hideHandle = false },
    Mom      = { name = "MomHat",         offset = CFrame.new(0,  0.6,  0.0), hideHandle = true  }, -- Handle이 커서 투명처리
    Son      = { name = "SonCap",         offset = CFrame.new(0,  0.5,  0.0) * CFrame.Angles(math.rad(90), 0, 0), hideHandle = false },
    Daughter = { name = "DaughterRibbon", offset = CFrame.new(0,  0.3,  0.0), hideHandle = false },
}

local function buildViewport(vp, charData, onDone)
    for _, c in ipairs(vp:GetChildren()) do
        if c:IsA("WorldModel") or c:IsA("Camera") then c:Destroy() end
    end
    vp.CurrentCamera = nil

    task.spawn(function()
        -- ── 소스 모델: ReplicatedStorage.CapybaraModel 우선 ─────────────────
        local src = ReplicatedStorage:FindFirstChild("CapybaraModel")
        if not src or not src:FindFirstChild("HumanoidRootPart") then
            return  -- CapybaraModel 없으면 포기
        end

        -- ── 클론 & 스크립트 제거 ─────────────────────────────────────────────
        local clone = src:Clone()
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Animator") then
                d:Destroy()
            end
        end
        for _, c in ipairs(clone:GetChildren()) do
            -- Accessory 인스턴스, CharAccessory 이름, 또는 Handle 파트를 포함한 Model (카탈로그 악세서리) 제거
            if c:IsA("Accessory") or c.Name == "CharAccessory" then
                c:Destroy()
            elseif (c:IsA("Model") or c:IsA("Part") or c:IsA("MeshPart")) and c:FindFirstChild("Handle") then
                c:Destroy()
            end
        end

        local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
        if not cloneHrp then return end

        -- ── 모든 파트를 원점 기준으로 이동 & 고정 ───────────────────────────
        local toOrigin = cloneHrp.CFrame:Inverse()
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CFrame     = toOrigin * d.CFrame
                d.Anchored   = true
                d.CanCollide = false
            end
        end
        cloneHrp.CFrame   = CFrame.new(0, 0, 0)
        cloneHrp.Anchored = true

        -- ── WorldModel에 삽입 ────────────────────────────────────────────────
        local wm = Instance.new("WorldModel")
        clone.Parent = wm
        wm.Parent    = vp

        -- ── 캐릭터만으로 BoundingBox 계산 (악세서리 제외) ───────────────────
        local bbCF, bbSize = clone:GetBoundingBox()
        -- 실제 기하 중심 (발~머리 정중앙)
        local charCenter = bbCF.Position

        -- ── 악세서리 배치: Humanoid:AddAccessory() 사용 ─────────────────────
        -- 게임 실제 착용과 동일한 위치 (Attachment 자동 매칭)
        local accInfo   = ACC_INFO[charData.type]
        local accFolder = ReplicatedStorage:FindFirstChild("Accessories")
        if accInfo and accFolder then
            local template = accFolder:FindFirstChild(accInfo.name)
            local humanoid = clone:FindFirstChildWhichIsA("Humanoid")
            if template and humanoid then
                local acc = template:Clone()
                -- AddAccessory가 Attachment를 찾아 정확한 위치에 부착
                humanoid:AddAccessory(acc)
                -- 뷰포트는 물리 불필요 → 앵커 처리
                local handle = acc:FindFirstChild("Handle")
                if handle then
                    handle.Anchored   = true
                    handle.CanCollide = false
                end
                for _, d in ipairs(acc:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.Anchored = true; d.CanCollide = false
                    end
                end
            end
        end

        -- ── 카메라: 악세사리 포함 전체 바운딩박스 기준 ──────────────────────
        -- 악세사리를 배치한 뒤 WorldModel 전체 크기로 카메라 거리 결정
        local fullBBCF, fullBBSize = wm:GetBoundingBox()
        local fullCenterY = fullBBCF.Position.Y
        local fullH = math.max(fullBBSize.X, fullBBSize.Y, fullBBSize.Z)
        -- 카메라를 중심보다 약간 낮게, lookAt은 약간 위로 → 모자 잘림 방지
        local lookAt = Vector3.new(0, fullCenterY + fullBBSize.Y * 0.1, 0)
        local camPos = Vector3.new(0, fullCenterY - fullBBSize.Y * 0.05, -fullH * 3.5)

        local cam = Instance.new("Camera")
        cam.FieldOfView = 30
        cam.CFrame      = CFrame.new(camPos, lookAt)
        cam.Parent       = vp
        vp.CurrentCamera = cam

        if onDone then onDone(clone, cam, lookAt, bbSize) end
    end)
end

local charButtons = {}
local descFrame   -- 아래 설명 패널 (나중에 생성)
local descImg     -- 설명 패널 이미지 (나중에 생성)

local function selectChar(idx)
    local opt = CHAR_OPTIONS[idx]
    selectedCharType = opt.type
    Events.CharacterSelected:FireServer(selectedCharType)

    -- 카드 하이라이트
    for i, b in ipairs(charButtons) do
        local on = (i == idx)
        TweenService:Create(b.card, TweenInfo.new(0.18),
            { BackgroundColor3 = on and C_CARD_ON or C_CARD }):Play()
        b.stroke.Color     = on and opt.color or C_BORDER
        b.stroke.Thickness = on and 2.5 or 1.5
        b.nameLbl.TextColor3 = on and opt.color or C_TEXT
        b.vpFrame.BackgroundColor3 = on
            and Color3.new(opt.color.R*0.18, opt.color.G*0.18, opt.color.B*0.18)
            or  Color3.fromRGB(20, 20, 26)
    end

    -- 설명 패널 갱신
    if descFrame then
        local nameD = descFrame:FindFirstChild("DescName")
        local tagD  = descFrame:FindFirstChild("DescTag")
        local abilD = descFrame:FindFirstChild("DescAbil")
        local descD = descFrame:FindFirstChild("DescText")
        if nameD then nameD.Text = opt.name; nameD.TextColor3 = opt.color end
        if tagD  then tagD.Text  = opt.tagline end
        if abilD then abilD.Text = "✦ " .. opt.ability end
        if descD then descD.Text = opt.desc end
    end

    -- 설명 패널 이미지 갱신
    if descImg then descImg.Image = opt.image end
end

-- 카드 생성
for i, opt in ipairs(CHAR_OPTIONS) do
    local cx = CARD_X0 + (i - 1) * (CARD_W + GAP)

    local card = Instance.new("Frame")
    card.Size             = UDim2.new(0, CARD_W, 0, CARD_H)
    card.Position         = UDim2.new(0, cx, 0, CARD_Y)
    card.BackgroundColor3 = C_CARD
    card.BorderSizePixel  = 0
    card.ZIndex           = 3
    card.Parent           = bg
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color     = C_BORDER
    stroke.Thickness = 1.5

    -- ImageLabel (캐릭터 이미지)
    local vp = Instance.new("ImageLabel")
    vp.Size                  = UDim2.new(1, 0, 0, CARD_VP_H)
    vp.Position              = UDim2.new(0, 0, 0, 0)
    vp.BackgroundColor3      = Color3.fromRGB(20, 20, 26)
    vp.BackgroundTransparency = 0
    vp.BorderSizePixel       = 0
    vp.Image                 = opt.image
    vp.ScaleType             = Enum.ScaleType.Fit
    vp.ZIndex                = 4
    vp.Parent                = card
    Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 12)

    -- 이름
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Text               = opt.name
    nameLbl.Size               = UDim2.new(1, -8, 0, 28)
    nameLbl.Position           = UDim2.new(0, 4, 0, CARD_VP_H + 6)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.TextSize           = 18
    nameLbl.TextColor3         = C_TEXT
    nameLbl.TextXAlignment     = Enum.TextXAlignment.Center
    nameLbl.ZIndex             = 4
    nameLbl.Parent             = card

    -- 특기 태그
    local abilLbl = Instance.new("TextLabel")
    abilLbl.Text               = opt.ability
    abilLbl.Size               = UDim2.new(1, -8, 0, 22)
    abilLbl.Position           = UDim2.new(0, 4, 0, CARD_VP_H + 36)
    abilLbl.BackgroundTransparency = 1
    abilLbl.Font               = Enum.Font.Gotham
    abilLbl.TextSize           = 11
    abilLbl.TextColor3         = C_MUTED
    abilLbl.TextXAlignment     = Enum.TextXAlignment.Center
    abilLbl.ZIndex             = 4
    abilLbl.Parent             = card

    -- 선택 버튼 (투명 클릭 영역)
    local btn = Instance.new("TextButton")
    btn.Size                  = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text                  = ""
    btn.ZIndex                = 5
    btn.Parent                = card
    btn.MouseButton1Click:Connect(function()
        if isReady then return end
        selectChar(i)
    end)

    charButtons[i] = {
        card = card, stroke = stroke,
        nameLbl = nameLbl, vpFrame = vp,
    }
end

-- ── 설명 패널 ─────────────────────────────────────────────────────────────
local DESC_Y = CARD_Y + CARD_H + 12
local DESC_H = 118

descFrame = Instance.new("Frame")
descFrame.Name             = "DescPanel"
descFrame.Size             = UDim2.new(1, -32, 0, DESC_H)
descFrame.Position         = UDim2.new(0, 16, 0, DESC_Y)
descFrame.BackgroundColor3 = C_CARD
descFrame.BorderSizePixel  = 0
descFrame.ZIndex           = 3
descFrame.Parent           = bg
Instance.new("UICorner", descFrame).CornerRadius = UDim.new(0, 12)
local dStroke = Instance.new("UIStroke", descFrame)
dStroke.Color     = C_BORDER
dStroke.Thickness = 1.5

-- 왼쪽: 캐릭터 이미지
local VP_W = 110
descImg = Instance.new("ImageLabel")
descImg.Size                  = UDim2.new(0, VP_W, 1, -16)
descImg.Position              = UDim2.new(0, 8, 0, 8)
descImg.BackgroundColor3      = Color3.fromRGB(18, 18, 24)
descImg.BackgroundTransparency = 0
descImg.BorderSizePixel       = 0
descImg.Image                 = CHAR_OPTIONS[1].image
descImg.ScaleType             = Enum.ScaleType.Fit
descImg.ZIndex                = 4
descImg.Parent                = descFrame
Instance.new("UICorner", descImg).CornerRadius = UDim.new(0, 8)

-- 오른쪽: 이름 / 태그 / 능력 / 설명
local TEXT_X = VP_W + 16

local dName = Instance.new("TextLabel")
dName.Name               = "DescName"
dName.Size               = UDim2.new(1, -(TEXT_X + 8), 0, 28)
dName.Position           = UDim2.new(0, TEXT_X, 0, 10)
dName.BackgroundTransparency = 1
dName.Font               = Enum.Font.GothamBold
dName.TextSize           = 20
dName.TextColor3         = C_ACCENT
dName.TextXAlignment     = Enum.TextXAlignment.Left
dName.ZIndex             = 4
dName.Parent             = descFrame

local dTag = Instance.new("TextLabel")
dTag.Name               = "DescTag"
dTag.Size               = UDim2.new(1, -(TEXT_X + 8), 0, 18)
dTag.Position           = UDim2.new(0, TEXT_X, 0, 36)
dTag.BackgroundTransparency = 1
dTag.Font               = Enum.Font.Gotham
dTag.TextSize           = 12
dTag.TextColor3         = C_MUTED
dTag.TextXAlignment     = Enum.TextXAlignment.Left
dTag.ZIndex             = 4
dTag.Parent             = descFrame

local dAbil = Instance.new("TextLabel")
dAbil.Name               = "DescAbil"
dAbil.Size               = UDim2.new(1, -(TEXT_X + 8), 0, 20)
dAbil.Position           = UDim2.new(0, TEXT_X, 0, 54)
dAbil.BackgroundTransparency = 1
dAbil.Font               = Enum.Font.GothamBold
dAbil.TextSize           = 12
dAbil.TextColor3         = Color3.fromRGB(255, 220, 80)
dAbil.TextXAlignment     = Enum.TextXAlignment.Left
dAbil.ZIndex             = 4
dAbil.Parent             = descFrame

local dText = Instance.new("TextLabel")
dText.Name               = "DescText"
dText.Size               = UDim2.new(1, -(TEXT_X + 8), 0, 46)
dText.Position           = UDim2.new(0, TEXT_X, 0, 74)
dText.BackgroundTransparency = 1
dText.Font               = Enum.Font.Gotham
dText.TextSize           = 11
dText.TextColor3         = Color3.fromRGB(160, 160, 180)
dText.TextXAlignment     = Enum.TextXAlignment.Left
dText.TextYAlignment     = Enum.TextYAlignment.Top
dText.TextWrapped        = true
dText.ZIndex             = 4
dText.Parent             = descFrame

-- ── 준비 완료 버튼 ───────────────────────────────────────────────────────────
local READY_Y = DESC_Y + DESC_H + 14

local confirmBtn = Instance.new("TextButton")
confirmBtn.Name             = "ConfirmButton"
confirmBtn.Text             = "준비 완료"
confirmBtn.Size             = UDim2.new(1, -32, 0, 46)
confirmBtn.Position         = UDim2.new(0, 16, 0, READY_Y)
confirmBtn.BackgroundColor3 = C_ACCENT
confirmBtn.TextColor3       = Color3.fromRGB(10, 10, 20)
confirmBtn.Font             = Enum.Font.GothamBold
confirmBtn.TextSize         = 16
confirmBtn.BorderSizePixel  = 0
confirmBtn.ZIndex           = 3
confirmBtn.Parent           = bg
Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 10)

local waitText = Instance.new("TextLabel")
waitText.Name               = "WaitText"
waitText.Text               = ""
waitText.Size               = UDim2.new(1, -32, 0, 18)
waitText.Position           = UDim2.new(0, 16, 0, READY_Y + 50)
waitText.BackgroundTransparency = 1
waitText.Font               = Enum.Font.Gotham
waitText.TextSize           = 12
waitText.TextColor3         = C_MUTED
waitText.ZIndex             = 3
waitText.Parent             = bg

-- 기본 선택: 엄마 (index 2)
selectChar(2)

-- ══════════════════════════════════════════════════════════════════════════
--  인트로 시퀀스 실행
-- ══════════════════════════════════════════════════════════════════════════
local introFinished = false
local introSkipped  = false

-- 패널 스케일은 previewScreen 선언 이후에 적용 (전방 선언)
local applyPanelScale

local function showLobby()
    if introFinished then return end
    introFinished = true
    if applyPanelScale then applyPanelScale() end
    introScreen.Visible = false
    bg.Visible = true
    TweenService:Create(bg, TweenInfo.new(0.5, Enum.EasingStyle.Quad),
        { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
end

skipBtn.MouseButton1Click:Connect(function()
    if introFinished then return end
    introSkipped = true
    showLobby()
end)

task.spawn(function()
    task.wait(0.4)
    if introSkipped then return end
    TweenService:Create(dotsLabel, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()

    local function setDots(cur, tot)
        local s = ""
        for i = 1, tot do
            s = s .. (i == cur and "●" or "○")
            if i < tot then s = s .. "  " end
        end
        dotsLabel.Text = s
    end

    local total = #introLines
    for i, line in ipairs(introLines) do
        if introSkipped then return end
        setDots(i, total)
        mainLabel.Text         = line.text
        mainLabel.TextSize     = line.size
        mainLabel.Font         = line.bold and Enum.Font.GothamBold or Enum.Font.Gotham
        mainLabel.TextColor3   = line.color
        mainLabel.TextTransparency = 1
        TweenService:Create(mainLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad),
            { TextTransparency = 0 }):Play()
        task.wait(0.8 + line.hold)
        if introSkipped then return end
        if i < total then
            TweenService:Create(mainLabel, TweenInfo.new(0.5),
                { TextTransparency = 1 }):Play()
            task.wait(0.6)
        end
    end
    if introSkipped then return end
    task.wait(0.9)
    TweenService:Create(mainLabel,   TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
    TweenService:Create(dotsLabel,   TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
    TweenService:Create(introScreen, TweenInfo.new(1.2, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 1 }):Play()
    skipBtn.Visible = false
    task.wait(1.3)
    showLobby()
end)

-- ══════════════════════════════════════════════════════════════════════════
--  캐릭터 프리뷰 화면 (준비 완료 후)
-- ══════════════════════════════════════════════════════════════════════════
local previewScreen = Instance.new("Frame")
previewScreen.Name             = "PreviewScreen"
previewScreen.Size             = UDim2.new(0, PANEL_W, 0, PANEL_H)
previewScreen.AnchorPoint      = Vector2.new(0.5, 0.5)
previewScreen.Position         = UDim2.new(0.5, 0, 0.5, 0)
previewScreen.BackgroundColor3 = C_PANEL
previewScreen.BorderSizePixel  = 0
previewScreen.ZIndex           = 3
previewScreen.Visible          = false
previewScreen.Parent           = screenGui
Instance.new("UICorner", previewScreen).CornerRadius = UDim.new(0, 16)
local psStroke = Instance.new("UIStroke", previewScreen)
psStroke.Color     = C_BORDER
psStroke.Thickness = 1.5

-- ── 패널 스케일 함수 (previewScreen 선언 후 정의) ─────────────────────────
applyPanelScale = function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vs = cam.ViewportSize
    if vs.X <= 0 or vs.Y <= 0 then return end
    local s = math.min(1, math.min(vs.X * 0.95 / PANEL_W, vs.Y * 0.95 / PANEL_H))
    local bsc = bg:FindFirstChildWhichIsA("UIScale")
    if not bsc then bsc = Instance.new("UIScale", bg) end
    bsc.Scale = s
    local psc = previewScreen:FindFirstChildWhichIsA("UIScale")
    if not psc then psc = Instance.new("UIScale", previewScreen) end
    psc.Scale = s
end

-- 헤더
local psHeader = Instance.new("Frame")
psHeader.Size             = UDim2.new(1, 0, 0, 52)
psHeader.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
psHeader.BorderSizePixel  = 0
psHeader.ZIndex           = 4
psHeader.Parent           = previewScreen
Instance.new("UICorner", psHeader).CornerRadius = UDim.new(0, 16)
local psHdrFix = Instance.new("Frame")
psHdrFix.Size             = UDim2.new(1, 0, 0.5, 0)
psHdrFix.Position         = UDim2.new(0, 0, 0.5, 0)
psHdrFix.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
psHdrFix.BorderSizePixel  = 0
psHdrFix.ZIndex           = 4
psHdrFix.Parent           = psHeader
local psTitle = Instance.new("TextLabel")
psTitle.Text               = "CAPYBARA ESCAPE"
psTitle.Size               = UDim2.new(1, -24, 1, 0)
psTitle.Position           = UDim2.new(0, 20, 0, 0)
psTitle.BackgroundTransparency = 1
psTitle.Font               = Enum.Font.GothamBold
psTitle.TextSize           = 17
psTitle.TextColor3         = C_TEXT
psTitle.TextXAlignment     = Enum.TextXAlignment.Left
psTitle.ZIndex             = 5
psTitle.Parent             = psHeader

-- 큰 ViewportFrame (캐릭터 표시)
local VP_H = PANEL_H - 52 - 110  -- 헤더, 하단 정보 영역 제외
local previewVP = Instance.new("ViewportFrame")
previewVP.Size                  = UDim2.new(1, -32, 0, VP_H)
previewVP.Position              = UDim2.new(0, 16, 0, 60)
previewVP.BackgroundColor3      = Color3.fromRGB(16, 16, 22)
previewVP.BackgroundTransparency = 0
previewVP.BorderSizePixel       = 0
previewVP.LightDirection        = Vector3.new(-1, -2, -1)
previewVP.Ambient               = Color3.fromRGB(200, 200, 220)
previewVP.ZIndex                = 4
previewVP.Parent                = previewScreen
Instance.new("UICorner", previewVP).CornerRadius = UDim.new(0, 12)

-- 하단 정보 영역
local INFO_Y = 60 + VP_H + 12
local psCharName = Instance.new("TextLabel")
psCharName.Size               = UDim2.new(1, -32, 0, 34)
psCharName.Position           = UDim2.new(0, 16, 0, INFO_Y)
psCharName.BackgroundTransparency = 1
psCharName.Font               = Enum.Font.GothamBold
psCharName.TextSize           = 26
psCharName.TextColor3         = C_TEXT
psCharName.TextXAlignment     = Enum.TextXAlignment.Center
psCharName.ZIndex             = 4
psCharName.Parent             = previewScreen

local psTagline = Instance.new("TextLabel")
psTagline.Size               = UDim2.new(1, -32, 0, 20)
psTagline.Position           = UDim2.new(0, 16, 0, INFO_Y + 34)
psTagline.BackgroundTransparency = 1
psTagline.Font               = Enum.Font.Gotham
psTagline.TextSize           = 13
psTagline.TextColor3         = C_MUTED
psTagline.TextXAlignment     = Enum.TextXAlignment.Center
psTagline.ZIndex             = 4
psTagline.Parent             = previewScreen

local psWaiting = Instance.new("TextLabel")
psWaiting.Size               = UDim2.new(1, -32, 0, 30)
psWaiting.Position           = UDim2.new(0, 16, 0, INFO_Y + 60)
psWaiting.BackgroundTransparency = 1
psWaiting.Font               = Enum.Font.Gotham
psWaiting.TextSize           = 13
psWaiting.TextColor3         = Color3.fromRGB(100, 180, 255)
psWaiting.TextXAlignment     = Enum.TextXAlignment.Center
psWaiting.ZIndex             = 4
psWaiting.Parent             = previewScreen

-- 캐릭터 프리뷰 화면 열기
local rotateThread = nil

local function openPreview(charType)
    -- 선택한 캐릭터 정보 찾기
    local opt
    for _, c in ipairs(CHAR_OPTIONS) do
        if c.type == charType then opt = c; break end
    end
    if not opt then return end

    psCharName.Text          = opt.name
    psCharName.TextColor3    = opt.color
    psTagline.Text           = opt.tagline
    psWaiting.Text           = "⏳  다른 플레이어를 기다리는 중..."

    -- 캐릭터 뷰포트 빌드 (비동기) — onDone에서 카메라 회전 시작
    buildViewport(previewVP, opt, function(clone, cam, center, bbSize)
        local dist  = math.max(bbSize.X, bbSize.Y, bbSize.Z) * 2.2
        local angle = 180  -- 180° = 정면(-Z)에서 시작

        if rotateThread then task.cancel(rotateThread) end
        rotateThread = task.spawn(function()
            while previewScreen.Visible do
                angle = (angle + 0.4) % 360
                local rad = math.rad(angle)
                cam.CFrame = CFrame.new(
                    center + Vector3.new(math.sin(rad) * dist, 1.2, math.cos(rad) * dist),
                    center
                )
                task.wait(1/30)
            end
        end)
    end)

    -- 화면 전환 (빌드 완료를 기다리지 않고 즉시 전환)
    TweenService:Create(bg, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 1 }):Play()
    task.wait(0.25)
    bg.Visible                           = false
    bg.BackgroundTransparency            = 0
    previewScreen.BackgroundTransparency = 1
    previewScreen.Visible                = true
    TweenService:Create(previewScreen, TweenInfo.new(0.35, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 0 }):Play()
end

-- ══════════════════════════════════════════════════════════════════════════
--  이벤트
-- ══════════════════════════════════════════════════════════════════════════
confirmBtn.MouseButton1Click:Connect(function()
    if isReady then return end
    isReady = true
    Events.ReadyUp:FireServer()
    openPreview(selectedCharType)
end)

Events.UpdateHUD.OnClientEvent:Connect(function(data)
    if data.type == "lobbyCountdown" then
        psWaiting.Text      = "🎮  " .. data.count .. "초 후 게임 시작!"
        psWaiting.TextColor3 = Color3.fromRGB(255, 210, 50)
    end
end)

Events.StageStarted.OnClientEvent:Connect(function()
    if rotateThread then task.cancel(rotateThread) end
    screenGui.Enabled = false
    task.delay(1, function() screenGui:Destroy() end)
end)

