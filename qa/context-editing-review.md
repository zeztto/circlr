# build 30 직접 음악 설정 검증

2026-09-09. `codex/daw-integration`, 기준 `17778eb`. 전체 개발 목표는 progress다. 독립 read-only 리뷰 에이전트를 요청했지만 도구가 `agent thread limit reached`를 반환했다. 동일 실행자가 UI/UX → Core/Swift utility → 읽기 전용 코드·입력 검토 → QA를 순차 수행했으며 독립 agent 검토로 보고하지 않는다.

## 대상과 자동 검사

- 사용자 앱은 0.19.0 build 21로 유지했다. 실제 마이크·재생·계정 상태를 변경하지 않았다.
- 최종 앱: `qa/generated/context-editing/final/써클러 통합 검증.app`, 0.20.0 build 30, UUID `ABA75AA2-EF06-3279-95AF-1FE21067C023`.
- QA 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/context-editing.circlr`, ID `BFE21996-2B65-5751-90D0-6C2F0A37A7A4`. authored studio fixture의 3트랙·2 tone 자산만 복사했다. 원본 manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`를 보존했다.
- Swift 전체: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, 272개, 실패 0, 22.685초. Python MCP/키트 26개 통과. 최종 release 23.26초.
- Core 7개 추가 테스트: 유효값·상속/앨범/보관된 local, 성분별 보존, global/곡/rhythm/JSON 왕복, 공유 원본의 use override 복사 방지, 비활성 편곡안 대상, 실패 원자성, 강세 parser.
- 전체 Swift 검사 뒤 Native에서 발견한 동일 문자열 이벤트 guard를 추가했다. 이 최종 App 변경은 release 및 아래 최종 Native 검증을 통과했다.
- `python3 qa/check-context-evidence.py` 통과: 저장된 실제 음악 값/revision/복원, codesign, 최종 소스·앱의 file-backed Mach-O 37 section, Codex kit 25개 hash, 원본 fixture 보존.

## Native 결과

최소 폭 1024, 캔버스 1024×673에서 콘솔 열림/닫힘을 확인했다. 설정은 같은 캔버스 안에 있으며 별도 전체 적용 버튼 없이 유효값과 출처를 함께 표시한다. 근거는 `qa/generated/context-editing/`에 보존한다.

| 시나리오 | 결과 | 근거 |
|---|---|---|
| 상속 값 직접 편집 | 128 BPM → Tab → 박 수 7. 두 항목만 local, r14→16 | `tempo-meter.json` |
| 성분 보존 | 분모 8, D→major, 강세 2+2+3, 분할 8→Tab→스윙 0.3. 7/8·D major와 sibling 성분 유지 | `musical-fields.json`, r22 |
| 잘못된 강세 | 2++3 거절, inherit beatGrid·r19 유지 | `accent-invalid.json`, AX |
| 출처와 보관값 | 앨범 전환은 표시 120·저장된 local 128 유지. 개별 재선택은 128 | `source-album.json`, `source-restored.json` |
| 항목별 Undo | 10번 변경을 10번 Undo, r34에서 음악 원본 일치 | `restored.json` |
| 최종 global 직접 확정 | 126 BPM·강세 3+3+2를 각각 Return으로 즉시 적용, r36 | `final-global.json` |
| 확정 UI | 강세 확정 후 불필요한 적용/취소 버튼 제거 | `final-accent-applied-ax.txt` |
| 외부 충돌 | 강세 draft 작성 중 MCP 트랙 gain 변경 r37. Return 거절, global 전체 유지 | `final-stale.json`, AX |
| 취소·Undo | Esc 후 세 번 Undo로 음악 복원 r40 | `final-undo.json` |
| 최종 섹션 연속 Tab | 130 BPM→5/4, 각각 local·r42. 콘솔 닫힘에서 행·길이/반복 확인 | `final-section-tab.json`, `final-section-console-closed.png` |
| 리듬 연결 | 패턴 생성 r45, 재생 안 함 r46은 패턴 자산 유지. Undo r47에 같은 패턴 연결 복원 | `final-pattern-created.json`, `final-rhythm-none.json`, `final-rhythm-undo.json` |
| 저장·재열기 | 패턴 생성도 Undo 후 r48. global/tracks/sections/arrangements/assets/patterns 모두 초기와 동일, open completed·dirty false | `final-restored.json`, `final-reopened.json` |

## 발견한 결함과 범위

첫 후보에서 강세 확정 직후 SwiftUI가 같은 문자열의 setter를 다시 호출해 이미 끝난 draft의 적용·취소 버튼이 남았다. 문자열이 동일하면 편집을 다시 시작하지 않도록 수정했다. 첫 후보의 음악 데이터 검증과 최종 후보의 수정 검증을 분리하며 두 앱을 덮어쓰지 않았다.

공유 원본 편집은 원본 graph에서 settings만 수정한다. use의 전체 node override가 이미 존재하면 그 사용에서는 원본 변경이 가려질 수 있으며 기존 override schema를 바꾸지 않았다. 공유 원본·곡/악장·숨은/다른 편곡안 주소는 Core 검증 범위다. 그 전체 Native 조합과 실제 VoiceOver 발화는 남아 있다.

legacy 사각 설정 창의 전체 draft, 전역 signal/전환/automation 모든 위젯, 녹음 중 입력·장치·MP4·밀집 화면과 E 출고 gate는 이번 완료 범위에 포함하지 않는다. 소스 private push와 사용자 앱 출고는 별개다.
