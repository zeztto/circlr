# 0.8.0 앨범 계층 캔버스 검증

DATE: 2026-09-07
ROLE: development-lead / qa / code-review
STATUS: 로컬 0.8.0 bundle 검증 완료
SCOPE: 앨범·곡·악장·섹션·음악 서클과 같은 캔버스 직접 편집
PRODUCT_BUNDLE: dist/써클러.app / 0.8.0 / build 9
PREVIOUS_BUNDLE: dist/archive/써클러-0.7.1.app
QA_BUNDLE: qa/generated/Hierarchy QA.app / com.circlr.hierarchyqa
USER_DATA: QA package 및 별도 Application Support/circlr-hierarchy-qa만 사용. 사용자 곡과 production 복구 데이터 미변경.

## 자동 검증

최종 Core/Audio/Geometry 테스트 **61개, 0 failures**. `generated/0.8-tests-final.log`에 19:09:26 종료가 기록되어 있다. 포함·순서·반복·상속·migration·round-trip, typed MIDI/audio routing·cycle/sidechain, clip/lane 동기화, 원본/변형, 실제 DSP·WAV·playback, 그룹 좌표·접기·외부 연결, 정확한 Take 대상, 부분 마디 clock, viewport 저장/복원을 검증했다.

기본 제한 환경의 첫 전체 실행은 macOS Audio Component 접근 실패로 중단됐다. 동일 테스트를 오디오 서비스를 사용할 수 있는 승인된 실행 환경에서 통과했다. 실패 로그 `hierarchy-complete-tests.log`와 성공 로그를 구분한다.

Release 빌드: `generated/0.8-release-build-final.log`. 최종 화면 가시성 조정은 같은 Release 앱으로 native 확인했다. SwiftPM 증분 ABI 문제가 있었던 초기 빌드와 분리된 scratch에서 통합 검증했다.

## 실제 앱 검증

1. 빈 앨범에서 두 곡과 두 악장, 세 섹션을 생성했다. 같은 캔버스로 내부에 들어가거나 상위로 복귀했다.
2. MIDI 서클의 PianoRoll에 노트 3개를 넣었다. 저장된 Lane과 재열기 후 세 노트를 확인했다. 휠로 확대/축소하면서 편집기가 같은 메인 창에서 나타나고 사라진다.
3. 실제 controlled WAV를 가져와 생성된 오디오 서클과 파형을 확인했다. 양쪽 trim handle 이동 후 sourceStart 약 0.024초, duration 약 0.201초를 저장했다. Undo/redo로 길이를 복원했다.
4. 오디오 경로에 Delay를 삽입하고 Amount 0.35를 저장했다.
5. 두 음악 서클을 원형 그룹으로 묶고 이동했다. Undo로 원위치, 접기/펼치기로 내부 표시와 외부 wire 유지, package 저장의 Layout.groups를 확인했다.
6. 앨범 사운드에서 실제 트랙 출력·버스·마스터를 표시했다. 전역 Gain과 버스를 생성해 트랙 → Bus 2 → Gain → 마스터로 연결했다. Gain 0.8을 저장했다.
7. 저장 후 앱을 종료·재실행하고 문서를 열어 전역 사운드의 선택 서클과 확대 위치, 연결을 복원했다.
8. 전환 UI는 연결을 미리 갖춘 **통제된 QA fixture** `0.8-transition-native.circlr`에서 검증했다. 같은 캔버스의 전환 편집에서 길이 1마디·Gain 0.5를 저장하고, 연결 삭제 후 Undo로 연결과 전환 값이 함께 복원됨을 확인했다. 이 fixture의 최초 flow edge는 UI로 만든 것이 아니다.
9. 섹션 재사용과 Undo 후 상위 곡으로 복귀하는 동작을 확인했다. 관계없는 겹친 곡이 확대 편집 화면을 가리던 표시를 정리하고 최종 실행에서 확인했다.
10. 닫기 버튼/⌘W 후 QA 앱이 계속 실행 중임을 확인했고, ⌘Q 후 종료 및 재실행을 확인했다. 최소화 delegate는 0.7.1 검증 구현을 유지한다. CUA의 앱 screenshot은 최소화 중에도 마지막 window buffer를 반환하므로 그 이미지를 Dock 최소화 증거로 사용하지 않는다.

