# Circlr MCP

Python 표준 라이브러리만 사용하는 로컬 stdio MCP 서버다. 음악 편집·렌더는 실행 중인 써클러의 Core/Audio로 전달한다. 화면 클릭, 브라우저, 터미널 창 조작은 필요하지 않다.

## 연결

써클러 앱을 실행한 다음 MCP 클라이언트에 루트의 `.mcp.json` 설정을 등록한다. stdio 명령은 `/usr/bin/python3 /Users/sungwoonjeon/Documents/ChatGPT/circlr/mcp/server.py`다. 이 설정 파일을 작성한 것만으로 이미 실행 중인 Codex의 도구 목록이 자동 갱신되는 것은 아니다.

기본 소켓은 `~/Library/Application Support/circlr/Agent/agent.sock`이다. 검증 앱에는 `--socket` 또는 `CIRCLR_SOCKET`으로 `~/Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock`을 지정한다. 폴더 권한은 0700, 소켓 권한은 0600이고 앱은 연결한 프로세스의 UID도 확인한다.

## 에이전트 작업 흐름

1. `circlr_snapshot`으로 projectID, revision, arrangement/use/track ID를 읽는다.
2. `circlr_inspect`로 대상 섹션의 실제 lane, notes, node, connection ID를 읽는다.
3. `circlr_apply`에 projectID, expectedRevision, operations를 전달한다. 한 batch가 한 Undo 단위다. 다른 편곡의 편집도 사용자의 캔버스 선택을 이동시키지 않는다.
4. `circlr_bounce` 또는 `circlr_export`는 jobID를 즉시 반환한다. `circlr_job`으로 완료 상태를 확인한다. 도구 호출 성공은 렌더 완료를 뜻하지 않는다.
5. `circlr_events`로 sequence 이후의 실제 로그를 읽는다. 렌더 취소는 `circlr_stop`이다. 작업 중 문서가 바뀌면 이전 snapshot의 결과를 적용하지 않는다.
6. `circlr_save`로 미디어를 포함한 프로젝트를 저장한다. 원본 복원은 `circlr_restore_bounce`다.

`circlr_open`도 jobID를 반환한다. `circlr_job`의 completed를 확인한 뒤 `circlr_snapshot`으로 새 projectID/revision을 읽는다. macOS가 앱의 문서 폴더 접근을 처음 요청하면 사용자가 시스템 창에서 허용해야 한다. 파일을 읽는 동안에도 상태 조회와 정지는 동작한다. 취소한 열기 요청이 나중에 문서를 교체하지 않는다.

`apply`의 `generate_midi` 및 `set_notes`는 기본적으로 해당 lane의 노트를 교체한다. 추가하려면 `append: true`를 지정한다. GUI 콘솔의 `midi arpeggio` 명령은 안전하게 추가 모드를 사용한다. MIDI 노트 JSON에는 beat, length, pitch, velocity가 필요하며 ID를 생략하면 새 ID가 발급된다.

`set_step`은 `useID`, `laneID`, `stepIndex`(0부터), `pitch`, `enabled`로 일반 MIDI 노트를 편집한다. `subdivisions`는 4분음표당 1/2/3/4/6/8칸이며 기본 4다. `velocity` 1–127, `gate` 0.01–16칸은 선택 항목이다. 이미 켜진 셀을 다시 켜면 ID·타이밍·길이를 유지하고 지정한 값만 바꾼다. `nodeID`를 넣으면 그 MIDI 서클의 개별 길이를 사용하며 lane이 일치해야 한다. 같은 칸에서 시작한 같은 음높이 노트들은 함께 편집하고, 이전 칸에서 시작해 유지되는 노트는 지우지 않는다. MCP는 현재 use의 변형을 편집한다. 공유 원본 편집은 GUI 설정에서 선택한다.

`set_instrument`는 `synthVoice` 정수로 내장 음색을 선택할 수 있다: 0 pad, 1 bass, 2 keys, 3 supersaw, 4 pluck, 5 lead, 6 electricPiano, 7 organ, 8 brass, 9 strings. `add_effect`는 오디오 `from` 서클 뒤에 이펙터를 삽입한다. `connect`는 MIDI/audio 연결, `connect_sections`는 송폼 재생 연결이다. 로컬 tempo/meter 등은 `set_node`/`set_section`의 `settings`로 지정한다.

