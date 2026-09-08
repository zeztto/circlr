# 서클 gain/pan 오토메이션 실행 계약

0.18 `cf23b01` 이후의 구현 범위다. 목표는 같은 캔버스에서 실제 오디오 신호에 적용되는 gain/pan 곡선을 편집하고 MIDI·오디오·이펙트·바운스·MCP 작업을 연결하는 것이다. 기본 DAW 전체와 아티스트 세계관 도구의 남은 범위는 기존 로드맵에 유지한다.

## 역할과 범위

development-lead → planner/UI-UX → native Swift utility(Core/Audio) → native Swift UI utility → 읽기 전용 코드·보안 검토 → QA → lead 릴리스 판단 순서다. `p1zza-development-lead`, `p1zza-planner`, UI/UX·시각 지침을 적용한다. 추가 agent dispatch는 `agent thread limit reached`로 실패했으므로 이번 실행의 delegation은 none이다. 다른 작업을 새 task로 만드는 우회나 사용자의 concurrency 설정 변경은 하지 않는다.

- Core: `Automation.swift`, `SectionGraph.swift`, `SectionGraphCompiler.swift`, `AgentProtocol.swift`. optional node automation과 안정적인 point ID, gain/pan 범위·중복·유한수·점 개수·컴파일 크기 검증, 원본/use 변형·atomic 편집.
- Audio: `AutomationDSP.swift`, `SectionGraphRenderer.swift`. 기존 DSP·static node gain 뒤에 샘플 단위 곡선을 적용한다. output gain을 제외하는 바운스는 output automation도 제외하고 바운스 뒤 기존 output에서 한 번 적용한다.
- UI: `AutomationEditor.swift`, `InlineCircleEditor.swift`, `AppStore.swift`, `AlbumWorkspace.swift`, `CirclrApp.swift`, 기존 키보드/명령 검색. 선택 서클의 직접 버튼과 ⌘5로 연다. gain/pan, 점 추가/선택/삭제, 시간·값·linear/hold, on/off를 같은 canvas에 둔다. 텍스트 입력에는 음악 핫키를 적용하지 않는다.
- MCP/kit: `mcp/server.py`, 테스트, 번들 operations 문서. `set_automation`은 기존 14 tools 안에서 제공한다. 읽기 전용 specialist 권한은 그대로다.

## 시간과 신호 의미

- 대상은 audio source·악기·이펙터·믹스·출력·audio rhythm 서클이다. MIDI 신호의 크기는 velocity이며 audio automation 대상에 포함하지 않는다. MIDI 트랙은 악기 또는 출력 서클의 automation으로 제어한다.
- 점의 beat는 node.startBeat부터의 로컬 4분음표 박이다. 개별 tempo가 있으면 해당 tempo, 상속이면 부모 tempo map을 따른다. points는 시간 순으로 정규화하고 각 점의 outgoing 구간이 linear 또는 hold다. 첫 점 앞·마지막 점 뒤는 가까운 끝 값을 유지한다.
- node.lengthBeats가 명시되어 있으면 그 길이·repeatCount에 따라 곡선도 반복한다. 반복 완료 뒤에는 마지막 주기 끝 값, 섹션 잔향에는 섹션 끝 값을 유지한다. 개별 길이가 없는 audio의 자동 source 반복에서는 곡선이 섹션 안에서 연속 진행한다. 두 반복 방식의 차이를 UI에 표시한다.
- gain은 기존 node gain에 곱하는 0–4 배율이다. pan은 -1(왼쪽)–1(오른쪽), 중앙은 unity인 기존 equal-power 법칙과 일치한다. 비활성/없는 곡선은 원래 PCM을 바꾸지 않는다.
- 분할은 같은 node clock·곡선을 복사하므로 원래 소리를 보존한다. 복제의 명시 반복은 node origin을 이동하며, 자동 길이 조각의 beatOffset 복제는 곡선 점도 같은 로컬 beat만큼 이동한다. 범위 밖 이동은 atomic 거부한다.
- 기본/전역 bus graph automation과 plugin parameter·synth filter는 이 gain/pan 기반 다음 확장이다. placeholder UI를 만들지 않는다.

## UI 계약

단일 다크 캔버스를 유지한다. 현재 편집 내용과 automation을 직접 전환하며 새 창·dock·중첩 설정 메뉴를 추가하지 않는다. 궤도에서는 각도=시간, 반경=값이며 자유 배치에서는 가로=시간·세로=값이다. 좌표와 실제 값의 매핑을 표시한다. 작은 창에서도 파형/곡선과 핵심 명령이 콘솔에 가리지 않도록 배치한다.

