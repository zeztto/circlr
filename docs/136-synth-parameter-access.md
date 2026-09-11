# 신스 수치 편집의 키보드 접근

상태: build118 baseline 결함 재현 후 build119 소스·native UI·패키징 검증을 완료했다. 물리 오디오 검증은 포함하지 않는다.

## 문제와 완료 조건

단일 캔버스의 신스 편집에서 세로로 잘린 파라미터가 Tab 포커스만 받고 화면 안에 나타나지 않는다. baseline의 첫 필터 수치부터 Tab10회로 마지막 움직임0.55가 선택되었지만, 화면은 필터·Detune·Attack·Decay·Sustain·Release까지만 표시했다. source의 LazyVGrid와 포커스별 reveal 부재를 대조했다. 가로 overflow가 있었다고 주장하지 않는다.

기존2열 수치 편집을 유지하면서 모든 필드를 지속적으로 등록하고, Tab/Shift-Tab으로 선택한 수치가 현재 ScrollView 안에 보여야 한다. 같은 캔버스·기존 편집 대상·정확한 수치 단위는 유지한다. 배치 변경만으로 초안을 잃거나 음악 revision이 증가하면 안 된다. 기존 NumberEditingContext의 project/track/revision/activation 검증을 보존한다.

## 검증 계획

독립 authored `synth-workspace.circlr` 사본의 engine3를 사용한다. build118/119 helper5종은 모두 exit78 stub으로 교체하며 production 바이너리와 구분한다. 원본 사용자 앱과 오디오 장치는 사용하지 않는다.

1. 짧은 편집 영역에서 11개 필드 정·역방향 Tab 이동과 마지막/첫 필드 노출.
2. 마지막 움직임 수치 입력·적용·Undo의 정확한 음악 변화와 자산 보존.
3. 미확정 초안에서 화면 높이/콘솔 배치 변경, Esc 취소.
4. 저장·종료·정확한 재열기와 남은 입력 값·편집 대상 확인.
5. engine1/2의 표시 필드 수와 키보드 경계는 가능한 native 범위를 따로 기록한다.

준비/캡처는 `qa/prepare-synth-workspace-qa.py`와 `qa/verify-synth-workspace-native.py`를 사용한다. 실제 포커스·가시성 판단은 JSON만으로 대체하지 않고 AX와 JPEG를 함께 확인한다.

## 구현과 검증 결과

`SynthParameterLayout`이 동일 field subtree를 eager2열로 배치한다. 엔진별6/9/11개 순서의 registry는 State로 유지하고 revealOnFocus를 켰다. 상위 NumberEditingContext 전체를 복사해 fieldFocus만 교체하므로 기존 target/revision/activation·초안 보호는 보존된다. binding·단위·음악 파라미터 의미는 변경하지 않았다. Source read-only review: blocker0.

- baseline118/final119는 동일 canvas1024×673, 짧은 body에서 비교했다. tool JPEG 표시 크기는1019×768이며 앱 논리 좌표와 구분한다. baseline의 last 선택0.55는 화면 밖, final의 last는 자동 스크롤 후 가시 영역에 있다.
- engine3 정방향11필드·역방향10회 이동 후 first10000 복귀를 AX chain과 endpoint JPEG로 확인했다. 각 중간 필드의 모든 프레임을 JPEG로 캡처한 것은 아니다.
- filter 초안1000.를 유지한 채 콘솔 로그 높이122→180으로 body를 줄여도 같은 필드 focus·초안 유지. Escape로10000 복귀, 음악r14 유지. 이는 콘솔에 따른 편집 영역 높이 변경이며 실제 window 폭 변경 테스트는 아니다.
- 움직임0.55→0.7 적용r15, Undo0.55 r16. engine1(6개)/engine2(9개)의 마지막 필드까지 Tab·JPEG 확인 후 두 Undo로engine3/voice6 및 전체 음악을 복원(r20).
- 초기 EP(voice6)를engine1로 바꾸는 QA 요청은 유효성 검사로 거절되어r16 유지. 지원 voice0를 함께 지정한 별도 QA 변경으로 검증했고 마지막에 모두 Undo했다. 이 거절을 성공 편집으로 세지 않는다.
- 최종 manifest와 재열기 후 manifest 및 디스크가 정확히 일치한다. 음악 비교는 revision·layout·view·modifiedAt 메타데이터를 제외하고 모든 필드를 대조했다. 자산2개 checksum 유지. 콘솔 높이는 세션별 기본122로 복귀하지만 저장된 편집 스크롤y93.5·대상·카메라는 보존된다.
- 최종 Release45.18초, main UUID `F7DDD631-412D-3307-B026-B590A2F56234`. production 앱 서명·QA main UUID 동일성 검증. 모든 QA helper5종은 exit78 stub이고 output/audition attempts0·재생/녹음false를 캡처마다 검사했다.
- QA JPEG9장 직접 검토. 가시성은 JSON checker만으로 판정하지 않는다. QA 앱 종료 후 사용자 원본PID86114만 유지했다.

로컬 증거는 `qa/generated/synth-workspace/baseline118` 및 `final119`에 있다. VoiceOver 발화, dirty draft 중 트랙/엔진 외부 전환, 실제 창 폭 변경, 다른 긴 편집 폼은 후속 검증 대상이다.

증거 검사: `python3 qa/check-synth-workspace-evidence.py` PASS. snapshot9개·AX chain4개·JPEG9개, version/UUID/sign·source hashes·명시 revision·단일 값 변화·엔진 QA 범위·음악 복원·disk exact 검사. 실제 JPEG를 PNG 확장자로 저장했던 최초 파일명은 바이트와 SHA를 보존하여 `.jpg`로 바로잡았다.
