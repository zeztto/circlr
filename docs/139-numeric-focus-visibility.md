# 수치 입력 포커스의 화면 노출

0.20.0 build121. 공통 수치 컨트롤의 접근 문제를 수정한 기록이며 전체 DAW 사용성·실제 오디오 검증과 구분한다.

## 재현과 수정

같은 authored 프로젝트와 콘솔180pt 조건에서 build120의 compressor 임계값−21dB와 압축비4.5는 모두 보였다. 그러나 다음 Tab으로 출력 볼륨0.00을 선택하면 입력란이 화면 밖에 남았다. AX 선택 값만으로는 가시성을 판정할 수 없어 같은 시점의 화면도 대조했다.

`CommittedNumberField.swift`의 native control은 `becomeFirstResponder` 성공 뒤 enclosing scroll view가 있을 때 자신의 bounds와 세로22pt 여백을 노출한다. 명시적 focus registry가 없는 일반 Tab 경로에도 적용된다. commit·binding·검증 계약은 유지한다. `EffectControls.swift`는 상위 `NumberEditingContext` 전체를 복사하고 fieldFocus만 바꾸도록 했다. names 누락의 실제 장애가 확인된 것은 아니다.

## 이번 후보의 검증

- Release 빌드44.03초 완료. source·QA·production main UUID `BE4C0064-8C4B-34EB-92B4-67DC7FC8D0B6`; QA와 production 패키지의 서명 검증 통과.
- 실제 Tab으로 임계값→압축비→출력 볼륨 이동 시 출력 볼륨이 화면 안에 나타났다. Shift+Tab 두 번으로 임계값에 돌아올 때도 해당 필드가 보였다.
- 출력 볼륨−6dB 적용으로 대상 effect node의 gain만1→0.5011872336272722, revision43→44. 실행 취소 후 gain1·revision45로 복원했다.
- 미확정 `-6.` 입력 중 콘솔180→122pt 변경 후 초안과 focus를 유지했다. Esc 취소 후 음악revision45가 유지됐다. 설정/이펙트 페이지 왕복 화면도 검토했다. 모든 페이지의 정확한 scroll offset 복원을 증명한 검사는 아니다.
- 같은 fixture의 신스11개 필드를 Tab 순방향11개 상태·Shift+Tab 역방향10개 상태로 확인했다. 마지막 움직임0.55와 첫 필터10000의 선택 및 화면 노출을 확인했다. 기존 명시적 focus chain과 공통 reveal을 함께 사용했을 때 이 경로의 접근 실패가 없었다.
- before/edited/undone/cancelled/synth-regression/reopened의6개 저장 snapshot을 수집했다. 독립 증거 감사에서 Undo 이후 음악과 자산 보존, reopened manifest와 disk의 정확한 일치를 확인했다. 재실행 시 QA 콘솔은 기본122pt/열림으로 복원했다.

로컬 증거는 `qa/generated/effect-access/`의 baseline120과 final121에 있다. 최종 후보는 AX 왕복4개 파일, snapshot6개와 JPEG9장이다. 화면은 직접 검토했으며 screenshot bytes는 JPEG로 저장했다. 증거·fixture·앱·미디어는 source push에 포함하지 않는다.

재현 도구: [QA 패키징](../qa/prepare-effect-access-qa.py), [snapshot·저장 검증](../qa/verify-effect-access-native.py). 이미 있는 candidate와 증거는 덮어쓰지 않는다. fixture의 음악은 기존 직접 작성 QA 자료를 복사하며 원본은 보존한다.

## 범위와 다음 작업

QA 앱은 별도 bundle ID와 fixture/socket을 사용한다. 다섯 audio helper는 exit78 stub이고 output/audition attempts0, 재생·녹음 없음 조건을 검사했다. production 패키지는 실제 helper를 포함하되 실행하지 않았다. QA 앱 종료 후 사용자 원본 앱PID86114는 유지했다.

물리 오디오·연주 지연·VoiceOver 발화·한국어 IME·모든 폼/창 크기는 미검증이다. [현행 개발 계획](138-current-development-plan.md)에 따라 다음 단위는 한 곡의 섹션 생성부터 저장/재열기까지의 연속 동선이다. 이번 수치 접근 개선을 전체 제작 흐름의 완료로 세지 않는다.
