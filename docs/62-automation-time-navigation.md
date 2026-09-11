# 오토메이션 시간 눈금과 점 탐색

`session-bootstrap-v1`: owner=development-lead; baseline=af1b33f; branch=codex/daw-integration; delegation=none. 직전 실제 서브 에이전트 생성은 `agent thread limit reached`였고 build 47은 검증/push 완료 progress다.

## UX 계약

오토메이션의 전체 점 보기는 원래 서클보다 긴 범위를 표시할 수 있지만 마디 눈금은 원래 clock의 `barStarts`에서 끝난다. 이전/다음 점으로 범위 밖의 점을 선택해도 점이 보이지 않는다. 한 다크 캔버스의 기존 곡선/궤도 안에서 다음을 구현한다.

- 표시 끝까지 마지막 박자를 이어서 마디 눈금을 생성한다. 기존 변박·로컬 시간·미완성 마지막 마디의 경계는 유지한다. 원래 길이 끝을 새 마디로 오인하지 않는다. 긴 범위는 희소 눈금을 생성하고 실제 글자 영역을 검사해 작은 창에서도 겹치지 않게 한다.
- 선택 점의 현재 번호/전체 수와 마디·박·초를 읽을 수 있게 한다. 이전/다음 및 Home/End는 실제 선택 점까지 표시 범위를 펼친다. 수치로 범위 밖으로 옮긴 점은 ‘선택 점 보기’로 직접 복귀한다. 펼친 범위는 다음 편집/Undo/배치 전환 중 유지하고 기존 서클 길이 보기로 돌아간다.
- 표시 범위·선택·탐색은 음악/Undo를 변경하지 않는다. 기존 박 입력, 선형 gain/pan 보간, 반복/재생 clock과 데이터 schema는 유지한다. AX는 현재 실제로 보이는 점의 대상/세션을 검사하고 제거된 화면의 오래된 객체가 새 곡선을 선택하지 않게 한다.

## 소유와 실행

UI/UX → native Swift utility → 읽기 전용 code review → QA → development-lead 순차 수행. Core 소유: `Compiler.swift`의 표시용 마디 경계 metadata, 새 `AutomationRuler.swift`, `AutomationViewport.swift`, `Tests/CirclrCoreTests/AutomationRulerTests.swift`. App 소유: `AutomationEditor.swift`. `AgentWorkspace`는 기존 `displayBeats`로 실제 범위를 관찰한다. `Info.plist` build 48, README/CHANGELOG/로드맵과 전용 QA helper/보고서를 갱신한다.

Swift 전체 offline: `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. Python: `python3 -m unittest mcp.test_server qa.test_agent_kit`. Release: `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. Core는 변박, 부분 마디, 상속 중간 시작, 범위 밖·최대 범위·비유한 입력, 선택 범위 확장/고정을 검사한다. 최초 증분 scratch의 테스트 충돌 뒤 새 디렉터리에서 동일 소스를 전체 재빌드했다.

전용 authored 사본에서 64박 안/밖의 오토메이션 점을 만들고 자유/궤도 배치의 눈금과 선택 위치, 이전/다음·Home/End, 숫자 편집/선택 보기/한 Undo, 범위 고정·원본/다른 사용 전환·저장/재열기를 검사한다. 사용 중인 앱과 다른 작업 트리, 원본 음악·tone asset·이전 QA 앱은 보존한다. HAL 출력/audition·실제 입력은 시작하지 않는다. 독립 리뷰/VoiceOver 발화/물리 입력 검증으로 주장하지 않으며 source/docs/tests/QA helper만 승인된 private branch에 commit/push한다. 전체 DAW/UI goal은 유지한다.

## 결과

build 48에서 구현하고 깨끗한 빌드의 Swift 374개·Python 26개, 실제 앱 snapshot 17개·JPEG 6개와 패키지 검사를 통과했다. 실제 화면의 첫 마디/아래 궤도 숫자 누락과 AX 정보 덮어쓰기를 수정했다. 음악·배치를 복원한 뒤 저장/재열기를 확인했다. [QA 보고서](../qa/automation-time-navigation-review.md)에 최초 증분 실패, 후보별 근거, 미검증 범위를 구분한다. 전체 목표와 실제 장치/출고 검증은 진행 중이다.
