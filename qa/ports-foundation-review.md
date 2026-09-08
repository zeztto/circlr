# 포트 기반 · Core 검증

2026-09-08, macOS 26.5.1 / Apple Silicon. 기준 commit `040bb2b`의 독립 `codex/eight-direction-ports` worktree다. 녹음 0.20의 미커밋 변경과 전용 QA 앱·진행 중인 open job을 보존했다. 이 결과는 **포트 기반 A 단계**이며 8방향 native UI나 실제 독립 다중 bus 구현의 완료가 아니다.

## 구현과 검사

- 실제 기존 MIDI/audio/main/sidechain/송폼 포트의 고정 ID·IN/OUT·신호·수용 정책을 제공한다. 입력 없는 source, 출력 없는 master, sidechain이 없는 effect에 해당 포트를 만들지 않는다. IN에서 시작한 연결 요청도 OUT→IN으로 정규화한다. signal 불일치·존재하지 않는 bus·같은 포트·다른 use의 연결은 거부한다. cycle·실제 route 적용은 기존 graph 명령이 계속 담당한다.
- 포트 배치를 원래 logical from/to 주소와 edge ID에 묶었다. 같은 source section을 재사용해 edge ID가 같아도 use/arrangement가 다르면 배치는 독립적이다. 그룹 접기 시 표시 endpoint만 바꾸고 logical connection과 배치를 유지한다. 접힌 그룹에 가짜 신호 포트를 만들지 않는다.
- project의 선택적 `portLayout`이 없으면 E OUT/W IN을 사용한다. layout transaction은 projectID/musicRevision/layoutRevision을 검사하고 layoutRevision만 증가시킨다. no-op는 변경하지 않는다. 한 batch의 누락 대상·중복·stale 요청은 모두 무변경이다.
- layout Undo/Redo Core 경로는 현재 음악을 덮어쓰지 않고 배치를 새 revision으로 복원한다. 새 MIDI 노트와 musicRevision을 변경한 뒤 이전 배치만 복원하는 검사를 통과했다. 이는 앱 전체 Undo 기록에 연결하기 전의 Core 검사다.
- 화면 좌표 기반 geometry에서 8방향 각각 main IN/sidechain IN/OUT의 **24개 handle**과 hit를 구분했다. 보이지 않는 handle 목록은 hit를 만들지 않는다. 64개 시작/끝 방향 조합의 cubic curve가 각 끝점의 외곽 법선과 정확한 시작/끝 위치를 유지한다. 실제 native drawing·VoiceOver 검사는 후속이다.
- 한 logical audio OUT의 **13개 분기**가 각 endpoint 배치를 유지한다. 방향은 8개지만 연결 수를 8개로 제한하지 않는다. 원래 모든 음악 필드·edge·gain은 그대로다.
- main/sidechain을 포함한 실제 renderer fixture에서 모든 연결을 8방향으로 옮긴 결과가 양 채널 PCM과 **정확히 동일**했다. `.circlr`에 embedded media와 함께 저장·재열기한 결과도 일치했다. 48 kHz, stereo 48,000 frames이며 실제 음악 청취·오디오 장치 재생 결과로 주장하지 않는다.

최종 오프라인 Swift **159개 통과**: 0.19 기준 148개 + 신규 Core 10개/Audio 1개. 하드웨어 테스트 `testArrangementRenderExportAndPlayback` 하나는 제외했다. 녹음 0.20 브랜치의 161개와 서로 다른 소스 기준이므로 합산하지 않는다. MCP·kit·Audio DSP 소스는 바꾸지 않았으며 Python 검사는 이번 단계에 반복하지 않았다.

최종 release build는 warning 없이 통과했다. 실행 파일 UUID `1185AFA1-CCF9-3C16-9652-9C789D9DB693`. 이 binary를 사용 앱으로 패키징하거나 녹음 QA 앱 대신 실행하지 않았다.

## 발견 후 수정과 검토

중복 배치 JSON을 scene dictionary에 넣으면 Swift가 중단되는 회귀 검사를 먼저 실패시켰다. 저장 경계뿐 아니라 `HierarchySceneBuilder.build` 진입에서도 validate하여 오류로 거부하도록 수정했고 같은 검사와 전체 회귀가 통과했다. 초기 build의 일치하는 테스트 0개는 컴파일 확인일 뿐 테스트 통과로 계산하지 않았다.

매 프레임 호출되는 `acceptsInput`/`providesOutput`은 descriptor 배열을 매번 만들지 않고 기존처럼 content/kind에서 직접 계산한다. 실제 descriptors와 boolean의 일치도 검사했다. 수치 성능 향상을 측정했다는 의미는 아니다.

검토한 입력 경계: octant enum 0…7, layout 항목 16,384개, batch 1…128개, ID 길이 1…1,024 UTF-8 bytes, 중복 ID와 유효한 revision, 유한 화면 좌표/반경. 사라진 edge의 이전 배치는 Undo를 위해 저장될 수 있지만 새 이동 명령은 현재 연결을 요구한다. 새 네트워크·shell·인증정보·파일 경로 인자는 없다. 독립 에이전트는 실행 한도로 사용할 수 없어 구현자와 같은 에이전트가 읽기 전용 코드/입력 검토를 수행했다.

## 다음 단계

독립 다중 bus의 실제 port별 buffer, App의 8방향 새 연결·재연결·위치 이동·명령별 Undo·포트 선택 UI, MCP의 명시적 port/layout revision 계약, 그룹의 노출 binding과 native 작은 창/키보드/VoiceOver/기존 v4 PCM 검증이 남아 있다. [전체 계약](../docs/22-eight-direction-ports.md)과 [실행 계획](../docs/35-port-foundation-plan.md)을 유지한다.

현재 제품의 좌우 포트 조작을 완료된 8방향 UI로 표시하지 않는다. 사용 앱의 버전·아이콘·kit와 녹음 QA 프로세스를 교체하지 않았다. 검증된 Core 단계만 private feature branch에 보관하고 main 통합은 후속 단계에서 검토한다.

## 재현

```sh
./scripts/swift-local.sh test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback
./scripts/swift-local.sh build -c release --product circlr --scratch-path .build/ports-release
```

로컬 증거는 이 worktree의 `qa/generated/ports-foundation/`이다. `ports-core-red.log`, `ports-targeted-tests.log`, `ports-full-tests.log`, `ports-review-tests.log`, `ports-review-build.log`, `ports-final-tests.log`에 실패·수정·최종 결과를 분리했다. 파일/음원/장치/화면 산출물은 commit에서 제외한다.
