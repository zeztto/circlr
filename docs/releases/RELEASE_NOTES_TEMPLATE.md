# circlr <version>

<!-- 출고 때 <version>-notes.md로 복사하고 모든 안내/빈칸을 실제 결과로 바꾼다.
     필수 QA가 남아 있으면 게시하지 않는다. 한국어·영어 내용은 같은 범위를 설명한다. -->

## 한국어

<이번 버전에서 사용자가 완료할 수 있는 작업을 한 문장으로 설명한다.>

### 주요 변경

- <사용자에게 보이는 변화와 필요한 조작>

### 설치 및 호환

- 패키지: `circlr-<version>-build<build>-macos-arm64.zip`, build `<build>`
- 지원 환경: <검증한 macOS 및 CPU architecture>
- 배포 상태: <prerelease 또는 stable; 코드 서명·notarization 상태>
- 프로젝트 호환: <schema, 구버전 프로젝트 처리, migration 여부>
- 설치: <압축 해제·실행 절차 및 실제 필요한 안내>. [macOS 설치·보안 경고 안내](https://github.com/zeztto/circlr/blob/main/docs/install-macos.md#한국어).
- 무결성: ZIP과 `SHA256SUMS`를 같은 폴더에 내려받아 `shasum -a 256 -c SHA256SUMS`를 실행한다.

### 검증 및 알려진 제한

- 검증: <자동 테스트·실제 UI/오디오·패키지의 실행 범위>
- 비차단 제한: <증상·영향·우회·후속 버전, 없으면 없음>
- 복구: <이전 앱과 프로젝트 백업을 함께 복원하는 절차>

## English

<One sentence describing the user workflow this release completes.>

### Changes

- <User-visible change and relevant action>

### Installation and compatibility

- Package: `circlr-<version>-build<build>-macos-arm64.zip`, build `<build>`
- Supported environment: <verified macOS and CPU architecture>
- Distribution: <prerelease or stable; code signing and notarization status>
- Project compatibility: <schema, older projects, and migration behavior>
- Installation: <extraction and launch instructions>. [macOS installation and security alerts](https://github.com/zeztto/circlr/blob/main/docs/install-macos.md#english).
- Integrity: Download the ZIP and `SHA256SUMS` into one directory, then run `shasum -a 256 -c SHA256SUMS`.

### Verification and known limitations

- Verified: <automated tests, native UI/audio, and package coverage>
- Non-blocking limitations: <symptom, impact, workaround, follow-up version, or None>
- Recovery: <restore the previous app together with a compatible project backup>

## References / 참고

- Tag: `v<version>`
- Version plan / 버전 계획: <link to the version document at the release tag>
- QA evidence / 검증 기록: <link to the sanitized QA record at the release tag>
- Changelog / 변경 이력: <link to CHANGELOG at the release tag>
