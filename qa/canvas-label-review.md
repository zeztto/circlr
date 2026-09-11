# build 44 캔버스 이름·선택 검증

## 결과와 범위

`codex/daw-integration`, baseline `48c2ac6`. 긴 이름을 선택하면 최대 320px·세 줄과 종류를 표시하며 나머지 라벨은 한 줄로 유지한다. 한글 단어 단위 줄바꿈, 선택 테두리, 화면 가장자리의 대체 위치, 편집기/연결 도구/선택 포트/시간 손잡이 회피를 추가했다. 라벨의 실제 사각형을 클릭과 AX에 함께 사용하고 기존 `playback.labels` 진단에 제목·선택·anchor를 추가했다.

사용자의 한도 해제 안내 뒤 read-only 포트 검토 subagent를 다시 호출했지만 `agent thread limit reached`로 거절됐다. UI/UX → native Swift utility → read-only code review → QA를 같은 에이전트의 순차 역할 전환으로 수행했다. 독립 리뷰로 주장하지 않는다.

## 자동 검사와 패키지

- Swift **353개**, 실패 0, 25.119초: `.build/canvas-label-tests-final.log`. 기존 물리 출력 의존 `testArrangementRenderExportAndPlayback` 1개 제외. 새 8개는 네 모서리, 정상 위치 우선, 장애물·다른 서클 회피, 화면 밖 중심, 과대/비유한 크기, 우선순위·결정성, 실제 밀집 배치 회귀를 검사한다.
- Python **26개**, 실패 0: `.build/canvas-label-python.log`.
- 최종 release **41.75초**: `.build/canvas-label-release-final.log`.
- 최종 앱: `qa/generated/canvas-labels/perimeter/써클러 통합 검증.app`, `com.circlr.integrationqa`, 0.20.0 build 44, Mach-O UUID `55E16214-EE4E-30B2-B630-49544E2295EE`.
- `python3 qa/check-canvas-label-evidence.py`: **passed**. 실제 snapshot 14개·JPEG 11개, 소스 5개·kit 25개·실행 섹션 37개 일치와 strict codesign, 원본 authored 자산 SHA, 음악/배치 복원을 검사한다. 결과는 `qa/generated/canvas-labels/perimeter/verification.json`이다.

## 실제 앱 시나리오

전용 사본 `~/Library/Application Support/circlr-integration-qa/fixtures/canvas-labels.circlr`, ID `40C45549-C688-50BE-A1B8-2346E3D590EF`. 원본 `studio.circlr`의 직접 작성한 3트랙·2 tone asset만 복사하고, 긴 한글/영문 이름과 인접 mix bus 3개를 추가했다. 실제 캔버스는 1024×673, 화면 JPEG는 1019×768이다. 음악·미리 듣기·마이크·MIDI 입력은 시작하지 않았다.

| 시나리오 | 관찰 및 근거 |
| --- | --- |
| 밀집 선택 | 첫 후보에서 320px 라벨이 사라졌다(`selected-missing.json`). 주 선택만 화면 가장자리의 빈 후보도 탐색하도록 수정하고 실제 좌표를 회귀 테스트로 보관했다. 최종 `final-selected`에서 제목 전체가 320×66의 두 줄에 표시된다. |
| 화면 밖 중심 | H 드래그→V로 서클 중심을 viewport 왼쪽 밖으로 이동했다. `edge`에서 라벨은 viewport 안에 있고 AX selected/full title이 남는다. 라벨 클릭→Return으로 같은 악기 편집기에 진입했다(`edge-editor`). |
| 한글·생략 | `long`의 320×84 세 줄에서 끝을 생략하고 AX는 전체 제목을 보존한다. 한글 단어 내부 줄바꿈을 우선 피한다. 공백 없는 한글+영문 이름은 `unbroken`에서 세 줄로 읽힌다. |
| 연결 도구 | `cable`에서 도구를 피하며 선택 이름을 표시한다. Right로 OUT 방향을 오른쪽→오른쪽 아래로 이동했다(`cable-moved`, layout r4→5). Undo 후 원래 portLayout과 같으며 revision만 r6으로 증가했다. |
| 그룹 포트 | 접힌 그룹 IN 선택→포트 도구를 열었다(`port`). 그룹 이름 두 줄, 입력 선택 테두리, IN/OUT과 도구가 라벨에 가려지지 않는다. |
| 궤도 | 메뉴의 궤도 타임라인 전환, 섹션 전체 맞춤, MIDI 이름 선택을 수행했다. `time-handle`에서 시작 시간 손잡이를 가리지 않는다. 직접 드래그한 `time-moved`는 MIDI 시작 박을 변경하고 새 손잡이 위치를 피한다. |
| 복원 | 이름 변경, 포트 방향, MIDI 시간, 보기 변경을 Undo했다. `restored`와 저장 후 `reopened`의 음악/신호/자산/자유 배치/portLayout은 기준 사본과 일치한다(portLayout revision 제외). 마지막 music r133, dirty=false다. |

### 입력 검사 중 발견한 별도 한계

CUA `typeText`로 긴 한글 이름을 입력한 시도는 한글이 빠지고 ASCII·공백만 전달됐다. 그 결과는 `typing-failed.json`으로 보관했으며 정상 한글 입력 검증으로 계산하지 않는다. 해당 57개 변경을 Undo한 뒤 원래 이름을 검사하고 MCP의 단일 `set_node` operation으로 완전한 Unicode 이름을 전달했다(r129). 이 변경을 실제 ⌘Z 한 번으로 복원했다(r130).

기존 이름 TextField는 매 binding 변경을 음악 편집으로 저장한다. 이름의 한 번 확정/취소·한 Undo, IME 조합·외부 변경 보호는 다음 독립 개선 항목이다. 이번 변경은 이름 표시와 배치만 다룬다.

## 제한과 후속

실제 VoiceOver 발화·키보드 순회 전체, 펼친 그룹 내부의 여러 계층/다중 선택/모든 8방향 밀집 조합은 남아 있다. 가장자리에도 빈 공간이 전혀 없으면 겹쳐 그리지 않는다. 선택 label의 leader는 원과 이름을 연결하며 다른 cable의 경로까지 재배치하지 않는다. 충분한 빈 공간이 먼 곳에만 있으면 이름과 원 사이 거리가 길어질 수 있다.

이번 검사에서 출력·audition attempts는 모두 0이다. 기존 HAL 연결·실제 재생/녹음·MP4 출고 검증을 대신하지 않는다. 사용자 `dist/써클러.app` 0.19 build 21과 다른 작업 트리는 유지하며 최종 QA 앱은 정상 종료했다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
