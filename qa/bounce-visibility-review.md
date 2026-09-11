# 바운스 대상 표시 — build85 compact 검증

2026-09-10. `bounce-visibility.circlr` 별도 authored QA 프로젝트로 build84 baseline, 초기 build85 회귀, 수정한 compact 후보를 구분해 검증했다. 최종 통과 범위는 상태 표시·명령 대상·편집 보존·stale 거절·재열기다.

baseline에서 같은 track의 오디오를 복제한 뒤 복제 node의 출력 edge만 제거했다. 같은 track에 연결된 다른 source가 남아도 선택한 복제 node 자체는 출력 경로 밖이다. 이어 원래 group→output edge도 제거해 출력 입력이 없는 상태를 만들었다. 고정 ID와 두 edge 원본은 `scenario.json`에 있다.

초기 build85는 baseline no-input 문서를 그대로 열었다. 출력 서클을 여는 navigation만으로 음악은 변하지 않았다. UI에서 group main 연결을 Return으로 적용해 기존 group→output endpoint를 새 edge ID로 복구했고, 다시 경로 밖 복제 오디오를 선택했다. checker는 두 disconnect와 reconnect의 정확한 edge 차이, 대상 use 외 모든 필드 보존, navigation 전후 음악 불변을 확인한다.

초기 build85에서 별도 status 행이 waveform 영역을 약 85px에서 45px로 줄이고 진폭 표시를 약 1px로 축소하는 화면 회귀를 발견했다. 따라서 이 후보를 화면 통과로 계산하지 않고, compact 후보에서 수정 후 재검증했다.

compact build85 UUID `1A15C6F2-3FA2-38AB-84C0-FC443ED81314`, release 40.86초 후보에서는 상태를 기존 행에 배치했다. `compact/outside.png`를 직접 확인해 1020×768 화면에서 waveform과 진폭이 충분한 높이로 표시되고 수치 입력도 유지됨을 확인했다. 별도 status 행을 사용한 초기 후보는 계속 회귀 증거로 보존한다.

`compact/command-open`은 경로 밖 오디오에서 명령 검색의 바운스 출력 연결 보기를 실행했을 때 동일 arrangement/use의 실제 주 output node로 이동하고 connections 페이지를 연 증거다. 이 이동은 음악을 변경하지 않는다. 이후 output edge를 하나 해제하면 입력 없음 안내가 나타나며 Undo는 음악 전체를 되돌린다. automation 페이지 전환도 동일한 경로 밖 안내를 유지하고 음악 변경 없이 열린다. 이 automation 검증은 표시·navigation이며 곡선 편집 검증은 아니다.

팔레트에 명령을 표시한 뒤 MCP rename_project로 revision을 바꾸고 Return을 누르면 대상이나 음악이 바뀌었다는 안내로 거절됐다. `stale-mutated/stale-rejected`는 전체 manifest가 같고 원래 오디오 선택·automation 표시가 유지됐다. Undo로 이름을 되돌린 뒤 실제 open job 완료 후 저장한 `final/reopened`도 전체 manifest가 일치한다.

초기 Core 28개와 audio PCM 15개 테스트 통과, release 72.90초 성공 보고를 받았다. 이 테스트는 물리 오디오 출력을 검증한 것이 아니다. `python3 qa/check-bounce-visibility-evidence.py`는 20개 캡처(그중 compact 12개)의 보존·명령 대상·해제/Undo·automation 표시·stale·재열기 검사를 통과했고 `status: passed`를 출력한다.

원본 studio manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 authored asset 2개의 원본·fixture 실제 파일 checksum이 유지됐다. 캡처에서 output/audition attempts는 0이고 재생·마이크·MIDI 입력을 시작하지 않았다. 실제 바운스 렌더, A/B 청감, 물리 출력 정상 동작과 전체 DAW 완료는 이 단계에서 주장하지 않는다.
