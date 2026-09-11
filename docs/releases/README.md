# 버전별 개발·릴리스 운영

상태: 운영 규약 확정. 시작 기준은 `0.20.0 build152`, 현재 후보는 **0.50.1 build169**이며 `v0.50.1` 게시 대기다. 직전 정식 출고는 0.50.0 build166이다. 출고 여부는 버전 문서의 gate로 판단한다.

## 문서와 버전의 기준

- 현재 버전 계획: [0.50.1 자동 정렬](0.50.1.md). [한영 노트](0.50.1-notes.md) · [QA](0.50.1-qa.md).
- 이후 버전 순서: [제품 로드맵](roadmap.md).
- 다음 버전 시작 시 [버전 문서 양식](TEMPLATE.md)을 복사한다. 출고할 때 [한·영 릴리스 노트 양식](RELEASE_NOTES_TEMPLATE.md)을 `<version>-notes.md`로 작성한다.
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
| RELEASED | 원격 branch/tag SHA 일치, GitHub Release 게시, 한·영 노트 및 검증된 패키지·SHA256 등록 | release URL·draft/prerelease·첨부 자산 확인 후 사용자 안내 |

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
- 현재 공개 패키지는 ad-hoc 서명이며 Apple notarization을 받지 않았다. codesign 검증 성공은 Apple 배포 인증을 뜻하지 않는다. 릴리스 노트에는 [macOS 설치·첫 실행 안내](../install-macos.md)를 연결해 Gatekeeper의 ‘그래도 열기’ 절차를 제공한다. Developer ID 서명·notarization·stapling 도입 전까지 이 상태를 명시한다.
- I/O 차단 QA 앱은 UI 검증용이다. 실제 재생·녹음·청취 gate에는 실제 helper를 가진 후보가 필요하다. 기존 물리 I/O 정지 경계는 자동 해제하지 않는다.

## Git·문서·배포 완료 절차

현재 `codex/daw-integration`의 검증된 HEAD가 첫 기준이다. 다음 구현 시작 때 이 HEAD에서 `release/0.30.0`을 만들고, 이후에는 직전 릴리스 tag에서 `release/<version>`을 만든다. 기존 커밋·브랜치를 재작성하지 않는다. 버전 중간에는 복구용 로컬 commit 또는 필요시 개발 브랜치 checkpoint push가 가능하지만 릴리스로 세지 않는다.

최종 순서는 **구현 → QA → 독립 검토/수정 → 문서 → 최종 commit → tag → push → GitHub Release 등록 → 원격 검증**이다. 사용자 요청에 따라 앞으로 완료하는 모든 제품 버전(patch 포함)에 GitHub Release를 등록한다. 문서 수정이나 미완료 후보 build는 새 제품 릴리스가 아니다.

1. 한국어·영어 README와 CHANGELOG에 승인 버전의 변화·호환·제한을 반영한다. `<version>-notes.md`에 두 언어로 설치, 변경, QA, 알려진 제한, 복구 방법을 작성한다. 자동 생성 commit 목록만을 릴리스 설명으로 사용하지 않는다.
2. 버전 문서에 필수 작업/QA PASS, 검토자·조치, 후보 build·SHA256·앱 위치, 이전 앱/프로젝트 복구 방법을 채운다. 동일 승인 후보의 앱과 5개 helper·Codex kit를 검증하고, 배포 패키지 내용에 음악 원본·Splice 등 재배포 불가 샘플·QA 프로젝트·인증정보·로컬 설정이 없는지 확인한다. 소스 공개나 저장소 공개 전환은 별도 작업이다.
3. staged diff에 소스·문서·테스트·허용된 생성물만 포함해 최종 commit한다. 패키지가 이 commit의 소스에 대응하는지 확인한다. 소스나 생성물이 바뀌었다면 재빌드하고 영향받는 QA부터 다시 수행한다. 승인 commit에서 annotated tag를 만들고 명시적 branch/tag만 push한다. 기존 tag를 이동/삭제하지 않는다.
4. 검증된 앱을 ZIP으로 패키징하고 SHA256 파일을 만든다. 압축을 별도 임시 폴더에 풀어 버전/build, 서명, 모든 helper, kit 및 앱 시작을 확인한다. 아래 명령은 **출고 승인 이후**의 예시이며 현재 0.30.0 실행 지시가 아니다. `dist/써클러.app`은 검증된 승인 후보여야 한다.

```sh
release_version=0.30.0
release_tag="v$release_version"
release_asset="dist/circlr-$release_version-macos.zip"
release_notes="docs/releases/$release_version-notes.md"
release_commit=$(git rev-parse HEAD)

git status --short                         # 작업 트리가 깨끗한지 확인
codesign --verify --deep --strict 'dist/써클러.app'
ditto -c -k --sequesterRsrc --keepParent 'dist/써클러.app' "$release_asset"
(cd dist && shasum -a 256 "circlr-$release_version-macos.zip" > SHA256SUMS)
# 압축 해제 후 동일 후보의 버전/서명/시작 검증을 마친 뒤 진행
git tag -a "$release_tag" -m "circlr $release_version: approved release"
git push --atomic origin "HEAD:refs/heads/release/$release_version" "refs/tags/$release_tag"
git ls-remote origin "refs/heads/release/$release_version" "refs/tags/$release_tag^{}"
```