창을 숨기고 작업하려면 `circlr_focus`에 `minimized: true`, 다시 표시하려면 `minimized: false`를 보낸다. 이 경우에는 창 상태만 바뀐다. `snapshot.runtime.windows`로 실제 최소화 상태를 확인할 수 있다.

## 현재 API 경계

0.11의 `circlr_focus`는 `{"follow": true}`로 재생 팔로우를 켜거나 재개하고 `{"follow": false}`로 끈다. 다른 focus 대상이나 minimized와 함께 보내면 거부한다. `snapshot.playback`은 playing, seconds, follow(`off`/`following`/`suspended`), currentSection, focusedSection, caption, stale, animated, camera와 node/edge/phase readout을 제공한다. `seconds`는 실제 재생 시간이고, `displaySeconds`와 신호 값은 마지막 표시 프레임 기준이다. 최소화 중에는 표시 값과 frameCount가 멈추지만 재생 시간은 계속 진행한다. 카메라를 직접 focus하면 재생 팔로우가 일시 중지되며 음악은 바뀌지 않는다.

- 인터넷에 서버를 공개하지 않는다. 임의의 shell 명령 실행 기능은 없다.
- 에이전트는 사용자가 실행한 앱의 현재 문서를 편집한다. 별도 LLM 계정이나 모델을 앱 안에서 자동 실행하지 않는다.
- open은 미저장 편집이 있으면 거부한다. save는 다른 프로젝트를 덮어쓰지 않는다. export는 새 WAV 경로만 허용한다.
- 입력은 최대 8 MiB, 편집 batch는 128 operations, 이벤트는 최근 500개, 작업 상태는 최근 64개다.
- 연결이 끊겨 쓰기 성공 여부가 불명확하면 snapshot/job을 읽는다. native request를 재전송할 때는 동일 ID와 동일 bytes를 사용한다. 새 ID로 무조건 재실행하지 않는다. 최근 요청 캐시는 앱 재시작 후에는 유지되지 않는다.
- 현재 한 번에 한 렌더 작업을 실행한다. 자동 MIDI 생성·샘플 악기·내장 신스는 외부 플러그인 없이 사용할 수 있다. 하드웨어 녹음과 플러그인 설치는 MCP 도구에 포함하지 않는다.

`snapshot.playback.windowAttached`, `windowVisible`, `windowOccluded`, `meterPlaying`으로 창이 가려져 표시 작업이 멈춘 상태와 실제 음악 재생을 구분할 수 있다. 백그라운드 재생 명령은 사용자의 다른 창을 자동으로 앞으로 밀어내지 않는다.

## 개발 검증

`python3 -m unittest discover -s mcp -p 'test_*.py'`로 stdio handshake, 도구 목록과 입력 검증을 확인한다. 실제 앱과의 end-to-end 검증은 `python3 mcp/native_smoke.py`로 실행한다. QA 전용 socket만 사용하고 매번 새 폴더에 f0r h3r 사본과 로그를 만든다. `--require-minimized`는 작업 전후 창의 최소화 상태도 검사한다. 앱의 macOS 파일 접근은 미리 허용해야 한다.

상세 명령 책임과 실패 처리 계약은 [에이전트 아키텍처](../docs/17-agent-interface.md)에 있다.

[MCP stdio 전송 규약](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)과 [MCP 도구 규약](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)을 기준으로 구현했다.
## 궤도 편집 확장 · 0.10

`inspect`는 `circles`에 각 서클의 `timeline`과 `orbit`을 함께 반환한다. 시간 단위는 초이며 `owner`, `anchor`, `intervals`로 음악상의 부모와 시작/반복 구간을 읽는다. `snapshot.view.layout`은 현재 orbit/freeform 보기다.

`apply`의 기존 `set_node.startBeat`로 MIDI·오디오 소스 시작을 바꾼다. `reorder_section`은 `arrangementID`, `useID`, 선택적인 `to`(이 섹션 앞에 배치)를 받는다. `to`를 생략하면 맨 끝이다. 분기 경로와 손실되는 전환은 거부한다. `set_clip`은 `useID`, `laneID`, `clipID`와 `sourceStart`, `duration`, `startBeat`, `gain`을 받으며 원본 파일 길이를 넘는 trim은 거부한다.

`focus.compositionID`로 곡·악장 서클을 보여줄 수 있다. 편집을 위해 focus할 필요는 없다. `mcp/orbit_native.py`는 별도 QA socket과 `qa/generated/0.10-` 문서에서만 실행되는 실제 명령 검증이다.
