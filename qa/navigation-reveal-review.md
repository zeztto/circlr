# build 57 접힌 그룹 작업 이동 검증

2026-09-09 · `codex/daw-integration`, baseline `82171e1e2cabd4b57e62fc4ae026836bbc21db23`. 개발 progress이며 전체 DAW/0.20 출고 완료가 아니다. [계약](../docs/71-navigation-group-reveal.md).

## 변경과 검토

선택의 상위 scope를 따라 포함 그룹 주소를 구한 뒤 scene에서만 펼친다. 작업 이동의 `mutate("작업 경로 펼치기")`와 layout override 작성은 제거했다. 화면 밖 그룹·다른 use의 동일 그룹 ID는 구별한다. 선택 변경은 scene cache를 갱신하고, 상위 복귀 camera는 현재 접힘 상태의 scene에서 계산한다. 저장된 내부 선택도 같은 검증/scene 경로로 복원한다. 명시적 그룹 접기/펼치기의 문서 편집과 Undo는 유지한다.

직전 실제 dispatch가 `agent thread limit reached`로 거절되어 순차 UI/UX → native Swift/Core utility → read-only code/security review → QA를 수행했다. 독립 에이전트 검토를 주장하지 않는다. 경로/ID·그룹 scope·공유 use·활성 편곡·캐시 무효화·삭제 후 선택 정규화·viewport 재열기를 검토했다. MCP focus는 숨은 유효 대상을 허용하며, 없는 대상의 원자적 거절은 Core의 scene 검증을 공유한다. 도구 인자·인증·권한·음악 schema·DSP 변경은 없다.

