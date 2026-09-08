# build 42 · MIDI 가져오기 위치 검증

2026-09-09, `codex/daw-integration`, 기준 `87dc228`. MIDI 가져오기 흐름의 bounded progress이며 전체 DAW 출고 판정이 아니다.

## 자동 검사와 패키지

- 최종 Swift **333개, 실패 0, 23.485초**: `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`. `.build/midi-import-tests-final.log`. 실제 출력 장치 의존 1개를 제외했다.
- 새 검사 3개: 6/8→5/8 변박의 섹션 확장, 선행 쉼표/노트 값/간격, 자유 배치의 두 서클 좌표와 궤도 시간, 다른 사용·기존 routing/master 위치 보존, invalid offset/확장 거절의 원자성. 기존 MIDI 검사와 합쳐 focused 7개 통과.
- Python MCP/kit **26개**, `.build/midi-import-python.log`. 새 QA helper 3개 Python 문법 및 evidence checker 실행.
- 최종 release **23.87초**, `.build/midi-import-release-guarded.log`. 앱 `qa/generated/midi-placement/guarded/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build 42. UUID **49CE45BE-F130-3C59-B74A-223D6223E60F**.
- `check-midi-placement-evidence.py`: source 6개·kit 25개 해시, executable 파일 기반 Mach-O 37개 section 일치, strict signature, 원본 QA fixture/2개 자산 무변경, 6개 실제 JPEG와 상태 복원을 검사했다. `guarded/verification.json` passed.

## Native 검사

전용 `fixtures/midi-placement.circlr`, ID `586E904D-0A3D-5BCF-9B3B-2F4193A8C566`. 검사용 MIDI는 helper가 직접 작성한 2트랙·6노트·178 bytes다. MIDI 파일의 note start는 0.5/2.25/60, length는 0.75/1/1, velocity는 81/105/91이다. 기존 사용자 곡/Splice 파일은 사용하지 않았다.

| 시나리오 | 실제 결과와 근거 |
|---|---|
| 작은 창 미리보기 | 시작 1박, 끝 62박, 현재 64박 길이. 제목·확정/취소·위치·두 트랙이 1024×673 canvas와 열린 콘솔에서 보인다. `preview.jpg`, 최종 `guarded-preview.jpg` |
| 위치 입력/길이 초과 | 9.25박 입력 Return → 끝 70.25박. 확장을 끄면 주황 안내와 가져오기 비활성화. 초안 중 음악 r14 불변. `overflow.jpg`, `preview-unchanged.json` |
| 여러 트랙 가져오기 | 음악 r15, tracks +2, 대상만 18마디. 노트 start 8.75/10.5/68.25: 선행 쉼표와 간격 보존. source section/다른 use/master 위치 보존. 편집기 없이 섹션 전체로 이동. `batch.json`, `batch-overview.jpg` |
| 한 번의 Undo | r16에서 원래 음악 복원. 같은 파일을 다시 열면 시작 9.25박을 유지한다. `batch-undo.json` 및 실제 입력 관찰 |
| 한 트랙 선택 | ‘섹션 처음’ → 시작 1박, 드럼 트랙 선택 해제 → r17에 keys 한 트랙. 바로 MIDI 편집기로 이동. Undo r18 복원. `single.json`, `single-editor.jpg`, `single-undo.json` |
| 최종 후보 적용 | `guarded` 후보 r18에서 9.25박을 입력하고 두 트랙 적용 r19, 실제 Undo r20. 최초 후보와 같은 노트/18마디/전체 보기. `guarded-batch/undo.json` |
| 외부 변경 보호 | 최종 후보 초안 중 QA 프로젝트 이름만 MCP rename r21. 취소/재선택 안내와 확정 비활성화가 표시된다. 노트 추가 없음. 취소 후 rename Undo. `guarded-stale.json/jpg` |
| 저장/재열기 | 최종 r22, dirty=false. name/global/tracks/sections/arrangements/assets/patterns/signal/port binding·배치가 초기와 일치한다. layout revision과 탐색 camera는 음악 복원 비교와 분리. `restored/reopened.json` |

최초 후보 4개 JPEG와 최종 후보 2개 JPEG를 구분한다. 최종 후보는 외부 revision 변경 이유를 추가한 UI 보완이며, 위치 적용/Undo를 최종 실행 파일에서 다시 확인했다. 메뉴 파일 목록은 일부 초기 클릭이 선택을 만들지 않아 AX 상태로 확인하고 Down/Return으로 확정했다. 시도만으로 성공을 기록하지 않았다.

## 검토와 제한

동일 실행자가 UI/UX → native Swift utility → 읽기 전용 code/security review → QA로 역할 전환했다. 독립 감사 spawn은 `agent thread limit reached`로 실패했다. 독립 reviewer 검증으로 세지 않는다.

리뷰에서 selection 변경이 `selectedBeat`를 초기화하는 경로를 확인해 import 완료 후 focus를 바꾼 다음 위치를 설정했다. 초안마다 UUID를 부여해 SwiftUI 선택값을 초기화하고 project/revision/generation/current draft를 다시 검사한다. Copy-on-write Core 적용은 실패 시 원본을 바꾸지 않으며 새 track 생성이 기존 master 좌표를 덮지 않게 한다. 입력은 기존 local regular MIDI file·16 MiB 제한 경로를 유지한다. 새 권한·네트워크·외부 파일 쓰기는 없다.

- 실제 **Finder 교차 창 drop, orbit drop hover/overlay, Splice file promise, 라이브러리 시작 위치 변경의 native 왕복은 미검증**이다. 이번 변경의 호출부와 Core timing/placement 검증이 이 gesture 검증을 대체하지 않는다.
- MIDI CC/pitch bend/tempo map, 악기 파일 import는 추가하지 않았다. 파일 첫 tempo와 제외 이벤트 안내는 유지한다. 시작 위치의 ‘박’은 명시한 대로 4분음표 기준이며 변박의 마디·박 입력 UI는 후속 범위다.
- 최종 source 기반 unit/compile 및 Native 메뉴 검증이다. 새 음원 청취·오프라인 WAV·물리 출력·마이크·VoiceOver·MP4를 이번 단계에서 실행하지 않았다. 모든 snapshot의 output attempts=0, 녹음 idle. 기존 장치 출고 조건은 유지한다.
- QA 앱은 정상 종료하고 사용자 0.19 build21 앱, 원본 QA fixture, root/ports 작업 트리를 보존한다. source/docs/tests/helper만 private branch에 기록하고 생성 MIDI·프로젝트·앱·미디어·로컬 로그는 Git에서 제외한다.
