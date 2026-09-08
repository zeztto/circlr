# 직접 연결 편집 · C1 검증

2026-09-08, `codex/eight-direction-ports`, 시작 commit `b915ef9`. macOS 26.5.1 Apple Silicon. 이 기록은 같은 캔버스의 직접 연결 편집기와 라우터 편집을 검증한 C1 결과다. 전체 C/D/E 완료나 사용 앱 출고를 뜻하지 않는다.

## 변경과 검토

- `CircleConnectionEditing`이 실제 port ID를 정규화해 music/signal/section 연결을 처리한다. 재연결 성공 전까지 기존 graph를 유지하며 edge ID·gain·송폼 전환을 보존한다. 순환·중복 대체·다른 use·삭제된 원본을 거절한다. composition은 순서 이동이며 일반 케이블 해제/재연결을 표시하지 않는다.
- `CircleHistory`와 AppStore Undo entry가 배치만의 기록을 구분한다. 배치 Undo는 현재 음악을 보존하고 layout revision을 증가시킨다. 일반 음악 Undo와 섞여도 배치 revision을 과거 값으로 돌리지 않는다.
- 연결 버튼·L은 같은 캔버스의 편집기를 연다. 대상 검색·실제 IN/OUT 선택·8방향 위치·기존 케이블의 재연결/해제를 직접 제공한다. 폭 660 이상은 두 열, 그보다 좁으면 스크롤되는 한 열이다. 별도 창이나 고정 좌우 패널을 만들지 않는다.
- 라우터 생성·경로 탐색과 2×2 전송량을 제공한다. 슬라이더는 편집 종료 때 적용하며 숫자는 Return/포커스 이동 때 한 번 적용한다. 0…4의 유한값만 받으며 Escape는 입력을 되돌린다. 선택 경로의 텍스트 대비를 개선했다.
- 최종 케이블과 playback overlay가 같은 8방향 곡선을 사용한다. 새 연결은 그린 포트와 같은 hit 목록을 사용하고 IN 시작을 지원하며 project/music/layout revision 변경을 검사한다. 이 새 드래그 경로는 빌드·소스 검토까지 했고 native gesture 검증은 C2에서 수행한다.

독립 review agent를 요청했으나 `agent thread limit reached`로 거절됐다. 아래 코드·입력 검토는 구현자와 같은 에이전트가 read-only 역할로 수행했다. Core candidate의 최종 validation과 대입 순서, stable port ID·같은 scope 확인, 삭제/순환 실패의 무변경, 배치-only history, 숫자의 유한값/범위, 전용 QA 저장소 분리를 검토했다. 새 외부 API·임의 경로·권한·shell 실행은 추가하지 않았다. 독립 코드 리뷰를 받았다고 주장하지 않는다.

## 자동 검사와 빌드

- 신규 Core 6개: 역방향 연결/중복 no-op, 재연결 ID·gain·다른 bus 보존/순환 atomic 거절, 없는/다른 use edge의 거절과 정확한 해제, 음악·배치 혼합 history, 송폼 전환/선택 분기 보존, 전역 sidechain 정규화/해제.
- 전체 offline Swift **178개**, 실패 0, **17.595초**. B의 172개 + 신규 6개다. 하드웨어 의존 `testArrangementRenderExportAndPlayback`만 제외했으며 녹음 branch의 검사 수와 합산하지 않는다.
- Python MCP **13개**, agent kit **9개** 통과. 외부 MCP schema·배포 kit는 이번에 변경하지 않았다. QA helper의 Python compile도 통과했다.
- 최종 release build **20.13초**, warning/error 없이 완료. source binary와 전용 QA 앱 UUID는 **3B25A96F-D90E-3105-BC07-DE8C41E20F2D**다. 패키지의 deep/strict codesign verification을 통과했다.
- 최종 로그: `qa/generated/ports-foundation/ports-c-verified-tests.log`, `ports-c-python-mcp.log`, `ports-c-python-kit.log`, `ports-c-numeric-fix-build.log`.

## 실제 앱 검증

전용 앱은 `qa/generated/ports-ui/써클러 포트 검증.app`, bundle ID는 `com.circlr.portsqa`다. 전용 Application Support의 fixture·socket·recovery를 사용한다. 기존 녹음 QA와 사용자 앱의 저장소를 사용하지 않는다. fixture는 이미 승인된 QA 사본에서 별도로 복사했으며 실제 마이크 녹음이나 음악 재생을 시작하지 않았다.

