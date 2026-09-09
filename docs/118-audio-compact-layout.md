# 작은 오디오 편집기의 파형과 입력 배치

상태: build103 Release39.90초·아래 native/checker·시각 검토 통과.

## 실제 기준 재현

build102 compact에서 label 잘림·복제/템포 줄바꿈과 약40px 파형을 확인했다. 기준 화면은 `qa/generated/audio-compact/baseline/compact.png`다.

## 배치와 focus 계약

파형은 도구 Scroll 밖에 두고 frame 높이를 `min(Orbit 160 / non-Orbit 140, max(80, bodyHeight−100))`으로 정한다. 본문234에서는 frame134, 본문196에서는 frame96이다. ring은 frame보다48px 작으므로 frame 하한80을 ring의 최소 높이로 해석하지 않는다. metadata는 위, 도구 Scroll은 아래에 배치하며 action/nav flow를 적용한다. 수치 입력은4열·label above로 구성한다.

`AudioWorkspaceView.fieldFocus`에 `NumberFieldFocus(revealOnFocus: true)`를 사용해 선택적 자동 reveal을 활성화한다. 기본값과 다른 editor의 focus 동작은 바꾸지 않는다. 수치 입력으로 이동할 때 해당 field에 접근하되 초안·선택·취소와 음악 값을 의도치 않게 변경하지 않는다.

## 검증 기준

1. 기준 compact에서 파형 frame의 가변 높이와 label 가시성을 확인하고 도구를 스크롤해 접근한다.
2. action/nav·4열 입력과 수치 focus reveal, 입력 초안·취소·Undo를 확인한다.
3. 다른 editor의 기본 focus 동작과 기존 오디오 편집 의미가 유지된다.
4. 음악/revision·자산·저장 재열기의 필요한 보존을 대조한다.
5. 최종 Release·native·QA의 실제 확인 범위만 완료로 기록한다. 사용자 앱·physical 출력 조건은 유지한다.

## 최종 후보의 근거

Release39.90초, UUID `AA06CD29-088B-3429-B2C0-D2B218E216AB`. `qa/check-audio-compact-evidence.py`는 snapshot4개·자산2개·physical audio0을 통과했다.

초안 revision36에서 첫 Tab reveal·초안0.의 줌 왕복 보존,999+Tab의 invalid focus 유지·Esc를 확인했다. 유효 trim Return은 revision37의 이번 사용 laneOverride에 sourceStart0.1·duration31.9를 적용했다. Undo와 재열기 revision38에서 음악을 정확히 복원하고 전체 manifest strict 일치·completed open job을 확인했다.

명시적 fresh focus 후 Shift+Tab으로 마지막 입력의 선택120과 compact 가시성을 확인했다. 초기 `last-field`/`tab-cycle` 이미지는 Undo 직후의 성급한 action 관측이므로 acceptance 근거에서 제외한다. 전체8개 field 연속 Tab은 검증하지 않았다.

최종 시각 근거는 compact·draft-wide·draft-return·invalid·trim·last-field-confirmed·last-compact·reopened.jpg이며 수평 overflow 없음 검토를 통과했다. 검증 앱 종료 뒤 기존 사용자 PID86114만 유지했다. 실제 재생·녹음은 실행하지 않았다.

본문 높이180 미만과 recording busy 상태는 이번 native 미검증이다. 현재 관측을 이 조합까지 확대하지 않는다.
