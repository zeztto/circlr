# 내장 신스 resonance 오토메이션 계획

상태: 다음 기능의 계약 계획이며 미구현이다. cutoff와 resonance를 함께 움직이는 필터 sweep의 음악적 표현을 목표로 한다. 새 oscillator·MIDI CC·plugin host 확장은 범위 밖이다.

## 파라미터와 지원 범위

`SynthPatch.resonance`의 기존 기본값은 0.12이고 유효 범위는 0…0.9다 (`ProductionModel.swift`). 저장·MCP 값은 0…0.9, 화면은 raw×100인 0…90%다. plot 위치만 raw/0.9로 전체 폭에 linear 매핑하며 상한을 100%로 재해석하지 않는다. 기본 0.12는 12%다. 곡선이 없을 때 실제 patch.resonance를 사용하며 고정 0.12로 덮지 않는다.

`synth.c`의 engine v2/v3 SVF는 `k = 2 - 1.6 * resonance`로 값을 사용한다. engine1에는 해당 처리가 없으므로 `.instrument`이며 kind가 synthesizer이고 effective engineVersion이 2 또는 3인 경우만 지원한다. legacy engine1을 자동 승격하거나 sampler/AU에 같은 파라미터를 있다고 가정하지 않는다.

기존 hold/linear/smooth 보간·clock·공유 원본/이번 use·반복·release tail의 마지막 값 유지 의미를 따른다. cutoff와 resonance를 함께 sample 단위로 적용하되 voice·phase·filter state·source별 pitch bend를 유지한다. 블록마다 악기를 다시 생성하지 않는다.

## 구현 경계와 소스 지도

- `Sources/CirclrCore/Automation.swift`: enum·지원 판정·fallback·검증·set 및 필요한 schema 승격을 함께 설계한다. 현재 schema5에서 최초 실제 곡선 편집 시 schema6로 승격한다. 구파일/Undo 호환과 미지원 target 거절을 검증한다.
- `AutomationDisplay.swift`, `StudioWorkspace`: percent 표시·linear 위치와 미지원 선택의 fallback을 연결한다.
- `Sources/CirclrApp/AutomationCapabilities.swift`: gain/pan 이외를 모두 Hz로 취급하는 현재 단위 분기를 바꾼다. `AutomationEditor.swift`에 네 번째 파라미터와 % 수치 표현을 연결한다.
- `AgentWorkspace.swift`의 runtime capability `synthResonanceAutomation: 1`, `mcp/server.py`의 enum·범위·strict set_automation 및 최신 capability gate를 함께 추가한다. GUI와 MCP가 같은 저장 단위를 쓴다.
- `Sources/CirclrAudio/AutomationDSP.swift`: cutoff 전용 cursor를 최소한의 파라미터별 cursor로 확장한다. `ProductionInstrument.swift`는 cutoff/resonance sample buffer를 함께 전달한다.
- `Sources/CirclrRealtime/include/CirclrSynth.h`와 `synth.c`: 새 render API를 추가하되 기존 API·기존 voice 상태와 결과를 유지한다. C의 invalid sample은 patch fallback을 둘 수 있지만 Core/MCP의 잘못된 요청은 명시적으로 거절한다.

## 검증 계획

1. 0/0.9 허용·0.9 초과와 1 거절·invalid·실제 patch 기본값·% 표시·보간·clock과 shared/use scope를 확인한다. engine1·sampler·AU·잘못된 node는 거절하고 음악을 보존한다.
2. C/DSP에서 nil·constant의 기존 API/PCM 보존, v2/v3 변화의 filter 응답, cutoff와 동시 작동·block 크기 독립성·pitch bend/voice continuity·release tail을 비교한다.
3. schema 저장/읽기·Undo와 악기/engine 변경 후 기존 곡선의 지원 검증을 연결한다. 미지원 상태를 조용히 무시하지 않는다.
4. GUI/MCP의 동일 값·단위·atomic 실패·stale/capability 거절을 확인한다. 작은 캔버스의 파라미터·곡선·수치 가시성을 native로 검증한다.
5. 한 곡의 filter sweep 편집→오프라인 출력→바운스·원본 복원→저장/재열기로 의도한 변화와 음악·자산 보존을 대조한다. 실제 청취·물리 I/O는 별도 증거다.

이 문서는 소스 기반 후속 계획이다. 테스트 수치나 구현 완료를 미리 기록하지 않으며 build146 배치 변경의 성공 범위에 포함하지 않는다.

## 저장·atomic 보강

ProjectStore·Compiler·AlbumModel·migration의 최대 schema guard를 검색해 함께 갱신한다. 파일을 열기만 해서는 승격하지 않으며 clear 뒤 자동 downgrade하지 않는다. 구앱은 새 enum을 안전하게 거절해야 하지만 이미 배포된 구앱의 친절한 버전 오류 문구까지 보장할 수는 없다.

원본 graph·use override·비활성 variant·bounce snapshot까지 공통 supports 판정을 사용하고 disabled lane도 미지원 곡선 저장을 허용하지 않는다. `AppStore.mutate`는 kind 변경뿐 아니라 같은 synthesizer kind의 engine3→1 변경도 검증해야 한다. AgentProjectEditing의 최종 구조 검증과 GUI가 같은 atomic 결정을 내리며 실패 시 project·schema·revision·Undo는 그대로여야 한다.

예정 검사는 Core/Audio 각각의 `SynthResonanceAutomationTests.swift`와 `Tests/test_mcp_resonance.py`로 분리한다. 기존 cutoff·MIDI tempo·pitch bend·SynthCore 회귀를 선별한다. Audio는 nil/disabled/constant와 cutoff-only legacy PCM 보존, finite 응답·spectrum 변화·block 31/64/257 일치, tempo/반복/pitch bend 동시 적용과 tail·bounce 복원을 검사한다. Core는 비활성/bounce target·engine 변경·schema6·Undo까지, MCP는 capability·stale·범위·target·실패 batch 불변을 검사한다.

범위 근거는 `ProductionModel.swift`의 SynthPatch.validate와 `InspectorView.swift`의 정적 UI가 모두 사용하는 finite 0…0.9다. C는 별도 clamp 없이 resonance를 사용하므로 새 stream 역시 이 범위를 검증하고 invalid sample은 patch 값으로 fallback한다.
