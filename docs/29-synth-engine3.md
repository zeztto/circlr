# 내장 신스 엔진 3

0.14.0의 새 patch 기본값은 engineVersion 3이다. 저장된 1/2는 각자의 C render 함수를 유지한다. 누락된 version은 1로 읽으며, 새 4음색을 이전 엔진으로 지정한 잘못된 패치는 거부한다. 기존 v3 곡을 최종 0.14 바이너리로 재렌더한 전체 WAV SHA가 이전과 일치한다.

## 소리

- sine body와 rising saw/pulse의 기음 부호를 맞췄다. 역위상 합으로 bass/lead가 약해지는 문제가 engine 3 비교 과정에서 확인돼 수정됐다.
- pad는 saw/pulse/sine과 느린 pulse-width/filter/drift, bass는 위상 일치 mono pulse/body, keys는 velocity에 따라 감쇠하는 정수 배음, supersaw는 비균일 7-oscillator tuning, pluck는 sine/saw, lead는 sine/pulse/saw를 쓴다. Unison 합성의 레벨 계산을 조정했다.
- electricPiano는 서로 다른 감쇠의 배음과 짧은 7.01배 tine partial, organ은 정수 drawbar partial과 percussion attack, brass는 attack을 따라 열리는 필터, strings는 5-oscillator ensemble이다. partial은 Nyquist 이전에 제외한다. EP는 실제 전자피아노 샘플이나 물리 모델을 복제했다고 주장하지 않는다.
- `character`(배음) 0…1은 voice별 body/배음 비중, `motion`(움직임) 0…1은 pad/strings drift/PWM/filter와 bass를 제외한 chorus 양을 조절한다. width가 0이면 chorus wet은 0이다. 음색에 따라 같은 컨트롤의 효과가 다르다.
- chorus는 2개의 공간화된 가변 delay tap이다. dry 성분을 보존하고 2×2048 float buffer를 초기화 시 준비한다. 연산은 고정 256-frame stack scratch를 사용한다. Callback에서 allocation/mutex는 없다. 본격적인 oversampled analog circuit emulation이나 wavetable import 기능은 구현한 범위가 아니다.

TPT SVF는 [Cytomic의 원문](https://cytomic.com/files/dsp/SvfLinearTrapOptimised2.pdf), chorus의 가변 delay 구조는 [Julius O. Smith의 Physical Audio Signal Processing](https://www.dsprelated.com/freebooks/pasp/Chorus_Effect.html)을 참고했다. 특정 상용 악기의 사운드를 측정·복제한 것으로 표현하지 않는다.

## 조작과 에이전트

악기 서클 확대 → 내장 신스 → 음색. engine 3에는 배음/움직임 필드가 표시된다. 이전 patch에는 `신스 엔진 3으로 전환` 버튼이 있으며 기존 숫자를 유지한 채 version만 바꾸고 Undo할 수 있다. 음색 선택은 해당 음색의 기본 patch를 새로 적용한다.

콘솔: `synth pad|bass|keys|supersaw|pluck|lead|ep|organ|brass|strings`.
MCP `synthVoice`: 0…9. 자세한 값은 [MCP 계약](../mcp/README.md)을 따른다. `instrument.synth`를 수정할 때 snapshot의 전체 Instrument를 읽고 필요한 값을 바꾼다. 프로젝트 로컬·앱 동봉 Codex kit도 0.14로 갱신했다.

## 메모리·검증

15트랙/194초의 전체 버퍼 준비에는 이전 고정 1GiB보다 많은 메모리가 필요했다. 새 전체 렌더 한도는 **물리 RAM의 1/4와 2GiB 중 작은 값**이다. 섹션 내부 한도는 기존 1GiB를 유지한다. 128GiB Mac의 실제 CLI 렌더 최대 RSS는 약 1.74GB였다. 한도를 넘으면 구간 내보내기를 안내하며 무제한으로 늘리지 않는다. 전체곡 stem은 더 많은 메모리가 필요하므로 `section-stems`는 한 섹션의 post-effect/pre-master 출력을 순차 WAV로 저장한다.

검증은 parameter round trip/range, 1/2 호환, waveform body 상쇄 방지, block size 동일성, additive callback, polyphony/steal/overflow recovery, 극단 pitch/resonance/release, 실제 UI edit/Undo와 native export/bounce를 포함한다. [QA 증거와 경계](../qa/0.14-review.md).
