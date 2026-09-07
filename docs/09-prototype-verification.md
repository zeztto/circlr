# 0.4.0 프로토타입 검증 기록

현재 UI 검증은 [0.7.0 통합 서클 편집 검증](../qa/0.7-review.md)을 참고한다. 아래 내용은 이전 실행 기록이다.

이 문서는 0.4.0 당시의 검증 이력이다. 현재 0.5.0 화면·장치 대기·검증 제한은 [하나의 캔버스 검증](10-single-canvas-redesign.md)을 따른다. 아래 공용 `qa/generated/` 로그와 파일은 후속 실행으로 변경될 수 있어 현재 버전의 완료 근거로 사용하지 않는다.


검증일: 2026-09-06 · 실행 OS: macOS 26.5.1 (25F80), arm64 · 대상: 이 workspace의 `dist/써클러.app` · 상태: 로컬 실행 프로토타입 전달 가능

실제 앱·오디오 경로를 확인했다. 이 판정은 [프로토타입 계약](08-prototype-contract.md)의 범위이며, 장기 DAW 전체 사양이나 제3자 plugin/모든 장치의 제품 release 인증을 뜻하지 않는다.

## 자동 검증

최종 명령 `./scripts/verify.sh`가 exit 0으로 끝났다. XCTest **16개, 실패 0개**이며 release app build와 `codesign --verify --strict`가 통과했다. 마지막 전체 테스트는 2026-09-06 23:05:40 KST에 완료했다.

- [전체 테스트 로그](../qa/generated/tests.log)
- [앱 빌드 로그](../qa/generated/build.log)
- [실제 오디오 보고서](../qa/generated/audio-report.txt)
- [WAV 속성·해시와 원본 보존](../qa/generated/artifact-facts.json)
- [실제로 조작한 UI 프로젝트 데이터](../qa/generated/ui-data-evidence.json)
- [소스·실행 파일 SHA-256](../qa/generated/source-sha256.json)

Core 10개는 필드별 상속/global reset, tempo·변박과 시계 역변환, ring angle, 명시적 반복/펼치기, 공유 원본/변형/편곡안, layout 독립성, 순환·미선택 분기·orphan override·3중 겹침 오류, package 원본 byte 보존과 경로 이탈을 검사한다.

Audio 6개는 실제 Sound Bank MIDI render, note 시작 전 무음/시작 후 PCM, pattern 반복과 swing, 오디오 파일·구간 읽기, time-stretch, DSP, transition에 의한 실제 PCM 변화, signal gain, bounded 녹음 writer, 가상 CoreMIDI의 다중 packet, WAV/stem export와 AVAudioEngine 재생 시계 진행을 검사한다. WAV는 이름만 확인하지 않고 RIFF/WAVE header도 검사했다. Export가 기존 일반 폴더를 덮어쓰지 않는 실패 경로도 확인했다.

## 실제 native UI 검증

컴퓨터 제어 도구로 최종 앱을 실행하고 접근성 상태와 실제 창 이미지를 확인했다. 이미지 확인은 이 작업 대화의 native screenshot 출력에 남아 있다. 아래 작업은 테스트 모델에 직접 값을 넣은 것으로 대체하지 않고 화면에서 수행했다.

