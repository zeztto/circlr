# <version> — <사용자가 얻을 결과>

상태: PLANNED / IN_PROGRESS / RC / IN_REVIEW / APPROVED.
기준 commit/tag:
구현 브랜치: release/<version>
목표 앱 버전 / 후보 build:

## 목표와 계약

- 한 버전이 제공하는 완결된 사용자 작업:
- 포함 범위:
- 이후 버전으로 남길 범위:
- 기존 데이터·UI·API 불변 조건:
- 이전 버전 의존성과 착수 조건:

## 작업 계획

| ID | 작업 | 담당 역할·소유 파일 | 의존 | 완료 조건 | TODO/DOING/DONE |
|---|---|---|---|---|---|

## 필수 QA

| ID | 시나리오·환경 | 예상 결과 | build/후보 SHA·명령 | 실제 결과·증거 | NOT_RUN/PASS/FAIL |
|---|---|---|---|---|---|

필수 여부는 계획 때 고정한다. 소스·fixture/CPU·native UI·실제 오디오·패키지 검증을 구분한다. 테스트 필터의 실제 존재/I/O 여부를 착수 때 확인한다. 과거 버전 결과를 새 결과로 복사하지 않는다.

## 결함과 범위 변경

| ID | 재현·영향 | 차단 여부 | 수정/수용 근거 | 재검사·후속 버전 |
|---|---|---|---|---|

## 독립 검토

- 검토자와 검토 범위:
- 지적/수정/재검사:
- 필수 QA 미실행 0 및 차단 결함 0 확인:

## 문서·패키지·출고

- README/CHANGELOG 갱신:
- 저장 schema·MCP capability·구버전 프로젝트 호환:
- 실제 패키지 상대 경로·버전/build·SHA256:
- 앱과 모든 helper·Codex kit 동일 후보 확인:
- 설치 대상 및 기존 앱·프로젝트 백업/복구:
- 알려진 비차단 제한:
- 리드 결정 APPROVED 또는 보류 사유:
- 태그: v<version>
- 한·영 릴리스 노트: `<version>-notes.md` ([양식](RELEASE_NOTES_TEMPLATE.md))
- 배포 ZIP·SHA256SUMS·재배포 가능 자산 확인:
- GitHub Release URL / isDraft / isPrerelease:
- 원격 branch·peeled tag의 승인 commit 일치:
- 내려받은 패키지와 로컬 승인 패키지의 SHA256 일치:

실제 RELEASED는 원격 branch와 annotated tag의 peeled SHA가 승인 commit과 일치하고, GitHub Release 게시·한영 노트·패키지·checksum 및 원격 상태 검증까지 통과했을 때만 판정한다. 문서 승인 상태만으로 push나 설치가 완료됐다고 보고하지 않는다. [공통 종료 절차](README.md)를 따른다.
