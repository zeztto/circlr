# build 54 라이브러리 가져오기 위치 검증

2026-09-09 · `codex/daw-integration`, baseline `74cc43f7e4b6ce7c14bd06cc3325fdb619e702dc`. 상태는 개발 검증 progress이며 0.20 전체 출고 완료가 아니다. [사용 흐름과 범위](../docs/68-library-import-placement.md).

## 변경과 검토

라이브러리의 대상 메뉴를 같은 overlay의 섹션 검색으로 바꾸고 시작 박·마디·초·트랙을 footer에서 지정한다. 새로운 창·dock·프로젝트 schema·외부 endpoint·권한·구매는 없다. 섹션 선택은 request만 갱신하며 전역 편집 선택·음악·카메라를 보존한다. 프로젝트/revision/generation/선택/request/숫자 identity guard가 기존 파일 staging과 원자적 import 앞에 적용된다. 단일 오디오·MIDI·batch 경로를 실제로 검사했다.

순차 native utility → read-only code/security review → QA로 진행했다. 사용자 안내 후 독립 read-only 검토를 요청했지만 `agent thread limit reached`가 반환됐다. 독립 검토 결과로 기록하지 않는다. 파일 scope 수명과 size/type 제한, 샘플 경로 노출 범위, stale request의 무시와 staging 실패 cleanup을 소스로 재검토했다. 이번 변경에서 추가 고확신 결함은 발견하지 못했다.

## 빌드와 자동 검사

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback` | 401개 / 0 실패, 25.388초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.215초 |
| 최종 `--filter 'NumberEditSessionTests\|AudioImportPlacementTests'` | 13개 / 0 실패, 0.004초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` 최종 | 성공, 28.16초 |
| `python3 qa/check-library-placement-evidence.py` | snapshot 17개(최종 앱 13개), 최종 AX 17개·JPEG 17개, source hash 8개, kit 25개, Mach-O section 37개, strict codesign 통과 |

Core 검사는 변박·tempo map·부분 길이 패턴, finite/exclusive-end 경계, 없는 섹션/트랙, 범위/원본/배치 보존과 경로·Unicode 검색을 다룬다. 장치 출력 검사를 제외한 수치이며 물리 재생을 대신하지 않는다. 로그는 `.build/library-placement-{tests,python,final-numbers,final-release}.log`에 있다.

첫 release에서 immutable `NumberEditIdentity` 필드 대입이 컴파일 실패했고 전체 identity 생성으로 수정했다. 첫 native 후보는 길이 끝 65박 입력을 올바르게 거절했으나 숫자 안내가 상한을 반올림해 `1–65`로 보였다. 선택적 숫자 검증 hook을 추가해 최종 앱에서 `시작 위치는 대상 섹션 또는 패턴의 길이 안으로 지정하세요`를 확인했다. invalid 초안/포커스는 유지하며 실제 위치는 바뀌지 않는다.

## Native 시나리오

최종 앱 `qa/generated/library-placement/final/써클러 통합 검증.app`: 0.20.0 build 54, bundle `com.circlr.integrationqa`, arm64 UUID `72011552-4483-3879-B1E5-A70D0AE68B61`. 앱을 UI로 실행하고 데이터 확인·저장·외부 변경은 해당 bundle/fixture를 제한하는 로컬 MCP로 수행했다.

원본 `studio.circlr`의 authored 음악/두 검증 톤을 전용 `library-placement.circlr`로 복사하고 같은 섹션의 두 번째 use를 추가했다. project ID `E52594F7-E3C1-533A-96EB-3BCAB30A0B36`. 새 입력은 직접 생성한 2초 WAV 두 개와 1음 MIDI이며 제품 데모곡·사용자 음악·구매 샘플이 아니다. 원본 미디어는 바꾸지 않았다.

| 경로 | 확인한 결과 |
|---|---|
| 파일 → 섹션 검색 | 한글 `공유` 검색, 빈 검색, ↑↓/Return, Esc 복귀. 기존 파일 검색어와 다중 선택 유지 |
| 대상·시작·트랙 지정 | 첫/최종 후보의 선택 전후 저장 manifest 및 전역 selection 동일. 음악/revision·카메라 변경 없음 |
| 숫자 | 9.5박 적용 후 3마디·4.25초/64박 표시. 12 초안 Esc 후 9.5 유지. 65 입력 거절 및 해당 오류 표시. Return/Esc 후 파일 검색으로 복귀 |
| 단일 오디오 | r16→17. 두 번째 use, 기존 출력 2, 내부 8.5박. tracks 3 유지/assets 2→3. 첫 use와 공통 section 정의 동일 |
| 오디오 Undo | 한 Undo r18로 baseline 음악 복원 |
| MIDI | 9.5박이 트랙 선택 화면에 전달되고 실제 노트 beat 8.5. 새 트랙 하나, 첫 use 동일. r19→한 Undo r20 복원 |
| 다중 오디오 | 4.5박, 트랙 선택 메뉴 없이 새 트랙 두 개. 두 clip beat 3.5, tracks 5/assets 4, checksum 일치. r21→한 Undo r22 복원 |
| 외부 변경 | 11 초안 중 MCP rename r23. 숫자·가져오기 disabled, request 시작은 1박 유지. Undo r24 및 섹션 재선택 후 다시 사용 가능 |
| 복구·보존 | 이번 `inputs/Samples`만 등록 해제. 기존 폴더 1개/파일 4개 유지. r24 저장·재열기 후 baseline 음악 동일 |
| 시각 검사 | 1019×768 창, 콘솔 펼침, 850×560 overlay의 대상·시작·트랙·동작이 잘리지 않음. 저장 JPEG 직접 확인 |

batch 검사 도중 검증 스크립트가 clip의 실제 필드 `beat`를 `startBeat`로 잘못 조회했다. 앱 mutation은 발생하지 않았다. Undo 전 r21 capture를 `final-batch-import-confirmed.json`으로 명확히 이름 바꾸고 필드를 수정해 실제 Undo r22를 별도로 확인했다. 이 임시 검사 오류를 앱 결함이나 Undo 성공으로 계산하지 않는다.

## 보존과 후속 범위

원본 manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 원본/사본의 두 asset checksum, 세 QA 입력 checksum을 확인했다. root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 `dist/써클러.app` 0.19.0 build 21을 유지했다. 첫/최종 build54 검증 앱은 CmdQ로 정상 종료했고 해당 프로세스 0개다.

물리 output·audition 시도는 0회이며 마이크·MIDI 녹음도 실행하지 않았다. HAL 지연 원인 해결·정상 청취·장치별 녹음·VoiceOver 발화는 미검증이다. 초과 트랙 수의 메뉴 접근성과 긴 경로 stress, 실제 외부 file promise, 중첩 폴더 catalog 중복·재연결은 후속이다. 기본 오디오 편집기의 0 기반 박 표시와 가져오기의 1 기반 박을 통일하는 UX 계약도 남는다. Undo로 선택 트랙이 사라진 경우 잘못된 대상으로 import하지 않고 섹션 재선택을 요구하는 현재 복구 흐름을 확인했다.

검증 미디어·fixture·앱·캡처·환경 설정은 Git에서 제외하고 source/docs/tests/QA 도구만 승인된 private branch로 전달한다.
