# Contributing · 기여 안내

circlr is an open-source project under the [MIT License](LICENSE). Contributions to code and documentation are submitted under that license. Keep third-party notices and declare the source and license of contributed assets. Demo music has [separate terms](Resources/Demos/DEMO-LICENSE.md).

써클러 코드·문서는 MIT 오픈소스입니다. 기여한 코드·문서에도 같은 라이선스를 적용합니다. 외부 자산은 출처·라이선스를 명시하고 기존 고지를 보존하세요. 데모 음악에는 별도 이용 조건이 적용됩니다.

## Before changing code · 변경 전

- Check the [current plan](docs/releases/0.30.0.md) and [roadmap](docs/releases/roadmap.md). Keep a change scoped to one problem; discuss larger features in an issue first.
- Read [AGENTS.md](AGENTS.md) for repository execution rules. AI coding agents follow the same version, review and verification requirements.
- Keep private music projects, credentials, unapproved samples and generated QA packages out of commits. Reviewed redistributable demo assets with license notices are permitted.

현재 계획·로드맵에서 변경 범위를 확인하고 큰 기능은 먼저 issue로 논의합니다. 에이전트도 같은 버전·검토·검증 기준을 따릅니다. 개인 음악 원본·인증정보·미승인 샘플·QA 앱은 commit하지 않습니다. 출처와 권리를 검토한 재배포 가능 데모 자산은 예외입니다.

## Verify the change · 검증

From the repository root / 저장소 루트에서:

```sh
./scripts/swift-local.sh test --scratch-path .build/integration-tests --filter CirclrCoreTests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_mcp_*.py'
git diff --check
```

These commands cover Core and MCP contracts, not native UI or physical audio. Select affected audio tests after checking whether they touch devices. UI changes require an actual app run; audio changes require appropriate render/device evidence. Use the [release QA procedure](docs/releases/README.md).

위 명령은 Core·MCP 계약을 검사하며 UI·실제 오디오 검증을 대신하지 않습니다. 오디오 테스트의 장치 접근 여부를 먼저 확인하고 변경에 필요한 검사만 실행합니다. 문서만 바뀌면 링크·양쪽 언어의 의미·이미지 표시·diff를 확인하며 앱을 재빌드하지 않습니다.

## Review and documentation · 검토와 문서

Describe the problem, the changed behavior, how it was verified and any remaining limitations. Include reproduction steps, macOS/app version and sanitized logs for a bug. Do not attach private songs or samples to an issue.

Update `README.md` and `README.ko.md` together when public-facing instructions change. Keep their structure, support claims and commands equivalent. Record changes in `CHANGELOG.md`; place detailed build history and QA in `docs/` instead of expanding the README.

문제·변경 동작·검증·남은 제한을 설명합니다. 버그 보고에는 재현 순서·macOS/앱 버전·민감정보를 제거한 로그를 넣습니다. 안내가 바뀌면 한·영 README를 함께 갱신하고 상세 build 이력과 QA는 `docs/`에 둡니다.

Completed versions require an independent review and a GitHub Release. Follow the [publishing procedure](docs/releases/README.md); a documentation commit or an intermediate build is not a release.

완료 버전은 독립 검토와 GitHub Release 등록이 필요합니다. 문서 commit·중간 build는 릴리스로 취급하지 않습니다.
