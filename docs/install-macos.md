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

0.80 개발 빌드에서 곡을 열 때는 `.circlr` **폴더 자체를 선택**하세요. `manifest.json`을 골랐다면 앱이 같은 곡 폴더를 한 번 더 선택하도록 안내합니다. macOS는 파일 선택만으로 옆의 오디오·MIDI 파일까지 접근을 허용하지 않을 수 있습니다. 다른 폴더를 고르거나 취소하면 현재 곡은 유지됩니다. [Apple의 Documents 접근 설명](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription).

### 오디오 장치에서 소리가 나지 않을 때

앱의 **출력 설정**에서 Mac 내장 스피커 또는 다른 지원 장치를 명시적으로 선택하고 다시 재생해 보세요. 이 선택은 circlr에만 적용되며 macOS의 기본 출력은 바꾸지 않습니다. 오래된 Scarlett 등 외부 인터페이스는 세대·macOS 버전에 따라 지원 범위가 다르므로 [Focusrite의 macOS 호환성 안내](https://support.focusrite.com/hc/en-gb/articles/12033372452754-Focusrite-Compatibility-on-macOS)에서 정확한 세대를 확인하세요. 장치 초기화가 실패하면 circlr는 재시도를 안내하며, 해당 장치의 실제 청취 품질은 별도로 확인해야 합니다.

2026-09-24 기준 Focusrite는 macOS 26에서 **Scarlett 6i6 1세대의 오디오 전송은 가능하지만 Scarlett Mix Control은 작동하지 않는다**고 안내하고, **6i6 2세대는 지원 대상**으로 표시합니다. macOS 장치 목록의 `Scarlett 6i6 USB`라는 이름만으로 세대를 확인할 수 없습니다. [Focusrite의 세대 확인 안내](https://support.focusrite.com/hc/en-gb/articles/208295789-Which-generation-of-Scarlett-do-I-have)에 따라 기기 밑면의 시리얼 접두 문자를 확인하세요. circlr의 출시 QA는 외부 장치가 연결되어 있어도 앱 안에서 Mac 내장 출력을 선택해 수행하며, Scarlett 호환성은 정확한 세대와 실제 입출력을 확인하는 별도 검사로 기록합니다.

현재 오디오 **녹음 입력**은 macOS의 기본 입력을 사용합니다. 기본 Scarlett에서 녹음 준비가 멈추면 사용자가 **시스템 설정 → 사운드 → 입력**에서 다른 지원 입력 장치(있는 경우 내장 마이크 포함)를 직접 선택해 다시 시도할 수 있습니다. circlr가 macOS 기본 입력을 자동 변경하지는 않습니다. 앱 전용 입력 장치 선택과 실제 take 검증은 [0.90 계획의 R90-07](releases/0.90.0.md)에 남아 있으며, 현재 기능으로 안내하지 않습니다.

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

In 0.80 development builds, select the **`.circlr` folder itself** when opening a song. If you select `manifest.json`, the app asks you to select the same song folder once more. macOS may grant access to the selected file without granting access to neighboring audio and MIDI files. Choosing another folder or canceling leaves the current song unchanged. [Apple's Documents access guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription).

### If audio does not start on an external interface

Choose the Mac's built-in speakers or another supported device explicitly in circlr's **Output settings**, then retry playback. This selection affects circlr only; it does not change the macOS system default. Older Scarlett interfaces have different support by generation and macOS version, so check the exact model against [Focusrite's macOS compatibility guidance](https://support.focusrite.com/hc/en-gb/articles/12033372452754-Focusrite-Compatibility-on-macOS). circlr reports device initialization failures and allows a retry; audible output on a particular interface still needs its own check.

As of 2026-09-24, Focusrite lists the **1st Gen Scarlett 6i6 as passing audio on macOS 26 while Scarlett Mix Control does not work**, and lists the **2nd Gen 6i6 as supported**. The device name `Scarlett 6i6 USB` in macOS does not establish its generation. Check the serial prefix on the underside using [Focusrite's generation guide](https://support.focusrite.com/hc/en-gb/articles/208295789-Which-generation-of-Scarlett-do-I-have). circlr release QA selects Mac built-in output in the app even when an external device is connected; compatibility with a Scarlett requires a separate check of its exact generation and physical input/output.

Audio **recording input** currently uses the macOS default input. If preparation stalls with the Scarlett as default, you can manually select another supported input device (including a built-in microphone where available) in **System Settings → Sound → Input** and retry. circlr does not change the system default for you. App-specific input selection and a verified take remain in [R90-07 of the 0.90 plan](releases/0.90.0.md); they are not a current product feature.
