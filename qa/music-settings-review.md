# build 65 음악 설정 가시성 검증

2026-09-09. `codex/daw-integration`, baseline `5705a38`. 실제 1 slot에 따라 UX → native utility → read-only code review → QA를 순차 수행했다. 독립 에이전트 검토는 아니다. 전체 DAW/UX 목표는 계속 진행 중이다.

## 최종 산출물과 검사

- 앱: `qa/generated/music-settings/refined/써클러 통합 검증.app`, 0.20.0 build65, UUID `B621DCAC-E136-3AFD-88A6-89B842E669B5`. 모든 owned QA 프로세스를 종료했다.
- 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/music-settings.circlr`, ID `3950E095-CDF9-5AE9-AD06-8009326A4C93`. authored 3트랙·2 tone 자산에 두 사용과 직접 작성한 4박 MIDI 패턴을 넣었다. 상속100/앨범120/보관132 BPM을 구분했다.
- Swift463개, 실패0, 26.161초. Python28개, 실패0, 0.213초. 기존 Core의 출처·보관값·원본/override·비활성 주소·실패 원자성 테스트를 포함한다. 이후 UI 키보드 보완은 release 및 native로 재검증했다. DSP/schema/Core 변경은 없다.
- release: initial39.83초 → final37.07초 → refined36.41초. 각 후보 앱과 소스 hash를 보존했다. 마지막 후보만 최종 키보드 acceptance 근거다.
- `python3 qa/check-music-settings-evidence.py`: 23상태·최종21화면, 전체 음악 데이터 비교, 최종 소스4개 hash, Mach-O37개 section, Codex kit25개 hash, codesign 통과. 원본 manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 및 자산 checksum 보존.
- root `d88ea5d`, ports `1d304eb`, 사용자 앱0.19.0 build21을 현 상태에서 확인했다. 물리 재생·audition 시도0, 녹음 시작0.

## 실제 동작

| 검사 | 결과·근거 |
|---|---|
| 작은 창 | 폭1024에서 섹션 마디·반복·템포·박자·스케일·리듬이 콘솔과 함께 보인다. `rhythm-local.jpg`, `settings-return.jpg` |
| 직접 출처 | 상속100→앨범120→개별132. 보관값을 help/AX에 표시한다. `tempo-album`, `tempo-local`, `source-noop`에서 같은 출처 재선택은 r16 그대로다 |
| 최종 키보드 | BPM에서 Shift-Tab 두 번으로 앨범, Return 선택 r17, Tab/Return으로 개별 r18, Tab→136입력→Tab으로 확정 r19. 현재 섹션 유지, 다음 박자 출처에 초점. `refined-keyboard-album`, `tempo-committed-tab` |
| 길이·반복 | 상단 직접 입력 12마디·2회 r21. `section-duration` |
| 리듬·이력 | 개별 보관 패턴 선택 r22, Undo r23, 실제 ⇧⌘Z Redo r24. 패턴/노트 자체 보존. `rhythm-local`, `rhythm-undone`, `settings-return` |
| 연결 왕복 | 한 줄 `섹션 순서·전환` 진입·검색 Tab→결과 목록·편집 복귀. 키보드 루프 회귀 없음. r24 음악 유지. `connections-open`, `connections-tab`, `settings-return` |
| 전체 복원 | 항목별 Undo 후 기본값 전환 r29에서 최초 음악 전체와 일치. 콘솔 접으면 강세·섹션 추가 작업까지 한 화면. `section-restored`, `section-console-closed.jpg` |
| MIDI 타이밍 | 9.5박→24박→2회 연속 Tab, r32. 시작은 내부8.5이며 MIDI 노트·다른 서클·공유 원본 보존. `midi-timing` |
| 앨범·곡 | 앨범126 BPM r33, Undo 후 곡 반복3 r38. 각각 단일 설정만 변경. `album-tempo`, `composition-repeat` |
| 저장·재열기 | 모든 음악 복원 r39, MIDI 서클과 설정 화면 재열기에서 확인. 이후 휠 줌·스크롤바로 보기만 변경하고 저장, 음악 전체 동일. `saved-settings`, `reopened-music`, `reopened-after-view` |
| 아래 설정 접근 | 휠은 캔버스 줌이며 스크롤바로 강세·음소거·패턴 만들기에 접근. `advanced-scrollbar.jpg` |

## 발견·수정 및 검증 제한

첫 후보의 SwiftUI 출처 버튼은 macOS 기본 Tab 이동에서 빠졌다. native 버튼으로 바꾼 두 번째 후보는 초점을 받을 수 있었지만 Tab이 canvas의 다른 섹션 선택으로 전달됐다. `PortButtonControl`에 navigation이 없는 경우의 next/previous key-view 이동을 추가한 최종 후보에서 현재 편집 대상 보존·Tab/Shift-Tab/Return을 확인했다. 기존 navigation이 있는 연결 버튼 동작은 유지한다. 소스 snapshot/apply의 project·generation·대상·원본 guard와 기존 숫자 편집 identity를 보존했다.

CUA의 이전 앱을 캡처한 helper가 닫힌 이전 후보를 다시 열었던 시도가 있었다. `final-keyboard-local`·`final-section-settings`는 빈 이전 앱의 실패 관측이며 통과 근거에서 제외했다. 중복 앱은 연결을 획득하지 못했으며 음악을 쓰지 않았다. 이후 helper에 정확한 앱 handle을 인자로 넘겨 복구하고 프로세스를 NFC 경로로 확인했다. `keyboard-backtab`, `native-keyboard-album` 역시 수정 전 결함 근거다.

콘솔이 열린 작은 창에서 모든 세부/추가 작업이 동시에 보인다는 주장은 하지 않는다. 아래 영역은 스크롤바가 필요하고 휠은 사용자 정의대로 줌한다. 공유 원본의 전체 native 조합, 실제 VoiceOver, 음악 설정 외 모든 UI의 키보드 조작 및 실제 입력/출력은 별도 후속이다. 이번 재열기에서 MIDI 설정 페이지는 복원됐으나 연결 검색어/전환 페이지 등의 전체 복귀 계약을 증명하지 않는다.
