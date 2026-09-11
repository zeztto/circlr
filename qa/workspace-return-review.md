# build 66 연결 작업·전환 편집 복귀 검증

2026-09-09. `codex/daw-integration`, baseline `473ba15`. 실제 1 slot에 맞춰 UX → Core/native utility → read-only review → QA를 순차 수행했다. 독립 에이전트 검토는 아니다. 전체 DAW/UX 개발 목표는 진행 중이다.

## 산출물과 검사

- 최종 앱: `qa/generated/workspace-return/final/써클러 통합 검증.app`, 0.20.0 build66, UUID `B4B43084-15DB-357A-8243-7C9E996E5974`. 실제 키보드 검증한 `keyboard` 후보와 실행 파일의 37개 file-backed section이 같다. 이 작업의 검증 앱은 모두 종료했다.
- 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/workspace-return.circlr`, ID `A870E933-4C6E-5665-8127-9E4B454E5DC9`. 직접 작성한 3트랙·2 tone 자산, 32섹션·2분기와 다른 곡의 별도 편곡을 사용했다.
- Swift469개, 실패0, 26.069초. 새 Core 복원 검사6개 포함. Python28개, 실패0, 0.321초. 물리 재생을 포함하는 `testArrangementRenderExportAndPlayback`는 기존 범위에 따라 제외했다.
- release: initial66.12초 → 유효 전환 헤더 보완36.94초 → 상단/본문 공통 Tab 보완37.63초 → 파일 끝 빈 줄 정리34.76초. 마지막 수정은 `StudioModeButton.swift` 끝의 빈 줄 하나이며 실행 파일 section과 UUID가 같아 native 재검사를 반복하지 않았다. 전체 테스트 이후 동작 변경은 App의 헤더/키보드 결합이며 Core와 테스트는 같고 release/native로 검증했다.
- `python3 qa/check-workspace-return-evidence.py`: 저장된27상태, 상태 복원34화면과 최종 키보드7화면, 전체 음악 문서 비교, 최종 소스9개 hash, Mach-O37개 section, Codex kit25개 hash, codesign 통과.
- 원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 모든 자산 checksum 유지. root `d88ea5d`, ports `1d304eb`, 사용자 앱0.19.0 build21 및 실행 프로세스를 확인했다. 물리 출력·audition 시도0, 녹음 시작0.

## 실제 동작과 전체 문서 비교

| 검사 | 결과·근거 |
|---|---|
| 연결 작업 복원 | `#3` 검색·선택, OUT 재생 포트, 시작 오른쪽 아래/대상 왼쪽 위, 현재 포트 범위를 설정 화면 왕복 후 복원. `pending-directions`, `connection-restored` r14 |
| 전환과 편집 분리 | 연결 행의 #3 전환을 열고 상단 편집으로 나간 뒤 전환 버튼으로 같은 edge 복귀. 전환 길이 .125→.25만 변경 r15, Undo r16. `transition-open`, `section-from-transition`, `transition-return`, `transition-to-connections` |
| 서클별 재연결 | #2로 가는 케이블의 재연결에서 #4를 고르고 다른 섹션으로 이동. 다른 섹션은 빈 작업, 돌아오면 #4·재연결 모드 복원. r16 유지. `reconnect-pending`, `other-section-fresh`, `reconnect-restored` |
| 보이지 않는 동안 삭제 | 설정으로 나간 동안 MCP로 해당 케이블 제거 r17. 다시 연결로 오면 #4 검색만 남고 선택·재연결은 해제되며 연결 버튼 비활성. Return도 무변경. Undo r18로 전체 복원. `hidden-deleted`, `deleted-reconnect-return` |
| 현재 전환 삭제 | 전환 화면의 edge를 MCP로 제거 r19. 상단은 섹션 이름·선택된 편집을 보이며 오래된 전환 버튼을 숨긴다. 나머지 선택 분기 유지, Undo r20. `active-transition-deleted` |
| 오디오·MIDI | 악기 OUT 오디오/믹스 검색·대상을 설정 왕복에서 유지. IN MIDI/MIDI 검색·대상도 따로 확인. r20 음악 전체 유지. `audio-query-restored`, `midi-restored` |
| 원본 범위·명시적 포트 | 공유 원본 범위는 빈 작업으로 시작하고 이번 사용 범위로 돌아오면 MIDI 작업 복원. 실제 캔버스 OUT을 열면 캐시보다 우선하여 OUT/빈 검색으로 진입. 원본 음악 쓰기 없음. `original-fresh`, `use-scope-restored`, `explicit-audio-port` |
| 세션 경계 | 같은 프로젝트를 다시 열면 저장 manifest는 정확히 같고 연결 검색·대상·최근 전환은 초기화. 음악 Undo와 저장 schema에 임시 상태를 넣지 않는다. `before-session-reset`, `reopened`, `new-session-connections` r20 |
| 이름 draft | 상단 작업 이동 전에 이름을 한 번 확정 r21. Undo r22에서 최초 음악 전체와 일치. `name-committed-switch`, `final-restored` |
| 실제 재연결 적용 | 복원한 #4 draft를 적용 r23. 기존 케이블 ID·전환 효과·선택 분기를 보존하며 목적지만 #4로 변경. remove/append에 따라 해당 edge는 배열 끝으로 이동한다. Undo r24에서 전체 복원. `commit-restored-draft`, `reconnect-applied`, `reconnect-undone` |
| 최종 키보드 | 연결 검색에서 Shift-Tab 두 번으로 전환 → Return. L로 연결 복귀 시 #3 검색·선택 유지. 검색에서 Shift-Tab 네 번으로 편집 → Return. 악기에서는 검색→Shift-Tab 두 번→설정→Return. `body-to-header`, `keyboard-transition`, `keyboard-connection-back`, `body-to-edit`, `keyboard-section-edit`, `keyboard-music-header`, `keyboard-music-settings` |
| 최종 저장 | 최종 후보가 r24 문서를 그대로 열었고 키보드 왕복 후에도 음악 전체가 같다. `keyboard-opened`, `keyboard-return-verified` |

