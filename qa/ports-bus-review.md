# 독립 오디오 bus · B 단계 검증

2026-09-08, `codex/eight-direction-ports`, 시작 commit `056502b`. macOS 26.5.1 Apple Silicon에서 소스와 offline PCM을 검증했다. 이 worktree는 0.19 기반이며 녹음 0.20 브랜치와 아직 통합하지 않았다.

## 구현 계약과 결과

`MusicCircleContent.router(AudioRouter)`는 각각 스테레오인 입력 두 개와 출력 두 개를 가진다. stable ID는 `in.audio.bus1`, `in.audio.bus2`, `out.audio.bus1`, `out.audio.bus2`다. 기본 matrix는 1→1, 2→2이며 최대 네 개의 명시적 경로를 가질 수 있다. 경로 gain은 0…4이고, 생략된 경로와 연결되지 않은 입력은 무음이다. bus는 좌·우 채널과 다른 개념이다.

`MusicConnection.fromPortID`/`toPortID`는 선택적이다. 기존 JSON의 생략된 단일 포트는 종전 main/sidechain으로 해석하고 기존 데이터에 필드를 추가하지 않는다. router에서 포트를 생략하면 임의로 첫 bus를 사용하지 않고 거절한다. compiler가 실제 존재하는 방향·역할·신호·gain과 비순환 그래프를 확인한다. router가 담긴 문서는 이를 모르는 구버전에서 enum decoding이 실패하므로 신호를 바꿔 열거나 저장하지 않는다.

renderer의 buffer와 소비자 수는 `(nodeID, portID)`를 key로 사용한다. 각 입력의 fan-in, matrix gain, 각 출력의 node gain·automation, outgoing edge gain 순서로 처리한다. fan-out/sidechain의 마지막 소비자가 끝날 때 해당 출력만 해제한다. 기존 node 시각화 observer에는 router 출력의 합계를 전달하지만 그 PCM을 신호 routing에 사용하지 않는다. **연결선별 bus envelope 표시는 후속 UI 단계**다.

Core의 `insertEffect`는 출력 하나만 바꾸고 다른 bus와 sidechain edge를 보존한다. 기존 앱·agent 효과 삽입도 이 명령을 사용한다. 현재 UI/MCP에 bus 선택이 없으므로 다중 출력 노드의 모호한 요청은 오류로 끝나며 project를 변경하지 않는다. router 생성·matrix 편집 기능은 아직 제품 UI에 노출하지 않았다.

## 검증 근거

- Core 5개: 명시적 bus별 연결·중복 no-op·모호한 요청 atomic 거절, 잘못된 route/port/gain/sidechain/순환 거절, compiler/catalog/scene/JSON의 port ID 보존과 legacy JSON, 선택 bus의 효과 삽입, 8방향×4포트=32개 geometry/hit 구분.
- Audio 8개: 서로 다른 48 kHz stereo 48,000-frame 입력의 양 채널 PCM 분리, 시각화 observer on/off PCM 일치, 교차 matrix·fan-in gain·2×2 matrix, main/sidechain 분리, gain/automation/mute/누락 입력, 두 트랙 바운스·embedded 저장/재열기·원본 외부 파일 삭제 후 복원, 두 MIDI lane 합류→악기→bus, 13개 출력 분기, 80개 라우터 chain. 마지막 두 항목은 하나씩의 검사이며 matrix의 여러 시나리오는 한 검사에 포함된다.
- 바운스 직후 양 채널 차이는 24-bit **1 LSB 이하**, 원본 routing 복원 후 PCM은 정확히 동일하다. 저장된 `BounceSource.replacedInputs`가 원래 명시적 port ID를 유지한다.
- 전체 offline Swift **172개**, 실패 0개, 17.352초. A 기준 159개 + B 신규 13개다. `testArrangementRenderExportAndPlayback`는 하드웨어 의존으로 제외했다. 녹음 branch의 검사 수와 합산하지 않는다.
- 기존 Python MCP 13개와 agent kit 9개도 통과했다. 외부 MCP transport/schema와 배포된 kit는 변경하지 않았다.
- release build **42.80초**, warning/error 없이 완료. binary UUID **D1F50B71-8671-3CDF-A4A3-AC4AF92DEE0D**. 앱으로 패키징하거나 실행하지 않았다.

Core/API 입력 및 renderer 수명 검토는 실제 agent 슬롯 부족으로 구현자와 같은 에이전트가 역할을 전환해 수행했다. 독립 리뷰를 받았다고 주장하지 않는다. 허용 port ID의 유한 집합, route 4개와 중복 제한, graph 2,048 nodes/8,192 edges, gain 유한값과 0…4 범위, 원래 caller의 project/revision·atomic transaction을 확인했다. 새 외부 API·경로 입력·권한·shell 실행은 추가하지 않았다.

초기 build는 `StudioNavigation` 및 `AlbumWorkspace`의 누락된 router enum case로 실패했다. 모두 연결한 뒤 대상 21개, 추가 MIDI/13분기까지 포함한 전체 172개를 통과했다. 실패 build를 테스트 통과 근거로 계산하지 않는다.

## 남은 범위

[C/D/E 실행 계획](../docs/35-port-foundation-plan.md)의 native 8방향 조작, 각 출력 bus 선택과 matrix 편집, layout 전용 App Undo, 포트별 시각화, MCP 명시적 port 명령, 그룹 노출 binding, 녹음 branch 통합과 실제 앱 검증이 남아 있다. Audio Unit 플러그인의 다중 bus 호스팅이나 연속 실시간 처리 엔진을 구현했다는 의미가 아니다. 사용 앱과 전용 녹음 QA 프로세스를 교체하거나 실제 입력 녹음을 시작하지 않았다.

## 재현

```sh
swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback
swift build -c release --product circlr --scratch-path .build/ports-release
```

로컬 로그는 `qa/generated/ports-foundation/ports-b-{initial-build,core-build,targeted-tests,full-tests,release-build}.log`에 있다. 이 디렉터리와 임시 오디오 fixture는 Git 업로드에서 제외한다. 검증된 source checkpoint만 기존 승인 범위의 private feature branch에 보관하며 main 통합·사용 앱 교체는 후속 검증 뒤 진행한다.
