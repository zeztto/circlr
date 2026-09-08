# 오디오 작업 공간

2026-09-09, 기준 `3d57036`, `codex/daw-integration`, build 38. development-lead → UI/UX → native Swift utility → 읽기 전용 검토 → QA. 새 서브 에이전트 요청을 실제로 시도했으나 `agent thread limit reached`가 반환됐다. delegation none으로 순차 진행한다.

## 편집 계약

확대 버튼을 파일 이름 옆으로 옮겨 작은 창에서 파형 높이를 확보한다. 같은 캔버스 안에 왼쪽 배치 박·원본 시작/끝 초·분할 위치, 중앙 파형, 오른쪽 클립 볼륨 dB·페이드 ms·템포 추종·원본 BPM을 배치한다. 새 dock나 창을 만들지 않는다. 분할·복제·트랙 바운스와 바운스 원본 복원은 직접 접근한다. 파형은 원본 시간, 음악 궤도는 섹션 시간임을 구별하고 선택 구간의 원본/실제 재생 길이를 함께 표시한다.

전체 파일/선택 구간 보기는 음악을 변경하지 않는다. 선택 구간 맞춤은 여백을 포함한 원본 초 범위를 고정하며 trim 중 자동 확대하지 않는다. 화면 밖 끝점은 가짜 핸들로 표시하지 않는다. 궤도/자유 배치 변경에는 같은 범위를 유지하고 다른 대상/원본 편집 전환에는 초기화한다. 초는 소수 3자리, ms는 1자리로 표시하고 실제 모델 값과 입력 정밀도는 유지한다. 숫자는 배치→시작→끝→분할→볼륨→페이드 인→아웃→BPM 순서로 입력하며 Return/Esc 뒤 파형 키보드로 돌아간다.

시작 trim은 기존 끝을, 끝 trim은 기존 시작을 보존한다. 기존 명시적 페이드 합과 renderWindow의 경계를 지켜 동일한 제한을 숫자·드래그·방향키에 적용한다. 원본 source 초와 템포에 따른 재생 초는 별개이며 `AudioClipTiming`을 공통 사용한다. 분할 커서는 trim 후에도 가능하면 같은 절대 원본 위치를 유지한다.

직접 클립 편집도 `AudioEditing`의 원자적 경로를 이용한다. 같은 lane/clip을 참조하는 노드가 여럿이면 선택 노드에만 새 clip ID를 연결한다. 다른 노드·연결·원본 섹션/사용·바운스 이력은 보존한다. 교체 요청의 clip/asset identity가 다르거나 데이터가 잘못되면 전체 변경을 거절한다. 아무 변화가 없으면 복제·Undo를 만들지 않는다. 드래그는 프로젝트·세션·대상·revision·표시 범위·layout·disabled 변경 후 적용하지 않는다.

## 소유와 검증

- Core: `Sources/CirclrCore/AudioEditing.swift`, 새 `AudioSourceViewport.swift`; `Tests/CirclrCoreTests/AudioEditingTests.swift`, 새 `AudioSourceViewportTests.swift`. 공유 클립 분리, 잘못된 교체 원자성, trim 경계/페이드, 표시 범위·좌표 왕복을 검증한다.
- Native Swift: `Sources/CirclrApp/AudioWorkspace.swift`, `OrbitAudioEditor.swift`, `EditorKeyboard.swift`. 공통 numeric input은 기존 계약을 사용한다. 저장 형식·인증·네트워크 계약은 바꾸지 않는다.
- QA: `./scripts/swift-local.sh test --scratch-path .build/audio-workspace-final-quality --skip testArrangementRenderExportAndPlayback`, 기존 Python MCP/kit 검사, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. build 38 별도 앱과 직접 작성한 복사 fixture에서 작은 창·궤도/자유 배치·순차 입력·trim/페이드·키보드·Undo·충돌 거절·저장/재열기를 확인한다. 물리 출력 및 실제 마이크를 시작하지 않는다.
- Git: 승인된 private `zeztto/circlr`의 동일 브랜치에 소스·문서·검사만 커밋/push한다. build 앱·fixture·미디어는 로컬 QA 산출물로 남긴다. README/CHANGELOG/개발 계획과 증거를 갱신한다. 전체 DAW 목표와 기존 장치/출고 조건을 유지한다.

결과와 첫 후보 수정, 실제 검증 및 제한은 [build 38 QA](../qa/audio-workspace-review.md)에 기록한다.
