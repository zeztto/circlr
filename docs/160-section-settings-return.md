# 섹션 설정과 원래 편집 위치의 왕복

상태: build138 섹션 설정 왕복의 최종 Release·native 검증을 완료했다. 재시작을 포함한 두 독립 감사도 최종 PASS했다. build137의 길이 설정 검증을 이번 왕복 기능의 실행 결과로 세지 않는다.

## 목표와 범위

현재 child MIDI·오디오·오토메이션에서 해당 섹션 설정을 열고, 원래 노드·편집 모드·viewport로 정확히 돌아온다. 같은 캔버스 안에서 설정과 편집을 왕복하며 임의의 첫 MIDI를 선택하지 않는다. build137 native에서 확인한 child MIDI baseline과 새 후보를 비교한다.

상단 global 설정 버튼은 대상이 앨범임을 label로 드러낸다. 섹션 설정은 Option+Command+,로 여닫는 동작을 연결했다. 실제 메뉴·도움말·버튼과 단축키가 같은 대상과 guard를 사용하는지 검증한다.

## 복귀 계약

원래 child 주소와 모드·viewport를 기억하되 프로젝트와 target identity를 확인한다. 설정에서 정상 변경으로 revision이 증가해도 유효한 원래 대상에는 복귀할 수 있어야 한다. 단순 revision 일치만 요구해 정상적인 설정 편집을 막지 않는다.

invalid draft, stale 대상, 삭제된 target, 프로젝트·선택 전환 경계는 검증 없이 과거 상태를 복원하지 않는다. 이름·수치 오류를 해결하지 않은 채 이동하거나 다른 source에 이전 선택을 적용하지 않는다. pitch source가 바뀌었으면 이전 이벤트 index를 지우며 현재 길이에 맞춰 viewport를 clamp한다. 길이 변경 후 존재하지 않는 구간을 복원하는 것을 exact 복귀로 해석하지 않는다.

## 검증 계획

- MIDI 노트·스텝·pitch, 오디오와 오토메이션에서 섹션 설정을 열고 돌아와 주소·모드·선택·viewport를 비교한다. 실행한 모드와 실제 화면 크기를 AX/JPEG에 기록한다.
- 정상 설정 변경 뒤 증가한 revision에서도 원래 child로 복귀하는지, 음악에는 의도한 설정 변경만 있는지 확인한다.
- 잘못된 draft·stale/delete/switch 경계를 검사하고 오류 시 음악과 현재 선택이 보존되는지 확인한다. 직접 native 실행하지 못한 경계는 source 검증으로 구분한다.
- pitch source 변경의 index 해제와 길이 축소에 따른 viewport clamp를 원본 상태의 무조건 복원과 구분해 검사한다.
- 버튼·Option+Command+,·메뉴/도움말의 동등 동작, 앨범 대상 label의 가시성, 저장/재열기 및 기존 설정 Undo 계약을 확인한다.

QA 사본과 no-I/O 환경을 사용한다. 실제 물리 출력·청취·전체 접근성 검증을 주장하지 않는다. 최종 테스트·Release·native 결과는 실행 후 별도로 기록한다.

## build138 결과

최종 `sectionreturn138-final` package.json의 UUID는 `3C275EAA-7F5B-3A64-91D1-A60A3B39B07E`다. accessible Release는 50.20초·warning 0개로 통과했고 workspace 관련 Core 검사 21개도 PASS했다 (`.build/build138-workspace-tests.log`). 첫 Release는 리뷰 수정과 겹친 input modified 오류로 실패했으며 수정 중 후보를 최종 성공으로 세지 않는다.

초기 `sectionreturn138`에서 notes/step/pitch r156 순수 왕복이 정확히 일치했다. step은 5/16 페이지·C5·66스텝 cursor를 확인했다. 최종 후보는 Root AX value를 추가한 범위이며, 최종 native 재검증을 별도로 수행했다.

| 동선 | 결과 |
|---|---|
| invalid 진입/복귀·이름 | r156 진입/복귀와 r166 이름 오류에서 상태 불변·이동 차단 |
| 정상 설정 변경 | draft 20 확정 후 복귀 r157은 해당 target 길이만 변경, Undo r158 |
| 오토메이션·오디오 | pan과 오디오 표시 16–32초의 순수 왕복 r158 일치 |
| source 삭제 | r159 삭제 후 복귀 차단·현재 상태 보존, Undo r160 후 복귀 |
| 길이 축소 | step 페이지 5에서 길이 2마디 r161 적용 후 페이지 2·17스텝의 현재 범위로 복귀, Undo r162 |
| pitch source 변경 | 선택 r163 순수 왕복 후 외부 raw 12288 변경 r164에서 이전 selectedIndex 해제. Undo 두 번 r166은 baseline r156 음악과 정확히 일치 |
| 수동 이탈 | 앨범으로 나간 뒤 same-section 복귀 단축키는 r166 상태를 변경하지 않음 |
| 재시작 | r166 전체 manifest·hierarchyView 정확히 일치 |

UI·artifact 독립 감사는 재시작 증거 추가까지 완료해 최종 PASS했다. mixed-process 도구 연결 실패 캡처는 제외하고 세션 reset 후 최종 검증을 다시 수행했다. 이를 제품 결함으로 기록하지 않는다. 소스·QA 앱은 동결하고 종료했다. 실제 hardware·VoiceOver·IME와 다른 document의 중복 ID 시나리오는 native 미검증 범위다.

`SectionSettingsReturnState`는 세션 내 임시 상태다. 재시작 검증은 저장된 편집 view가 동일하게 복원되는지 확인한 것이며, 설정 왕복 ticket을 세션 사이에 영구 보존한다는 의미는 아니다.
