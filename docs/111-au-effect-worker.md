# Offline Audio Unit effect 실행 격리

상태: `codex/daw-integration` build96 최종 관련 테스트·Release·패키지 Apple AU 검증 통과. [QA](../qa/au-effect-worker-review.md). 사용자 dist 앱은 교체하지 않는다.

## 범위와 실행 계약

Offline effect의 Audio Unit instantiate·render를 별도 process에서 수행한다. 앱 안의 plugin hang/crash가 작업 전체를 무기한 막지 않도록 descriptor·state·PCM 전달과 결과 수신 경계를 정의한다.

- descriptor·state·frame 수·결과 형식과 크기를 제한하고 입력/출력을 검증한다. state8MiB·request12MiB, maximumFrames268435456(기존2GiB/8byte 단일 PCM 호환 hard bound)을 사용한다. 실제 다중 buffer 예산은 기존 `RenderTailPlanner` memory preflight로 제한한다. truncated·nonfinite 결과를 정상 오디오로 적용하지 않는다.
- 요청마다 고유 세션 ID를 사용하고 결과는 검증 완료 뒤 원자적으로 적용한다. 취소·대상 교체·deadline 이후 늦은 완료를 반영하지 않는다.
- deadline은 duration×4+15초를30–1800초로 제한한다. 취소·deadline·비정상 exit에서 소유한 child와 임시 파일을 정리한다. 성공 경로의 cleanup 실패는 error로 보고하고 실패 경로 cleanup은 best-effort다. 실제 삭제 여부는 검증 환경에서 별도로 확인한다. 실패를 보존하고 명시적인 재시도 경로를 검증한다.
- `AppStore`·`AgentWorkspace` outer task에 진입 guard와 `withTaskCancellationHandler`를 적용해 즉시 STOP의 진입 경쟁과 취소 전파를 처리한다.
- worker 배포·실행 가능성·서명과 현재 프로토콜의 호환성을 확인한다. 다른 프로세스나 사용자 앱을 변경하지 않는다.

## 검증 완료 기준

1. instantiate와 render가 실제 별도 process에서 수행되는지 확인한다.
2. fake hang/crash/truncated/nonfinite/late 완료와 descriptor/state/frame/result 상한을 검사한다.
3. 취소·deadline·abnormal exit 뒤 child/임시 파일 정리, 다음 요청 재시도와 늦은 결과 미적용을 확인한다.
4. 실제 Apple AU의 기존 offline PCM과 worker PCM을 같은 입력·설정으로 비교하고 허용 오차와 비교 범위를 기록한다.
5. 최종 패키지 worker로 실제 실행·QA 대조를 확인한 범위만 완료로 기록한다. 소스 준비나 fake worker 검사만으로 실제 AU 통과를 선언하지 않는다.

## 제한과 제외 범위

이 worker는 plugin의 crash/hang을 분리하는 process 경계이며 보안 sandbox가 아니다. 임의10분 frame 제한은 호환 회귀 검토에서 제거하고 기존 memory 예산과 맞췄다. 입력 상한이 모든 길이의 render 실행을 허용한다는 의미는 아니다.

물리 출력·가상악기·plugin UI host·실시간·continuous engine은 이번 effect 격리와 별도이며 미해결 조건을 유지한다. Apple AU offline PCM 일치가 실제 장치 출력이나 모든 외부 plugin의 안정성을 보장하지 않는다.

## 최종 검증 근거

- 최종 selected regression46개 실패0·18.491초 (`.build/au-effect-final-tests.log`), 최종46개는 신규18개(protocol10+process8)와 기존28개다.
- Release47.10초 (`.build/au-effect-release-final.log`), 패키지3개 실행 파일 검사 통과 (`.build/au-effect-packaging.log`). helper UUID `0EA9E83A-9DF1-3496-B931-0C021640B7C5`.
- 패키지 실제 Apple AU1개 테스트0.700초 (`.build/au-effect-package-native.log`). default/captured state 두 설정에서 각12000-frame PCM maxError0·RMS error0, peak0.0938143/0.0849933 확인. 두 설정은 테스트2개가 아니며 selected46개와 별도 packaged1개를 합쳐 총47개 테스트다.
- host cancel은 실제 테스트했지만 GUI App 즉시 STOP race는 source guard·compile만 확인했다. 두 범위를 합산하지 않는다.
- 사용자 dist PID86114를 유지했다. 다음 출력 방향은 앱별 장치 선택·prepared PCM 경로이며 정상 physical 출력과 plugin UI/instrument 격리는 별도 미해결 범위다.
