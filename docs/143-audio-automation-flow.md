# 오디오 가져오기와 오토메이션의 작업 화면 전환

상태: build123에서 두 화면 전환 문제를 실제 재현했고 build124 소스 수정과 read-only 검토를 마쳤다. Release와 아래 native 전환·Undo·이름 오류 검증을 마쳤으며 저장/재열기도 확인했다. production 서명·UUID와 독립 데이터 감사도 통과했다. 기존 제작 검증의 성공을 이번 변경의 결과로 대신하지 않는다.

## 제작 흐름에서 확인한 문제

연결 화면에서 ⌘5로 오토메이션을 열어도 연결 화면 상태가 남아 요청한 편집기로 전환되지 않았다. 또 오토메이션을 보던 상태에서 오디오 파일을 가져오면 새 오디오 서클로 선택은 이동하지만 기존 오토메이션 모드가 유지돼 오디오 파형 작업을 바로 시작하기 어려웠다. 하나의 캔버스에서 작업 종류를 바꿀 때 이전 화면 상태가 다음 작업을 가린 문제다.

`qa/generated/audio-automation-flow/baseline-connection-shortcut.{jpg,ax.txt}`와 `baseline-import.{jpg,ax.txt,json}`에 build123 관측을 보존한다. 독립 프로젝트 `DD9B1E78-CF83-4756-BCBD-BECA85D3326D`에서 직접 작성한 WAV69276595…를 가져와 revision25→26의 import를 확인했다. 파일 내용 적용과 작업 화면 전환 문제를 구분한다. QA는 물리 입출력을 차단하며 사용자 원본 앱·곡·오디오 장치 설정을 변경하지 않는다.

## 수정 계약

[AutomationEditor.showAutomation](../Sources/CirclrApp/AutomationEditor.swift)은 이름 편집을 먼저 확정한다. 이름 검증에 실패하면 전환하지 않는다. 유효한 오토메이션 대상에서는 connectionsOpen을false로 정리한 뒤 기존 설정/plugin 상태 정리와 automationOpen·focusHierarchy를 적용한다. 곡의 automation 데이터나 시간·값 의미를 바꾸는 변경은 아니다.

[MediaImportWorkspace](../Sources/CirclrApp/MediaImportWorkspace.swift)는 기존 import 완료·project/revision·선택 보존 조건 안에서 섹션 대상으로 새 오디오를 보여줄 때 automationOpen을false로 바꾼다. 단일 clip은 새 오디오 서클을, 여러 clip은 섹션을 보여주는 기존 규칙을 유지한다. import 도중 사용자가 선택을 바꾸면 현재 작업을 가로채지 않는 조건을 유지한다. 취소·실패·revision 충돌 경로를 정상 import의 화면 정리와 혼동하지 않는다.

## 검증 범위와 완료 조건

read-only source review는 PASS했다. 검증 계약은 다음과 같으며 아래 결과와 미검증 범위를 구분한다.

1. 연결 화면에서 ⌘5 후 오토메이션이 실제로 보이고 같은 대상·음악revision을 유지한다. 이름 오류에서 이동을 차단하고 Escape 후 정상 진입할 수 있어야 한다.
2. 오토메이션에서 단일 authored WAV 가져오기 후 새 오디오의 파형·편집 도구를 바로 보여준다. 실제 import 대상·asset/clip·revision을 대조한다.
3. import 뒤 오토메이션 편집·Undo·저장/재열기의 연속 작업을 검증하고, 화면 전환만으로 음악이 변하지 않는지 확인한다. 실제 수행하지 않은 후속 편집은 완료로 기록하지 않는다.
4. 선택 변경 중 import 완료·취소·revision 충돌·다중 파일 등 분기는 실제 실행한 native 범위와 소스 guard 검토를 구분한다.
5. 패키지 식별·noIO helper와 출력/미리 듣기 시도0, 음악·자산의 의도된 변경 및 Undo/재열기를 저장 데이터와 AX/화면으로 각각 확인한다.

