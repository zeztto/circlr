# Circlr MCP

Python 표준 라이브러리만 사용하는 로컬 stdio MCP 서버다. 음악 편집·렌더는 실행 중인 써클러의 Core/Audio로 전달한다. 화면 클릭, 브라우저, 터미널 창 조작은 필요하지 않다.

## 연결

써클러 앱을 실행한 다음 MCP 클라이언트에 루트의 `.mcp.json` 설정을 등록한다. stdio 명령은 `/usr/bin/python3 /Users/sungwoonjeon/Documents/ChatGPT/circlr/mcp/server.py`다. 이 설정 파일을 작성한 것만으로 이미 실행 중인 Codex의 도구 목록이 자동 갱신되는 것은 아니다.

기본 소켓은 `~/Library/Application Support/circlr/Agent/agent.sock`이다. 검증 앱에는 `--socket` 또는 `CIRCLR_SOCKET`으로 `~/Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock`을 지정한다. 폴더 권한은 0700, 소켓 권한은 0600이고 앱은 연결한 프로세스의 UID도 확인한다.

## 에이전트 작업 흐름

1. `circlr_snapshot`으로 projectID, revision, arrangement/use/track ID를 읽는다.
2. `circlr_inspect`로 대상 섹션의 실제 lane, notes, node, connection ID를 읽는다. 포트 기능이 포함된 개발 앱에서는 `circlr_ports`로 명시적 bus와 케이블 배치를 읽는다.
3. `circlr_apply`에 projectID, expectedRevision, operations를 전달한다. 한 batch가 한 Undo 단위다. 다른 편곡의 편집도 사용자의 캔버스 선택을 이동시키지 않는다.
4. `circlr_bounce` 또는 `circlr_export`는 jobID를 즉시 반환한다. `circlr_job`으로 완료 상태를 확인한다. 도구 호출 성공은 렌더 완료를 뜻하지 않는다.
5. `circlr_events`로 sequence 이후의 실제 로그를 읽는다. 렌더 취소는 `circlr_stop`이다. 작업 중 문서가 바뀌면 이전 snapshot의 결과를 적용하지 않는다.
6. `circlr_save`로 미디어를 포함한 프로젝트를 저장한다. 원본 복원은 `circlr_restore_bounce`다.

`circlr_open`도 jobID를 반환한다. `circlr_job`의 completed를 확인한 뒤 `circlr_snapshot`으로 새 projectID/revision을 읽는다. macOS가 앱의 문서 폴더 접근을 처음 요청하면 사용자가 시스템 창에서 허용해야 한다. 파일을 읽는 동안에도 상태 조회와 정지는 동작한다. 취소한 열기 요청이 나중에 문서를 교체하지 않는다.

`apply`의 `generate_midi` 및 `set_notes`는 기본적으로 해당 lane의 노트를 교체한다. 추가하려면 `append: true`를 지정한다. GUI 콘솔의 `midi arpeggio` 명령은 안전하게 추가 모드를 사용한다. MIDI 노트 JSON에는 beat, length, pitch, velocity가 필요하며 ID를 생략하면 새 ID가 발급된다.

`set_step`은 `useID`, `laneID`, `stepIndex`(0부터), `pitch`, `enabled`로 일반 MIDI 노트를 편집한다. `subdivisions`는 4분음표당 1/2/3/4/6/8칸이며 기본 4다. `velocity` 1–127, `gate` 0.01–16칸은 선택 항목이다. 이미 켜진 셀을 다시 켜면 ID·타이밍·길이를 유지하고 지정한 값만 바꾼다. `nodeID`를 넣으면 그 MIDI 서클의 개별 길이를 사용하며 lane이 일치해야 한다. 같은 칸에서 시작한 같은 음높이 노트들은 함께 편집하고, 이전 칸에서 시작해 유지되는 노트는 지우지 않는다. MCP는 현재 use의 변형을 편집한다. 공유 원본 편집은 GUI 설정에서 선택한다.

