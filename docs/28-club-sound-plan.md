# 0.14 / f0r h3r v4 실행 계획

요청: 복잡한 드럼을 줄이고 DJ가 연결하기 쉬운 곡, 역할이 구분되는 풍성한 편성, 실질적으로 개선한 기본 신스.

- owner: development-lead. Bootstrap: 현재 대화의 session-bootstrap-v1. delegation: none (전체 실행 슬롯 1개). sound-designer/engine 구현 → arranger/beatmaker → QA/review를 순차 수행한다.
- 음악: 120 BPM, 4/4, F♯ minor. 96마디, 16마디 intro/outro, 16 groove / 8 lift / 16 chorus / 8 break / 16 final. 킥 매 박, backbeat 2·4박, offbeat hat, snare roll·반복 tom fill 제거. 15트랙, 신스 10음색의 register·진입/퇴장 구분. 기존 모티프의 정체성은 유지하되 선율과 코드 리듬을 이 form에 맞춘다.
- engine owner: `Sources/CirclrRealtime/{synth.c,include/CirclrSynth.h}`, `Sources/CirclrCore/ProductionModel.swift`, `Sources/CirclrAudio/{ProductionInstrument,Renderer}.swift`. Engine 3를 추가하고 저장된 engine 1/2를 보존한다. PWM·oscillator body·velocity partials·ensemble modulation, EP/organ/brass/strings. 콜백 할당/lock 금지. 15트랙 전체곡의 준비 메모리를 측정하고 명시된 한도 내에서만 렌더한다.
- app/agent 계약 owner: `Sources/CirclrApp/{InspectorView,AgentConsole}.swift`, `mcp/server.py`, `Resources/Info.plist`, `Resources/Codex/`. 실제 선택·편집·MCP 가능한 음색만 노출한다.
- arrangement owner: `Tools/CirclrStudioTool/`, `music/f0r-h3r/v4/`. CC0 bank 6개를 그대로 사용, 새 구매 없음. 원본 v1–v3와 사용자가 열어둔 문서는 보존. 새 파일·새 프로젝트에만 작성.
- 검증: Swift synth 품질/serialization/queue/legacy + offline regression, C warnings, Python MCP tests, 고정 v3 WAV 재렌더 SHA 일치, v4 킥·스네어 grid/notes/form/미디어 감사, native QA 앱 열기와 export, 음량·DC·stereo 및 악기별 비교 파일. 청취와 수치 검사를 구분한다.
- 명령: `CIRCLR_MODULE_CACHE_PATH="$PWD/.build/quality/module-cache" ./scripts/swift-local.sh test --scratch-path .build/quality --skip testArrangementRenderExportAndPlayback`; release `--product circlr` / `--product circlr-studio`; `python3 scripts/package-app.py .build/app-release/release/circlr`.
- Git: 기존 승인된 private main에 검토된 source/docs/tests/MIDI만 commit/push. audio/project/app/사용자 설정은 ignore 유지. README/CHANGELOG/QA/재현 명령 갱신 후 로컬 앱과 새 WAV/portable project 전달. 사용자 음악 평가가 최종 미학 판단이다.
