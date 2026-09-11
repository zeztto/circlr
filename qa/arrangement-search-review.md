# 편곡안 검색 검증 — build 63

2026-09-09, `codex/daw-integration`, 기준 `38f22129028356c3c05df5109aad44f186f44eb0`. 사용자 재요청으로 독립 읽기 전용 review agent를 다시 dispatch했으나 `agent thread limit reached`로 거절됐다. 실제 총 1 slot에 맞춰 UX/구현/읽기 전용 검토/QA를 순차 수행했다. 독립 agent 검토는 수행하지 못했다.

## 검사와 최종 후보

- ArrangementSelectionTests 6개/실패0, 0.004초. 소유 곡의 선언 순서·동명/긴 이름·Unicode/전각/#정확 번호·다른 소유/누락/컨테이너 거절·65개 목록·현재 선택 no-op·전체 모델의 변경 범위를 검사했다.
- `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`: 457개/실패0, 26.227초. 기존 HAL 환경의 물리 playback 한 테스트는 제외했다.
- `python3 -m unittest mcp.test_server qa.test_agent_kit`: 28개/실패0, 0.213초. 기존 MCP·키트 계약은 유지한다.
- 초기 release 65.30초, UUID `9DD7F4BC-8C6B-3C22-BC64-D51557E1044A`. Native에서 설정 버튼의 가시성을 수정한 최종 release는 37.53초, UUID `99381634-AAE0-3A4D-9AD9-F80C6FFBB0B4`, 0.20.0 build63이다.
- 최초 관련 빌드는 SwiftUI 목록 표현식의 type-check 시간 초과로 실패했다. row와 rowContent를 추출한 뒤 관련/전체 테스트와 release를 실행했다. 초기·최종 제품 소스 14개 중 변경된 파일은 InlineCircleEditor.swift 하나이며, 설정 버튼 순서만 바뀌었다. 최종 바이너리에서 버튼 진입·선택·Undo·재열기를 다시 검사했다.

## 실제 앱 검증

`qa/prepare-arrangement-search-qa.py`는 authored 원본 fixture의 3트랙/2asset 사본에 두 번째 section use와 67개 편곡을 준비한다. 첫 곡은 65개, 다른 곡은 2개를 소유한다. 동명·긴 이름·빈 편곡은 QA에만 들어가며 제품 catalog는 실제 프로젝트를 읽는다. 프로젝트 ID `96F52E7D-A74F-57EE-B9B9-139761DC6D9A`, baseline r14. `qa/verify-arrangement-search-native.py`는 정확한 bundle/build/path/ID 및 출력 카운터를 확인한다. 선택은 실제 GUI로, 외부 변경과 Undo·저장·열기는 native MCP로 수행했다.

| 흐름 | 결과 |
|---|---|
| 곡 서클의 편곡안 버튼 / ⌥⌘J / 명령 검색 | 같은 캔버스의 검색을 바로 열고 실제 소유 곡·재생 선택·65개 결과 표시 |
| 한글 NFD 붙여넣기 / 전각 #１ / #999 | 동명 #2·#3·긴 #65 세 결과 / 정확히 #1 한 결과 / 빈 결과 |
| 긴 이름 / 현재 편곡 찾기 | #65 전체 help·AX, 두 줄 이름. 검색 초기화 후 현재 #3 강조·포커스 복원 |
| 현재 재선택 / 다른 편곡 선택 | r14 유지 / #3 선택 r15. 원본 편곡 내용과 다른 곡 보존 |
| Undo → 현재 재선택 → Redo | r16의 문서와 화면 전체 동일한 no-op, Redo로 #3 복원 r17 |
| 빈 편곡 / Undo | #4의 0개 섹션 표시, r18에 선택하고 r19에 #3 복원 |
| 검색 중 프로젝트 이름 외부 변경 | r20, 이전 요청의 결과 비활성화·재진입 안내. 선택 적용 없음 |
| 검색 중 다른 곡으로 focus | r21 유지, 이전 요청 비활성화. 새 검색에는 다른 곡의 2개만 표시 |
| 다른 곡의 대안 / Undo | r22에 다른 곡 #2 선택, r23에 복원. 첫 곡 #3와 모든 편곡 내용 보존 |
| 작성 중인 곡 이름 → 단축키 | 이름을 먼저 확정한 r24의 새 범위로 유효한 검색 표시. Undo r25로 이름 복원 |
| 작업 이동 / 샘플 라이브러리 전환 | 이전 편곡 overlay 제거, 새 검색만 활성. 음악·출력 카운터 유지 |
| 음색 편집 중 단축키 / 현재 재선택 | 소유 곡의 검색 진입. 카메라가 안정된 전후 manifest·선택 전체 동등 |
| 최종 설정 버튼 / #2 선택 / Undo | 스크롤 없이 첫 항목으로 보임. r26에 #2 선택, 한 Undo로 r27의 #3 복원 |
| 최종 저장·종료·재열기 | final-saved와 final-reopened manifest 전체 일치. 실제 검색에 #3 재생 편곡 표시 |

