# build 40 전환·효과 편집 검증

2026-09-09, `codex/daw-integration`, 기준 `855d80b`. development-lead → UI/UX/planner → native Swift utility → read-only code/security review → QA 순서로 수행했다. 독립 코드 검토 agent를 요청했으나 `agent thread limit reached`로 실패했다. 이 기록은 동일 실행자의 역할 전환 검토이며 독립 검토로 주장하지 않는다.

## 변경과 검토

전환의 두 섹션과 시간 기준/결과를 같은 캔버스에서 읽고 직접 수정한다. 공통 `TransitionTiming`은 기존 컴파일러의 출발 끝/도착 시작 계산을 그대로 사용하며 마지막 반복에만 적용된다. Renderer의 within/insert/overlap 처리를 대조해 미사용 효과를 숨겼다. 기존 비활성 설정을 지우거나 스키마/DSP를 변경하지 않는다.

전역·음악·전환의 `EffectControls`는 공통 `CommittedNumberField`와 명시적 필드 순서를 사용한다. live binding, revision·project·arrangement·대상 확인, 유한 수치/범위 검증, 읽기만 할 때 원본 정밀도 보존을 검토했다. 게인은 선형 저장값을 dB로 표시한다. 기존 음수 gain은 배수와 위상 반전 안내를 유지한다. 전역 Audio Unit 선택 getter와 한국어 명령도 정리했다.

검토에서 최종 변경의 고확신 차단 결함은 찾지 못했다. 첫 후보의 전환 복귀 후 window 포커스와 지나치게 긴 소수 표시는 최종 후보에서 수정했다. 처음 SwiftUI와 Core `Transition`의 모호한 타입 오류는 명시적인 Core 타입으로 수정했다. QA 도구는 고정된 검증 bundle/project/path와 revision을 확인하며 새 네트워크/auth/마이크 경로를 추가하지 않는다. 사용자 원본과 미디어는 Git 변경 범위 밖이다.

## 실행 근거

- 최종 fresh scratch Swift **330개 / 0 failures**, 25.861초. `./scripts/swift-local.sh test --scratch-path .build/transition-effects-final-quality --skip testArrangementRenderExportAndPlayback`. 장치 재생 테스트 한 항목을 제외했으며 나머지 통과를 물리 출력 성공으로 해석하지 않는다.
- Python **26개**, `python3 -m unittest mcp.test_server qa.test_agent_kit` 통과. 최종 release는 51.53초에 완료됐다. 로그: [Swift](generated/transition-effects/swift-tests-final.log), [Python](generated/transition-effects/python-tests.log), [release](generated/transition-effects/release-final.log).
- 별도 bundle `com.circlr.integrationqa`, 0.20.0 build 40. 최종 앱 UUID `33558307-67CD-34A0-B455-6E0782C11F4A`, ad-hoc codesign strict 검증 통과. 소스 11개, Codex kit 25개 hash 일치; 빌드/패키지의 file-backed Mach-O section 37개 일치.
- [증거 검사기](check-transition-effects-evidence.py) 통과. [검사 결과](generated/transition-effects/readable/verification.json)에 최종 후보의 JPEG 27개(1019×768) hash가 있다. 즉시 메뉴 선택 뒤의 일부 AX 캡처는 이전 view를 포함했으므로 `final-settled-*` 캡처를 상태 판정에 사용한다. 파일 수는 성공 시나리오 수가 아니다.

## Native 시나리오