`edit_notes`는 실제 `useID`·`laneID`·중복 없는 `noteIDs`와 `edit`를 받는다. `transpose`는 `semitones`, `move`·`duplicate`는 4분음표 단위 `beatOffset`, `velocity`는 1–127을 지정한다. `quantize`는 `subdivisions`(기본 4)와 `strength`(0–1, 기본 1), `delete`는 ID만 사용한다. 그룹 이동은 음정·시간 간격을 유지하며 범위를 넘으면 batch 전체를 거부한다. 복제만 새 ID를 만들고, 비선택 노트·오디오는 유지한다. 선택한 MIDI 서클에 개별 길이가 있으면 일치하는 `nodeID`도 지정한다. 실제 변화가 없는 명령은 Undo를 늘리지 않는다.

0.17의 MIDI 파일 가져오기는 GUI의 **⌥⌘I**에서 제공한다. 파일 읽기를 위한 MCP operation은 아직 없다. snapshot의 `selectedNoteIDs`와 `recording`(`midi`·`audio`·`permissionPending`)은 읽기 전용 상태다. 녹음 권한 대기는 `circlr_stop`으로 취소할 수 있다.

0.18의 `edit_audio`는 실제 `useID`·오디오 `nodeID`와 `edit`를 받는다. `split`에는 선택 구간 시작부터의 원본 초 `sourceOffset`, `fade`에는 원본 초 `fadeIn`·`fadeOut`이 필요하다. `duplicate`의 로컬 4분음표 박 `beatOffset`은 선택 항목이며 생략하면 마지막 반복 뒤에 배치한다. `delete`는 해당 서클과 연결을 지우고 asset을 보존한다. 이후 inspect로 새 clip/node ID를 확인한다. 분할 이전의 fade·resample 기준·반복 주기를 보존하며 조각의 추가 fade는 기존 envelope에 곱해진다. 내부 `renderWindow`와 바운스 `familyID`를 직접 쓰지 않는다. [정확한 시간 의미와 제한](../docs/32-audio-editing.md).

0.19의 `set_automation`은 `useID`·`nodeID`·`parameter`(`gain`/`pan`)에 `automationPoints`를 지정한다. 각 점은 로컬 4분음표 `beat`, `value`, 선택적인 `id`·`shape`(`linear`/`hold`)다. gain은 기존 node gain에 곱하는 0–4, pan은 -1–1이다. 점 배열은 해당 파라미터 곡선 전체를 교체하므로 기존 ID·다른 점을 inspect에서 읽고 보존한다. 빈 배열은 삭제, 점 배열 없이 `enabled:false/true`는 데이터 보존 후 적용 해제/재개다. MIDI는 연결된 악기·믹스·출력 서클에서 제어한다. node.startBeat·개별 tempo 또는 부모 tempo map을 따르며, 명시적 lengthBeats가 있을 때만 repeatCount에 따라 곡선도 반복한다. 처음/끝/섹션 잔향은 경계 값을 유지한다. 출력 automation은 pre-output 바운스에서 제외하고 원래 output에서 한 번 적용한다. snapshot의 `automationEditor`는 표시 상태·파라미터·선택 점 ID·표시 박 수를 제공하는 읽기 전용 정보다. Plugin parameter·전역 bus automation은 아직 없다.

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


## 명시적 포트 편집 (개발 브랜치)

포트 QA/개발 앱에서만 지원한다. 먼저 snapshot의 `layoutRevision` 존재를 확인한다. `circlr_ports`의 `node`는 기존 Codable 주소다. 음악 서클은 `{"music":{"arrangementID":"실제 편곡 ID","useID":"실제 use ID","nodeID":"실제 노드 ID"}}`, 섹션은 `{"section":{"arrangementID":"실제 편곡 ID","useID":"실제 use ID"}}`, 사운드 노드/곡은 각각 `{"signal":{"_0":"실제 ID"}}`/`{"composition":{"_0":"실제 ID"}}`다. ID를 만들어내지 말고 snapshot/inspect에서 얻는다.

