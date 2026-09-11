# 오토메이션 작업 공간 검증

2026-09-09, `codex/daw-integration`, 0.20.0 build 34. 기준 `aeb54c0`. [실행 계약](../docs/48-automation-workspace.md).

development-lead → UI/UX → native Swift utility → read-only code/security review → QA의 순차 역할 전환이다. 실제 root 포함 한 슬롯이며 이번 검토를 독립 에이전트 리뷰로 계산하지 않는다.

## 결과

오토메이션의 긴 측면 ScrollView를 제거했다. 자유 배치는 곡선의 폭을 사용하고 궤도는 원의 높이를 유지한다. 같은 캔버스에서 선택 점의 위치·dB/%·선형/유지, 점 추가/삭제, 원본 범위를 조절한다. Return/Esc 후 곡선에 포커스를 돌려 방향키가 다른 서클을 선택하지 않도록 했다. 저장된 gain/pan·schema·DSP·보간은 유지한다.

최종 앱은 `qa/generated/automation-workspace/orbit/써클러 통합 검증.app`, UUID `59D23BD1-DF25-3BC8-80D0-05E4B69B9202`다. 작은 창(스크린샷 1019×768)과 콘솔 열림에서 두 배치의 명령·곡선·선택 값이 보이는 것을 확인했다. 최종 궤도의 외곽 지름은 화면상 약 176 px다. 검증 뒤 정상 종료했으며 기존 사용자 앱 0.19.0 build 21과 다른 작업 앱을 유지했다.

## 자동 검사와 검토

