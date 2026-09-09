# build 55 음악 위치 표시 검증

2026-09-09 · `codex/daw-integration`, baseline `f24e9da98b2fa0be5c18950304eb65f70b8be907`. 상태는 개발 progress이며 전체 DAW·0.20 출고 완료가 아니다. [표시·입력 계약](../docs/69-beat-position-display.md).

## 변경과 검토

공통 `NumberEditPresentation.beatPosition`이 저장 beat를 표시할 때만 +1, 입력을 해석할 때만 −1 한다. 오디오 배치·MIDI 시작·오토메이션 위치·부모 안 시작과 import를 이 표현에 연결했다. 기간·오디오 초·geometry·Core 편집·MCP·프로젝트 schema는 그대로다. 원시 baseline으로 변경을 판단하므로 표시 자리수로 음악을 재저장하지 않는다. 범위는 원시 단위로 검사하되 오류 안내를 표시 단위로 바꾼다. MIDI import의 마지막 시작 경계는 semantic validation으로 검사한다.

실제 1-slot 제한을 따라 UI/UX → native Swift/Core utility → 순차 read-only code/security review → QA로 수행했다. 직전 회차의 실제 `agent thread limit reached`를 근거로 동일 조건의 재호출을 반복하지 않았다. 독립 에이전트 검토를 주장하지 않는다. 값/범위/길이의 혼동, 이중 +1, stale identity, 공유 use 분리와 임포트 전달을 검토했고 이번 변경에서 추가 고확신 결함은 발견하지 못했다. 외부 API·권한·파일 scope 확장은 없다.

## 자동 검사와 패키지

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback` | 406개 / 0 실패, 25.651초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.225초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` | 성공, 54.27초 |
| `python3 qa/check-beat-position-evidence.py` | snapshot 19개·AX/JPEG 각 24개, source hash 17개·kit 25개·Mach-O section 37개·strict codesign 통과 |

새 테스트는 1 기반 입력/0 기반 저장, 길이 보존, 미세 위치의 untouched/cancel, 표시 범위·잘못된 값, revision/target/raw value 충돌, 변속 구간의 초와 ordinal 분리를 확인한다. 처음 테스트 fixture가 존재하지 않는 `MusicContext(tempo:)` initializer를 사용해 compile 실패했고, 실제 initializer와 tempo 설정으로 수정했다. 최종 로그는 `.build/beat-position-fixed-tests.log`, `.build/beat-position-python.log`, `.build/beat-position-release.log`다. 첫 실패 로그도 `.build/beat-position-tests.log`에 보존했다. 제외한 물리 재생 검사는 이 결과로 통과한 것이 아니다.

전용 앱 `qa/generated/beat-position/써클러 통합 검증.app`: 0.20.0 build 55, bundle `com.circlr.integrationqa`, arm64 UUID `BB76D654-5B77-3D39-8F35-33B0FE3830E0`. 새 QA project ID `D2F41557-396B-5515-8537-EB56F8EFFAA5`. 원본 `studio.circlr`의 authored 음악·두 검증 톤을 복사하고 두 번째 use를 만든 fixture다. 입력은 직접 작성한 2초 WAV·1음 MIDI이며 제품 음악이 아니다. 패키지/QA helper는 이전 앱·fixture를 덮어쓰지 않는다.

## 실제 앱 검증

