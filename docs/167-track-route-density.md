# 트랙 경로의 좁은 화면 배치

상태: build145 Release·아래 native 동선을 확인했다. data 독립 감사는 PASS_DATA_ONLY, 최종 UI 감사는 PASS_WITH_SCOPE_LIMITS다. 기존 build144의 공유 오디오 가시성 검증은 별도 완료 범위로 유지한다.

## 실제 문제와 변경 범위

`routebar145-before/seven-compact.jpg`의 약 680px 폭에서 긴 트랙 이름과 역할 7개가 한 행을 차지하면서 글자가 한 글자씩 세로로 줄바꿈됐다. 역할과 현재 트랙을 읽고 선택하기 어려운 배치 문제다.

`StudioNavigationView.swift`의 route bar를 넓은 폭에서는 한 행, 좁은 폭에서는 트랙 행과 줄바꿈 가능한 역할 영역으로 배치한다. 기존 target 선택·탐색·입력 guard 로직은 유지한다. 화면에 맞는 배치를 제공하되 역할을 잘못 합치거나 다른 트랙의 항목을 선택하지 않아야 한다.

## 검증 기준

- 같은 긴 이름·역할 7개 fixture에서 넓은 한 행과 약 680px 좁은 배치를 AX/JPEG로 비교한다. 단일 글자 세로 줄바꿈이 사라지고 현재 트랙·역할을 식별할 수 있어야 한다.
- 역할 선택과 현재 표시, 마우스·키보드 이동을 실제 수행한 범위에서 확인한다. 잘못된 이름·수치의 기존 guard를 우회하지 않는지 검사한다.
- 폭 변경과 순수 탐색 전후 음악·revision·자산 보존을 비교한다. 더 좁은 모든 폭·모든 이름 길이·전체 접근성 통과로 확대하지 않는다.
- 오디오·MIDI workspace의 편집 공간에 미치는 영향을 확인하고 기존 build144의 배치를 별도 결과와 혼합하지 않는다.

아래 결과는 QA 사본의 배치·탐색·데이터 검증 범위다. 물리 I/O·청취·전체 DAW 목표는 별도 조건이다.

## build145 실행 결과

Release는 48.43초에 통과했다 (`.build/build145-release.log`). 독립 소스 검토와 패키지 감사도 PASS했다. 배치 변경을 그대로 따라 쓰는 불필요한 테스트를 추가하지 않았으며 전체 suite는 실행하지 않았다.

`routebar145-final`에서 넓은 한 행과 좁은 7개 역할의 수직 글자 꺾임 해소를 확인했다. MIDI chooser의 Escape, 음색·effect·router·mix·output 단일 역할 5개의 직접 이동, audio chooser Return, 공유 오디오의 compact 배치와 Tab 수치 접근·MIDI 복귀를 r208에서 실행했다. data 감사는 PASS_DATA_ONLY, 최종 UI 감사는 PASS_WITH_SCOPE_LIMITS다.

compact 오디오의 최초 화면에서는 수치가 아래로 밀리는 한계가 남는다. 파형과 action은 접근 가능하지만 모든 핵심 수치가 항상 보인다고 주장하지 않는다. invalid draft·VoiceOver·모든 폭·bounce branch의 native 실행·전체 suite·물리 I/O는 이번에 검증하지 않았다.

data 감사는 캡처 3개의 r208에서 hierarchyView를 제외한 전체 manifest와 자산 SHA 18건을 확인했고 일정 tempo 사본 r208·원본 r198도 보존됐다. build144 baseline과 build145 compact-cancel 사이에는 camera pan x의 약 1e-12 차이와 piano scroll x의 +2px 차이가 있다. zoom/jump를 포함한 경로이므로 취소 회귀로 단정하지 않지만 전체 workspace exact 복귀 PASS도 주장하지 않는다. QA 앱을 종료하고 사용자 PID 86114를 유지했다.

최종 `native-ui-audit.json`은 JPEG/AX 16쌍과 baseline을 직접 비교해 `PASS_WITH_SCOPE_LIMITS`로 확인했다. compact 7개 역할·긴 이름, wide 한 행, 음색 화면의 effect 추가와 단일 역할 5개 표시, chooser Escape/Return, 공유 오디오 Tab의 배치 1 선택·시작 0.000 가시성 및 최종 MIDI를 확인했다. AX focus footer가 없어 OS focus 자체의 정확한 상태는 단정하지 않는다. 추가 blocker는 없으며 앞서 기록한 workspace 차이·compact 수치 가시성·물리 I/O 등의 한계는 유지한다.
