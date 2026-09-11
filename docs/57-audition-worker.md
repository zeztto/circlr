# build 43 · 악기 미리 듣기 수명과 UI 응답성

## 계획

`session-bootstrap-v1`: owner=development-lead; implementation=native Swift utility; branch=codex/daw-integration; baseline=1ca6cc3; delegation=none (실제 단일 슬롯, 앞선 spawn 거절 확인).

현재 `AppStore.audition`은 background에서 생성한 engine을 UI actor로 가져온다. sampler note의 PCM 생성과 player 호출, 일부 취소 후 stop은 MainActor에 남는다. 초기화 뒤 note-on/off Task를 순서대로 재생해 준비 중 이미 놓은 건반이 늦게 울릴 수 있다. 이전 초기화 Task에 후속 Task가 계속 연결되며 준비/취소 상태가 표시되지 않는다.

성공 조건:

- MainActor는 악기 snapshot과 현재 누른 노트만 전달한다. 악기 생성·sample 렌더·note·stop·release는 UI 밖의 단일 소유 수명에서 수행한다.
- 한 번에 하나의 준비/정리만 수행한다. 취소/트랙 변경 중 준비된 이전 backend는 note를 보내지 않고 정리한다. 장치가 막혀 있어도 새 backend를 중복 생성하지 않는다.
- 준비 중 놓은 노트는 재생하지 않는다. 같은 pitch 재누르기를 구분하며 오래된 release가 새 note를 멈추지 않게 한다. 샘플 준비 뒤 취소 검사를 player 시작 직전에 한다.
- 준비/정리/실패 상태와 Space 취소를 기존 transport 상태 줄 및 MCP snapshot에 표시한다. 새 창/패널은 추가하지 않는다.
- 제어된 backend에서 block/failure/cancel/release/retrigger/target switch/timeout/cleanup을 검사한다. 정확한 authored QA 사본에서 미리 듣기 준비·취소 중 UI 편집/Undo·저장과 표시를 검증한다. 실제 정상 소리와 HAL 지연 해결은 별도 관찰 근거가 있어야 인정한다.

## 소유 파일과 실행

Audio: `AuditionTransport.swift`, `ProductionInstrument.swift`; App: `AppStore.swift`, `AuditionWorkspace.swift`, `PlaybackOutputStatus.swift`, `RootView.swift`, `AgentWorkspace.swift`; Tests: `AuditionTransportTests.swift`. README/CHANGELOG/roadmap 및 QA helper/기록은 후속 문서 slice다. 파일 import·MIDI 저장·DSP 알고리즘·녹음 schema는 유지한다.

UX 계약 → Swift 구현 → 읽기 전용 code/security review → QA 순차 역할 전환. Swift 전체 검사(기존 실제 출력 의존 1개 제외), Python MCP/kit, release, 별도 QA 앱의 상태/키보드/Undo/저장 복원과 source/package 검증 후 승인된 private branch에 source/docs/tests만 commit/push한다. 마이크·시스템 장치 설정·다른 실행 앱은 변경하지 않는다.

## 결과와 후속 경계

Swift 345개·Python 26개와 최종 release/패키지 검사 통과. 실제 authored sampler에서는 HAL IOProc 대기가 worker에 남고 UI의 노트/숫자 편집·Space 취소·Undo/저장/재열기가 작동했다. 준비 요청은 1회이며 native 경과 시간의 초기화 문제를 수정했다. 소리 출력이 준비된 상황의 실제 note/voice/플러그인 회귀는 남아 있다. [세부 근거와 미검증 범위](../qa/audition-worker-review.md).
