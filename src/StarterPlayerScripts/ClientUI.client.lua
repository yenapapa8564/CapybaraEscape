-- StarterPlayerScripts/ClientUI
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

-- ScreenGui 생성
local screenGui = Instance.new("ScreenGui")
screenGui.ResetOnSpawn = false
screenGui.Name = "GameHUD"
screenGui.Parent = player.PlayerGui

-- 사운드 플레이 헬퍼
local function playSound(soundId, volume, pitch)
    local snd = Instance.new("Sound")
    snd.SoundId = "rbxassetid://" .. soundId
    snd.Volume = volume or 0.6
    snd.PlaybackSpeed = pitch or 1
    snd.RollOffMaxDistance = 0
    snd.Parent = workspace
    snd:Play()
    game:GetService("Debris"):AddItem(snd, 6)
end
-- 사운드 ID 목록
local SFX = {
    carrotPickup  = 9125402735,  -- 당근 획득
    trapPickup    = 147722227,   -- 함정 획득
    escape        = 1435170862,  -- 탈출 성공
    caught        = 147722137,   -- 잡힘
    hunterSpawn   = 3264899297,  -- 추가 헌터 등장
    countdown     = 5100567489,  -- 카운트다운 틱
    trapTrigger   = 131070972,   -- 함정 발동
    buttonClick   = 147722227,   -- 버튼 클릭
}

-- 색상 상수
local pastelBg = Color3.fromRGB(255, 245, 230)     -- 크림색 배경
local textColorNormal = Color3.fromRGB(80, 60, 60)  -- 기본 텍스트
local carrotFlashColor = Color3.fromRGB(255, 179, 102) -- 당근 획득 플래시

-- 타이머 상태
local stageStartedAt = 0
local timerRunning   = false

-- ── 위험 감지 테두리 ─────────────────────────────────────────────────────
local dangerBorder = Instance.new("Frame")
dangerBorder.Name = "DangerBorder"
dangerBorder.Size = UDim2.new(1, 0, 1, 0)
dangerBorder.BackgroundTransparency = 1
dangerBorder.ZIndex = 8
dangerBorder.Parent = screenGui

local dangerStroke = Instance.new("UIStroke")
dangerStroke.Color = Color3.fromRGB(220, 30, 30)
dangerStroke.Thickness = 0
dangerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
dangerStroke.Parent = dangerBorder

local dangerLabel = Instance.new("TextLabel")
dangerLabel.Text = "⚠️  사냥꾼 접근 중!"
dangerLabel.Font = Enum.Font.GothamBold
dangerLabel.TextSize = 20
dangerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
dangerLabel.BackgroundTransparency = 1
dangerLabel.Size = UDim2.new(0.3, 0, 0, 30)
dangerLabel.AnchorPoint = Vector2.new(0.5, 0)
dangerLabel.Position = UDim2.new(0.5, 0, 0.04, 0)
dangerLabel.ZIndex = 9
dangerLabel.Visible = false
dangerLabel.Parent = screenGui

local dangerPulseThread = nil
local currentDangerLevel = "safe"

local function stopDangerPulse()
    if dangerPulseThread then
        pcall(task.cancel, dangerPulseThread)
        dangerPulseThread = nil
    end
    dangerStroke.Thickness = 0
    dangerLabel.Visible = false
end

local function startDangerPulse(level)
    stopDangerPulse()
    if level == "safe" then return end

    local isDanger = (level == "danger")
    dangerStroke.Color = isDanger
        and Color3.fromRGB(220, 30, 30)
        or  Color3.fromRGB(230, 160, 30)
    dangerLabel.TextColor3 = isDanger
        and Color3.fromRGB(255, 80, 80)
        or  Color3.fromRGB(255, 200, 50)
    dangerLabel.Text = isDanger and "⚠️  사냥꾼 바로 뒤에 있다!" or "⚠️  사냥꾼 접근 중!"
    dangerLabel.Visible = true

    dangerPulseThread = task.spawn(function()
        local maxThick = isDanger and 18 or 8
        local speed    = isDanger and 0.35 or 0.55
        while true do
            TweenService:Create(dangerStroke,
                TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Thickness = maxThick }
            ):Play()
            task.wait(speed)
            TweenService:Create(dangerStroke,
                TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Thickness = 0 }
            ):Play()
            task.wait(speed)
        end
    end)
end

-- HUD 레이블 생성 헬퍼
local function makeLabel(name, text, anchorPoint, position, size)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Frame"
    frame.BackgroundColor3 = pastelBg
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.AnchorPoint = anchorPoint
    frame.Position = position
    frame.Size = size
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = name
    label.Text = text
    label.TextColor3 = textColorNormal
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = frame
    return label
end

-- 상단 HUD 3개 레이블
local stageLabel = makeLabel(
    "StageLabel", "1층",
    Vector2.new(0, 0),
    UDim2.new(0, 10, 0, 10),
    UDim2.new(0, 150, 0, 40)
)

local timerLabel = makeLabel(
    "TimerLabel", "00:00",
    Vector2.new(0.5, 0),
    UDim2.new(0.5, 0, 0, 10),
    UDim2.new(0, 120, 0, 40)
)

local survivorsLabel = makeLabel(
    "SurvivorsLabel", "생존자 0명",
    Vector2.new(1, 0),
    UDim2.new(1, -10, 0, 10),
    UDim2.new(0, 150, 0, 40)
)

-- 당근 버튼 공통 생성 헬퍼
local function makeCarrotButton(text, bgColor, yOffset)
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = bgColor
    btn.TextColor3 = Color3.fromRGB(50, 30, 10)
    btn.AnchorPoint = Vector2.new(1, 1)
    btn.Position = UDim2.new(1, -10, 1, yOffset)
    btn.Size = UDim2.new(0, 200, 0, 50)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.Text = text
    btn.Visible = false
    btn.Parent = screenGui
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 22)
    c.Parent = btn
    return btn
end

-- 💩 버튼 (G키) — 함정 버튼 위에 배치
local poopButton  = makeCarrotButton("💩 똥 싸기 [G]",  Color3.fromRGB(200, 160, 80),  -190)
-- ⚡ 버튼 (H키)
local speedButton = makeCarrotButton("⚡ 속도 증가 [H]", Color3.fromRGB(255, 220, 80), -130)

local function hideCarrotButtons()
    poopButton.Visible  = false
    speedButton.Visible = false
end

local function useCarrot(choice)
    if not poopButton.Visible then return end  -- 이미 사용됨
    hideCarrotButtons()
    Events.CarrotChoice:FireServer(choice)
end

poopButton.MouseButton1Click:Connect(function()  useCarrot("poop")  end)
speedButton.MouseButton1Click:Connect(function() useCarrot("speed") end)

-- 함정 버튼 (우하단, 기본 숨김)
local trapButton = Instance.new("TextButton")
trapButton.Name = "TrapButton"
trapButton.Text = "🪤 함정 [F]"
trapButton.BackgroundColor3 = Color3.fromRGB(255, 204, 213)  -- 연분홍
trapButton.TextColor3 = textColorNormal
trapButton.AnchorPoint = Vector2.new(1, 1)
trapButton.Position = UDim2.new(1, -10, 1, -10)
trapButton.Size = UDim2.new(0, 150, 0, 50)
trapButton.Font = Enum.Font.GothamBold
trapButton.TextSize = 16
trapButton.Visible = false
trapButton.Parent = screenGui

local trapCorner = Instance.new("UICorner")
trapCorner.CornerRadius = UDim.new(0, 22)
trapCorner.Parent = trapButton

-- 연막탄 버튼 (우하단, 기본 숨김)
local smokeButton = Instance.new("TextButton")
smokeButton.Name = "SmokeButton"
smokeButton.Text = "💨 연막탄 [Z]"
smokeButton.BackgroundColor3 = Color3.fromRGB(180, 180, 220)
smokeButton.TextColor3 = textColorNormal
smokeButton.AnchorPoint = Vector2.new(1, 1)
smokeButton.Position = UDim2.new(1, -10, 1, -70)
smokeButton.Size = UDim2.new(0, 200, 0, 50)
smokeButton.Font = Enum.Font.GothamBold
smokeButton.TextSize = 15
smokeButton.Visible = false
smokeButton.Parent = screenGui
local smokeCorner = Instance.new("UICorner")
smokeCorner.CornerRadius = UDim.new(0, 22)
smokeCorner.Parent = smokeButton

