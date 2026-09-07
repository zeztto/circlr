# f0r h3r — v3

써클러의 편집 가능한 배포용 튜토리얼 곡. v2의 송폼·화성·멜로디·3,119 MIDI 노트와 내장 엔진 2를 유지하고 외부 샘플 6개를 **FreePats CC0**로 교체했다. Splice 계정이나 별도 샘플 구매 없이 프로젝트를 열 수 있다. v1/v2는 보존했다.

- [프로젝트](f0r%20h3r.circlr) · [48kHz/24-bit stereo WAV](f0r%20h3r.wav) · [MIDI](f0r%20h3r.mid)
- 116 BPM / 4/4 / F♯ minor / 68마디 / 9트랙 / 2분 22.7초
- [제작 기록](production-report.json) · [측정](audio-analysis.json) · [미디어 감사](license-audit.json)
- [샘플 출처·가공·hash](sample-license/manifest.json) · [CC0 원문](sample-license/LICENSE)

## 바뀐 소리

네온 킥: Kick04. 네온 드럼: Snare14, ClosedHiHat01-01, ShakerLong01, HighTom02-01. 빛의 잔향: Cymbal01-01. 모두 FreePats synthesizer percussion 2022-07-18의 Roberto 제작 소리다. 20Hz DC 정리와 peak trim을 거쳤으며 원본 샘플의 CC0 조건으로 가공·동봉할 수 있다. 곡 전체를 CC0로 선언한 것은 아니다. [공식 출처](https://freepats.zenvoid.org/Percussion/electric-percussion.html).

## 따라 하기

1. 써클러 0.13 이상에서 프로젝트를 연다. `⇧⌘P`에서 `f0r h3r · Chorus`로 이동한다.
2. MIDI 서클에서 Return으로 편집하고 Tab·방향키로 노트·시간·음정을 바꾼다.
3. `네온 드럼` 악기 서클에서 MIDI 38/42/70/50과 각 샘플 연결을 확인한다. 킥은 별도 `네온 킥` 트랙이며 `빛의 코드` compressor의 sidechain을 구동한다.
4. 선택 트랙을 오디오로 바운스하고 원본 복원 또는 Undo로 돌아간다.
5. `⇧⌘S`로 새 사본을 저장한다. 저장 시 미디어도 프로젝트 내부에 포함된다.

곡의 11섹션과 코드 진행은 [구성표](FORM.md)에서 확인한다. v3는 샘플 교체판이며 새 멜로디나 편곡을 덮어쓰지 않았다.

## 재현

저장소 root에서 실행한다. Python 3, macOS tar와 기존 Swift 도구를 사용한다.

```sh
python3 scripts/prepare-demo-samples.py
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-studio
.build/app-release/release/circlr-studio make-demo music/f0r-h3r/rebuilt
python3 qa/verify-demo-license.py 'music/f0r-h3r/rebuilt/f0r h3r.circlr'
```

이미 결과가 있는 위치를 덮어쓰지 않는다. 완성 프로젝트·WAV와 전체 샘플의 로컬 패키지는 `dist/f0r-h3r-v3-portable.zip`에 있다. Git에는 소스·MIDI·출처/허가·측정 기록을 보관하며 오디오·프로젝트는 위 명령으로 재구성할 수 있다.

Sample peak −1.20dBFS, clipping 0, integrated −18.30LUFS, 4× 보간 peak 추정 −1.01dBFS다. 측정은 자체 QA 도구이며 실제 청취·발매 판단을 대신하지 않는다. 실제 재생 장치와 화면 녹화의 기존 검증 경계도 유지한다.
