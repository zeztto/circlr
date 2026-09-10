# 에이전트 공유 오디오 편집과 오토메이션 적용 범위

상태: build125 Core/MCP 구현·관련 테스트·Release와 아래 native 명령/UI 검증을 마쳤다. 저장/재열기·production 서명/UUID·독립14개 snapshot 감사도 통과했다. GUI와 MCP의 범위 차이를 줄이는 계약이며 모든 오디오 편집·실제 오디오·전체 제작 흐름의 완료를 의미하지 않는다.

## 공유 오디오 주소

`circlr_snapshot`의 patterns에서 실제 patternID·trackID·clipID를 조회하고 최신 projectID/expectedRevision과 함께 `circlr_apply`로 보낸다. 새 `edit_shared_audio`는 공유 pattern.audio를 편집한다. 어느 use의 서클을 선택했는지가 적용 범위를 제한하지 않으며 해당 패턴을 소비하는 모든 곳에 영향을 준다. 출력 연결 대상 대신 패턴의 소유 trackID를 사용한다.

| edit | 필드·단위 | 의미 |
|---|---|---|
| split | sourceOffset, 초 | 선택 clip 구간 시작부터의 원본 시간 오프셋에서 분할 |
| duplicate | beatOffset, 선택적 로컬4분음표 박 | 지정한 상대 위치에 복제. 생략 시 선택 클립 길이만큼 뒤에 배치하며 소비 템포 계약에 따라 거절 가능 |
| fade | fadeIn·fadeOut, 원본 초 | 선택 clip의 fade 설정 |
| delete | 추가 필드 없음 | 선택 공유 clip 삭제. 자산 삭제와 구분 |

다음 ID는 설명용 자리표시자이며 실제 snapshot의 값으로 바꿔야 한다.

```json
{
  "projectID": "PROJECT_ID",
  "expectedRevision": 12,
  "operations": [{
    "kind": "edit_shared_audio",
    "patternID": "PATTERN_ID",
    "trackID": "OWNER_TRACK_ID",
    "clipID": "CLIP_ID",
    "edit": "fade",
    "fadeIn": 0.01,
    "fadeOut": 0.2
  }]
}
```

일반 `edit_audio`의 useID/nodeID 주소와 공유 주소를 섞지 않는다. 새 공유 명령에서 arrangementID·compositionID·useID·laneID·nodeID는 거절하고 patternID를 다른 명령에 사용하는 것도 거절한다. 분할·복제 뒤에는 snapshot.patterns를 다시 읽어 실제 새 clip ID를 확인한다. 이 범위에 trim·replace를 추가했다고 해석하지 않는다.

## 오토메이션 원본·변형

`set_automation`에 선택적 boolean `original`을 추가한다. 생략 또는false는 해당 use의 변형을, true는 공유 원본을 편집한다. 원본 편집이 다른 use의 명시적 override까지 덮어쓰는 동작은 아니다. 대상 useID·nodeID와 기존 gain/pan·automationPoints·enabled 계약을 유지한다.

```json
{
  "projectID": "PROJECT_ID",
  "expectedRevision": 13,
  "operations": [{
    "kind": "set_automation",
    "useID": "USE_ID",
    "nodeID": "NODE_ID",
    "parameter": "gain",
    "original": true,
    "automationPoints": [
      {"beat": 0, "value": 0.5, "shape": "linear"},
      {"beat": 4, "value": 1, "shape": "hold"}
    ]
  }]
}
```

beat는 로컬4분음표 박이고 gain은 node gain에 곱하는0–4 값이다. 이 예시는 곡선 전체 교체이며 기존 점 유지가 필요하면 읽은 ID와 점을 포함한다. original은 다른 종류의 명령에서 거절한다. 문자열/숫자를 boolean으로 해석하지 않는다. 명시적 null은 MCP schema에서 거절한다. 직접 Swift decoding의 optional null은 nil로 처리되므로 이 경로까지 null 거절이 같다고 주장하지 않는다.

## 검증과 남은 조건

[AgentProtocol](../Sources/CirclrCore/AgentProtocol.swift), [공유 오디오 Core](../Sources/CirclrCore/SharedRhythmAudioEditing.swift), [AutomationEditing](../Sources/CirclrCore/Automation.swift), [MCP schema](../mcp/server.py)를 같은 주소·범위 계약으로 연결한다. 검증은 다음 조건을 구분한다.

- 공유 clip의 split/duplicate/fade/delete가 올바른 pattern·owner에만 적용되고 다른 pattern·일반 lane·원본 자산을 보존한다.
- original 생략/false의 use 변형과 true의 공유 원본이 구별되고 기존 use override를 보존한다.
- 혼합 주소·다른 명령의 original/patternID·잘못된 boolean·stale revision·유효하지 않은 소유 관계는 atomic하게 거절한다.
- MCP 전달과 GUI/Core의 결과·Undo·저장/재열기를 실제 데이터로 대조한다. 노출된 schema만으로 지원 앱과의 실행 성공을 판단하지 않는다.
- 실제 native·오프라인 PCM·물리 입출력은 수행 범위를 따로 기록한다. 소스/테스트 준비만으로 청취나 모든 DAW 기능을 완료했다고 주장하지 않는다.

## 현재 검증 결과

Core 관련30개 테스트는 실패0·0.036초(표시 범위0.038초), 해당 compile은4.66초다. MCP27개는0.118초에 통과했고 Release는73.17초에 성공했다. 실제 앱에 MCP로 공유 오디오 split/duplicate/fade/delete를 각각 적용하고 Undo했다. 실패 batch와 stale revision의 거절에서 음악 보존을 확인했다.

원본 A의 gain0.5와 B override0.25를 한 batch로 적용하여revision37을 만들었다. native JPEG/AX에서 A −6.02dB·B −12.04dB를 확인했다. Undo 후38은 기준 음악과 정확히 일치했다. 재적용한39의 saved=reopened=disk도 정확히 일치하며 재열기 JPEG/AX에서 B −12.04dB를 유지했다. QA 준비/검증 스크립트2개를 마련했고 noIO·자산4개 범위에서 진행한다. 실제 소리·PCM 결과를 이 native 값 표시로 대체하지 않는다.

독립14개 snapshot 감사는 네 공유 편집 외 음악 불변·각 Undo의 baseline 일치·automation 원본0.5/B override0.25만 변경·한 번 Undo·거절 후 음악 불변을 확인하여 PASS했다. 자산4개 SHA·noIO·helper5개·현재 MCP manifest도 확인했다. production strict 서명과 UUID `471A19C2-D44B-33A8-A894-0CED8ED0C83D` 검증을 통과했다. QA 앱을 종료하고 원본 사용자PID86114를 보존했다. 공유 오디오 trim/replace와 전체 automation 확장은 남아 있으며 [현행 개발 계획](138-current-development-plan.md)의 오디오·오토메이션·편곡 대안 작업을 계속한다.
