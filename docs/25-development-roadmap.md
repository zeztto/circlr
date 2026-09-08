# 써클러 개발 방향과 실행 계획

작성: 2026-09-08. 계획 시작 기준: 0.11 native 앱, 0.12 음악 에이전트 키트 소스. 현재 산출물은 0.19.0이다. 목표는 송폼 중심의 전문 음악 제작을 먼저 완성하고, 이를 아티스트의 작품·세계관 관리로 확장하는 것이다.

0.20 녹음 lifecycle은 소스·전용 검증 앱과 오프라인 검사까지 진행했다. 문서 재열기·직접 녹음 버튼·단축키 안내를 확인하고 오디오 이동 메뉴의 대비를 개선했다. 실제 입력과 녹음 중 UI 검증이 남아 사용 앱은 0.19를 유지한다. [0.20 검증 상태](../qa/0.20-review.md)의 남은 acceptance를 유지한다.

독립 `codex/eight-direction-ports` 브랜치의 `056502b`에는 포트 기반 A를 구현하고 private push했다. 고정 포트 ID·IN/OUT·sidechain·13개 분기, 배치 revision·Core Undo·8방향 geometry·그룹 logical endpoint·PCM 불변의 159개 offline 검사와 release build가 통과했다. [포트 실행 계획](https://github.com/zeztto/circlr/blob/056502bf5451f6a6e2f8b2aa2c94b04e4286a099/docs/35-port-foundation-plan.md)의 B–E(독립 bus·native UI·MCP·통합)를 이어간다. 이 Core 브랜치를 사용 앱에 통합한 상태는 아니다.

0.14에서 10음색 engine 3와 15트랙의 f0r h3r v4를 추가했고, 0.15에서 B의 탐색 깊이·라벨 가독성·작은 창 편집을 개선했다. 배포용 v4는 FreePats CC0 bank를 사용한다. 기존 버전·원본 곡은 보존한다. [음질·음악 검증](../qa/0.14-review.md)과 [UI 검증](../qa/0.15-review.md)을 분리한다.

추가된 기본 DAW 요청에 따라 0.16 스텝, 0.17 MIDI 일괄 편집·노트 import와 권한 대기 guard, 0.18 오디오 split/duplicate/fade, 0.19 gain/pan automation을 구현했다. 다음 실행 순서는 장치 lifecycle → E의 endpoint 데이터·표시·hit·Undo/MCP → 공통 drop/로컬 라이브러리 → 실제 MP4 재검증과 F/G/H다. 상세 완료 조건은 [기본 DAW 확장 계획](31-daw-basics-plan.md)을 따른다. Scarlett 출력 연결과 실제 재생 녹화 검증은 남아 있으며, UI 완료가 이를 대신하지 않는다. [Splice 연동 계획](27-splice-licensing-and-integration.md)은 공통 파일 import → 로컬 라이브러리 → companion AU 순서다.

| 단계 | 현재 상태 | 다음 확인할 결과 |
|---|---|---|
| A | private 소스 이력, 로컬 패키징 구현 | CI·서명 배포는 별도 범위 |
| B | 생성/명령 검색/⌘J/트랙 전환/라벨 개선 | 8방향 연결 탐색과 통합 |
| C | 캡처·코덱 경로 구현 | Scarlett 실제 출력·MP4 동기/최소화 |
| D | engine 3·v4 MIDI/CC0/WAV·native bounce | 아티스트 청취 피드백 |
| E | 상세 계약 확정, 구현 전 | stable ports·8방향 cable placement·migration |
| Import | 정책 조사·CC0 대체, 0.17 MIDI 노트 가져오기 완료 | CC/tempo map, 공통 drop·중복 자산 관리 |
| F | prepared PCM 기반 | 장치 lifecycle 후 연속 render graph/PDC |
| G | 공식 계정 콘솔 설계·전문 kit/MCP 구현 | App Server adapter·권한/취소·대화 UI |
| H | 아티스트 세계관 설계 | catalog/schema·파일 참조·복원 |

## 제품 원칙

1. 하나의 다크 캔버스에서 작업한다. 원은 시간·반복을 가진 궤도이며 관계 그래프의 장식이 아니다.
2. 앨범 → 곡·악장 → 섹션 → MIDI·오디오·악기·이펙터를 같은 탐색 모델로 다룬다.
3. 마우스·키보드·AI는 같은 편집 명령, 검증, Undo 및 프로젝트 데이터를 사용한다.
4. 실제 동작과 음악 품질을 검증한 기능만 UI에 표시한다. 미완성 버튼이나 가짜 에이전트 진행을 넣지 않는다.
5. 제작 중 원본과 수정본을 구분한다. 사용자 곡, 샘플 출처, 편곡 대안과 복구 가능성을 보존한다.

## 현재 문제와 우선순위

| 우선순위 | 문제 | 완료 결과 |
|---|---|---|
| P0 | 원격 이력 없음 | 비공개 GitHub 저장소, 검증한 단계별 커밋·push |
| P0 | 원형 UI의 생성·선택·조작이 발견하기 어려움 | 빈 공간 우클릭 생성, 명령 검색, 키보드 탐색·편집 |
| P0 | 내장 음색과 f0r h3r의 완성도 부족 | DSP 개선, 새로운 실제 편곡·믹스·프로젝트·MIDI·WAV |
| P1 | 재생 비주얼을 영상으로 사용할 수 없음 | 앱 캔버스 영상과 실제 재생 오디오를 함께 저장 |
| P1 | 음악 AI 역할 분담 기반 필요 | 설치된 전문 역할, 안정적인 단일 writer, 실제 도구·작업 로그 |
| P1 | 좌우 포트에 제한됨 | 8방향 IN/OUT, 다중 입출력, 연결 의미와 배치 분리 |
| P2 | prepared PCM 엔진의 한계 | 연속 실시간 엔진, PDC, 녹음·플러그인 안정성 |
| P2 | 앱 내 Codex 계정 대화 미구현 | 공식 App Server 세션·로그인·취소·권한 UI |
| P3 | 아티스트 자산이 곡 파일로 분산 | 아티스트 프로필, 작품·세계관·통합 미디어 catalog |

## 이번 실행 A — 이력과 릴리스 기반

- 현재 소스·문서·테스트·브랜드 리소스를 먼저 커밋한다. 사용자 승인된 계정의 private 저장소를 생성하고 privacy와 원격 HEAD를 검증한다.
- licensed 샘플이 들어간 .circlr/WAV, build 앱, 임시 QA 산출물, 계정·로컬 절대 경로 설정을 Git에서 제외한다. 직접 작성한 MIDI와 제작 코드는 보관한다.
- 단계마다 README의 실제 버전/사용법과 CHANGELOG를 유지한다. 새 버전은 소스·bundle Info·agent kit manifest가 일치해야 한다.
- macOS CI는 순수 Core/형식 검사를 우선하고 Audio Unit/native GUI 검증을 별도 단계로 명시한다. 서명·notarization 배포는 개발자 계정과 배포 정책을 정한 뒤 구성한다.
- 완료 기준: private=true, 원격 commit SHA 일치, 비밀정보 패턴 검사, 로컬 기존 앱 보관.

## 이번 실행 B — 캔버스 조작과 키보드

### 생성

- 빈 공간 우클릭으로 생성 메뉴를 연다. 현재 계층에 맞춰 곡·악장·섹션·MIDI·오디오·이펙터를 제공한다.
- 클릭 지점과 포함 owner를 분리한다. 자유 배치에서는 클릭 좌표를 owner의 로컬 좌표로 변환해 저장한다. 궤도 모드에서는 시간 의미를 유지하며 공간 좌표가 재생 순서를 임의로 바꾸지 않는다.
- 생성 가능하지 않은 계층에서는 적절한 상위 컨테이너를 선택하거나 의미 있는 안내를 제공한다. 섹션 밖에 소유자 없는 MIDI를 만들지 않는다.
- 추가는 한 Undo 작업으로 처리하고 새 서클을 선택한다. 음악 context는 부모 상속을 유지한다.

### 명령과 포커스

- 명령 검색은 단일 캔버스 위의 짧은 overlay로 제공한다. 검색어, 결과 이동, Return 실행, Escape 닫기를 지원한다.
- 선택·확대/부모·형제·다중 선택, 생성·삭제·재사용·그룹·연결·설정, 재생·녹음·저장·내보내기를 키보드에서 접근 가능하게 한다.
- 기존 ⌘N/O/S/Z/⇧Z/I/E/W와 닫기=최소화, ⌘Q=종료 계약을 유지한다. 텍스트 입력 중 Space/Backspace/문자 핫키가 음악 명령으로 실행되면 안 된다.
- MIDI 노트는 키보드 선택, 입력, 시간/음정 이동, 길이 변경 및 삭제를 지원한다. 오디오 trim과 파라미터는 키보드로 접근 가능한 수치 입력을 갖춘다.
- 키맵은 도움말에서 확인한다. 모든 동작에 개별 핫키가 필요하지는 않지만 명령 검색/메뉴/Tab을 통한 마우스 없는 접근은 필요하다.
- Native QA: 빈 캔버스 우클릭 생성, 계층별 생성 owner, 메뉴 취소, 검색 0건, 한국어 입력, 텍스트 입력 충돌, keyboard-only 섹션→MIDI→연결→저장 흐름. 1440×900과 축소 창에서 확인.

파일 책임: AppStore/AlbumWorkspace/AlbumCanvas, 새 command UI, CirclrApp 메뉴, Orbit MIDI/Audio editor. Core에는 좌표·선택·편집 의미의 검증 가능한 공통 동작만 둔다.

## 이번 실행 C — 재생 화면 영상 녹화

- 첫 범위는 써클러 자신의 캔버스와 실제 재생 음악이다. 다른 앱·알림·마이크를 함께 녹화하지 않는다.
- 녹화 시작 전에 파일 경로를 선택하고 렌더를 준비한다. 화면 크기가 바뀌어도 영상 해상도를 고정하고 비율을 보존한다.
- 영상 timestamp를 재생 시간과 연결한다. 임의 wall-clock 증가만으로 오디오와 영상을 맞추지 않는다. 실제 준비된 PCM을 같은 구간으로 기록한다.
- 시작/녹화 중/종료 저장/실패 상태와 정지 명령을 제공한다. 자동 재생 종료, 사용자의 중간 정지, 음악 revision 변경, 최소화·화면 가림, 저장 실패를 정의한다.
- 작업 중 파일은 임시 경로에 작성하고 완료 후 확정한다. 기존 영상은 허락 없이 덮어쓰지 않는다. 오류 시 partial 파일을 최종 결과처럼 노출하지 않는다.
- AVFoundation 기반 H.264 영상·AAC 오디오 MP4를 우선 검증한다. 지원하지 않는 포맷/해상도 옵션은 표시하지 않는다.
- Native QA: 실제 움직이는 서클, 정상 오디오 track, 시작/끝 동기, 중간 정지, 프레임 누락 시 timestamp 유지, 최소화/복원, 취소·디스크 오류. 생성한 MP4의 tracks/duration/frame rate를 검사하고 표본 프레임을 확인한다.

파일 책임: 독립 recording/export 서비스, AppStore 녹화 상태, AlbumCanvas capture, toolbar/menu. 오디오 엔진과 파일 포맷을 공유하되 녹화 파일 I/O를 실시간 오디오 callback에 넣지 않는다.

## 이번 실행 D — 악기 DSP와 실제 곡 재제작

### 문제 진단

- 현재 synth는 여섯 스타일에 유사한 oscillator/2단 low-pass를 사용한다. 다중 voice의 위상·폭·velocity 반응과 envelope·필터를 검사한다.
- pitch 정확도, alias 성분, DC, note-off/stealing click, voice 누적, 높은 음역의 FM·하모닉과 stereo 저역을 측정한다.
- 믹스에서 코드/패드/키/lead가 차지하는 register와 시간, 킥·베이스 충돌, 과한 잔향과 반복 패턴을 구분한다. 단순 gain 증가로 해결하지 않는다.

### 구현과 음색

- 공유 DSP를 개선해 live preview와 offline bounce가 같은 음색을 사용하도록 한다. 기존 patch 저장 호환성을 유지한다.
- 오실레이터별 역할, 저역 중심 안정성, pad/saw 폭, keys의 타건 반응, pluck의 스펙트럼 변화, lead의 중심 음정을 분리한다.
- 범위가 명확한 표현 파라미터만 노출한다. 미구현 modulation/automation 기능을 약속하지 않는다.
- 수치 시험과 비교 WAV를 남기고 CPU 비용을 실제 조건에서 검사한다. 64 voices·event overflow·블록 크기 변경·짧은 노트·긴 release를 검증한다.

### f0r h3r

- 방향: 북유럽 신스웨이브의 서늘한 공간감 + 일본 city pop의 화성과 리듬 + future bass 후렴의 대비. 곡명과 아티스트 의도는 유지한다.
- v1은 보존하고 v2 새 경로에 제작한다. 하나의 주 모티프와 호흡 있는 문장을 중심으로 인트로·절·빌드·후렴·브리지·최종 후렴·아웃트로를 설계한다.
- 베이스와 드럼의 pocket, 코드 보이싱의 voice leading, 후렴 register/폭/밀도 대비, 전환과 tail을 실제 MIDI·graph에 반영한다.
- 보유 Splice 소재부터 사용한다. 기존 승인 한도는 10 credits이며 추가 구매가 필요하면 지출과 출처를 기록한다. 다른 서비스 유료 결제는 자동으로 확장하지 않는다.
- 정적 balance → source/arrangement 조정 → 필요한 dynamics/공간 처리 → level-matched 비교 순으로 진행한다. 무조건적인 LUFS 목표 대신 목적에 맞는 dynamics를 보존하고 측정 방법을 표시한다.
- 산출물: 편집 가능한 .circlr, 전체 MIDI, stereo WAV, 가능하면 stems, 제작/출처 기록, 측정·검토 기록. 앱 재생 및 bounce/export에서 동일한 내용을 확인한다.
- 완료 기준: 기술적 오류·clipping·불필요한 silence·누락·tail 잘림 없음, 원본 보존, 실제 산출물 검증. 청취를 하지 못한 검사를 수행했다고 표현하지 않으며 발매 미학의 최종 판단은 아티스트가 한다.

파일 책임: CirclrRealtime/synth.c, CirclrCore/ProductionModel, CirclrAudio/ProductionInstrument 및 필요한 DSP, 제작 CLI, music/f0r-h3r/v2, 음질/호환성 테스트.

## 다음 개발 E — 8방향 포트와 편집 명령 통합

[8방향 계약](22-eight-direction-ports.md)을 구현한다. port ID와 cable endpoint 위치를 분리하고 종류별 입력/출력을 표시한다. Fan-in/out, sidechain, reroute, 다중 케이블 선택을 지원한다. 키보드 연결 선택과 MCP가 동일한 type/cycle 검사를 통과하도록 한다. 기존 그래프 migration·재생 동등성을 우선 검증한다.

## 다음 개발 F — 연속 실시간 오디오와 녹음

- immutable render graph를 오디오 callback 경계에서 교체하고 allocation/lock/file I/O를 callback 밖으로 분리한다.
- tempo map, live MIDI timestamp, pre-roll/count-in, punch/loop recording과 take 관리의 공통 clock을 설계한다.
- plug-in latency 신고/측정·PDC, latency 변화, bypass, suspend, sample rate 변경, 외부 장치 hot-plug를 검증한다.
- crash 격리 및 복구, offline render와 실시간 render 차이를 명시한다. 복잡한 plug-in의 안정성을 소스 검사만으로 선언하지 않는다.

## 다음 개발 G — 앱 내 Codex

[계정 콘솔 계획](20-codex-account-console-plan.md)과 [음악 제작팀](24-music-agent-kit.md)을 연결한다. 공식 App Server를 사용하고 별도 비공식 OAuth나 auth.json 복제를 하지 않는다. 전용 storage/runtime, 모델 목록, 로그인/로그아웃, 대화 복원, 실제 역할 로그를 구현한다.

RunLease는 projectID·revision·turn generation·권한을 묶는다. 사용자의 STOP/프로젝트 전환 뒤 늦은 결과를 적용하지 않는다. 전문 에이전트가 제안한 여러 변경은 single writer가 통합하고 승인 정책은 실제 변경 단위와 연결한다. 사용자 계정/모델/비용 정책을 UI에서 확인 가능하게 한다.

## 이후 H — 아티스트의 창작 세계

[아티스트 세계관 설계](21-artist-universe.md)를 기반으로 프로필·작품·에셋·버전·권리/출처·발매 묶음을 도입한다. 음악 시간 궤도와 텍스트/이미지의 관계 궤도를 혼동하지 않는다. 파일은 stable ID·hash·참조 무결성으로 관리하고 외부 파일 이동/삭제 및 백업·복원 흐름을 검증한다.

## 실행 방식과 진행 기록

단일 agent 슬롯에서 UX → 구현 → 코드/보안 검토 → QA를 순차 수행한다. 서로 다른 파일 책임을 명시하고 사용자 변경을 덮어쓰지 않는다. 0.13의 B/C/D 이후 0.14 음악·엔진과 0.15 탐색 UI까지 진행했다. 후속 범위는 위 표와 각 버전 QA에 유지하며, 이번 milestone만으로 전체 개발 목표를 완료 처리하지 않는다. 날짜 약속 대신 검증 완료 조건으로 다음 단계를 시작한다.
