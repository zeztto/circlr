# build77 생성 메뉴·드럼 입력 검증

2026-09-10. 단일 슬롯에서 native 구현 검토와 QA를 순차 수행했다. 서브 에이전트 생성은 thread limit으로 거절됐으며 독립 검토가 아니다.

- 관련 Swift7개 성공: `.build/creation-interface-final-tests.log`. 전체513개 재실행 결과가 아니다.
- 최종 release67.41초, 생성 후보 앱 deep/strict 서명과6개 source hash 일치 확인.
- 실제 신규 곡 `creation-workflow.circlr`에서 build76의 빈 드럼1행과 비활성 생성 항목을 관찰했다. build77은 기본8행, 킥1스텝/스네어5스텝 입력, 스네어 검색1/8행, 두 Undo를 확인했다.
- 현재 섹션 메뉴에서 MIDI 생성 후 Undo. 곡/섹션/사운드 메뉴는 AX로 확인했다. 메뉴 screenshot은 제공되지 않는다.
- `python3 qa/check-creation-interface-evidence.py`:10 native snapshots, 음악 비교, r1→2→3→5→6→7, 메뉴·검색·저장 편집기 복원 통과. 음악 비교는 musicRevision/hierarchyView만 제외한다.
- 저장한 드럼 스텝 편집기를 다시 열어8행과 빈 노트를 확인했다. 최종 화면 `qa/generated/creation-workflow/editor-reopened.jpg`.
- 최초 MCP focus 직후 저장/재열기는 선택과 스텝 설정은 남았으나 카메라가 멀리 있었다. 이를 성공한 편집기 복원 증거로 세지 않는다. Return으로 편집 진입 완료 후 저장한 `editor-saved`/`editor-reopened`는 hierarchyView까지 같다. focus/카메라 저장 타이밍은 후속 조사한다.
- 원본 studio fixture manifest SHA256 유지. 실제 작업 프로젝트는 새로 만든 UUID0AD0C9DE-2568-4A6E-A040-8ADB09E697CB이며 packager의 auxiliary creation-interface fixture와 다르다.
- 모든 검사 상태에서 output/audition attempts0, 녹음 없음. 물리 재생/녹음·MP4·실제 곡 완성도는 이 검증에 포함하지 않았다. 생성 후보만 검증하며 사용자 배포 앱은 교체하지 않는다.
