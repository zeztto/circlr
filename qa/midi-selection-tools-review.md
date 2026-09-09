# MIDI 파트와 코드 선택 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `cdcb11f`, 0.20.0 build 51. 직전 turn의 build 50은 private push까지 완료된 progress다. 확인된 1 slot 제약을 유지하며 development-lead → UI/UX → native Swift → 읽기 전용 review → QA를 순차 수행했다. 이번 turn에 독립 agent 리뷰를 수행했다고 주장하지 않는다.

## 검사와 후보

- Swift **386개**, 실패 0, **25.429초**. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. 기존 출력 장치 검사 한 개를 제외한다. 새 4개 Core 검사는 다중 pitch/onset 기준·화면 밖 노트·0.0000001박 오차·실제 off-grid 구별·전체/해제/반전·없는 ID·10,000개 역순 노트와 비전이적 조건 선택을 다룬다.
- Python **26개**, 실패 0, **0.214초**. 첫 release **49.61초**, 메뉴 화살표 **25.78초**, 중복 접근성 수정 **25.62초**. 두 후속 App 수정은 최종 release/native로 검증했으며 Core/Python은 첫 검사 이후 바뀌지 않았다.
- 첫 후보 UUID **5750FA3E-0125-3CFC-94B1-F4DC1E3638FA**에서 피아노 롤·음정/드럼 스텝과 입력 보호를 확인했다. 중간 `final` UUID **D065288B-409E-3825-AC5D-B82659D9B0B5**에서는 화살표 때문에 메뉴가 AX에서 두 번 노출됐다. 장식 이미지에 `accessibilityHidden`을 적용해 해결했다.
- 최종 `qa/generated/midi-selection-tools/readable/써클러 통합 검증.app`, UUID **F841159B-4F8B-3FD1-8733-CF3DD6816024**. `python3 qa/check-midi-selection-tools-evidence.py`가 snapshot **13개**(최종 7개), 최종 AX **13개**/JPEG **11개**, 소스 hash **7개**, Mach-O file section **37개**, Codex kit **25개**, build/version·strict ad-hoc codesign을 확인했다. 이 도구는 이번 로컬 산출물의 검증이며 다른 바이너리의 보편적 CI 검사가 아니다.

## 실제 UI와 데이터

직접 작성한 tone 2개·트랙 3개 사본을 사용했다. project ID는 **CA931FD5-3110-547C-BBD0-1A2FF12FB35E**다. 준비한 5개 노트의 시작/음정은 seed `0.13/60`, chord `0.13/64`, rounding `(0.13+1e-9)/72`, near `0.1301/67`, late `32.13/60`이며 길이 0.5박·세기 87이다. 창은 **1019×768**, 콘솔을 열어둔 상태다.

| 검사 | 실제 결과 |
| --- | --- |
| 파트 선택→편집 | 피아노 롤에서 Tab으로 seed를 고르고 ⌥P로 seed/late를 선택했다. 화면 밖 32박 노트도 포함하며 r15를 유지했다. Right는 그 두 노트만 +0.25박/r16으로 이동하고, 한 번 Undo/r17로 복원됐다. |
| 코드·다중 기준·반전 | ⇧⌘A 해제 후 Tab/⌥T는 seed/chord/rounding 3개를 선택하고 near는 제외했다. 선택 메뉴의 같은 음높이는 late까지 4개로 확장했다. ⌥I는 near 1개를 선택했다. near의 실제 시작 `0.1301`은 숫자 입력란에서 확인했다. AX 노트 요약은 기존 최대 3자리 표시다. |
| 입력 보호·해제 | near의 세기 작성 중 ⌥P와 ⇧⌘A를 눌러도 MIDI 선택 1개/r17을 유지했다. `81p`는 입력란에만 남았고 Escape로 원래 87을 보존했다. 직접 해제 버튼은 편집기로 포커스를 돌려주며 조건 선택 메뉴를 비활성화했다. |
| 음정·드럼 스텝 | 음정 스텝에서 ⌥P는 seed/late 2개를 선택했다. 드럼 행으로 바꿔 ⌥T를 누르면 두 시작 박의 합집합 seed/chord/rounding/late 4개가 된다. 음악과 r17은 그대로다. 최종 앱에서도 스텝 ⌘A 5개/⇧⌘A 0개와 메뉴 화살표를 확인했다. |
| 최종 피아노 롤·궤도 | 최종 피아노 롤에서 ⌥P 2개 선택을 다시 확인했다. 궤도 메뉴의 같은 시작 박으로 3개 선택 후 포커스가 궤도로 돌아왔다. Up은 코드 3개에만 +1반음/r18, 한 번 Undo/r19로 복원했다. ⌥I는 near/late를 선택하고 anchor는 가장 앞의 near/G4가 됐다. |
| 다른 사용 | 메뉴를 연 채 MCP로 두 번째 use **D3976E37-6DB2-52AD-8130-780692B60DC3**로 이동하면 현재 선택이 없어져 조건 메뉴가 비활성화됐다. 메뉴 취소 후 ⌘A는 그 사용의 원래 3개 노트만 골랐다. 첫 use의 준비된 5개 노트와 음악은 그대로다. |
| 저장·재열기 | 배치 Undo/r20 후 첫 use의 원래 3개 노트를 MCP로 복원/r21하고 저장·재열기했다. 이름/global/tracks/sections/arrangements/assets/patterns/signal/portLayout/circleLayout이 baseline과 일치한다. portLayout revision만 비교에서 제외했다. |

세 후보는 같은 QA 사본을 이어서 열었다. 첫 후보 편집은 실제 Undo로 복원했고, 최종 원래 노트는 MCP 편집으로 복원했다. fixture를 오프라인으로 덮어쓰지 않았다. 선택 명령은 `setLane`/audition/Undo를 호출하지 않으며 기존 anchor가 결과에 있으면 유지한다. 조건의 큰 lane 비용은 정렬/이진 탐색으로 제한한다.

## 검토와 남은 범위

읽기 전용 검토에서 선택의 순수 Core 계산, 편집기 포커스 조건, 공통 anchor/커서, 메뉴의 full edit identity, disabled 상속과 기존 파일 메뉴의 공통 명령을 확인했다. 차단할 추가 결함은 찾지 못했다. Native 대상 변경 검사는 메뉴가 현재 선택에 맞춰 비활성화된 경로다. 보관한 오래된 callback/AX 객체의 직접 재호출, 모든 외부 변경 경쟁, VoiceOver 발화는 별도로 남아 있다. legacy `MIDISelectionControls`의 표시 구조는 이번 주 캔버스 개선 대상이 아니다.

원본 `studio.circlr` manifest SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**, 두 tone checksum, root `d88ea5d`, ports `1d304eb`, 사용자 앱 **0.19.0 build 21**을 보존했다. 이번 QA 앱 3개는 모두 정상 종료했다. 출력/audition 시도는 **0회**다. 실제 마이크/MIDI 입력·재생/MP4·사용 앱 출고는 이번 선택 도구 검사에 포함되지 않는다. 소스·문서·테스트·QA helper만 private branch에 반영한다.
