# Circlr: 궤도와 실제 음악 제작

상태: 구현 중. 0.8의 계층형 컨테이너는 출발점이며 아래 궤도 계약을 아직 전부 충족하지 않는다.

0.9 진행 상태: 내장 synth·sampler, MIDI 생성/파일 저장, 이펙트 포함 바운스·복원, f0r h3r 제작과 튜토리얼, MCP·콘솔 및 최소화 상태의 실제 실행 검증을 완료했다. 아래 4번의 시간/각도 기반 궤도 배치와 원호 편집은 아직 구현하지 않았다. 완료된 기능은 [0.9 검증](../qa/0.9-review.md)과 [에이전트 아키텍처](17-agent-interface.md)에서 확인한다.

## 제품 계약

서클은 타임라인이다. 12시가 시작, 시계 방향이 진행, 한 바퀴가 해당 서클의 음악 길이다. 작은 서클의 **각도는 부모 시간의 시작 위치**, 차지하는 호는 지속 시간이다. 반지름과 카메라 확대율은 시간 길이를 바꾸지 않는다. 같은 시점의 소스는 서로 다른 동심 궤도에 놓인다. 악기·이펙터는 입력 신호를 처리하므로 임의의 시작 시간을 갖게 하지 않고 소스에 연결한다.

음악 시간 연결, MIDI/audio 신호 연결, 공간 배치, 향후 지식 참조는 별도 관계다. 공간 이동이 의도치 않게 곡 순서나 연주 시점을 바꾸지 않게 하고, 궤도 시간 손잡이 조작을 명시적으로 제공한다. 송폼의 순서는 선택한 재생 경로에서 계산한다. 분기·반복의 각 사용은 원본 ID와 별개로 식별한다.

글로벌·부모·개별 tempo, scale, meter, BeatGrid, rhythm pattern의 기존 상속을 유지한다. 독립 tempo의 자식은 부모의 초 단위 구간으로 변환한 후 각도에 투영한다. 마디는 meter map에 따라 표시한다. 오디오의 연속 tempo map 추종처럼 미지원인 경우 저장·재생 단계에서 명확하게 거부한다.

단일 dark canvas, 휠 중심 확대, 같은 캔버스의 MIDI·파형 편집을 유지한다. 최종적으로 음표의 시작/길이도 원호에서 편집한다. 왼쪽·오른쪽·아래 고정 창을 추가하지 않는다.

## 이번 제작물: f0r h3r

- 북유럽을 연상시키는 차갑고 긴 pad, 절제된 lead, 반복하는 저음 pulse.
- 일본 city pop을 연상시키는 maj9/min9, 전위와 반음계적 dominant, electric keys.
- Future bass의 당김음 chord chops, 넓은 detuned saw, halftime와 straight groove의 대비.
- 한 곡을 실제 MIDI와 라이선스된 샘플로 제작하고 master WAV, MIDI, 편집 가능한 `.circlr`를 제공한다.
- Splice 구매 상한 10 credits. 보유 사운드 우선. 원본 샘플은 사용자의 로컬 프로젝트에만 포함하며 공개 앱 배포용 번들에 넣지 않는다.

## 실행 단계 / 소유 경계

동시 agent 슬롯이 없어 로컬에서 순차 실행한다. 각 단계의 파일 책임은 구분한다.

1. 음악/오디오 구현: `Sources/CirclrCore/Production*.swift`, `Sources/CirclrAudio/*Instrument*.swift`, `Sources/CirclrRealtime/` — 내장 synth, sample 악기, MIDI 생성/파일 저장, 실제 이펙트 렌더.
2. 바운스: Core의 원본/렌더 참조, Audio의 선택 출력 렌더, App의 완료/취소/Undo. 처리된 출력을 오디오 서클로 만들고 이중 재생을 방지한다. 공유 입력·sidechain을 보존한다.
3. 음악 제작: `music/f0r-h3r/` — 1곡의 MIDI, Splice 소재 기록, 프로젝트, master와 사용 튜토리얼. 재현은 앱과 동일한 Core/Audio 경로를 사용한다.
4. 궤도 구현: `Sources/CirclrCore/Orbit*.swift`, `HierarchyScene.swift`, `Sources/CirclrApp/AlbumCanvas.swift` — 시간/각도 변환, 동심 배치, 재생 위치와 시간 편집.
5. QA: `Tests/`, `qa/` — MIDI의 실제 note event, synth/sample의 실제 PCM, 이펙트 전후 차이, bounce 전후 동등성, Undo/저장 복원, orbit 좌표와 시간 일치, native 화면/재생 확인.

