# 케이블 드래그 · C2 검증

2026-09-08, `codex/eight-direction-ports`, 시작 commit `f7f9e50`. macOS 26.5.1 Apple Silicon의 전용 `com.circlr.portsqa` 앱으로 검증했다. 주요 케이블 조작의 결과이며 전체 C3/D/E나 사용 앱 출고를 뜻하지 않는다.

## 구현과 검토

케이블 클릭은 해당 선과 양 끝을 선택한다. 같은 캔버스의 작은 도구막대에서 재연결/위치 이동을 명시적으로 고르며 Delete는 선택한 케이블 하나만 해제한다. 양 끝점을 피해서 도구막대를 배치하고 드래그 중에는 숨긴다. 큰 서클뿐 아니라 포트를 표시하는 중간 확대에서도 IN/OUT과 bus 번호를 읽을 수 있다. 선택된 끝점의 글자를 일반 포트 글자와 중복해서 그리지 않는다.

`CircleCableGesture`는 시작 때 논리 edge·양 포트·배치·project/music/layout revision을 캡처한다. preview는 음악을 바꾸지 않는다. 적용 시 원본이 그대로 존재하는지 확인하며 재연결은 C1의 atomic 명령으로 ID·gain·다른 분기를 보존한다. 위치 이동은 원래 서클/포트의 방향만 바꾸고 배치 전용 Undo를 쓴다. 중심에 놓으면 포트를 선택하며 기존 방향을 유지한다. 둘레에서는 가장 가까운 octant를 고른다.

Core revision만으로는 같은 project ID와 revision의 파일을 다시 연 세션을 구분할 수 없다. App의 드래그별 UUID token을 문서 `.restore`와 취소 때 무효화한다. 메뉴를 열어 둔 채 재열기가 완료된 뒤 늦게 선택해도 이전 조작을 적용하지 않는다. 새 연결 경로도 같은 token 확인을 사용한다.

정밀 편집기가 열리기 전에는 선택한 음악 서클의 부모 문맥을 유지해 주변 서클과 케이블을 숨기지 않는다. 마지막 실제 QA 곡에서 이 동작과 기존 음악 보존을 확인했다. 복잡한 궤도에서 이웃 서클의 겹침과 작은 화면의 정보 밀도는 C3의 추가 개선 항목이다.

검토는 추가 agent 슬롯 제한으로 같은 agent가 read-only 역할을 전환해 수행했다. 독립 리뷰로 보고하지 않는다. 입력의 유한 좌표/반경, 정확한 논리 포트·scope, candidate 적용 경계, layout-only history, late callback token과 QA 경로 제한을 검토했다. 새 auth·shell 실행·외부 mutation schema는 없다. 기존 snapshot의 playback 진단에 그려진 포트/케이블과 선택 상태를 읽기 전용으로 추가했다.

## 자동 검사와 최종 빌드

- 신규 Core 4개: 양 끝 재연결·고정 끝의 방향 유지, 8방향 위치 이동·음악 불변·다른 포트 거절, project/music/layout 변경과 삭제된 원본의 atomic 거절, 곡선 거리·잘못된 geometry·중앙 drop 안정성. C1의 6개와 함께 10개이며 중복 계산하지 않는다.
- 전체 offline Swift **182개**, 실패 0, **18.661초**. 하드웨어 의존 `testArrangementRenderExportAndPlayback`만 제외했다. 로그 `qa/generated/ports-foundation/ports-c2-session-tests.log`.
- Python MCP **13개**, agent kit **9개**, QA helper compile 통과. `ports-c2-python-mcp.log`, `ports-c2-python-kit.log`. 기존 외부 MCP schema/kit는 변경하지 않았다.
- 최종 release build **23.51초**, warning/error 없음. `ports-c2-session-build.log`. source binary와 전용 QA 앱 UUID **5CB10195-F78C-39EB-8FBC-E376EB60D048**, deep/strict codesign verification 통과.

## Native 증거

로컬 증거 위치는 `qa/generated/ports-ui/`다. 기존 `ports.circlr`에서 별도 `ports-gesture.circlr`를 복사해 한 QA 섹션만 오디오·라우터 A·라우터 B·출력의 네 서클로 구성했다. 원본 QA 프로젝트·사용자 곡은 변경하지 않았다. 실제 신호 분리/바운스 PCM 검사는 [B 기록](ports-bus-review.md)을 따르며 이번 UI 작업으로 하드웨어 재생이나 녹음을 시작하지 않았다.

