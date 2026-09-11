# 신스 cutoff 오토메이션 구현과 검증

상태: build129 소스·기계 검증·Release 결과를 기록한다. native GUI의 Hz 편집·잘못된 값 거절은 확인했으며 바운스·복원·저장/재열기도 확인했다. 최종 종합 UI 데이터 감사도 통과했으며 전체 DAW 완료로 판정하지 않는다. [계획148](148-synth-cutoff-automation-plan.md)의 요구와 실제 수행한 검증을 구분한다.

## 구현 범위

[Automation](../Sources/CirclrCore/Automation.swift)의 synthCutoff는 내장 synthesizer instrument node에서만 지원하며 절대 40–20,000Hz를 사용한다. 곡선 없음/비활성은 해당 patch cutoff로 돌아간다. linear는 Hz 선형이고 hold는 경계에서 전환한다. [AutomationDisplay](../Sources/CirclrCore/AutomationDisplay.swift)의 세로 위치는 log-frequency이며 실제 lane 값 평가 뒤 표시 변환을 적용한다. engine2/3의 tracking·envelope·motion 및 최종 cutoff clamp는 기존 DSP 규칙을 유지한다.

[ProductionInstrument](../Sources/CirclrAudio/ProductionInstrument.swift)는 compiled span을 절대 sample time으로 평가해 [C render API](../Sources/CirclrRealtime/include/CirclrSynth.h)에 frame별 cutoff 배열을 전달한다. [synth.c](../Sources/CirclrRealtime/synth.c)는 voice·envelope·필터 상태를 유지하며 base cutoff만 사용한다. [SectionGraphRenderer](../Sources/CirclrAudio/SectionGraphRenderer.swift)가 instrument의 계획을 전달하고 [AutomationDSP](../Sources/CirclrAudio/AutomationDSP.swift)는 cutoff를 후단 PCM 효과로 적용하지 않는다. 마지막 값은 release tail까지 유지한다.

새 cutoff lane은 schema3 저장 경계를 사용한다. 원본 graph·inactive override까지 target validation을 적용하고 sampler/AU 등 미지원 악기 변경을 거절한다. 기존 original/이번 use 편집 의미를 유지한다. GUI의 단위·눈금·입력과 MCP parameter 범위를 연결했으며 snapshot runtime capability는 synthCutoffAutomation=1이다. schema/지원 범위를 소스에 연결한 것과 실제 GUI 실패 경로 검증은 별개다.

## 수행한 기계 검증

- `.build/cutoff129-tests.log`: 선택된 Core/Audio 관련 479개 테스트, 실패 0, 1.903초. 전체 native/하드웨어 검사를 뜻하지 않는다.
- `.build/cutoff129-tempo-test.log`: 추가 부모 tempo 통합 테스트 1개, 실패 0, 0.171초. 앞선 479개 실행과 별도 결과다.
- `.build/cutoff129-mcp-tests.log`: cutoff MCP 검사 7개, 0.005초. `.build/cutoff129-mcp-regression.log`: MCP 회귀 27개, 0.117초. `.build/cutoff129-agent-kit.log`: kit 9개, 0.103초. 각각 PASS했다.
- `.build/build129-release.log`: 최종 Release 77.59초 성공. main UUID는 `6FDB984B-2E1E-36C0-A2DF-B46B973AC8C8`이다. native 실행·패키지 출고 성공을 이 빌드 결과만으로 주장하지 않는다.

[Audio cutoff 테스트](../Tests/CirclrAudioTests/SynthCutoffAutomationTests.swift)는 engine1/2/3의 일정값/비활성과 같은 고정 patch PCM 일치, Hz 선형/hold/tail의 값, 후단 PCM 미적용, instrument에 전달된 cutoff와 gain의 분리를 검사한다.

추가 부모 tempo 테스트는 유효한 instrument(start 0, length nil, repeat 1)를 실제 SectionGraphRenderer까지 렌더한다. 120BPM에서 beat2 이후 60BPM이 되는 4박 구간은 3초이며, 독립 구성한 기대 span의 PCM과 정확히 일치했다. 1초는 3,400Hz, 2초는 4,900Hz, tail은 6,400Hz이고 tempo 변화를 무시한 계획과 PCM이 다름을 확인했다. Core 단독 반복 테스트의 가상 instrument length/repeat를 실제 graph 지원으로 표현하지 않는다.

