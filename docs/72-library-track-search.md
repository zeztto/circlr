# 라이브러리의 오디오 대상 트랙 검색

`session-bootstrap-v1`: owner=development-lead; baseline=89c53d9; branch=codex/daw-integration; delegation=none (현재 1-slot 및 직전 실제 dispatch 거절). UI/UX → native Swift/Core utility → read-only code/security review → QA를 순차 수행한다.

## 계약

단일 오디오의 대상 트랙 메뉴를 같은 라이브러리 overlay의 검색 목록으로 바꾼다. 트랙 이름·번호를 Unicode 정규화/대소문자 무시로 검색하고, 프로젝트 순서의 번호와 해당 대상 섹션의 오디오 구간/MIDI 노트 수를 표시해 동명 트랙을 구별한다. 긴 이름은 두 줄과 전체 접근성/도움말로 확인한다. 새 트랙도 명시적인 선택 항목이다. ↑↓·Return·클릭으로 지정하고 Esc는 파일 목록으로 돌아간다.

선택은 import request의 trackID만 바꾸며 시작 박·섹션·좌표·원본/이번 사용 범위, 파일 검색어·선택을 유지한다. 캔버스·음악·Undo는 바꾸지 않는다. 고르기 시작한 request와 단일 오디오 ID를 고정하고 project/revision/generation/선택/request/파일이 바뀌면 적용을 거절한다. 오래된 대상은 파일 목록에서 갱신하도록 표시한다. 검색 중 preview는 금지하고 Return 선택이 곧바로 실제 import를 실행하지 않도록 포커스를 분리한다. MIDI/다중 오디오의 기존 새 트랙 정책은 보존한다.

## 범위와 검증

Core: `Sources/CirclrCore/AudioImportPlacement.swift`, `Tests/CirclrCoreTests/AudioImportPlacementTests.swift`. App: `Sources/CirclrApp/MediaLibraryController.swift`, `MediaLibraryPlacement.swift`, `MediaLibraryView.swift`, 새 `LibraryTrackChooser.swift`. build 58과 README/CHANGELOG/roadmap/DAW 계획, QA helper/기록을 갱신한다. Schema/MCP/DSP/권한·외부 연결 변경은 없다.

자동 검사: `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native: authored 두-use·많은 트랙 QA 사본에서 이름/번호·동명/긴 이름·빈 결과·현재 선택·키보드/취소·Esc/Return 포커스·오래된 revision 거절을 확인한다. 기존 로컬 QA 오디오를 선택 트랙·fractional 시작 박에 실제 import→한 Undo/Redo→저장/재열기로 검증하고 새 트랙 전환과 다른 사용 보존을 확인한다. 작은 창·콘솔과 파일 목록의 선택/검색 유지, 소스/앱/kit/codesign·원본/사용자 앱/root/ports HEAD를 대조한다. 출력/audition/마이크는 시작하지 않는다. 검증한 source/docs/tests/QA helper만 승인된 private branch에 commit/push한다.

## 구현·검증 결과

0.20.0 build 58. 선택 후 footer/도움말도 `번호 · 이름`을 사용한다. nil은 새 트랙, 삭제된 ID는 삭제된 트랙으로 구별한다. 독립 read-only 검토를 다시 dispatch했으나 실제 `agent thread limit reached`로 거절되어 순차 검토했다.

전체 Swift 423개·Python 26개, 최종 표시 보완 후 해당 Swift 9개와 release build가 통과했다. 99개 트랙의 native 검색·번호/동명·현재 대상 스크롤·긴 이름·빈 결과·키보드/클릭·취소·revision 충돌, 9.5박 실제 오디오 가져오기와 한 Undo/Redo, 저장·재열기를 확인했다. 음악·원본/다른 사용 보존과 최종 소스/패키지는 [QA 기록](../qa/library-track-search-review.md) 및 `qa/check-library-track-search-evidence.py`가 대조한다.