-- 스프레이 캔 버튼 (우하단, 기본 숨김)
local sprayButton = Instance.new("TextButton")
sprayButton.Name = "SprayButton"
sprayButton.Text = "🎨 낙서 [X]"
sprayButton.BackgroundColor3 = Color3.fromRGB(180, 220, 255)
sprayButton.TextColor3 = textColorNormal
sprayButton.AnchorPoint = Vector2.new(1, 1)
sprayButton.Position = UDim2.new(1, -10, 1, -130)
sprayButton.Size = UDim2.new(0, 200, 0, 50)
sprayButton.Font = Enum.Font.GothamBold
sprayButton.TextSize = 15
sprayButton.Visible = false
sprayButton.Parent = screenGui
local sprayCorner = Instance.new("UICorner")
sprayCorner.CornerRadius = UDim.new(0, 22)
sprayCorner.Parent = sprayButton

local sprayNearWall = false  -- 벽 근처 여부

-- ── 낙서 캔버스 오버레이 ─────────────────────────────────────────────────
local canvasOverlay = Instance.new("Frame")
canvasOverlay.Name = "GraffitiCanvas"
canvasOverlay.Size = UDim2.new(1, 0, 1, 0)
canvasOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
canvasOverlay.BackgroundTransparency = 0.45
canvasOverlay.Visible = false
canvasOverlay.ZIndex = 30
canvasOverlay.Parent = screenGui

-- 상단 툴바
local canvasToolbar = Instance.new("Frame")
canvasToolbar.Size = UDim2.new(1, 0, 0, 44)
canvasToolbar.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
canvasToolbar.BackgroundTransparency = 0.1
canvasToolbar.BorderSizePixel = 0
canvasToolbar.ZIndex = 31
canvasToolbar.Parent = canvasOverlay

local canvasTitle = Instance.new("TextLabel")
canvasTitle.Text = "🎨 낙서하기  —  가장 가까운 벽에 그려집니다"
canvasTitle.Font = Enum.Font.GothamBold
canvasTitle.TextSize = 16
canvasTitle.TextColor3 = Color3.fromRGB(220, 220, 255)
canvasTitle.BackgroundTransparency = 1
canvasTitle.Size = UDim2.new(0.6, 0, 1, 0)
canvasTitle.Position = UDim2.new(0, 12, 0, 0)
canvasTitle.TextXAlignment = Enum.TextXAlignment.Left
canvasTitle.ZIndex = 32
canvasTitle.Parent = canvasToolbar

-- 브러시 굵기 버튼 (툴바 오른쪽)
local thicknessValues = {1, 2, 3}
local thicknessDots = {}
local currentThickness = 2
for i, tv in ipairs(thicknessValues) do
    local dot = Instance.new("TextButton")
    dot.Size = UDim2.new(0, 28, 0, 28)
    dot.Position = UDim2.new(1, -160 + (i-1)*36, 0.5, -14)
    dot.AnchorPoint = Vector2.new(0, 0)
    dot.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    dot.Text = ""
    dot.ZIndex = 32
    dot.Parent = canvasToolbar
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)
    local inner = Instance.new("Frame")
    local sz = 4 + tv * 4
    inner.Size = UDim2.new(0, sz, 0, sz)
    inner.AnchorPoint = Vector2.new(0.5, 0.5)
    inner.Position = UDim2.new(0.5, 0, 0.5, 0)
    inner.BackgroundColor3 = Color3.fromRGB(220, 220, 255)
    inner.BorderSizePixel = 0
    inner.ZIndex = 33
    inner.Parent = dot
    Instance.new("UICorner", inner).CornerRadius = UDim.new(0.5, 0)
    thicknessDots[i] = dot
    dot.MouseButton1Click:Connect(function()
        currentThickness = tv
        for j, d in ipairs(thicknessDots) do
            d.BackgroundColor3 = (j == i)
                and Color3.fromRGB(80, 120, 200)
                or  Color3.fromRGB(60, 60, 80)
        end
    end)
end

-- 캔버스 드로잉 영역
local canvasArea = Instance.new("Frame")
canvasArea.Name = "DrawArea"
canvasArea.Size = UDim2.new(1, 0, 1, -44-80)
canvasArea.Position = UDim2.new(0, 0, 0, 44)
canvasArea.BackgroundTransparency = 1
canvasArea.BackgroundColor3 = Color3.fromRGB(30, 30, 50)  -- 배경색 (투명도 낮추면 보임)
canvasArea.ClipsDescendants = true
canvasArea.Active = true  -- 필수: 이게 없으면 InputBegan/Changed/Ended 안 발생
canvasArea.ZIndex = 31
canvasArea.Parent = canvasOverlay

-- 하단 팔레트 바
local canvasPalette = Instance.new("Frame")
canvasPalette.Size = UDim2.new(1, 0, 0, 80)
canvasPalette.Position = UDim2.new(0, 0, 1, -80)
canvasPalette.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
canvasPalette.BackgroundTransparency = 0.1
canvasPalette.BorderSizePixel = 0
canvasPalette.ZIndex = 31
canvasPalette.Parent = canvasOverlay

-- 색상 팔레트 버튼 (크레파스 크기)
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local paletteColors = Constants.GRAFFITI_PALETTE
local currentColor = paletteColors[1]
local colorDots = {}
for i, col in ipairs(paletteColors) do
    local dot = Instance.new("TextButton")
    dot.Size = UDim2.new(0, 52, 0, 52)
    dot.Position = UDim2.new(0, 10 + (i-1)*58, 0.5, -26)
    dot.BackgroundColor3 = col
    dot.BorderSizePixel = 0
    dot.Text = ""
    dot.ZIndex = 32
    dot.Parent = canvasPalette
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)
    local sel = Instance.new("UIStroke")
    sel.Color = Color3.fromRGB(255, 255, 255)
    sel.Thickness = (i == 1) and 4 or 0
    sel.Parent = dot
    colorDots[i] = {btn=dot, stroke=sel}
    dot.MouseButton1Click:Connect(function()
        currentColor = col
        for j, cd in ipairs(colorDots) do
            cd.stroke.Thickness = (j == i) and 4 or 0
        end
    end)
end

-- 실행취소 / 취소 / 완료 버튼
local undoBtn = Instance.new("TextButton")
undoBtn.Size = UDim2.new(0, 80, 0, 34)
undoBtn.AnchorPoint = Vector2.new(1, 0.5)
undoBtn.Position = UDim2.new(1, -210, 0.5, 0)
undoBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
undoBtn.Text = "↩ 실행취소"
undoBtn.Font = Enum.Font.GothamBold
undoBtn.TextSize = 13
undoBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
undoBtn.ZIndex = 32
undoBtn.Parent = canvasPalette
Instance.new("UICorner", undoBtn).CornerRadius = UDim.new(0, 8)

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(0, 70, 0, 34)
cancelBtn.AnchorPoint = Vector2.new(1, 0.5)
cancelBtn.Position = UDim2.new(1, -120, 0.5, 0)
cancelBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
cancelBtn.Text = "✕ 취소"
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.TextSize = 14
cancelBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
cancelBtn.ZIndex = 32
cancelBtn.Parent = canvasPalette
Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 8)

local submitBtn = Instance.new("TextButton")
submitBtn.Size = UDim2.new(0, 80, 0, 34)
submitBtn.AnchorPoint = Vector2.new(1, 0.5)
submitBtn.Position = UDim2.new(1, -30, 0.5, 0)
submitBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
submitBtn.Text = "✓ 완료"
submitBtn.Font = Enum.Font.GothamBold
submitBtn.TextSize = 14
submitBtn.TextColor3 = Color3.fromRGB(200, 255, 220)
submitBtn.ZIndex = 32
submitBtn.Parent = canvasPalette
Instance.new("UICorner", submitBtn).CornerRadius = UDim.new(0, 8)

-- ── 낙서 드로잉 로직 ───────────────────────────────────────────────────────
local strokes = {}
local currentStroke = nil
local canvasSnapOriginPos  = nil
local canvasSnapLookVector = nil
local canvasTimeoutThread  = nil
local isDrawing = false