## C DSP 비교

`qa/generated/synth-cutoff/final129/result.json`은 기존 commit의 C DSP와 현재 DSP를 CPU만으로 비교한 결과다. 48kHz·144,000 frames에서 engine1/2/3 모두 기존/NULL/일정 400Hz 경로의 float byte 일치, sweep의 64/257/1024-frame 분할 일치를 확인했다. 정규화한 고역 대역 비율 증가와 note-off tail 감쇠도 검사했다. 원본/현재 소스 SHA를 기록해 비교 대상을 고정했다.

이 결과는 필터가 소리의 스펙트럼에 반영되고 기존 경로를 보존한다는 기계 근거다. 실제 청취·음색 선호·HAL·AU를 검사한 결과는 아니다. 단순 gain 변화나 완료 PCM 후단 필터로 대체한 결과도 아니다.

## GUI·schema 검증과 패키지

GUI 최초 적용 r71은 schema3이었다. Undo r74는 schema2와 기준 음악으로 정확히 복귀했고 Redo r75는 첫 적용 음악과 schema3으로 복원됐다. Hz 편집 r76은 같은 점의 값만 2,400→400Hz로 바꿨다. ui_access_audit의 독립 5개 JSON·3개 JPEG/AX 검토는 PASS했다. 실제 값 오류 거절도 확인했다.

`python3 scripts/package-app.py`는 exit0으로 완료했고 `.build/package129.log`에 기록했다. production strict 서명과 위 main UUID의 QA 동일성을 확인했다. 바운스·최종 저장/재열기 결과는 다음 절에 별도 기록한다.

## Native 바운스·원본 범위·재열기

MCP 한 batch에서 공유 원본에 400→6,400Hz sweep을, 같은 section의 두 번째 use에 1,200Hz override를 적용해 r77을 만들었다. unsupported target·stale revision·mixed invalid batch는 음악 변경 없이 거절됐다. GUI에서 공유 원본 400Hz와 override 1,200Hz를 확인했다.

MCP 바운스 r78·원본 복원 r79와 관련 export job이 모두 완료됐다. 48kHz stereo 24bit·1,711,456 frames·약 35.655333초의 바운스 전후 PCM 최대 차이는 1LSB다. 원본 복원 PCM과 WAV SHA는 바운스 전과 byte-exact다. synth_focus_impl의 `dsp-independent-audit.json` 독립 감사가 PASS했다. 이 결과는 렌더 보존 검증이며 실제 청취를 의미하지 않는다.

Sound Bank 변경을 시도하면 곡선을 먼저 제거하라는 실제 alert가 표시되고 r79 음악을 유지했다. 저장/재열기 r79는 schema3이며 같은 400Hz·공유 원본·선택 화면으로 복귀했다. 최종 독립 감사에서 saved·reopened·실제 manifest가 뷰와 revision까지 완전히 일치했다. 추가 JPEG/AX 5개에서도 원본·Override·반려 안내와 복원된 선택을 확인했다.

## 검증 범위와 남은 조건

같은 곡에서 신스 cutoff 입력·실제 Hz/log 곡선 표시 → 원본 A/B override → GUI/MCP 결과 → 바운스/원본 복원 → Undo·schema·저장/재열기를 확인한다. 미지원 악기 변경·잘못된 값·stale 요청 등은 실제 실행한 경로와 source guard 검토를 구분한다. 정확한 패키지 식별·서명·자산/음악 보존과 noIO 상태도 별도로 확인한다.

GUI Hz 편집·오류 거절·바운스·복원·재열기를 확인했으며 최종 종합 UI 데이터 감사도 통과했다. prepared song/offline automation과 transport clock이 없는 note audition은 구분하며 실제 장치 연주·청취는 별도 gate로 유지한다. 전체 한 곡 제작과 [현행 개발 계획](138-current-development-plan.md)의 남은 범위를 유지한다.

검증용 앱은 종료했고 사용자 앱 PID86114는 유지했다. 원본 자산 4개의 SHA를 보존했으며 output/audition 시도는 0, 녹음은 꺼진 상태였다. QA 번들의 manifest 외 Python 캐시를 제거한 뒤 다시 서명해 검증했고 production 패키징은 기존 캐시 제외 규칙을 사용했다.