| 흐름 | 결과 |
|---|---|
| 오디오 배치 | 첫 위치 1박·원본 시작 0초. 9.5 입력→Tab으로 원본 초 이동, 저장 clip.beat 8.5. duration 32초/원본 시작/다른 use 보존. r15→Undo r16 |
| MIDI 시작·길이 | 첫 노트 1박·길이 0.5박. 0 입력은 `1–64.5 박` 범위 오류. 9.5→Tab 적용은 raw beat 8.5, 길이 0.5 유지. r17 |
| 피아노 롤·스텝·궤도 | 같은 노트의 9.5박/0.5박 유지, 양쪽 노트 AX 설명 일치. 12 초안 Esc는 9.5 복원. 보기 전환은 아래 별도 Undo 관측 참조 |
| 오토메이션 | 첫 점 1박/0초, 9.5 위치는 raw 8.5와 4.25초. 표시 위치 1–65박, 궤도 중심은 길이 64박. 추가 r19/이동 r20 |
| 외부 변경 | 위치 12 초안 중 MCP rename r21, Return은 stale 오류와 초안을 유지하고 원래 9.5/4.25초 보존. Esc→rename/이동/점 추가를 각각 Undo해 r24 |
| 서클 설정 | 첫 위치 1박. 부모 안 시작 3.25 입력은 node.startBeat 2.25, 길이 64박 유지. 이번 use만 변경. r25→Undo r26 |
| 오디오 가져오기 | 라이브러리 9.5박과 가져온 오디오 편집기의 9.5박 일치. raw beat 8.5, 원본 2초·checksum 일치. r29→한 Undo r30 |
| MIDI 가져오기 | 라이브러리·트랙 선택·피아노 롤 속성·AX 모두 9.5박. 65는 exclusive 끝 오류, 64.9995는 허용하며 끝 65.9995/연장 안내. 다시 9.5에 실제 import r31→한 Undo r32 |
| 복원·재열기 | 모든 음악·보기 데이터 baseline 복원, 이번 `inputs/Samples`만 등록 해제. 기존 folder 1개/files 4개 유지, r32 저장/재열기 뒤 첫 MIDI 1박 확인 |
| 시각 검사 | 1019×768 창·콘솔 펼침, 오디오/피아노 롤/궤도/설정의 수치 가독성과 길이 구별. 앱 재실행 후 선형 오토메이션의 끝 65박도 실제 JPEG로 확인 |

Core 모델 비교는 원시 음악 값만이 아니라 공통 section 정의·다른 use·signal·portLayout(음악 revision 제외)·circleLayout까지 확인한다. GUI 탐색 카메라는 의도적으로 변할 수 있다. 수치 외 실제 볼륨/연주 품질은 평가하지 않았다.

## 발견한 후속 UX와 검사 경계

기존 `RootView`와 `CanvasCommands`의 궤도/자유 배치 전환은 `mutate(..., musical:false)`로 Undo stack에 들어간다. r17의 MIDI 편집 뒤 보기 왕복을 하고 Undo하면 음악 대신 마지막 보기가 복원된다(r18, orbit·MIDI beat 8.5 유지). 따라서 이를 MIDI 편집이 취소됐다고 기록하지 않았다. 해당 capture는 `layout-undo.json`이며 이후 보기와 MIDI 변경을 되돌려 r28 baseline을 별도로 확인했다. 오디오/MIDI import는 보기 전환 없이 각각 한 번의 Undo로 검증했다. 보기 선호를 음악 Undo와 분리하면서 실제 노드 배치의 Undo·저장·dirty/revision을 보존하는 후속 계약이 필요하다.

초기 focus 요청은 레거시 그래프의 실제 node ID 대신 파생 clip ID를 사용해 거절됐다. inspect에서 node ID를 읽어 복구했으며 음악은 바뀌지 않았다. 설정 스크롤 뒤 첫 클릭은 바뀐 AX index의 라벨을 가리켜 입력되지 않았다(`node-position` capture, r24 그대로). 새 AX index로 실제 field에 적용한 `node-committed`와 r25 모델을 수용 증거로 사용한다. 증거 checker의 첫 실행은 라이브러리를 열기 전에도 파일 catalog가 로드됐다고 가정해 실패했고, 실제 초기 0개/열기 후 6개/정리 후 4개 상태로 수정했다.

legacy `EditorView`의 별도 audio ValueField와 CanvasFileDrop의 문구는 컴파일·소스 검토까지이며 해당 경로의 drag gesture를 이번 앱에서 재검증하지 않았다. 64.9995 MIDI 경계는 draft 수용까지이고 그 위치의 실제 섹션 연장은 이 회차의 import 대상이 아니다. VoiceOver 발화·모든 변박/최대 길이 UI·물리 장치 출력·마이크는 미검증이다. output/audition 시도는 0, 녹음도 실행하지 않았다.

## 보존

원본 manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 원본/사본의 두 asset 및 두 입력 checksum을 유지했다. root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱 0.19.0 build 21을 보존했다. build55 앱은 두 실행 모두 CmdQ로 정상 종료했고 현재 해당 프로세스는 0개다. 생성된 앱·음악·fixture·캡처·환경 설정은 Git 제외이며 source/docs/tests/QA 도구만 승인된 private branch로 전달한다.
