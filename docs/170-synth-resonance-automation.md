# 내장 신스 resonance 오토메이션 검증

상태: build147 Core·DSP·GUI·MCP 구현과 아래 Release/native 검증을 완료했다. data 독립 감사는 PASS_DATA_ONLY이며 UI 감사는 PASS_WITH_EXPLICIT_LIMITS이며 DSP 읽기 전용 검토도 PASS했다. [설계 계약](169-synth-resonance-plan.md)을 기준으로 최종 테스트·Release·native 결과를 별도로 기록한다.

## 구현 계약

공명 값은 raw 0…0.9, 표시는 raw×100인 0…90%다. 그래프 위치만 raw/0.9로 전체 범위를 사용한다. 실제 `AutomationShape`가 지원하는 linear/hold를 따르며 smooth를 기존 기능으로 가정하지 않는다. 기본값은 실제 patch.resonance다.

내장 synthesizer의 effective engine v2/v3만 지원한다. v1·sampler·AU를 자동 변경하거나 미지원 곡선을 조용히 무시하지 않는다. Core schema6·지원 검증과 GUI/MCP의 단위·범위·capability를 함께 연결하며 실패 시 음악·revision·Undo가 부분 변경되지 않아야 한다.

DSP는 cutoff와 resonance를 함께 적용하되 voice·phase·filter 상태와 source별 pitch bend를 보존한다. 원본/이번 use·비활성 variant·바운스 뒤 보존된 원본 노드의 지원 판정과 같은 kind의 engine 변경도 검증한다.

## 검증 기준

- Core: 0/0.9·nonfinite/초과값, descriptor·단위·실제 patch fallback, v1/AU/sampler 거절, 공유/이번 use/비활성/bounce 및 engine 변경 atomic, schema6·구파일·Undo를 확인한다.
- DSP: nil/constant·기존 cutoff PCM 보존, 공명에 따른 유효한 응답 변화, block 크기·tempo·반복·pitch bend 동시 작동과 tail·바운스 복원을 비교한다.
- GUI/MCP: 같은 raw/% 값·linear/hold·오류·stale/capability·실패 batch 불변과 작은 화면의 수치/곡선 가시성을 확인한다.
- Native 제작: 필터 sweep 편집→오프라인 출력→바운스/원본 복원→저장/재열기에서 음악·자산과 실제 출력 결과를 대조한다. 실행하지 않은 조합은 source 검증과 구분한다.

검증은 QA 사본과 no-I/O 환경을 사용한다. 앱/장치의 실제 출력·청취·모든 backend 또는 전체 DAW 완료를 주장하지 않는다. 결과 수치는 실제 실행 후 추가한다.

## build147 실행 결과

Release는 94.83초에 통과했다. Swift 전체 Core와 선별 Audio 검사 568개·실패 0개를 확인했다 (`.build/build147-tests.log`). 신규 Core 7개·Audio 6개가 포함되며 전체 Audio suite를 실행한 것은 아니다. MCP는 신규 5개를 포함한 22개·실패 0개다. Core/input/source/package 감사도 PASS했다.

native에서 기본 12% r213/schema6, 90% r214와 91 입력 거절·Escape를 확인했다. Undo r215·Redo r216을 수행했다. MCP r217에서 cutoff·resonance 각각 점 3개를 적용하고 범위·stale·실패 batch의 거절을 확인했다. CPU 바운스 r218은 35.655333초였으며 원본 복원 r219에서 archive 자산을 유지했다. 앱 종료를 확인한 뒤 재시작·파일 열기로 r219 곡선과 선택 복원을 확인했다.

data 독립 감사는 PASS_DATA_ONLY이며 UI 감사는 PASS_WITH_EXPLICIT_LIMITS이며 DSP 읽기 전용 검토도 PASS했다. QA 앱은 종료했으며 사용자 production PID 86114는 유지했다. 전체 Audio suite·모든 orbital 폭·물리 청취는 이번에 검증하지 않았다. 오프라인 구현 검증을 실제 청취나 전체 DAW 완료로 확대하지 않는다.

native 증거는 AX/JPEG 12쌍이다. MCP 범위 거절은 Python ValueError layer에서 QA 호출자가 확인했고 stale은 capability freshness 검사, atomic 실패는 app response error로 확인했다. 실패 전후 manifest의 독립 비교 결과는 별도 감사로 기록한다. DSP legacy 비교는 현재 코드의 baseline API(nil)와의 exact 테스트이며 과거 release binary의 PCM 비교가 아니다. 번들 `Resources/Codex`의 manifest·MCP server를 갱신했고 독립 parity 감사는 PASS했다.

data 감사(`independent-state-audit.json`)의 실제 상태는 `PASS_DATA_ONLY`다. 캡처 8개에서 의도한 오토메이션 변경·negative 무변경·원본 곡선/연결 복원·재시작 보존을 확인했다. 원래 자산 6개와 새 bounce hash 및 source r212 불변을 확인했다. WAV는 35.6553초·48 kHz·24-bit stereo, peak 0.38483·clipping 0이었다. 이는 PCM 측정이며 청취 검증이 아니다.

UI 감사는 `PASS_WITH_EXPLICIT_LIMITS`로 AX/JPEG 12쌍과 manifest에서 기본 12%·상한 90%·91 draft guard·Undo/Redo·compact 파라미터 4개·bounce/restore를 확인했다. 실제 PID 51452→51706 재시작에서 schema6·r219·곡선 점을 보존했다. 재열기 focus 26은 outer이므로 자동 편집 focus 복원은 이번에 검증했다고 주장하지 않는다.

최종 DSP 읽기 전용 검토는 optional buffer/count·v3 offset·기존 API의 nil 전달·voice 상태·MIDI dispatch·미지원 검증을 확인해 PASS했으며 높은 확신의 결함은 없었다. 과거 release binary PCM, 전체 곡 PCM 동등성 및 청감 개선은 이번 검증 결과가 아니다.