-- 크레파스 느낌 선분 (도트 + 메인 + 얇은 하이라이트 레이어)
local function addSegmentVisual(x1, y1, x2, y2, color, thickness)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    local thickPx = ({[1]=6, [2]=11, [3]=18})[thickness] or 11
    local angle   = math.deg(math.atan2(dy, dx))
    local cx      = (x1 + x2) * 0.5
    local cy      = (y1 + y2) * 0.5
    local lenExt  = len + thickPx  -- 이음새 없애기 위해 조금 연장

    local function makeStroke(offY, w, alpha, cornerR)
        local f = Instance.new("Frame")
        f.BackgroundColor3      = color
        f.BackgroundTransparency = alpha
        f.BorderSizePixel       = 0
        f.Size                  = UDim2.new(0, lenExt, 0, w)
        f.Position              = UDim2.new(0, cx - lenExt*0.5, 0, cy - w*0.5 + offY)
        f.Rotation              = angle
        f.ZIndex                = 35
        f.Parent                = canvasArea
        Instance.new("UICorner", f).CornerRadius = UDim.new(cornerR, 0)
        return f
    end

    -- 메인 크레파스 획 (약간 투명 + 둥글지 않게 → 크레파스 느낌)
    local main = makeStroke(0, thickPx, 0.05, 0.25)

    -- 중앙 하이라이트 (밝은 느낌, 반투명)
    makeStroke(0, math.max(2, thickPx * 0.35), 0.45, 0.3)

    -- 끝점 도트 (선 연결 공백 메움)
    local dot = Instance.new("Frame")
    dot.BackgroundColor3      = color
    dot.BackgroundTransparency = 0.05
    dot.BorderSizePixel       = 0
    dot.Size                  = UDim2.new(0, thickPx, 0, thickPx)
    dot.Position              = UDim2.new(0, x2 - thickPx*0.5, 0, y2 - thickPx*0.5)
    dot.ZIndex                = 35
    dot.Parent                = canvasArea
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)

    return main
end

-- 캔버스 닫기 (아이템 소모 없음)
local function closeCanvas()
    canvasOverlay.Visible = false
    isDrawing = false
    for _, child in ipairs(canvasArea:GetChildren()) do child:Destroy() end
    strokes = {}
    currentStroke = nil
    local char = player.Character
    local hum  = char and char:FindFirstChild("Humanoid")
    if hum then hum.WalkSpeed = 16 end
    if canvasTimeoutThread then
        task.cancel(canvasTimeoutThread)
        canvasTimeoutThread = nil
    end
    submitBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    -- 채팅/핫바 복원
    local StarterGui = game:GetService("StarterGui")
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true) end)
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
end

-- 완료 버튼 활성/비활성 업데이트
local function updateSubmitBtn()
    if #strokes > 0 then
        submitBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
    else
        submitBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    end
end

-- 캔버스 열기
local function openCanvas()
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    canvasSnapOriginPos  = hrp.Position
    canvasSnapLookVector = hrp.CFrame.LookVector

    hum.WalkSpeed = 0

    strokes = {}
    currentStroke = nil
    for _, child in ipairs(canvasArea:GetChildren()) do child:Destroy() end
    updateSubmitBtn()
    canvasOverlay.Visible = true
    -- 채팅/핫바 숨김 (그림 방해 방지)
    local StarterGui = game:GetService("StarterGui")
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

    canvasTimeoutThread = task.delay(60, function()
        canvasTimeoutThread = nil
        if canvasOverlay.Visible then
            closeCanvas()
        end
    end)
end

-- 마우스 드로잉 이벤트
-- InputBegan: 캔버스 위에서 클릭 시작
canvasArea.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not canvasOverlay.Visible then return end
    if #strokes >= 20 then return end
    isDrawing = true
    local pos   = input.Position
    local aPos  = canvasArea.AbsolutePosition
    local aSize = canvasArea.AbsoluteSize
    local x = pos.X - aPos.X
    local y = pos.Y - aPos.Y
    currentStroke = {
        color     = currentColor,
        thickness = currentThickness,
        points    = {{x = math.clamp(x/aSize.X, 0, 1), y = math.clamp(y/aSize.Y, 0, 1)}},
        frames    = {},
        lastX     = x,
        lastY     = y,
    }
end)

-- InputChanged: UserInputService 글로벌 이벤트 사용 (마우스가 캔버스 밖으로 나가도 추적)
UserInputService.InputChanged:Connect(function(input)
    if not isDrawing or not currentStroke then return end
    if not canvasOverlay.Visible then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local pos   = input.Position
    local aPos  = canvasArea.AbsolutePosition
    local aSize = canvasArea.AbsoluteSize
    local x = pos.X - aPos.X
    local y = pos.Y - aPos.Y
    local dx = x - currentStroke.lastX
    local dy = y - currentStroke.lastY
    if math.sqrt(dx*dx + dy*dy) < 1 then return end  -- 최소 이동 거리 (1px로 낮춤)

    local seg = addSegmentVisual(
        currentStroke.lastX, currentStroke.lastY, x, y,
        currentStroke.color, currentStroke.thickness)
    if seg then table.insert(currentStroke.frames, seg) end

    local aSize2 = canvasArea.AbsoluteSize
    table.insert(currentStroke.points, {
        x = math.clamp(x / aSize2.X, 0, 1),
        y = math.clamp(y / aSize2.Y, 0, 1),
    })
    currentStroke.lastX = x
    currentStroke.lastY = y
end)

-- InputEnded: UserInputService 글로벌로 마우스 버튼 해제 감지
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not isDrawing or not currentStroke then return end
    isDrawing = false
    if #currentStroke.points >= 2 then
        table.insert(strokes, {
            color     = currentStroke.color,
            thickness = currentStroke.thickness,
            points    = currentStroke.points,
            frames    = currentStroke.frames,
        })
        updateSubmitBtn()
    end
    currentStroke = nil
end)

-- 실행취소 버튼
undoBtn.MouseButton1Click:Connect(function()
    if #strokes == 0 then return end
    local last = table.remove(strokes)
    for _, f in ipairs(last.frames or {}) do
        if f.Parent then f:Destroy() end
    end
    updateSubmitBtn()
end)

-- 취소 버튼
cancelBtn.MouseButton1Click:Connect(function()
    closeCanvas()
end)

-- 스프레이 버튼 클릭
sprayButton.MouseButton1Click:Connect(function()
    if sprayNearWall and not canvasOverlay.Visible then
        openCanvas()
    end
end)

-- 완료 버튼
submitBtn.MouseButton1Click:Connect(function()
    if #strokes == 0 then return end

    local sendStrokes = {}
    for _, s in ipairs(strokes) do
        table.insert(sendStrokes, {
            color     = s.color,
            thickness = s.thickness,
            points    = s.points,
        })
    end

    Events.GraffitiPlaced:FireServer({
        strokes    = sendStrokes,
        originPos  = canvasSnapOriginPos,
        lookVector = canvasSnapLookVector,
    })

    closeCanvas()
end)

-- 사망 시 캔버스 강제 닫기
player.CharacterAdded:Connect(function()
    if canvasOverlay and canvasOverlay.Visible then
        closeCanvas()
    end
end)

-- 탈락 오버레이 (기본 숨김)
local eliminatedOverlay = Instance.new("Frame")
eliminatedOverlay.Name = "EliminatedOverlay"
eliminatedOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
eliminatedOverlay.BackgroundTransparency = 0.4
eliminatedOverlay.Size = UDim2.new(1, 0, 1, 0)
eliminatedOverlay.Visible = false
eliminatedOverlay.ZIndex = 10
eliminatedOverlay.Parent = screenGui

local eliminatedText = Instance.new("TextLabel")
eliminatedText.Text = "잡혔다!"
eliminatedText.TextColor3 = Color3.fromRGB(255, 100, 100)
eliminatedText.BackgroundTransparency = 1
eliminatedText.Size = UDim2.new(1, 0, 0.5, 0)   -- 위쪽 절반 (재도전 버튼 공간 확보)
eliminatedText.Position = UDim2.new(0, 0, 0, 0)
eliminatedText.Font = Enum.Font.GothamBold
eliminatedText.TextSize = 72
eliminatedText.ZIndex = 11
eliminatedText.Parent = eliminatedOverlay