이 변경은 물리 오디오·청취·녹음·영상 동기 또는 전체 한 곡 제작의 완료가 아니다. 사용 중인 원본 앱 교체 없이 독립 QA 사본에서 진행한다.

## 현재 native 결과

Release는42.16초에 성공했고 main UUID는 `B988FE79-820E-3F28-A23B-B84541F5291F`다. `qa/generated/audio-automation-flow/final124`의 connection-shortcut JPEG/AX에서 L로 연 연결 화면 → ⌘5 후 실제 오토메이션 표시를 확인했다.

오토메이션에서 단일 authored WAV를 가져온 뒤 import-waveform JPEG/AX/JSON에서 새 파형이 즉시 보이는 것을 확인했다. revision27·자산5개 상태에서 Undo1회 후 revision28이 되었으며, before-import-manifest의revision26 음악과 view/revision/modifiedAt 메타데이터를 제외하고 정확히 일치했다. 빈 이름 상태에서 ⌘5는 오류를 표시하며 연결 화면과revision28을 유지했고 Escape로 복구했다. Escape·⌘5 뒤 저장한 오토메이션 선택을 재실행 후 실제 JPEG/AX에서 확인했다. saved.json과 reopened.json의 manifest가revision28에서 정확히 일치한다. QA 앱은 정상 종료했다. production 서명·UUID와 독립 데이터 감사도 통과했다.

독립 감사에서 import가 asset·clip·node·edge·position을 각각1개만 추가한 점, Undo 후 음악이revision26 기준과 정확히 일치한 점, saved=reopened=disk의revision28 일치를 확인했다. 원본 자산4개 SHA·noIO·helper5개·서명·UUID도 통과했다. 신규 자산은 Undo/저장 이후 제거되어 현재 파일은 없으며, import-waveform 캡처 당시에는 자산5개 SHA를 직접 검사하여 통과했다. 현재 파일 검증과 당시 캡처 검증을 구분한다.

OpenPanel의 경로/클릭 조작에 실패한 뒤 키보드 목록으로 정확한 WAV를 선택했다. import.jpg·import-completed.jpg는 대화상자의 중간 실패 캡처이며 정상 import 성공 증거로 사용하지 않는다. 성공 화면은 import-waveform이다.

실제 입출력 시도는0이다. import 완료 전 다른 선택으로 이동하는 async 경로·취소/실패·다중 파일·pattern import는 이번 native 검증에 포함하지 않았으며 기존 소스 guard 검토와 구분한다. 오토메이션 곡선의 실제 값 변경·편곡 대안까지 이 결과에 합산하지 않는다.

## 이어서 정리할 에이전트 계약

소스 대조에서 GUI와 MCP의 편집 범위 차이도 확인했다. [AgentProtocol](../Sources/CirclrCore/AgentProtocol.swift)의 `edit_audio`는 일반 AudioEditing.apply로 전달되고 `set_clip`은 effective lane에서 clip을 찾는다. 공유 리듬 오디오의 별도 편집 경로와 동일한 주소·pattern/clip 대상 계약을 연결하는 작업은 후속 범위다. 현재 UI 전환 수정이 MCP 공유 오디오 편집까지 완성한 것은 아니다.

같은 파일의 `set_automation`은 AutomationEditing.set에 original을 전달하지 않지만 GUI의 setAutomation은 editOriginal을 전달한다. [MCP operation schema](../mcp/server.py)와 Core 명령을 함께 정리하여 원본/변형 적용 범위를 명시하고, GUI/MCP 결과·다른 use 보존·stale 거절·Undo/저장 동등성을 검증해야 한다. 이 누락은 현재 소스 대조 결과이며 이번 문서 작성에서 새 MCP 명령을 실행하거나 수정하지 않았다.

[현행 개발 계획](138-current-development-plan.md)에 따라 오디오 가져오기→오토메이션→편곡 대안의 연속 흐름을 이어간다. 기존 스텝·음색·바운스 검증을 반복 집계하지 않고 실제 다음 작업을 가리는 문제부터 해결한다.
