# 이동 직후 저장한 편집 위치 — build78

build77 실제 QA에서 MCP focus(detail:true) 직후 save/open하면 선택은 MIDI지만 화면은 상위 곡 크기에 머물렀다. 저장 callback은 SwiftUI가 대기 명령을 소비했는지 확인하지 않고 현재 보간 카메라를 읽었다.

저장 계약: 대기 중인 hierarchy command를 캔버스에 적용한 뒤, 유효한 이동 Timer가 있으면 목적지 카메라를 저장한다. 자연스러운 화면 이동은 계속한다. 취소되거나 완료된 Timer는 현재 카메라를 저장한다. 음악 데이터·Undo·스텝 설정을 바꾸지 않는다.

검증 계획: 실제 MCP focus→save→open을 같은 프로세스에서 연속 호출하고 서클/스텝 편집기 복원을 확인한다. 선택 변경, 일반 저장, 사용자 취소 후 저장, 음악 보존을 비교한다. 출력·audition·녹음은 시작하지 않는다. 이 문서는 구현 계약이며 native 검증 완료를 뜻하지 않는다.

중간 검증: 관련18개 테스트와 release72.71초 통과. UUID3AB3CA35-3171-3A04-B32D-414CC4071C47 후보에서 focus→save→open을 연속 실행해 오디오 편집기 복원 확인. camera/selection은 정확히 같고 hierarchyView 외 모든 음악/이력 필드는 baseline과 같다. workspace.editor는 첫 표시 후 기본값이 추가되므로 전체 viewport byte 동일성을 주장하지 않는다. 취소 후 저장 검증은 아직 남았다.

최종: 실제 확대 도중 캔버스 클릭으로 취소. 시작0.229468, 목적지0.305192 사이의0.282476을 저장했고 대기/재열기 후 같았다. 관련18개/실제8상태·전체 비보기 필드·소스 hash·Mach-O app/helper sections·서명·원본 fixture 보존 통과. [QA](../qa/save-focus-review.md). 앞의 검증 계획/중간 결과는 수행 당시 기록이다.
