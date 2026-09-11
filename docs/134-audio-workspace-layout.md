# 오디오 편집 공간의 수치 접근

상태: build117 Release·실제 앱 검증 완료. build116의 실제 1020×768 화면에서는 고정 파형 아래에 있는 별도 스크롤 영역이 좁아 수치 행이 잘려 보였다.

## 변경

파형과 도구, 수치 입력을 하나의 세로 스크롤 흐름으로 연결한다. 작은 높이에서는 파형을 112pt로 표시하며, 스크롤로 파형을 벗어나 수치 행을 함께 볼 수 있다. 640pt 미만 편집 폭은 2열, 그 이상은 4열이다. 별도 창이나 고정 사이드바를 추가하지 않는다.

입력 뷰는 lazy로 생성하지 않아 화면 밖 필드도 기존 Tab 순서에 등록된다. 음악 변경·대상 identity·Undo 계약은 그대로 사용한다. 파형 확대·이동과 전체 편집 공간 스크롤은 별개다. `AlbumCanvas`의 wheel monitor는 `OrbitAudioView`와 `NSScrollView` 하위 입력을 해당 뷰에 전달한다. 빈 캔버스의 확대 동작은 유지한다.

## 검증

`.build/build117-release-final4.log` Release46.45초·exit0, UUID `1D43D21B-ACD0-3BD6-8ABA-5AD820194588`. `qa/generated/shared-audio-workspace/compact117-final2`의 최종 후보만 승인한다. 초기 컴파일의 `Layout` 이름 충돌은 `SwiftUI.Layout` 명시로 수정했고, 앞선 후보에서 발견한 휠 가로채기와 화면 밖 포커스 복귀도 수정 후 재검증했다.

실제 1020×768 앱에서 넓은 4열의 입력8개가 함께 보이는 화면, 축소한 서클의2열, 일반 오디오의 Shift+Tab 마지막 필드 접근을 PNG·AX로 확인했다. Return/Escape로 파형에 복귀할 때 파형도 스크롤 안으로 드러난다. 최종 PNG9장에는 초기·스크롤·복귀·compact·변경 후 복귀·gain·일반 오디오·파형 확대·재열기가 포함된다.

`qa/check-audio-workspace-layout-evidence.py`의9개 저장 상태가 통과했다. r38의 before/scrolled는 카메라를 포함한 manifest가 정확히 같고, 캔버스 위 휠은 실제 카메라를 변경한다. 작은 서클의 clip2 gain −12dB(r39)와 Undo(r40), 일반 오디오의 파형 위 휠 확대·카메라 보존, 공유 clip2 선택 유지, restored/reopened/disk 전체 일치, 원본 자산2개 SHA와 실행 바이너리 SHA/UUID를 검사했다. 표시 상태의 가독성은 PNG 직접 검토이며 AX 등록만으로 화면 표시를 주장하지 않는다.

스크롤 위치에 따라 인접 행의 일부가 경계에 걸칠 수 있으나 선택 필드는 자동으로 드러나며, 넓은 화면에서는 수치8개를 동시에 볼 수 있다. 다른 편집기 전체·모든 창 크기·물리 입출력을 검증한 결과는 아니다. QA 앱을 종료하고 기존 사용자 앱 PID86114를 유지했다. 이 turn의 서브 에이전트는 사용량 제한으로 종료되어 구현·소스 재검토·native 검증은 root가 순차 수행했다.
