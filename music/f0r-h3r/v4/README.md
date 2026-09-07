# f0r h3r · v4 Club Arrangement

120 BPM · F♯ minor · 4/4 · 96마디 · 3:14 · 15트랙. 북유럽 신스웨이브의 공간감과 city pop의 EP/확장화음, future bass의 코드 질감을 곧은 클럽 그루브에 배치했다. 이전 v1–v3는 보존한다.

[후렴 32초 미리듣기](chorus-preview.wav) · [전체 WAV](f0r%20h3r.wav) · [써클러 프로젝트](f0r%20h3r.circlr) · [직접 작성한 MIDI](f0r%20h3r.mid) · [구성과 악기 역할](FORM.md).

## 이번에 바뀐 음악

- 킥은 매 박, 스네어는 2·4박, 하이햇은 엇박. 후렴에서도 기본 그리드를 유지한다. 반복 tom fill, snare roll, 상시 16분 셰이커를 제거했다. 전체 2,562 notes이며 곡이 길어져도 v3의 3,119 notes보다 적다.
- 16마디 intro/outro. 첫 8마디와 끝 8마디는 harmonic MIDI 없이 드럼으로 연결할 수 있다. 중간 breakdown은 6마디 킥을 비우고 마지막 2마디에서 곧은 그루브로 복귀한다.
- 6종에서 10종으로 늘어난 신스의 발음과 역할을 구분했다. EP가 코드, lead가 주선율, organ이 리듬 응답, brass가 구간 끝 강조, strings가 마지막 후렴 확장을 맡는다. 모든 트랙이 계속 연주하지 않는다.
- 베이스와 리드의 sine/pulse/saw 기음 상쇄를 새 엔진에서 해결했다. 킥 사이드체인을 베이스·패드·코드·스트링에 연결하되 첫 렌더보다 과한 감쇄를 줄였다. 공간계는 킥/베이스/하이햇에 넣지 않았다.

## 앱에서 확인하기

1. 써클러 **0.14.0**을 실행하고 ⌘O로 `f0r h3r.circlr`를 연다. 실행 중인 이전 앱은 저장 후 ⌘Q로 종료해야 새 바이너리가 실행된다.
2. 곡 → Club Chorus를 확대한다. 각 MIDI·악기·효과·출력 서클은 실제 데이터와 연결돼 있다.
3. `도시의 벨벳 EP` 악기 서클을 확대하면 필터·ADSR·공명·폭과 새 **배음/움직임**을 편집할 수 있다. ⌘Z로 원복한다.
4. `빛의 코드` 출력 서클을 선택해 바운스한다. MIDI→신스→컴프레서와 킥 sidechain을 포함한 오디오를 생성하며 원본은 보존한다. 원본 복원/Undo를 사용할 수 있다.
5. ⌘E는 전체곡 WAV 내보내기다. 실제 QA 앱의 결과가 동봉 WAV와 바이트 단위로 일치했다. 전체 15-track stem 동시 렌더는 메모리 한도에 걸릴 수 있으므로 아래 섹션 stem 명령을 사용한다.

`chorus-stems/`는 첫 후렴의 악기별 출력이다. 섹션 이펙트·track gain을 포함하며 앨범 master bus 이전이다. 해당 구간에서 쉬는 arp와 strings 파일은 무음이다. 이는 장식 트랙이 아니라 intro/lift/break/final에서 사용된다.

`sound-bank/`에는 외부 이펙트 없이 렌더한 기본 10음색과 기존 6음색의 engine 2/3 비교 WAV가 있다. 각 비교의 앞 2초 RMS를 맞추되 peak 상한을 우선했으므로 `manifest.json`의 실제 레벨을 참고한다. 단순한 볼륨 차이보다 attack·배음·지속·스테레오 움직임을 비교할 수 있다.

## 재현

저장소 루트에서 실행한다. 기존 출력 폴더는 덮어쓰지 않으므로 새 폴더를 지정한다.

```sh
python3 scripts/prepare-demo-samples.py
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-studio
.build/app-release/release/circlr-studio make-demo music/f0r-h3r/recreated-v4
.build/app-release/release/circlr-studio sound-bank music/f0r-h3r/recreated-v4/sound-bank
.build/app-release/release/circlr-studio section-stems 'music/f0r-h3r/recreated-v4/f0r h3r.circlr' music/f0r-h3r/recreated-v4/chorus-stems 3
python3 qa/verify-club-demo.py 'music/f0r-h3r/recreated-v4/f0r h3r.circlr'
python3 qa/verify-demo-license.py 'music/f0r-h3r/recreated-v4/f0r h3r.circlr'
```

`make-demo-v3`는 기존 엔진 2 편곡 생성 경로다. `render 프로젝트.circlr 출력.wav`는 저장된 곡을 그대로 렌더한다. 랜덤 ID 때문에 프로젝트 JSON은 재생성 시 달라질 수 있으나 곡의 notes/clock/오디오 생성은 결정적이다.

## 출처와 검증 경계

외부 미디어는 고정 hash로 검증한 FreePats CC0 bank 6파일이다. 이번 편곡에서는 tom 음표를 사용하지 않는다. 원본 허가와 출처는 `sample-license/`, 전체 파일 감사는 `license-audit.json`에 있다. Splice 구매·크레딧 지출은 0이다. MIDI와 곡은 이 프로젝트에서 직접 작성했다.

동봉 WAV: 48kHz/24-bit stereo, sample peak −1.50dBFS, 자체 측정 integrated −17.48LUFS, 4× 보간 peak 추정 −1.36dBFS, clipping 0. `audio-analysis.json`에 상세 값과 측정기 한계를 기록했다. 재생 장치가 Scarlett 6i6인 환경의 기존 실시간 연결 문제는 이번 오프라인 렌더 확인으로 해결됐다고 보지 않는다.

모델의 직접 청취는 수행하지 못했다. 이번 결과는 편곡·합성·밸런스 수정과 native export/bounce 검증을 마친 아티스트 청취용 버전이다. 클럽에서의 저역 전달, 멜로디 전면감과 장시간 피로도는 실제 시스템에서 평가해야 한다.
