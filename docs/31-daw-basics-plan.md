# 기본 DAW 작업 흐름 확장

2026-09-08 사용자 요청: 드럼·신스 공통 스텝 에디터, 오디오 녹음·편집, 오토메이션, MIDI editing을 실제 제작에 사용할 수 있도록 완성한다. 기존 단일 다크 캔버스, 시간 궤도, 기존 음악/Undo/저장/MCP를 유지한다. 0.15 UI 개선은 먼저 검증·패키징·private push했다.

서브 에이전트 요청에 따라 독립적인 코드 조사를 실제 dispatch했으나 `agent thread limit reached`로 실패했다. 현재 총 1 slot이므로 사용자 요청을 작업 중단 사유로 삼지 않고 역할별로 순차 실행한다. 추가 slot이 제공되면 read-only 오디오/automation 조사부터 분담한다.

## 확인한 출발점

| 작업 | 현재 구현 | 확장·완료 조건 |
|---|---|---|
| 스텝 | 없음 | 일반 Note/Lane을 그대로 편집하는 16-step page, 드럼/음정 row, 해상도, 세기/길이, 키보드, MCP, Undo/바운스 |
| MIDI | 궤도/기존 piano roll 입력·이동·길이·velocity·단일 선택, MIDI 장치 녹음/테이크 | 스텝과 동등한 결과, 선택/quantize/transpose/복제, MIDI import, 오프그리드 보존 |
| 오디오 녹음 | 입력 tap·ring buffer writer·CAF, 마이크 permission, 테이크/활성화 | 명확한 입력/녹음 상태, permission 대기 중 STOP/프로젝트 전환 guard, 장치 실패 복구, 녹음→편집→bounce |
| 오디오 편집 | import, source trim/시작/길이/gain/tempo follow, 바운스 원본 복원 | 분할·복제·fade·무음/삭제·정확한 source 범위·Undo/저장 |
| 오토메이션 | 데이터/편집/재생 경로 없음 | stable target ID, 점/곡선, gain/pan 우선, tempo/local clock/repeat, 실제 render/export·MCP·Undo |
| 엔진 | prepared PCM, 일부 live synth/recording | 장치 lifecycle, transport/record sync, 이후 continuous render/PDC·plugin crash 격리 |

## 실행 순서

1. **0.16 스텝 편집**. `CirclrCore/StepEditing.swift`는 Note/Lane에 편집을 적용하고 별도 패턴 복제 저장소를 만들지 않는다. `CirclrApp/StepEditor.swift`를 기존 Inline MIDI 영역의 `궤도 / 스텝` 전환으로 제공한다. grid 1/4·1/8·1/16·1/32와 triplet, 16칸 page, 드럼 row/음정 row, 선택 note velocity/length는 공통 setter를 사용한다. 현재 time signature·section length를 보존하며 오프그리드 노트를 UI 진입만으로 양자화하지 않는다. 소리 내기/바운스는 기존 graph 그대로다.
2. MIDI 편집 명령을 Core에 통합하고 page 복제·비우기·quantize/transpose와 MIDI import를 추가한다. 경계 밖 클립·노트, repeated section 원본/변형, 다중 source lane을 검증한다.
3. 오디오 edit의 source-safe split/duplicate/fade와 녹음 lifecycle을 구현한다. 기본 경로부터 native 녹음 결과의 파일·파형·재생/bounce 동등성을 확인한다. 현재 Scarlett 장치 제약이 재현되면 OS 설정을 임의 변경하지 않고 다른 구현과 검증을 계속한다.
4. volume/pan 자동화부터 schema → validation/compiler → renderer → 같은 canvas editor → MCP 순서로 완성한다. 곡선이 실제 소리에 반영되는 impulse/constant/tone/tempo fixture를 사용한다. 신스 filter와 plugin parameter 자동화는 유효한 parameter descriptor와 DSP 경로가 연결된 뒤 노출한다.
5. 8방향 포트와 공통 import/Splice·실시간 엔진·계정 콘솔·아티스트 catalog는 기존 로드맵과 병행 후속 범위다. 사용자의 기본 DAW 요청이 추가됨에 따라 step/audio/automation을 포트 구현보다 우선한다.

## 0.16 acceptance

- 드럼·신스 양쪽에서 스텝 입력, 지우기, polyphony, gate/velocity, page 이동/복제, 기존 off-grid 음악 보존.
- keyboard arrows로 셀 선택, Tab으로 다른 입력 이동, Return toggle, Delete 지우기. 텍스트 입력에는 음악 핫키가 개입하지 않는다.
- GUI와 MCP는 동일한 Core 명령/원본·변형/transaction 사용. 유효하지 않은 pitch/resolution/step/gate/stale revision은 atomic 실패.
- 새로운 창·dock를 만들지 않는다. 작은 창에서 grid/hit/라벨 일치, 검색에서 step editor 진입, 음색·이펙트 전환 유지.
- 실제 앱 저장·재열기·Undo·바운스 및 CLI와 음악 동등성. 기존 v4를 그대로 여는 것만으로 hash가 바뀌지 않는다.
- 구현된 UI만 노출, README/CHANGELOG/QA/version/kit 갱신 후 private source push. 오디오·프로젝트·앱·인증정보는 Git 제외.

기본 기능 전체 완료는 이 문서의 단계별 동작이 실제 검증됐을 때만 선언한다. 모델이 실제로 청취하거나 하드웨어 녹음하지 않은 항목은 수치/fixture 검사와 구분한다.
