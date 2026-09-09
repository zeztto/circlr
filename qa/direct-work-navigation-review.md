# build 59 섹션·서클 직접 검색 검증

2026-09-09 · `codex/daw-integration`, baseline `85aa024d47ea815d664fe9364c3e7169e2af1c92`. 개발 progress이며 전체 DAW/0.20 출고 완료가 아니다. [계약](../docs/73-direct-work-navigation.md).

## 변경과 검토

⌘J의 결과를 트랙별 primary 대신 실제 섹션·서클로 바꿨다. 섹션은 긴 메뉴 대신 검색 결과와 전체 앨범/이 섹션 필터로 찾는다. 종류별 버튼은 MIDI/오디오/음색/이펙트/라우터/믹스/출력을 직접 제한한다. 같은 역할의 여러 서클 버튼은 섹션·트랙·종류가 고정된 목록을 열고, 트랙 제한도 해제할 수 있다. 빈 섹션·긴 이름·반복 use·공유 FX의 트랙 경로는 별도 ID와 번호로 구별한다.

Core catalog는 actual routes와 track order를 사용하며 프로젝트를 수정하지 않는다. 정규화된 검색 문자열은 기존 hierarchy revision 캐시에서 갱신된다. 명시적인 `2번 트랙`과 `2번 섹션`은 해당 필드만 비교한다. 일반 단어 검색은 경로/이름/역할에 모두 적용되므로 숫자만 입력하면 여러 경로가 일치할 수 있다. 결과에는 실제 대상 이름과 경로가 표시된다.

행을 열 때 project ID와 현재 필터된 catalog의 ID를 확인하고 기존 scene validator/그룹 reveal/편집기 포커스를 사용한다. 다중 경로의 ID는 destination과 track ID로 구성한다. 검색/필터는 음악·Undo를 호출하지 않으며 외부 변경 뒤 삭제된 행을 그대로 적용하지 않는다. 이름/번호는 문자열 검색에만 사용하고 파일 경로·네트워크·셸에 전달하지 않는다. 권한·MCP 인증·DSP·음악 schema 변경은 없다.

직전 실제 sub-agent 요청이 thread limit으로 실패했고 이번 실행도 1 slot이므로 UI/UX → native Swift/Core utility → read-only code/security review → QA를 순차 수행했다. 독립 에이전트 검토를 주장하지 않는다. 수정할 잔여 고신뢰 결함은 확인하지 못했다.

