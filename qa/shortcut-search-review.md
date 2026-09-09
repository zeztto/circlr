# 키보드 도움말 검색과 명령 우선순위 — build75

2026-09-09. 기준 dc55720, codex/daw-integration. 변경은 CanvasCommands.swift와 앱 build 번호다. 검색 가능한 도움말, 작업 종류 필터, 제목 일치 우선 정렬을 실제 검증 앱에서 확인했다. 독립 agent 실행은 한도로 거절됐으며 같은 실행자가 코드 검토와 QA를 순차 수행했다.

최종 release는 39.25초에 성공했다. 최종 후보는 `qa/generated/shortcut-search/ranked/써클러 통합 검증.app`, UUID `11D16FC9-632A-3475-8F6F-F66BBCF90A4D`다. source hashes 2개, Mach-O sections 37개, 코드 서명과 Codex kit 25개 파일을 비교했다. 이번 변경에서는 전체 Swift/Python 테스트를 다시 실행하지 않았다. build74의 498/29 결과를 이번 실행 결과로 계산하지 않는다.

1020×768 정도의 작은 창에서 전체 54개 도움말의 검색, 오디오 자동 범위 9개, MIDI 13개, 오토메이션 3개, ↑↓ 스크롤을 확인했다. 오디오 범위의 피아노 검색 결과 없음에서 전체 범위로 넓히면 F 안내 한 행이 나온다. Tab 및 ⌘O 검색도 한 행으로 좁혀진다. 실제 ⌘/ 키 입력은 CUA 키 이름 오류로 검증하지 않았고, 도움말은 명령 팔레트로 열었다.

‘키보드’ 검색은 도움말을 첫 결과로 표시하면서 12개 일치 명령을 모두 유지한다. 최종 앱의 `⌘S 프로젝트` 검색은 저장 한 개를 표시하며 Return 저장 로그를 확인했다. 없는 명령의 Return은 팔레트를 유지하고 음악을 변경하지 않았다. 실행 함수와 NSTextField 제출 계약은 기존과 같다.

초기 후보에서 ‘키보드’ 검색의 첫 연결 명령이 실행된 것을 입력 경쟁으로 잘못 해석했다. AX 기록 `ambiguous-query`가 연결 명령이 먼저였음을 확인하므로 임시 입력 변경은 모두 되돌렸다. QA 사본에서 발생한 두 연결 변경은 각각 Undo했고 r16/r18에서 전체 음악의 복원을 대조했다. `final-audio-help`와 `safe-audio-help`는 성공 도움말 화면으로 계산하지 않는다.

`python3 qa/check-shortcut-search-evidence.py` 통과: 문서 snapshot 7개, 최종 화면 9개, 음악 전체 비교(보기와 revision만 제외), 원본 manifest와 authored asset 2개 보존. 최종 음악 r18이며 물리 출력·audition 시도 0회, MIDI 녹음과 입력 busy 없음. 검증 후보는 종료했다. 사용자 앱 0.19.0 build21 교체나 물리 입출력·VoiceOver 통과를 의미하지 않는다.

로컬 생성 앱·화면·음악·JSON은 commit에서 제외한다. 실제 장치 출고와 전체 작업 흐름 평가는 다음 로드맵 조건으로 남는다.
