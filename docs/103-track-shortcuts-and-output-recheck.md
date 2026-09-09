# 현재 트랙 단축키와 출력 재대조

상태: build89 parser·최종 Release·아래 native 탐색 검증 확인. 저장·재열기와 QA 최종 대조 통과. [단축키 QA](../qa/track-shortcut-review.md). 출력 원인 해결 결과는 없다.

## 트랙 단축키 계약

`StudioNavigationView`의 ⌘1/⌘2/⌘3이 첫 대상을 임의로 고르는 동작을 현재 section·track 범위의 일관된 선택으로 바꾼다. 대상0개는 명확한 빈 상태,1개는 해당 대상으로 이동, 여러 개는 선택 동선을 제공한다. MIDI와 audio가 섞인 범위는 typed union으로 대상을 표현한다. 단축키만으로 다른 트랙의 첫 대상을 선택하거나 서로 다른 종류의 주소를 혼동하지 않는다.

실제 후보에서0/1/multi·혼합 MIDI/audio·현재 section/track 경계와 키보드 선택·취소·복귀를 확인한다. 탐색만으로 음악이 바뀌지 않고 작은 창에서도 기존 편집 동선을 유지해야 한다. 신규 Swift unit 테스트는 추가하지 않았다.

## 최종 후보 확인 범위

Release42.42초, UUID `52B4819A-9626-3B81-B040-D45A340763B2`. parser 검사와 실제0/1/multi·혼합 대상·미연결 대상 Return·종류 전환·현재 찾기 union 해제를 확인했다. QA checker가 baseline5+final8 문서 캡처와 AX7개를 대조했다. 저장·실제 open 뒤 음악 revision16·선택·camera와 자산2개·source SHA를 보존했고 output0회다. `hierarchyView.workspace.editor`의 기본 객체 구체화만 있으므로 전체 파일 byte 동일로 표현하지 않는다. 기존 빌드의 테스트 개수를 이번 검증으로 합산하지 않는다.

## 출력의 동시간 대조 결과

[출력 QA](../qa/output-signature-review.md)와 `qa/generated/output-signature-build89/summary.json`에서 서명 보존 helper2회와 동시간 raw control2회가 모두 mixerAcquisition/entered에서 timeout했다. 네 시도 모두 started=false, command EOF 요청 뒤 강제 kill 없이 exit0, 임시 디렉터리 제거를 기록했다. 원본은 보존됐다.

서명을 보존한 패키지의 strict 검증은 가능하지만 timeout 해결을 입증하지 못했다. 앞선 raw 성공과 서명 변경의 상관만으로 원인을 서명에 귀속할 수 없다. 이번 동시간 raw 실패는 이전 서명 가설을 제한하는 반증이며 출력 원인은 계속 미확정이다.

## 후속 검증 경계

단축키 개선 완료와 출력 문제 해결을 합산하지 않는다. 서명 대조 probe들은 sample 요청 전에 종료돼 해당 대조의 stack은 없다. 이후 별도 live stall probe2회에서는 sample을 확보했다 (`qa/generated/output-stall-build89/stall-summary.json`). mainMixer→AudioDeviceCreateIOProcID→HAL SetPropertyData→mach_msg 대기를 확인했지만 서버 원인과 장치 identity는 미확정이다. 사용자 앱·원본과 timeout/retry/device 정책을 유지하며 정상 출력·청취·물리 I/O 출고 완료를 선언하지 않는다.

## 다음 UI 과제 — 포트별 출력 도달성

현재 node 단위 탐색은 독립 router bus에 있는 다른 트랙의 effect도 노출할 수 있다. 다음 범위는 `BounceAssessment.membership` 재사용 또는 공통 Core endpoint 역추적을 통해 `StudioNavigation.outputTracks`와 `build`의 판정을 함께 맞추는 것이다. sidechain 제외·fanout·implicit port를 검사하고 독립 bus의 다른 트랙 대상이 섞이지 않는지 확인한다. 이 분석과 후속 계획은 현재 build89에서 해결된 결과가 아니다.
