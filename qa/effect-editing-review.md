# build 28 · 효과 단위와 입력 검증

2026-09-08, `codex/daw-integration`, 기준 `5936cb5`. 이 결과는 효과 편집의 가독성·키보드·한 Undo를 개선한 progress다. 전체 DAW/장치/접근성 출고 완료 판정은 아니다.

## 검사와 패키지

- 전체 Swift **259개, 실패 0, 22.012초**, `qa/generated/effect-editing/keyboard-swift-tests.log`. 명령: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 기존 실제 출력 장치 의존 검사 하나를 제외했다. 마지막 변경인 `acceptsFirstMouse` 한 줄은 이후 release compile과 Native 입력 검사로 확인했다.
- 새 Core **4개**: 모든 종류의 실제 단위, 범위/로그 슬라이더 왕복, 비정상/다른 종류 입력 거절, legacy clamp/no-op·음수 gain 표시·renderVersion/plugin state 저장 보존.
- 새 Audio **2개**: 1000 Hz 필터의 impulse 계수, 500 ms delay의 실제 frame/좌우 feedback, −18 dB/4:1 압축의 출력 레벨, gain/pan/drive와 wet 0 reverb의 실제 PCM. 표시만 맞춘 값을 오디오 의미와 구분해 검사했다.
- Python MCP/kit **26개**, `python-tests.log`: `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`. 새 QA helper는 `py_compile`을 사용한다.
- 최종 release **22.63초**, `release-mouse.log`. 앱 `qa/generated/effect-editing/mouse/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build 28, UUID **`456B4223-8356-361A-8ECF-0AC1E8C65B01`**.
- `python3 qa/check-effect-evidence.py`는 기록 snapshot **43개**의 정확한 QA 대상·녹음 idle, 성공/실패 조건, Undo/재열기와 source/package Mach-O **37개 section**, signature·kit **25개** hash·원본 fixture manifest 불변을 확인했다. `verification.json`은 passed이며 비활성 drag는 `not_verified`다.

## Native 근거

`prepare-effect-qa.py`로 authored 톤 fixture만 복사한 `fixtures/effect-editing.circlr`, ID `63489E15-0B92-5446-BBD3-FF7A87CD74E6`를 사용했다. 원본 `studio.circlr`는 쓰지 않았다. 정확한 QA socket의 project/revision guard로 검증용 Low-pass 한 개를 추가한 상태가 `initial.json`이며 최종에도 이 초기 필터 상태를 복원했다. 기록·미디어·앱은 Git 대상이 아니다.

| 시나리오 | 결과·근거 |
|---|---|
| 단위와 배치 | 최소 폭 1024, canvas 1024×673. 컷오프 894.427 Hz, 효과 종류·슬라이더·숫자·음소거/볼륨/바운스가 한 편집기에 표시됨. `initial.png`, `mouse-before.png`. 콘솔 접힘은 `console-closed.png` |
| 숫자 확정 | 1200 입력 중 r15 유지, Return 후 r16 한 번 증가. 저장 amount를 DSP 공식으로 읽으면 1200 Hz. `typed/committed.json` |
| 오류·Esc | 50000 Hz는 범위 안내, 음악 무변경. Esc 뒤 효과 편집 유지, 1200 복귀. ⌘Z 한 번으로 초기 값/그래프 복원. `invalid-ax.txt`, `invalid/escaped/undo-number.json` |
| 연속 Tab | 최종 keyboard 후보에서 임계값 −18 입력→Tab으로 다음 칸의 4.5 선택→4 입력→Return. kind 변경 r30 이후 두 확정만으로 r32. amount0.6/secondary0.2, 실제 −18 dB/4:1. `keyboard-tab-ax.txt`, `keyboard-ratio.json/png` |
| 작성 중 외부 변경 | −12 작성 중 MCP가 compressor amount0.7로 변경. Return은 충돌 안내와 r33 유지. Esc로 복귀. 이전 Low-pass 후보에서도 같은 방어 확인. `keyboard-external/stale.json`, `keyboard-stale-ax.txt` |
| 개별 Undo | external→ratio→threshold→kind를 각각 ⌘Z. 대응하는 이전 tracks/assets/sections/arrangements/signal/patterns/portLayout 일치. `keyboard-undo-*.json`, `keyboard-restored.json` |
| 슬라이더·키보드 | controls 후보에서 방향키0.5→0.51과 drag를 각각 한 revision으로 확인. 최종 mouse 후보에서 AX 클릭으로 활성화한 뒤 drag r39→40, amount0.7665325126262627, Right r40→41로 +0.01. 선택 서클 유지. `controls-key/drag.json`, `mouse-active-drag/key.json` |
| 슬라이더 Undo | 최종 ⌘Z로 키 변경을, 다음 ⌘Z로 drag를 되돌려 초기 Low-pass0.5와 전체 음악 필드가 일치. `mouse-undo-key/restored.json` |
| 접근성 값 | 슬라이더의 normalized value 외에 실제 단위 `894.427 Hz`, `−20.7 dB`, `4.5 :1` value description 제공. `final-before-ax.txt`, `compressor-ax.txt`. 실제 VoiceOver 발화는 미검증 |
| Audio Unit | controls 후보에서 종류를 Audio Unit으로 바꾸면 미사용 amount/secondary 슬라이더 없이 플러그인 선택과 편집 버튼이 표시됨. 미선택 시 편집 비활성. `audio-unit-ax.txt/json`. 실제 플러그인 로딩은 이번 범위 밖 |
| 저장/재열기 | 최종 초기 필터 상태 저장→같은 파일 open completed, dirty=false, 음악 필드 일치. `mouse-restored/reopened.json`. 원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 보존 |

## 발견한 문제와 재검증

첫 테스트의 `tanh` 숫자 타입 모호성과 delay 기대값 목록의 secondary 누락은 테스트를 수정한 뒤 전체 검사로 확인했다. 초기 후보의 슬라이더 방향키는 캔버스 형제 탐색으로 전달됐다. 명시적 화살표 처리와 드래그 종료 action을 넣고 실제 값/revision/선택을 대조했다.

Tab은 이전 칸의 blur 확정 전에 다음 칸에 focus를 줬다. 따라서 다음 칸이 오래된 effect snapshot을 들고 정상 연속 입력을 거절했다. 아직 작성하지 않은 칸만 최신 baseline으로 갱신하도록 수정했고 정상 Tab과 작성 중 외부 변경 거절을 모두 재검증했다.

일부 CUA 단독 드래그는 값이 바뀌지 않았다. `acceptsFirstMouse`를 제공했으나 비활성 창 테스트 `mouse-drag.json`도 r39 무변경이다. 이 시도와 `keyboard-drag.json`은 성공으로 세지 않는다. **대상 슬라이더를 AX 클릭해 활성화한 뒤 실제 좌표 drag한 결과**가 최종 성공 근거다. 비활성 창 첫 drag의 전체 입력 경로는 후속 검사로 유지한다.

## 검토와 남은 범위

동일 실행자가 read-only 검토 역할로 DSP 공식·UI 변환·입력 수명·consumer binding과 diff를 대조했다. 독립 agent 슬롯이 없어 역할 전환 검토이며 독립 리뷰가 아니다. DSP/schema/MCP는 바꾸지 않았다. 입력은 finite/range/kind와 baseline을 확인하고, 현재 프로젝트/선택 대상에만 적용한다. 다른 파라미터·plugin state·reverb 알고리즘을 표시 갱신으로 덮어쓰지 않는다. 새 인증·외부 전송·권한 요청은 없다.

Native 성공 범위는 음악 effect 서클이다. 공통 UI를 쓰는 전역 signal/전환/legacy section의 위젯별 회귀, 실제 VoiceOver, 다른 신스·출력 볼륨 숫자 필드의 확정/취소, 비활성 첫 drag는 다음 범위다. 기존 prepared PCM 정책상 재생 중 편집은 다음 재생에 적용된다. 마이크·HAL·MP4·전체 밀집 조합의 E gate와 사용자 0.19 앱은 유지한다.