| 시나리오 | 관찰한 결과 | 로컬 증거 (`qa/generated/ports-ui/`) |
|---|---|---|
| 연결 버튼/L · 직접 편집 | 같은 캔버스에서 대상·위치·기존 연결을 조작. 초기 세로 배치의 하단 가림을 발견해 넓은 화면의 두 열과 다크 메뉴로 수정 | `connections-first.jpg`, `connections-compact.jpg` |
| 위치만 이동·Undo·Redo | OUT 북쪽 이동은 music revision 113 유지, layout 1. Undo는 원래 graph 유지와 layout 2. Redo 후 북쪽 위치 복원 | `native-before-layout.json`, `native-out-north.json`, `native-layout-undo.json` |
| 각 끝점 8방향 | OUT과 IN 각각 8개 방향을 메뉴로 선택. 최종 NW/NW, layout 26, music 113과 원래 graph 유지 | `eight-out-directions-ax.json`, `eight-in-directions-verified.json`, `native-eight-directions.json` |
| 저장·재열기 | 최종 양 끝의 NW가 재열기 후에도 표시 | `reopened-layout.txt` |
| 라우터 생성·포트 연결 | 앱 생성 메뉴로 라우터 생성. OUT 1→출력과 IN 1에서 시작한 오디오 source 연결이 실제 port ID로 저장됨 | `native-router-connected.json` |
| 슬라이더·Undo | 한 번 클릭한 전송량 적용 116→117, Undo 118에서 116의 graph와 정확히 일치 | `native-router-slider-undo.json` |
| 숫자 입력 수정 | 초기 formatted binding에서는 2 입력이 1로 되돌아가고 118→121의 복수 revision이 생김. 문자열 draft 분리 후 2+Return이 정확히 121→122 한 번 적용 | `native-numeric-first.json` (실패), `native-numeric-fixed.json` (수정 후) |
| 잘못된 숫자·한 번의 Undo | 9+Return은 graph/music 122 유지. Escape 후 CmdZ 한 번으로 전송량 1과 121 당시 graph를 복원, music 123 | `native-numeric-invalid.json`, `native-numeric-undo-final.json`, `router-numeric-final.jpg` |

초기 IN 방향 자동화의 로깅 closure가 이전 배열을 참조하여 `eight-in-directions-ax.json`은 빈 배열이다. 이것을 성공 근거로 쓰지 않는다. 직접 배열에 기록하는 루프로 재수행한 `eight-in-directions-verified.json`의 8개 기록과 최종 manifest를 확인했다. 그래서 layout revision은 방향 개수보다 더 증가했다.

연결/배치 UI의 compact 빌드는 UUID `AAAD7BB5-39EA-3A06-B92F-06DA46392F83`, 잘못된 숫자 입력 빌드는 `84B86AFE-DC17-3A59-8F1A-F98090FB7C11`로 보존했다. 최종 숫자 검증은 위 `3B25A96F-…` 앱에서 수행했다. 숫자 필드 수정 외 연결 코드가 같은 마지막 빌드를 성공한 전체 검사와 대조했다. 이전 실패 빌드/화면을 최종 성공으로 계산하지 않는다.

## 남은 검증과 개발

- C2: 케이블 선택, 끝점 드래그 재연결, 명시적 위치-only drag. 새 연결의 native 8방향 drag, 취소·삭제·stale·잘못된 대상과 한 gesture 한 Undo 검증. router의 캔버스 포트는 아직 일반 IN/OUT 라벨이므로 IN 1/2·OUT 1/2 식별을 보완한다. 임시 드래그 선도 방향별 곡선으로 교체한다.
- C3: 여러 작은 창 크기, 축소·접기·시간 손잡이 충돌, 키보드 전체 작업과 실제 VoiceOver 발화, 슬라이더의 연속 drag 검증. 직접 편집기의 AX label을 확인한 것과 canvas port 개별 접근성을 구분한다.
- 실제 routing PCM은 port별로 분리되어 있으나 현재 bus의 화면 envelope는 node 합계 기반이다. 연결선별 실제 bus envelope는 후속이다.
- D/E: 명시적 port MCP·layout revision 외부 명령, 그룹의 exposed binding, 녹음 branch 통합, v4 전체 WAV 재확인, 실제 장치/MP4와 앱 출고 검증.

사용 앱과 main은 0.19이고 녹음 0.20 branch는 별도다. QA 앱 실행은 이전 승인 범위에서 수행했으며 실제 입력 녹음 승인 대기와 무관하게 진행했다. source checkpoint에는 소스·문서·테스트·helper만 포함한다. QA 앱·fixture 프로젝트·WAV·스크린샷·로컬 로그·인증정보는 업로드하지 않는다.

## 재현

```sh
swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback
swift build -c release --product circlr --scratch-path .build/ports-release
python3 -m unittest discover -s mcp -p 'test_*.py'
python3 -m unittest discover -s qa -p 'test_agent_kit.py'
```

`python3 qa/verify-ports-native.py <새로운-증거-이름> [--save]`는 실행 중인 정확한 port QA bundle과 `~/Library/Application Support/circlr-ports-qa/fixtures/ports.circlr` 경로를 검사하고 snapshot·선택 graph를 저장한다. `--save`는 이 fixture만 저장하고 manifest를 함께 기록한다. 기존 증거 이름 덮어쓰기를 거절하며 playback/recording을 시작하지 않는다. 해당 fixture를 열지 않았거나 녹음 중이면 실행하지 않는다.