-- 관전자 정보 패널 (탈락 후 표시)
local spectatorPanel = Instance.new("Frame")
spectatorPanel.Name = "SpectatorPanel"
spectatorPanel.Size = UDim2.new(0, 200, 0, 120)
spectatorPanel.AnchorPoint = Vector2.new(0, 0)
spectatorPanel.Position = UDim2.new(0, 10, 0.5, -60)
spectatorPanel.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
spectatorPanel.BackgroundTransparency = 0.35
spectatorPanel.BorderSizePixel = 0
spectatorPanel.Visible = false
spectatorPanel.ZIndex = 11
spectatorPanel.Parent = screenGui
Instance.new("UICorner", spectatorPanel).CornerRadius = UDim.new(0, 14)

local spectatorTitle = Instance.new("TextLabel")
spectatorTitle.Text = "👁  관전 중"
spectatorTitle.Size = UDim2.new(1, 0, 0, 32)
spectatorTitle.Position = UDim2.new(0, 0, 0, 6)
spectatorTitle.BackgroundTransparency = 1
spectatorTitle.Font = Enum.Font.GothamBold
spectatorTitle.TextSize = 18
spectatorTitle.TextColor3 = Color3.fromRGB(180, 180, 255)
spectatorTitle.ZIndex = 12
spectatorTitle.Parent = spectatorPanel

local spectatorAlive = Instance.new("TextLabel")
spectatorAlive.Name = "AliveCount"
spectatorAlive.Text = "생존자: -명"
spectatorAlive.Size = UDim2.new(1, 0, 0, 26)
spectatorAlive.Position = UDim2.new(0, 0, 0, 40)
spectatorAlive.BackgroundTransparency = 1
spectatorAlive.Font = Enum.Font.Gotham
spectatorAlive.TextSize = 15
spectatorAlive.TextColor3 = Color3.fromRGB(220, 220, 220)
spectatorAlive.ZIndex = 12
spectatorAlive.Parent = spectatorPanel

local spectatorTip = Instance.new("TextLabel")
spectatorTip.Text = "카메라를 자유롭게\n이동하세요"
spectatorTip.Size = UDim2.new(1, -10, 0, 44)
spectatorTip.Position = UDim2.new(0, 5, 0, 68)
spectatorTip.BackgroundTransparency = 1
spectatorTip.Font = Enum.Font.Gotham
spectatorTip.TextSize = 12
spectatorTip.TextColor3 = Color3.fromRGB(150, 150, 150)
spectatorTip.TextWrapped = true
spectatorTip.ZIndex = 12
spectatorTip.Parent = spectatorPanel

-- 재도전 버튼 (GameOver 후에만 표시)
local rematchBtn = Instance.new("TextButton")
rematchBtn.Name = "RematchButton"
rematchBtn.Text = "🔄  재도전"
rematchBtn.Size = UDim2.new(0, 220, 0, 60)
rematchBtn.AnchorPoint = Vector2.new(0.5, 0.5)
rematchBtn.Position = UDim2.new(0.5, 0, 0.65, 0)
rematchBtn.BackgroundColor3 = Color3.fromRGB(130, 220, 160)
rematchBtn.TextColor3 = Color3.fromRGB(30, 80, 50)
rematchBtn.Font = Enum.Font.GothamBold
rematchBtn.TextSize = 22
rematchBtn.Visible = false
rematchBtn.ZIndex = 12
rematchBtn.Parent = screenGui

local rematchCorner = Instance.new("UICorner")
rematchCorner.CornerRadius = UDim.new(0, 24)
rematchCorner.Parent = rematchBtn

local isRematchReady = false

-- 타이머 포맷 (초 → MM:SS)
local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

local function stopElapsedTimer()
    timerRunning = false
end

local function startElapsedTimer()
    timerRunning = true
    task.spawn(function()
        while timerRunning do
            local elapsed = math.floor(tick() - stageStartedAt)
            timerLabel.Text = "⏱ " .. formatTime(elapsed)
            timerLabel.TextColor3 = textColorNormal
            task.wait(1)
        end
    end)
end

-- 함정 설치 공통 함수
local trapDebounce = false
local function useTrap()
    if not trapButton.Visible then return end
    if trapDebounce then return end
    trapDebounce = true
    Events.TrapPlaced:FireServer()
    task.delay(0.5, function() trapDebounce = false end)
end

-- 함정 버튼 클릭
trapButton.MouseButton1Click:Connect(useTrap)

-- 로컬에서 내 연막 모델 즉시 제거 (파티클 잔상 없이)
local function clearLocalSmoke()
    local smokeName = "SmokeCloud_" .. player.Name
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == smokeName and obj:IsA("Model") then
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("ParticleEmitter") then
                    pcall(function() desc:Clear(); desc.Enabled = false end)
                elseif desc:IsA("Smoke") then
                    pcall(function() desc.Opacity = 0 end)
                end
            end
            pcall(function() obj:Destroy() end)
        end
    end
end

-- 연막탄 발사 후 이동 감지 → 로컬 즉시 제거 + SmokeCanceled 전송
local function startSmokeMovementWatch()
    task.spawn(function()
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local startPos = hrp.Position
        local deadline = tick() + 32
        while tick() < deadline do
            task.wait(0.1)
            if not hrp.Parent then break end
            if (hrp.Position - startPos).Magnitude > 1 then
                clearLocalSmoke()              -- 로컬 즉시 제거
                Events.SmokeCanceled:FireServer()  -- 서버에도 알림
                break
            end
        end
    end)
end

-- 연막탄 사용 공통 함수
local function useSmoke()
    if not smokeButton.Visible then return end
    Events.SmokePlaced:FireServer()
    smokeButton.Visible = false
    startSmokeMovementWatch()
end

-- 키보드 단축키
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F then
        useTrap()
    elseif input.KeyCode == Enum.KeyCode.G then
        useCarrot("poop")
    elseif input.KeyCode == Enum.KeyCode.H then
        useCarrot("speed")
    elseif input.KeyCode == Enum.KeyCode.Z then
        useSmoke()
    elseif input.KeyCode == Enum.KeyCode.X then
        if sprayButton.Visible and sprayNearWall and not canvasOverlay.Visible then
            openCanvas()
        end
    end
end)

smokeButton.MouseButton1Click:Connect(function()
    useSmoke()
end)

-- ── Roblox Tool 핫바 활성화 처리 ────────────────────────────────────────────
local function connectToolActivated(tool)
    local tag = tool:FindFirstChild("ToolType")
    if not tag then return end
    local toolType = tag.Value

    if toolType == "trap" then
        tool.Activated:Connect(function()
            useTrap()
        end)
    elseif toolType == "smoke" then
        tool.Activated:Connect(function()
            useSmoke()
        end)
    elseif toolType == "spray" then
        tool.Activated:Connect(function()
            if sprayButton.Visible and sprayNearWall and not canvasOverlay.Visible then
                openCanvas()
            end
        end)
    elseif toolType == "carrot" then
        -- 당근: G/H 키로 선택 (기존 유지). Activated는 안내만 표시.
        tool.Activated:Connect(function()
            -- G키=똥, H키=속도 안내 (기존 키 계속 사용)
        end)
    end
end

-- 장착 시 Tool.Activated 연결
local function onCharacterAdded(char)
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            connectToolActivated(child)
        end
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

-- 스프레이 캔: 스프레이 보유 시 언제든 사용 가능 (서버에서 벽 근접 검증)
-- sprayNearWall은 항상 true로 유지 (버튼이 보일 때)
task.spawn(function()
    while true do
        task.wait(0.3)
        if sprayButton.Visible then
            sprayNearWall = true
            sprayButton.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
            sprayButton.TextColor3       = Color3.fromRGB(20, 20, 80)
        else
            sprayNearWall = false
        end
    end
end)

-- 재도전 버튼 클릭
rematchBtn.MouseButton1Click:Connect(function()
    if isRematchReady then return end
    isRematchReady = true
    rematchBtn.Text = "⏳  다른 플레이어 대기 중..."
    rematchBtn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
    rematchBtn.TextColor3 = Color3.fromRGB(100, 100, 100)
    Events.ReadyUp:FireServer()
end)

