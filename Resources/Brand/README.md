# circlr 앱 아이콘

차콜 바탕에 민트색의 열린 궤도, 내부 원, 작은 위성을 배치했다. 서클 안에 다른 서클이 연결되고 시간 궤도가 되는 circlr의 구조를 표현한다.

## 원본과 생성 기록

- `circlr-icon-v1-source.png`: 일반 ChatGPT 브라우저에서 pageAssets로 내보낸 원본, 1254×1254 RGBA PNG. 원본 바이트를 보존한다.
- `circlr-icon-v1.png`: `sips`로 1024×1024로 축소한 빌드 입력. 모서리가 실제 투명한 이미지다.
- `icon-composer.json`: macOS용 배경색·레이어 배치 설정. 같은 PNG를 1.25배 배치하고 그림자·레이어 유리 효과를 끈다. 외곽 모양과 시스템 표면 처리는 macOS에 맡긴다.
- [생성 manifest](provenance-v1.json): 정확한 프롬프트, 대화, 파일 해시와 변환 기록.

[ChatGPT 생성 대화](https://chatgpt.com/c/6a9ebe53-c330-83ee-b19d-e829351c71ed)에서 한 번의 요청으로 생성했다. 자동으로 나온 후보 중 실제 alpha 채널이 있는 마지막 이미지를 선택했다. 체크무늬가 배경 픽셀로 들어간 후보는 제외했다. 텍스트나 외부 로고는 넣지 않았다.

## 재빌드

Xcode 26 이상에서 다음을 실행한다.

```sh
python3 scripts/build-icon.py
./scripts/build-app.sh
```

`build-icon.py`는 임시 iconset의 10개 크기 표현을 `iconutil`로 변환하고, 임시 `.icon` 패키지에 PNG와 설정을 넣어 `actool`로 컴파일한다. 결과는 `Resources/AppIcon.icns`와 `Resources/Assets.car`이다. 정상 생성 후 기존 파일을 교체한다. 전체 앱 빌드는 이 과정을 자동 호출하므로 보통 두 번째 명령만 필요하다.

번들의 `CFBundleIconName=Circlr`는 컴파일된 리소스를, `CFBundleIconFile=AppIcon`은 ICNS를 지정한다. 이미지 원본이나 생성 대화는 앱 번들에 포함하지 않는다. [Apple 아이콘 구성 문서](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)와 [CFBundleIconName](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleiconname)을 참고했다.

macOS 아이콘 변환·표시 서비스가 차단된 sandbox에서는 `iconutil`이 Invalid Iconset을 반환하거나 `NSWorkspace`가 빈 아이콘을 반환할 수 있다. 이번 검증은 동일한 로컬 명령을 서비스 접근이 가능한 환경에서 실행해 완료했다. [검증 결과](../../qa/0.10.1-icon-review.md).