각 단계 완료 시 실제 결과로 상태를 갱신한다. 기존 문서의 완료는 0.8 범위에만 적용한다.

### 추가된 에이전트 계약

사용자는 CUA에 의존하지 않는 백그라운드 작업과 MCP 연결을 요청했다. 하단 콘솔은 사용자가 요청한 예외로 추가하되 단일 캔버스 위에서 접고 펼칠 수 있는 게임 채팅 형태를 사용한다.

- 로컬 MCP stdio → 공개된 JSON 명령 → 실행 중인 앱의 Unix socket → 동일한 Core 편집/Audio 렌더.
- 소켓은 현재 사용자 전용이며 임의의 shell 실행 기능을 제공하지 않는다.
- 읽기는 snapshot/inspect/events, 쓰기는 project ID + expected revision을 요구한다. 쓰기 batch는 전체 검증 후 한 번의 Undo 단위로 적용한다.
- 장시간 bounce/export는 job ID를 즉시 반환하고 running/completed/failed/cancelled를 이벤트로 보낸다. 정지 명령을 제공한다.
- 로그에는 실제 실행 상태만 기록한다. 작업 중인 척하는 생성 문구나 가짜 agent 메시지를 넣지 않는다.
- native console과 MCP는 같은 명령 디스패처를 사용한다. MCP를 실제 JSON-RPC 요청으로 검증하고 f0r h3r의 편집/바운스에 사용한다.
- native Swift 파일 구현은 개발 lead가 소유하는 로컬 통합 단계로 처리한다. Python MCP adapter는 독립 파일 경계를 유지한다.

## 아티스트 세계관으로의 확장

2026-09-07 제품 확장: [아티스트 프로필과 창작 세계](21-artist-universe.md)에서 프로필 선택, 작품·생성물·버전·출처, 세계관 관계와 상위 catalog를 구체화했다. 음악은 그 아티스트 작업 공간의 제작 기능으로 이어진다.

음악 중심 실행 계층과 별도로 안정적인 `ContentID`, typed payload, asset provenance, `ReferenceEdge`를 둔다. text/image처럼 시간이 없는 콘텐츠는 음악 궤도에 cue로 연결하거나 공간상의 참조 서클로 둔다. video는 frame/seconds timebase를 가지며 음악 clock과 명시적으로 동기화한다. 링크가 audio route로 해석되거나 단순 이미지가 저절로 loop처럼 실행되어서는 안 된다. 아직 구현하지 않은 미디어 기능을 UI 메뉴에 노출하지 않는다.

## 위험 / 검증

- PCM 전체 준비의 메모리 비용: 필요할 때만 stems 생성, DAG의 마지막 소비 이후 버퍼 해제, 실제 길이의 한 곡으로 확인.
- 새 악기와 기존 프로젝트 호환: optional config로 decode 하위 호환, 악기 선택 실패를 조용히 다른 음색으로 대체하지 않음.
- bounce는 준비 도중 프로젝트·선택이 바뀌면 적용하지 않음. 파일과 모델을 트랜잭션으로 저장하며 원본을 복구 가능하게 유지.
- 궤도 겹침: 동시 시작을 각도로 억지 분산하지 않음. 동일 시간은 동일 각도, 반경과 zoom으로 분리.

## 확인한 외부 자료

- [Splice: 다운로드 위치 및 MIDI 파일](https://support.splice.com/en/articles/8652631-where-do-my-downloaded-samples-presets-midi-files-go)
- [Splice: credit 단가](https://support.splice.com/en/articles/8652639-how-do-credits-work)
- [Splice: certified license](https://support.splice.com/en/articles/8652641-how-do-i-generate-a-certified-license-for-my-samples)
