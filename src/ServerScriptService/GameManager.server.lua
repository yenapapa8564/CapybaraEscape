-- ServerScriptService/GameManager
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MazeModule = require(game.ServerScriptService.Modules.MazeModule)
local PlayerManager = require(game.ServerScriptService.Modules.PlayerManager)
local HunterAI = require(game.ServerScriptService.Modules.HunterAI)
local ItemManager = require(game.ServerScriptService.Modules.ItemManager)

local Events = ReplicatedStorage.Events

local readyPlayers = {}

-- 당근 효과 선택 이벤트 (클라이언트에서 G/H 키로 발동)
Events.CarrotChoice.OnServerEvent:Connect(function(player, choice)
    if not PlayerManager.hasPendingCarrot(player) then return end
    if PlayerManager.getState(player) ~= "alive" then
        PlayerManager.setPendingCarrot(player, false)
        return
    end
    if choice == "poop" then
        PlayerManager.applyPoop(player)
        local remaining = PlayerManager.getCarrotCount(player)
        ItemManager.updateToolNamePublic(player, "carrot", remaining)
        Events.UpdateHUD:FireClient(player, { type = "carrotUsedPoop", remaining = remaining })
    elseif choice == "speed" then
        PlayerManager.applySpeedBoost(player)
        local remaining = PlayerManager.getCarrotCount(player)
        ItemManager.updateToolNamePublic(player, "carrot", remaining)
        Events.UpdateHUD:FireClient(player, { type = "carrotUsedSpeed", remaining = remaining })
    end
end)

-- 캐릭터 타입 선택 이벤트
Events.CharacterSelected.OnServerEvent:Connect(function(player, charType)
    local valid = { Dad = true, Mom = true, Son = true, Daughter = true }
    if valid[charType] then
        PlayerManager.setCharType(player, charType)
    end
end)

-- 준비 완료 이벤트
Events.ReadyUp.OnServerEvent:Connect(function(player)
    readyPlayers[player] = true
end)

Players.PlayerRemoving:Connect(function(player)
    readyPlayers[player] = nil
end)

local mazeFolder = Instance.new("Folder")
mazeFolder.Name = "Maze"
mazeFolder.Parent = workspace

local gameDifficulty = "Normal"

local function makeRNG(seed)
    local s = seed
    return function()
        s = (s * 1664525 + 1013904223) % (2^32)
        return s / (2^32)
    end
end

local function broadcastHUD(data)
    for _, player in ipairs(Players:GetPlayers()) do
        Events.UpdateHUD:FireClient(player, data)
    end
end