직접 작성한 두 톤 자산·MIDI의 `transition-effects.circlr` QA 사본만 편집했다. 앞 섹션은 16마디 중 끝부분 변박/tempo map으로 총 34초, 뒤 섹션은 local 7/8·96 BPM으로 35초다. 원본 `studio.circlr` manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`로 유지됐다.

| 작업 | 확인 결과 |
|---|---|
| 전환 수치·왕복 | 앞 마디 1.5 → 4.500초, gain −6 dB → raw 0.5011872336272722(r34). 전환→연결→전환 뒤 edge와 캔버스 포커스 유지 |
| 확정 화면 재검증 | 뒤 마디 1.5 → 3.281초. overlap은 3.281초 먼저/효과 숨김(r83), insert는 늦게/리듬 없을 때 효과 숨김. 리듬 지정 뒤 삽입 리듬 효과 표시(r85) |
| 잘못된 전환 | 40초 overlap은 inline 재생 불가 표시; 길이를 2초로 수정 가능 |
| 정밀도 | Delay 516.152 ms를 읽고 Return 후 raw amount가 −6 dB 때의 0.5011872336272722 그대로(r42). 표시값으로 반올림 저장하지 않음 |
| 숫자/오류 | 400 ms → Tab → 35% → Return(r44). 2000 ms의 Tab을 범위 오류와 함께 거절. 500 ms 초안 도중 MCP global tempo 변경 후 Return을 stale 오류로 거절; Esc와 global Undo 후 원래 400 ms·35%·120 BPM 유지(r46) |
| 전역 효과 | −3 dB 저장(r47). Reverb 40/55를 Tab으로, 30/45를 Shift-Tab으로 연속 수정하여 최종 amount .45/secondary .30(r52). Return 뒤 캔버스 포커스 |
| 음악 서클 효과 | keyboard instrument 뒤 compressor 추가(r53), −27 dB·6:1 연속 Tab 입력으로 raw .3/.4(r55). 기존 MIDI 보존, Return 뒤 캔버스 포커스 |
| 트랙 비우기 | within·2초·키보드 트랙 선택(r57). 효과를 숨기고 해당 구간을 비운다는 안내 표시, 기존 effect 값 보존 |
| 복원 | 첫 후보 9 Undo → r32. 최종 23 Undo → r80. 확정 화면 재검증 5 Undo → r90. 각 단계 저장/재열기. global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout/signal이 기준 r14와 일치 |

화면 예: [겹치기](generated/transition-effects/final-settled-overlap.jpg), [삽입 리듬](generated/transition-effects/final-settled-insert-rhythm.jpg), [숫자·단위](generated/transition-effects/final-delay-tab.jpg), [트랙 비우기](generated/transition-effects/final-within-replace.jpg).

## 오프라인 출력과 제한

r46 export job `90A36817-C0AE-4D78-BC66-28A75EB98E14`가 completed. **73초 / 48 kHz / stereo / 24-bit**, 3,504,000 frames. 구성은 34초 + 2초 insert + 35초 + 2초 tail이다. peak 0.0941433907, RMS 0.0164020382, 비영 샘플 6,328,345이며 clipping이 없다. [PCM 측정](generated/transition-effects/export-pcm.json), [WAV](generated/transition-effects/transition-master.wav), SHA-256 `16d3fc7064a98da8984f00b0386552fbf26263ab64bf9f9855978092351ed3d8`.

이것은 전환과 효과 경로의 기능용 fixture 렌더다. f0r h3r의 청감/발매 품질 검증이 아니다. 모든 snapshot의 output attempts는 0이며 물리 재생·마이크·MIDI 장치 녹음·MP4를 시작하지 않았다. QA 앱은 r90 복원 뒤 정상 종료했고 사용자 0.19 build 21 앱과 기존 작업 브랜치를 보존했다.

최종 슬라이더 드래그/방향키 전체 회귀, 첫 필드 이전 Tab의 시스템 포커스, 전역 편집↔연결의 복귀 포커스, 실제 Audio Unit 화면, VoiceOver 발화, 모든 legacy 창 조합은 별도 범위다. 전역/전환 숫자와 MIDI/오디오/오토메이션의 기존 개별 근거를 전체 키보드/장치 출고 완료로 합산하지 않는다. 전체 DAW와 UI goal은 계속 active다.
