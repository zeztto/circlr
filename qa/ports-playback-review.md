# 출력별 신호 시각화 C3a 검증

2026-09-08, `codex/eight-direction-ports`, 기준 `f3b2ba2`. source checkpoint이며 main·사용 앱·녹음 branch를 변경하지 않았다. 새 QA 앱의 UUID는 `B56C481C-5D00-38C5-A021-AC2601DD15BF`, bundle은 `com.circlr.portsqa`다. release source와 QA executable이 일치하고 `codesign --verify --deep --strict`가 통과했다. QA bundle의 버전 표기는 0.19를 유지하며 새 제품 release를 뜻하지 않는다.

## 계약과 검토

각 출력의 node gain·automation 처리 후 PCM을 60 Hz envelope로 요약한다. 섹션 내부 케이블 레벨은 출발 포트의 값에 해당 edge gain을 한 번 적용한 값이다. UI는 occurrence의 로컬 시간과 use gain을 적용한다. 그 값은 master 이후의 청감 크기를 나타내지 않는다. 동시에 겹치는 occurrence의 화면 레벨은 기존 max 정책을 유지한다.

활성 경로는 출력 트랙부터 입력 포트별로 역추적한다. router의 한 OUT에 도달했다고 다른 OUT의 IN까지 활성화하지 않는다. node meter는 독립 출력 envelope의 최댓값으로 만들며 역상 PCM을 합해 소거하지 않는다. 접힌 그룹의 화면 주소 대신 원래 logical edge ID를 조회한다. PCM은 시각화 데이터에 보관하지 않는다. envelope 저장량을 전체 오디오 준비 메모리 검사에 더했다.

read-only 역할 전환 검토에서 callback이 실제 routing buffer를 수정하지 않는지, gain 중복·use 범위·sidechain/MIDI 경로·음소거·stale endpoint를 확인했다. QA helper는 기존 두 fixture와 새 `ports-playback.circlr`만 허용한다. 생성기는 고정된 전용 QA 폴더에 새 프로젝트만 만들고 기존 파일 덮어쓰기를 거절한다. 외부 인증·MCP 쓰기 schema를 변경하지 않았다. 에이전트 한도 해제 안내 후 실제 spawn은 `agent thread limit reached`로 거절됐으며, 독립 리뷰나 병렬 agent 수행을 주장하지 않는다.

## 오프라인 검사

```sh
swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback
swift build -c release --scratch-path .build/ports-release
python3 -m py_compile qa/verify-ports-native.py qa/create-port-playback-fixture.py
```

전체 Swift **190개**, 실패 0, 19.141초. 유일하게 제외한 검사는 실제 장치를 사용하는 `testArrangementRenderExportAndPlayback`다. 새 검사 8개를 포함한다. release **26.73초**, warning/error 없음. MCP·agent kit의 Python 22개는 C2에서 통과했고 해당 코드가 바뀌지 않아 이번에는 재실행하지 않았다.

| 검사 | 확인한 결과 |
|---|---|
| 출력 observer와 node gain/automation | 서로 다른 stereo bus의 실제 출력과 envelope 일치. 관측 on/off의 두 track 및 최종 mix PCM이 정확히 동일 |
| 시간 분리·역상 출력 | 앞/뒤 구간의 출력이 섞이지 않음. 역상 두 bus의 master 합계가 0이어도 두 port와 router meter의 실제 활동은 유지 |
| 비활성 분기 | track mute/gain 0, 끊긴 출력, matrix gain 0, output node mute, output edge gain 0의 여섯 경우에 무관한 IN 2 소스가 표시되지 않음 |
| 교차 matrix | OUT 1이 IN 2를 받을 때 IN 2만 역추적하며 route gain 반영 |
| 분기·sidechain·use gain | main과 sidechain의 서로 다른 edge gain, use gain을 각각 한 번 적용 |
| MIDI·잔향 | 실제 note velocity와 시작/끝, 빈 리듬 경로의 무음, effect tail 케이블 |
| 그룹·반복 | 접힌 화면 endpoint와 logical endpoint가 달라도 올바른 케이블 조회. 두 번째 occurrence의 로컬 시간, 잘못된 endpoint·NaN의 0 반환 |
| 저장량 추정 | 보관한 peak 배열 크기보다 큰 추정값, occurrence 증가에 따른 예산 증가 |

