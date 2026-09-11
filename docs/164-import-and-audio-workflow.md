# MIDI 가져오기와 오디오 편집 동선

상태: build142의 아래 구현·Release·native 검증을 완료했다. 최종 UI 감사는 `PASS_WITH_SCOPE_LIMITS`, state 독립 감사는 PASS다. 기준 HEAD는 `b47226c`다. 소스 검토와 관련 테스트·빌드도 PASS했다. 완료된 build141의 포커스 검증을 이번 파일 작업 성공으로 대체하지 않는다.

## 실제 build141 재현

`workflow142-before/import-top`의 첫 화면에서는 가져올 트랙 목록이 보이지 않았다. 한 페이지 스크롤한 `import-tracks`에서는 파일 이름과 대상 표시가 사라져 선택 중인 자료와 적용 위치를 함께 확인하기 어려웠다.

pitch 편집에서 시작한 단일 import는 r171에 새 노트 3개를 만들었지만 빈 pitch editor를 열었다. 공유 범위에서 시작한 import는 r173에서 shared scope 오류를 표시했다. Undo r174의 원곡 복원은 독립 대조에서 음악 일치를 확인했다.

## 구현 범위

`MIDIImportView`의 파일·대상 정보를 상단에 고정하고 트랙 목록을 앞에 배치한다. 스크롤로 정책과 세부 설정을 보더라도 현재 파일과 적용할 use를 식별할 수 있어야 한다. 기존 preserve/omit·tempo 정책과 오류 guard를 유지한다.

단일 import 성공은 새로 만든 이번 use의 content를 대상으로 기본 노트 모드를 연다. 이전 pitch 모드나 공유 원본 편집 범위를 새 MIDI에 넘기지 않는다. 데이터 생성 성공과 생성물을 바로 편집할 수 있는 상태를 함께 검증한다. 취소는 이전 mode·scope·workspace 복귀 계약을 유지하며 성공과 취소를 같은 상태 전환으로 처리하지 않는다.

`AudioWorkspace`는 action row를 파형 앞쪽에 배치해 편집 동작의 접근을 높인다. 파형·수치·작업 버튼의 실제 가시성과 키보드 이동을 대조한다. 화면 순서 변경을 오디오 기능 전체 완료로 해석하지 않는다.

## 완료 기준

- 작은 창과 콘솔이 열린 상태에서 첫 화면에 파일·대상·트랙 선택이 함께 보이고 스크롤 뒤에도 파일·대상을 확인할 수 있어야 한다. 실제 창 크기와 AX/JPEG를 기록한다.
- 일반 pitch 출발과 공유 scope 출발의 단일 import를 실행해 새 노트와 이번 use 노트 모드·scope가 일치하는지 확인한다. 다른 use·공유 원본과 기존 음악의 보존을 대조한다.
- 실패·취소·Undo·저장/재열기를 실행한 범위에서 비교한다. 미실행한 multi-import·모든 정책 조합은 source 검증과 구분한다.
- 오디오 action row의 마우스·키보드 접근, 파형·수치 가시성 및 기존 invalid 입력 보호를 확인한다.
- 실제 파일 작업과 생성된 음악·자산·revision을 비교하고, 순수 탐색의 음악 불변을 확인한다. 물리 I/O·청취와 전체 DAW 완료는 별도 조건이다.

검증은 QA 사본에서 수행한다. 다른 작업자의 변경과 사용자 원본을 보존하며 최종 결과는 실제 로그·패키지·native 증거를 확보한 뒤 추가한다.

## build142 검증 결과

Release는 45.66초에 통과했다 (`.build/build142-release.log`). 관련 검사 49개·실패 0개를 확인했다 (`.build/build142-workflow-tests.log`). `workflow142-final/independent-package-audit.json`의 패키지 독립 감사도 PASS했다. 전체 테스트 suite는 이번에 실행하지 않았다.

| 실제 동선 | 확인 결과 |
|---|---|
| 오디오 진입 r174 | action row·파형·첫 수치 4개 가시성 |
| split r175→Undo r176 | 음악 복원. Undo는 overview로 복귀하며 파형 자동 복귀를 확인한 것은 아님 |
| pitch import 취소 r176 | 원래 pitch workspace 정확히 복귀 |
| 단일 import | pitch 출발 r177, 공유 원본 출발 r178→r179 모두 이번 use의 piano·노트 3개. Tab으로 노트 선택 |
| 여러 트랙 import r181 | section overview 진입, Undo r182 |
| 잘못된 시작 위치 | -1의 고정 오류·Apply 비활성, 취소 r182 |
| 저장·재열기 | r182 before/after-restart의 전체 workspace·hierarchyView·runtime 일치. UI 독립 감사 PASS_WITH_SCOPE_LIMITS, state 감사 PASS |

실제 물리 I/O·전체 suite·긴 파일 이름·표현 정책 모든 조합·오디오 키보드 모든 조합은 실행하지 않았다. 이번 개선 완료를 전체 DAW·접근성·음악 품질 완료로 확대하지 않는다.

root의 strict 비교에서도 pitch-origin→pitch-cancel의 project/revision/address/노트 선택/음악/전체 hierarchyView가 일치했다. native UI 감사는 16쌍을 `PASS_WITH_SCOPE_LIMITS`로 확인했다. QA 앱 종료를 ps로 확인하고 사용자 production PID 86114는 유지했다.

최종 state 독립 감사는 캡처 10개에서 split 16+16, 단일 import 각각 노트 3개, 다중 import 2트랙·6노트 및 원본·다른 use·자산 6개 SHA 보존을 확인했다. 취소·전체 Undo·재시작도 정확히 일치해 PASS했다.