1. 빈 프로젝트에서 `검증 Verse`를 만들고 piano roll에 note 3개 입력. 재생 버튼이 정지로 바뀌고 transport가 1.1초로 진행하는 것을 확인했다.
2. 서클 다시 사용 → `검증 Chorus`로 이름 변경 → 개별 96 BPM. Verse는 글로벌 120 BPM 상속을 유지했다. Verse → Chorus 연결 후 총길이는 36초였다.
3. Chorus를 끌어 이동하고 영역 다중 선택 → 그룹 생성 → native 저장. 파일에는 원본 1개, 사용 위치 2개, 각 note 3개, 연결 1개, 그룹 1개, snap 좌표 `(432, 120)`이 보존됐다.
4. 그룹 접기 → ⌘Z 실행 취소 → 저장 → native 열기 패널에서 프로젝트 다시 열기. 두 서클과 그룹, 36초 길이가 복원됐다. 프로젝트 대신 부모 폴더를 선택한 경우 오류가 표시되고 기존 곡이 유지되는 것도 확인했다.
5. 별도 QA 곡에서 120 BPM·4/4와 96 BPM·7/8, overlap 0.5초, Chorus 총 2회 표시를 확인했다. 원형 테두리와 그룹, 포트 연결이 실제 그려졌다.
6. 사운드 보기에서 Low-pass를 추가해 `피아노 → Low-pass → 출력`, `드럼 → 출력` 경로가 생성되는 것을 확인했다.
7. 앱의 WAV 내보내기 메뉴로 `UI-final-export.wav`를 만들고 실제 파일의 header·채널·sample rate·길이·PCM 값을 확인했다. `UI-sound.circlr`로 별도 저장하며 원본 media checksum도 대조했다.
8. 최종 화면 보정본에서 가로 정렬과 zoom을 조작했다. 세 원의 y 좌표가 `41.6666666667`로 같아졌고 zoom은 `1.6940841675`로 저장됐다. 음악 길이는 15.875초로 유지됐다.
9. 화면 건반으로 MIDI를 녹음했다. 2개 note를 가진 take 1개가 보존되고 사용 위치의 override에만 반영됐다. 세 원본 섹션의 note는 각각 8개 그대로였다.
10. 최종 보정본에서 그룹 제목과 시작 배지가 겹치지 않으며, 선택 전 불필요한 빈 편집 공간이 사라진 화면을 다시 확인했다.

## 오디오 결과

자동 검증 곡은 QA 목적의 통제된 악보/입력이다. 사용자 곡이나 제품 기본 콘텐츠가 아니다. 곡 본문 15.875초에 고정 tail 2초를 더한 결과다.

| 파일 | 형식 | 길이 | Peak | RMS |
|---|---|---:|---:|---:|
| `render.wav` / `stereo-export.wav` | 2ch, 48 kHz, 24-bit WAV | 17.875초 / 858,000 frames | 0.131530 | 0.016300 |
| `stem-piano.wav` | 동일 | 17.875초 | 0.102990 | 0.012124 |
| `stem-drums.wav` | 동일 | 17.875초 | 0.080087 | 0.011098 |
| `UI-final-export.wav` | 동일, Low-pass 추가 | 17.875초 | 0.117510 | 0.015469 |

자동 renderer와 stereo export 파일의 SHA-256이 일치한다. Low-pass를 추가한 UI export는 길이를 유지하면서 실제 PCM이 달라졌다. 이 숫자는 실제 신호·파일·재생 경로의 증거이며 사람의 주관적 청감 평가를 대신하지 않는다. 장기 session의 음질·latency 평가를 수행했다는 뜻도 아니다.

`UI-final-export.wav`는 Low-pass 추가 후, 후속 MIDI take 검증 이전의 revision이다. `UI-sound.circlr`에는 그 뒤 수행한 가로 정렬·zoom·MIDI take도 보존돼 있다. 둘이 동일 revision의 오디오라고 표현하지 않는다.

## 계약별 판정

| 기준 | 구현과 근거 | 검증 범위 |
|---|---|---|
| A01 앱 | arm64 Mach-O, app bundle, local 서명, 실제 실행 | 현재 Mac에서 확인 |
| A02 canvas | 원형·drag·다중 선택·정렬·group·grid/snap·zoom과 파일 복원 | 실제 UI + 저장 JSON. Trackpad pinch의 제스처 실기는 별도 |
| A03 ring/시간 | 마디·박 눈금, 반복 표시, local tempo/meter, 재생 위치 | domain 계산 + 실제 창. 혼합 meter의 수학은 자동 검증 |
| A04 context | 항목별 inherit/global/local, 분리된 BeatGrid/Pattern, local off | domain tests + 96 BPM UI. 모든 조합을 UI에서 반복하지 않음 |
| A05 편곡 | 공유 원본/변형/분리, 연결·반복, A/B 복제, 삽입 | domain tests + 재사용/연결 UI. 큰 분기 그래프 usability는 별도 |
| A06 MIDI/악기 | 실제 sampler, pattern, CoreMIDI, 화면 건반/녹음, Audio Unit host | 기본 AU·가상 MIDI·native UI 확인. 제3자 전체 호환성은 미검증 |
| A07 audio/take | 원본 복사·clip·녹음 writer·보존 take | 실제 파일/PCM/writer 확인. 실제 마이크·외부 interface 녹음은 미검증 |
| A08 effect/전환 | DSP·signal graph·within/insert/overlap | PCM 변화·시간 tests + Low-pass UI/export. 완전한 PDC는 미구현 |
| A09 저장/오류 | transactional package, undo/redo, recovery, 오류 표시 | save/open/undo 실제 확인, 원본 byte·경로 tests. 강제 종료 복구 실험은 미실행 |
| A10 export/play | stereo/stems, 고정 tail, clipping guard, native playback | 실제 WAV header/길이/PCM/stem/재생 시계 + UI export |
| A11 문서 | README·CHANGELOG·architecture·계약·현재 검증 기록 | 파일과 구현 상태 대조 |