응답의 `ports`는 실제 descriptor 배열, `connections`의 각 항목은 `{connection, placement, canReconnect, canDisconnect}`다. `connection.from/to`는 `{node, portID}`, `connection.id`는 `{edgeID, from, to}`이며 뒤의 from/to는 logical 주소다. 여러 use가 같은 edgeID를 공유할 수 있으므로 전체 id를 재사용한다.

| 도구 | revision 외 필수 인자 | 실제 동작 |
| --- | --- | --- |
| `circlr_connect_ports` | first, second, firstOctant, secondOctant | 호환되는 OUT과 IN 연결. IN 시작도 가능 |
| `circlr_reconnect_ports` | 위 인자와 connectionID | 기존 edge ID·gain을 유지하며 두 끝 교체 |
| `circlr_disconnect_ports` | connectionID | 해당 케이블 하나 해제 |
| `circlr_move_ports` | moves: `[{id, placement:{from,to}}]` | 기존 케이블 1–128개의 둘레 위치만 변경 |

위 쓰기는 모두 `projectID`, `expectedRevision`, `expectedLayoutRevision`을 요구한다. octant는 0=위부터 시계 방향 0–7이며 음악 bus가 아니다. `firstOctant`/`secondOctant`는 지정한 first/second에 대응한다. layout의 from/to는 정규화된 OUT/IN이다. 라우터의 `in.audio.bus1/bus2`, `out.audio.bus1/bus2`를 명시하고 단일 main bus를 추정하지 않는다. sidechain은 실제 `in.audio.sidechain`을 선택한다.

연결 중복은 `changed:false`이며 기존 배치도 유지한다. 이동 no-op도 Undo/revision을 추가하지 않는다. `circlr_undo`에 두 최신 revision을 모두 전달하면 layout 전용 변경도 충돌을 검사하며 한 명령을 되돌린다. batch의 한 항목이라도 실패하면 전체를 유지한다. 쓰기 실패 응답에도 현재 revision/layoutRevision을 제공한다.

`ports`는 읽기 전용 specialist에 허용되며 네 가지 쓰기는 차단된다. 앱 최소화와 무관하게 동작하며 선택이나 카메라를 이동하지 않는다. 그룹 alias는 [그룹 노출 포트](../docs/36-group-ports.md)에 설명한다. Audio Unit의 임의 다중 bus는 아직 제공하지 않는다. composition 순서 연결은 reconnect/disconnect 대신 순서 편집을 사용한다.

그룹 포트는 `circlr_set_group_port`/`circlr_remove_group_port`로 관리한다. node는 group 주소, target은 내부 실제 endpoint다. 두 명령 모두 project/music/layout revision을 요구하며 음악은 유지한다. 반환 portID를 connect/reconnect에 사용하고, 기존 ID의 target을 바꿀 수는 없다. [정확한 요청·Undo·미해결 대상 계약](../docs/36-group-ports.md#mcp). `circlr_focus`의 node 주소로 그룹을 바로 보여줄 수도 있다.

0.20의 `circlr_record`는 현재 선택한 섹션·트랙의 실제 오디오 녹음을 시작한다. 사용자가 입력 녹음을 요청했을 때만 사용하며 `projectID`·`expectedRevision`이 필요하다. macOS 마이크 권한 선택은 사용자에게 맡긴다. snapshot.recording의 phase/busy/seconds/peak/format/message/recoveryPath로 실제 상태를 확인한다. STOP 뒤에도 파일 마무리는 비동기이므로 busy=false와 실제 새 take를 확인하기 전 재시도하지 않는다. 장치의 첫 두 채널(모노는 1채널)을 기록하며, 반주 transport 동기·latency 보정·장치 채널 선택은 후속 범위다. read-only 전문 역할에는 이 도구가 노출되지 않는다. 통합 개발 adapter의 전체 catalog는 22개다.