-- 스테이지 시작 이벤트 (재도전 성공 → 새 게임 시작)
Events.StageStarted.OnClientEvent:Connect(function(data)
    local fl = data.floor or data.stage or 1
    stageLabel.Text = fl .. "층"
    stageStartedAt = tick()
    timerLabel.Text = "⏱ 00:00"
    timerLabel.TextColor3 = textColorNormal
    timerLabel.Parent.Visible = true
    stopElapsedTimer()
    startElapsedTimer()
    survivorsLabel.Text = "생존자 " .. data.survivors .. "명"
    eliminatedOverlay.Visible = false
    trapButton.Visible = false
    smokeButton.Visible = false
    sprayButton.Visible = false
    sprayNearWall       = false
    spectatorPanel.Visible = false
    hideCarrotButtons()
    -- 위험 감지 초기화
    currentDangerLevel = "safe"
    stopDangerPulse()
    -- 카운트다운 / 랭킹 프레임 제거
    local oldCd = screenGui:FindFirstChild("StageCountdown")
    if oldCd then oldCd:Destroy() end
    local oldFrame = screenGui:FindFirstChild("RankingFrame")
    if oldFrame then oldFrame:Destroy() end
    -- 재도전 버튼 초기화
    rematchBtn.Visible = false
    isRematchReady = false
    rematchBtn.Text = "🔄  재도전"
    rematchBtn.BackgroundColor3 = Color3.fromRGB(130, 220, 160)
    rematchBtn.TextColor3 = Color3.fromRGB(30, 80, 50)

    -- ── 층 진입 플래시 연출 ──────────────────────────────────────
    local isMilestone = (fl % 10 == 0) or fl == 25 or fl == 75
    local flash = Instance.new("Frame")
    flash.Name = "FloorEntryFlash"
    flash.Size = UDim2.new(1, 0, 1, 0)
    flash.BackgroundColor3 = isMilestone
        and Color3.fromRGB(80, 55, 0)
        or  Color3.fromRGB(10, 15, 30)
    flash.BackgroundTransparency = 0
    flash.ZIndex = 25
    flash.Parent = screenGui

    local floorBig = Instance.new("TextLabel")
    floorBig.Text = fl .. "층"
    floorBig.Font = Enum.Font.GothamBold
    floorBig.TextSize = isMilestone and 100 or 80
    floorBig.TextColor3 = isMilestone
        and Color3.fromRGB(255, 220, 60)
        or  Color3.fromRGB(180, 220, 255)
    floorBig.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    floorBig.TextStrokeTransparency = 0.3
    floorBig.BackgroundTransparency = 1
    floorBig.AnchorPoint = Vector2.new(0.5, 0.5)
    floorBig.Size = UDim2.new(0.6, 0, 0, 110)
    floorBig.Position = UDim2.new(0.5, 0, 0.44, 0)
    floorBig.ZIndex = 26
    floorBig.Parent = flash

    local subTxt = Instance.new("TextLabel")
    if isMilestone then
        subTxt.Text = "⭐ 특별 층 ⭐"
        subTxt.TextColor3 = Color3.fromRGB(255, 200, 60)
    else
        subTxt.Text = "탑 " .. fl .. " / 100"
        subTxt.TextColor3 = Color3.fromRGB(160, 200, 255)
    end
    subTxt.Font = Enum.Font.Gotham
    subTxt.TextSize = 24
    subTxt.BackgroundTransparency = 1
    subTxt.AnchorPoint = Vector2.new(0.5, 0)
    subTxt.Size = UDim2.new(0.5, 0, 0, 36)
    subTxt.Position = UDim2.new(0.5, 0, 0.57, 0)
    subTxt.ZIndex = 26
    subTxt.Parent = flash

    -- 0.5초 유지 후 페이드아웃
    task.delay(0.5, function()
        if not flash.Parent then return end
        TweenService:Create(flash,
            TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 }
        ):Play()
        TweenService:Create(floorBig,
            TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 1, TextStrokeTransparency = 1 }
        ):Play()
        TweenService:Create(subTxt,
            TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 1 }
        ):Play()
        task.delay(0.75, function()
            if flash.Parent then flash:Destroy() end
        end)
    end)
end)