최소 폭 1024, 콘솔을 펼친 화면의 실제 픽셀을 확인했다. 첫 후보의 설정 안 버튼은 음악 설정 아래 스크롤 밖에 있어 보이지 않았다(`settings-before`). 버튼을 설정 맨 위로 이동해 `final-settings`에서 스크롤 없이 보이고 클릭 한 번으로 검색하는 것을 확인했다. 검색은 850×560으로 목록·현재 선택·키보드 안내가 창 안에 보인다. AX에서도 배경 캔버스가 제외된다. 고정 좌우/하단 편집 창은 추가하지 않았다.

처음 입력한 한글 NFD 문자열은 shortcut 직후 도구 입력 타이밍 때문에 반영되지 않았다. 검색 포커스를 확인한 뒤 paste로 다시 검사했다. 하드웨어 IME 조합 검증을 주장하지 않는다. 초기 baseline 및 첫 editor-before는 focus animation 도중 저장되어 카메라 값이 달랐다. 이후 카메라가 안정된 editor-stable과 editor-stable-noop를 별도로 저장해 전체 문서·선택의 정확한 동등성을 확인했다. 최초 job 조회의 `id` 인자는 adapter가 거절했고 올바른 `jobID`로 완료 상태를 확인했다. 증거 checker를 작성할 때 이전 음색 QA의 cutoff731 전제를 잘못 가져온 assertion은 제거했다. 이 fixture의 cutoff는10000이며 전체 모델 동등 비교로 실제 초기 값을 보존한다. 해당 QA 오류와 중간 자료는 남겼다.

## 검토와 보존

Core catalog는 소유 composition의 arrangementIDs만 사용하며 누락/중복/외부 소유를 거절한다. 선택은 기존 AlbumEditing의 selectedArrangementID와 activeArrangementID만 변경한다. 현재 선택은 mutate를 부르지 않아 Undo/Redo를 소비하지 않는다. UI 요청은 프로젝트·revision·세션·선택·편집 상태·owner를 고정하고, 준비/녹음/import 중이거나 대상이 바뀌면 적용을 막는다. 원본 이름 draft는 요청을 고정하기 전에 기존 규칙으로 해결한다. 다른 overlay/새 세션은 요청을 지운다. 캔버스 keyDown/file drop 진입점도 차단한다. 파일 drop guard와 녹음 중 guard는 코드 검토 범위이며 실제 드롭/녹음 검증으로 표현하지 않는다.

수정된 제품 경로에 새 shell 실행·네트워크·파일 읽기·인증정보 접근은 없다. QA helper는 고정된 owned fixture/app 경로를 사용하고 생성 자료를 Git에서 제외한다. 최종 읽기 전용 검토에서 차단할 결함을 발견하지 않았다. 전체 VoiceOver·하드웨어 IME·물리 재생/녹음은 미검증이다.

`qa/check-arrangement-search-evidence.py` 통과: 저장 상태26개, AX/JPEG24쌍, 두 곡/67편곡, 소스14개, Mach-O37 section, signed app 및 Codex kit25파일. 초기/최종 source hash와 최종 바이너리를 대조했다. 원본 fixture SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱0.19.0 build21을 보존했다. Owned QA 프로세스0, 등록 폴더1, 모든 capture에서 output/audition attempts0·재생/녹음 없음. 생성 앱·fixture·스크린샷·상태 JSON은 Git에 넣지 않는다.
