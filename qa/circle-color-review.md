# build81 서클 색상 검증

상태: 색상 기능 검증 통과. 사용자 앱 교체는 물리 오디오 출고 조건 확인 전까지 보류한다.

## 검증 결과

- `.build/circle-color-clean-tests.log`: 색상·history14개 테스트 통과. 구형 manifest, occurrence별 저장, 색상 전용 Undo/Redo가 최신 음악·view·port revision을 보존함을 확인.
- `.build/circle-color-reset-release.log`: 최종 release37.98초 성공.
- 최종 앱: `qa/generated/circle-color/native/reset/써클러 통합 검증.app`, UUID `A6895A29-2130-3B23-803D-5CF2CB3453C9`.
- native 팔레트·C 메뉴·우클릭·명령 검색·사용자 검정색 입력·Undo/Redo·저장/재열기·기본색 복원 확인.
- `reset-before-open`, `reset-panel-open`, `reset-custom`, `reset-custom-undo`, `reset-reopened`: 명시적인 사용자 색상 변경 외 전체 프로젝트 동일. 기본색 복원 후 패널을 다시 열어도 override가 생기지 않음.
- `panel-switched-before/after`: 프로젝트를 바꾼 후 이전 패널에서 입력해도 새 프로젝트가 변경되지 않음.
- `reset-custom.png`: 검정 사용자 색상의 서클 윤곽과 선택 이름표 대비 확인.
- `python3 qa/check-circle-color-evidence.py`로 저장 근거 재검증.

## 수정한 결함

검정색 작은 서클과 선택 이름표에 중립 테두리를 추가했다. 색상 Undo가 음악 revision을 증가시키던 문제는 색상 전용 history로 해결했다. 패널 초기화가 기본색 override를 생성하던 문제는 초기화 중 action 해제와 현재 표시색과 동일한 callback 무시로 해결했다. 이전 `final.json`은 해당 결함 재현 이력이며 최종 통과 근거는 reset 후보다.

## 범위와 운영

영상 녹화 중 실제 물리 출력·녹화 검증은 이번 범위에 포함하지 않았다. 회귀 테스트는 음악 revision 보존을 확인한다. 생성 앱·음원·snapshot·화면 이미지는 로컬 QA 자료로 유지한다.

유휴 hierarchyqa15995, portsqa36228, integrationqa35380은 저장됨·재생/녹음 정지 확인 후 종료했고 PID 소멸을 재검증했다. 미저장 사용자 앱은 유지했다.

사용자 요청에 따라 설정을 전체10개·서브에이전트9개로 바꾸고 앱 재시작 뒤 실제 9개 생성 및 root 포함10개 running 상태를 확인했다. 이는 현재 세션의 설정·동시 실행 검증이며 서비스의 최대 한도를 뜻하지 않는다.
