# 모든 MIDI 모드의 파일 작업 흐름

상태: build136 공통 파일 작업·수치 확정 개선과 아래 실행 범위의 Release/native 검증을 완료했다. 최종 원본 음악 복구·artifact 독립 감사도 PASS했다. [build135 표현 편집 검증](157-pitch-bend-edit-and-export.md)을 유지하며 파일 작업의 접근성과 작은 화면 배치를 개선한다.

## 확인한 불편과 목표

build135의 pitch bend 모드에는 파일 가져오기·저장·바운스 진입이 없어 노트 모드로 돌아가야 한다. 파일 작업과 노트 생성 메뉴도 섞여 있고 `MIDIWorkspaceActions` 전체 HStack은 개별 동작군 단위로 줄바꿈하지 못한다. 작업 대상이나 편집 모드를 바꾸는 우회 없이 현재 연주에서 파일 작업을 시작하는 것이 목표다.

모든 MIDI 모드에 공통 가져오기·MIDI 저장·오디오 바운스와 tail 설정을 직접 제공한다. 생성 작업은 파일 작업과 식별 가능한 동작군으로 배치한다. 한 줄 전체를 고정하지 않고 개별 그룹이 줄바꿈하며 실제 1019×768 창·122pt 콘솔에서 최대 두 줄을 목표로 검증한다. pitch bend plot 72pt와 필요한 수치 입력 공간을 유지한다. 버튼 추가를 위해 표현 편집 영역을 과도하게 줄이지 않는다.

## 실행과 키보드 계약

Option+Command+I/E/B의 가져오기·저장·바운스 진입을 메뉴·command palette·도움말과 일치시킨다. 같은 명령이 모드마다 다른 대상을 사용하거나 이름만 있는 비동작 항목이 되지 않아야 한다. 사용 가능 조건과 잠금 이유도 실제 실행 guard와 일치시킨다.

현재 이름·수치 편집의 확정/취소 계약을 존중하며 잘못된 초안을 파일 작업이 우회하지 않도록 한다. import에서도 이름 resolve를 거쳐 확정하도록 구현했다. build136 첫 검증 패키지(`fileactions136`)에서 raw 8192를 draft 12288로 바꾼 뒤 Return 없이 Save를 누르면 r126의 기존 raw 8192가 파일에 저장되는 문제를 재현했다. raw SMF 감사에서도 8192를 확인했다. 수정 계약은 main window의 실제 activeNumericField를 먼저 resolve하고 invalid/stale 입력을 차단한 뒤, 갱신된 revision과 scope 일치를 확인하여 새 file/job request를 만드는 것이다. 다른 window의 binding은 호출하지 않는다. 이는 다른 window에서 명령 자체의 가용성을 바꾸는 계약은 아니다. 수정 후 실제 파일의 raw 12288 저장과 invalid/stale 차단을 아래 최종 검증에서 확인했다.

현재 project·revision·선택 scope를 확인한 뒤 작업하며 stale 대상에 실행하지 않는다. 가져오기 취소의 원래 workspace 복귀, 확정된 연주의 파일 저장은 음악 불변이며 유효한 초안은 파일 창 이전에 한 번 commit하는 동작, 바운스 적용과 Undo·원본 복원 계약을 유지한다. 공유 원본과 이번 use를 혼동하지 않도록 실제 대상 범위를 표시한다. 녹음·재생·진행 job의 잠금과 기존 오류 경계를 별도 우회 경로로 열지 않는다.

## 검증 계획

1. 실제 네 가지 MIDI 작업 화면에서 가져오기·저장·바운스 진입과 tail 접근을 확인한다. 각 화면의 이름·주소·공유 여부를 증거에 기록하고, 같은 캔버스의 현재 모드를 유지하는지 비교한다.
2. 미리보기·파일 대화상자 취소 전후 음악·revision·선택과 전체 hierarchyView를 대조하고 AX/JPEG로 화면 복귀를 확인한다. 성공한 가져오기는 새 target 선택 계약을 별도로 검사한다.
3. 실제 MIDI 파일 저장 결과와 오디오 바운스·원본 복원·Undo를 검증한다. 일반/공유 source의 범위 및 다른 use의 보존을 확인한다. 파일 생성 성공을 실제 청취 성공으로 계산하지 않는다.
4. Option+Command+I/E/B, 메뉴, command palette와 도움말의 동등 동작을 실제 실행한다. 숫자·이름 오류, 잠금, stale 취소와 pending 초안의 처리 결과를 기록한다. 실행하지 않은 잠금 경계는 source 검증으로 구분한다.
5. 1019×768·122pt 콘솔에서 최대 두 줄의 개별 그룹 배치, plot 72pt, 수치 가시성·Tab/Shift-Tab·Escape·마우스와 스크롤을 AX/JPEG로 대조한다. 접근성 전체 완료나 다른 화면 크기 통과로 확대하지 않는다.