## 자동 검사와 실패 수정

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback` | 429개 / 0 실패, 25.668초 |
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --filter StudioNavigationSearchTests` | 마지막 캐시/포커스 정리 후 6개 / 0 실패, 0.018초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.228초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` | 최종 성공, 54.74초 |
| `python3 qa/check-direct-work-navigation-evidence.py` | snapshot 15개, AX/JPEG 각 22개, source hash 5개·kit 25개·Mach-O section 37개·strict codesign 통과 |

첫 focused build는 다중 역할 버튼의 SwiftUI 표현식을 type-check하지 못했다. 버튼을 작은 helper로 나눈 뒤 컴파일됐다. 이어 `2번 트랙` 검색에 `2번 섹션`의 다른 트랙이 섞이는 테스트 실패를 발견했다. 숫자 조건을 필드별로 해석하고 2/12 구별·전각 숫자/띄어쓰기 검사를 보강해 통과했다. 현재 서클 찾기 뒤 query change가 강조를 첫 행으로 덮지 않도록 비어 있는 검색은 현재 선택을 다시 찾는다.

로그는 `.build/direct-work-navigation-{focused-tests,focused-retry,focused-final,tests,python,release,final-tests,final-release}.log`. 최초 실패와 수정 후 통과를 구별한다. 최종 QA 앱은 `qa/generated/direct-work-navigation/써클러 통합 검증.app`, UUID `FDDCEE6C-8CAD-3685-8B95-34EAC7D549AE`다.

## 실제 앱 검증

- 원본 authored 프로젝트를 새 사본으로 복사하고 13개 use(12개 반복·마지막 빈 브리지)를 구성했다. 11/12는 같은 긴 이름이다. 별도 QA 사본에 MCP로 동명 Reverb/Delay 두 개를 한 transaction으로 추가해 r15 baseline을 저장했다. 실제 source 원본에는 추가하지 않았다.
- 1024 너비·열린 콘솔에서 137개 대상과 현재 오디오 강조/스크롤, 검색·종류·범위 고정 배치를 확인했다. overlay에는 배경 캔버스 AX가 섞이지 않는다. 빈 결과에서 Return은 이동하지 않고 현재 서클 찾기는 원래 선택과 검색 포커스를 복원한다.
- 전각 `ＮＯＲＤＩＣ`·분해된 한글 공간·`2번 트랙` 검색은 해당 트랙 경로의 이펙트 1/2·2/2를 반환했다. ↓·Return으로 실제 Reverb를 열고 트랙 경로 2를 유지했다. 기존 트랙 primary MIDI로 이동하지 않았다.
- Reverb 공간 크기 20→37%를 직접 편집해 r16을 만들었다. 이펙트 검색 버튼은 이 섹션/2번 트랙/이펙트·2개 결과를 열었다. ↑·Return으로 Delay에 진입한 뒤 ⌘Z로 Reverb 값만 되돌렸다(r17).
- 검색으로 접힌 그룹의 검증 톤 1에 진입하고 ⇧⌘Z로 같은 Reverb 편집을 복원했다(r18). 그룹의 collapsed 상태·다른 use·원본·기존 음악/라우팅은 유지했다. ⌘Z로 다시 원래 값을 복원하고 MIDI/이 섹션 필터·Return으로 MIDI 스텝 편집기에 직접 들어갔다(r19).
- 빈 브리지 검색은 한 개의 섹션 결과를 반환했고 Return으로 해당 use에 진입했다. 긴 동명 섹션은 11/12번을 표시했다. ↓·Return으로 12번을 연 뒤 이 섹션/오디오 필터·Return으로 그 use의 검증 톤 1에 들어갔다. 필터 이후 검색 입력 포커스를 확인했다.
- 열린 `Nordic 공간` 검색 중 MCP로 Reverb를 별빛 잔향으로 바꿨다(r20). 공유 경로 네 결과가 Delay 두 결과로 갱신됐다. Undo r21에서 네 결과로 돌아왔다. 트랙 제한 해제도 2→4경로와 포커스 복귀를 확인했다. Esc는 해당 작업 화면으로 돌아간다.
- 실제 편집/이름 변경을 Undo한 음악과 최초 오디오 선택을 저장했다. 앱을 종료·재실행해 열었고 manifest·selection·오디오 파형 편집 포커스가 그대로 복원됐다. 최종 r21의 음악 문서는 r15 baseline과 같다. 추가된 두 이펙트는 재현용 QA fixture의 일부로 보존한다.

원본 `studio.circlr` manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`. root/ports HEAD와 사용자 `dist/써클러.app` 0.19.0 build 21을 보존했다. 종료 후 소유 QA 프로세스는 0개이며 소스·문서·테스트·QA helper만 Git에 포함한다.

## 남은 범위

물리 output/audition/마이크 시도는 0이다. 기존 HAL 대기, 실제 출력/청감·녹음·전체 출고는 이 UI 검증으로 해결된 것으로 취급하지 않는다. VoiceOver 실제 발화, 보관한 AX 객체의 삭제 후 callback, 여러 앨범 전체 규모의 성능 수치는 미검증이다. 유효하지 않은 대상의 거절은 Core scene 검사와 현재 catalog guard를 검토했다. 이름 변경 중 목록 갱신은 native에서 확인했다. 사용 중인 앱은 교체하지 않았다.