처음 MIDI 검사는 빈 rhythm MIDI까지 실제 노트가 있다고 가정해 실패했다. 그룹 검사는 album 초기화를 빠뜨려 실패했다. 둘 다 fixture/기대값을 수정했으며 제품 동작을 테스트에 맞춰 바꾸지 않았다. 초기 실패 로그도 유지한다.

## 실제 앱·영상

독립 프로젝트 `~/Library/Application Support/circlr-ports-qa/fixtures/ports-playback.circlr`를 생성했다. 프로젝트 ID `A727DC35-BB4D-5C79-AEB1-004A2F0CC2B0`, revision 1. 오디오 두 개 → 2×2 기본 router → 두 track 출력이며, 낮은 세기의 직접 만든 테스트 톤이 4초마다 번갈아 재생된다. 상업용 곡이나 사용자 원본으로 제시하는 음원이 아니다. 마이크 녹음·권한·기본 장치 설정을 변경하지 않았다.

처음 일반 재생은 실제 시계가 0.046→10.217초 진행했다. macOS가 창을 가려진 상태(`windowOccluded=true`)로 보고해 기존 정책에 따라 애니메이션은 중단됐다. 이를 시각화 실패 또는 정상 가시 창 모션의 성공으로 처리하지 않는다.

같은 앱에서 영상 녹화를 시작하면 기존 capture 경로가 가림 상태에서도 모션을 진행한다. 20.445→29.722초의 상태 10개 모두 frame count가 증가했고 **활성 bus 2→1→2의 정확한 두 케이블만** nonzero였다. 측정 구간에서 frame count 1224→1780, 세션 최대 frame 간격 44.907 ms. 이는 일반적인 성능 보장이 아닌 이 작은 fixture에서의 측정이다.

앱이 저장한 `~/Library/Application Support/circlr-ports-qa/fixtures/c3a-ports-motion.mp4`는 **1456×1080 H.264 + AAC, 30.755초, 919프레임, 누락 0**이다. AVFoundation으로 video/audio track과 길이를 읽었다. 영상 1.927초와 5.747초의 원본 프레임을 PNG로 추출해 각각 OUT 1/OUT 2 케이블과 출력 서클이 빛나는 것을 확인했다. 오디오 품질을 청음으로 평가한 것은 아니다. 최종 snapshot에서 재생·MIDI/오디오 녹음 모두 정지, revision 1과 저장 완료를 확인했다.

검증용 프로젝트의 초기 생성은 source signal의 필수 effect 필드, 이전 sampler의 asset 참조 누락 때문에 두 번 열기에 실패했다. 고정된 내장 synth 설정과 필수 필드를 갖추도록 생성기만 수정했다. 성공한 open job은 `F00DF1A3-61D5-438F-A8FB-DEBBC59CE847`다. 실패 fixture는 별도 이름으로 보존했다.

## 증거와 남은 범위

Git에서 제외한 `qa/generated/ports-foundation/`:

- `ports-c3a-targeted-tests.log`, `ports-c3a-full-tests.log`: 초기 검사 실패 포함.
- `ports-c3a-verified-tests.log`, `ports-c3a-release-build.log`: 최종 전체 검사와 빌드.

Git에서 제외한 `qa/generated/ports-ui/`:

- `c3a-before-update.json`, `c3a-final.json`: 교체 전·최종 저장 상태.
- `c3a-playback-identities.json`, `c3a-open-*-request.json`: fixture와 실제 open job.
- `c3a-native-playback.json`, `c3a-native-playback-events.json`: 가려진 일반 창의 재생 기록.
- `c3a-visible-playback.json`, `c3a-native-motion-assertions.json`: **녹화 중** 실제 frame/edge 상태. 파일명의 visible은 macOS의 가시성 판정이 아니며 row의 `windowOccluded`를 기준으로 읽는다.
- `c3a-movie-inspection.json`, `c3a-inspect-movie.swift`, `c3a-movie-frame-2.png`, `c3a-movie-frame-6.png`: MP4 metadata·재현 스크립트·실제 프레임.
- `c3a-native-motion.jpg`는 캡처 시점에 이미 정지한 화면이며 모션 증거로 사용하지 않는다.

키보드·VoiceOver와 작은 창·고밀도 궤도 간섭은 C3b에서 이어간다. 일반 가시 창의 native 모션, 전체 MIDI/sidechain/flow 포인터 행렬, MCP port 명령·그룹 binding, 녹음 branch 통합·v4 full WAV·제품 패키지 출고 gate는 여전히 남아 있다. 이번 작은 MP4는 전체 E gate를 대신하지 않는다.
