# build152 페달 포커스 요청 유지

범위: 페달 편집기 진입의 포커스 수명 한 가지를 수정한다. 음악 모델·저장 schema·MCP 계약은 바꾸지 않는다.

## 변경

기존 공통 attachment의 finalAttempt에서 SustainPlotView가 아직 없으면 요청을 취소했다. 페달 화면이 열려 있고 MIDI lane이 유효한 동안 기존 요청을 유지하며, 그래프 mount 또는 update에서 다시 소비한다. 새 요청을 자동 생성하지 않는다.

기존 identity/page 검사, 다른 창·모달 보호, field editor 소유자·IME·수치 초안 검사와 사용자 포커스 이동 검사를 그대로 거친다. 모드·대상이 바뀌면 오래된 요청은 취소된다.

## 검증

Release 빌드 결과는 아래 최종 기록을 참고한다. 소스 변경 범위와 diff를 검토한다. 실제 앱의 첫 진입·재열기 포커스 성공은 아직 검증하지 않았으며, build151의 관측을 build152 성공으로 바꾸지 않는다. 설치 앱은 교체하지 않는다.

## 실사용 확인

1. MIDI에서 페달로 전환한 뒤 그래프를 클릭하지 않고 대괄호/Home/End로 선택한다.
2. 페달 상태로 저장·재열기한 뒤 같은 동작을 확인한다.
3. 빠르게 노트/페달을 왕복할 때 마지막 모드만 키를 받는지 확인한다.
4. 수치 입력·잘못된 초안·한국어 조합 중 늦은 포커스 이동이 없는지 확인한다.
5. 다른 창·파일 대화상자·다른 서클로 이동한 뒤 과거 요청이 입력을 가져가지 않는지 확인한다.

현재 상태: 소스 수정과 아래 제한된 native 확인 완료. 이번 버전은 포커스 전체 문제의 해결을 선언하지 않는다.

Release 검증: `swift build --scratch-path .build/app-release -c release --product circlr` 성공 (exit 0). 로그: `.build/build152-release.log`. `git diff --check` 통과. UI 동작은 위 실사용 절차로 별도 확인한다.

## build152 native 후속 확인

동일 Release를 패키징하고 별도 `focus152` QA 앱에서 확인했다. 다섯 출력/미리 듣기 helper는 exit78 stub이며 사용자 설치 앱은 교체하지 않았다. build151 fixture를 `focus152.circlr`로 복사해 사용했다.

- 피아노 롤→페달 전환 후 그래프를 클릭하지 않고 Home으로 1/6 raw100, End로 6/6 raw127을 선택했다. Tab으로 위치 수치81 진입을 확인했다.
- 앱 종료·재실행 후 MCP로 같은 파일을 열고 창을 활성화했다. 그래프 클릭 없이 Home/End로 동일 이벤트를 선택했다. 초기 AX는 outer canvas를 표시했으므로 열기 완료 시점부터 즉시 graph focus가 보장된다고 주장하지 않는다.
- 모드 전환과 같은 호출에서 즉시 보낸 첫 Home은 선택을 바꾸지 않았고, 이후 Home은 정상 적용됐다. 지연·입력 타이밍의 모든 조합은 미검증이다.
- `before-reopen.json`과 `reopened.json`의 전체 manifest가 같고 실행 PID는 달랐다. 원래 build151 fixture와 hierarchyView를 제외한 음악 전체가 같다. 두 캡처 모두 r242, no-I/O, 자산 checksum과 패키지 식별을 검사했다.
- 증거: 로컬 `qa/generated/midi-import-return/focus152/`의 AX 01–07, 최종 화면, 두 state/manifest 캡처와 package.json. 생성된 QA 자산은 레포에 넣지 않았다. 최종 검증 앱을 종료했다.

범위: 모드 전환·재열기의 키보드 선택, Tab 진입, 저장 데이터 보존을 통과했다. 빠른 반복 전환·invalid draft·IME·다른 창의 모든 조합과 실제 오디오는 이번에 실행하지 않았다. 새 소스 수정이나 build 번호 증가는 없다.