- Targeted Swift **23개, 실패 0**. 새 Core 검사 4개는 pan 표시 정밀도/입력 범위/finite/stale, gain 0.5/0.1/3 dB 증감과 경계, pan 5/1/25%p와 표시, 로컬 tempo map의 박→초를 검사한다.
- 전체 offline Swift **307개, 실패 0**, 23.759초. `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 실제 장치 의존 검사 한 개는 기존 HAL 지연 때문에 제외했다. 이 전체 검사는 마지막 궤도 배치 조정 직전이며 Core는 이후 변경하지 않았다. 마지막 UI 조정은 최종 release와 native 시나리오로 확인했다.
- Python **26개, 실패 0**, 0.221초. `python3 -m unittest mcp.test_server qa.test_agent_kit`.
- 최종 release **24.00초**, warning/error 없음. `orbit-release.log`에 보존한다.
- `python3 qa/check-automation-workspace-evidence.py`: 저장된 편집/복원 근거, 원본/asset checksum, Mach-O file-backed section **37개**, source hash **7개**, 내장 kit **25개**, codesign strict 통과. 이후 다른 release를 빌드하면 최신 바이너리 비교 대상은 바뀌므로 역사적 근거는 보존된 UUID/해시/로그로 구분한다.
- 순차 코드/보안 검토: pan 변환 뒤 공통 finite/range 검사, 원값 보존, live point partial Binding, shape의 전체 편집 identity, drag의 identity/extent/enabled guard를 확인했다. MCP 변경은 기존 displayBeats를 실제 표시 범위에 맞춘 것이다. 인증·권한·외부 실행 기능을 추가하지 않았다. QA 스크립트는 전용 fixture ID와 bundle 검증을 사용한다.

## 실제 앱 시나리오

`automation-workspace.circlr`(ID `C9FE4910-13B5-512A-AA14-39EA01D3F634`)는 authored tone fixture의 복사본에 같은 섹션의 두 번째 사용을 추가했다. 원본 `studio.circlr`은 보존하고 구매 샘플·사용자 곡·마이크는 사용하지 않았다.

| 동작 | 관측 근거 |
|---|---|
| 위치/볼륨 연속 입력 | 첫 후보 r22. 4박/−6 dB와 32박/0 dB 두 점. Tab으로 위치를 확정한 뒤 볼륨을 바꿔도 앞선 위치가 유지된다. |
| 유지/적용 전환 | 첫 후보 r24. 첫 점 hold와 두 점을 유지한 채 enabled=false. 다시 켜면 같은 곡선이다. |
| 팬과 잘못된 입력 | 첫 후보 −50% 입력 뒤 Option-Up은 −49%(r28). 101은 범위 오류로 거절하고 r28 유지. |
| 최종 숫자/키보드 | −6 dB Return 뒤 Up으로 −5.5 dB(r44). 포커스는 곡선이고 저장 gain은 `10^(-5.5/20)`이다. |
| 최종 궤도 드래그 | r45에 0박/−5.5 dB 점을 16박/gain 4로 이동. Cmd-Z 한 번 r46에서 ID·시간·값 복원. |
| 전체 점/범위 | MCP로 96박 점 추가(r47). ‘전체 점 보기’는 GUI와 MCP displayBeats 모두 96. 다음 점 선택 후 Left는 95.75박(r48)으로 이동하며 범위도 95.75가 된다. Undo로 96박 복원. |
| 공유 원본 | 원본으로 전환하면 개별 두 점이 보이지 않는다. 원본 점 추가 r50은 base curve만 변경하며 개별 두 점과 두 번째 사용의 override 부재를 유지한다. |
| 오래된 숫자 입력 | −12 dB draft 중 MCP가 첫 점을 gain 0.4로 변경(r51). Return은 stale 오류, Esc는 현재 −7.96 dB를 표시하고 곡선 포커스로 복귀한다. |
| 삭제/곡선 지우기 | Delete r52로 첫 점 제거, Cmd-Z r53 복원. 곡선 지우기 r54는 원본 곡선을 유지하고 개별 곡선만 제거, Cmd-Z r55 복원. |
| 최종 자유 배치 드래그 | r56에 16박/gain 약 1.71363으로 이동. Cmd-Z r57은 0박/gain 0.4를 복원한다. |
| 원본 없는 서클 | 사용에 추가한 출력의 원본 모드는 안내와 비활성 점 추가를 표시한다. Return에도 r57 유지, 원본 토글을 끄면 개별 편집으로 돌아간다. |
| 저장/재열기 | 첫 후보 r41, 최종 r65에서 global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout을 최초와 같게 Undo. 저장 후 재열기 r65에서도 일치한다. |

PNG/AX/JSON은 `qa/generated/automation-workspace/`에 보존한다. 대표 화면은 `final-orbit.png`, `freeform-drag.png`, `all-points.png`, `stale-rejected.png`다. 원본 manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`이고 원본/QA 사본의 두 authored asset checksum이 일치한다. 원시 프로젝트·이미지·앱·오디오는 Git에 포함하지 않는다.

## 수정한 결함과 남은 범위

첫 세로 배치는 작은 창에서 궤도가 약 75 px로 축소됐다. 마지막 후보는 중앙 원의 높이를 확보하고 양옆 같은 캔버스에 편집 요소를 배치했다. 숫자 Return/Esc가 주 캔버스로 돌아가던 문제도 오토메이션 전용 포커스로 수정했다. 초기 축 목록의 Swift 타입 추론 컴파일 오류는 명시적 `[Double]`로 해결했고 실패/성공 로그를 구분해 보존했다.

전체 점 보기에서 마지막 점을 움직이면 표시 범위도 자동으로 바뀐다. 고정 범위 편집과 궤도 시작/끝의 겹친 점 선택은 후속 UX 범위다. 궤도/자유 전환은 현재 편집 확대를 해제해 QA에서 같은 서클로 재진입했다. 이 전환의 깊이를 아직 개선했다고 주장하지 않는다.

외부 변경 중 native mouse-down을 유지하는 조합은 코드 guard를 검토했으며 실제 제스처 검증은 남아 있다. VoiceOver 발화·콘솔 닫힘/여러 창 크기의 전체 행렬·전역/legacy·밀집 다중 곡선도 이번 표본과 구분한다. 현재 재생은 prepared PCM이고 실제 출력/마이크/MP4 및 실시간 automation 반영·write/touch/latch·다른 파라미터는 완료 범위가 아니다. 사용자 앱 교체와 전체 개발 목표 완료를 선언하지 않는다.
