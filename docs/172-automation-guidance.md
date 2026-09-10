# 오토메이션 안내와 낮은 화면 편집

상태: build149 최종 후보의 Release·native 편집 및 data 검증을 완료했다. 최종 UI 독립 감사도 PASS_WITH_EXPLICIT_LIMITS다. 전체 화면 크기·입력 조합 완료를 뜻하지 않는다.

## 실제 변경

build148의 안내 잘림과 점 선택 시 안내 소실을 개선했다. 낮은 화면에서는 plot과 제한된 세로 controls를 같은 캔버스에 나란히 배치한다. 적용 조건은 높이 240 미만·폭 600 이상 800 미만이며 다른 조건은 세로 배치다. navigation/time/value/shape와 scope/range/position/짧은 안내는 단일 eager 그룹으로 줄바꿈한다. 전체 의미는 Help·AX에 제공한다.

같은 plot·수치 subtree를 사용하며 .id 또는 중복 branch를 만들지 않는다. controls의 wheel은 해당 세로 스크롤로 전달하고 바깥 canvas의 zoom은 유지한다. 실제 변경 파일은 AutomationEditor와 AlbumCanvas다.

중간 후보에서 compact 안내·shape 잘림, controls wheel이 canvas zoom으로 전달돼 편집기가 닫히는 문제를 재현하고 수정했다. 넓은 화면의 grid 높이 감소도 default/max/fixedSize 측정으로 보완했다. 중간 후보의 thumb drag 성공을 wheel 성공으로 세지 않는다.

## 최종 검증

이번 compact/wide 전환은 같은 1019×768 창에서 canvas wheel zoom으로 서클과 편집 영역의 크기를 바꾼 것이다. 실제 NSWindow resize는 검증하지 않았다.

`guidance149-verified` Release는 48.72초에 통과했고 package·source 감사도 PASS했다. UI 배치·이벤트 변경은 native 동선으로 집중 검증했으며 새 unit/full suite는 실행하지 않았다.

| 동선 | 실제 결과 |
|---|---|
| 낮은 화면 | 왼쪽 plot과 수치·shape·안내의 세로 스크롤을 같은 캔버스에서 확인 |
| 넓은 화면 | 중간 약 50px로 줄었던 grid를 최종 약 84px로 확인 |
| 유효 draft | 700→800 draft를 compact→wide→compact 동안 r229에서 유지한 뒤 Return r230, Undo r231 |
| invalid draft | `x`를 compact→wide→compact에서 보존하며 r231 유지, Escape 복구 |
| 범위 밖 점 | 시간 9→81 r232, 표시 범위 맞춤으로 1–81 확인, Undo r233 후 서클 길이 보기로 1–65 복원 |
| 안내·scope | 파라미터 4개·선택/빈 상태, 공유 원본 점 0개/이번 use 점 3개에서 새 곡선 생성 없이 안내 확인 |
| wheel | controls 하단/끝/상단 이동에서 zoom 없음, 바깥 canvas zoom 유지 |
| 저장·재시작 | PID 변경 후 r233 전체 manifest 일치. 자동 plot focus 복원은 주장하지 않음 |

최종 data 감사는 캡처 8개에서 음악 복원과 자산 SHA 7개, wheel 전후 전체 hierarchyView·camera 일치 및 final/reopened r233 전체 manifest 일치를 확인했다. QA 앱을 종료하고 사용자 production PID 86114를 유지했다. 최종 UI 감사는 JPEG/AX 22쌍에서 PASS_WITH_EXPLICIT_LIMITS이며 findings는 0개다.

## 검증 한계와 다음 작업

폭 600 미만·극단적으로 낮은 body·물리 I/O·모든 키보드 조합·orbital·실제 momentum hardware는 실행하지 않았다. 재시작 focus는 canvas 26이므로 autofocus 성공으로 해석하지 않는다. controls scroll offset은 영구 저장하지 않는다. 모든 control이 첫 화면에 동시에 보인다고 주장하지 않는다.

이번 조건의 안내·편집 개선은 완료 범위로 유지한다. 다음은 긴 캔버스 이름 tooltip의 실제 표시와 한 곡의 더 넓은 편집·파일 작업·송폼 동선을 검증한다.

재시작은 PID 58210→58601·r233으로 확인했다. 음악·workspace/camera·전체 manifest는 비교 기준에 정확히 일치하지만 state.sequence는 변하므로 runtime 전체 상태의 완전한 동일성을 주장하지 않는다.
