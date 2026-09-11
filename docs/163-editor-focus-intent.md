# 편집 포커스 요청의 우선순위

상태: build141 최종 후보의 요청 통합·빠른 전환·창 활성화 검증을 수행했다. 최종 native/state·package 독립 감사도 모두 PASS했다. 기준 HEAD는 `bfe0e3a`이며 build140의 빠른 전환 경쟁을 우선 해결한다. 아래 실제 검증 범위를 전체 timing 조합의 완료로 확대하지 않는다. 전체 DAW 목표는 유지한다.

## 재현과 수정 방향

build140의 `editorfocus140-verified/rapid-sequence-point`에서 빠른 Command+2→Command+5→Option+Command+0→Return 입력은 늦은 native attach 콜백이 명시적인 canvas focus를 덮어 r169에 automation 점을 추가했다. 안정된 outer focus를 확인한 뒤 Enter는 r170 음악을 보존하며 plot으로 진입했다. 두 증거를 모든 속도의 성공으로 합치지 않는다.

여섯 편집 view의 자동 attach와 mode entry를 공통 요청 체계로 통합한다. 마지막 사용자 의도와 현재 target·mode에 맞는 요청만 적용하며, 앞선 attach의 지연 콜백은 이후의 명시적 canvas 또는 입력 focus를 덮지 않아야 한다. mode entry 요청을 먼저 연결한 뒤 기존 자동 attach 경로를 제거해 첫 진입 기능을 잃지 않는다.

## 완료 기준

- 동일한 빠른 Command+2→Command+5→Option+Command+0→Return 후 음악 revision·automation 점 개수는 불변이며 실제 plot focus를 확인한다. 캡처 순서와 입력 속도·대상을 기록한다.
- 새 수치·이름·검색·console 입력에 들어간 뒤 오래된 attach가 focus를 빼앗지 않는지 검사한다. 같은 field editor 재사용에서도 현재 owner와 입력 보호를 유지한다.
- 각 mode 첫 진입과 재사용 host, 저장된 view의 앱 재시작 자동 진입을 회귀 확인한다. 자동 attach 제거만으로 첫 키 입력이 사라지지 않아야 한다.
- invalid draft·Escape·Tab·섹션 왕복과 기존 음악/자산 보존을 확인한다. source-only와 native 실행 범위를 구분한다.

패키지·앱·native 실행은 root 단일 writer가 QA 사본에서 수행한다. 문서와 구현의 소유 범위를 지키고 다른 작업자의 변경을 보존한다. 실제 I/O·청취·모든 접근성 조합을 이 수정의 성공으로 계산하지 않는다. 기존 build140은 알려진 경쟁이 있는 부분 개선 기록으로 유지하고 새 결과는 실제 검증 후 추가한다.

## 최종 후보 결과

`editorfocus141-final` Release는 48.10초·warning 0개로 통과했다 (`.build/build141-key-ready-release.log`). 관련 테스트 39개·실패 0개를 확인했다 (`.build/build141-key-ready-tests.log`). package.json의 UUID는 `0FF8637F-FA1E-35FA-B8EF-E1D616F6DE67`이며 package 감사도 PASS했다. 전체 816개 회귀를 이번에 재실행하지 않았다.

초기 두 후보에서 저장 view의 첫 focus 복귀가 실패했다. 계측 결과 keyWindow가 nil인 동안 요청을 폐기하는 경계를 확인했다. 최종 후보는 해당 window의 didBecomeKey에서 기존 UUID 요청을 재시도하며 진단 코드는 제거했다. 백그라운드로 처음 열린 창의 outer focus는 활성화 전 정상 pending으로 구분하고, 실제 titlebar 활성화 후 plot focus와 Tab의 console 이동을 확인했다.

native에서는 서로 다른 두 출발 상태의 빠른 Command+2→Command+5→Option+Command+0→Return 후 r170·점 0개를 유지했다. piano Tab, step 1→2→3·Enter, pitch raw 2 draft/Escape, invalid 16384·빈 이름 차단, 섹션 설정 복귀, audio Tab raw 2·Enter 후 Tab raw 3/Escape, pan picker focus와 console `focus141x` 입력을 확인했다. 재시작의 전체 hierarchyView도 정확히 일치했다. 최종 독립 data 감사는 캡처 7개의 음악 r170·자산 6개가 baseline과 같음을 확인했다. native 감사는 AX/JPEG 31쌍과 두 rapid의 점 0개를 확인했다. 재시작 전후 전체 manifest·hierarchyView·runtime도 정확히 같았으며 package 감사도 PASS했다. 모든 QA 앱을 종료하고 사용자 production PID 86114를 보존했다.

명시적 create/import/return 진입 연결은 소스 검토 범위이며 모든 해당 경로를 이번 native로 실행했다고 주장하지 않는다. 물리 I/O·청취·모든 timing 조합도 미검증이다. 다음은 현재 개발 계획의 한 곡 연속 동선을 따라 편집·파일 작업·섹션 전환을 함께 수행하며 남은 입력 보호와 작은 화면 가시성 문제를 구체적으로 확인한다.