## 발견·수정과 검토

상태 검증 후보 UUID `1BF9BD06-92A4-31ED-BEE2-DAA7D84707BC`에서 기존 이름 필드→상단 버튼의 Tab 이동은 가능했지만 연결 본문의 지역 Tab 순환은 상단 버튼을 제외했다. `InlineCircleEditor`가 공통 `PortKeyboardFocus`를 소유하고 상단 작업 버튼도 등록하도록 최종 후보에서 수정했다. 최종7화면은 이 후보의 실제 입력 증거이며 앞선34화면은 상태 로직 증거다. 최종 후보가 모든 이전 화면 검사를 다시 수행했다는 뜻은 아니다. 전환 진입 뒤 초점은 캔버스로 돌아오며 L로 연결을 다시 연다.

CUA의 최초 한글 `typeText`는 검색에 반영되지 않았다. `audio-pending`, `audio-restored` 화면은 한글 검색 통과 근거에서 제외하고 실제 paste 후 `audio-query-pending`, `audio-query-restored`를 사용했다. `audio-restored.json`은 수정된 검색 후 저장한 문서다. 최종 악기 검사의 첫 paste도 클립보드 timeout이 있었으며 새 AX로 검색 포커스를 확인한 후 재시도했다. 그 후 캡처한 `keyboard-music-header/settings`만 최종 근거다.

읽기 전용 소스 검토에서 Core가 현재 포트·필터된 대상·동일 케이블의 논리적 양 끝을 검증하는지 확인했다. AppStore 캐시는 프로젝트 ID와 세션 generation으로 지연된 onDisappear 저장을 막으며 이번 사용/원본 키를 나눈다. 명시적 요청은 한 번 소비하고 일반 진입만 기억을 사용한다. 네트워크·인증·파일 포맷은 추가하지 않았다. QA helper의 고정 사본/빌드 guard와 새 캡처의 배타적 파일 생성을 확인했다. 미해결 출고 차단 결함은 이 변경 범위에서 발견하지 못했다.

세션 캐시는 앱 재실행 뒤 저장되는 기능이 아니다. 연결 스크롤 위치·모든 작업 페이지의 영속 복원, 전체 그룹/멀티 bus의 native 조합, 실제 VoiceOver 발화, 실제 MIDI·오디오 입출력은 별도 후속이다. 창 폭1024의 화면에서 상단 작업·입력·콘솔을 확인했지만 모든 고급 설정이 스크롤 없이 동시에 보인다는 뜻은 아니다.
