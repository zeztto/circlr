# f0r h3r

현재 개정판은 [v4 Club Arrangement](v4/README.md)다. 120 BPM, 96마디·15트랙, 신스 엔진 3과 단순한 클럽 그루브를 적용했다. CC0 미디어를 사용하며 v1–v3는 보존한다. [v3 CC0 교체 기록](v3/README.md). 아래는 v1 당시 기록이다.

써클러에서 MIDI 생성·신스·샘플·이펙트·오디오 바운스를 직접 확인하기 위한 한 곡이다. 북유럽 신스웨이브의 차가운 pad와 저음 pulse, 일본 city pop의 확장 코드와 keys, future bass의 잘게 끊는 saw 코드를 조합했다.

- [편집 가능한 프로젝트](v1/f0r%20h3r.circlr)
- [Master WAV](v1/f0r%20h3r.wav) · 48 kHz / stereo / 24-bit
- [MIDI](v1/f0r%20h3r.mid) · 8개 트랙의 직접 작성한 노트
- [제작 기록](v1/production-report.json) · [PCM 측정](v1/audio-analysis.json)

116 BPM, 4/4, F♯ minor. 48마디, 8트랙, 본편 99.31초와 잔향 2초다. 총 2,728개의 MIDI 노트를 포함한다. 본편 렌더의 peak는 약 −1.2 dBFS이고 clipping sample은 0개다. 이 수치는 음질에 대한 청음 평가를 대신하지 않는다.

## 곡을 따라가며 편집하기

1. 써클러 0.9에서 프로젝트를 열고 재생한다. 연습 변경은 **다른 이름으로 저장**해서 보관한다.
2. 곡 서클 안에서 `f0r h3r · Chorus`를 확대한다. MIDI 소스, 악기, 이펙터, 믹스와 출력의 연결을 확인한다. 휠 위로 확대, 아래로 축소, Esc로 상위 서클에 돌아간다.
3. `그녀의 모티프` MIDI 서클을 확대한다. 빈 격자 클릭으로 노트를 입력하고 노트를 드래그해 이동한다. 오른쪽 끝은 길이, 아래 입력값은 음높이·세기·시작 박을 바꾼다. 생성 메뉴는 코드·아르페지오·베이스·펄스 노트를 실제 lane에 추가한다. 원본 노트를 확인한 뒤 생성하고 Undo로 되돌려 비교한다.
4. 연결된 악기 서클에서 내장 신스의 pad/bass/keys/supersaw/pluck/lead, cutoff와 ADSR를 편집한다. 트랙의 악기 설정은 같은 트랙을 사용하는 섹션에도 반영된다. `Digi Grid 드럼`은 각 MIDI pitch에 kick/snare/hat/shaker/tom을 매핑한 sample 악기다.
5. 이펙터 서클을 확대해 delay/reverb 등의 값을 편집한다. Future bass 코드의 compressor에는 드럼 sidechain을 연결했다. 노드의 위치와 실제 오디오 연결은 별개이며 출력까지 연결된 경로가 소리를 만든다.
6. MIDI/악기 편집에서 **오디오 바운스**를 실행한다. 해당 섹션·트랙의 내부 이펙트와 sidechain을 거친 실제 WAV가 오디오 서클로 추가된다. 기존 입력은 출력에서 분리되어 두 번 재생되지 않는다. track/global gain은 이후 경로에서 한 번 적용된다.
7. 생성된 오디오 서클의 **원본 복원**으로 MIDI·악기·이펙트 경로를 되살릴 수 있다. 렌더한 오디오는 연결이 끊긴 보관 서클로 남는다. 단순 작업 취소는 Undo다.
8. ⌘S는 미디어를 포함한 `.circlr` 저장, ⌘E는 전체 앨범 WAV 내보내기다. MIDI 편집 메뉴의 MIDI 저장은 현재 lane을 `.mid`로 저장한다.

현재 서클 배치는 자유로운 계층형 노드 캔버스다. 자식의 각도를 시간으로 바꾸는 궤도 편집과 원호형 노트 편집은 [궤도 설계](../../docs/16-orbital-production-plan.md)의 다음 구현 단계다.

## 콘솔과 에이전트

하단 콘솔에서 실제 작업 로그와 렌더 상태를 확인한다. Ctrl+`로 접고 펼친다. `help`, `state`, `play`, `stop`, `undo`, `save`를 입력할 수 있다. MIDI 서클 선택 후 `midi arpeggio`, 트랙 선택 후 `synth pluck`, `bounce`도 동작한다.

외부 에이전트는 [MCP 연결](../../mcp/README.md)로 snapshot → inspect → apply → bounce/export → job/events → save 순서로 작업한다. 화면 선택이나 마우스 조작이 필요하지 않다. 앱을 최소화해도 연결이 유지된다. ⌘Q로 종료하면 연결도 종료된다.

## 소재 기록

Splice 보유 라이브러리의 **Digi Grid Outrun Sounds**에서 kick, snare, closed hat, shaker, high tom, wave FX 6개를 로컬 동기화했다. 추가 구매는 **0 credits**, 승인 한도는 10 credits다. 작업 당시 잔액은 전후 4,545로 같았다. 파일 이름·출처·SHA-256은 제작 기록에 있다.

로컬 프로젝트에는 사용자의 라이선스된 원본 샘플이 포함된다. 이 폴더의 `.circlr`와 WAV는 공개 앱 번들 및 소스 버전 관리에서 제외한다. 소스만으로 재제작하려면 해당 6개 샘플이 사용자의 Splice 폴더에 있어야 한다. MIDI는 직접 작성했으며 Splice MIDI 구매는 하지 않았다.

## 재현

프로젝트 루트에서 `./scripts/swift-local.sh build -c release --product circlr-studio`로 제작 도구를 빌드한다. 다음 명령의 출력 폴더는 새 경로여야 한다.

```sh
.build/release/circlr-studio make-demo music/f0r-h3r/v2 /Users/sungwoonjeon/Splice
.build/release/circlr-studio render 'music/f0r-h3r/v1/f0r h3r.circlr' /private/tmp/f0r-h3r-render.wav
```

이 제작 도구, 앱 재생, MCP export는 같은 Core/Audio 엔진을 사용한다. 외부 상용 DAW로 미리 렌더한 음악을 대신 재생하는 구조가 아니다.
