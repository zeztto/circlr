# Screenshots · 실행 화면

## 0.70.0 build180

Frames extracted at 8 seconds from two actual build180 native-app MP4 recordings of the bundled f0r h3r song with song-level playback follow. The files show the **canvas**, not the app chrome or a simulated interface. JPEG encoding was applied once to the decoded frame; no layout or visual element was composited. The source recordings stay in the local ignored `.build/` QA directory and are not redistributed with the app. These frames document landscape/portrait orbital song form and playback graphics, not compositor FPS or physical listening.

동봉 f0r h3r를 실제 build180 앱에서 곡 단위 팔로우로 재생·녹화한 MP4의 8초 프레임입니다. **캔버스만** 담겨 있고 메인 컨트롤바는 보이지 않습니다. 디코딩 프레임을 JPEG로 한 번 인코딩했으며 화면 요소를 합성하지 않았습니다. 원본 MP4는 Git 제외 로컬 `.build/` QA 자료입니다. 가로·세로 궤도 화면의 증거이며 실제 표시 FPS·청취 성공을 의미하지 않습니다.

| File | Source MP4 | JPEG pixels | SHA256 |
|---|---|---:|---|
| `circlr-song-build180.jpg` | `r70-build180-song-overview.mp4` | 1912×1080 | `949b98a2ed6613cd625e5436ec675e65173a079f55f770d55b5a4f2b9141caba` |
| `circlr-song-portrait-build180.jpg` | `r70-build180-song-portrait.mp4` | 670×1080 | `ba25c232ace9f365ae007b63878a163f4cff47153c8cbb5e26bd25387268cf5a` |

## 0.60.0 build170

Actual isolated native app with the bundled v6 demo: radial song layout, factory EP search and the chorus filter curve. Original CUA JPEG bytes, no image editing. UI is Korean. The portrait-shaped window uses the left half of the current display; a700-pixel-wide window was not rechecked this version.

별도 검증 앱의 실제 v6 화면입니다. 가로 전체 창과 현재 디스플레이 왼쪽 절반의 세로 비율 창을 촬영했습니다. 원본 JPEG를 변경 없이 저장했으며700폭 재검증이나 물리 장치 청취의 증거로 사용하지 않습니다.

| File | Window / JPEG pixels | SHA256 |
|---|---|---|
| `circlr-song-build170.jpg` | 2560×1355 / 1451×768 | `87fb6f9ab47c6aba5691d9ca98ce3493a146318df54251274c5888202059e0d4` |
| `circlr-presets-build170.jpg` | 1281×1355 / 768×813 | `2b3f5d0e4d8b49a8ab6d5a4f4f5d90598cea0fd680b7d2912dfe0f95285af9e5` |
| `circlr-automation-build170.jpg` | 1281×1355 / 768×813 | `a617fec6812459464653d150fca919bd4473553e67b2f3275e86153c9b7cbffd` |


## 0.50.1 build169

Actual native app showing the bundled f0r h3r project after automatic layout. The hero shows the song’s radial layout; portrait captures show horizontal signal flow and radial section layout. The UI is Korean. These images document layout, not audio playback. JPEG files are copied byte-for-byte from `qa/generated/outward-orbit/build169/`; the landscape capture was delivered at reduced pixel dimensions.

자동 정렬한 동봉 f0r h3r 프로젝트의 실제 앱 화면입니다. 대표 이미지는 곡의 방사형 배치, 세로 이미지는 섹션의 가로 신호 흐름·방사형 배치를 보여줍니다. 화면 배치 증거이며 오디오 재생 검증은 아닙니다. JPEG는 원본 바이트 그대로 복사했으며 가로 캡처는 창 크기보다 작은 픽셀 크기로 제공되었습니다.

| File | Source | Window | JPEG pixels | SHA256 |
|---|---|---|---|---|
| `circlr-song-build169.jpg` | `landscape-song-radial.jpg` | 2560×1355 | 1451×768 | `fcc3991bef3260ad3efa7ecc58221633044e3afb37923234c309b749ecd9f76f` |
| `circlr-horizontal-build169.jpg` | `portrait-horizontal.jpg` | 700×1000 | 700×1000 | `632fcd16a202181058a99d07e44c2089b8e04f2f3a193031d026f9b8117a6351` |
| `circlr-radial-build169.jpg` | `portrait-radial.jpg` | 700×1000 | 700×1000 | `3775a690a959366c4df7a2c84dda8fda65b9d70f672d71c051b06a5481989ee7` |

## 0.50.0 build166

Actual native QA app showing the bundled f0r h3r project. The portrait capture includes a long title used to check truncation. These screenshots document layout, not audio playback. JPEG files are copied unchanged from `qa/generated/outward-orbit/build166/`.

동봉 f0r h3r를 연 실제 native QA 앱입니다. 세로 화면에는 제목 줄임 처리를 확인하기 위한 긴 이름이 표시됩니다. 화면 배치 증거이며 오디오 재생 검증은 아닙니다. 원본 JPEG를 변경 없이 복사했습니다.

| File | Source | SHA256 |
|---|---|---|
| `circlr-landscape-build166.jpg` | `landscape-1440.jpg` | `61f1a5782e8f0f0f418d688ad18588daf6c8ad663d6ef225c63fe64e53e77cf4` |
| `circlr-portrait-build166.jpg` | `portrait-700.jpg` | `5f5de941a647b706c4d9ea5214d0b229144b3e240de72a41abe5cdc4d0c78873` |

## 0.30.0 build157

Captured from the actual **0.30.0 build157** macOS application, using an isolated QA bundle and the authored `release030.circlr` project. These are editing screenshots, not rendered mockups or evidence of physical audio playback. The UI is Korean in both language versions of the README.

실제 **0.30.0 build157** 앱의 별도 QA 실행 화면입니다. 직접 작성한 `release030.circlr`를 열고 캔버스 배율·편집 방식·콘솔 표시만 조작했습니다. 합성 UI나 재생 성공 증거가 아니며 스크린샷의 앱 언어는 한국어입니다.

- `circlr-orbit-build157.jpg`: Intro section, nested timelines and connected MIDI/audio/effect nodes / Intro의 중첩 궤도와 노드 연결.
- `circlr-midi-build157.jpg`: four MIDI notes in the orbital editor / 궤도 편집기의 MIDI 노트 4개.
- Capture: native app-only CUA screenshot, 1019×768, JPEG bytes saved unchanged / 앱 창만 촬영한 JPEG 원본, 가공 없음.
- Source baseline: commit `5284431`; app version/build from `Resources/Info.plist`.
- Assets: authored QA material; no Splice samples, private songs or account data / 외부 샘플·개인 곡·계정 정보 없음.
- Physical I/O: disabled in this QA bundle / QA 패키지에서 차단.

| File | SHA256 |
|---|---|
| `circlr-midi-build157.jpg` | `39a8d8f9cf1106b20afddc1282ebf1cb86fdf8eea10411ab0563ab75c5bbe8b7` |
| `circlr-orbit-build157.jpg` | `60ce058133993d98915803f2641a8cbd8fcec286d5ec00c9e8a17e973f4ee374` |
