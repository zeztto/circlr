# 버전별 개발·릴리스 운영

상태: 운영 규약 확정. 시작 기준은 `0.20.0 build152`, 현재 `release/0.30.0`에서 **0.30.0** 후보를 구현·검증 중이다. 출고 여부는 버전 문서의 gate로 판단한다.

## 문서와 버전의 기준

- 현재 버전 계획: [0.30.0 기본 제작 흐름](0.30.0.md).
- 이후 버전 순서: [제품 로드맵](roadmap.md).
- 다음 버전 시작 시 [버전 문서 양식](TEMPLATE.md)을 복사한다.
- build151/152의 과거 구현·QA는 [인수인계](../178-development-handoff.md), [포커스 검증](../179-pedal-focus-mount.md)에 보존한다. 과거 PASS는 새 후보의 QA를 대체하지 않는다.
- 실행 우선순위는 **사용자의 최신 지시 → 이 운영 규약 → 해당 버전 문서 → 기존 상세 설계/이력** 순서로 읽는다. 기존 문서의 ‘다음 작업’은 현행 버전 범위를 자동으로 늘리지 않는다.

제품 버전은 사용자가 요청한 0.1 단계에 맞춰 `0.20.0 → 0.30.0 → 0.40.0`으로 운영한다. 이는 프로젝트의 표기 규약이며 SemVer의 minor 숫자를 소수로 계산하는 규칙이 아니다. 기존 0.20.0을 0.2.0이나 0.3.0으로 낮추지 않는다. 긴급 호환 수정만 `0.30.1`처럼 patch를 올리고 동일 완료 절차를 적용한다.

`CFBundleShortVersionString`은 기능 묶음, `CFBundleVersion`은 QA/패키지 식별용 증가 정수다. build152 이후 새 바이너리 후보는 153 이상을 사용한다. 다른 바이너리에 같은 build를 재사용하지 않는다. 문서만 변경하면 앱 버전/build를 올리지 않는다. 프로젝트 저장 schema와 MCP capability는 각각의 데이터/계약 변경 때만 올린다.

## 한 버전의 상태 전이

| 상태 | 필요한 결과 | 다음 단계 조건 |
|---|---|---|
| PLANNED | 목표, 포함/제외 범위, 작업 ID·의존성·소유 경로, QA 기준, 위험 | 모호한 핵심 계약이 없고 첫 작업을 시작할 수 있음 |
| IN_PROGRESS | 계획 ID별 구현·관련 검증·남은 문제 | 모든 필수 작업 구현, 범위 동결 |
| RC | 버전/build 확정, 동일 후보 패키지, 필수 QA 실행 | 필수 QA PASS, 미실행·실패 없음 |
| IN_REVIEW | 독립 diff·QA 증거·호환·보안 검토, 결함 조치 | 차단 결함 0, 필수 시나리오 전부 충족 |
| APPROVED | README·CHANGELOG·버전 기록·실사용 패키지 안내 완료, 리드 출고 결정 | 최종 commit 및 annotated tag 준비 |
| RELEASED | 승인한 commit/tag를 원격에 push하고 동일 SHA 확인 | 사용자에게 버전·패키지·변경·검증·제한 보고 |

필수 QA 실패/미실행이면 RC 또는 IN_PROGRESS에 머문다. 환경 문제는 해당 gate와 필요한 입력을 기록하고 독립 작업을 진행한다. 완료를 위해 필수 항목을 임의로 선택 사항으로 바꾸지 않는다. 낮은 우선순위의 비차단 제한만 영향·재현·후속 버전을 명시해 수용할 수 있다. ‘한 단계씩’의 종료 단위는 작은 수정이나 build가 아니라 위 절차를 마친 버전이다. 사용자 정지·질문·필수 외부 입력은 중간 중단 사유다.

## 작업과 검토 방식

1. 해당 버전 문서의 작업 ID부터 시작한다. 버전 중 새 기능 제안은 이후 버전 backlog로 보내고 현재 결함인지 먼저 판단한다.
2. 버전 내 독립 모듈이 있을 때만 제한된 수의 에이전트를 병렬 배정한다. 한 파일의 writer는 한 명이며 통합은 리드가 담당한다. 개별 수치 수정마다 팀을 새로 만들지 않는다.
3. 구현 중에는 바뀐 계약의 관련 테스트와 재현 동선을 검사한다. 최종 후보에서는 필수 통합 QA를 한 번 수행하고 실패·추가 변경 영향만 재검증한다.
4. 의미 있는 버전 변경은 구현하지 않은 검토자 한 명 이상이 diff와 완료 증거를 검토한다. 동일한 전체 리뷰를 여러 역할로 복제하지 않는다. 인증·입력·외부 명령을 바꾸면 보안 검토를 포함한다.
5. 최종 검토자는 작업별 완료 증거, 회귀 영향, 원본 보존, 실제 실행 패키지, 남은 결함을 확인한다. 소스 검토만으로 소리/UI 성공을 승인하지 않는다.
6. 검토에서 코드가 바뀌면 관련 테스트·패키지를 갱신하고 영향을 받는 QA와 리뷰를 다시 수행한다. 후보 바이너리 hash/build가 다른 증거를 혼합하지 않는다.

진행 보고는 `버전 / 단계 / 완료한 작업 ID / 차단 요인 / 다음 gate`로 간결하게 한다. 토큰이나 시간 예산은 사용자가 명시한 경우에만 수치로 제한한다. 반복적인 전체 조회·같은 화면 캡처·변경 없는 재빌드·다음 버전 선행 구현은 피한다.

