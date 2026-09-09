# 라이브러리의 대상 검색과 시작 위치

`session-bootstrap-v1`: owner=development-lead; baseline=74cc43f; branch=codex/daw-integration; delegation=none (실제 1-slot 제한). build 53 구현·native QA·private push는 progress다. UI/UX → native Swift/Core utility → 읽기 전용 code/security review → QA로 진행한다.

## 사용 흐름과 계약

기존 대상 섹션 메뉴는 길고 선택 시 캔버스를 이동하며 시작 박을 수정할 수 없다. 샘플 선택→섹션 검색→트랙/시작 박 지정→가져오기를 기존 850×560 overlay 안에서 완료한다. 별도 창이나 dock를 추가하지 않는다.

- `대상 섹션`은 같은 overlay의 검색 목록으로 전환한다. 곡 경로·섹션 이름을 검색하고 ↑↓/Return 또는 클릭으로 대상을 고른다. Esc/파일 검색은 취소·복귀하며 샘플 검색어와 다중 선택을 유지한다. 빈/중복 이름은 경로와 실제 섹션 ID로 구별한다.
- 섹션 선택은 library request만 바꾸고 캔버스·음악·Undo를 바꾸지 않는다. 새로 고른 섹션은 이번 사용·새 트랙·첫 박을 기본으로 한다. 가져오기 성공 뒤 기존 focus 경로로 해당 섹션/서클을 보여준다.
- 시작 박은 1 기반/4분음표 기준 숫자로 직접 입력하며 현재 마디·초와 섹션 길이를 함께 표시한다. 초기 request의 현재 위치/공유 원본 범위는 유지한다. 단일 오디오는 기존 트랙/새 트랙을 고르고 다중 오디오는 각 새 트랙이다. MIDI는 같은 시작 박을 기존 노트 트랙 선택 화면에 전달한다. 패턴의 시작 위치도 해당 loop 길이 안에서 검증한다.
- 음악/project/revision/선택/generation 변경 뒤의 request·숫자 작성·대상 callback을 거절한다. 입력은 대상·시작 위치의 초안이며 음악 mutation을 만들지 않는다. 범위 밖/NaN·무한값/없는 섹션·트랙은 거절한다. 실제 batch는 기존 원자적 staging/Undo/파일 scope를 따른다.
- 대상 검색 중 preview를 막는다. 숫자 확정/취소 뒤 파일 검색으로 포커스를 돌리고 다음 Return으로 가져올 수 있어야 한다. 원본 파일·다른 use·사용자 앱은 보존한다.

## 소유와 검증

Core: `AudioImportPlacement.swift`, `AudioImportEditing.swift`의 destination Equatable, 전용 테스트. App: `CommittedNumberField.swift`의 선택적 의미 검증 hook, `MediaImportWorkspace.swift`의 request Equatable, `MediaLibraryController.swift`의 overlay/focus 상태, `MediaLibraryView.swift`, 새 `MediaLibraryPlacement.swift`. build 54, README/CHANGELOG/로드맵·QA 도구/기록을 갱신한다. schema·외부 API·인증·구매는 없다.

Core 검사: 변박·tempo map·부분 패턴 clock, 시작 범위와 destination 보존, 없는 ID/부적합 트랙, 섹션 Unicode/경로 검색과 순서. 명령은 `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native: 두 use의 authored QA 사본과 샘플을 사용한다. 섹션 검색/취소·확정 뒤 캔버스/음악 보존, 숫자 입력/취소/범위 오류/외부 revision 거절, 다른 use의 시작 박에 import→한 Undo→저장/재열기를 검증한다. 작은 창·콘솔의 표시, 소스/app/kit/codesign·원본 checksum·root/ports/사용 앱 보존을 검사한다. 실제 출력/audition/마이크는 시작하지 않는다. 검증된 소스·문서·테스트·QA 도구만 승인된 private branch에 commit/push한다.

## 검증 결과와 사용법

build 54 최종 native 앱에서 섹션 검색·숫자 입력·오디오/MIDI/batch·Undo·저장 복원을 확인했다. 전체 Swift 401개와 Python 26개, 최종 숫자/배치 관련 Swift 13개가 통과했다. [QA 기록](../qa/library-placement-review.md).

1. ⌥⌘L로 라이브러리를 열고 파일을 선택한다. `대상 섹션…`에서 곡 경로나 섹션 이름을 검색한다.
2. ↑↓와 Return으로 섹션을 정한다. Esc는 검색 취소이며 파일의 검색어와 선택을 유지한다. 섹션을 새로 고르면 새 트랙·첫 박·이번 사용이 기본이다.
3. `시작`은 1 기반 4분음표 박이다. 예를 들어 9.5는 내부 8.5박 위치다. Return으로 확정하고 Esc로 작성만 취소한다. 확정 뒤 파일 검색에 돌아오며 다음 Return이 가져오기다.
4. 단일 오디오는 오른쪽에서 기존 트랙/새 트랙을 선택한다. MIDI는 `MIDI 트랙 선택`에서 사용할 노트를 확인한다. 여러 오디오는 각 새 트랙의 같은 위치에 들어간다.
5. 외부 변경으로 대상이 오래되면 섹션을 다시 고른다. `대상 갱신`은 현재 캔버스 선택을 사용하므로 앞서 별도로 정한 섹션을 유지하는 명령이 아니다.

섹션 끝과 같은 시작 박은 거절하고 정확한 길이 안내를 입력란에 표시한다. 첫 native 후보에서 숫자 범위 상한의 반올림이 경계를 모호하게 보이게 해, 공통 숫자 입력의 선택적 의미 검증으로 수정했다. 다른 숫자 입력은 기본 동작을 유지한다.

2026-09-09 사용자의 한도 해제 안내 뒤 독립 read-only 검토를 다시 dispatch했으나 `agent thread limit reached`로 실패했다. 실제 독립 검토를 주장하지 않으며 순차 코드/보안 검토→QA를 적용했다. 실행된 source-built 앱은 정상 종료했다. 실제 장치 출력·마이크·VoiceOver 발화는 이번 범위에서 검증하지 않았다.