## 발견해 수정한 사항

| 문제 | 수정과 확인 |
|---|---|
| 녹음 callback이 매번 buffer와 queue 작업을 할당 | 사전 할당 C11 atomic ring + disk consumer, writer sample 보존 test |
| 여러 MIDI packet을 stack copy에서 순회 | 원래 packet list의 메모리 위치를 순회, 실제 3-packet 입력 test |
| 반복 녹음 take가 겹쳐 모두 재생 | take를 모두 보존하고 하나를 lane에 활성화. UI 2-note take와 원본 보존 확인 |
| 취소된 render 결과가 늦게 게시될 가능성 | worker cancellation + generation 검사 |
| 정지 뒤 링에 재생 상태가 표시됨 | 실제 playing 상태에서만 occurrence indicator를 그림 |
| 임시 파일 이름에 확장자가 없어 CAF가 `.wav`로 이동됨 | `.wav` staging, RIFF/WAVE header 검사와 실제 export 대조 |
| 앱과 테스트의 virtual MIDI endpoint 이름 충돌 | 테스트별 고유 endpoint, 최종 16개 전체 통과 |
| 숫자 편집 후 Return 없이 적용 시 이전 값 사용 가능 | 유효한 숫자 입력을 즉시 binding에 반영 |
| 그룹 제목과 시작 표시 겹침 | 시작 배지를 원 내부로 이동하고 실제 창 재확인 |
| 선택 전 빈 편집기가 canvas를 차지 | 편집 대상을 고른 경우에만 editor 표시 |

## 남은 범위와 제품 사용 제한

- 실행 환경은 이 Mac의 Apple Silicon이다. Intel binary, macOS 14 실기, 설치·공증·자동 업데이트·배포는 미검증이다.
- 재생은 먼저 만든 PCM을 사용한다. 실시간 graph 교체, 녹음 count-in·반주 동시 녹음, comping, 입력 latency 보정, 연속 pattern phase, 상세 파형/automation 편집은 현재 범위 밖이다.
- 제3자 AU의 process 격리·crash 복구·정확한 latency compensation·모든 preset/editor 호환성을 보장하지 않는다. 기본 sampler와 native effect 경로에서 검증했다.
- 공유 nonlinear effect가 있는 경우 source별 stem 합과 mix가 다를 수 있다. 현재 전용 return stem 분리 규칙은 제공하지 않는다.
- Tail은 2초 고정이다. 긴 reverb/delay의 전체 자연 감쇠를 보장하지 않는다. 준비 메모리 1 GB, 단일 decode buffer 256 MB 등의 한도가 있다.
- MIDI는 note on/off와 현재 선택 트랙을 중심으로 한다. 외부 장치는 앱 시작 시 연결된 source를 연결한다. MIDI 2.0, MPE, 세밀한 host timestamp 보정·입력 선택 UI는 후속 범위다.
- 마이크 권한 부여나 사용자의 실제 주변 오디오 녹음은 수행하지 않았다. TakeWriter 검증을 실제 마이크 녹음 검증으로 표현하지 않는다.
- 복구 snapshot과 저장 전 오디오 take는 사용자 Application Support의 `circlr/`에 둔다. 장기 디스크 부족·전원 차단·복구 UI 시나리오는 별도 검증한다.
- 큰 프로젝트/다수 plugin/오랜 녹음/VoiceOver 전체 편집/고해상도 또는 작은 화면별 검증은 별도다.

이 한계는 README에도 노출했다. 동작하지 않는 미래 기능을 제품 UI에 ‘coming soon’으로 만들지 않았다. 검증용 악보와 오디오는 `qa/generated/`에만 있으며 app bundle에는 실행 파일과 Info.plist만 포함한다.
