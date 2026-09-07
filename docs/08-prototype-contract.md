# macOS 프로토타입 구현 계약

작성일: 2026-09-06 · 상태: 구현 기준 · 제품 전체 release 사양과 구분

사용자는 설계 정리 이후 실제 프로토타입 제작을 요청했다. 기존 문서의 ‘문서만 작성’ 경계는 이 요청으로 갱신한다. 이 문서는 새로운 제품 방향을 정하는 것이 아니라, 이미 정한 경험을 실행 가능한 macOS 앱으로 검증하기 위한 계약이다.

## 설계 마감 결정

- 사용 위치마다 원을 표시하고 원본 재사용·이번 사용 변형·독립 분리를 제공한다.
- 일정한 기본 반지름, 한 바퀴 = 섹션 한 회, 마디·박 눈금과 로컬 playhead를 채택한다.
- 프리폼 canvas의 grid·snap·정렬·그룹·접기는 음악 경로와 분리한다.
- 섹션을 열면 로컬 piano roll/audio lane을 편집한다. 실제 note를 입력하고 음원을 import할 수 있어야 한다.
- 글로벌/개별 tempo·scale·meter·BeatGrid·RhythmPattern을 항목별로 해석한다. 기존 절대 pitch는 scale 설정만으로 바뀌지 않는다.
- 실제 pattern은 각 서클 진입·반복에서 시작한다. 연속 phase는 향후 옵션이다.
- audio 녹음 원본과 MIDI take를 보존한다. 반복/경계별 clip 참조를 만들며 destructive 편집을 하지 않는다.
- 음색 처리는 instrument/effect/bus의 명시적 경로, 전환은 within/insert/overlap으로 표현한다.
- 첫 build는 현재 Mac의 arm64 환경에서 검증한다. 실행 기반은 macOS 14 이상으로 설정하고 다른 OS/CPU 검증을 주장하지 않는다.

이는 프로토타입을 시작하기 위한 채택 사항이다. 실제로 써본 뒤 수정 가능한 UX 결정이며 사용자가 직접 승인한 세부 사양이라고 표현하지 않는다.

## 기술 선택

Swift + AppKit으로 원형 canvas와 macOS 문서·창·입력 동작을 작성한다. AVAudioEngine/Audio Unit과 CoreMIDI를 사용한다. 설치된 기본 sound bank 및 사용자가 선택한 Audio Unit으로 실제 MIDI를 연주하고, audio import·녹음·PCM export를 구현한다. SwiftPM으로 domain과 native audio/application을 분리한다.

첫 프로토타입의 재생은 불변 계획을 바탕으로 준비된 audio를 사용한다. renderer는 실제 note/clip/effect를 처리하고 playback과 export가 동일한 준비 결과를 사용한다. 외부 plugin을 매 callback마다 UI graph에서 탐색하지 않는다. 음악 편집으로 새 준비가 필요하면 적용 상태를 명확히 표시하며 이전 실행 결과를 성공적으로 갱신한 것처럼 보이지 않는다.

이 방식은 graph 편곡의 청취 결과를 검증하는 실제 audio 경로다. 장기 architecture의 live processor 전환, 전체 plugin 포맷, 전문 comping, 무제한 feedback과 realtime 저지연 연주 품질은 별도 release 검증 영역이다. 프로토타입의 작동 여부와 해당 장기 영역의 완료 여부를 혼합하지 않는다.

## 파일 소유권과 작업 순서

현재 실행 슬롯이 하나이므로 아래 역할을 순차 수행한다. 파일 경계를 넘어 수정할 때는 해당 소유 역할로 전환한다.

| 단계 | 소유 역할 | 파일/폴더 | 종료 조건 |
|---|---|---|---|
| 1 | native-domain-developer | `Sources/CirclrCore/`, `Tests/CirclrCoreTests/` | 실제 context·graph·time·pattern·저장 의미 테스트 |
| 2 | native-audio-developer | `Sources/CirclrAudio/`, `Tests/CirclrAudioTests/` | PCM·MIDI·effect·Audio Unit·녹음 writer·export 증거 |
| 3 | native-ui-developer | `Sources/CirclrApp/` | 원형 canvas·inspector·editor·파일·transport 실제 연결 |
| 4 | infrastructure | `Package.swift`, `scripts/`, `Resources/`, `.gitignore` | 재현 가능한 app bundle build와 실행 |
| 5 | qa / code-reviewer | `qa/`, `docs/09-prototype-verification.md` | 요구별 증거와 남은 한계를 점검 |

UI는 한국어, 기본 흰 canvas와 읽기 쉬운 중립선·한 가지 선택 accent를 사용한다. 그리드는 사용자가 요청한 공간 정렬 기능이다. 빈 프로젝트가 기본이며 검증용 악보·음원은 QA 경로에만 생성한다. 비동작 CTA는 노출하지 않는다.

## 프로토타입 인수 기준

| ID | 요구 | 필요한 증거 |
|---|---|---|
| A01 | 실행 가능한 써클러 macOS 앱 | app bundle·실제 실행 화면·build log |
| A02 | 프리폼 원형 노드·pan/zoom·grid/snap·다중 선택·정렬·그룹 | UI에서 조작하고 저장/재열기로 복원 |
| A03 | 마디/박 링·진행 표시·길이·반복 | 서로 다른 meter/tempo의 실제 plan과 표시 비교 |
| A04 | 글로벌/사용별 음악 설정 | 상속·local·global reset·pattern off의 domain/GUI 검증 |
| A05 | 섹션 연결·재배치·반복·재사용·변형·편곡 A/B | 순서/원본/변형과 총길이 검증 |
| A06 | 실제 MIDI·리듬 패턴·가상악기 | editor 입력·CoreMIDI 수신 경로·실제 audio 출력 |
| A07 | 실제 audio import·녹음 take 보존 | 파일 roundtrip·writer 검증·원본 보존 증거 |
| A08 | 노드 음색 처리와 섹션 전환 | 실제 PCM 변화·routing·insert/overlap 길이 검증 |
| A09 | native 프로젝트 저장·열기·undo/redo·오류 상태 | 파일 roundtrip·참조/asset 보존·실패 경로 |
| A10 | stereo/stem export와 재생 | 실제 WAV 길이·peak/RMS·트랙 정렬·재생 엔진 상태 |
| A11 | 설계와 구현 상태가 일치하는 문서 | README·CHANGELOG·사용법·요구별 QA 표 |

음악 수학 테스트나 renderer 출력으로 native UI 사용성을 입증하지 않는다. 녹음 writer의 통제된 입력 검증으로 실제 마이크·외부 interface 녹음을 입증하지 않는다. 최종 검증 문서에는 이 차이를 명시한다.

## 명령과 전달물

- `swift test` — domain 및 native audio의 자동 검증
- `scripts/build-app.sh` — `dist/써클러.app` 생성
- `scripts/verify.sh` — tests·audio smoke·bundle 검사를 실행
- 실행 앱의 메뉴/버튼으로 빈 프로젝트 → 섹션 → note/audio → 연결 → 재생 → 저장/다시 열기 → WAV export
- `docs/09-prototype-verification.md` — 실제 확인한 결과, artifact 경로, 미검증 환경 기록

Git은 현재 초기 작업 폴더를 사용하고 제품 코드·문서만 추가한다. 원격 저장소·배포·공개 release는 현재 작업에 필요하지 않다.
