# 전환과 효과의 직접 편집

2026-09-09. 기준 `855d80b`, `codex/daw-integration`, build 40 계획. 이전 goal turn은 build 39 구현·검증·private push로 progress다. development-lead → UI/UX → native Swift utility → code/security review → QA 순차 수행. 호스트의 `agent thread limit reached`로 delegation none을 유지한다.

## 사용자 계약

같은 캔버스의 섹션 전환에서 앞·뒤 섹션 이름, 전환 방식, 마디/초 길이 기준, 실제 초, 뒤 섹션의 시작 변화를 함께 읽는다. 시간 계산은 재생 컴파일러와 공유하며 변박·템포 map, 앞 섹션의 마지막 반복과 뒤 섹션의 첫 반복에 적용되는 의미를 보존한다. 잘못된 기존 전환은 오류를 본문에 표시하고 값을 고칠 수 있게 한다. 별도 dock/창을 추가하지 않는다.

전역·음악 서클·섹션 전환의 효과 숫자는 기존 공통 입력기로 통일한다. Tab/Shift-Tab 순서, Return 확정/Esc 취소 후 캔버스 포커스, 범위 오류·외부 변경 거절, 읽기만 할 때 원본 정밀도 보존을 유지한다. 게인 효과는 dB로 표시하되 저장값은 기존 선형 gain이다. 슬라이더는 기존 범위와 드래그 한 번당 한 Undo를 유지한다.

렌더러의 실제 계약에 맞춰 within은 앞 섹션 끝부분의 효과 또는 지정 트랙 비우기를, insert는 빈 구간 또는 리듬+효과를, overlap은 자동 페이드와 선택 리듬을 표시한다. 비활성인 방식의 효과/트랙 설정은 저장값을 보존하고 UI에서 숨긴다. 전환 길이가 0이면 효과와 리듬이 재생되지 않는다고 표시한다.

## 파일 책임과 단계

1. Core: 새 `Sources/CirclrCore/TransitionTiming.swift`, `Compiler.swift`, `Tests/CirclrCoreTests/TransitionTimingTests.swift`. 기존 시간 계산을 공유하고 변박/tempo/fractional bar·within/insert/overlap·invalid 경계와 실제 compile 결과를 검사한다. 스키마/DSP 변경은 없다.
2. Native UI: `EffectControls.swift`, 새 `TransitionWorkspace.swift`, `InspectorView.swift`, `InlineCircleEditor.swift`, `InlineEditorHeader.swift`, `CircleWorkspace.swift`. 전환을 두 작업 영역에 배치하고 공통 효과 입력을 적용한다. 전환→연결→전환에서 edge 대상과 포커스를 유지한다. 전역 Audio Unit의 선택 값은 현재 모델에서 읽고 한국어 명령으로 표시한다. Legacy 창도 같은 전환 본문을 재사용한다.
3. QA: build 40 별도 패키지와 직접 작성한 fixture 사본. 전환 시간/효과, 전역 효과, 서클 효과의 수치 입력·Tab/Return/Esc·실패/충돌·연결 왕복·Undo·저장/재열기를 실제 작은 창에서 검사한다. 물리 재생·마이크는 시작하지 않는다. Swift regression은 기존 장치 재생 한 항목 제외, Python 26개와 release를 실행한다.
4. 검토/기록: read-only 코드·보안 검토 후 수정 필요분을 구현 역할로 넘긴다. README/CHANGELOG/roadmap·QA 기록을 업데이트하고 동일 승인된 private 브랜치에 소스·문서·검사만 커밋/push한다. 앱/미디어/프로젝트는 로컬에 보존한다.

기존 HAL 출력 획득·실제 녹음·MP4·VoiceOver·사용자 앱 교체의 출고 조건과 전체 DAW 목표는 유지한다.

## 구현·검증 결과

build 40 최종 release와 Swift 330개·Python 26개가 통과했다. `TransitionTiming`의 변박/tempo map·fractional bar·반복 끝·모드 경계를 네 개의 테스트로 검증했으며 숫자 표시 정밀도 검사를 추가했다. Native QA는 전환/전역/음악 효과의 입력·왕복·외부 충돌과 실제 단위, 소스 마디 4.500초/대상 마디 3.281초, 조건별 효과 숨김을 확인했다. 메뉴 직후의 이전 AX 상태가 섞인 캡처는 확정 화면으로 재검증했다.

최종 QA 앱 UUID는 `33558307-67CD-34A0-B455-6E0782C11F4A`다. 73초 WAV export와 원본 정밀도 보존을 확인했으며 모든 fixture 변경을 Undo하고 r90에서 저장·재열기·기준 데이터 일치를 검사한 뒤 종료했다. 소스 11개·kit 25개 hash와 Mach-O section 37개가 빌드 산출물과 일치한다. [상세 QA](../qa/transition-effects-review.md)의 주장별 제한을 적용한다. agent 생성은 다시 `agent thread limit reached`로 실패해 실제 위임 없이 역할을 순서대로 수행했다.

후속은 밀집 연결과 긴 이름의 표시/hit, 남은 import 작업 흐름 및 전역 설정 왕복 포커스다. 실제 VoiceOver·Audio Unit·슬라이더 전체 키보드 경로와 물리 출력/입력은 이번 수치·전환 검사로 완료 처리하지 않는다.
