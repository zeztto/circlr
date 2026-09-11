# 음악 소스에 맞는 서클 생성과 직접 탐색

2026-09-08, `codex/daw-integration`, 기준 `67415dc`. 이전 턴은 비동기 import·세션 media 수명·QA/private push로 progress다. 이번 목표는 오디오 가져오기로 생기는 빈 MIDI/악기와 잘못된 기본 편집 진입을 줄이는 것이다. 기존 큰 목표와 E 출고 gate를 유지한다.

## UX 계약

- 새 audio-only lane은 오디오·믹스·출력으로 시작한다. 음표 없는 MIDI와 악기를 기본 화면에 만들지 않는다. 상속한 오디오 리듬 연결은 유지하며 기존 문서의 노드/연결은 제거하지 않는다.
- MIDI를 위한 빈 lane 생성은 기존처럼 MIDI/악기를 만든다. audio-only lane에 처음 노트를 넣으면 MIDI/악기 경로를 생성해 소리가 나야 한다. 이미 노트가 있는 사용자가 끊거나 제거한 MIDI 경로는 다른 오디오 편집으로 되살리지 않는다.
- 명시적으로 리듬 패턴을 만들 때 대상 트랙의 MIDI 리듬 경로를 준비한다. 프로젝트의 모든 트랙을 자동 변환하거나 다른 사용을 수정하지 않는다.
- 새 트랙 생성은 기존 master 위치를 옮기지 않는다. 오디오 2개 import 뒤 화면/⌘J에는 기존 기본 MIDI/악기 4개가 추가되지 않아야 한다. ⌘1과 작업 이동의 기본 진입은 실제 오디오 편집이다.
- MIDI/오디오/이펙트 편집과 Undo·저장·render는 기존 하나의 캔버스/명령 모델을 따른다. 준비 중·planned UI를 추가하지 않는다.

## 소유와 경로

development-lead → UI/UX → Core/Swift utility → read-only review → QA 순차 수행. 이전 spawn이 실제 한도로 거절되어 delegation none; 독립 리뷰로 보고하지 않는다.

Core: `SectionGraphMigration.swift`의 기본 factory에 source 구성 선택, `Editing.swift`의 신규 source만 materialize하는 규칙, `Model.swift`의 master 좌표 보존. 필요한 명시적 rhythm 생성 helper는 새 `SourceCircleEditing.swift`. 기존 migration 호출은 기존 동작을 유지한다.

App: `AlbumWorkspace.swift`의 명시적 rhythm 생성과 `StudioNavigationView.swift` 소비 경로 확인. 오디오 편집/키보드 경로가 실제 node를 소비하도록 한다. 기존 native renderer/노드 포트 의미는 변경하지 않는다. 제품 version build 27.

상세 편집의 작업 경로 줄에 `이펙트 추가`를 바로 둔다. 오디오/Mix/악기/이펙터의 단일 출력 뒤 또는 선택한 트랙 출력 앞에 추가한다. 출력 선택 시 다른 트랙의 첫 mix를 임의로 고르던 fallback을 제거하고 `SectionGraph.swift`에 출력 앞의 전체 입력 삽입을 추가한다. Section에서 독립 effect를 만드는 명령은 자동으로 다른 트랙을 바꾸지 않는다. 다중 bus 선택은 기존 명시적 port 편집을 사용한다.

QA: source 구성·빈 MIDI 생성·첫 음표·끊긴 route·추가 오디오·pattern 리듬, legacy와 PCM 일치, save/reload·Undo 회귀를 의미 있는 테스트로 확인한다. 전체 Swift/Python·release 이후 별도 QA 앱에서 audio 2개 import → ⌘J → 오디오/⌘1/이펙트 진입 → Undo/저장/재열기, 가능 범위의 MIDI 추가를 검사한다. 실제 마이크·시스템 장치 설정·원본 곡·사용 앱은 변경하지 않는다.

Git: 현재 private 개발 branch에 검증한 source/docs/tests만 commit/push. README/CHANGELOG/로드맵에 구현과 미검증 범위를 분리한다. file-URL native drag·promise·전체 E/VoiceOver/장치 출고는 이전 미완료 범위로 유지한다.

## 실행 결과

build 27에서 위 계약을 구현했다. 새 테스트 Core 5개·Audio 3개를 포함한 Swift 253개, Python 26개와 release가 통과했다. 실제 QA 앱의 두 파일 import, ⌘J/⌘1, 오디오 뒤·출력 앞 이펙트 삽입, 선택 트랙 리듬 스텝과 다른 오디오 lane의 첫 MCP MIDI 입력을 확인했다. 34초 WAV export와 6단계 ⌘Z/저장, 초기 QA 음악으로 재열기가 일치했다. [재현 명령·근거·남은 범위](../qa/source-circles-review.md).

기존 audio-only 프로젝트의 빈 MIDI/악기는 제거하지 않는다. 새 lane 생성의 기본값만 바꿨다. 다중 출력 라우터의 이펙트 추가는 bus 선택이 필요하므로 공통 즉시 메뉴를 표시하지 않는다. 리듬·MIDI는 실제 입력할 때 추가되며 노트를 모두 지운 뒤에도 이미 생성한 서클은 보존한다.
