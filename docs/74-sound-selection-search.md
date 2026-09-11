# 음색과 Audio Unit 직접 검색

session-bootstrap-v1: development-lead, baseline=e12bf43, branch=codex/daw-integration. 이번 사용자 요청에 따라 read-only selector audit를 실제 dispatch했으나 `agent thread limit reached`로 실패했다. delegation=none, UI/UX → native Swift/Core utility → read-only review → QA를 순차 수행한다.

## 계약과 범위

악기 종류 → 음색 또는 긴 Audio Unit 메뉴의 두 단계를 같은 캔버스 검색으로 합친다. 내장 신스 10개, 기존 Sound Bank 모드, 실제 설치된 AU 악기를 직접 선택한다. 음악 서클/전역 이펙터는 AU 효과만 검색한다. 이름·제조사·종류를 Unicode 정규화해 검색하며 현재 음색, 종류 필터, 결과 수, 전체 이름/제조사, ↑↓·Return·Esc를 제공한다. 검색은 850×560 overlay이고 별도 NSWindow나 고정 패널이 아니다. 샘플 파일 열기와 GM Program 편집은 기존 경로를 유지한다.

같은 신스 음색이나 AU를 다시 선택하면 수정한 SynthPatch/PluginDescriptor.state를 보존한다. 새 신스 음색은 해당 SynthPatch 기본값을 적용하고, 새 AU는 현재 설치 catalog의 descriptor를 적용한다. 다른 종류를 거쳐 이전 음색으로 돌아오는 경우 비활성 상태로 보관된 동일 voice/plugin ID의 설정을 재사용한다. 사용자가 모드를 바꿔도 비활성 Instrument 설정은 유지한다. 선택 한 번은 음악 transaction 한 번이며 재선택/검색/취소는 Undo를 만들지 않는다. AU를 선택할 때만 종류와 descriptor를 함께 적용한다. 목록 조회/선택은 플러그인 인스턴스·미리듣기·물리 장치를 시작하지 않는다.

기존 NumberEditIdentity의 프로젝트/세션/음악 revision/대상/원본 범위를 고정한다. 녹음·준비·import 중 또는 다른 대상/내용으로 바뀐 요청은 적용하지 않고 다시 열도록 안내한다. 현재 설치 목록에 없는 저장된 AU는 현재 이름과 미설치 상태를 표시하되 가용 결과로 만들지 않는다.

## 소유 경로와 검증

Core: 새 SoundSelection.swift와 SoundSelectionTests.swift. Audio: AudioUnitHost.swift의 비영속 제조사 metadata 조회. App: 새 SoundPickerView.swift와 AppStore, RootView, InspectorView, InlineCircleEditor, EffectControls, EditorView, MediaLibraryView, StudioNavigationView, CanvasCommands, AlbumCanvas, CanvasFileDrop. Resources/Info.plist build60, README/CHANGELOG, docs/25-development-roadmap.md·docs/31-daw-basics-plan.md, QA helper와 보고서. 프로젝트 schema/DSP/권한/원본 앱과 사용자 음원은 보존한다.

Core 검색·종류 분리·동명 식별·미설치·전체 patch/state 보존·기본값·불변성 테스트 후 `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release build를 실행한다. 물리 playback test의 기존 HAL 환경 한계는 별도로 유지한다.

Native QA 사본에서 신스 검색/선택·같은 음색 재선택·Undo/Redo·AU 제조사 검색/선택·서클/전역 효과 검색·취소·오래된 revision 거절·저장 재열기를 수행한다. 작은 창과 콘솔이 열린 화면을 AX/스크린샷으로 검증한다. 최종 source hash/Mach-O/codesign/kit과 root/ports/user app 보존을 확인하고 승인된 private 저장소에 소스·문서·테스트·QA helper만 push한다.

## 구현 결과와 사용법

0.20.0 build 60. 음색 편집기의 `음색·악기 찾기`, 이펙트 편집기의 `Audio Unit 이펙트 찾기`에서 열린다. ⇧⌘P에서 같은 명령을 검색해 Return으로 진입할 수도 있다. 내장 신스·Sound Bank·AU 악기를 필터링하고 이름/제조사를 입력한다. ↑↓는 결과 이동, Return은 적용, Esc는 취소다. `현재 음색 찾기`는 검색/필터를 해제하고 현재 항목으로 돌아간다. 악기는 해당 트랙의 모든 섹션에 적용되며 이 범위를 상단에 표시한다.

AU effect는 종류와 descriptor를 하나의 변경으로 적용하고, 검색 취소는 기존 효과 종류를 유지한다. 설치된 AU 목록은 앱 시작 시 조회한다. 새 플러그인을 설치한 경우 앱을 다시 열어 목록을 갱신한다. 기존 Sound Bank 프로그램 번호/드럼 제어와 샘플 파일 흐름은 유지했으며, GM 프로그램 이름 검색은 후속 작업이다.

최초 관련 7개, 최종 관련 8개를 포함한 전체 Swift 437개, Python 26개, 최종 release 18.74초, 실제 앱 상태 23개와 AX/화면 20개, source 15개·Mach-O 37개·Codex kit 25개와 strict codesign 검증이 통과했다. [검증 보고서](../qa/sound-selection-review.md). 저장된 plugin state 보존은 생성한 plist fixture로 확인했으며, 플러그인 자체 UI/재생·장치 출력 검증과 구별한다.
