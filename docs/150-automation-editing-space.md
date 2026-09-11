# 오토메이션 곡선 편집 공간

상태: build130 구현·native 검증 기록. build129의 1024×768 검증 화면에서 Cutoff 대상 선택이 세로 3행을 차지하고 실제 선형 곡선 높이가 약60px로 줄었다. 수치는 읽히지만 직접 점을 조절할 공간이 좁다.

## 계약

소유 변경은 AutomationEditor.swift의 대상 선택과 배치다. 볼륨·팬·필터 cutoff를 명시적으로 노출하고 선택 상태와 접근성 이름을 보존한다. 좁은 orbital에서는 줄바꿈하며 새 메뉴·고정 패널을 만들지 않는다. 수치 입력 identity·focus chain·음악 데이터·DSP는 유지한다.

동일 1024×768·콘솔122 조건에서 build129 화면과 비교해 곡선 높이를 확보한다. 점 선택·Tab/Shift Tab 수치·입력/Undo·gain/pan/cutoff 전환과 좁은 orbital 접근을 확인한다. 독립 fixture와 원본 자산 SHA, 정확한 저장/재열기를 검사한다. 실제 오디오 실행은 포함하지 않는다.

branch는 codex/daw-integration이며 source/UI 리뷰 후 Release·QA 패키지·native 비교·문서·private push 순서로 진행한다. 기존 사용자 앱은 유지한다. 성공 결과는 실행 후 추가한다.

## 구현과 검증 결과

신스 파라미터를 기존 StudioModeButton과 줄바꿈 배치로 표시했다. 전체 이름·선택 상태·원본 범위·수치 입력은 유지한다. 도움말과 명령 검색에도 신스 필터를 명시했다.

초기 Release는46.81초였다. 같은 조건에서 선택부가 한 행이 되고 눈금 영역은 약60→90px로 늘었다. 이 후보의 빈 곡선에서 Tab을 누르면 상위 Canvas가 이벤트를 받아 다른 서클로 이동하는 기존 build129 결함도 재현했다. 수치 진입이 불가능하면 AppKit next/previous key view를 선택하고 이벤트를 소비하도록 보완했다.

최종 final2 Release는47.75초, UUID `461CBA51-F51B-31F4-95B2-E16A7A961BB4`다. final2에서 빈 볼륨 Tab은 콘솔 입력으로, 빈 팬 Shift-Tab은 Cutoff 버튼으로 이동하면서 같은 편집기를 유지했다. Return으로 필터를 선택하고 Tab 두 번으로 Hz를 편집했다. 궤도400→500 r82/Undo83, 선형400→600 r84/Undo85, 저장·재열기85를 확인했다. 음악과 자산의 독립 감사 결과는 아래에 기록한다.

실제 궤도 검증은1024px 창의225px 조작부이며170px 조작부 줄바꿈은 소스 검토 범위다. 모든 창 크기나 전체 키보드 접근성을 완료했다고 주장하지 않는다. 이번 변경은 레이아웃과 키 처리로, 별도 구현 복제 테스트 대신 native 입력·값·파일 검증을 수행했다.

`qa/generated/automation-space/final130`은 초기 후보이고 `final2`가 최종이다. 이전 후보가 종료 확인 창에 남아 있어 `final2/recovery-before.json`이 이전 앱의 socket 응답을 받은 사실을 발견했으므로 해당 capture는 최종 증거에서 제외한다. 두 후보를 종료한 후 final2만 다시 실행해 before부터 재검증했다. helper에 Unicode 정규화 executable 경로·유일 QA process·save 전후 같은 PID 검사를 추가했다.

production 패키지의 strict 서명과 QA 동일 UUID를 확인했다. 최종 QA 앱 종료를 process 조회로 확인했고 기존 사용자 앱 PID86114는 유지했다. 물리 출력/청취는 수행하지 않았다. 다음 엔진 작업은 [MIDI tempo 가져오기 계획](151-midi-tempo-import-plan.md)이며 아직 구현하지 않았다.

독립 감사에서 최종 정상 capture7개(before·orbit-edited·orbit-undone·empty-tab·linear-edited·saved·reopened)와 JPEG/AX6개를 검토했다. saved·reopened·실제 manifest는 완전히 일치했다. 뷰·musicRevision·circleLayout을 제외한 음악은 두 Undo 후 before와 같으며 자산5개의 SHA도 직접 일치했다. 실제 편집은 같은 원본 점의400→500/600뿐이다. 궤도 빈 Tab의 JPEG/AX는 `orbit-empty-tab`(r81), 선형 snapshot `empty-tab.json`은r83으로 별도 증거다. helper의 초기 before81은 PIDguard 추가 전이며 이후 capture는 유일 candidatePID88056을 기록했다.

JPEG와 AX는 독립 증거로 사용했다. 궤도→선형 전환 직후 AX에는 궤도 내용이 남아 있어 `linear-transition.ax.txt`로 구분했으며 선형 JPEG와 동일 순간의 쌍으로 검증하지 않았다. 도움말 전문의 좁은 영역 줄바꿈 가독성은 미검증이다. 재열기의 안정된 선형 화면과 파일 상태는 별도 확인했다.
