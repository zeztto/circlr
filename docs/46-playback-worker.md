# 재생 장치 작업의 직렬 소유

2026-09-09, 기준 `0b92af8`, `codex/daw-integration`. development-lead → native Swift utility → read-only review → QA. 사용자 요청으로 독립 검토 agent를 다시 요청했으나 실제 도구가 `agent thread limit reached`를 반환했다. 독립 리뷰로 보고하지 않는다.

## 근거와 계약

기본 Scarlett 6i6 USB는 44.1 kHz, 512 frames이며 별도 CoreAudio 속성 조회는 약 45 ms에 완료됐다. 음악 없는 별도 AVAudioEngine의 `mainMixerNode`도 HAL의 IOProc 생성/stream usage IPC에서 대기했다. 이 관찰은 프로젝트 렌더와 무관한 시스템 출력 획득 지연을 재현하며 특정 드라이버의 결함을 확정하지 않는다. 원본 로그와 stack은 `qa/generated/output-lifecycle/`에 보존한다. 시스템 장치·다른 앱·마이크 설정은 변경하지 않는다.

`Playback.swift`의 초기 연결은 background지만 이후 engine start/stop, player play/stop, clock 조회와 최종 해제는 MainActor에 남아 있다. 이 범위를 하나의 직렬 worker로 옮긴다. UI는 작은 값 snapshot만 읽는다. 같은 engine은 재사용하고 정리 중 재생 요청은 명시적으로 거절한다. 장치 시작은 음소거 상태로 실행하며 늦은 취소를 확인하기 전 음량을 열지 않는다. STOP은 UI 요청을 즉시 취소하고 물리적 정리 수명은 별도로 표시한다. 장치 응답을 기다리는 동안 같은 worker를 새로 생성하지 않는다.

## 파일과 검증

- Native Swift utility: `Sources/CirclrAudio/PlaybackTransport.swift`, `Playback.swift`, `PlaybackOutputConnection.swift`; App `PlaybackOutputStatus.swift`. 기존 PCM·renderer·녹음 schema·MCP 쓰기 계약은 유지한다. snapshot의 transport 상태만 additive다.
- Native 후속: 첫 후보에서 숫자 Return 확정 뒤 first responder가 창에 남아 Space가 소실됐다. `CommittedNumberField.swift`의 명시적 Return/Esc 종료만 주 창의 `focusCanvas`로 복귀한다. Tab 순서·별도 창·텍스트 입력은 건드리지 않으며 실제 재생 요청/취소로 확인한다.
- Tests: 새 `PlaybackTransportTests.swift`, 기존 `AudioTests.swift`의 공개 engine 직접 접근을 상태 조회로 대체. 초기 연결·느린 start/stop/clock·취소·실패·자연 종료·세대 보호를 제어된 backend에서 검사한다. 단위 검사는 물리 입력/출력을 열지 않는다.
- `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.
- 별도 build 32 QA 앱/복제된 authored fixture에서 시작→대기/취소→늦은 완료, 가능한 실제 재생→Space 정지, 숫자 편집/Undo와 저장을 확인한다. 소스/패키지 UUID·서명·kit와 원본 보존을 확인한다.
- README/CHANGELOG/roadmap·QA 기록 갱신 후 같은 private branch에 source checkpoint를 commit/push한다. 사용 앱이 현재 실행 중이므로 이번에는 강제 종료·교체하지 않는다. 전체 출고 조건은 기능별 증거로 재정리하며 이번 검사로 입력·VoiceOver까지 검증했다고 주장하지 않는다.

## 결과

Swift 293개·Python 26개와 최종 release build, 작은 창의 실제 숫자/Space/콘솔·Undo·저장 복원·패키지 검증을 마쳤다. 최종 UUID는 `BC4A9560-75E4-3091-9FA3-8473C5BDC735`다. 장치 획득은 마지막 331초 표본에도 대기 중이므로 정상 재생과 청감을 완료했다고 주장하지 않는다. [상세 결과와 남은 조건](../qa/playback-worker-review.md).
