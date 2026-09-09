# build 70 캔버스 접근성 좌표 검증

2026-09-09, `codex/daw-integration`, 기준544715b. 실제 추가 agent 슬롯이 없어 UI/UX → native Swift utility → code/security review → QA를 순차 수행했다. 전체 DAW/UI 목표는 진행 중이다.

## 결과

- 스텝 행·셀, 피아노롤·궤도 노트, 오토메이션 점, 서클·포트·케이블의8종 가상 요소에 부모 AX 좌표를 사용한다. AppKit이 화면으로 변환한 rect에서 부모 AX origin을 빼므로 flipped view·nonzero bounds·배율을 반영한다.
- 스텝 요소를 스크롤/커서 이동 중 재사용한다. 같은 문맥에서 방문한 행만 생성하고 최대128×17개로 제한된다. 프로젝트/세션/음악 revision/페이지/격자/행 목록/선택 identity 변경은 캐시를 초기화한다. 화면에 보이는 행만 children으로 노출하며 숨겨진 행의 기존 press guard를 유지한다.
- AppKit14개 검사 통과: flipped/unflipped 각각 최초·창 이동·문서 스크롤·bounds 원점/배율·문서/창 크기. 창 이동·스크롤은 자식 frame을 다시 설정하지 않고 검증했다. 실제 production helper를 함께 컴파일한다.
- 새 scratch Swift491개, 실패0,26.228초; Python29개, 실패0,0.234초. 물리 출력 의존 `testArrangementRenderExportAndPlayback`만 제외했다. 최종 변경은 AppKit 스텝 캐시에 한정되며 최종 release40.94초와 native 경계/검색/페이지/편집 재검증을 수행했다. 최초 release41.55초.
- `python3 qa/check-accessibility-geometry-evidence.py` 통과: 전체 문서/상태14개, 화면21개, 최종 소스8개 hash, 실행37개 section, kit25개 hash, 세 앱 codesign과 원본/사본 자산 checksum.

## 후보와 실제 동작

baseline은 build69 UUID `9D5D89DF-3A39-3992-9258-7F96874D2202`. 최초 build70(`final` 폴더) UUID `EF871FD9-50B7-3358-9063-38A6C85A2C1A`. 최종 build70(`refined` 폴더) UUID `A9524F90-F125-3A79-A90F-D680A06C7F93`. 세 앱 모두 종료했다. 파일명 `final`은 최초 후보의 경로이며 최종 증거는 `refined`다.

검증 사본은 `~/Library/Application Support/circlr-integration-qa/fixtures/accessibility-geometry.circlr`, ID `E95D8338-1A25-5D4B-A44C-5DEDDDB6B8F4`. 원본 authored3트랙·2톤·공유 섹션 사용을 유지한다. 작은 창은 약1024×768이며 콘솔을 연 상태다.

| 경로 | 실제 근거 |
|---|---|
| 기준 실패 | build69의 보이는69번 행 클릭이 `elementHasNoFrame`으로 거절됨. `baseline-step`, `baseline-row-error.txt`. 단독 AppKit에서 direct setter의 최초 frame은 정상이어도 실제 도구 경로는 실패했다. |
| 최초 후보 | 부모 frame으로 일반69행/3스텝 클릭은 성공, 노트69/beat0.5/length0.225/velocity96만 생성(r15). Undo r16. End 뒤 경계66행 접근 중 같은 오류가 재현되어 객체 재사용을 추가했다. `step-scroll-failure`를 통과 근거로 사용하지 않는다. |
| 최종 경계 행 | 66행 → Right2회 → End → 화면 상단66행 클릭 성공. Home 뒤 하단69행도 성공. 현재3스텝 열 유지, 음악r16 그대로. `refined-bottom`, `refined-scrolled-row`, `refined-top-row`. |
| 최종 키보드 입력 | 선택한66행에서 Return은 beat0.5의 노트 한 개만 생성(r17), Undo r18. 기존3개 및 다른 사용은 동일. `refined-input`. |
| 검색/페이지 | 드럼73 검색→Return→행 클릭, 피아노롤/궤도/서클 왕복 후 검색 유지. 다음/이전 페이지 왕복 뒤73행/3스텝 클릭은 새 노트 하나(r23), Undo r24. `drum-filter`, `refined-cell-input`. |
| 피아노롤/창 크기 | AX 이름으로69노트 선택 후 실제 창 zoom과66노트 클릭 성공. 수치와 클릭 위치 일치, 음악r18 유지. `piano-selected`, `piano-resized`. |
| 오토메이션 | 점 추가2회(r20), AX1번 점 클릭은 첫 점만 선택. Undo2회로 곡선 제거(r22). 두 점의 실제beat0/0.25·gain1·linear와 다른 graph/음악 보존을 대조. `automation-point`. |
| 궤도/서클 | 궤도73노트 선택으로 pitch73/start3박/velocity74 표시. Esc 후 MIDI 서클의 이름 클릭으로 같은 캔버스 편집을 다시 엶. `orbit-selected`, `section-canvas`, `circle-opened`. |
| 포트/케이블 | 섹션 IN 재생 경로 포트 클릭과 MIDI→악기 케이블 클릭으로 각 선택 도구 표시. 음악/연결/portLayout 무변경. `port-selected`, `cable-selected`. |
| 저장 재열기 | 최종r24 전체 음악은 초기r14와 동일하며 circleLayout만freeform→orbit, hierarchyView 변경. MCP open job 완료를 확인한 뒤73 검색/행 클릭 복귀. `final-restored`, `reopened`, `open-completed`. |

## 검토·보존·다음 범위

좌표 변경은 음악 입력/신호/권한 계약을 바꾸지 않는다. 모든 helper 호출의 accessibility parent가 전달한NSView인지 확인했다. 스텝 캐시는 컨텍스트 변경 시 비우고 기존 revision/ID/visibleRows/enabled 검증을 유지한다. 새 네트워크·인증·파일 접근 경로가 없으며 QA 도구는 고정된fixture/app과 build/projectID를 검사한다. 이 변경의 미해결 출고 차단 결함은 발견하지 못했다.

원본 manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 자산 checksum은 동일하다. 모든 snapshot의 output/audition attempts0·재생/녹음false다. root `d88ea5d`, ports `1d304eb`, 사용자 앱0.19.0build21을 보존한다. 화면 녹화/물리 입출력·실제 VoiceOver 발화·보조 도구가 장기간 보관한 오래된 객체 호출은 별도 검증 범위다. 캐시의 무효화 guard는 소스 검토이며 stale AX invocation을 직접 실행했다고 주장하지 않는다.

다음 UI 작업은 선택 노트/오토메이션 점/오디오 분할 커서의 서클별 복귀, 작은 창의 오디오 정밀 입력/작업 버튼 가시성이다. 전체 DAW·출고 목표는 계속 진행한다.
