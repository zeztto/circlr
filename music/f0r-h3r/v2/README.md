# f0r h3r — v2

북유럽 신스웨이브의 긴 여운과 일본 city pop의 코드, future bass의 half-time 후렴을 결합한 instrumental 개정판. 0.13 내장 엔진으로 제작했다. 기존 v1 프로젝트와 WAV는 보존했다.

- [편집 가능한 프로젝트](f0r%20h3r.circlr), [48kHz/24-bit stereo WAV](f0r%20h3r.wav), [9트랙 MIDI](f0r%20h3r.mid)
- 116 BPM, 4/4, F♯ minor. C♯7(b9)의 E♯ 같은 화성적 변형을 포함한다.
- 68마디, 본문 140.6897초 + 잔향 2초. 3,119 MIDI notes.
- 기존 보유 Splice Digi Grid Outrun 샘플 6개. 추가 지출 0/10 credits. 원본의 SHA-256은 production-report.json에 기록한다.

## 구성

| 마디 | 섹션 | 역할 |
|---|---|---|
| 1–4 | 멀리서 · Intro | 낮은 밀도의 키와 얼음 플럭, 뒤쪽 킥 진입 |
| 5–12 | 도시의 기억 · Verse | four-on-the-floor, 중음역 rootless 키, 뒤쪽 짧은 선율 |
| 13–16 | 다가오는 빛 · Lift | 코드와 snare subdivision으로 후렴 준비 |
| 17–24 | f0r h3r · Chorus | half-time backbeat, 8마디 질문/응답 선율 |
| 25–28 | 푸른 공기 · Post | 플럭 응답과 공간 확보 |
| 29–36 | 다시 걷는 길 · Verse B | 첫 verse보다 밝은 연주, 추가 shaker |
| 37–40 | 다시 피는 빛 · Lift | 두 번째 상승 |
| 41–48 | 너의 도시 · Chorus | 핵심 후렴 재현 |
| 49–52 | 북쪽의 밤 · Bridge | 밀도 감소, 길게 이어지는 선율 |
| 53–64 | 마지막 빛 · Final | 후렴 뒤 4마디를 새 종결구로 연결해 F♯에 해결 |
| 65–68 | 잔상 · Outro | 음 수와 velocity를 줄여 마무리 |

Verse는 F♯m9–Dmaj9–Amaj9–C♯7(b9)를 각 2마디씩 사용한다. 후렴은 Dmaj9–E9–C♯m7–F♯m9–Bm9–E9–Amaj9–C♯7(b9) 순서다. 선율은 긴 음 뒤에 휴지를 두고, 높은 플럭은 그 사이를 받친다. 키/소우는 중음역, 베이스는 낮은 단일 위상으로 분담했다. 킥은 독립 트랙이며 소우 compressor의 검출 신호로만 추가 연결한다.

## 편집 튜토리얼

1. 프로젝트를 열고 `⇧⌘P`에서 `f0r h3r · Chorus`를 찾아 Return으로 이동한다.
2. 섹션 안 MIDI 서클을 선택하고 Return으로 확대한다. Tab으로 노트 선택, 방향키로 시간/음높이, Shift 방향키로 길이/옥타브를 편집한다.
3. `빛의 코드` 악기 서클에서 공명·필터 엔벌로프·폭을 바꾼다. `Digi Grid 킥`이 소우 compressor에 sidechain으로만 들어가는 연결을 확인한다.
4. MIDI 서클의 `바운스` 또는 명령 검색의 `선택 트랙을 오디오로 바운스`로 원본을 보존한 오디오 출력을 만든다. 생성된 오디오의 원본 복원 또는 Undo로 되돌린다.
5. 수정판은 ⇧⌘S로 새 이름에 저장한다. ⇧⌘R은 처음부터 음악과 캔버스를 MP4로 기록한다.

## 측정과 판단 경계

`audio-analysis.json`: sample peak **−1.20 dBFS**, clipping **0**, integrated **−17.96 LUFS**, 4× 보간 peak 추정 **−1.19 dBFS**, stereo correlation **0.859**. 과도한 출력 정규화 대신 현재의 다이내믹을 유지했다.

`qa/analyze-song.py`는 ITU-R BS.1770-5 48kHz K weighting과 두 단계 gate를 사용한다. 997Hz stereo sine 및 무음 gate를 검증했다. peak는 97-tap windowed-sinc 4× 추정이며 전체 EBU compliance test 인증은 하지 않았다. 수치가 음색·감정·발매 완성도를 증명하지는 않는다. 모델의 실제 청취 심사는 수행하지 못했으며, 이 버전은 아티스트가 듣고 판단할 제작 후보이다.

프로젝트와 WAV는 라이선스된 미디어를 포함하는 로컬 산출물이다. 비공개 Git 저장소에도 해당 오디오와 프로젝트는 올리지 않는다. 코드·직접 작성한 MIDI·제작/측정 기록을 보관한다.