-- HUD 업데이트 이벤트
Events.UpdateHUD.OnClientEvent:Connect(function(data)
    if data.type == "timer" then
        -- 제한 시간 없음 모드 → timer 이벤트 무시
        return

    elseif data.type == "extraHunterSpawned" then
        playSound(SFX.hunterSpawn, 0.7)
        -- ⚠️ 추가 헌터 등장 경고
        local warn = Instance.new("TextLabel")
        warn.Text = "⚠️  추가 헌터 등장!  (" .. (data.count or 1) .. "마리째)"
        warn.Font = Enum.Font.GothamBold
        warn.TextSize = 30
        warn.TextColor3 = Color3.fromRGB(255, 60, 60)
        warn.TextStrokeColor3 = Color3.fromRGB(80, 0, 0)
        warn.TextStrokeTransparency = 0.2
        warn.BackgroundTransparency = 1
        warn.Size = UDim2.new(0.9, 0, 0.1, 0)
        warn.AnchorPoint = Vector2.new(0.5, 0.5)
        warn.Position = UDim2.new(0.5, 0, 0.25, 0)
        warn.ZIndex = 9
        warn.Parent = screenGui
        TweenService:Create(warn,
            TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, 0, 0.15, 0),
             TextTransparency = 1,
             TextStrokeTransparency = 1}
        ):Play()
        task.delay(2.2, function()
            if warn.Parent then warn:Destroy() end
        end)

    elseif data.type == "escapedSelf" then
        playSound(SFX.escape, 1.0)
        -- 탈출 소요 시간을 타이머 자리에 표시
        local elapsed = math.floor(tick() - stageStartedAt)
        timerLabel.Text = "🏁 " .. formatTime(elapsed)
        timerLabel.TextColor3 = Color3.fromRGB(80, 200, 120)
        timerLabel.Parent.Visible = true

        -- 탈출 성공 팝업 알림
        local notif = Instance.new("TextLabel")
        notif.Text = "🎉  탈출 성공!  " .. formatTime(elapsed)
        notif.Font = Enum.Font.GothamBold
        notif.TextSize = 52
        notif.TextColor3 = Color3.fromRGB(100, 255, 160)
        notif.TextStrokeColor3 = Color3.fromRGB(0, 60, 30)
        notif.TextStrokeTransparency = 0.2
        notif.BackgroundTransparency = 1
        notif.Size = UDim2.new(0.8, 0, 0.15, 0)
        notif.AnchorPoint = Vector2.new(0.5, 0.5)
        notif.Position = UDim2.new(0.5, 0, 0.45, 0)
        notif.ZIndex = 9
        notif.Parent = screenGui
        TweenService:Create(notif,
            TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, 0, 0.3, 0),
             TextTransparency = 1,
             TextStrokeTransparency = 1}
        ):Play()
        task.delay(2, function()
            if notif.Parent then notif:Destroy() end
        end)

    elseif data.type == "charAbility" then
        -- 층 시작 시 내 캐릭터 능력 알림
        local banner = Instance.new("TextLabel")
        banner.Text = data.desc or ""
        banner.Font = Enum.Font.GothamBold
        banner.TextSize = 20
        banner.TextColor3 = Color3.fromRGB(220, 255, 220)
        banner.BackgroundColor3 = Color3.fromRGB(20, 50, 20)
        banner.BackgroundTransparency = 0.2
        banner.Size = UDim2.new(0.52, 0, 0, 40)
        banner.AnchorPoint = Vector2.new(0.5, 0)
        banner.Position = UDim2.new(0.5, 0, 0.14, 0)
        banner.ZIndex = 10
        banner.Parent = screenGui
        Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
        task.delay(3.5, function()
            if not banner.Parent then return end
            TweenService:Create(banner,
                TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 1, BackgroundTransparency = 1 }
            ):Play()
            task.delay(0.55, function()
                if banner.Parent then banner:Destroy() end
            end)
        end)

    elseif data.type == "bossFloor" then
        -- 보스 층 경고 배너
        playSound(SFX.hunterSpawn, 0.9, 0.85)
        local warn = Instance.new("TextLabel")
        warn.Text = "💀  " .. (data.floor or "?") .. "층 — 보스 층!  사냥꾼 강화!"
        warn.Font = Enum.Font.GothamBold
        warn.TextSize = 28
        warn.TextColor3 = Color3.fromRGB(255, 60, 60)
        warn.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
        warn.TextStrokeTransparency = 0.2
        warn.BackgroundColor3 = Color3.fromRGB(30, 0, 0)
        warn.BackgroundTransparency = 0.2
        warn.Size = UDim2.new(0.65, 0, 0, 50)
        warn.AnchorPoint = Vector2.new(0.5, 0)
        warn.Position = UDim2.new(0.5, 0, 0.08, 0)
        warn.ZIndex = 10
        warn.Parent = screenGui
        local wc = Instance.new("UICorner")
        wc.CornerRadius = UDim.new(0, 14)
        wc.Parent = warn
        task.delay(4, function()
            if not warn.Parent then return end
            TweenService:Create(warn,
                TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 }
            ):Play()
            task.delay(0.65, function()
                if warn.Parent then warn:Destroy() end
            end)
        end)

    elseif data.type == "dangerAlert" then
        local lvl = data.level or "safe"
        if lvl ~= currentDangerLevel then
            currentDangerLevel = lvl
            startDangerPulse(lvl)
        end

    elseif data.type == "milestoneSupply" then
        -- 마일스톤 보급품 배너
        local fl = data.floor or 0
        local supplyText = fl >= 50
            and ("🎁  " .. fl .. "층 마일스톤 — 연막탄 +1 · 당근 +1 지급!")
            or  ("🎁  " .. fl .. "층 마일스톤 — 연막탄 +1 지급!")
        local banner = Instance.new("TextLabel")
        banner.Text = supplyText
        banner.Font = Enum.Font.GothamBold
        banner.TextSize = 24
        banner.TextColor3 = Color3.fromRGB(255, 230, 80)
        banner.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
        banner.TextStrokeTransparency = 0.2
        banner.BackgroundColor3 = Color3.fromRGB(40, 30, 0)
        banner.BackgroundTransparency = 0.25
        banner.Size = UDim2.new(0.7, 0, 0, 46)
        banner.AnchorPoint = Vector2.new(0.5, 0)
        banner.Position = UDim2.new(0.5, 0, 0.08, 0)
        banner.ZIndex = 10
        banner.Parent = screenGui
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 14)
        bc.Parent = banner
        playSound(SFX.carrotPickup, 0.8, 0.9)
        task.delay(3.5, function()
            if not banner.Parent then return end
            TweenService:Create(banner,
                TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 }
            ):Play()
            task.delay(0.65, function()
                if banner.Parent then banner:Destroy() end
            end)
        end)

    elseif data.type == "stageCountdown" then
        -- 기존 카운트다운 제거
        local old = screenGui:FindFirstChild("StageCountdown")
        if old then old:Destroy() end

        if data.count == 0 then return end  -- 0 = 제거만 하고 종료
        playSound(SFX.countdown, 0.5)

        -- 밀스톤 층 여부 (10, 25, 50, 75, 100)
        local fl = data.floor or 0
        local isMilestone = (fl % 10 == 0) or fl == 25 or fl == 75
        local bgColor  = isMilestone and Color3.fromRGB(60, 40, 5)   or Color3.fromRGB(10, 10, 20)
        local numColor = isMilestone and Color3.fromRGB(255, 215, 50) or Color3.fromRGB(100, 220, 255)
        local lblColor = isMilestone and Color3.fromRGB(255, 240, 80) or Color3.fromRGB(255, 240, 180)

        local frame = Instance.new("Frame")
        frame.Name = "StageCountdown"
        frame.BackgroundColor3 = bgColor
        frame.BackgroundTransparency = 0.15
        frame.Size = UDim2.new(0, 300, 0, 150)
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position = UDim2.new(0.5, 0, 0.45, 0)
        frame.BorderSizePixel = 0
        frame.ZIndex = 20
        frame.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 20)
        corner.Parent = frame

        if isMilestone then
            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 200, 50)
            stroke.Thickness = 2
            stroke.Parent = frame
        end

        -- 층 레이블
        local lbl = Instance.new("TextLabel")
        lbl.Text = data.label or ""
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 24
        lbl.TextColor3 = lblColor
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 0, 38)
        lbl.Position = UDim2.new(0, 0, 0, 8)
        lbl.ZIndex = 21
        lbl.Parent = frame

        -- 숫자 카운트 (크게)
        local num = Instance.new("TextLabel")
        num.Text = tostring(data.count)
        num.Font = Enum.Font.GothamBold
        num.TextSize = 80
        num.TextColor3 = numColor
        num.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        num.TextStrokeTransparency = 0.4
        num.BackgroundTransparency = 1
        num.Size = UDim2.new(1, 0, 0, 90)
        num.Position = UDim2.new(0, 0, 0, 48)
        num.ZIndex = 21
        num.Parent = frame

        -- 팝인 + 펄스 애니메이션
        frame.Size = UDim2.new(0, 140, 0, 80)
        TweenService:Create(frame,
            TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 300, 0, 150) }
        ):Play()
        -- 숫자 펄스
        num.TextSize = 60
        task.delay(0.18, function()
            if num.Parent then
                TweenService:Create(num,
                    TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { TextSize = 80 }
                ):Play()
            end
        end)

    elseif data.type == "playerEscaped" or data.type == "playerCaught" then
        survivorsLabel.Text = "생존자 " .. (data.survivors or 0) .. "명"
        -- 관전 패널 생존자 수 업데이트
        if spectatorPanel.Visible then
            spectatorAlive.Text = "생존자: " .. (data.survivors or 0) .. "명"
        end

    elseif data.type == "trapPickup" then
        playSound(SFX.trapPickup)
        local cnt = data.count or 1
        trapButton.Text    = "🪤 함정 [F]  x" .. cnt
        trapButton.Visible = true

    elseif data.type == "trapUsed" then
        local cnt = data.count or 0

        -- 로컬 전용 함정 시각 (설치한 플레이어에게만 보임)
        if data.trapPos then
            local px, py, pz = data.trapPos.X, data.trapPos.Y, data.trapPos.Z
            local visual = Instance.new("Part")
            visual.Name        = "LocalTrapVisual"
            visual.Size        = Vector3.new(3, 3, 3)
            visual.CFrame      = CFrame.new(px, py + 1.5, pz)
            visual.Anchored    = true
            visual.CanCollide  = false
            visual.Transparency = 0.3   -- 반투명으로 내 함정 표시
            visual.Parent      = workspace
            local sm = Instance.new("SpecialMesh")
            sm.MeshType = Enum.MeshType.FileMesh
            sm.MeshId   = "rbxassetid://5033484855"
            sm.Scale    = Vector3.new(1, 1, 1)
            sm.Parent   = visual
            -- 60초 후 자동 제거
            task.delay(60, function()
                if visual.Parent then visual:Destroy() end
            end)
        end

        -- 설치 완료 알림
        local notif = Instance.new("TextLabel")
        notif.Text = "🪤  함정 설치 완료!"
        notif.Font = Enum.Font.GothamBold
        notif.TextSize = 32
        notif.TextColor3 = Color3.fromRGB(255, 204, 80)
        notif.TextStrokeColor3 = Color3.fromRGB(80, 50, 0)
        notif.TextStrokeTransparency = 0.2
        notif.BackgroundTransparency = 1
        notif.Size = UDim2.new(0.6, 0, 0.1, 0)
        notif.AnchorPoint = Vector2.new(0.5, 0.5)
        notif.Position = UDim2.new(0.5, 0, 0.65, 0)
        notif.ZIndex = 9
        notif.Parent = screenGui
        TweenService:Create(notif,
            TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Position = UDim2.new(0.5, 0, 0.5, 0),
              TextTransparency = 1, TextStrokeTransparency = 1 }
        ):Play()
        task.delay(1.6, function() if notif.Parent then notif:Destroy() end end)

        if cnt > 0 then
            trapButton.Text    = "🪤 함정 [F]  x" .. cnt
            trapButton.Visible = true
        else
            trapButton.Visible = false
            trapButton.Text    = "🪤 함정 [F]"
        end

    elseif data.type == "carrotPickup" then
        playSound(SFX.carrotPickup, 0.8)
        -- 당근 획득 → 버튼 표시 + 개수 표시
        local cnt = data.count or 1
        poopButton.Visible  = true
        speedButton.Visible = true
        poopButton.Text   = "💩 똥 [G]  🥕×" .. cnt
        speedButton.Text  = "⚡ 속도 [H]  🥕×" .. cnt

    elseif data.type == "carrotUsedPoop" then
        local rem = data.remaining or 0
        if rem > 0 then
            poopButton.Text    = "💩 똥 [G]  🥕×" .. rem
            speedButton.Text   = "⚡ 속도 [H]  🥕×" .. rem
            poopButton.Visible  = true
            speedButton.Visible = true
        else
            hideCarrotButtons()
        end
        local notif = Instance.new("TextLabel")
        notif.Text = "💩  위치가 노출됐다!"
        notif.Font = Enum.Font.GothamBold
        notif.TextSize = 36
        notif.TextColor3 = Color3.fromRGB(160, 100, 40)
        notif.TextStrokeColor3 = Color3.fromRGB(60, 30, 0)
        notif.TextStrokeTransparency = 0.3
        notif.BackgroundTransparency = 1
        notif.Size = UDim2.new(0.7, 0, 0.12, 0)
        notif.AnchorPoint = Vector2.new(0.5, 0.5)
        notif.Position = UDim2.new(0.5, 0, 0.58, 0)
        notif.ZIndex = 9
        notif.Parent = screenGui
        TweenService:Create(notif,
            TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, 0, 0.42, 0),
             TextTransparency = 1, TextStrokeTransparency = 1}
        ):Play()
        task.delay(2, function() if notif.Parent then notif:Destroy() end end)

    elseif data.type == "carrotUsedSpeed" then
        -- ⚡ 선택 알림 + 화면 글로우
        local rem2 = data.remaining or 0
        if rem2 > 0 then
            poopButton.Text    = "💩 똥 [G]  🥕×" .. rem2
            speedButton.Text   = "⚡ 속도 [H]  🥕×" .. rem2
            poopButton.Visible  = true
            speedButton.Visible = true
        else
            hideCarrotButtons()
        end
        -- 플래시
        task.spawn(function()
            for _ = 1, 3 do
                local flash = Instance.new("Frame")
                flash.BackgroundColor3 = carrotFlashColor
                flash.BackgroundTransparency = 0.4
                flash.Size = UDim2.new(1, 0, 1, 0)
                flash.ZIndex = 5
                flash.Parent = screenGui
                TweenService:Create(flash,
                    TweenInfo.new(0.12, Enum.EasingStyle.Linear),
                    {BackgroundTransparency = 1}):Play()
                task.wait(0.18)
                if flash.Parent then flash:Destroy() end
            end
        end)
        -- 텍스트 알림
        local notif = Instance.new("TextLabel")
        notif.Text = "⚡  속도 증가!"
        notif.Font = Enum.Font.GothamBold
        notif.TextSize = 42
        notif.TextColor3 = carrotFlashColor
        notif.TextStrokeColor3 = Color3.fromRGB(80, 40, 0)
        notif.TextStrokeTransparency = 0.2
        notif.BackgroundTransparency = 1
        notif.Size = UDim2.new(0.7, 0, 0.12, 0)
        notif.AnchorPoint = Vector2.new(0.5, 0.5)
        notif.Position = UDim2.new(0.5, 0, 0.58, 0)
        notif.ZIndex = 9
        notif.Parent = screenGui
        TweenService:Create(notif,
            TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, 0, 0.38, 0),
             TextTransparency = 1, TextStrokeTransparency = 1}):Play()
        task.delay(1.6, function() if notif.Parent then notif:Destroy() end end)
        -- 테두리 글로우
        local oldBorder = screenGui:FindFirstChild("CarrotBorder")
        if oldBorder then oldBorder:Destroy() end
        local borderFrame = Instance.new("Frame")
        borderFrame.Name = "CarrotBorder"
        borderFrame.BackgroundTransparency = 1
        borderFrame.Size = UDim2.new(1, 0, 1, 0)
        borderFrame.ZIndex = 4
        borderFrame.Parent = screenGui
        local uiStroke = Instance.new("UIStroke")
        uiStroke.Color = carrotFlashColor
        uiStroke.Thickness = 12
        uiStroke.Transparency = 0
        uiStroke.Parent = borderFrame
        task.delay(2, function()
            if borderFrame.Parent then
                TweenService:Create(uiStroke,
                    TweenInfo.new(1, Enum.EasingStyle.Linear),
                    {Transparency = 1}):Play()
                task.delay(1.1, function()
                    if borderFrame.Parent then borderFrame:Destroy() end
                end)
            end
        end)

    elseif data.type == "smokePickup" then
        smokeButton.Text = "💨 연막탄 [Z]  x" .. (data.count or 1)
        smokeButton.Visible = true
        playSound(SFX.trapPickup, 0.6)

    elseif data.type == "smokeUsed" then
        if (data.count or 0) > 0 then
            smokeButton.Text = "💨 연막탄 [Z]  x" .. data.count
        else
            smokeButton.Visible = false
        end

    elseif data.type == "smokeCleared" then
        -- 서버가 연막 취소 통보 → 로컬에서 즉시 제거 (잔상 방지)
        clearLocalSmoke()

    elseif data.type == "hudMsg" then
        -- 디버그 메시지 (화면 상단에 3초 표시)
        local lbl = Instance.new("TextLabel")
        lbl.Text = data.msg or ""
        lbl.Size = UDim2.new(1, 0, 0, 30)
        lbl.Position = UDim2.new(0, 0, 0, 60)
        lbl.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        lbl.BackgroundTransparency = 0.3
        lbl.TextColor3 = Color3.fromRGB(255, 255, 100)
        lbl.TextSize = 16
        lbl.Font = Enum.Font.Gotham
        lbl.ZIndex = 100
        lbl.Parent = screenGui
        game:GetService("Debris"):AddItem(lbl, 4)

    elseif data.type == "sprayPickup" then
        sprayButton.Text    = "🎨 낙서 [X]  x" .. (data.count or 1)
        sprayButton.Visible = true
        sprayButton.BackgroundColor3 = Color3.fromRGB(180, 220, 255)

    elseif data.type == "sprayUsed" then
        local remaining = data.count or 0
        if remaining > 0 then
            sprayButton.Text = "🎨 낙서 [X]  x" .. remaining
        else
            sprayButton.Visible = false
            sprayNearWall = false
        end
    end
