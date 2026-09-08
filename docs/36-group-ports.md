# 그룹 노출 포트

개발 브랜치의 그룹은 같은 그래프 안의 서클을 모으는 배치 컨테이너다. 그룹 IN/OUT은 사용자가 고른 내부 포트를 가리키는 명시적 alias이며, 새 악기·버스나 다른 section clock으로 향하는 audio bridge를 생성하지 않는다.

## 같은 캔버스에서 사용

그룹 선택 → **연결 / L**을 누른다. 아직 노출 포트가 없으면 내부 포트 관리가 바로 열린다. 내부 서클·포트 이름으로 검색하고 실제 IN/OUT을 선택한 뒤 이름을 입력해 **포트 노출**을 누른다. 새 포트가 선택된 연결 편집으로 이동한다. 그룹을 펼쳐 내부 노드까지 탐색할 필요가 없다.

**노출 포트 관리**에서 현재 포트의 이름·내부 대상·신호를 읽고 이름을 바꾸거나 노출을 해제한다. 없어진 내부 대상은 ‘대상 없음’으로 표시하고 새 연결 후보에서 제외한다. 노출 해제는 내부 노드와 음악 케이블을 유지한다. 다른 target으로 바꾸려면 기존 이름표를 재사용하지 말고 새 포트로 노출한다.

그룹의 포트도 클릭/P 선택, IN 또는 OUT 시작 드래그, 8방향 배치, K 케이블 탐색, Return 연결 편집을 사용한다. 접힌 그룹의 경계에서는 노출한 포트 이름과 실제 케이블을 표시한다. 내부끼리 연결된 선은 접으면 숨기고, 펼치면 원래 내부 endpoint를 표시한다. 노출하지 않은 기존 경계 케이블은 접힌 외곽 표시를 유지하며 자동 binding으로 바뀌지 않는다.

편집기의 연결 적용 버튼은 상단에 있다. Tab은 검색 → 대상 → 두 방향 → 적용 순서로 이동하며 필요한 항목을 화면 안으로 스크롤한다. 포트 관리의 검색·내부 대상·이름·노출 버튼도 같은 키보드 경로를 제공한다.

## 의미와 보존

- 하나의 alias는 하나의 실제 내부 endpoint를 가리킨다. IN/OUT·audio/MIDI/flow·합산/분기 정책과 sidechain 역할을 내부 포트에서 읽는다. 같은 포트를 이중 노출하면 기존 ID를 반환한다.
- 스테레오 router의 bus1/bus2는 별개로 노출한다. alias 번호나 둘레 방향이 새로운 오디오 채널을 만들지 않는다. 한 그룹의 포트는 최대 64개이며 실제 케이블 수와 8방향 수는 별개다.
- binding은 선택적 `project.portLayout.bindings`에 저장한다. `{id, group, name, target}`이며 target은 `{node, portID}`다. 각 group/use의 전체 주소로 소유를 구분한다. 이름을 바꿔도 ID와 target은 유지한다.
- 음악 케이블은 원래 logical node/port를 유지한다. alias를 통한 연결 요청은 검증 후 그 endpoint로 정규화하고 기존 GUI/Core 편집을 실행한다. gain·MIDI 시간·컴프레서 detector·router matrix는 원래 엔진 의미를 따른다.
- 포트 노출·이름 변경·노출 해제는 layout revision과 layout 전용 Undo만 바꾼다. 단순 접기·펼치기는 binding을 만들거나 삭제하지 않는다. 기존 프로젝트에 배열이 없으면 노출 포트가 없는 것으로 읽는다.
- 내부 노드/포트가 삭제되거나 다른 그룹으로 이동하면 binding을 미해결 상태로 보존한다. 자동으로 다른 노드에 연결하지 않는다. 해당 alias로 새 연결은 거절하며, 사용자가 노출 해제하거나 Undo로 원래 대상을 복원할 수 있다.

## MCP

기존 explicit-port 도구 외에 `circlr_set_group_port`와 `circlr_remove_group_port`를 추가해 개발 adapter는 21개 도구를 제공한다. 사용자용 0.19 앱에는 이 API가 없다. 실행 앱과 adapter를 함께 확인한다.

`circlr_ports(node)`의 group 주소는 `{"group":{"parent":실제 부모 주소,"id":실제 그룹 ID}}`다. parent는 album/sound/composition/section이며, 섹션 부모는 `{"section":{"arrangementID":실제 편곡 ID,"useID":실제 use ID}}` 형태다. group ID는 inspect의 effective graph/layout이나 저장된 layout에서 읽는다. 임의 ID를 만들지 않는다.

응답의 `bindings`는 저장된 정의 전체, `ports`는 유효한 실제 포트다. 그룹 port descriptor의 `bindingTarget`으로 실제 대상과 비교할 수 있다. `connections`는 유효한 alias를 통해 그룹 밖에 연결되는 logical 케이블이다. 그룹 내부끼리 연결된 선을 외부 연결로 중복 집계하지 않는다.

| 명령 | 필수 인자 | 결과 |
| --- | --- | --- |
| set_group_port | node, target, name, projectID, expectedRevision, expectedLayoutRevision | 새 alias의 portID. 같은 target은 no-op |
| set_group_port 이름 변경 | 위 인자와 기존 portID | 같은 target의 이름 변경 |
| remove_group_port | node, portID, projectID, expectedRevision, expectedLayoutRevision | alias만 제거 |

그룹 endpoint `{node:그룹 주소,portID:alias ID}`는 connect_ports/reconnect_ports에서 그대로 사용한다. 반환되는 connectionID는 정규화된 실제 node 주소다. 연결 배치는 이 logical ID로 이동한다. undo에도 현재 expectedLayoutRevision을 전달한다. 오류·no-op는 다른 음악을 수정하지 않는다.

선택 화면이 필요할 때만 `circlr_focus(node:그룹 주소,detail:true)`를 사용한다. node 주소는 다른 focus selector와 함께 보낼 수 없다. 읽기 전용 specialist는 ports 조회만 사용할 수 있으며 두 새 쓰기도 차단된다.