| 시나리오 | 확인 결과 | 증거 파일 |
|---|---|---|
| OUT 위치 drag·Undo | 123의 음악 graph 유지, 북쪽 이동 layout 1, Undo 2에서 기본 배치 복원 | `c2-out-north-drag.json`, `c2-position-undo.json` |
| IN/OUT 재연결 | IN 2는 125→126, OUT 2는 126→127 한 번 적용. 원래 edge ID·다른 edge·방향 유지 | `c2-input-reconnect-final.json`, `c2-output-reconnect-final.json` |
| 잘못된 대상·취소 | viewport 밖 drop, 출력 없는 서클로 OUT drop, 포트 메뉴 Esc 모두 graph/revision 127 유지. 호환 오류 안내를 실제 activity에서 확인 | `c2-invalid-drop.json`, `c2-incompatible-drop.json`, `c2-cancelled-menu.json` |
| 한 번의 재연결 Undo | 오류·취소 후 CmdZ 한 번이 마지막 OUT 변경만 복원하고 앞선 IN 2 변경은 유지 | `c2-final-reconnect-undo.json` |
| 양 끝의 모든 방향 drag | OUT 0…7, IN 1…7·0을 실제 드래그하고 각 단계에서 CmdS 후 manifest 방향을 검증. 16회 모두 music 128·동일 graph, layout 5→21 | `c2-out-native-directions.json`, `c2-in-native-directions.json`, `c2-all-directions-final.json` |
| IN에서 새 분기 | IN 1→라우터 A의 OUT 1 선택이 OUT→IN으로 저장. 128→129, 기존 세 edge를 유지한 채 하나 추가 | `c2-input-start-new-branch.json` |
| 선택 케이블 Delete·Undo | 129→130에서 새 edge만 제거, 네 서클·기존 세 edge 유지. CmdZ 131에서 삭제한 ID까지 복원 | `c2-delete-selected-edge.json`, `c2-delete-undo.json` |
| 최종 글자 UI·배치 Undo | 중간 확대와 선택 상태에서 IN/OUT·bus 번호 표시. 132에서 IN의 N→NE 이동·Undo, 음악 불변과 layout 22→23 | `c2-final-build-drag.json`, `c2-final-build-undo.json`, `c2-final-labels.jpg` |
| 원래 복잡한 곡 재열기 | 기존 QA 음악 graph와 revision 123 유지, 다른 문서의 케이블 선택 제거, 주변 연결 문맥 유지 | `c2-original-context-final.json` |
| 같은 파일 재열기 중 늦은 메뉴 | 포트 선택 메뉴를 열어 둔 상태에서 같은 fixture의 open job 완료를 확인. 이전 OUT 2 선택은 거절되고 graph/revision 132 유지 | `c2-menu-reopen-state.json`, `c2-late-menu-rejected.json`, `c2-late-menu-events.json` |
| 새 세션 정상 재연결 | 현재 세션의 OUT 2 선택은 132→133, 한 번의 Undo 134에서 원래 routing 복원·저장 | `c2-session-valid-reconnect.json`, `c2-session-final.json`, `c2-session-final.jpg` |

첫 IN 재연결에서 중앙 drop의 작은 좌표 차이가 남쪽 방향을 만들고 도구막대가 끝점을 가리는 문제를 발견했다. 실패 증거 `c2-input-reconnect-before-fix.json`을 유지한 채 중앙 fallback과 도구막대 회피를 수정했다. 기본 E/W 배치는 저장 entry가 없는 것이 정상이다. 검증 코드의 초기 entry 필수 가정도 수정해 implicit default를 확인했다.

빌드별 native 범위를 구분한다. 초기 위치 검사는 `691F48AA-…`, 중앙 fallback/양 끝 재연결·잘못된 drop/취소는 `9ABC9129-…`, 16방향·새 분기·Delete는 `4FFB3324-…`, 글자와 원래 곡 문맥은 `507AC4B3-…`, 같은 파일 재열기와 정상 재연결/Undo는 최종 `5CB10195-…`에서 수행했다. 이후 변경은 각각 도구막대 숨김, 라벨 표시, 세션 token이며 전체 방향을 매 빌드마다 재수행했다고 주장하지 않는다. 최종 소스의 전체 offline 검사와 release build를 완료했다.

## 남은 범위와 재현

C3에서 작은 창·고밀도 궤도·접힌 그룹과 시간 손잡이의 간섭, 개별 canvas port/케이블의 키보드 선택·VoiceOver 발화, 포트별 실제 envelope를 검증/개선한다. native에서 마우스 버튼을 누른 채 음악·배치를 바꾸거나 대상을 삭제하는 모든 조합까지 검사한 것은 아니다. 해당 데이터 변경의 atomic 거절은 Core 검사, 문서 세션 교체의 늦은 메뉴 거절은 위 native 증거로 구분한다. MIDI·sidechain·송폼의 모든 포인터 조합도 확대 회귀 항목이다. D의 명시적 port MCP·그룹 binding, E의 녹음 branch 통합·v4 전체 WAV·실제 장치/MP4와 출고 gate가 남아 있다.

```sh
swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback
swift build -c release --product circlr --scratch-path .build/ports-release
python3 -m unittest discover -s mcp -p 'test_*.py'
python3 -m unittest discover -s qa -p 'test_agent_kit.py'
python3 qa/verify-ports-native.py <새-증거-이름> --save
```

QA helper는 정확한 port QA bundle과 Application Support의 `fixtures/ports.circlr` 또는 `fixtures/ports-gesture.circlr`만 허용한다. `--save`는 현재 허용된 fixture를 저장하고 그 manifest를 읽는다. 기존 증거 덮어쓰기를 거절하며 재생·녹음을 시작하지 않는다. 검증의 JSON·스크린샷·음원·fixture·앱·로그는 Git 제외 대상이다. 소스·검사·문서·helper만 승인된 private feature branch에 저장하고 main·사용 앱은 0.19를 유지한다.