end)


-- 관전 모드 전환 지연 스레드 (GameOver 시 취소용)
local spectatorThread = nil

-- 탈락 이벤트
Events.PlayerEliminated.OnClientEvent:Connect(function()
    playSound(SFX.caught, 0.9)
    eliminatedOverlay.Visible = true
    eliminatedText.Text = "잡혔다!"
    eliminatedText.TextSize = 72
    eliminatedText.TextColor3 = Color3.fromRGB(255, 100, 100)
    -- 3초 후 관전 패널 표시 (GameOver가 오면 취소됨)
    spectatorThread = task.delay(3, function()
        spectatorThread = nil
        if eliminatedOverlay.Visible then
            eliminatedText.Text = "잡혔다! 😵"
            eliminatedText.TextSize = 36
            eliminatedText.TextColor3 = Color3.fromRGB(255, 80, 80)
            spectatorPanel.Visible = true
        end
    end)
end)

-- 게임 오버 이벤트 — 랭킹 화면 표시
Events.GameOver.OnClientEvent:Connect(function(data)
    stopElapsedTimer()
    if spectatorThread then
        task.cancel(spectatorThread)
        spectatorThread = nil
    end
    spectatorPanel.Visible = false

    local allEscaped = data.allEscaped
    local rankings   = data.rankings or {}

    -- 배경 오버레이
    eliminatedOverlay.Visible = true
    eliminatedOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
    eliminatedOverlay.BackgroundTransparency = 0.25

    -- 타이틀
    if allEscaped then
        eliminatedText.Text = "🎉 탈출 성공!"
        eliminatedText.TextColor3 = Color3.fromRGB(100, 255, 160)
    else
        eliminatedText.Text = "😵 전원 탈출 실패 — 재도전!"
        eliminatedText.TextColor3 = Color3.fromRGB(255, 100, 80)
    end
    eliminatedText.TextSize = 34
    eliminatedText.Position = UDim2.new(0, 0, 0, 0)
    eliminatedText.Size     = UDim2.new(1, 0, 0, 60)

    -- 기존 랭킹 프레임 제거
    local oldFrame = screenGui:FindFirstChild("RankingFrame")
    if oldFrame then oldFrame:Destroy() end

    -- 랭킹 프레임
    local rowH    = 44
    local padTop  = 50  -- 헤더 공간
    local frameH  = padTop + #rankings * rowH + 10
    local rankFrame = Instance.new("Frame")
    rankFrame.Name              = "RankingFrame"
    rankFrame.Size              = UDim2.new(0, 320, 0, frameH)
    rankFrame.AnchorPoint       = Vector2.new(0.5, 0)
    rankFrame.Position          = UDim2.new(0.5, 0, 0, 68)
    rankFrame.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
    rankFrame.BackgroundTransparency = 0.12
    rankFrame.BorderSizePixel   = 0
    rankFrame.ZIndex            = 12
    rankFrame.ClipsDescendants  = true
    rankFrame.Parent            = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 22)
    corner.Parent = rankFrame

    -- 스테이지 헤더 추가
    local stageHeader = Instance.new("TextLabel")
    stageHeader.Text = "🏁  " .. (data.floor or data.stage or 1) .. "층 결과"
    stageHeader.Size = UDim2.new(1, 0, 0, 36)
    stageHeader.Position = UDim2.new(0, 0, 0, 6)
    stageHeader.BackgroundTransparency = 1
    stageHeader.Font = Enum.Font.GothamBold
    stageHeader.TextSize = 22
    stageHeader.TextColor3 = Color3.fromRGB(255, 240, 100)
    stageHeader.ZIndex = 13
    stageHeader.Parent = rankFrame

    local medals = {"🥇", "🥈", "🥉", "4위", "5위", "6위", "7위", "8위"}

    for i, info in ipairs(rankings) do
        local row = Instance.new("TextLabel")
        local medal = medals[info.rank] or (info.rank .. "위")
        local escapeMark = info.escaped and ("  🏁 #" .. info.rank .. "탈출") or "  ❌ 실패"
        row.Text = string.format("  %s  %s%s   +%d점",
            medal, info.name, escapeMark, info.points)
        row.Size               = UDim2.new(1, 0, 0, rowH)
        row.BackgroundTransparency = 1
        row.Font               = Enum.Font.GothamBold
        row.TextSize           = 20
        row.TextXAlignment     = Enum.TextXAlignment.Left
        row.TextColor3         = info.escaped
            and Color3.fromRGB(30, 30, 30)
            or  Color3.fromRGB(200, 60, 60)
        row.ZIndex             = 13
        row.Parent             = rankFrame

        -- 내 플레이어 강조
        if info.name == player.Name then
            row.BackgroundTransparency = 0.6
            row.BackgroundColor3 = Color3.fromRGB(255, 240, 150)
        end

        -- 슬라이드인 애니메이션 (오른쪽 밖에서 시작)
        row.Position = UDim2.new(1, 0, 0, padTop + (i - 1) * rowH)
        task.delay(0.1 * i, function()
            if row.Parent then
                TweenService:Create(row,
                    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {Position = UDim2.new(0, 0, 0, padTop + (i - 1) * rowH)}
                ):Play()
            end
        end)

        -- 1등 탈출 시 특별 사운드 효과
        if info.name == player.Name and info.escaped and info.rank == 1 then
            playSound(SFX.escape, 1.2, 1.1)
        end
    end

    -- 재도전 / 다음 게임 버튼
    isRematchReady = false
    if allEscaped then
        rematchBtn.Text             = "▶  다음 층으로"
        rematchBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
    else
        rematchBtn.Text             = "🔄  재도전"
        rematchBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 60)
    end
    rematchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    rematchBtn.Position   = UDim2.new(0.5, 0, 0, 68 + frameH + 12)
    rematchBtn.Visible    = true
