# 비교 조사와 출처

확인일: 2026-09-06 · 범위: 제품 개념과 architecture를 위한 공식 자료 검토

사용자가 기존 DAW를 폭넓게 경험했다는 전제에서, 익숙한 기능을 다시 소개하기보다 circlr 설계의 차이와 이미 존재하는 접근을 구분하기 위한 조사다. 모든 DAW의 현재 기능을 전수 비교한 결과가 아니다. 실제 제품을 설치하거나 동일 과제를 실행한 비교도 아니다.

## 음악 작업 방식의 선행 사례

| 대상 | 공식 자료에서 확인한 사실 | circlr에 대한 해석·제안 |
|---|---|---|
| Ableton Live Session View | Scenes로 clip들을 함께 실행하며, scene tempo/meter와 Follow Actions를 설정할 수 있다 | 단순히 섹션을 실행·반복하는 것만으로 차별성을 주장하기 어려움. 사용별 변형과 편곡안의 관계를 검토해야 함 |
| Logic Pro Arrangement Markers | 곡의 구간을 arrangement marker로 정의하고 구간을 이동·복사하는 편곡 작업을 제공한다 | 구간 이동 자체보다 원본 공유, 변형, 전환을 포함한 변경 결과의 예측 가능성을 비교해야 함 |
| Bitwig The Grid | module과 patch cord로 instrument·audio effect·note processing을 구성한다 | 사운드 patching의 익숙한 접근을 활용하되 송폼 순서의 연결 규칙을 별도 정의할 이유가 있음 |
| AudioNodes | Patcher의 node에 속한 audio·MIDI·automation을 Timeline에서 배치한다 | node와 timeline 결합도 이미 존재함. circlr에서는 섹션과 편곡안이 중심 도메인이라는 점을 검증해야 함 |
| Nodal 2.0 | node/edge를 지나는 voice가 MIDI event를 생성하며 edge 길이가 시간에 대응한다 | graph 음악 시스템의 선행 사례. circlr의 기본안에서는 화면 정리가 음악 시간을 바꾸지 않게 함 |

표의 오른쪽 열은 자료에서 도출한 설계 해석이다. 각 제품에 circlr가 제안한 기능이 전혀 없다는 주장이나 완전한 기능 비교가 아니다.

- Ableton: [Session View, Live 12 Manual](https://www.ableton.com/en/live-manual/12/session-view/), 특히 Scenes와 Scene View. [Launching Clips, Live 12 Manual](https://www.ableton.com/en/live-manual/12/launching-clips/), 특히 Follow Actions.
- Apple: [Add arrangement markers](https://support.apple.com/en-ca/guide/logicpro/lgcpb9f20ee5/mac), [Edit arrangement markers](https://support.apple.com/guide/logicpro/edit-arrangement-markers-lgcpf7c0a3d7/mac).
- Bitwig: [Welcome to The Grid](https://www.bitwig.com/userguide/latest/welcome_to_the_grid/), [The Grid devices](https://www.bitwig.com/userguide/latest/the_grid_devices/).
- AudioNodes: [Timeline Overview](https://www.audionodes.com/docs/timeline/).
- Nodal: [Nodal 2.0 Manual](https://www.nodalmusic.com/downloads/NodalManual.pdf), 인쇄 페이지 2 및 20–22. PDF 내부 갱신일은 2019-12-19다. 현재 OS 호환성이나 최신 제품 상태의 근거로 사용하지 않았다.

## 0.3 프리폼 작업 공간 참조

사용자가 ComfyUI를 작업 감각의 기준으로 지정했다. [공식 인터페이스 안내](https://support.comfy.org/articles/7675456845-the-comfyui-interface)는 node를 배치·연결하는 canvas를 중심 작업 공간으로 설명한다. 써클러는 이 접근을 자유 배치·연결·그룹 UX에 참고한다. 그리드·정렬·그룹과 원형 테두리 시간 표현은 사용자 요구와 써클러의 설계 제안이며 ComfyUI 기능의 복제 또는 framework 채택을 의미하지 않는다.

## 구현 기반을 검토하는 데 사용한 자료

| 출처 | 확인한 내용 | 이번 설계에서의 사용과 한계 |
|---|---|---|
| [JUCE 공식 소개](https://juce.com/) | C++ application/plugin framework와 여러 플랫폼·포맷을 소개 | native audio 후보 근거. 특정 host 포맷과 필수 plugin 호환성을 검증한 것은 아님 |
| [JUCE AudioProcessorGraph](https://docs.juce.com/master/classjuce_1_1AudioProcessorGraph.html) | AudioProcessor들을 node로 추가하고 channel을 연결해 재생 | signal graph adapter 후보 근거. SongGraph나 complete DAW 구현을 제공한다는 뜻은 아님 |
| [Tracktion Engine 저장소](https://github.com/Tracktion/tracktion_engine) | sequence 기반 audio application용 high-level 모델과 JUCE module 구조 | 기존 engine 재사용 후보. graph 적합성, 버전 고정, 실제 integration은 미검증 |
| [PortAudio callback 지침](https://portaudio.com/docs/v19-doxydocs/writing_a_callback.html) | callback에서 memory allocation, I/O, mutex 등 blocking/불확정 작업을 피하도록 안내 | realtime thread와 준비 worker 분리의 근거. PortAudio 채택을 뜻하지 않음 |

`latest`, `master` 및 제품 웹문서는 변경될 수 있다. 이번에는 읽기 조사만 수행했으며 dependency를 설치하거나 버전을 선정하지 않았다. 기술 채택 단계에서는 사용할 release/commit과 필요한 계약을 다시 확인한다.

## 조사에서 확정하지 않은 것

- circlr 아이디어의 시장 유일성, 특허성, 사업성
- 특정 engine의 latency·음질·안정성 우열
- 모든 DAW보다 더 빠른 편곡 작업이라는 성능 주장
- 모든 plugin 포맷과 장치의 호환성
- node UI만으로 전문 음악가의 작업 흐름이 개선된다는 사용성 주장

이 항목들은 실제 작업 관찰과 후속 기술 검증으로 확인해야 한다. 현재 자료는 설계 대안을 좁히는 근거다.

## 0.4.0 native 구현 확인 자료

- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine): native graph와 manual offline rendering API 경계.
- [AVAudioUnitSampler](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler): 설치된 Sound Bank의 실제 MIDI 연주.
- [AVAudioUnit](https://developer.apple.com/documentation/avfaudio/avaudiounit): Audio Unit 생성과 host adapter.
- [Offline audio processing](https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing): 준비 PCM과 native render 경로의 근거.

웹 페이지가 JavaScript shell로 제공되는 부분은 설치된 Xcode 26.6의 AVFAudio·AudioToolbox·CoreAudioKit SDK header와 실제 컴파일로 API signature를 확인했다. 실제 PCM 결과와 장치/호환성 주장의 범위는 검증 기록에 따로 적었다.
