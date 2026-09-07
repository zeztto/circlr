# 궤도 타임라인 구현 계약

상태: 0.10 구현 완료, 로컬 실행 검증. owner: development-lead / native integration. 이전 MCP 단계에 이어 원 자체의 시간 의미를 구현했다. 동시 agent 슬롯이 없어 Core → App → QA를 순차 소유했다. Git은 현재 untracked workspace를 유지하고 commit/외부 배포 없이 로컬 앱으로 검증했다. 최종 동작은 [궤도 타임라인과 편집](19-orbit-timeline.md), 증거와 제한은 [0.10 검증 기록](../qa/0.10-review.md)에 정리한다.

## 결과와 UX

앨범 → 곡·악장 → 섹션 → 음악 소스의 실제 실행 길이를 원 둘레에 투영한다. 12시는 0초, 시계 방향은 진행이다. 배율·반경은 시간에 영향을 주지 않는다. 박자/tempo map의 마디 시작은 MusicClock.seconds(at:)를 통해 표시한다. 부모의 궤도상 소스 위치는 해당 로컬 타임라인의 시작이며, 내부에 노트/파형의 실제 발생 구간을 표시한다.

기본은 궤도 보기다. 기존 자유 배치 좌표와 그룹은 별도로 보존하며 사용자가 그리드 메뉴에서 자유 배치로 전환할 수 있다. 시간 위치는 궤도 손잡이로 명시적으로 편집한다. processing/effect/mix/output은 시간 소스가 아니므로 임의의 시작 시간을 갖게 하지 않고 내부 신호 영역에 둔다. 같은 시작의 음악 소스는 동일 각도와 다른 동심 궤도를 사용한다.

송폼의 위치/길이는 선택된 실행 경로에서 계산한다. 반복의 매 회, overlap/insert 전환을 반영한다. 재생 경로 밖의 섹션이나 미완성 경로는 시간 위치가 확정된 것처럼 표시하지 않는다. 공간 그룹의 생성·접기·정렬은 음악 순서/시간을 바꾸지 않는다.

확대한 MIDI는 원호 위 실제 notes를 추가·선택·이동·길이 조절하고 음높이는 동심 반경으로 편집한다. 오디오는 원형 waveform에 실제 사용 구간·trim 손잡이를 표시한다. 숫자 설정과 이펙트 컨트롤은 같은 canvas에서 접근한다. 새로운 독립 창이나 고정 편집 pane을 추가하지 않는다.

## 파일과 단계

1. `Sources/CirclrCore/OrbitTimeline.swift`, `Model.swift`, `HierarchyScene.swift`: 시간/각도 변환, 마디 tick, 실제 실행 interval과 동심 배치. 기본 orbit와 보존된 freeform의 명시적 모드. rendering DSP는 변경하지 않는다.
2. `Sources/CirclrCore/OrbitEditing.swift`, `Sources/CirclrApp/AlbumCanvas.swift`, `RootView.swift`: source의 시작 손잡이와 순서 편집, 실시간 transport 위치, 궤도 guide/arc/선택. 한 gesture는 한 Undo다. 순서 재배치는 선형 경로에서 동작하고 분기 관계를 조용히 파괴하지 않는다.
3. `Sources/CirclrApp/OrbitMIDIEditor.swift`, `InlineCircleEditor.swift`: 같은 canvas의 원호형 note 편집. 정밀 수치·velocity·recording·generation·bounce 기능을 유지한다.
4. 오디오 source의 시간/원본 trim 표현과 편집을 원형 경로로 연결한다. 파일의 초와 음악 clock을 구분하고 PCM 바운스 결과를 유지한다.
5. `Tests/CirclrCoreTests/OrbitTests.swift`, `qa/`: 시간 좌표와 compiler 결과 대조, local tempo/map/repeats/transitions, group/Undo/저장 복원, 실제 MIDI 편집과 audio waveform/trim, 최소화 MCP 회귀. final source Release를 별도 QA 앱에 적용한 뒤 배포 bundle을 갱신한다.

## 검증

- `./scripts/swift-local.sh test --scratch-path .build/orbit-production`
- `./scripts/swift-local.sh build -c release --scratch-path .build/orbit-production`
- `python3 mcp/native_smoke.py --require-minimized` 및 `qa/analyze-bounce.py`로 기존 제작/agent 경로가 유지되는지 확인한다.
- 실제 QA 앱: 앨범에서 f0r h3r 곡의 section 시작 각도/마디를 확인하고 MIDI 서클까지 확대한다. 시작 손잡이를 이동해 데이터와 PCM 발음 위치가 함께 바뀌는지 확인하고 Undo한다. 원호에 note 추가·이동·길이 변경 → save/reopen을 검사한다.
- 기존 자유 배치 회귀는 그 모드를 명시한 fixture에서 유지한다. 신규 기본 궤도 모드는 별도의 actual time assertions로 검증한다. 이전 geometry 테스트가 통과하는 것만으로 궤도 의미가 구현됐다고 판단하지 않는다.

인증은 기존 사용자 전용 MCP 경계를 유지한다. 생성된 음악/검증 사본만 사용한다. 사용자 승인된 native QA 실행과 파일 접근 범위에서 진행하고 원본 demo 파일이나 사용자가 편집 중인 문서를 덮어쓰지 않는다.