## 자동 검사와 패키지

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback` | 419개 / 0 실패, 25.500초 |
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --filter NavigationRevealTests` | 마지막 저장 선택 테스트 보강 후 6개 / 0 실패, 0.020초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.201초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` | 성공, 57.27초 |
| `python3 qa/check-navigation-reveal-evidence.py` | snapshot 15개·scene 3개·invalid focus 1개, AX/JPEG 각 19개, source hash 8개·kit 25개·Mach-O section 37개·strict codesign 통과 |

기존 `.build/automation-time-quality`의 증분 빌드는 이전 `HierarchySceneBuilder.build(Project)`를 참조한 `PortPlaybackAnalysisTests.swift.o`의 undefined symbol로 실패했다. `.build/navigation-reveal-quality`에서 깨끗한 전체 빌드를 수행해 통과했다. 실제 viewport의 선택을 encode/decode하도록 마지막 테스트를 보강하고 해당 6개를 다시 통과시켰다. 로그는 `.build/navigation-reveal-{tests,clean-tests,final-tests,python,release}.log`다. 최초 실패를 숨기거나 오래된 바이너리를 실행하지 않았다. 이후 같은 API 변경의 회귀 검사에는 새 quality scratch를 사용한다.

Core 검사 6개는 원본/이번 사용의 override 불변, 두 배치의 상위/다른 경로 복귀, 앨범·곡·섹션의 세 그룹 경로, 음악 Undo/Redo와 명시적 그룹 편집의 분리, 저장된 선택 복원, 없는 대상/선택하지 않은 편곡 거절을 검증한다. 기존 그룹/포트·음악 컴파일·PCM 검사를 포함한 전체 결과이며 제외한 물리 출력 검사나 녹음의 성공을 의미하지 않는다.

전용 앱 `qa/generated/navigation-reveal/써클러 통합 검증.app`: 0.20.0 build 57, bundle `com.circlr.integrationqa`, UUID `57F9EE62-04CD-379B-A7A4-3C65D534D149`. authored 두-use QA fixture ID `2CDF95C6-B58F-5C90-A6AE-EE96F03F0EE6`. 제품에 QA 음악·캡처·앱을 배포하지 않는다.

## Native 시나리오

| 작업 | 관찰 |
|---|---|
| 접힌 그룹에서 ⌘J → Return | 그룹 안의 검증 톤 1 오디오 편집기로 직접 이동. r14·dirty=false, 원본/이번 사용의 그룹은 계속 collapsed=true, Undo 명령 없음 |
| 오디오 위치 편집 | 표시 1→9.5박, 내부 0→8.5, 원본 0–32초 보존. r15 |
| 역할 버튼으로 출력 이동 | 그룹 밖 출력 1 편집기로 한 번에 이동. r15·dirty=false, scene에서 내부 오디오가 숨겨짐 |
| 한 번 Undo → 오디오 복귀 → Redo | r16에서 표시 1박. 역할 이동 뒤 Redo 명령이 유지되고 r17에서 표시 9.5박 복원. r18 Undo로 음악 baseline 복원 |
| Esc 상위 복귀 | 신스 그룹이 다시 접힌 상태로 표시되고 그룹 중심에 camera가 맞춰짐. 음악/그룹 문서 변경 없음 |
| 명시적 그룹 펼치기/Undo | 이번 사용의 그룹 collapsed=false, r18. 한 번 Undo r19에서 true로 복원. 원본과 두 번째 사용은 보존 |
| MCP focus | 접힌 그룹 안의 오디오를 궤도 편집기로 바로 열며 r19·dirty=false 유지. 다른 사용의 같은 그룹은 계속 접혀 있음 |
| 없는 대상 | 현재 선택·문서·revision·보기·dirty를 보존하며 오류 반환 |
| 저장·종료·재열기 | 그룹은 파일에서 collapsed=true, 선택은 내부 오디오다. 재실행 시 같은 내부 편집기와 viewport 전체 값이 복원됨. Esc로 나오면 그룹은 다시 접힘 |
| 초기 상태 복원 | 모든 음악·그룹·실제 배치·보기 설정을 baseline으로 복원하고 r19로 저장. 전용 앱 세 실행 모두 종료 |

자유/궤도 편집 화면, 선택·역할 버튼·숫자·Esc 복귀와 작은 창(1024폭/캔버스 673높이)의 콘솔 공존을 AX/JPEG로 확인했다. `explicit-open.ax.txt`는 메뉴 선택 직후의 중간 표시이고, 실제 펼친 화면은 `explicit-open-settled.ax.txt` 및 문서 snapshot으로 확인했다.

마지막 보기 메뉴 선택 직후 같은 CUA 호출에서 보낸 ⌘S는 dirty를 해제하지 않았다. 해당 사본은 MCP로 저장했다. 추가 실행에서는 메뉴가 닫혔음을 fresh AX로 확인한 뒤 ⌘S를 보냈고 dirty=true→false와 파일 저장을 두 번 확인했다. 일반 저장은 통과했으며 메뉴 전환 중 초고속 연속 입력은 도구 타이밍과 실제 사용자 재현을 구별할 후속 항목이다.

## 보존·남은 범위

snapshot은 음악 revision·viewport·circleLayout을 제외한 전체 문서를 비교하고, 보기 값도 별도로 검사한다. 오디오 한 구간/명시적 그룹 편집 외 변경이 없고 최종에는 모두 baseline이다. 원본 `studio.circlr` SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 두 오디오 checksum·기존 라이브러리 등록 1개·root `d88ea5d`·ports `1d304eb`·사용자 앱 0.19.0 build 21을 보존했다. 최종 task-owned QA 프로세스는 0이다.

출력·audition·마이크 시도는 0이다. HAL 지연, 실제 녹음/재생 중 경로 이동, VoiceOver 발화, 모든 다중 선택·접힌 상위 악장 조합의 native 검증은 이 결과에 포함하지 않는다. 파일·snapshot·Core 세 겹 경로 검사는 native 전체 조합을 대신하지 않는다. 다음 UI 작업은 긴 트랙 목록/가져오기 대상의 선택 깊이와 이동 중 키보드 포커스를 함께 다룬다.
