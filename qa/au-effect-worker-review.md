# build96 AU effect worker QA

실제 packaged Apple AU offline PCM 비교 **PASS**. `.build/au-effect-package-native.json`과 `.log`를 직접 확인했다. helper arm64 UUID는 `0EA9E83A-9DF1-3496-B931-0C021640B7C5`이며 XCTest 1개가 0.700초에 실패0으로 완료됐다. default와 captured-state는 한 테스트 안의 두 구성이다.

| Apple AULowPassFilter 구성 | frames | peak | maximum error | RMS error |
| --- | ---: | ---: | ---: | ---: |
| default | 12000 | 0.09381431341171265 | 0.0 | 0.0 |
| captured cutoff900Hz·resonance3dB | 12000 | 0.08499331772327423 | 0.0 | 0.0 |

48kHz stereo 입력은 좌우가 다른 저주파·고주파와 impulse를 포함한다. 입력 배열 exact 보존, 출력 count·finite·nonzero peak, reference의 실제 effect 변화, 최대오차1e−5/RMS오차1e−6 이하를 검사한다. 위 측정에서는 두 경로가 sample 단위로 같았다.

state 구성은 공식 LowPass parameter 상수로 cutoff/resonance를 설정한 뒤 `AudioUnitHost.capture`로 descriptor.state를 만들었다. 새 reference 인스턴스에서900Hz/3dB 복원을 확인하고 default 대비 실제 PCM 변화도 검사했다. 따라서 양쪽이 state를 무시한 채 우연히 같아진 결과를 통과로 취급하지 않는다. worker와 reference는 AU 인스턴스를 공유하지 않는다.

`python3 qa/verify-au-effect-package.py --log .build/au-effect-package-native.log`가 재현 명령이다(로그는 새 파일이어야 함). `--binary`와 `--scratch-path`를 지원한다. root가 먼저 debug test를 빌드해야 하며 runner는 `--skip-build`로 실행한다. 환경변수 `CIRCLR_AU_EFFECT_WORKER_TEST_EXECUTABLE` 없이는 integration test가 명시 skip하므로 skip은 실제 PASS가 아니다. runner는 두 구성의 측정 출력이 모두 있어야 성공한다.

runner는 TemporaryDirectory에 production packager·kit builder·MCP server·Resources를 복사해 실제 Release로 패키징했다. packaged helper의 Mach-O sections가 source helper와 같고 codesign deep/strict가 통과했다. 이 packaged helper 경로를 env로 전달해 실제 실행했으며 사용자 dist 앱에 접근하지 않았다. subprocess timeout 시 process group을 정리하며 test 명령120초, host worker15초 제한이다. reference의 OS AU instantiate까지 포함한 전체 runner 제한과 worker timeout은 서로 다른 경계다.

root 보고 최종 Release47.10초와 packaging 검사3개가 통과했다. `.build/au-effect-final-tests.log`의 선택 회귀 묶음은46개(신규18+기존28), 실패0, 18.491초로 완료됐다. packaged Apple AU 비교1개·2구성은 이46개와 별도의 실행 근거다. 생성 로그는 commit 대상이 아니다.

이 검증은 Apple AU의 실제 offline 처리와 state 전달이다. helper cancel/timeout 실행 검증은 host test 결과로 따로 판단한다. GUI/App의 immediate STOP race는 source guard와 compile 확인 범위이며 실제 GUI STOP 시나리오를 수행했다고 주장하지 않는다. 물리 장치 출력·입력, 외부 third-party AU 호환성, 모든 플러그인 또는 전체 DAW 완료는 미검증이다.
