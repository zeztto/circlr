# 오디오 원본 탐색 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `6e4c2b6`, 0.20.0 build 49. development-lead → UI/UX → native Swift → 읽기 전용 code review → QA를 순차 수행했다. 독립 UI 검토에 실제 에이전트를 배정했지만 `agent thread limit reached`가 반환됐다. 독립 리뷰를 수행했다는 의미는 아니다.

## 결과와 패키지

- Swift **377개**, 실패 0, **26.124초**. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. 출력 장치가 필요한 기존 검사 한 개의 제외 조건을 유지한다. 새 Core 검사 3개는 포인터 anchor·경계·최소 배율·이동/커서 보기·원본 좌표 정밀도·비유한 입력 거절을 다룬다.
- Python **26개**, 실패 0, **0.219초**: `python3 -m unittest mcp.test_server qa.test_agent_kit`. 첫 release **50.52초**, 휠 전달 수정 **26.96초**, 최종 높이 수정 **27.87초**. Core와 Python 소스는 첫 테스트 이후 바뀌지 않았다. App의 두 수정은 release 재빌드와 실제 앱 재검증을 했다.
- 최종 앱: `qa/generated/audio-source-navigation/readable/써클러 통합 검증.app`, UUID **73F358EC-207D-320A-A558-0727AF1035C3**. Mach-O section **37개**, 소스 hash **7개**, Codex kit **25개**, build/version과 ad-hoc strict codesign을 확인했다.
- `python3 qa/check-audio-source-navigation-evidence.py` 통과. 최종 `readable/verification.json`은 저장된 snapshot **9개**, AX **35개**, JPEG **6개**를 검증한다. 이 도구는 이번 로컬 실행의 산출물을 검사하며, 다른 release 바이너리에 대한 보편적인 CI 검사가 아니다.

## 실제 화면과 데이터

직접 작성한 검증 톤 2개·트랙 3개의 사본 `audio-source-navigation.circlr`를 사용했다. project ID는 **541EA22B-D5A7-56B2-AA80-C7341F4A463E**, 두 번째 use는 **95227028-B6DC-5573-B533-6611BA01C4E2**다. 창은 **1019×768**, 콘솔을 연 상태다. 원본 톤의 source 범위는 0–32초다.

| 검사 | 최종 앱에서 확인한 결과 |
| --- | --- |
| 휠/카메라 | 자유 파형 위 실제 휠 up으로 0–32초 → 7.947–23.947초, down으로 전체 복귀. 궤도 위에서도 4.64초 폭 → 2.32초 폭으로 확대했다. 편집 중 canvas zoom은 `234.96296296296293`을 유지했다. |
| 버튼/키보드 | 확대 버튼과 `+`로 12–20초, Page Down으로 16–24초, End로 24–32초. 커서 보기 버튼/C는 12–20초, Home은 0–8초, Page Up은 8–16초로 이동했다. 탐색은 r18을 유지했다. |
| 숫자→선택 | 시작 8초, 끝 16초, 분할 offset 2초를 순차 입력했다. 음악은 두 번 변경되어 r20이다. F로 7.36–16.64초를 표시했다. |
| 숨겨진 커서 | 확대/이동 후 11–15.64초에서 C가 source 10초를 찾아 7.68–12.32초로 이동했다. 분할 위치만 7초로 바꾸면 음악 revision·표시 범위는 그대로이고 커서 보기만 활성화된다. C로 12.68–17.32초를 표시했다. |
| 키보드 trim | Right가 시작을 8.01초로 바꿔 r21이 됐다. 끝 16초·표시 범위·절대 분할 source 15초를 유지했다. 한 번 Undo로 시작 8초, r22가 됐고 배율은 유지됐다. Undo 후 분할 cursor는 기존 상대 offset 규칙을 따른다. |
| 궤도/최소 배율 | 자유→궤도에서 12.68–17.32초 범위를 유지했다. 확대 하한은 14.983–14.993초로 0.01초다. 밀리초 숫자가 원의 중앙에 보인다. 배치 Undo 후 자유 파형도 14.980, 14.985, 14.990, 14.995, 15.000초의 구별되는 눈금을 표시했다. 기존 배치 Undo는 revision을 r23으로 올린다. |
| 작성 중 입력 | 볼륨에 `-6` 작성 중 F 키는 활성 한글 입력기의 `ㄹ`로 필드에 입력됐다. 휠은 파형 배율만 바꾸고 필드 포커스와 `-6ㄹ` draft를 유지했다. Escape로 gain 1/0 dB를 보존했다. |
| 직접 trim | F 후 시작 손잡이를 드래그해 source 시작 `8.511421990645559`, 끝 16초, r24. 7.36–16.64초 범위와 절대 커서를 유지했다. 각각 Undo하여 드래그 r25, 끝 입력 r26, 시작 입력 r27 순으로 복구했다. |
| 대상/원본 | 같은 clip의 다른 use로 이동하면 0–32초로 초기화됐다. 다른 use 확대 후 첫 use 복귀도 전체로 돌아갔다. 공유 원본 편집 켜기/끄기 후 오디오로 돌아와 전체 범위와 원래 음악을 확인했다. |
| 저장/재열기 | 첫·두 번째 사용의 그룹 접힘을 UI에서 복원하고 저장·재열기 했다. 이름/global/tracks/sections/arrangements/assets/patterns/signal/portLayout/circleLayout이 최초 baseline과 일치한다. portLayout의 revision만 비교에서 제외했다. 음악 revision은 r27이다. |

