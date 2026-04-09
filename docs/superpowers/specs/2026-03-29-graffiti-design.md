# 벽 낙서(Graffiti) 기능 설계

**날짜:** 2026-03-29
**프로젝트:** CapybaraEscape (Roblox)

---

## 개요

플레이어가 스프레이 캔 아이템을 사용해 미로 벽에 자유롭게 그림을 그릴 수 있는 기능. 낙서는 SurfaceGui로 벽 표면에 부착되며 스테이지 종료 시 자동 삭제된다.

---

## 요구사항

1. 시작 시 스프레이 캔 1개 지급 (연막탄과 동일한 방식)
2. 벽에서 **3 studs 이내**에 있을 때만 사용 가능
3. X키로 오버레이 캔버스 열기
4. 캔버스 열린 동안 로컬 캐릭터 이동 비활성화 (클라이언트 한정, 서버 전체 정지 아님)
5. 완료 시 가장 가까운 벽 면(Face)에 SurfaceGui로 낙서 부착
6. 작성자가 아닌 플레이어는 보기만 가능 (상호작용 불가)
7. 낙서 하단에 작성자 닉네임 서명 표시
8. 스테이지 종료 시 벽 파트가 속한 mazeFolder 파괴로 자동 삭제
9. 스테이지당 전체 낙서 최대 **20개** 제한

---

## 사용자 흐름

```
스프레이 캔 지급
    → 0.3초마다 벽 근접 체크 (3 studs 이내)
    → X키 입력 (버튼 활성 상태일 때)
    → 캔버스 오픈 시점의 플레이어 위치 스냅샷 저장
    → 로컬 캐릭터 WalkSpeed = 0 (캔버스 닫힐 때 복원)
    → 오버레이 캔버스 열림
    → 색상/굵기 선택 후 마우스 드래그로 드로잉
    → 완료 버튼 클릭
    → GraffitiPlaced RemoteEvent 전송 (스트로크 데이터)
    → 서버: 검증 → SurfaceGui 생성 → 벽 파트에 직접 부모 설정
    → 모든 클라이언트에서 낙서 표시
```

---

## 아키텍처

### 클라이언트 (ClientUI.client.lua)

**벽 근접 체크**
- `task.wait(0.3)` 루프로 0.3초마다 HRP와 주변 벽 파트 거리 체크
- `workspace:GetPartBoundsInRadius(hrp.Position, 3)` 로 후보 파트 필터링
- 벽 파트 여부: Name == "Wall" 이거나 MazeWall 태그 확인
- 조건 충족 시 sprayButton 활성화, 미충족 시 비활성화 + 툴팁

**캔버스 열기**
- X키 입력 → sprayButton 활성 상태일 때만 동작
- 캔버스 오픈 시점의 `hrp.Position` 스냅샷 저장 (서버 전송용)
- 로컬 `humanoid.WalkSpeed = 0` (캔버스 닫힐 때 기본값 복원)
- 플레이어 사망/탈락 시 캔버스 강제 닫기 + WalkSpeed 복원

**드로잉**
- `MouseButton1Down` + `MouseMoved` → 포인트 수집 (5px 미만 간격 필터링)
- `MouseButton1Up` → 스트로크 완료
- 스트로크 20개 초과 시 입력 차단 (클라이언트 제한)
- 실행취소: 마지막 스트로크 삭제 (단일 레벨)
- 취소: 캔버스 닫기, 아이템 소모 없음, WalkSpeed 복원
- 완료: 스트로크 0개면 제출 불가 (완료 버튼 비활성)

**캔버스 타임아웃**
- 열린 후 60초 경과 시 자동 닫힘 + WalkSpeed 복원 (아이템 소모 없음)

**서버 전송 페이로드**
```lua
{
  strokes    = { { color=Color3, thickness=number, points={{x,y},...} }, ... },
  originPos  = Vector3,   -- 캔버스 오픈 시점 위치 스냅샷
  lookVector = Vector3    -- 캔버스 오픈 시점 HRP.CFrame.LookVector (Raycast 방향용)
}
```

**HUD**
- 기존 smokeButton 아래에 sprayButton 추가
- 아이콘 🎨, 키 표시 [X], 남은 개수 표시
- UpdateHUD 이벤트 `type = "sprayUsed"` / `type = "sprayPickup"` 처리

### 서버 (ItemManager.lua)

**placeGraffiti(player, data, mazeFolder)**

1. **스테이지 낙서 수 체크**: 전체 낙서 >= 20이면 거부
2. **consumeSpray 원자적 처리**: `count >= 1` 사전 확인 → 소모 → 이후 검증 실패 시 즉시 환불
3. **거리 재검증**: `data.originPos`(스냅샷)에서 3 studs 이내 벽 파트가 있는지 확인
   - 실패 시 스프레이 환불 후 return
