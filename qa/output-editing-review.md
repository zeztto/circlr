# 출력 레벨 편집 검증

2026-09-09, `codex/daw-integration`, 0.20.0 build 33. 기준 `09b183c`. [실행 계약](../docs/47-output-editing.md).

development-lead → UI/UX → native Swift utility → read-only code/security review → QA의 순차 역할 전환이다. 직전 실제 sub-agent dispatch가 실행 한도에 막혀 이번 검토를 독립 에이전트 리뷰로 계산하지 않는다.

## 결과

출력 서클에서 서클별 레벨과 트랙 전체 레벨을 구분한다. dB 입력·fader·음소거·0 dB 복원을 제공하고 볼륨/팬 오토메이션·바운스로 바로 이동한다. 최소 폭 1024의 창과 콘솔 열림 상태에서 두 범위와 바로가기가 스크롤 없이 보이는 것을 확인했다. 악기 화면은 음색 편집에 집중한다. dB는 표시/입력 단위이며 기존 선형 gain, schema와 renderer는 유지한다.

최종 앱은 `qa/generated/output-editing/gesture/써클러 통합 검증.app`, UUID `F119E664-A045-380F-BE1D-FDA30F90809D`다. 이전 후보도 보존했다. 검증 완료 후 앱을 정상 종료했으며 사용자 앱 0.19.0 build 21과 다른 작업 앱을 교체/종료하지 않았다.

## 자동 검사

- 최종 전체 offline Swift **303개, 실패 0**: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 24.890초. 기존 실제 출력 장치 의존 검사 한 개는 HAL 지연 때문에 제외했다.
- Python **26개, 실패 0**. MCP/내장 kit 계약은 바꾸지 않았다.
- 최종 release build **47.45초**, warning/error 없음.
- 새 Core/입력 검사 8개: 두 사용의 독립 서클/공통 트랙, original partial write와 override 보존, invalid/no-op atomicity, dB 변환과 표시 반올림 시 원값 보존, 무음/유한값/범위, stale target/revision, fader 범위와 움직이지 않은 위치의 정밀도 보존.
- 새 Audio 검사 2개: 실제 PCM에서 서클 −6 dB는 첫 사용만 `10^(-6/20)` 배, track gain은 두 사용 모두에 한 번 적용된다. 서클/트랙 음소거 범위를 확인했다. `applyOutputGain:false` 바운스 렌더에서 출력 gain을 중복 굽지 않는 비율을 검사했다. 이번 검사의 바운스 범위는 renderer 계약이며 native 바운스 전체 재검증은 아니다.
- `python3 qa/check-output-editing-evidence.py`: 저장된 UI/MCP/manifest 근거, 원본/asset checksum, 최종 Mach-O file-backed section **37개**, source hash **9개**, 내장 kit **25개**, codesign strict 검사를 통과했다. 이후 다른 release를 빌드하면 이 검사기의 최신 release 대조 대상도 바뀌므로 역사적 검증은 보존된 UUID/해시/로그로 식별한다.

## 실제 앱 시나리오

검증 전용 프로젝트 `output-editing.circlr`(ID `DBB508A6-2452-5CAD-8037-9E0804AA4EB1`)는 기존 authored tone fixture를 복사하고 같은 섹션의 두 번째 사용을 추가했다. 사용자 곡·구매 샘플과 마이크 입력을 사용하지 않았다. 두 번째 사용은 별도 검사 대상으로 선택하며 전체 송폼의 재생 경로를 바꾸지 않았다.