최종 앱 검사는 새 Undo 이력에서 시작했다. 중간 후보 종료 후, 그 후보에서 편집한 authored QA 사본만 baseline으로 재설정하고 r18을 유지했다. 재설정 전 manifest를 `before-readable-fixture-reset.json`에 보존했다. 최종 후보의 편집/Undo/저장 복원 검사는 이 초기화 이후 실제 앱에서 수행했다.

## 발견한 문제와 수정

첫 후보 UUID **BE2C6746-E12E-30C9-A1F2-A76A7321AB07**은 버튼/키보드는 동작했지만 `AlbumCanvas`의 local scroll monitor가 파형 이벤트를 먼저 소비했다. hit 대상의 상위 view를 확인해 `OrbitAudioView`로 이벤트를 전달하도록 수정했다. 첫 focus 요청은 접힌 그룹 내부여서 거절됐으며 기존 작업 이동의 오디오 버튼으로 진입했다.

두 번째 후보 `final`, UUID **AB8D3BCA-D6F4-31F8-9969-562B09E8EE7A**에서 실제 휠 동작을 확인했지만, 하단 세 줄 때문에 작은 창의 원형 파형이 작아지고 중앙 시간 표시가 사라졌다. 최종 후보에서는 확대/축소·재생 길이·커서 찾기를 한 줄로 모았다. 화면 밖 선택 정보는 기존 ‘선택 구간’ 버튼의 도움말로 제공한다. 최종 앱에서 위 전체 대표 경로를 다시 수행했다.

## 보존과 남은 범위

원본 `studio.circlr/manifest.json` SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**와 두 tone 파일 checksum을 유지했다. root/ports HEAD와 사용자 앱 **0.19.0 build 21**을 보존했다. 이번 QA 앱 3개는 모두 정상 종료했다. 원시 오디오·프로젝트·앱·화면은 Git에 올리지 않는다.

세로 휠 native 입력은 확인했다. CUA가 modifier를 유지한 wheel을 제공하지 않아 Shift+wheel과 가로 hardware wheel, trackpad의 연속 gesture 감각은 소스 검토 범위다. VoiceOver 발화, 오래된 객체에 이벤트를 주입하는 경쟁, 드래그 도중 화면 변경 경쟁은 native 미검증이며 현재 대상 identity/viewport/layout/bounds guard를 읽기 전용으로 검토했다. legacy 오디오 lane의 확대 기능은 이번 변경 대상이 아니다.

출력/audition 장치 획득 시도는 **0회**이며 실제 마이크·MIDI 입력·재생·MP4 검증을 시작하지 않았다. 기존 HAL 출력 지연과 출고 조건, 전체 DAW·아티스트 세계관 목표는 진행 중이다.