4. **벽 Face 탐지**: `data.originPos`에서 `data.lookVector` 방향으로 Raycast → Hit된 파트와 Face 사용
5. **스트로크 서버 검증**:
   - strokes 개수 > 20 → 거부
   - 각 stroke의 points 개수 > 200 → 거부
   - 각 point x,y → `math.clamp(v, 0, 1)`
   - color → 허용 팔레트 6가지 중 가장 가까운 색으로 스냅
   - thickness → `math.clamp(thickness, 1, 3)`, 숫자가 아니면 2로 기본값
6. **SurfaceGui 생성**: 검증된 벽 파트에 직접 Parent 설정, `ResetOnSpawn = false`
   - 벽 파트는 mazeFolder 하위이므로 스테이지 종료 시 자동 파괴
7. **CanvasSize**: 서버와 클라이언트 모두 `Vector2.new(500, 500)` 고정
8. **스트로크 렌더**: 각 연속 포인트 쌍을 회전된 Frame으로 표현
9. **서명 레이블**: 우하단 TextLabel에 `player.Name` 표시

**mazeFolder 참조**: 서버에서 직접 `workspace:FindFirstChild("MazeFolder_" .. stageId)` 로 조회 (클라이언트로부터 수신하지 않음)

### RemoteEvent

- `GraffitiPlaced` (ReplicatedStorage/Events): 클라이언트 → 서버

---

## 스트로크 데이터 포맷

```lua
{
  color     = Color3,       -- 허용 팔레트 6색 중 하나
  thickness = 2,            -- 1 / 2 / 3
  points    = {             -- 0~1 정규화 좌표
    {x = 0.1, y = 0.3},
    {x = 0.2, y = 0.4},
    ...                     -- 최대 200개
  }
}
```

**공유 상수 (Constants.lua)**
```lua
GRAFFITI_CANVAS_SIZE = 500   -- SurfaceGui CanvasSize 및 클라이언트 캔버스 공통
GRAFFITI_RANGE       = 3     -- 사용 가능 거리 (studs)
GRAFFITI_MAX_STAGE   = 20    -- 스테이지당 최대 낙서 수
SPRAY_COUNT          = 1     -- 시작 시 지급 수량
GRAFFITI_PALETTE     = {     -- 허용 색상 팔레트
  Color3.fromRGB(255,107,107),  -- 빨강
  Color3.fromRGB(253,203,110),  -- 노랑
  Color3.fromRGB(116,185,255),  -- 파랑
  Color3.fromRGB(85,239,196),   -- 민트
  Color3.fromRGB(253,121,168),  -- 핑크
  Color3.fromRGB(223,230,233),  -- 흰색
}
```

---

## UI 구성

| 영역 | 내용 |
|------|------|
| 상단 툴바 | "낙서하기" 타이틀 + 브러시 굵기 3단계 선택 |
| 캔버스 | 게임 화면 반투명 배경, 마우스 드래그로 선 그리기 |
| 하단 팔레트 | 6가지 색상 + 실행취소 + 취소 + 완료 (0 스트로크 시 완료 비활성) |

---

## 변경 파일 목록

| 파일 | 변경 내용 |
|------|-----------|
| `Constants.lua` | SPRAY_COUNT, GRAFFITI_RANGE, GRAFFITI_MAX_STAGE, GRAFFITI_CANVAS_SIZE, GRAFFITI_PALETTE 추가 |
| `PlayerManager.lua` | sprayTable, addSpray, consumeSpray, getSprayCount 추가 (연막탄 패턴 그대로) |
| `ItemManager.lua` | placeGraffiti() 추가, 스테이지 낙서 카운터 관리 |
| `GameManager.server.lua` | GraffitiPlaced 이벤트 연결 (기존 SmokePlaced 패턴과 동일) |
| `ClientUI.client.lua` | X키 바인딩, 드로잉 캔버스 UI, 0.3초 벽 근접 체크 루프, HUD 스프레이 버튼 |
| `ReplicatedStorage/Events` | GraffitiPlaced RemoteEvent 추가 |

---

## 엣지 케이스 처리

| 상황 | 처리 |
|------|------|
| 캔버스 열린 상태로 사망 | 캔버스 강제 닫기, WalkSpeed 복원, 아이템 소모 없음 |
| 캔버스 60초 타임아웃 | 자동 닫기, WalkSpeed 복원, 아이템 소모 없음 |
| 캔버스 열린 상태로 스테이지 종료 | 캔버스 강제 닫기, WalkSpeed 복원 |
| 완료 후 서버 검증 실패 | 스프레이 캔 환불 |
| 빈 캔버스 완료 시도 | 완료 버튼 비활성 (제출 불가) |
| 스테이지 종료 후 이벤트 도착 | mazeFolder nil 체크 후 거부 |
| 두 플레이어가 같은 벽에 동시 그리기 | SurfaceGui 각각 생성 (겹침 허용) |

---

## 범위 밖 (이번 구현 제외)

- 지우개 기능
- 낙서 겹치기 제한
- 욕설/부적절 콘텐츠 필터
- 낙서 신고 기능
- 멀티 레벨 실행취소