| 동작 | 관측 근거 |
|---|---|
| 서클 −6 dB, 트랙 −6 dB | r15/r16. 원본과 두 번째 사용의 서클 gain은 1을 유지한다. 두 번째 사용 UI는 서클 0.00 dB / 트랙 −6.00 dB다. 최종 후보에서도 r45/r49로 재확인했다. |
| 개별/트랙 음소거 | r17은 해당 node override만 mute, r21은 Track.muted만 변경. 각각 Undo로 복원했다. |
| 공유 원본 −3 dB | r19 및 최종 r46. base node gain만 변경하고 첫 사용 −6 dB override를 보존한다. 두 번째 사용은 −3 dB를 상속한다. 이번 사용에만 추가한 출력은 원본이 없다는 안내와 전환 방법을 보여준다. |
| 잘못된 입력과 무음 | 20 dB는 오류 표시 후 r22 유지. `-inf` 확정 r23, `−∞` 붙여넣기 확정 r28은 gain=0. Esc와 0 dB 버튼으로 취소/복원했다. |
| fader와 Undo | 최종 r36→r37 드래그 적용, Cmd-Z 한 번으로 r38 원값 복원. 같은 위치 클릭은 r38 유지. Right/Option-Right/Shift-Right가 0.50/0.60/3.60 dB(r39–41), 각각 Undo 가능하다. |
| 표시 정밀도 | raw Track.gain=0.7을 −3.10 dB로 표시한다. 입력 없이 Return으로 떠나면 r45와 raw 0.7을 유지한다. |
| 외부 변경 충돌 | −12 dB draft 중 MCP로 track gain=0.65 변경(r48). Return은 stale 오류를 표시하며 node gain은 기존 −6 dB. Esc는 캔버스 포커스로 돌아간다. |
| Tab/바로가기 | 트랙 −6 dB는 Tab에서 한 번 확정(r49). 볼륨/팬 바로가기는 올바른 대상을 선택하고 빈 곡선을 만들지 않는다(r48 유지). 악기 화면에는 레벨 입력이 없다. |
| 저장/복원 | 중간 후보 r36, 최종 r52에 모든 음악 변경을 Undo했다. 저장 후 재열기 r52에서 global/tracks/sections/arrangements/assets/patterns/portLayout이 최초와 같다. |

최종 안정된 최소 창 화면은 `qa/generated/output-editing/gesture-start.png`, 드래그 결과는 `gesture-drag.png`, 충돌 표시는 `stale-rejected.png`에 있다. `*-ax.txt`와 각 이름의 JSON snapshot/저장 manifest를 함께 보존한다. 최종 재열기 상태는 `reopened.json`이다.

## 발견한 문제와 수정

초기 화면은 중복 제목과 큰 여백 때문에 트랙 레벨이 아래로 밀렸다. 제목과 간격을 줄이고 두 레벨 아래에 범위 전환/바로가기를 묶었다. dB 표시는 소수 둘째 자리로 간결하게 만들고 untouched baseline은 계속 원래 선형값을 보존한다.

continuous slider에서 중간 SwiftUI 상태를 갱신하던 초기 후보의 드래그가 원위치로 돌아왔다. native tracking 동안 모델/SwiftUI preview를 바꾸지 않고 mouse-up에 한 번 확정하도록 변경한 최종 후보에서 실제 이동과 한 Undo를 확인했다. 움직이지 않은 slider의 dB 왕복 오차도 원래 gain을 보존해 불필요한 revision을 막는다.

CUA `typeText`로 Unicode 기호가 입력되지 않았지만 `paste` 후 native field의 `−∞` draft와 확정은 정상 동작했다. 새 앱 후보 선택 뒤 이전 closure가 닫힌 중간 앱을 다시 열었던 도구 오류도 있었다. 새 앨범/Agent 연결 없음 상태를 확인해 정상 종료하고, 정확한 최종 앱 핸들로 모든 최종 검사를 수행했다. 중간 앱에서 프로젝트 편집은 없었다.

초기 Audio 테스트의 Swift 구문 오류와 빌드 중 도움말 변경으로 인한 compiler input-changed 거절은 각각 수정/소스 고정 후 재실행했다. 실패 로그도 보존하며 최종 성공 검사와 혼동하지 않는다.

## 남은 범위

- 이번 변경은 출력 레벨 경로의 partial write를 고쳤다. 기존 `updateMusic`을 사용하는 다른 편집기의 원본/override 전체 의미를 고쳤다고 주장하지 않는다.
- 서클의 static gain과 곱해지는 automation, track 전체 gain의 구분은 유지한다. track pan/solo, bus solo와 post/pre-fader routing, 실시간 gain 반영은 별도 신호 계약 후 구현한다. 현재 재생은 prepared PCM 기반이다.
- 실제 출력 획득·재생/정지/재시작, 마이크 테이크, MP4 동기, VoiceOver와 전역/legacy 모든 편집기 조합은 이번 QA가 포함하지 않는다. [build 32의 HAL 관찰](playback-worker-review.md)과 별개다. 이 상태로 사용자 앱을 교체하지 않는다.
- 원본 `studio.circlr` manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`를 유지한다. 원본과 QA 사본의 두 authored asset checksum이 같다. QA 앱/프로젝트/PNG/JSON/오디오는 Git에 넣지 않는다.
