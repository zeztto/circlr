# build 29 숫자 입력 검증

2026-09-09. `codex/daw-integration`, 기준 `8fce062`. 전체 goal은 progress이며 사용자 앱 출고 gate는 그대로다. 사용자가 요청한 UX 서브 에이전트 생성은 도구의 `agent thread limit reached`로 거절되어 같은 실행자가 UX→Swift utility→읽기 전용 코드/입력 검토→QA를 순차 수행했다. 독립 agent 검토로 보고하지 않는다.

## 대상과 자동 검사

- 사용자 앱 `dist/써클러.app` 0.19.0 build 21은 교체하지 않았다. `.build/integration-worktree`의 소스와 격리 QA 앱만 사용했다. 실제 마이크·출력 재생은 시작하지 않았다.
- 최종 앱: `qa/generated/number-editing/final/써클러 통합 검증.app`, 0.20.0 build 29, UUID `8342BE3E-1C8D-3F63-AC77-CB5152D5ABAE`.
- QA 프로젝트: `~/Library/Application Support/circlr-integration-qa/fixtures/number-editing.circlr`, ID `422D68D8-8D07-577C-A021-F62F2DA9B82A`. authored `studio.circlr`의 3트랙·2 tone 자산만 복사했다. 원본 manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`를 보존했다.
- Swift `--skip testArrangementRenderExportAndPlayback`: 265개, 실패 0, 최종 live-getter 소스 검사 22.668초. 그 뒤 `isEnabled` 전달 1항목을 추가했고 final release·Native에서 검증했다. 첫 테스트 후보의 지수 표기 대소문자 assertion은 수치 동등성 검사로 수정했다.
- Python `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`: 26개 통과. 최종 release 23.79초. Core 6개 추가 테스트는 draft/정밀도/정수·비정상 수치/값·대상 충돌/Tab·첫 글자 이벤트 순서를 다룬다.
- `python3 qa/check-number-evidence.py`: 실제 기록의 음악 값·revision·복원·서명·키트 hash를 재검사한다. 소스/최종 앱의 file-backed Mach-O 37개 section 일치, 키트 25개 파일 hash 일치.

## Native 시나리오

화면은 최소 폭 1024, 캔버스 1024×673이며 콘솔 열림/닫힘을 확인했다. 키보드와 실제 AX/스크린샷, MCP snapshot과 저장된 manifest를 함께 비교했다. 아래 근거는 `qa/generated/number-editing/`에 보존한다.

| 시나리오 | 관찰한 결과 | 근거 |
|---|---|---|
| 타이핑과 음악 분리 | 최종 신스 1500 입력 중 cutoff 1200·revision 62 유지 | `final-synth-typed.json` |
| 빠른 신스 Tab | 1200 Hz→12 cent 두 확정으로 r60→62 | `final-synth-tab.json`, AX |
| 빠른 오디오 Tab | 12.25초→gain 0.8 두 확정으로 r70→72 | `final-audio-tab.json`, AX |
| MIDI 세 필드 | 키보드로 기존 73번 노트 선택, 2.25박→0.75박→96 입력으로 r48→51 | `final-midi-tab.json`, AX |
| MIDI 정수/Undo | 96.5 거절, Esc 후 한 Undo로 velocity 74 복원, 두 Undo로 시간 복원 r54 | `final-midi-invalid-ax.txt`, `final-midi-undo-velocity.json` |
| 반복 횟수 | 2.5 거절, 2 확정, 증가 버튼→Undo는 2, 다음 Undo는 1 | `final-repeat*.json`, `final-count-invalid-ax.txt` |
| 글로벌 템포 | Return으로 draft 128 확정 후 음악은 120 유지. 앨범에 적용 시 128, Undo는 120 | `final-tempo-*.json` |
| 외부 편집 충돌 | 1500 dirty 중 MCP가 트랙 gain을 0.65로 변경. Return 거절·cutoff 1200 유지, r63 추가 변경 없음 | `final-stale.json`, AX |
| 대상 변경 | 1700 dirty 상태에서 MCP로 출력 2→출력 1 이동. 두 트랙 값 모두 기존 값 유지 | `final-target-changed.json` |
| 정밀도 | 900.1234567890123을 900.1234568로 표시한 뒤 수정 없이 Return. 저장된 원값·r67 그대로 | `final-precision-before.json`, `final-precision-after.json` |
| 서클 출력 | MIDI 트랙 mix 서클 gain 0.85 한 번 적용 후 Undo | `final-output.json`, `final-output-restored.json` |
| 복원·재열기 | global/tracks/sections/arrangements/assets 전부 최초 상태와 동일. r74 저장·open 완료·dirty false | `final-restored.json`, `final-reopened.json` |
| 화면 | 최종 오디오 콘솔 닫힘과 기존 최소 폭 신스/오디오 콘솔 열림. 오류 아이콘·테두리·AX 설명 확인 | `final-console-closed.png`, `native-audio.png`, `synth-invalid.png` |

## QA에서 발견하고 수정한 결함

1. 첫 SwiftUI 후보에서 길이→볼륨으로 빠르게 Tab 입력하면 `0.8`이 `1.8`로, 다음 검사는 `0.8.6`으로 바뀌었다. focus 이벤트보다 첫 텍스트 이벤트가 먼저 처리되는 경로를 재현했다. `audio-tab.json`, `audio-fast-tab-failed.json`은 실패 후보이며 성공 근거에 포함하지 않는다.
2. 첫 글자 시점에 draft 기준을 확보한 후보는 글자를 보존했지만, 앞 필드 확정의 revision을 정상 후속 입력과 구분하지 못했다. `focus-fast-tab-stale.json`.
3. AppKit 동기 확정으로 오디오 연속 입력은 해결됐으나 captured synth Binding의 오래된 snapshot이 신스 Tab을 거절했다. `native-synth-tab-stale.json`. 최종 코드는 현재 모델 getter와 입력 전 최신 identity를 함께 사용한다. dirty 입력이 생긴 뒤에는 baseline을 재설정하지 않는다.
4. 같은 검토에서 오디오 fade getter와 automation point setter도 현재 값을 읽도록 맞췄다. automation의 다음 숫자를 바꿀 때 이전 point 전체를 덮어쓰는 형태를 제거했다. Native 컨트롤에 SwiftUI `isEnabled`를 전달했다.

각 후보 앱과 로그를 덮어쓰지 않았으며 다음 후보 시작 전에 Undo로 음악을 복원했다. 최종 후보의 source/package 비교를 별도로 수행했다.

## 남은 범위

- 실제 VoiceOver 발화, IME·서로 다른 locale/접근성 설정, 녹음 중 입력·비활성화, 전역 signal/전환/legacy/automation의 위젯별 전체 Native 조합은 이번 성공 범위에 포함하지 않는다.
- MIDI 일괄 편집·라우터·효과 slider처럼 별도 전용 입력은 기존 계약을 유지한다. 이번 변경은 공통 `ValueField`/`CompactNumber`/`CountControl` 소비자다.
- 글로벌/섹션 설정은 숫자 Return/Tab 확정 후 기존 전체 적용 버튼을 사용하는 draft다. 전체 설정 draft와 적용 버튼의 외부 변경 수명/원자성은 별도 후속 범위다.
- collapsed group 안의 router ID 직접 focus는 기존 도구에서 '서클을 찾을 수 없습니다'로 거절됐다. 이번 출력 검사는 탐색 가능한 MIDI mix 서클에서 수행했다. 새 음악 변경은 발생하지 않았다.
- 실제 마이크·오디오 장치·MP4·연속 엔진과 E 출고 gate는 완료로 올리지 않는다. 검증 앱과 소스 push는 사용자 설치 앱 교체와 별개다.
