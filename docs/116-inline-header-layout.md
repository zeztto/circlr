# 좁은 편집기 header 배치

상태: build101 final2 Release37.87초·아래 native 및 checker 대조 통과. 초기 후보 실패와 최종 증거를 구분한다.

## 원인과 배치 계약

폭591px에서 이름·모드·녹음·부모 이동을 한 줄에 배치하면 header가 넘쳐 끝 동작이 잘린다. 안정된3개 그룹 Layout으로 넓은 폭은 한 줄, compact는 이름+actions 첫 줄·modes 둘째 줄로 배치한다.

새 메뉴를 추가하지 않고 기존 동작을 직접 노출한다. 폭 전환 시 view identity·이름 초안·native focus를 유지한다. 표시 배치만 변경하며 이름 확정/취소나 모드·녹음·부모 이동의 의미를 바꾸지 않는다.

## 검증 기준

1. 591px와 넓은 폭에서 이름·모드·녹음·부모 이동이 잘리지 않고 기존 동작에 접근한다.
2. compact/wide 왕복에서 이름 초안과 native focus를 보존하고 확정·취소를 검사한다.
3. 모드·부모 이동과 필요한 음악/revision·선택 보존을 확인한다. 녹음 버튼 노출을 실제 녹음 성공으로 계산하지 않는다.
4. 최종 Release·native·QA 근거의 범위만 완료로 기록한다. 사용자 앱·물리 출력 조건은 유지한다.

## 후속 native 조사 후보

소스 감사에서 `AudioWorkspace:108–125`의 한 줄 조작과145–175의 고정4열 입력이 compact591px에서 잘릴 가능성을 확인했다. 실제 재현 후 responsive 범위를 정하고 trim 초안·Undo 보존을 검증한다.

`PortConnectionsEditor:111–117`은 폭800 미만에서 compose 높이340 뒤 기존 연결 목록이 낮은 viewport에 숨을 가능성이 있다. 실제 재현 후 reconnect 대상 reveal·기존 연결 목록 직접 이동을 검토한다. 두 후보 모두 아직 native 재현하지 않았으며 현재 결함으로 확정하지 않는다.

## 초기 후보 실패와 후속 수정

초기 candidate의 직사각형 폭591·끝806이 원형 상단 chord 약797을 넘어 실제 잘림이 남았다. 초기 잘림은 대화 중 native 관측으로 확인했으며 보존된 이미지 근거는 없다. `qa/generated/header-compact/final/compact.png`는 빈 새 앨범 화면이므로 초기 실패 증거로 사용하지 않는다.

final2는 Orbit header에 수평16 여백을 추가해 가용 폭559로 줄이고, group help를 제거해 `NativeNameField`의 기존 help를 복원한다. 최종 빌드와 실제 재검증 결과는 아래와 같다.

## 최종2 검증 범위

Release37.87초, UUID `D0CD2CF6-964B-328D-B85A-72935E68A3C3`. `loaded-compact.png`에서 실제 두 줄 header의 양끝이 온전함을 확인했다. `final2/compact.png`는 초기 CUA 중복 bundle 실행 관측으로 제외한다. 최종 성공 이미지 근거는 loaded-compact·name-wide·name-roundtrip·parent로 한정하며 시각 검토도 통과했다.

`name-wide`·`name-roundtrip` PNG/AX에서 같은 한국어 초안과 focus를 유지했고 Esc로 기존 이름을 복원했다. automation 클릭의 instrument 자동 전환은 기존 동작이다. settings/connections 직접 접근, MCP focus로 MIDI 복귀 후 실제 상위 축소 버튼의 section 이동을 확인했다.

checker7개 상태·초안AX2개·음악 revision36 불변·자산2개·original fixture SHA 보존과 parent/reopened/disk strict 일치·completed open job을 확인했다. physical0이며 검증 앱 종료 후 기존 사용자 PID86114를 유지했다.

실제 녹음 busy/takes 조합·IME 조합·모드 Tab 순서는 검증하지 않았다. 기존 source guard 보존을 이 native 조합의 성공으로 확대하지 않는다.

두 줄 header는 body 높이를 줄이므로 기존 스크롤이 필요하다. build101에서 body 하단 스크롤은 별도로 검증하지 않았으며 build100 결과를 이번 완료 범위로 확대하지 않는다.
