# build90 출력 장치 read-only 감사

판정: 당시 기본 출력 장치와 활성 CoreAudio client를 조회했다. 이 client가 출력 준비 stall의 원인이라는 증거는 없다. `qa/generated/output-device-build90`의 summary·client-summary·query 결과·stdout 전체 및 진단 Swift 소스를 대조했으며 이 감사에서 추가 조회나 실행은 하지 않았다.

`summary.json`, `query.stdout`, `query.json`은 기본 output device ID96, Scarlett 6i6 USB, USB transport, 44100 Hz, buffer 512 frames, alive=1, runningSomewhere=1을 기록한다. 8개 property 완료 status는 모두 0이다. query PID76229는 0.383초에 exitCode=0으로 끝났고 timedOut=false다. UID는 probe 안에서 SHA256으로 변환되며 원문을 보고하지 않는다.

`client-query.stdout`, `client-summary.json`, `client-query.json`은 process object 34개 가운데 device96에 대응하는 object158 하나를 기록한다. bundleID=com.google.Chrome.helper, PID58755, inputDeviceIDs=[96], outputDeviceIDs=[96], running=1, runningInput=0, runningOutput=1이다. input 목록에 존재한다는 사실을 입력 녹음 중이라는 뜻으로 해석하지 않는다. query PID76467은 0.431초에 exitCode=0, timedOut=false로 끝났다.

진단 소스 `DeviceQuery.swift`와 `ClientQuery.swift`는 CoreAudio SDK의 `AudioObjectGetPropertyData` 및 `AudioObjectGetPropertyDataSize`를 사용한다. client의 `kAudioProcessPropertyDevices`를 input/output scope별로 조회하며 property 설정이나 장치 시작·정지 호출은 없다. 이 결과는 현재 출력 사용 client를 특정한 것이며 별도 IOProc 등록 정체의 원인이나 독점 점유를 입증하지 않는다.

보존 범위: summary는 사용자 앱 PID86114가 계속 존재함을 기록한다. 진단 소스에는 사용자 앱·Chrome 종료, default device/sample rate/driver 변경이 없다. production code·packaging·사용자 파일·장치 설정을 이 감사에서 수정하지 않았다. 감사 시 private integration checkout HEAD는 `89e42bf1d84ec9310d68d0f04e89a5984d54ef06`였고, 작업 트리에 README/CHANGELOG/Info.plist와 port navigation 관련 다른 작업자의 변경이 있어 그대로 보존했다.

build89 live sample은 mixerAcquisition에서 `mainMixerNode → CreateIOProcID → HALC_ProxyIOContext::_TellServerAboutStreamUsage → SetPropertyData → mach_msg` 대기를 확인했다. 이번 device ID mapping은 그 sample과 다른 시점에 수집됐다. 따라서 과거 stack의 대상 장치가 이번 device96이었다거나 Chrome의 현재 출력 사용이 그 대기의 원인이라고 결론내리지 않는다. 역사적 running=0과 이번 running=1의 차이도 시점별 관측값이다.

다음 증거가 필요하다면 동일 시각의 소유 helper stack과 read-only 장치/client mapping을 함께 보존하고, 서버 측 대기와 연결 가능한 정보를 대조한다. 서버 측 원인·물리 장치 identity·시스템 변경 필요 여부는 아직 미확정이다. 본 문서는 후속 실행이나 장치 리셋을 수행하지 않는다.