end)

-- ── 100층 탑 클리어 엔딩 화면 ──────────────────────────────────────────────
Events.TowerCleared.OnClientEvent:Connect(function(data)
    eliminatedOverlay.Visible = false
    local oldFrame = screenGui:FindFirstChild("RankingFrame")
    if oldFrame then oldFrame:Destroy() end
    rematchBtn.Visible = false

    -- 엔딩 스토리 라인
    local endingLines = {
        { text = "100층에 도달했다.",                              size = 26 },
        { text = "눈부신 빛이 쏟아지고, 탑이 서서히 사라진다.",    size = 22 },
        { text = "아이는 천천히 눈을 떴다.",                       size = 22 },
        { text = '"...꿈이었나."',                                 size = 20, italic = true },
        { text = "하지만 손바닥에는\n작은 카피바라 발자국이 남아있었다.", size = 18 },
    }

    -- 1단계: 흰 빛으로 화이트아웃
    local flash = Instance.new("Frame")
    flash.Size                   = UDim2.new(1, 0, 1, 0)
    flash.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    flash.BackgroundTransparency = 1
    flash.ZIndex                 = 60
    flash.Parent                 = screenGui

    TweenService:Create(flash, TweenInfo.new(1.2, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 0 }):Play()
    task.wait(1.4)

    -- 2단계: 검은 배경으로 전환 (눈 뜨는 느낌)
    local endingBg = Instance.new("Frame")
    endingBg.Name                 = "TowerClearedScreen"
    endingBg.Size                 = UDim2.new(1, 0, 1, 0)
    endingBg.BackgroundColor3     = Color3.fromRGB(8, 8, 12)
    endingBg.BackgroundTransparency = 0
    endingBg.ZIndex               = 55
    endingBg.Parent               = screenGui

    TweenService:Create(flash, TweenInfo.new(1.0, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 1 }):Play()
    task.wait(0.5)

    -- 3단계: 스토리 텍스트 한 줄씩
    local lbls = {}
    for i, line in ipairs(endingLines) do
        local lbl = Instance.new("TextLabel")
        lbl.Text                   = line.text
        lbl.Size                   = UDim2.new(0.7, 0, 0, 60)
        lbl.AnchorPoint            = Vector2.new(0.5, 0.5)
        lbl.Position               = UDim2.new(0.5, 0, 0.5, (i - (#endingLines + 1) / 2) * 52)
        lbl.BackgroundTransparency = 1
        lbl.Font                   = (line.italic) and Enum.Font.Gotham or Enum.Font.GothamBold
        lbl.TextSize               = line.size
        lbl.TextColor3             = Color3.fromRGB(210, 210, 220)
        lbl.TextXAlignment         = Enum.TextXAlignment.Center
        lbl.TextWrapped            = true
        lbl.TextTransparency       = 1
        lbl.ZIndex                 = 56
        lbl.Parent                 = endingBg
        lbls[i] = lbl
    end

    for i, lbl in ipairs(lbls) do
        TweenService:Create(lbl, TweenInfo.new(1.0, Enum.EasingStyle.Quad),
            { TextTransparency = 0 }):Play()
        task.wait(2.0)
        if i > 1 then
            TweenService:Create(lbls[i-1], TweenInfo.new(0.6),
                { TextTransparency = 0.6 }):Play()
        end
    end

    task.wait(2.0)

    -- 4단계: 새벽빛으로 서서히 밝아짐 (현실로 돌아오는 느낌)
    local dawn = Instance.new("UIGradient")
    dawn.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 220, 150)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 180, 80)),
    })
    dawn.Rotation = 90
    dawn.Parent = endingBg

    TweenService:Create(endingBg, TweenInfo.new(2.5, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 0 }):Play()
    for _, lbl in ipairs(lbls) do
        TweenService:Create(lbl, TweenInfo.new(1.5), { TextTransparency = 0.8 }):Play()
    end
    task.wait(1.5)

    -- 마지막: "꿈에서 깨어났다" 메시지
    local wakeMsg = Instance.new("TextLabel")
    wakeMsg.Text               = "꿈에서 깨어났다."
    wakeMsg.Size               = UDim2.new(0.8, 0, 0, 70)
    wakeMsg.AnchorPoint        = Vector2.new(0.5, 0.5)
    wakeMsg.Position           = UDim2.new(0.5, 0, 0.5, 0)
    wakeMsg.BackgroundTransparency = 1
    wakeMsg.Font               = Enum.Font.GothamBold
    wakeMsg.TextSize           = 48
    wakeMsg.TextColor3         = Color3.fromRGB(255, 255, 240)
    wakeMsg.TextTransparency   = 1
    wakeMsg.TextXAlignment     = Enum.TextXAlignment.Center
    wakeMsg.ZIndex             = 57
    wakeMsg.Parent             = endingBg
    TweenService:Create(wakeMsg, TweenInfo.new(1.5, Enum.EasingStyle.Quad),
        { TextTransparency = 0 }):Play()
end)
