# 라이브러리 폴더 관리와 오류 복구

`session-bootstrap-v1`: owner=development-lead; baseline=e41983c; branch=codex/daw-integration; delegation=none (직전 실제 dispatch가 1-slot 한도로 거절됨). build 52 private push는 progress다. UI/UX → native Swift utility → 읽기 전용 security/code review → QA를 순차 수행한다.

## 사용자 흐름과 수락 기준

현재 같은 이름의 등록 폴더는 필터/제거 메뉴에서 구별되지 않고, 해소한 혼합 선택 오류가 다음 단일 선택에도 남는다. 폴더 관리는 하위 메뉴에서 경로를 볼 수 없어 잘못된 등록을 정리하기 어렵다. 기존 850×560 라이브러리 overlay 안에서 파일 검색과 폴더 목록을 전환한다. 별도 창/좌우 dock를 추가하지 않는다.

- 상단 `폴더 관리 · N` 버튼은 경로·파일 수·읽기 상태와 `파일 보기`/`등록 해제`를 표시하는 목록으로 직접 이동한다. `파일 검색`으로 돌아가면 기존 query/형식/선택을 유지한다. 폴더의 `파일 보기`는 그 폴더를 필터링하고 검색어를 비워 실제 내용을 보여준다. 추가 폴더는 기존 native panel로 선택한다.
- 동명 폴더의 필터/검색 결과는 서로 구분되는 최소 경로 suffix를 표시한다. 미해결 bookmark/같은 경로 등으로 경로만으로 구별할 수 없으면 명시적인 등록 번호를 붙인다. 전체 로컬 경로는 폴더 관리 행과 help에 표시하고 MCP/프로젝트에는 내보내지 않는다.
- 등록 해제는 목록과 선택을 정리하며 디스크 파일이나 프로젝트의 imported asset을 지우지 않는다. 읽기 상태는 폴더별로 보이고 scan 경고는 선택/입력 오류와 분리한다. 선택·필터 수정은 transient 오류만 지운다. 같은 mixed 오류를 footer와 notice에 중복 표시하지 않는다.
- 폴더 관리로 이동하면 preview를 취소한다. 비동기 scan의 generation·취소·bookmark scope 및 기존 batch/Undo/원본 보호는 유지한다. 파일 정체성/등록 ID/schema는 바꾸지 않는다. 중첩 루트 catalog dedup·폴더 감시·Splice remote/file promise는 후속이다.

## 소유와 검증

`Sources/CirclrAudio/MediaLibraryFolderDisplay.swift`와 전용 테스트는 순수 표시 계산을 소유한다. `MediaLibraryController.swift`는 비동기 경로/폴더 상태·독립 notice, `MediaLibraryView.swift`는 같은 overlay의 폴더 관리와 명시적 동작을 소유한다. build 53, README/CHANGELOG/로드맵·QA wrapper/checker를 함께 갱신한다. 인증/네트워크/추가 라이선스 구매는 없다.

테스트: 최소 suffix·깊은 동명 parent·이름 Unicode 정규화·없는 경로·동일 경로 fallback. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native: authored 동명 폴더 두 개 등록→경로/개수/필터 구분→다중 선택 유지 왕복→MIDI 혼합 수정 시 오류 제거→등록 해제 뒤 원본/프로젝트 보존. 작은 창·열린 콘솔에서 조작과 안내가 보여야 한다. 실제 출력/audition/마이크는 시작하지 않는다. 현재 소스와 app/kit/codesign·fixture checksum·source/root/ports/user app 보존을 검사하고 승인된 private branch에 소스·문서·테스트·QA 도구만 commit/push한다.

## 전달 결과

build 53은 Swift 396개·Python 26개, 실제 동명 폴더 등록/관리·검색 왕복·오류 복구·imported 음악 보존·Undo/재열기와 최종 패키지 검사를 통과했다. 첫 후보의 경고/파일 수 표시와 관리 화면 Escape를 보강했다. [실행 기록과 미검증 범위](../qa/library-folders-review.md)를 따른다. 기존 사용자 앱 출고와 장치/마이크 검사는 이 변경으로 완료된 것이 아니다.
