# build 58 오디오 대상 트랙 검색 검증

2026-09-09 · `codex/daw-integration`, baseline `89c53d9de44a3cac310189d3ca8ef087c802eb73`. 개발 progress이며 전체 DAW/0.20 출고 완료가 아니다. [계약](../docs/72-library-track-search.md).

## 변경과 검토

오디오 단일 파일의 대상 트랙 메뉴를 기존 850×560 라이브러리 안의 검색 목록으로 전환했다. 이름/번호 Unicode 검색은 원래 프로젝트 순서를 유지한다. 각 행은 해당 섹션의 오디오 구간/MIDI 노트 수, 전체 이름 AX/help, 현재 대상 표시를 제공한다. 목록 재진입은 현재 대상까지 스크롤한다. 선택한 뒤에도 번호가 남아 동명 트랙을 구별한다. 새 트랙과 삭제된 ID를 같은 표시로 처리하지 않는다.

선택 화면을 열 때 `MediaImportRequest`와 단일 오디오 entry ID를 고정한다. project/revision/generation/선택/destination/workspace/파일 집합이 달라지면 적용을 거절한다. `AudioImportPlacement.track`은 기존 섹션·시작 박·좌표·원본/이번 사용을 유지하며 ID와 범위를 다시 검증한다. 선택은 import나 음악 mutation을 호출하지 않는다. track chooser에서 preview를 시작하지 않으며 파일 접근·검증·실제 import는 기존 경로를 사용한다.

서브 에이전트 재시도가 실제 `agent thread limit reached`로 거절됐다. UI/UX → native Swift/Core utility → read-only code/security review → QA를 순차 수행했다. 독립 에이전트 검토를 주장하지 않는다. 검색 입력은 문자열 비교에만 사용하며 파일 경로/셸/네트워크 실행에 전달하지 않는다. QA packager는 선언된 authored 원본을 복사한 새 사본만 확장하고 기존 앱/fixture 존재 시 거절한다. 원본 파일·권한·MCP 인증·DSP/schema 변경은 없다. 검토에서 수정이 필요한 잔여 결함은 확인하지 못했다.

## 자동 검사와 패키지

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback` | 423개 / 0 실패, 24.792초 |
| `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --filter AudioImportPlacementTests` | 최종 표시 보완 후 9개 / 0 실패, 0.005초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.207초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` | 최종 성공, 58.84초 |
| `python3 qa/check-library-track-search-evidence.py` | snapshot 9개, AX/JPEG 각 13개, source hash 6개·kit 25개·Mach-O section 37개·strict codesign 통과 |

로그는 `.build/library-track-search-{tests,final-tests,python,release,final-release}.log`. QA 앱은 `qa/generated/library-track-search/써클러 통합 검증.app`, UUID `94522033-F840-3C34-8A26-719036D6C312`. `prepare-library-track-search-qa.py`는 원본 3트랙에 빈 authored QA 트랙 96개를 추가한다. 97/98은 동명, 99는 긴 한글 이름이며 production 콘텐츠로 넣지 않는다.

## 실제 앱 근거

1. 1024 너비의 작은 창과 열린 콘솔에서 파일 `Nordic pad.wav`를 검색하고 시작 9.5박을 입력했다. 대상 목록은 새 트랙을 포함해 100개 결과, 기존 2번 선택·오디오/MIDI 사용량을 표시했다.
2. 전각 `ＮＯＲＤＩＣ`과 분해된 한글 `패드` 검색은 97/98 두 결과를 반환했다. ↓·Return으로 98번을 선택한 뒤 파일 검색어/선택/9.5박이 남고 r14·99트랙·2asset·clean 상태를 유지했다. 재진입은 98번 선택과 스크롤 끝을 보여줬다.
3. 99번 검색·Return 및 클릭 선택, 전체 이름 AX/help, 빈 결과에서 Return 무동작, Esc 복귀, 명시적 새 트랙 선택을 확인했다. 모든 경우 파일 목록의 시작 박과 검색을 유지했다.
4. chooser가 열린 동안 MCP rename으로 r15를 만들었다. 행이 비활성화되고 Return도 적용하지 않았다. 전후 음악 manifest가 같았다. rename Undo r16 후 대상 갱신으로 복구했다.
5. 기존 99번 트랙에 오디오를 실제 가져왔다. r17, 트랙 99개·asset 3개, 해당 use에 audio lane과 mix/output 연결만 추가됐다. 클립은 raw beat 8.5(표시 9.5박), sourceStart 0, source duration 32초다. 원본 섹션·다른 use·기존 연결·보기 설정을 전체 문서 비교로 보존 확인했다. 이 검사는 섹션 길이 확장을 요청하지 않았다.
6. ⌘Z 한 번으로 r18의 원래 음악을 복구하고 ⇧⌘Z로 r19의 같은 import ID/연결/asset을 복원했다. 저장 후 앱을 종료·재실행해 열었고 저장된 manifest와 정확히 같았다. Redo 이후 선택은 섹션이며 재열기도 그 저장 선택을 유지했다.
7. 앱 종료를 확인한 뒤 QA fixture의 manifest만 캡처한 초기 99트랙 baseline으로 복구했다. 이 최종 정리는 제품 Undo 검증과 별개인 QA 파일 정리다. 가져온 QA 파일은 참조 없이 보존하며 원본은 수정하지 않았다.

원본 `studio.circlr` manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`. root/ports HEAD와 사용자 `dist/써클러.app` 0.19.0 build 21을 보존했고 소유 QA 프로세스는 0개다. 소스·문서·테스트·QA helper만 Git에 포함한다.

## 남은 범위

이 변경은 트랙 선택 UI다. 실제 출력/audition/마이크를 시작하지 않았고 물리 오디오 시도는 0이다. 기존 HAL 지연, 정상 출력/청감·녹음·전체 DAW 출고 조건은 해결됐다고 주장하지 않는다. VoiceOver 발화와 refresh 도중 디스크 분리의 실제 경쟁은 미검증이다. 원본/이번 사용의 표시 차이는 Core 테스트, 이번 사용에 실제 가져오기는 native에서 확인했다. 사용 중인 앱 교체는 별도 전달 조건을 따른다.
