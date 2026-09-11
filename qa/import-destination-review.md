# build79 오디오 가져오기 목적지

2026-09-10, 기준5799577. 단일 슬롯에서 UX→native 구현→검토→QA를 순차 수행했다. 독립 에이전트 검토가 아니다.

- 회귀 원인: selectHierarchy(section)는 이전 selectedTrackID를 보존한다. 기존 audioImportDestination은 이 값을 무조건 사용했다. 새 기본값은 음악 서클에서만 트랙을 받아 섹션/그룹에서는 새 트랙으로 만든다. 라이브러리 명시적 트랙 선택과 pattern 경로는 유지한다.
- 파일 선택 창에 실제 대상 이름·트랙·1기반 박·원본/이번 사용과 다중 파일 규칙을 표시한다. 이름은 각80자까지만 표시하며 실제 이름/저장 데이터는 자르지 않는다. 추가 확인 창은 없다.
- 관련16개 테스트 성공(`.build/import-destination-final-tests.log`): AudioImportPlacementTests11개, AudioImportEditingTests5개. 단일 파일 새 트랙 및 기존 MIDI/다른 사용 보존을 추가했다. 기존 트랙·다중/패턴 적용도 Core 검증 범위다.
- release64.20초, UUID3269522D-4480-3AFE-B768-8039E5781690. 전용 authored fixture UUID99587A36-D771-5C30-A976-C96E5652441C.
- 실제 음악 서클 선택→파일 창은 `1 · 출력 1`; 취소→섹션→파일 창은 `새 트랙`. AX와 화면 확인. `qa/generated/import-destination/new-track-panel.jpg`.
- 그 파일 창에서 fixture의 직접 작성한 WAV 하나를 선택·Open. tracks3→4/assets2→3/r14→15. 기존 트랙/원본 섹션/다른 사용 보존. Undo1회 r16으로 음악 복원 후 저장/재열기.
- `python3 qa/check-import-destination-evidence.py`:5 native snapshots, 대상 표시·실제 새 트랙·음악/원본/다른 사용·Undo/재열기·source hash·app/helper Mach-O sections·deep/strict signature 통과.
- OS 창을 열고 바로 보낸 단축키는 첫 시도에서 입력창을 열지 못했다. 파일 목록에 포커스를 둔 뒤 경로 이동으로 선택했다. 앱 가져오기 실패로 계산하지 않는다.
- native 다중 파일/패턴과 라이브러리 왕복은 이번에 재실행하지 않았다. output/audition0회, 녹음 없음. 오디오 출력/입력·MP4와 사용자 앱 출고는 별도 남은 범위다.
