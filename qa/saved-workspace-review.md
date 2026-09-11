# build 67 저장한 작업 페이지 복귀 검증

2026-09-09. `codex/daw-integration`, baseline `4d50a8c`. 실제 1 slot에 맞춰 UX → Core/native utility → read-only review → QA를 순차 수행했다. 독립 에이전트 검토는 아니다. 전체 DAW/UX 목표는 진행 중이다.

## 최종 산출물과 검사

- 앱: `qa/generated/saved-workspace/refined/써클러 통합 검증.app`, 0.20.0 build67, UUID `BE6B04E0-71C4-34A4-95FA-F2787010EC1B`. 이 작업의 검증 앱은 모두 종료했다.
- 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/saved-workspace.circlr`, ID `F8DAEB31-C399-5654-A31A-8B8D2364AB69`. 직접 작성한 3트랙·2 tone 자산, 32섹션·2분기와 다른 곡의 별도 편곡을 사용했다.
- 깨끗한 scratch `.build/saved-workspace-quality`: Swift477개, 실패0, 25.984초. 새 저장/복원 Core 검사8개 포함. Python28개, 실패0, 0.220초. 기존 물리 출력 의존 `testArrangementRenderExportAndPlayback`만 제외했다.
- release69.31초 → 범위 표시38.67초 → 같은 문서 재열기 identity 수정38.33초. 전체 테스트 이후 변경은 App의 범위 표시와 연결 편집기 identity이며 Core는 같고 release/native로 검사했다.
- `python3 qa/check-saved-workspace-evidence.py`: 최종 후보18상태·20화면, 이전 후보3기록(재현된 결함1건 포함), 전체 음악 비교, 최종 소스10개 hash, Mach-O37개 section, Codex kit25개 hash, codesign 통과.
- 원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 자산 checksum 유지. root `d88ea5d`, ports `1d304eb`, 사용자 앱0.19.0 build21과 기존 실행 프로세스 보존. 물리 출력·audition 시도0, 녹음 시작0.

## 실제 동작

| 검사 | 결과·근거 |
|---|---|
| 이전 문서 | workspace가 없는 원본 형식의 그룹 선택과 카메라를 열었다. `legacy-opened`, `baseline` r14. 이전 settingsOpen/midiStepMode 디코딩은 Core에서도 검사 |
| 연결 저장 | #2로 가는 재연결에서 #4 검색·대상·시작 오른쪽 아래/대상 왼쪽 위를 저장. 음악 r14 유지. `connection-saved` |
| 최종 cold/warm 복원 | 새 프로세스에서 #4·대상·재연결 모드 복원. #5로 바꿔 저장, 같은 프로세스에서 재열기 후 #5 복원, #4로 다시 바꿔 저장. 양방향 위치3/7 유지. `refined-cold-open`, `refined-query-saved`, `refined-warm-open`, `refined-warm-edited` |
| 실제 적용/Undo | 사용자의 재연결 적용 후 기존 ID·효과·분기를 유지하며 목적지를 #4로 변경 r15. edge는 배열 끝으로 이동하고 포트 위치3/7 추가, layout r5. 한 번 Undo로 원래 음악/위치를 복원 r16/layout r6. `reconnect-applied`, `reconnect-undone` |
| 섹션 전환 | #1→#3 전환 페이지·정확한 edge·카메라를 저장하고 재열기. 전체 manifest 동일. `transition-saved`, `transition-reopened` |
| 팬 오토메이션 | 악기 오토메이션에서 팬 선택 후 저장. 재열기 AX에 선택된 오토메이션·팬과 동일 곡선 화면이 있다. `automation-pan-saved` JSON/AX, `automation-pan-reopened` AX/이미지. 재열기 직후 별도 JSON은 없으며 다음 설정 전환 후 snapshot과 혼동하지 않는다 |
| 범위 복원 | 이번 사용에 추가한 악기의 공유 원본 설정은 재열기에서도 선택 및 기존 편집 불가 안내를 유지한다. 연결 페이지의 공유 원본 표시도 복원한다. `original-settings-saved/reopened`, `original-connections-saved/reopened`. 이 과정에서 원본 쓰기는 하지 않음 |
| 실제 공유 오디오 | 원본 graph에 존재하는 오디오의 공유 원본 설정·입력 가능 값을 저장하고 재열기. 전체 manifest 동일. `audio-original-settings-saved/reopened` |
| MIDI 편집 방식 | 이번 사용 범위에서 MIDI·스텝 모드를 저장하고 재열기. 선택 서클·content page·스텝·음악·전체 manifest 동일. `midi-step-saved/reopened` |
| 사라진 서클 | 저장 보기의 nodeID만 없는 값으로 만든 owned 사본을 열어 상위 섹션 선택·맞는 화면 배율로 복귀. 음악 r16 유지. `missing-node-input`, `missing-node-reopened` |
| 삭제된 재연결 | 저장 이후 대상 케이블만 제거한 사본을 연다. #4 검색만 남고 선택·재연결 ID는 해제, 연결 버튼 비활성, Return 무변경 r17. `missing-reconnect-input/reopened` |
| 삭제된 전환 | 저장 전환 edge만 제거한 사본에서 섹션 편집으로 복귀. 오래된 전환 버튼을 숨기며 다른 선택 분기는 유지. `missing-transition-input/reopened` |
| 사본 복원 | 결함 주입 전 MIDI 스텝 문서로 복원·재열기·저장. `final-restored`는 `midi-step-reopened`와 정확히 같음. 원래 노트·음색·자산·포트 binding 보존 |

## 발견·수정 및 검토

첫 focused test는 테스트의 enum 표기 `southEast` 오타로 컴파일에 실패해 실제 `southeast`로 수정했다. 이후8개 통과. 기존 `.build/navigation-reveal-quality`의 전체 증분 테스트는 `AgentPortTests.swift:11`에서 graph nil 강제 해제/SIGTRAP으로 시작 직후 중단됐다. 같은 소스를 새 scratch에서 모두 빌드한 뒤477개가 통과했다. 모델 구조 변경과 오래된 ABI 산출물 혼합 가능성은 있으나 원인을 입증했다고 단정하지 않는다. 실패 로그 `.build/saved-workspace-tests.log`와 통과 로그 `.build/saved-workspace-clean-tests.log`를 보존하고 추가 제외를 하지 않았다.

첫 native 후보 UUID `3BDD8107-5965-34A9-A870-C2D091825BC7`에서는 같은 문서 재열기 때 연결 SwiftUI view가 유지돼 이전 세션 generation을 참조했다. 화면에서 #5로 바꾼 뒤 저장값이 #4로 남는 결함을 `reopened-query-edit` AX/JSON으로 재현했다. `InlineCircleEditor`의 연결 본문 identity에 session generation을 추가했다. 최종 후보에서 cold open과 warm open 뒤 검색 변경·재저장을 모두 확인했다. 수정 전 기록을 최종 통과 수치에 합산하지 않는다.

읽기 전용 소스 검토에서 optional 보기 필드의 legacy/future page 기본값, 프로젝트 현재 scene에 대한 유효성 검증, 동일 source edge 제한, 삭제된 재연결의 선택 해제, 음악 Undo 중 현재 hierarchyView 보존과 import/plugin 자동 시작 부재를 확인했다. QA 결함 주입 도구는 고정 사본·build67·clean/완료 상태·기존 캡처와 정확히 같은 문서만 받고 전체 원본을 별도 기록한 뒤 재열기한다. 네트워크·인증·플러그인 실행 경로 변경은 없다. 이 변경 범위의 미해결 출고 차단 결함은 발견하지 못했다.

현재 선택한 서클의 작업과 연결 상태만 문서에 저장한다. build66의 모든 서클별 임시 cache가 앱 재실행 뒤 남는다는 뜻은 아니다. 스크롤·스텝의 세부 페이지/행·피아노롤/파형 배율·오토메이션 선택 점/표시 구간은 아직 전체 영속화되지 않는다. 실제 그룹/멀티 bus의 모든 native 조합, VoiceOver 발화, 장치 입출력과 사용자 앱 교체는 후속이다. 스텝의 헤더와 기본 입력은 작은 창에서 보이며 아래 행은 스크롤한다.