외부 MIDI 하드웨어·실제 마이크 녹음·임의 third-party AU 화면의 모든 조합을 검증한 것은 아니다. 정확한 Take 대상과 AU callback의 서클/descriptor 일치 guard는 core 테스트 및 소스 검토 범위다.

## 실제 오디오 대조

`generated/0.8-native-global-export.wav`는 native 메뉴로 내보낸 50초·48 kHz·stereo·24-bit WAV다. 전체 body 48초와 tail 2초를 포함한다. 별도 RIFF/PCM 파서로 대조했다.

- Peak: 0.1493788958
- RMS: 0.0040939456
- 이전 native WAV × 0.8과의 최대 차이: 9.536743165e-8, 24-bit PCM 한 단계 이내
- SHA-256: f645382cd9bb131ad05d760491db9a0a5eaca8848ef4545d2a746f90012bc985
- Native transport 37.5초 진행 후 정지: `generated/0.8-playback-native.txt`

증거: `generated/0.8-native-audio-evidence.json`. 이는 실제 라우팅 및 Gain 적용 검증이며 주관적 청취 품질 평가를 뜻하지 않는다.

## 수정·검토한 회귀

- 부모 원의 header 침범: clipping 적용.
- 같은 payload와 graph source의 불일치: 새/삭제 clip·lane만 동기화, 삭제한 노드/경로 보존.
- 개별 audio clock·길이 무시: 반복별 위치·trim 경계 적용.
- 배치 그룹이 음악 시간을 바꿀 가능성: Layout-only transaction 및 좌표/PCM 회귀.
- 전역 signal UI 누락: 실제 sound/signal 서클과 기존 DSP 연결.
- Take가 첫 트랙 Lane을 덮는 문제: targetLaneID/arrangementID로 적용, 대상 삭제 시 atomic rejection.
- 지연된 AU 화면이 다른 서클에 적용될 가능성: 요청 address·descriptor guard.
- 반복 서클의 editor 배율 및 링 바깥 hit/port: 외곽 radius와 detail radius 분리.
- 재사용 overlap 및 사라진 선택: 실제 크기 기준 간격, Undo 후 상위 복귀.
- 큰 가지의 label/노드 겹침: 작은 배율의 단계별 표시와 깊은 확대 시 선택 가지 집중.

현재 범위에서 release를 막는 확인된 결함은 남아 있지 않다. 현재 오디오는 준비한 PCM을 재생한다. 연속 실시간 그래프 재구성, 모든 AU의 crash 격리/PDC, 가변 tempo map에 따른 연속 audio warp, 장시간 앨범의 chunk streaming은 후속 엔진 범위다. 렌더링 메모리 예상량이 제한을 넘으면 명시적으로 거부한다.

## 패키지와 증거 위치

- `generated/0.8-source-sha256.json`: 최종 Sources hash, 이전/현재 앱 binary hash, Release/QA/product의 동일 Mach-O __TEXT,__text hash.
- 이전 0.7.1 binary hash는 archive 이동 전후 동일하다.
- 현재 및 이전 bundle 모두 `codesign --verify --strict` 통과. 로컬 ad-hoc 서명이며 Apple notarization 배포가 아니다.
- `generated/0.8-midi-native.png`, `0.8-viewport-restored.png`, `0.8-transition-native.png`, `0.8-focus-final.png`, `hierarchy-group-native.png`, `hierarchy-group-collapsed.png`.
- 초기 `hierarchy-midi-native.png`는 header clipping 수정 전 화면이므로 최종 화면과 혼동하지 않는다.
- 현재 실행 중인 production 프로세스는 자동 종료하지 않았다. 새 앱 사용에는 ⌘Q 후 재실행이 필요하다.
