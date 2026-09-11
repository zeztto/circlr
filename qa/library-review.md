# build 31 로컬 샘플 라이브러리 검증

2026-09-09. `codex/daw-integration`, 기준 `d318e44`. 전체 goal은 progress다. 실제 agent 생성 한도 거절에 따라 같은 실행자가 UI/UX → Swift utility → read-only 코드·입력/보안 검토 → QA를 수행했다. 독립 agent 검토로 표현하지 않는다.

## 산출물과 검사

- 최종 앱: `qa/generated/library-editing/verified/써클러 통합 검증.app`, 0.20.0 build 31, UUID `8A4EE035-EB82-3A2B-930E-E302623E0BD1`.
- QA 프로젝트: `~/Library/Application Support/circlr-integration-qa/fixtures/library-editing.circlr`, ID `183951BB-4FA4-5A4A-8BC4-E8136B507F0E`. 사용자 설치 앱 0.19 build 21과 실제 곡은 보존했다. 실제 마이크·Splice 계정/구매는 사용하지 않았다.
- 원본 authored studio fixture의 3트랙·2 tone을 복사하고 QA 폴더에 오디오 2개·직접 작성한 MIDI·손상 오디오·숨김 파일·설명 파일을 준비했다. 미디어/프로젝트/앱은 Git에 포함하지 않는다. `prepare-library-qa.py`는 버전별 앱과 재현용 파일을 준비하며 기존 후보를 덮어쓰지 않는다.
- Swift 전체 285개 통과, 실패 0, 22.984초. 명령: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. Python MCP/키트 26개 통과. 그 뒤 대상 갱신의 안내 초기화·main window 단축키 guard 2개 UI 보완은 최종 release와 Native에서 검사했다. 최종 release 24.59초.
- 신규 13개: MediaLibrary 8개(재귀·검색·정렬·범위/개수·링크/교체·파일 변경·실제 decoder/복사·취소), MediaPreview 5개(정상/실패·준비 전/중·장치 시작 중·재생 중 취소).
- `python3 qa/check-library-evidence.py` 통과. 실제 캡처의 데이터·revision·원본 파일 6개 hash·최종 file-backed Mach-O 37개 section·codesign·Codex kit 25개 hash를 재검사한다. 원본 studio manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`도 유지했다.

## Native 작업 흐름

최소 폭 1024, 캔버스 1024×673에서 실제 키보드·AX·화면·MCP와 저장 manifest를 대조했다. 근거는 `qa/generated/library-editing/` 아래에 있다.

| 작업 | 결과 | 근거 |
|---|---|---|
| 폴더 등록·bookmark 복원 | 사용자가 선택하는 NSOpenPanel 경로로 QA 폴더 등록, 다른 후보 앱 재실행 뒤 4개 파일 복원. 숨김/텍스트 제외 | `registered-ax.txt`, `final-bookmark-ax.txt` |
| 검색·파일 정보 | Nordic 검색은 1개, 실제 decoder의 32.00초·48000 Hz·stereo. MIDI는 2개 노트 | AX와 `verified-library.png` |
| 빈 검색 | 일치하는 파일 없음·가져오기 비활성 | `final-empty-search-ax.txt` |
| 작은 창·접근성 | 상단 템포가 한 줄, 검색 화면 동안 배경 canvas가 AX 트리에서 제외됨. 파일 행은 하위 경로까지 구분 | `final-library.png`, `verified-library-ax.txt` |
| 키보드 | ⌥⌘L 열기, ↑↓ 선택/Return 명령 경로, ⌥Space 시작·취소, Esc 캔버스 복귀 | `verified-keyboard-down-ax.txt`, `verified-keyboard-up-ax.txt`와 snapshot |
| 오디오 가져오기 | 검색→Return으로 기존 트랙에 32초 오디오 추가, r14→15. 출력 준비 정리 중에도 UI와 MCP 응답 | `final-audio-imported.json` |
| Undo/Redo·재열기 | 한 Undo r16에 초기 음악 완전 복원. Redo r17과 저장/재열기 데이터 일치 | `final-audio-undo.json`, `final-audio-redo.json`, `final-audio-reopened.json` |
| revision 충돌 | 라이브러리를 연 뒤 MCP gain 변경 r18. Return 거절, asset/track 증가 없음. 갱신 전 버튼 비활성 | `final-stale-rejected.json`, `final-target-stale-ax.txt` |
| 선택 충돌·안내 복구 | MCP로 다른 출력 선택 시 가져오기 거절, 현재 대상 갱신 뒤 오래된 안내 제거 | `ready-target-refreshed-ax.txt` |
| MIDI | 검색→트랙 선택→2개 노트(C4/E4, 각 1박·velocity 96) 새 트랙 추가 r20. Undo r21은 오디오만 가져온 상태와 일치, Redo r22 | `final-midi-preview-ax.txt`, `final-midi-imported.json`, `final-midi-undo.json` |
| 폴더 제거 | 목록에서 제거 후 folders/files 0, 음악 r22 유지·원본 파일 6개 그대로. 재실행 후에도 빈 목록 유지 | `final-folder-removed.json`, source hash 검사 |
| 폴더 대화상자 단축키 | 유효 오디오 선택 후 폴더 선택 창에서 ⌥Space. 취소해 돌아와도 previewPending/Playing false | `verified-folder-dialog-ax.txt`, `verified-panel-keyboard.json` |
| 최종 저장 | r22·dirty false·previewPending false·libraryOpen false. 가져온 오디오와 MIDI를 QA 사본에 보존 | `verified-final.json` |

## 발견하고 수정한 문제

1. macOS `/var` alias의 정규화와 enumerator URL 표기가 달라 상대 경로에 root 이름이 중복됐다. 양쪽을 동일하게 정규화하고 실제 파일 검사·부모 symlink 교체 테스트로 확인했다. macOS가 package로 취급하는 확장자 디렉터리도 건너뛴다.
2. 첫 후보에서 상단 템포/스케일 줄바꿈·영어 decoder 오류·배경 AX 노출을 관찰해 compact header·한국어 오류·접근성 범위를 수정했다.
3. NSSearchField가 ⌥Space를 공백으로 입력했다. 라이브러리가 열린 main window의 local monitor로 처리하며 IME 조합과 파일 선택 창은 제외했다.
4. 첫 미리 듣기 후보는 준비만 백그라운드로 수행하고 play를 MainActor에서 실행했다. 실제 앱 응답 timeout과 `AVAudioPlayer.play → AudioQueueStart → HALC_ProxyObject::HasProperty` 대기를 stack sample로 확인했다. 수정 전 QA 프로세스 57079만 SIGTERM으로 종료했다. 이 시점에는 폴더 설정만 변경됐고 곡은 r14였다. stack과 실패 후보를 보존했다.
5. 최종 구현은 player 생성/준비/muted 시작/음량 활성화/시계/정지를 모두 백그라운드에 둔다. 실제 지연 중에도 AX/MCP가 응답했고 취소 후 오디오 import까지 완료했다. 취소된 작업이 뒤늦게 끝난 뒤 pending/playing false를 확인했다. Native는 지연과 취소/정리를 증명하며 정상 속도의 실제 preview 완료를 증명하지 않는다. 단위 테스트는 device start가 취소 뒤 반환해도 audible 단계에 들어가지 않음을 검증한다.

## 남은 범위와 다음 단계

- 이 Mac의 HAL 출력 준비 지연 원인과 실제 audible preview 완료/정상 latency는 남아 있다. 추가 시작 요청도 준비 지연을 보였으며 취소한 뒤 QA 앱을 정상 종료했다. 미리 듣기 기능의 구현·취소 검증을 정상 장치 성능 완료로 표현하지 않는다.
- 색인 상한은 50,000개, 폴더당 탐색 200,000개, 등록 폴더 16개다. 한도 논리는 축소 fixture로 검사했으며 실제 대규모 라이브러리 성능·여러 외장 볼륨·이동된 bookmark 갱신·권한 철회 전체 Native 조합은 미검증이다.
- 실제 VoiceOver 발화·IME 전체 조합·Finder/Splice file promise·자동 폴더 감시·미디어 중복/GC·전용 라이브러리 MCP 명령·transport 동기 preview는 후속 범위다. 이 구현은 로컬 다운로드 파일을 다루며 Splice의 클라우드 카탈로그나 구매 API가 아니다.
- 사용자 앱 출고·실제 녹음/MP4·E gate를 완료로 올리지 않는다. 다음 진단은 출력 준비의 실제 device/driver 대기를 분리하고, 사용자에게 전달할 설치 앱의 검증 범위를 재점검하는 것이다.