앱 실행과 검증은 QA 사본에서 수행하며 사용자 원본 앱을 보존한다. 실제 소스·테스트·패키지·native 결과는 완료 후 추가하고, 현재 문서에 예상 성공 수치를 넣지 않는다. 물리 오디오·청취와 전체 DAW 완성은 별도 조건이다.

## build136 최종 검증

최종 Release는 warning 없이 49.06초에 통과했다 (`.build/build136-final-release.log`). `NumberEditSessionTests` 8개와 `MIDIPitchBendEditingTests` 5개, 총 13개가 PASS했다 (`.build/build136-focused-tests.log`). 이들은 Core 테스트이며 816개 전체 회귀는 build135의 이전 결과다. build136에서 전체 회귀를 재실행했다고 주장하지 않는다. 최종 패키지 기록은 `qa/generated/midi-import-return/fileactions136-final/package.json`, UUID는 `1EF87570-C3C1-36E7-A93F-82FD9C9909A1`다.

| 항목 | 실제 실행 결과 |
|---|---|
| 네 가지 MIDI 모드 배치 | 1019×768·122pt 콘솔에서 직접 파일 버튼과 tail 가시성 확인. pitch는 두 줄·plot 약 76px이며 수치 viewport를 가리지 않음 |
| 수치 확정 후 실제 저장 | raw 8192→draft 12288을 Return 없이 저장해 r126→127. SMF beat 3의 raw 12288을 감사함 |
| invalid 입력 차단 | 16384 직접 저장, 12288.5 단축키 저장, 빈 값 가져오기와 잘못된 값 바운스 차단. Undo로 r128 복귀 |
| 이름 확정 | 잘못된 이름에서 Option+Command+I 차단 |
| 취소 복귀 | pitch import 취소 r128 전체 workspace 일치, piano/orbit export 취소와 step 직접 import 취소 상태 일치 |
| 바운스 | Option+Command+B로 CPU 바운스 r129→원본 복원 r130→Undo 두 번 r132 |
| stale 수치 | 외부 shared seed 변경 r133 이후 이전 draft 거절, Undo r134 |
| 저장·재시작 | r134 음악·전체 hierarchyView·선택 일치. native UI 독립 감사 PASS |
| 이번에 실행하지 않음 | 새 MIDI의 실제 성공 import, shared export, 모든 모드의 바운스 전체 실행. 기존 build135 계약은 소스 검토로 확인했으며 새 실행 증거로 세지 않음 |

저장 SMF SHA256은 `fc0da3381296589e2e04ec59f86d2db01160ef1c0c3386dd0e232769b7e6ff91`이다. 초기 step의 빠른 취소→단축키 연속 조작에서는 패널이 열리기 전 Escape가 캔버스를 축소하는 QA 실패가 있었다. fresh 상태의 직접 재검사는 PASS했으나 모든 빠른 연속 조작이 통과했다고 주장하지 않는다. 물리 I/O·청취·AU는 이번에 검증하지 않았다.

`independent-artifact-audit.json`의 최종 감사도 PASS했다. baseline r126과 r128/r132/r134의 음악은 revision·hierarchy를 제외하고 정확히 같았으며 재시작 전후 r134의 전체 manifest·선택도 일치했다. 원본 복원 r130은 archive node/lane/position/asset 각각 1개를 제외하면 baseline과 같았다. 모든 캡처의 I/O 시도는 0이었다. 최종 자산·export SHA와 QA/dist/app-release UUID·서명·Codex parity도 확인했다. 중간 바운스 WAV는 Undo로 정리되어 현재 재해시할 수 없으며 당시 캡처에서 실제 hash를 검증한 범위로 구분한다.
