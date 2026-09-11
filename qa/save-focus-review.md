# build78 이동 중 저장 검증

2026-09-10. 기준3dc897c. 단일 슬롯에서 native 구현→코드 검토→QA 순차 수행. 독립 에이전트 검토가 아니다.

변경은 캔버스 viewport capture에 한정된다. SwiftUI가 아직 처리하지 않은 command를 update로 반영하고, 유효한 Timer가 있을 때만 목적지 카메라를 저장한다. 취소 Timer는 과거 목적지를 재사용하지 않는다. 현재 화면 애니메이션은 중단하지 않는다. 파일 경로/인증/외부 전송 계약은 변경하지 않았다.

- 관련 Swift18개 성공: `.build/save-focus-tests.log` (CanvasGeometryTests, HierarchyIntegrationTests, SavedWorkspaceTests). AppKit callback의 직접 증거는 아래 native 검사다.
- release72.71초, UUID3AB3CA35-3171-3A04-B32D-414CC4071C47. `qa/prepare-save-focus-qa.py`로 독립 후보 생성.
- MCP focus(album)→save→focus(audio,detail)→save→open 연속 호출. 카메라와 선택이 정확히 복원되며 오디오 편집기 화면을 직접 확인했다. `qa/generated/save-focus/audio-reopened.jpg`/AX.
- 첫 재열기에 workspace.editor 기본값이 추가돼 전체 hierarchyView 동등성 assert는 실패했다. 카메라/선택 및 hierarchyView 외 전체 필드는 같다. 기본값 초기화와 카메라 복원을 구별한다.
- UI 확대 버튼 직후 캔버스 클릭으로 실제 보간 도중 취소. 시작0.229468→목적지0.305192 사이0.282476으로 저장됐다. 대기 후에도 움직이지 않고 재열기 카메라도 정확히 같다.
- `python3 qa/check-save-focus-evidence.py`:8 native states, 전체 음악/이력 필드, 원본 manifest hash, 변경 소스 hash, app/helper Mach-O sections, deep/strict 서명 통과.
- 모든 캡처 output/audition attempts0, 녹음 없음. 물리 출력/입력·MP4·음악 완성도 검증과 사용자 앱 배포는 별도 미완료 범위다.
