# 콘솔 로그 높이 조절

상태: build94 parse·최종 Release40.59초·아래 native 관측 확인. QA 최종 대조 통과. [QA](../qa/console-height-review.md). 신규 Core unit 테스트는 없다.

## 사용자 동선과 상태 계약

콘솔 로그 높이는 세션에서40–180px로 조절하며 기본값은122px다. drag와 키보드의 작게·기본·크게 조작을 제공한다. header 상태와 명령 입력은 유지하고 자동으로 강제 접지 않는다.

높이는 UI 세션 상태이며 음악이나 music revision을 변경하지 않는다. 편집기 왕복에서 선택한 높이를 유지한다. 로그 높이 조절과 스크롤 입력은 음악 캔버스 조작으로 새지 않아야 한다. 명령 초안·취소의 기존 동작을 보존한다.

## 검증 완료 기준

1. drag와 키보드로40/122/180px를 선택하고 범위 밖으로 커지거나 줄지 않는지 확인한다.
2. 1020×768에서122→40px일 때 편집 viewport가82px 증가하고 header·명령 입력과 핵심 상태가 보인다.
3. 편집기 왕복 시 높이가 유지되며 음악·revision이 바뀌지 않는다.
4. wheel 입력 격리, 명령 초안 보존·취소, 키보드 포커스를 실제 UI에서 검사한다.
5. 최종 테스트·Release·native·QA 대조의 확인 범위만 완료로 기록한다. 사용자 앱·물리 출력 출고 조건은 별도 유지한다.

세션 설정을 프로젝트 영구 저장 기능으로 표현하지 않는다. 구현은 UI owner, 계약 기반 검증은 QA owner가 맡으며 문서는 확보한 결과를 반영한다.

## 최종 후보와 관측 범위

초기 Release41.28초 후보에서 메뉴는 작동했지만 입력창 ⌃⌘1/2/3은 실패했다. `CirclrAppCommands` 등록을 수정한 최종 Release40.59초 (`.build/console-height-release-final.log`), UUID `B3A0BC3E-3D1A-3A77-A9FB-37DED0608EB3`를 검증했다.

- 입력창 초안 상태를 유지하며 단축키로122→40/180/122 선택, drag40–180 clamp 확인.
- 접힘 중 단축키 비활성·펼침 후40/초안 유지, audio/router 왕복40, console wheel의 canvas zoom 불변 확인.
- `state` 명령 성공과 초안 비움, revision62 saved/reopened 전체 manifest strict 동일 및 같은 세션 높이40 유지 확인. 모든 음악 revision은62로 유지됐다.
- MCP geometry에서 consoleHeightReduction82를 정확히 확인했다.

실행 중 job 취소 버튼은 이번 native에서 검증하지 않았다. 앱 재시작 후 로그 높이는 세션 기본122px이며 프로젝트 재열기와 구분한다. QA baseline1+initial3+final14의18개 snapshot·최종AX10개·자산2개·physical0 대조를 통과했다.
