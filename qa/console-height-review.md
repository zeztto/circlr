# build94 console-height native QA

최종 `final-shortcuts` build94 UUID `B3A0BC3E-3D1A-3A77-A9FB-37DED0608EB3`, Release 40.59초. root가 GUI와 1020×768 화면을 확인했고 checker는 앱 호출 없이 저장된 증거를 검사했다.

`python3 qa/check-console-height-evidence.py`: **PASS — baseline snapshot 1개, 초기 후보 3개, 최종 후보 14개(총18), 최종 AX 검사10개, 자산2개 보존, physical output/audition attempts0**.

fixture는 `music-scope/final/reopened.json` r62를 새 ID `F0E5C644-2902-5659-81B9-74F2AE5A0AC6`로 복사했다. ID 외 최초 manifest가 strict 동일하고 source evidence SHA를 검사한다. 모든 native snapshot은 r62로 음악 전체가 보존된다.

## 후보별 증거

baseline93 `before`의 console bounds는 `[20,462.5,794,192.5]`다. 초기 build94 `final/before`와 `final/compact`도 동일하다. 이때 Ctrl-Command-1은 실패했으므로 compact 파일명은 성공 의미가 아니다. 메뉴 작게를 선택한 `final/menu-compact`는 `[20,544.5,794,110.5]`로 높이가82 줄고 root PNG에서 waveform 확대가 보였다. 초기 후보는 shortcut 회귀와 메뉴 경로 증거이며 최종 shortcut 성공을 대체하지 않는다.

최종 Commands 등록 후보의 실제 결과:

| 시나리오 | snapshot 및 실제 bounds |
| --- | --- |
| 키보드 작게 | `compact`: Ctrl-Command-1 후 높이110.5(로그40), draft `state` 보존 |
| drag 상하 경계 | `drag-maximum`: 위220px drag 후250.5(로그180), `drag-minimum`: 아래210px 후110.5 |
| 키보드 크게·기본 | `key-large`: Ctrl-Command-3 후250.5, `key-default`: Ctrl-Command-2 후192.5(로그122) |
| 접기·펼치기 | `collapsed`: consoleOpen false, 높이34. 닫힌 상태의 크게 shortcut 이후에도 `expanded`는110.5이며 draft 보존 |
| 로그 wheel | `log-scrolled`: 로그를 위로 스크롤한 뒤 console bounds와 canvas zoom 유지 |
| editor 왕복 | `router`와 `audio-returned`:110.5 및 draft `state` 보존 |
| 실제 명령 | `command-executed`: Return으로 `state` 실행, AX에 `r62 · 3트랙 · 2섹션` 결과, 입력 draft 비움 |
| 저장·재열기 | `saved/reopened`: r62 전체 manifest strict 동일. open job completed와 최종 디스크 strict 동일 확인, console 높이110.5 유지 |

모든 bounds는 x20·width794·bottom655로 동일하며 로그 크기 변경은 위쪽 경계와 높이만 바꾼다. 기본→작게 실제 전체 console 높이 감소는82다. 로그 높이와 입력·handle을 포함한 전체 bounds 높이를 구분한다. root의 compact/router/drag-maximum PNG가 실제 편집 공간 변화 근거다. zoom은 resize·로그 스크롤 구간에서 동일하며 editor 왕복 시 약3e−14의 부동소수 차이만 있어 checker는 절대허용오차1e−10으로 검사한다. zoom 변화로 공간 확대를 대신하지 않았다.

음악 비교는 hierarchyView/musicRevision만 제외하고 revision62는 별도 exact 검사한다. circleColors pair 배열은 중복 key를 거절하며 사전 의미로 정규화한다. 저장·재열기는 이 정규화 없이 전체 manifest strict 비교다. 원본 studio SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 원본/fixture 자산2개 실제 checksum을 확인했다. 정확한 QA bundle/build/project/path·저장 상태·재생/녹음 비활성·physical0을 검사한다.

root가 후보 앱을 종료했다. 실행 중 job 취소 버튼은 이번 slice에서 native 재검증하지 않았으며 음악 변화가 없으므로 Undo 동작 테스트를 별도로 수행하지 않았다. session 높이의 앱 재시작 영구 보존, 물리 출력·청취 또는 전체 DAW 완료를 주장하지 않는다.
