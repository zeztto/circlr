# Documentation · 문서 안내

Start with [English](../README.md) or [한국어](../README.ko.md). The current application UI and most detailed engineering documents are in Korean. English entry points are maintained here and in the project README.

[영어 소개](../README.md) 또는 [한국어 소개](../README.ko.md)에서 시작하세요. 상세 설계·QA 문서는 현재 대부분 한국어이며 아래에서 목적별로 찾을 수 있습니다.

## Find your next step · 목적별 안내

| Topic / 목적 | Document / 문서 |
|---|---|
| Install downloaded app / 다운로드한 앱 설치 | [macOS installation / macOS 설치](install-macos.md) |
| First build and basic controls / 첫 빌드·기본 조작 | [English](../README.md#getting-started) · [한국어](../README.ko.md#시작하기) |
| Circle time and navigation / 궤도의 시간·탐색 | [Orbit timeline](19-orbit-timeline.md) |
| Audio editing / 오디오 편집 | [Audio workspace](52-audio-workspace.md) |
| MIDI steps / MIDI 스텝 | [MIDI grid workspace](51-midi-grid-workspace.md) |
| Music agents / 음악 작업 에이전트 | [MCP](../mcp/README.md) · [Studio kit](24-music-agent-kit.md) |
| Contributing / 기여 | [CONTRIBUTING](../CONTRIBUTING.md) · [AGENTS](../AGENTS.md) |
| Architecture / 구조 | [Hierarchy](15-hierarchy-canvas-architecture.md) · [Agent interface](17-agent-interface.md) |
| Current version / 현재 버전 | [0.60.0](releases/0.60.0.md) · [Release notes](releases/0.60.0-notes.md) · [QA evidence](releases/0.60.0-qa.md) |
| Demo library / 데모곡 후보·편곡 | [Sources and plan](releases/demo-library-plan.md) |
| Next versions / 다음 버전 | [Roadmap](releases/roadmap.md) |
| Release publishing / 릴리스 등록 | [Process](releases/README.md) · [Bilingual notes template](releases/RELEASE_NOTES_TEMPLATE.md) |
| Changes / 변경 내역 | [CHANGELOG](../CHANGELOG.md) · [Archived README](history/readme-build157.md) |

## Source map · 소스 안내

| Path | Responsibility / 책임 |
|---|---|
| `Sources/CirclrCore/` | Document model, graph and edit contracts / 문서 모델·그래프·편집 계약 |
| `Sources/CirclrApp/` | macOS canvas and editors / macOS 캔버스·편집기 |
| `Sources/CirclrAudio/`, `Sources/CirclrRealtime/` | Rendering and audio processing / 렌더링·오디오 처리 |
| `Tools/` | Audio helpers and studio CLI / 오디오 helper·스튜디오 CLI |
| `mcp/server.py` | Local stdio MCP adapter / 로컬 stdio MCP 어댑터 |
| `Tests/`, `qa/` | Automated contracts and native verification / 자동 검사·native 검증 |
| `Resources/Info.plist` | Candidate app version and build / 후보 앱 버전·build |

For agents: read `AGENTS.md`, then the current release plan. Check the running app's `snapshot.runtime` and capabilities before using MCP. Build numbers, passing unit tests and screenshots do not imply a released or audio-validated product.

에이전트는 `AGENTS.md`와 현재 버전 계획부터 읽고 MCP 사용 전에 실행 앱의 `snapshot.runtime`과 capability를 확인합니다. build 번호·단위 테스트·스크린샷을 출고 또는 실제 오디오 검증 완료로 해석하지 않습니다.
