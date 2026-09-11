# macOS 설치 · macOS installation

[한국어](#한국어) · [English](#english)

## 한국어

현재 circlr macOS 패키지는 **ad-hoc 서명**이며 **Apple 공증(notarization)을 받지 않았습니다**. 첫 실행에서 개발자를 확인할 수 없거나 악성 소프트웨어 여부를 확인할 수 없다는 경고가 나타날 수 있습니다. 패키징 상태는 [패키징 스크립트](../scripts/package-app.py)와 [릴리스 절차](releases/README.md)에 기록되어 있습니다.

### 다운로드·설치

1. [공식 GitHub Releases](https://github.com/zeztto/circlr/releases)에서 원하는 버전의 `circlr-<version>-build<build>-macos-arm64.zip`과 같은 릴리스의 `SHA256SUMS`를 내려받습니다. macOS 14 이상, Apple Silicon용입니다.
2. 두 파일을 같은 폴더에 두고 Terminal에서 그 폴더로 이동한 뒤 `shasum -a 256 -c SHA256SUMS`를 실행합니다. 다운로드한 ZIP의 결과가 `OK`인지 확인합니다. 일치하지 않으면 실행하지 말고 공식 릴리스에서 다시 내려받습니다. 체크섬은 게시된 파일과의 일치 확인이며 Apple의 공증을 대신하지 않습니다.
3. ZIP을 풀고 `써클러.app`을 **응용 프로그램** 폴더로 옮깁니다.

### 첫 실행이 차단될 때

출처와 파일을 확인하고 앱을 신뢰하는 경우에만 다음 절차를 진행합니다. [Apple 공식 안내: Mac에서 앱 안전하게 열기](https://support.apple.com/ko-kr/102445).

1. Finder에서 `써클러.app`을 두 번 클릭해 실행을 시도합니다.
2. 차단 안내를 닫고 **Apple 메뉴 → 시스템 설정 → 개인정보 보호 및 보안**을 엽니다.
3. 아래로 스크롤해 써클러 차단 항목의 **그래도 열기**를 누릅니다.
4. 다시 나타나는 경고에서 **열기**를 선택하고, 요청되면 Mac 로그인 암호 또는 Touch ID로 인증합니다. 이후에는 같은 앱을 두 번 클릭해 실행할 수 있습니다.

버튼이 보이지 않으면 앱 실행을 다시 시도한 뒤 설정을 확인하세요. 조직에서 관리하는 Mac은 관리자에게 문의하세요. **앱이 손상되었거나 컴퓨터를 손상시킨다는 경고**는 위 절차로 처리하지 말고 다운로드와 체크섬을 재확인한 뒤 [이슈](https://github.com/zeztto/circlr/issues)에 버전·macOS 버전·경고 내용을 남겨주세요. 경고 종류는 [Apple 공식 안내](https://support.apple.com/ko-kr/102445)를 참고하세요.

## English

Current circlr macOS packages are **ad-hoc signed** and **not notarized by Apple**. macOS may report that it cannot verify the developer or check the app for malicious software on first launch. See the [packaging script](../scripts/package-app.py) and [release procedure](releases/README.md) for the packaging state.

### Download and install

1. Download `circlr-<version>-build<build>-macos-arm64.zip` and `SHA256SUMS` from the same version on [official GitHub Releases](https://github.com/zeztto/circlr/releases). The app targets Apple Silicon and macOS 14 or later.
2. Put both files in one folder, open Terminal in that folder, and run `shasum -a 256 -c SHA256SUMS`. Confirm the downloaded ZIP reports `OK`. If it does not match, download it again from the official release before opening it. A checksum confirms a match with the published file; it does not replace Apple notarization.
3. Extract the ZIP and move `써클러.app` to **Applications**.

### If macOS blocks the first launch

Proceed only after checking the source and file and deciding you trust the app. [Apple’s official instructions: Safely open apps on your Mac](https://support.apple.com/en-us/102445).

1. Double-click `써클러.app` in Finder to attempt a launch.
2. Dismiss the blocked-app alert and open **Apple menu → System Settings → Privacy & Security**.
3. Scroll to the circlr blocked-app entry and choose **Open Anyway**.
4. Choose **Open** in the next alert and authenticate with your Mac login password or Touch ID if prompted. Subsequent launches of the same app can use a normal double-click.

If the button is missing, attempt a launch again and check Settings. For a managed Mac, contact your administrator. If the alert says the app **is damaged or will damage your computer**, recheck the download and checksum and [report an issue](https://github.com/zeztto/circlr/issues) with the app version, macOS version and alert text instead of following the steps above. See [Apple’s alert descriptions](https://support.apple.com/en-us/102445).