## QA·빌드 명령과 경계

레포 루트에서 실행한다. 아래는 실행 절차이며 이 문서 작성 중 실행한 결과가 아니다.

```sh
# 기계검증: Core 계약과 MCP
./scripts/swift-local.sh test --scratch-path .build/integration-tests --filter CirclrCoreTests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_mcp_*.py'

# 실제 수정에 해당하는 Audio test class는 먼저 I/O 여부를 읽고 버전 문서에 고정한다.
# 최종 패키지: 앱과 5개 helper를 같은 소스에서 빌드하고 kit를 재생성한다.
./scripts/build-app.sh
codesign --verify --deep --strict 'dist/써클러.app'
git diff --check
```

- `scripts/verify.sh`는 전체 Swift test와 빌드/패키징을 실행한다. Python MCP·native UI·실제 오디오 검증을 포함하지 않으며 I/O 없는 검사로 가정하지 않는다. 실제 테스트 목록을 검토한 뒤 사용한다.
- `build-app.sh`는 아이콘·Resources/Codex를 생성하고 **현재 checkout의 dist 앱을 교체/보관**한다. 사용자 실행 앱 경로와 같으면 먼저 저장·종료·백업/출고 경계를 해결한다. 다른 checkout의 설치 앱을 임의로 교체하지 않는다.
- 앱과 모든 helper를 함께 빌드한다. 앱 바이너리만 새로 만든 뒤 이전 helper를 결합한 패키지를 최종 후보로 승인하지 않는다.
- `build-agent-kit.py`는 Info.plist 버전과 MCP 소스를 반영한다. 버전 변경 후 생성한 `Resources/Codex/manifest.json` 및 실제 변경된 kit 파일을 검토·commit한다.
- ad-hoc codesign 성공은 notarization 또는 일반 사용자 배포 인증이 아니다. 로컬 비공개 출고와 향후 public 배포 조건을 구분한다.
- I/O 차단 QA 앱은 UI 검증용이다. 실제 재생·녹음·청취 gate에는 실제 helper를 가진 후보가 필요하다. 기존 물리 I/O 정지 경계는 자동 해제하지 않는다.

## Git·문서·배포 완료 절차

현재 `codex/daw-integration`의 검증된 HEAD가 첫 기준이다. 다음 구현 시작 때 이 HEAD에서 `release/0.30.0`을 만들고, 이후에는 직전 릴리스 tag에서 `release/<version>`을 만든다. 기존 커밋·브랜치를 재작성하지 않는다. 버전 중간에는 복구용 로컬 commit 또는 필요시 private WIP push가 가능하지만 릴리스로 세지 않는다.

최종 순서는 **구현 → QA → 독립 검토/수정 → 문서 → 최종 commit → tag → push → 원격 확인**이다.

1. README 상단에 현재 승인 버전과 시작 문서, CHANGELOG에 버전 단위 변경·호환·제한을 기록한다. build별 상세 이력은 참고 문서로 유지한다.
2. 버전 문서에 필수 작업/QA PASS, 검토자·지적/조치, 후보 build·SHA256·앱 위치, 이전 앱/프로젝트 복구 방법, 알려진 제한을 채운다. 로컬 절대 경로는 기계별 값이므로 레포에는 상대 경로·재현 명령을 우선 기록한다.
3. `git status`와 staged diff를 검토해 소스·문서·테스트·허용된 생성물만 포함한다. 음악 원본·라이선스 샘플·QA 앱·로컬 설정·인증정보는 올리지 않는다.
4. 최종 commit에 승인본을 포함하고 `v0.30.0` annotated tag를 붙인다. 문서의 승인은 출고 판단이며 실제 RELEASED 여부는 원격 branch/tag 확인으로 판정한다. commit 자신의 SHA를 본문에 넣으려고 추가 commit을 반복하지 않는다.
5. 명시적 branch/tag만 한 번에 push한다. 기존 tag는 이동/삭제하지 않는다. 새 버전 예시:

```sh
git tag -a v0.30.0 -m 'circlr 0.30.0: approved release'
git push --atomic origin HEAD:refs/heads/release/0.30.0 refs/tags/v0.30.0
git rev-parse HEAD
git ls-remote origin refs/heads/release/0.30.0 'refs/tags/v0.30.0^{}'
git status --short
```

annotated tag의 원격 `^{}` 결과와 branch가 승인한 로컬 HEAD와 같아야 한다. 거절/실패 시 RELEASED로 보고하지 않고 오류를 해결한다. main/default branch 병합과 public GitHub Release 게시를 암묵적으로 수행하지 않는다.

6. 최종 안내에는 실제 사용 가능한 패키지 경로·버전·핵심 변화·QA·남은 제한·commit/tag를 제공한다. 실제 사용자 앱을 교체했는지 명시한다. 패키지를 만들지 않았으면 소스만 전달한 것으로 표시하고 사용자 출고 gate를 충족했다고 하지 않는다.

실행 앱 교체 후 문제가 있으면 보관한 이전 앱과 **이전 schema의 프로젝트 백업**으로 복구한다. 새 schema 프로젝트를 구버전 앱에 그대로 덮어 열지 않는다. 이미 공개된 tag는 유지하고 수정 버전을 새로 만든다.