-- 단일 층 실행
local function runStage(stage, playerList)
    local size = MazeModule.getSizeForStage(stage)
    local seed = math.random(1, 999999)
    local rng  = makeRNG(seed)
    local ws   = Constants.WALL_SIZE.X

    -- 1. 미로 생성
    MazeModule.clear(mazeFolder)
    local grid     = MazeModule.generate(size, seed)
    local mazeInfo = MazeModule.render(grid, size, mazeFolder)

    -- 2. 플레이어 상태 초기화
    PlayerManager.init(playerList)

    -- 3. 스폰 위치 이동
    task.wait(1)
    for i, player in ipairs(playerList) do
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            local deadline = tick() + 3
            repeat task.wait(0.05) until char:FindFirstChild("HumanoidRootPart") or tick() > deadline
            hrp = char:FindFirstChild("HumanoidRootPart")
        end
        if hrp then
            local offset = Vector3.new((i - 1) * 5, 0, 0)
            local target = CFrame.new(mazeInfo.spawnPosition + offset)
            hrp.CFrame = target
            task.wait(0.1)
            hrp.CFrame = target
        end
        task.wait(0.1)
    end

    -- 4. 리본 + 캐릭터 타입 악세서리 적용
    for _, player in ipairs(playerList) do
        PlayerManager.applyCharType(player)
    end

    -- 5. 사냥꾼 스폰
    local centerX   = math.floor(size / 2) * ws + ws / 2
    local centerZ   = math.floor(size / 2) * ws + ws / 2
    local hunterSpawn = Vector3.new(centerX, 5, centerZ)
    HunterAI.spawn(hunterSpawn, gameDifficulty)
    HunterAI.updateSpeedForStage(stage)

    -- 6. 순찰 포인트
    HunterAI.setPatrolPoints({
        Vector3.new(ws, 5, ws),
        Vector3.new((size - 1) * ws, 5, ws),
        Vector3.new((size - 1) * ws, 5, (size - 1) * ws),
        Vector3.new(ws, 5, (size - 1) * ws),
    })

    -- 7.5. 마일스톤 보급 (25 / 50 / 75층 진입 시 전원 추가 아이템)
    local MILESTONES = {[25] = true, [50] = true, [75] = true}
    if MILESTONES[stage] then
        local supplyPlayers = PlayerManager.getAlivePlayers()
        for _, p in ipairs(supplyPlayers) do
            -- 모든 마일스톤: 연막탄 +1
            PlayerManager.addSmoke(p)
            ItemManager.updateToolNamePublic(p, "smoke", PlayerManager.getSmokeCount(p))
            -- 50층+: 당근 +1 추가
            if stage >= 50 then
                local newCarrot = PlayerManager.addCarrot(p)
                ItemManager.updateToolNamePublic(p, "carrot", newCarrot)
            end
            Events.UpdateHUD:FireClient(p, { type = "milestoneSupply", floor = stage })
        end
    end

    -- 8. 출구 Touched 감지
    local exitDebounce = {}
    local escapeOrder  = {}
    local exitConn = mazeInfo.exitPart.Touched:Connect(function(hit)
        local char   = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        if exitDebounce[player] then return end
        if PlayerManager.getState(player) == "alive" then
            exitDebounce[player] = true
            table.insert(escapeOrder, player)
            PlayerManager.setEscaped(player)
            Events.UpdateHUD:FireClient(player, {
                type = "escapedSelf",
                rank = #escapeOrder,
            })
            broadcastHUD({
                type       = "playerEscaped",
                rank       = #escapeOrder,
                playerName = player.Name,
                survivors  = PlayerManager.getSurvivorCount(),
            })
        end
    end)

    -- 9. 사냥꾼 충돌 감지
    HunterAI.onTouched(function(player)
        PlayerManager.eliminate(player)
        broadcastHUD({
            type       = "playerCaught",
            playerName = player.Name,
            survivors  = PlayerManager.getAliveCount(),
        })
    end)

    -- 10. 함정 설치 이벤트
    local trapConn = Events.TrapPlaced.OnServerEvent:Connect(function(player)
        ItemManager.placeTrap(player, mazeInfo.exitPosition, mazeFolder)
    end)

    -- 연막탄 설치 이벤트
    local smokeConn = Events.SmokePlaced.OnServerEvent:Connect(function(player)
        ItemManager.placeSmoke(player, mazeFolder)
    end)

    -- 클라이언트가 이동 감지 → 연막 취소
    local smokeCancelConn = Events.SmokeCanceled.OnServerEvent:Connect(function(player)
        ItemManager.cancelSmoke(player)
    end)

    -- 낙서 설치 이벤트
    local graffitiConn = Events.GraffitiPlaced.OnServerEvent:Connect(function(player, data)
        ItemManager.placeGraffiti(player, data, mazeFolder)
    end)

    -- 11. 층 시작 알림 (타이머 없음)
    Events.StageStarted:FireAllClients({
        stage      = stage,  -- 하위 호환
        floor      = stage,
        timer      = 0,  -- 제한 시간 없음
        survivors  = #playerList,
        difficulty = gameDifficulty,
    })

    -- 7. 아이템 스폰 (StageStarted 이후에 실행해야 버튼이 제대로 보임)
    -- StageStarted가 클라이언트에서 버튼을 숨기므로, 이후에 아이템 지급해야 함
    ItemManager.spawnItems(mazeFolder, rng)

    -- 12. AI 시작
    HunterAI.startAI()

    -- 12.5. 보스 층 (10의 배수) — 사냥꾼 속도 +4 추가, 즉시 추가 헌터 1마리 소환
    if stage % 10 == 0 then
        local config = Constants.HUNTER[gameDifficulty]
        local baseSpeed = math.min(
            config.baseSpeed + config.increment * (stage - 1),
            config.maxSpeed
        )
        local bossSpeed = math.min(baseSpeed + 4, config.maxSpeed + 4)
        local hunterHuman = workspace:FindFirstChild("HunterModel") and
            workspace.HunterModel:FindFirstChild("Humanoid")
        -- HunterAI 내부 모델에 직접 접근 대신 extra 소환으로 보스 효과 구현
        local rx = math.random(1, size - 1) * ws + ws / 2
        local rz = math.random(1, size - 1) * ws + ws / 2
        HunterAI.spawnExtra(Vector3.new(rx, 5, rz))
        broadcastHUD({ type = "bossFloor", floor = stage })
    end

    -- 13. 1분마다 추가 헌터 스폰 (병렬 루프)
    local stageRunning   = true
    local extraCount     = 0
    local extraHunterTask = task.spawn(function()
        local elapsed = 0
        while stageRunning do
            task.wait(1)
            elapsed += 1
            if elapsed > 0 and elapsed % Constants.HUNTER_EXTRA_INTERVAL == 0 then
                extraCount += 1
                -- 미로 내 랜덤 위치 (벽이 아닌 통로 근방)
                local rx = math.random(1, size - 1) * ws + ws / 2
                local rz = math.random(1, size - 1) * ws + ws / 2
                HunterAI.spawnExtra(Vector3.new(rx, 5, rz))
                broadcastHUD({type = "extraHunterSpawned", count = extraCount})
            end
        end
    end)

    -- 14-b. 위험 감지 루프 (0.5초마다 사냥꾼↔플레이어 거리 체크)
    -- 50스터드 이내 = near / 28스터드 이내 = danger
    local dangerState = {}  -- player → "safe" | "near" | "danger"
    local dangerTask = task.spawn(function()
        while stageRunning do
            task.wait(0.5)
            local hunterPositions = HunterAI.getHunterPositions()
            for _, p in ipairs(PlayerManager.getAlivePlayers()) do
                local char = p.Character
                if not char then continue end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end

                local minDist = math.huge
                for _, hp in ipairs(hunterPositions) do
                    local d = (hrp.Position - hp).Magnitude
                    if d < minDist then minDist = d end
                end

                local newState = "safe"
                if minDist <= 28 then
                    newState = "danger"
                elseif minDist <= 55 then
                    newState = "near"
                end

                if dangerState[p] ~= newState then
                    dangerState[p] = newState
                    Events.UpdateHUD:FireClient(p, { type = "dangerAlert", level = newState })
                end
            end
        end
    end)

    -- 14. 탈출 또는 전원 탈락까지 대기 (제한 시간 없음)
    while true do
        task.wait(1)
        if PlayerManager.getAliveCount() == 0 then break end
        if PlayerManager.getEscapedCount() > 0  then break end
    end
    stageRunning = false
    task.cancel(dangerTask)
    -- 전원 danger 해제
    for _, p in ipairs(playerList) do
        pcall(function()
            Events.UpdateHUD:FireClient(p, { type = "dangerAlert", level = "safe" })
        end)
    end

    -- 15. 정리
    exitConn:Disconnect()
    trapConn:Disconnect()
    smokeConn:Disconnect()
    smokeCancelConn:Disconnect()
    graffitiConn:Disconnect()
    HunterAI.stop()
    ItemManager.clear(mazeFolder)

    -- 16. 랭킹 생성
    local rankings   = {}
    local escapedSet = {}
    local totalPlayers = #playerList

    for rank, p in ipairs(escapeOrder) do
        local pts = math.max(totalPlayers - rank + 1, 1)
        table.insert(rankings, {
            name    = p.Name,
            rank    = rank,
            points  = pts,
            escaped = true,
        })
        escapedSet[p] = true
    end

    for _, p in ipairs(playerList) do
        if not escapedSet[p] then
            table.insert(rankings, {
                name    = p.Name,
                rank    = #escapeOrder + 1,
                points  = 0,
                escaped = false,
            })
        end
    end

    local anyEscaped = (#escapeOrder > 0)
    return rankings, anyEscaped
end

-- 모든 플레이어가 준비 완료했는지 확인
local function allReady(playerList)
    for _, p in ipairs(playerList) do
        if not readyPlayers[p] then return false end
    end
    return true
end

-- 최소 인원(MIN_PLAYERS) 이상이 준비했는지 확인
local function enoughReady(playerList)
    local count = 0
    for _, p in ipairs(playerList) do
        if readyPlayers[p] then count += 1 end
    end
    return count >= Constants.MIN_PLAYERS
end

local function startGame(playerList, difficulty)
    gameDifficulty = difficulty or "Normal"
    task.wait(Constants.RESULT_DISPLAY_DURATION)

    local floorNum = 1

    while true do
        local rankings, anyEscaped = runStage(floorNum, playerList)

        -- 100층 클리어 → 탑 완파 엔딩
        if anyEscaped and floorNum >= Constants.MAX_FLOOR then
            Events.GameOver:FireAllClients({
                rankings   = rankings,
                allEscaped = true,
                stage      = floorNum,
                floor      = floorNum,
            })
            task.wait(2)
            Events.TowerCleared:FireAllClients({ floor = floorNum })
            break
        end

        Events.GameOver:FireAllClients({
            rankings   = rankings,
            allEscaped = anyEscaped,
            stage      = floorNum,
            floor      = floorNum,
        })

        readyPlayers = {}
        local waited = 0
        while waited < 30 do
            task.wait(1)
            waited += 1
            local current = Players:GetPlayers()
            -- 전원 준비 시 즉시 시작, MIN_PLAYERS 이상 준비 시 최대 30초 대기
            if #current >= Constants.MIN_PLAYERS and allReady(current) then break end
            if #current >= Constants.MIN_PLAYERS and enoughReady(current) and waited >= 10 then break end
        end

        playerList = Players:GetPlayers()
        if #playerList < Constants.MIN_PLAYERS then break end

        readyPlayers = {}

        if anyEscaped then
            floorNum += 1
        end

        local nextLabel = anyEscaped
            and (floorNum .. "층 시작!")
            or  "재도전!"
        for i = 3, 1, -1 do
            broadcastHUD({ type = "stageCountdown", count = i, label = nextLabel, floor = floorNum })
            task.wait(1)
        end
        broadcastHUD({ type = "stageCountdown", count = 0, label = nextLabel, floor = floorNum })
        task.wait(0.3)
    end
end

local function lobbyWait()
    while true do
        local playerList = Players:GetPlayers()
        if #playerList >= Constants.MIN_PLAYERS then
            local elapsed = 0
            while elapsed < 30 do
                task.wait(1)
                elapsed += 1
                local current = Players:GetPlayers()
                if #current >= Constants.MIN_PLAYERS and allReady(current) then break end
                if #current >= Constants.MIN_PLAYERS and enoughReady(current) and elapsed >= 10 then break end
            end

            local currentPlayers = Players:GetPlayers()
            -- 최소 한 명 이상 준비 완료해야 시작 가능
            if #currentPlayers >= Constants.MIN_PLAYERS and enoughReady(currentPlayers) then
                for i = 5, 1, -1 do
                    for _, p in ipairs(currentPlayers) do
                        Events.UpdateHUD:FireClient(p, {type = "lobbyCountdown", count = i})
                    end
                    task.wait(1)
                end
                readyPlayers = {}
                startGame(currentPlayers, "Normal")
                readyPlayers = {}
                task.wait(2)
            end
        end
        task.wait(2)
    end
end

task.spawn(lobbyWait)
