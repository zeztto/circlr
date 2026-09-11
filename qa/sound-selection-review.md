# 음색·Audio Unit 선택 검증 — build 60

2026-09-09, integration branch e12bf43 이후 변경. 사용자 요청에 따라 독립 selector audit 에이전트를 실제 호출했으나 `agent thread limit reached`로 거절됐다. 구현·코드/입력 경계 검토·QA를 동일 실행자가 역할별로 순차 수행했으며 독립 agent 승인을 주장하지 않는다.

## 자동 검사와 패키지

- `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --filter SoundSelectionTests`: 7개/실패 0, 0.002초. Unicode/제조사/종류 검색, 동명 ID, 서로 다른 AU 종류 분리, 수정된 patch와 이전 엔진 버전·state 보존, 새 음색 기본값, 미설치 거절.
- `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`: 최종 437개/실패 0, 25.665초 (관련 8개 포함). 기존 HAL 장치 환경 문제로 물리 playback test 제외.
- `python3 -m unittest mcp.test_server qa.test_agent_kit`: 26개/실패 0, 0.221초.
- 최초 release 64.98초 후, 비활성 음색 복귀 보완을 포함한 최종 release 18.74초. 최종 앱 UUID `C064E6FE-0DB9-39B0-B3C4-CA6767DC1A8F` (`qa/generated/sound-selection/final/`). source 15개 hash, Mach-O file-backed section 37개, bundled Codex kit 25개, strict codesign과 metadata 일치.

## 실제 앱

`qa/prepare-sound-selection-qa.py`가 작성한 QA 사본은 원본 3트랙/2 authored tone을 보존하며 두 번째 section use, 수정된 EP cutoff 731, 전역 Reverb를 추가한다. 음악 서클 Reverb를 MCP transaction으로 추가한 r15가 기준이다. 실제 곡/Splice 음원/원본 사용자 앱은 편집하지 않았다.

1024px 창·콘솔을 연 상태로 850×560 검색 화면의 이름/제조사/대상 범위/현재 항목·결과·키보드 안내를 확인했다. AX에서 배경 캔버스가 검색 중 숨겨지고 search field에 포커스가 잡힌다. 이 Mac에서는 내장 신스 10개+Sound Bank 1개+AU 악기 9개, AU effect 26개가 실제 발견됐다. 이 숫자를 일반 사용자 환경의 고정 수로 간주하지 않는다.

| 경로 | 실제 결과 |
|---|---|
| EP 재선택 → 분해형 한글 `베이스` → Return | 재선택은 r15 유지, bass 적용 r16. Undo r17에서 EP cutoff 731을 포함한 전체 설정 복원 |
| EP 재선택 후 Redo | 재선택이 Redo를 지우지 않으며 r18에 bass 복원 |
| `ＡＰＰＬＥ`·AU 필터·방향키 | Apple AU 악기 3개, DLSMusicDevice 선택/적용 r20. 다른 트랙/섹션/신스 비활성 설정 보존 |
| 같은 AU 재선택 | 생성한 binary plist state를 포함한 instrument 전체 일치, r21 유지. 실제 plugin instantiate는 수행하지 않음 |
| 검색 중 외부 rename → Return | r22에서 결과 비활성·재진입 안내. 검색한 pad는 적용되지 않고 기존 AU/state 유지 |
| 빈 검색·현재 음색 찾기·명령 | 결과 0 안내, 검색/필터 초기화 후 EP 강조, ⇧⌘P로 악기/전역 효과 검색 직접 진입 |
| 서클 효과 | `Apple reverb` 결과 2개 중 AUMatrixReverb 적용 r26. amount/secondary와 공유 원본·다른 use·라우팅 보존 |
| 전역 종류 메뉴의 AU → Esc | 선택하지 않은 AU 종류는 적용하지 않으며 Reverb/음악 revision r27 유지 |
| 전역 효과 | `Apple Delay` 결과 2개 중 AUDelay 적용 r28. 다른 음악 보존 |
| 미설치 AU | 현재 저장된 이름과 `설치 목록에 없음`, 현재 찾기 비활성. 가용 결과에 가짜 항목을 넣지 않고 Esc 보존 |
| Sound Bank → Undo → 저장/재열기 | 기존 program/비활성 patch 유지, r33에 기준 음악 복원. 재열기 전후 manifest 전체 일치와 실제 EP 편집기 cutoff 731/검색 재진입 확인 |

후속 검토에서 비활성 음색을 다시 고를 때 patch/state가 초기화되는 경로를 발견해 Core 변환을 보완했다. 최종 앱에서 r34에 보관된 AU state fixture를 구성하고 Sound Bank(r35) → EP(r36) → AU(r37) → EP(r38)를 실제 검색으로 선택했다. EP cutoff 731과 모든 patch 값, AU serialized state가 각 복귀 후 그대로 유지됐다. 기준 instrument 복원 r39 뒤 최종 앱의 종료·재열기에서도 manifest 전체가 일치했다. 초기 15개 제품 파일 중 이 보완으로 바뀐 파일은 SoundSelection.swift 하나이며, 최종 hash와 비교하고 전체 Swift 437개를 다시 통과시켰다.

최종 앱으로 바꾼 뒤 초기 CUA helper가 이전 앱 handle을 참조해 두 번의 입력 오류와 이전 빈 QA 앱 재실행이 있었다. helper를 최종 handle로 다시 연결했다. 이전 앱의 `이미 실행 중인 Agent 연결이 있습니다` 상태와 revision 0을 기록했고, 모든 MCP 캡처는 정확한 QA project/path를 검사한다. 마지막에는 두 QA 프로세스를 모두 종료했다. 이것을 제품 입력 결함이나 음악 변경으로 분류하지 않는다.

native snapshot 23개·AX/JPEG 20쌍을 `qa/check-sound-selection-evidence.py`로 비교한다. 단순 revision 검사뿐 아니라 변경한 instrument/effect 이외 모든 곡 데이터, 원본·다른 use·notes·assets·routing의 보존을 비교한다. `qa/generated/sound-selection/verification.json`은 로컬 결과이며 생성 앱/음원/화면은 Git에 포함하지 않는다.

## 코드·입력 경계 검토와 남은 범위

Core 순수 변환은 현재 catalog membership와 component type을 확인하고 같은 선택은 기존 전체 설정을 반환한다. UI 적용은 NumberEditIdentity의 프로젝트·revision·세션·target·원본 범위 및 녹음/준비/import 상태를 다시 확인한 뒤 기존 updateTrack/updateMusic/updateSignal transaction을 사용한다. 외부 프로젝트 열기의 reset에서 닫히고, 다른 검색/라이브러리 진입도 overlay를 정리한다. 문자열 검색은 메모리 내 연산이며 shell/네트워크/새 파일 접근 경로를 만들지 않는다. AU metadata 조회는 plugin을 instantiate하지 않는다. 보관된 음색 복귀 결함을 수정·재검증했으며, 최종 검토에서 남은 차단 결함은 발견하지 않았다.

원본 fixture SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, root `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱 0.19.0 build21 보존. owned QA 프로세스 0. 물리 output/audition attempts 0, 녹음 미실행. full VoiceOver·실제 AU editor/음질·장치 I/O·전체 DAW 출고 검증을 대체하지 않는다.
