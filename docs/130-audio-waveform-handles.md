# 짧은 오디오 구간의 파형 손잡이

상태: build114 final2 Release41.14초·exit0, 실제 geometry782개 검사·source v3 review blocker0 통과. native20개 JSON을 생성하고 QA 앱을 종료했다. JPG10장·AX 시각 검토와 native20개 strict checker를 통과했다. 기준 HEAD `ece7702`의 기존 build113 이력을 보존한다.

## 문제와 변경 계약

build113 final split JPG에서 실제32초 파일의0.5초 구간에 시작/끝 라벨이 가까운 문제가 관측됐다. linear hit 판정은 x 거리14px 미만을 trim으로 취급해 짧은 구간 안의 조작이 trim에 잡히고 cursor를 직접 배치하기 어려웠다.

짧은 구간에만 y-separated handle을 적용하고 그리기와 hit 판정이 같은 geometry를 사용하도록 수정했다. 라벨과 원래 시간 위치는 leader로 연결한다. 자동 fit으로 사용자의 표시 범위를 바꾸지 않고 직접 cursor 배치와 trim을 지원한다. orbital의 기존 동작은 보존한다. orbital의 보존은 source 확인 범위이며 실제 native 회귀 검증으로 계산하지 않는다.

## 현재 자동 검증

초기 `.build/audio-handle-layout-qa-final.log`는72개 scenario·737개 검사를 통과했다. 후속 edge 보완을 포함한 실제 geometry 검사는782개로 통과했다. standalone harness의 첫 compile은 CoreGraphics import 누락으로 실패했으나 명시 import 후 통과했다. 첫 앱 Release 자체는 성공했으므로 이 harness 실패를 제품 compile 실패로 기록하지 않는다.

실제 drag 중 resize 취소는 현재 CUA API에서 동시 gesture를 재현하지 않았으며 source guard 검토 범위다. native 재현 성공으로 계산하지 않는다.

## final2 native 검증

`.build/build114-release-final2.log`: Release41.14초, UUID `8EBE5ECA-B744-3D51-874C-78794B72374A`다. 최종20개 JSON에서 원본 자산2개와 noIO를 capture helper로 확인했으며 시각 JPG10장·AX와 `qa/check-audio-handles-evidence.py`의20개 strict snapshot 대조를 통과했다.

- before18에서 실제 시작 경계 drag19, Undo와 cursor20, 끝 drag21, Undo/F22를 수행했다.
- 끝0.05초 tiny 구간에서 cursor22, end drag23/Undo24, start drag25/Undo26을 수행했다.
- middle UI 준비2회는 revision27/28이며 cursor28, drag29와 Undo30/31/32 뒤 restored/reopened32를 확보했다.

초기 final 후보의 start glyph x55는 plot 밖 early guard에 걸려 no-op(revision16)이었고 안쪽 x57은 성공17/Undo18이었다. 이 증거는 보존하되 최종 native 승인에서 제외한다. final2의 실제 경계 drag를 별도로 대조한다. wide native는 F 확대 표시와0 복원만 수행했으며 wide drag는 실행하지 않았다. wide hit는782개 geometry harness의 검증 범위다. 물리 재생·실제 drag 중 resize·orbital native 회귀는 수행하지 않았다. orbital은 source branch 정책 보존만 검토했다.

strict checker는 음악·graph·다른 lane·원본 자산 보존과5개 gesture를 확인했다. gesture 예상 변화량은 독립 계산32/908에 native 좌표1px tolerance만 허용했으며 반대쪽 끝은 exact, 방향과 비영 변화도 확인했다. 이 좌표 허용 오차를 geometry harness782개 exact 검사에 적용하지 않는다. cursor AX/저장값, F의0.55 표시 범위와 전체 보기의 빈 `audio` viewport, revision18→32를 대조했다. restored·reopened·disk 전체 동일성과 open job도 통과했다.

초기 checker는 존재하지 않는 `all.ax`를 요구해 실패했으며 실제 `all.json`의 `audio={}`로 전체 보기 복원을 대조하도록 수정했다. 없는 증거를 새로 만들거나 확보했다고 표시하지 않는다.

## 별도 오디오 진단 후속

`AuditionTransport`의 현재 in-process AU 경로(검토 시186행)는 AU 생성 이후 mixer 획득과 start 단계가 세분화되지 않아 대기 위치를 구별하기 어렵다. timeout 경로(검토 시159행)는 기다리는 요청을 끝내도 factory 자체를 중단하지 못한다. 후속 진단에는 bounded trace와 각 단계의 진입/완료 관측이 필요하다. 이번 파형 UI 수정의 완료 조건과 분리하며 원인 확정이나 HAL stall 해결로 표현하지 않는다.

QA 앱을 정상 종료했고 root의 프로세스 검사에서 기존 사용자 앱 PID86114가 유지됨을 확인했다. 사용자 앱·물리 장치 설정은 변경하지 않았다.

## 시각 검토 범위

before/start-dragged/end-dragged/fitted/tiny-before/tiny-cursor/tiny-end-dragged/tiny-start-dragged/middle-end-dragged/reopened의 JPG10장과 AX를 검토했다. 라벨 사이 간격·leader·세로 분리 손잡이·현재 수치 가독성과 boundary clipping 없음을 확인했다. 15ms 이동의 실제 수평 pixel 정밀도는 정적 이미지로 판단할 수 없으므로 수치 AX/native 증거와 분리한다. middle 끝 수치는 다음 행 스크롤 아래에 남지만 현재 행에는 겹침이 없다.
