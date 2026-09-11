# 선택 섹션 뒤 삽입과 출력 준비 단계

상태: build88 대상 테스트·Release·아래 native 관측 확인. 섹션 QA22개 상태·자산2개 보존 대조 통과. [섹션 QA](../qa/section-insertion-review.md). 섹션 편집과 출력 진단의 완료 범위를 분리한다.

## 선택 섹션 뒤 삽입

선택한 섹션 뒤에 새 섹션을 삽입할 때 기존 `A→B`를 `A→new→B`로 원자적으로 바꾼다. 끝 섹션 뒤 삽입은 기존 끝의 `isEnd`를 새 섹션으로 이전한다. 기존 독립 섹션 추가 동작은 유지한다.

분기·합류·loop·끝 표시와 잠재 outgoing의 모순·기본값이 아닌 transition처럼 단순 삽입의 의미가 불명확한 연결은 명시적으로 거절하고 연결을 확인·수정할 경로를 제공한다. 임의로 연결을 버리거나 다른 경로를 선택하지 않는다. 성공한 삽입은 한 번의 Undo로 복원되며 다른 편곡을 변경하지 않는다. 기존 선택·키보드 동선에서 작업할 수 있어야 한다.

Core API는 `SectionInsertion.assess(arrangementID:afterUseID:in:)`의 issue/canInsert/successorID와 `insert(...name:bars:at:in:)`의 새 use ID다. 이름 trim1–120자·bars1–4096·유한 좌표 abs<1e7을 검증한다. `Transition()`과 다른 설정은 길이가0이어도 거절한다. 전체 migration 없이 새 section graph만 생성하며 active·album 선택을 보존한다. MCP는 `circlr_apply`의 `insert_section`에 `arrangementID`·`useID`·`name`·`bars`·`at`을 명시한다.

완료 기준:

1. 중간 `A→B`, 끝 섹션과 독립 추가를 각각 검사한다. 삽입 후 경로·순서·끝 표시가 일치한다.
2. 분기·loop·non-default transition 거절은 부분 변경 없이 끝나고 연결 수정 대상이 명확하다.
3. Undo/Redo·다른 편곡 보존·저장/재열기와 실제 키보드 동선을 확인한다.

## 출력 준비 단계 기록

제한된 크기의 typed trace로 CAF 준비, helper hello, 파일 검증, engine·mixer·routing·schedule·start·play의 진입/완료와 세션 시간을 기록한다. `PlaybackOutputStatus.trace: PlaybackOutputTrace?`의 sessionID/events/helperReportsStages로 제공한다. event는 stage/phase/elapsedSeconds와 선택적 workerElapsedSeconds를 가진다. host 준비 시작과 helper 시작 기준 시간을 구분한다. 호스트4개+helper14개, 최대18개 event와 유한 시간·순서를 검증한다. helper 단계는 fileValidation/engineCreation/mixerAcquisition/routing/scheduling/engineStart/playerPlay의 entered/completed다.

각 trace는 해당 세션에 속하며 timeout과 cleanup 뒤에도 마지막 기록을 확인할 수 있다. 무한 누적을 피하고 교체 세션 기록을 이전 요청이 덮어쓰지 않게 한다. UI는 짧은 한국어 현재 단계와 Space 취소를 표시하도록 구현했다. cleanup 뒤 기존 status.elapsedSeconds는0이며 마지막 event 진입 시점을 구분한다. trace 없는 구형 v1 helper는 지원하되 old host+new helper 조합은 지원하지 않는다. host UI의 실제 믹서 준비 표시·Space 안내와 취소/정리를 확인했다. 정상 출력 성공과는 구분한다.

이 작업은 timeout 길이·retry 정책·장치 선택을 바꾸지 않는다. 단계 관측은 지연 구간을 좁히는 근거이며 원인 확정이나 정상 출력 복구를 의미하지 않는다.

완료 기준:

1. 대표 정상·오류 경로에서 단계 순서·enter/complete·세션 시간을 대조하고 trace 상한을 검사한다.
2. timeout·취소·cleanup 후 기록 보존과 교체 세션 분리를 확인한다.
3. 실제 UI의 현재 단계·Space 취소를 확인하며 기존 timeout/retry/device 정책이 유지된다.
4. 실제 출력 성공과 단순 진단 기록 수집을 분리하고 원인 해결을 증거 없이 선언하지 않는다.

## 사용자 앱과 검증 경계

현재 기본 socket의 읽기 전용 관측은 runtime version0.14, dirty=true, minimized=true, playing=false다. roadmap의 사용 앱0.19는 디스크 출고 버전일 가능성이 있어 실행 중 프로세스의 버전과 동일하다고 가정하지 않는다. 이 관측은 해당 시점의 상태이며 사용자 앱을 변경하지 않는다.

## 확보한 근거와 남은 검증

Audio26개·Core7개·MCP23개·kit9개·file worker16개와 최종 Release52.87초를 통과했다. 실제 MIDI 편집 중 명령으로 중간 섹션 삽입·Undo/Redo를 확인했다. 섹션 checker22개 상태·자산2개 보존 대조를 통과했다.

[raw Release helper 관측](../qa/output-preparation-native-review.md) 두 회는 started0.532605/0.121681초·진행 clock·자연 finished를 확인하고 command EOF 뒤 강제 종료 없이 exit0으로 끝났다. 별도 무음 진단 두 표본이므로 startup 문제 해결이나 성능 개선으로 일반화하지 않는다.

별도 앱 host fixture의 offline export는2초·96000 frames가 모두0인 PCM임을 확인했다. 첫 play는 timeout했고 마지막 기록은 mixerAcquisition/entered, trace9개였다. timeout 뒤 Space는 명시적 두 번째 시도를 시작했으며 역시 timeout했다. 세 번째 시작 뒤 Space로 즉시 취소해 request=cancelled·idle·didStart=false를 확인했다. 실제 `play.png`/AX에 믹서 준비6초와 Space 안내가 있고 `cancelled.ax`를 보존했다.

패키지 안의 최종 worker를 CLI로 독립 실행해도 두 번 mixerAcquisition에서 timeout했다. 성공한 두 시도는 raw Release helper다. 두 binary의 UUID·기계코드 섹션은 같지만 codesign과 .app 위치가 다르다. host에 한정된 문제라고 판단할 수 없으며 이 차이가 원인이라는 결론도 아직 없다.

추가 [matrix 결과](../qa/generated/output-preparation-build88-matrix/matrix-summary.json)에서 패키지 byte 동일 사본을 .app 밖에 둔2회와 raw 사본을 재서명해 .app 밖에 둔2회가 모두 mixerAcquisition/entered에서 timeout했다. 원본은 보존했고 command EOF 뒤 모두 exit0으로 정리됐다. .app 위치만으로 설명되지 않으며 서명 가설은 강화되지만 동시간 raw control이 없어 인과는 미확정이다.

다음은 worker 재서명을 생략한 QA 사본의 outer codesign strict 검사와 실제 출력 대조를 계획한다. 현재 checkpoint에서 추가 실행 결과는 없다. 진단 UI·cleanup·cancel 확인을 정상 앱 출력이나 startup 원인 해결로 확대하지 않는다. raw helper 성공·섹션 삽입 완료를 패키지 출력 복구나 물리 I/O 출고 완료로 합산하지 않는다.
