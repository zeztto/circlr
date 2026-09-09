# 섹션·서클로 직접 이동하는 작업 검색

`session-bootstrap-v1`: development-lead; baseline=85aa024; branch=codex/daw-integration. 직전 실제 sub-agent dispatch가 thread limit으로 실패했고 현재 1 slot이다. 순차 UI/UX → native Swift/Core utility → read-only review/security → QA로 진행한다. 소유 경로는 아래에 고정한다.

## UX 계약

현재 ⌘J는 이펙트 이름으로 검색해도 행의 primary MIDI/오디오를 연다. 섹션은 긴 메뉴에서, 같은 역할의 여러 서클은 두 번째 메뉴에서 찾아야 한다. 검색 결과를 실제 이동 대상인 섹션/서클 단위로 바꾼다. Return/클릭은 표시된 그 대상을 열고 음악·Undo를 바꾸지 않는다.

기존 단일 다크 캔버스의 overlay를 850×560으로 사용한다. 상단은 검색, `이 섹션 / 전체 앨범`, 역할 필터(전체·섹션·MIDI·오디오·음색·이펙트·라우터·믹스·출력)와 현재 제한 경로다. 하단 결과는 독립적으로 스크롤하며 이름 두 줄, 곡/섹션/번호·트랙 경로 두 줄, 같은 역할의 여러 대상 번호와 미연결 표시, 전체 AX/help를 제공한다. 빈 섹션도 결과로 이동할 수 있다.

검색은 Unicode/대소문자/폭을 정규화하며 실제 서클 이름·곡/섹션/트랙·번호·역할과 UI 동의어를 찾는다. 기본 ⌘J는 전체 앨범을 검색하며 현재 선택을 강조·스크롤한다. `이 섹션`은 진입 시 섹션을 고정한다. 여러 서클이 있는 역할 버튼은 해당 섹션·트랙·역할 필터로 이 검색 화면을 바로 연다. 제한된 트랙은 명시하고 한 번에 해제할 수 있다. 필터 변경은 검색 입력으로 포커스를 돌린다. ↑↓·Return·Esc를 지원하며 검색/필터 변경은 음악을 변경하지 않는다.

검색 중 삭제·외부 변경 뒤 오래된 행은 현재 catalog와 project ID를 재검증해 거절한다. 다른 프로젝트를 열면 기존 session reset 동작으로 닫는다. 미연결 원본과 반복된 use, 공유 이펙트의 트랙별 경로 ID를 구별한다. 실제 이동은 기존 `navigateStudio`의 그룹 scene reveal·편집기 포커스·유효성 검사를 사용한다.

## 구현 경로와 검증

Core 새 `Sources/CirclrCore/StudioNavigationSearch.swift`와 `Tests/CirclrCoreTests/StudioNavigationSearchTests.swift`. UI `Sources/CirclrApp/StudioNavigationView.swift`와 `AppStore.swift`·`RootView.swift`, build 59 `Resources/Info.plist`. 필요한 QA helper·README/CHANGELOG·로드맵/기본 DAW 계획을 갱신한다. 기존 노드 모델·DSP·권한·미디어·사용자 앱은 변경하지 않는다.

자동: 선택된 대상과 이름이 일치하는 검색, 역할/섹션/트랙 필터, 동명·반복 use·공유 FX ID, Unicode·빈 결과·빈 섹션·순서·원본 불변성 Core 테스트. 관련 검사 → 기존 전체 Swift(장치 playback test 제외)·Python 26개 → release build.

Native: authored QA 사본에서 실제 이름/역할 검색 → MIDI/오디오/이펙트 직접 진입, 동일 역할 다중 버튼의 검색 진입, 필터·keyboard·Esc·빈 결과·현재 선택, 작은 창/열린 콘솔의 긴 경로, 숨은 그룹 진입, 편집 한 번 → 검색 이동 → Undo/Redo 유지, 저장·재열기·다른 use/원본 보존을 검사한다. 외부 삭제의 오래된 target은 Core/current catalog 검사와 기존 navigation validator를 대조한다. 실제 audio output/audition/마이크는 시작하지 않는다. 최종 QA 앱/소스 hash·Mach-O·kit·codesign 및 root/ports/user app 보존을 확인하고 source/docs/tests/QA helper만 private push한다.

## 구현과 검증 결과

0.20.0 build 59. 검색 catalog는 기존 탐색 revision 캐시에 정규화해서 보관한다. `2번 트랙`과 `2번 섹션`은 서로 다른 번호 조건이며 공백·전각 숫자를 허용한다. 검색 중 바뀐 행은 현재 project/catalog를 재확인한다. 열린 작업 검색은 배경 캔버스의 접근성 요소를 숨기고 검색만 조작하도록 한다. 현재 선택이 catalog에 없는 앨범/사운드에서는 현재 서클 찾기를 비활성화한다.

전체 Swift 429개·Python 26개, 마지막 캐시/포커스 정리 후 검색 6개와 release build가 통과했다. 13개 섹션·137개 경로에서 실제 이펙트/MIDI/오디오/빈 섹션 진입, 동명·반복 경로, 현재 찾기·필터·트랙 제한 해제, 숨은 그룹·음악 Undo/Redo·외부 이름 변경·저장 재열기를 검증했다. [상세 QA](../qa/direct-work-navigation-review.md)와 `qa/check-direct-work-navigation-evidence.py`가 실제 상태·source·package를 대조한다. 전체 DAW/물리 오디오 출고 완료를 뜻하지 않는다.
