# 효과 편집의 음악 단위와 입력 계약

2026-09-08, 기준 `5936cb5`, 목표 build 28. 이전 턴은 소스별 서클·직접 효과 메뉴와 Native 검증/private push로 progress다. 전체 개발 목표와 E 출고 gate를 유지한다.

## 계획 gate

development-lead → UI/UX → Core/Swift utility → read-only review → QA 순차 수행. 실제 agent 슬롯은 root 포함 1개이며 이전 spawn 한도 거절을 반복하지 않는다. 독립 agent 리뷰로 보고하지 않는다. 기존 private `codex/daw-integration`에서 source/docs/tests만 commit/push하며 앱·QA 미디어는 Git에 넣지 않는다.

현재 효과 편집은 모든 종류의 amount를 0–1로, delay/reverb/compressor의 secondary를 하나의 Mix / Ratio로 표시한다. 숫자를 쓰는 중간 값마다 음악을 변경한다. 목표는 실제 DSP 의미를 읽을 수 있고 한 조작을 한 번에 Undo하는 편집기다.

## UI·데이터 계약

- 동일 캔버스·다크 팔레트·단일 편집기를 유지한다. 효과 종류를 상단에서 고르고 바로 아래에 이름/슬라이더/숫자/단위를 한 행으로 둔다. 관련 설명은 실제 엔진의 제약만 짧게 표시한다. 이펙터의 음소거·출력 볼륨·트랙 바운스는 한 줄로 모은다.
- NativeDSP의 현재 계산을 바꾸지 않고 amount/secondary를 음악 단위로 변환한다: gain 배율, lowpass 40–20,000 Hz, delay 30–1,000 ms, drive 1–19배, pan −100–100%, compressor −36–−6 dB와 2–11.5:1, reverb 공간 크기/잔향 레벨 %. Delay는 dry를 유지하며 반복 레벨이 feedback에도 연결되는 기존 구조를 정확히 설명한다. Audio Unit에는 사용하지 않는 amount/secondary를 표시하지 않는다.
- 기존 저장값·reverb renderVersion·plugin state를 보기만 해서 변경하지 않는다. 범위 밖 legacy 값은 DSP의 유효 표시값을 사용하되 다른 항목 편집으로 덮어쓰지 않는다. 종류를 바꿀 때도 기존 데이터 호환성을 유지한다.
- 숫자는 Return 또는 포커스 이동 때 한 번 적용한다. Esc는 입력 취소다. 범위 밖/비정상 문자열은 명확한 오류를 표시하고 음악을 바꾸지 않는다. 슬라이더는 드래그 종료 때 한 번 적용하며 키보드 조작도 가능해야 한다. 입력 도중 프로젝트/선택/효과가 바뀌면 이전 값을 새 대상에 적용하지 않는다.
- 실제 재생 중 변경은 기존 prepared PCM 정책에 따라 다음 재생에 반영한다. 실시간 DSP preview나 효과 bypass를 구현한 것으로 표시하지 않는다.

## 파일 소유와 검증

Core: 새 `Sources/CirclrCore/EffectParameters.swift`의 표시/입력 변환. DSP·schema·MCP schema는 유지한다.

App: 새 `Sources/CirclrApp/EffectControls.swift`, 기존 `InspectorView.swift`의 공통 소비·전환/signal binding, `InlineCircleEditor.swift`의 음악 effect binding·footer, `UnifiedSectionView.swift`의 legacy section effect 소비. 숫자/슬라이더 draft는 해당 컴포넌트에 국한한다. 필요 시 focus-safe AppKit control을 새 파일로 분리한다.

QA: 음악 단위의 endpoint/inverse·invalid/no-op·legacy metadata 보존과 NativeDSP 결과를 테스트한다. 전체 Swift `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, Python `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`, release `.build/integration-release`. 별도 build 28 QA 앱/프로젝트에서 최소 창·콘솔 상태의 숫자 valid/invalid/Esc·한 Undo·슬라이더 드래그·키보드·효과 종류/Audio Unit 표시, MCP 변경 도중 stale 입력, 저장/재열기를 확인한다. 실제 마이크와 원본 곡·사용자 앱은 변경하지 않는다.

## 실행 결과

새 Core 4개·Audio 2개를 포함한 Swift 259개와 Python 26개, release가 통과했다. 실제 음악 effect 서클에서 단위/수치/슬라이더·Tab·오류/취소·외부 충돌·Undo·재열기를 확인했다. 처음 발견한 키보드 전달과 Tab 기준값 문제는 Native 재검증을 거쳐 수정했다. 최종 패키지와 소스의 Mach-O 37개 section이 일치한다. [근거와 후보별 결과](../qa/effect-editing-review.md).

현재 Native 성공 근거는 활성 창의 effect 서클 편집이다. CUA 비활성 창의 단독 첫 드래그는 값이 바뀌지 않았으며 완료로 세지 않는다. 전역 signal/섹션 전환/legacy section의 공통 컴포넌트 연결은 빌드했으나 위젯별 Native 회귀는 후속이다. 기존 출력 볼륨·신스 등 다른 `ValueField`의 확정 입력과 효과 실시간 반영은 다음 범위다.