두 원격 SHA가 `$release_commit`과 일치해야 한다. 실패하면 등록을 멈추고 원인을 해결한다. 노트에는 최종 SHA를 넣을 수 있지만, commit 자신의 SHA를 기록하려고 추가 commit을 반복하지 않는다. 출고 기록은 tag와 Release URL로 연결한다.

5. GitHub Release를 같은 tag로 등록한다. 명시적으로 승인된 완료 버전은 **정식 release**로 등록한다. v0.30.0부터 사용자 요청으로 적용하며, 평가 후보만 prerelease로 구분한다. prerelease도 필수 QA를 생략하는 수단이 아니다. 이미 존재하는 Release는 먼저 조회하고 중복 생성하거나 검증된 자산을 임의로 덮어쓰지 않는다. 현재 저장소는 공개 MIT 프로젝트이며 데모 별도 권리를 보존한다.

```sh
gh release create "$release_tag" --repo zeztto/circlr --verify-tag \
  --title "circlr $release_version" --notes-file "$release_notes" \
  --latest "$release_asset" dist/SHA256SUMS

gh release view "$release_tag" --repo zeztto/circlr \
  --json url,tagName,isDraft,isPrerelease,assets,body
release_download=$(mktemp -d)
gh release download "$release_tag" --repo zeztto/circlr \
  --dir "$release_download" --pattern "circlr-$release_version-macos.zip" --pattern SHA256SUMS
(cd "$release_download" && shasum -a 256 -c SHA256SUMS)
shasum -a 256 "$release_asset" "$release_download/circlr-$release_version-macos.zip"
```

6. **RELEASED gate:** 원격 peeled tag/branch가 승인 commit과 일치하고, Release URL이 조회되며 `isDraft=false`, `isPrerelease`가 승인 계획과 일치해야 한다. 한·영 노트와 예상 ZIP·SHA256SUMS가 있고, 내려받은 ZIP의 SHA256이 로컬 승인 ZIP 및 첨부 checksum과 모두 같아야 한다. 하나라도 실패하면 버전 완료로 보고하지 않는다. draft 생성이나 tag push만으로 이 gate를 충족하지 않는다.
7. 최종 안내에 Release URL, 버전/build, 패키지, 주요 변화, QA와 제한, commit/tag를 제공한다. 실제 사용자 앱 교체 여부를 명시한다. 저장소가 private이면 링크 접근에는 저장소 권한이 필요하다. default branch 병합·저장소 public 전환·사용자 앱 교체는 Release 등록과 별도다.

실행 앱 교체 후 문제가 있으면 보관한 이전 앱과 **이전 schema의 프로젝트 백업**으로 복구한다. 새 schema 프로젝트를 구버전 앱에 그대로 덮어 열지 않는다. 이미 공개된 tag는 유지하고 수정 버전을 새로 만든다.

## 현재 후보의 명시적 preview 배포

사용자가 현재 후보의 등록을 명시적으로 요청한 경우, 완료 버전과 별도로 `v<version>-preview.N`을 사용한다. 현재 적용은 `v0.30.0-preview.1`이다. `main`에 통합한 commit을 가리키는 annotated tag로 만들고 `--prerelease --latest=false`로 실제 게시한다. 앱 내부 버전은 0.30.0/build158이며 태그와 노트에 preview 배포 상태를 명시한다.

이 경우 상태는 **PREVIEW_PUBLISHED**로 기록하고 0.30.0 마일스톤은 **IN_PROGRESS**를 유지한다. 필수 QA 미완료를 없애거나 정식 `v0.30.0` 태그를 발행하지 않는다. 소스 대응·bundle 내용·서명·압축 복원·한영 노트·원격 SHA·다운로드 checksum 검증은 수행한다. 실제 장치/전체 native 검증의 미완료 범위를 노트에 적는다.

브랜치 역할: `main`은 통합 소스, `release/0.30.0`은 아직 미완료인 버전의 후속 안정화 작업용이다. 기존 `codex/*` 브랜치는 통합 이력을 보존하며, 다른 worktree에서 사용 중인 브랜치를 일괄 삭제하지 않는다. preview tag는 이동하거나 덮어쓰지 않는다.

2026-09-11 v0.30.0 예외: 사용자가 한글 IME와 남은 native QA를 명시적으로 유예했다. 이 버전은 승인된 유예 기록과 함께 정식 게시하며, 유예를 PASS로 바꾸지 않는다. 이후 버전에 유예가 자동 승계되지는 않는다.