빈 곳 클릭/점 추가로 입력, 점 드래그는 한 번의 Undo로 확정, 방향키는 시간·값 편집, 점 선택은 키보드로 이동, Delete로 삭제한다. 값·박·연결 방식은 숫자 필드/명시 컨트롤에서도 접근한다. 읽기/쓰기 중 stale revision 또는 선택 변경은 이전 drag 결과를 버린다. 비활성 곡선과 무곡선은 다른 상태이며 비활성은 points를 보존한다.

## 검증과 Git

1. 독립 `.build/automation-quality` Swift: tempo map 경계의 beat interpolation, 개별 tempo/시작, 명시 반복·마지막 hold, 점 ID·공유 원본/use·atomic 오류, DSP 양 채널·출력 바운스 중복 방지·기존 PCM 그대로.
2. Python MCP·agent kit; `.build/automation-release` release build. 실패와 변경된 동작만 집중 재검사한 뒤 전체 필요한 회귀를 수행한다.
3. 0.19 dedicated QA app/project에서 GUI 입력→drag/keyboard→hold/on/off→MCP→Undo→save/reopen→bounce/export를 확인한다. 실제 생성 WAV에 gain/pan이 반영되는 구간과 기존 v4 hash를 검사한다. 마이크·Scarlett 하드웨어 성공 주장과 구분한다.
4. README/CHANGELOG/사용법/QA/version/kit를 갱신하고 main의 독립 기능 commit으로 private source push한다. 코드·문서·테스트만 포함하고 미디어·앱·로컬 설정은 제외한다. 이전 앱을 보관한 뒤 검증된 앱을 패키징한다.

이 문서는 실행 계획이며 검증 결과를 대신하지 않는다. 완료 조건은 실제 곡선 편집과 PCM·저장·MCP 증거다.

## 0.19 사용법

1. 오디오·악기·이펙터·믹스·출력 서클에서 **오토메이션** 또는 **⌘5**를 누른다. MIDI에서는 같은 트랙의 악기로 이동한다. 현재 editor와 직접 전환하고 새 창을 만들지 않는다.
2. **볼륨 / 팬**을 고른 뒤 빈 곳을 클릭하거나 **점 추가 / Return**을 사용한다. 볼륨은 ×1이 원래 크기, ×0이 무음, 최대 ×4다. 팬은 -1 왼쪽, 0 중앙, +1 오른쪽이다. 첫 점 앞과 마지막 점 뒤는 끝 값을 유지한다.
3. 점을 끌면 시간과 값이 함께 바뀐다. 기본은 음악 격자에 맞추며 ⇧ 드래그는 시간 snap을 해제한다. 겹친 시작·끝 점은 ⌥ 클릭으로 끝 점을 선택한다. 곡선과 단위는 선택한 서클의 개별 템포·박자를 따른다.
4. **위치 박 / 볼륨 배율 / 팬 L/R** 필드에 정확한 수치를 입력한다. **다음 점까지 → 선형 / 유지**는 선택 점에서 다음 점으로 이어지는 구간의 방식이다. 궤도의 gain 반경은 제곱근 척도이므로 ×1도 충분한 편집 공간을 갖는다.
5. 대괄호 또는 **이전 점 / 다음 점**으로 선택하고 방향키로 시간·값을 바꾼다. ⌘D는 선택 점을 한 격자 뒤에 복제하며, Delete 또는 점 삭제는 선택 점 하나를 지운다. 중복 시간·범위를 벗어나는 편집은 거부한다. 텍스트 입력 중 Return·⌘D·⌘T는 음악 추가·복제·분할을 실행하지 않는다.
6. **적용**을 끄면 점을 보존한 채 bypass한다. **곡선 지우기**는 해당 parameter의 점을 제거한다. 편집·삭제·드래그는 Undo로 돌아간다. 저장하면 point ID·값·enabled·shape가 함께 보관된다. 편집기의 열림/선택 상태는 세션 상태이며 곡선 데이터와 별개다.

작은 창에서는 곡선과 핵심 명령을 나란히 유지하고 상세 도움말은 ⇧ 휠로 스크롤한다. 소리는 기존 prepared PCM 경로에서 렌더하므로 재생 중 편집은 재생을 다시 시작할 때 반영된다. 실시간 write/touch/latch 녹음이나 MIDI CC·plugin parameter 자동화 기능은 포함하지 않는다.

실행 결과, 중간 실패 수정, 실제 WAV 수치와 한계는 [0.19 QA](../qa/0.19-review.md)에 기록한다. 다음 구현은 장치 lifecycle과 녹음 시작·취소·복구를 우선한다.
