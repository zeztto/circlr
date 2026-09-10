# 테이크 검색과 키보드 선택

상태: build108 final3 Release39.82초·아래 native·시각/source 검토 통과. checker9개 상태·검색 AX·테이크5개·자산2개·output0·r30 strict 복원/재열기/disk 대조 통과.

기존 native 메뉴를 canvas의 `StudioPalette` 검색으로 연결한다. 직접 버튼·⌥⌘T·전체 명령에서 진입하며 ↑/↓·Return·Esc로 탐색·선택·취소한다. build107의 키보드 메뉴 선택 미검증을 이번 후속 범위로 다룬다.

## 검증 계약

1. 버튼·⌥⌘T·전체 명령에서 같은 테이크 검색에 진입한다.
2. 검색0개·현재 대상 필터·다른 대상 제외를 확인한다.
3. Down/Return 실제 적용과 Esc 취소, 현재 일치 표시를 검사한다.
4. 한 Undo 복원·음악/자산 보존·저장 재열기를 확인한다.
5. 최종 Release·native·QA 근거가 확보된 범위만 완료로 기록하고 실제 I/O는 실행하지 않는다.

앱별 출력 장치 선택은 별도 [계획](107-app-output-device-plan.md)이며 아직 미구현이다. 검색 개선을 출력 stall 해결이나 물리 오디오 출고 완료로 계산하지 않는다.

## 후보별 관측과 최종 범위

초기 shortcut은 `AudioWorkspace.handleAudioEditKey`의 option 미검사로 실제 split23을 만들었고 Undo24로 복원했다. 정확한 modifier guard를 적용한 final2에서 ⌥⌘T·Down/Return·검색0·Esc·Undo를 확인했다. final3는 처음3개 목록을194px(3×60+14)로 줄이고 필터/빈 결과에서 높이를 유지한다.

최종 UUID `B3DB0EA9-922A-363F-8D15-9D28D96F7ABB`, Release39.82초다. shortcut26→16초 테이크 적용27→검색 취소27→Undo28, ⌘T split29→Undo30, stale/restored/reopened30을 확인했다. 현재1개 결과·없는 테이크0개에서 Return 무변경/Esc, ⇧⌘P ‘녹음 테이크’ Return 진입과 query reset·header·stale focus 적용 거부도 확인했다.

최종 screenshot6개 시각 검토와 source review를 통과했다. checker9개 상태·검색 AX·테이크5개·자산2개·output0·r30 strict 복원/재열기/disk 대조도 통과했다. physical I/O0이며 기존 사용자 PID86114를 보존했다. 앱별 출력 장치 선택은 여전히 미구현이다.

최종 checker는16초 선택·split Undo·stale 거절과 restored/reopened/disk revision30 일치·completed open job을 확인했다. 패키지/security 검사도 text14개 변경 범위·strict 서명으로 통과했으며 검증 앱 종료 뒤 사용자 PID86114만 유지했다.
