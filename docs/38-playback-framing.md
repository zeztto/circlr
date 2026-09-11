# 재생 화면 · 작업 서클과 이름표

2026-09-08. 기준 `0e2e422`, `codex/daw-integration`. 이전 턴은 통합·native 검증·private push로 progress다. 이번 역할은 development-lead → UI/UX → native Swift utility → 같은 실행자의 읽기 전용 검토 → QA다. 런타임 1슬롯이므로 delegation none이다.

## UX 계약

현재 follow는 콘솔과 상단을 제외한 높이에서 `focused`가 다시 160px를 빼고 부모 원에 맞춘다. 1440×900 통합 화면의 자식 서클이 중앙에 작게 모이고, 이름표가 다른 원과 케이블을 가린다. 기능 없는 표면이나 추가 패널을 만들지 않고 같은 캔버스의 실제 음악 요소를 읽고 편집하는 것이 목표다.

- 재생 follow는 활성 섹션의 실제 자식 서클 경계에 맞춘다. 접힌 그룹은 하나의 원으로 취급하고 비어 있는 섹션은 자체 궤도로 맞춘다. 콘솔/상단/하단을 제외한 공통 workspace viewport를 사용한다. 소리의 크기에 따라 확대/축소하거나 이름표 우선순위를 바꾸지 않는다.
- 일반 섹션 진입에도 같은 framing을 사용한다. 정지 상태에서 섹션 이름/탐색으로 들어왔을 때 자식들을 다시 휠로 확대할 필요를 줄인다. 섹션 설정의 detail 진입과 앨범 전체 보기의 의미는 유지한다. 이 연결의 소유 파일은 `Sources/CirclrApp/AlbumCanvas.swift`다.
- 부모 궤도는 원래 좌표 그대로 그리며 화면 경계에서 잘릴 수 있다. 현재 섹션·마디·반복은 기존 상단 재생 문구로 읽는다. 중복된 부모 이름표 대신 자식 이름과 연결에 공간을 준다.
- 이름표는 자신이 가리키는 원과 가까운 위치를 유지하며 다른 작업 서클의 원 내부를 덮지 않는다. 선택·hover·직접 자식 우선순위로 제한된 공간을 배분하고, 배치된 이름표를 더블클릭하면 즉시 기존 편집기로 들어간다.
- 수동 휠/드래그/키보드 탐색은 follow를 중단하고 명시적 재개 버튼으로 돌아온다. 창 크기/콘솔 변경 시만 관심 범위를 다시 계산하며 Reduce Motion을 유지한다. 프로젝트 음악·노드 위치·timing·port binding은 변경하지 않는다.

## 구현과 검증 소유

Swift utility: 새 Core `PlaybackFraming.swift`, `CanvasLabelLayout.swift`; App `PlaybackVisualization.swift`, `CanvasPresentation.swift`와 필요한 canvas 진단. Core geometry/label 회귀 테스트. native 앱 제품 버전은 0.20.0 build 24로 올리되 현재 사용자 앱은 유지한다. 별도 QA 패키지에 기존 authored 통합 fixture 사본을 사용한다. 녹음·시스템 장치 설정을 건드리지 않는다.

검사: targeted Core → 전체 `swift test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, release build `.build/integration-release`. 공통 Core/Audio 호출의 PCM은 기존 전체 회귀로 확인한다. MCP/kit byte/version 계약은 Python 26개로 확인한다. native 1440×900/최소 창, 콘솔 열림/닫힘, 재생 모션/포커스, label-원 간섭, 더블클릭 편집과 재개, 저장 음악 불변을 실제 screenshot/AX/MCP로 확인한다.

Git: 같은 private 통합 branch에 검증된 source checkpoint를 commit/push한다. 마이크·VoiceOver·전체 E 출고 검증과 다른 장기 계획은 남아 있으며 이 slice를 전체 목표 완료로 취급하지 않는다.

Native에서 추가 발견: 재생 중 더블클릭의 follow 중단이 비동기 SwiftUI update에 다시 처리되어, 방금 시작한 수동 확대 animation까지 취소했다. `interruptPlaybackFollow`가 자기 mode 변경을 즉시 소비하게 해, 후속 update가 새 수동 확대를 취소하지 않도록 수정한다. 정지 상태와 실제 재생 상태의 편집 진입·재개를 모두 확인한다.

## 실행 결과

build 24 최종 UUID `9F368D1F-758A-3D93-8777-5F8AB4D726A6`. 전체 Swift 231개·Python 26개와 release build 통과. 실제 canvas 1440×801/1024×673, 콘솔 열림/닫힘 네 조합에서 8개 이름표가 viewport 안에 있고 서로 및 다른 원 내부와 겹치지 않았다. 실제 재생 중 MIDI 이름표 pointer 더블클릭/AX 활성화·휠 확대·재개 버튼을 검증했다. [상세 QA](../qa/playback-framing-review.md).

사용자의 에이전트 한도 해제 안내 이후 독립 read-only 리뷰를 다시 dispatch했으나 도구가 `agent thread limit reached`로 거절했다. 별도 작업을 만들어 우회하지 않았으며 같은 실행자의 순차 코드/파일 안전성 검토로 기록한다. 기존 음악·노드 위치의 최종 복원을 확인했고 사용자 앱·원본 QA 음악은 보존했다. 전체 목표는 progress다.
