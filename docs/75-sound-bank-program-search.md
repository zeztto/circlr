# Sound Bank 이름·변형·드럼 킷 선택

session-bootstrap-v1: development-lead, baseline=856d18e, branch=codex/daw-integration. 직전 build60은 구현·native 검증·private push 완료로 progress다. 실제 agent slot이 1개이며 직전 dispatch도 thread limit으로 실패했다. delegation=none; UI/UX → native Swift/Core → read-only review/security → QA로 순차 전환한다.

## 사용자 흐름과 범위

현재 Sound Bank는 음색 이름 없이 종류 선택 뒤 0–127/1–128의 서로 다른 번호 제어와 드럼 toggle을 쓴다. build60의 검색 화면에 실제 macOS DLS metadata를 넣어 악기 이름과 계열, `#1`–`#128`, 기본/변형 뱅크, 멜로디/드럼 킷으로 바로 선택한다. 번호별 목록을 미리 만들어 제품에 넣지 않고 `CopyInstrumentInfoFromSoundBank`의 실제 설치 파일을 읽는다. 이 Mac의 metadata 235개(기본 멜로디 128·변형 98·드럼 킷 9)를 발견했다. 음색 번호는 화면에서 1–128, MIDI 값은 0–127이며 변형 뱅크 번호는 MIDI 식별값 그대로 표시한다.

Sound Bank 검색은 기존 850×560 캔버스 overlay를 재사용한다. 전체/내장 신스/Sound Bank/AU 필터 아래 Sound Bank일 때만 전체/멜로디/드럼 킷 필터를 보인다. 한글 계열(피아노·베이스·기타·신스 패드 등)도 검색한다. 같은 번호의 변형은 이름·뱅크 값으로 구별한다. 현재 Sound Bank에서는 해당 필터와 현재 항목으로 시작한다. ↑↓·Return·Esc와 현재 음색 찾기, 고정된 편집 대상/음악 revision 검사를 그대로 사용한다. 숫자 stepper·드럼 toggle은 같은 검색에서 유효한 preset을 선택하도록 대체한다.

프로젝트 Instrument에 optional `bankLSB`를 추가한다. 생략/nil은 기존 기본 뱅크 0이다. 선택은 kind/program/drums/bankLSB를 한 transaction으로 바꾸며 비활성 synth/plugin/sample 설정을 보존한다. 로더도 같은 program/MSB/LSB를 쓴다. 새 bankLSB의 0–127 범위를 구조 검증과 로드 경계에서 검사한다. AU metadata나 은행 음원은 프로젝트/저장소에 복사하지 않는다. 과거 앱은 새 변형 선택을 지원하지 않으므로 새로운 변형을 포함한 곡은 이 빌드 이상에서 연다.

## 근거와 소유 경로

현재 SDK AudioToolbox.h의 `CopyInstrumentInfoFromSoundBank`, AudioUnitProperties.h의 `kAUSampler_DefaultMelodicBankMSB=0x79`, `DefaultPercussionBankMSB=0x78`, LSB=0 및 실제 metadata를 대조했다. API의 설명 문장에는 두 MSB 숫자가 뒤바뀌어 있으므로 실제 상수와 발견된 파일 값(멜로디 121/드럼 120)을 사용한다. [MIDI Association GM1 설명](https://midi.org/general-midi-level-1/)은 프로그램 번호의 음색 의미를 설명한다. 실제 표시 이름은 로컬 Sound Bank에서 읽고 계열 명칭은 UI 검색 분류로 제공한다.

Core: Model.swift, ProjectStore.swift, SoundSelection.swift, 새 SoundBankPreset.swift 및 관련 테스트. Audio: AudioUnitHost.swift, 새 SoundBankCatalog.swift 및 metadata/load-address 테스트. App: AppStore.swift, SoundPickerView.swift, InspectorView.swift, EditorView.swift. Resources/Info.plist build61, README/CHANGELOG, docs17/25/31/75, QA helper/보고서. DSP·녹음 장치·사용자 앱·원본 음원·root/ports worktree는 보존한다.

## 검증 경로

관련 테스트 → 전체 `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release build. metadata 조회 테스트는 장치를 시작하지 않고 실제 파일과 renderer의 bank 인자를 대조한다. authored QA 사본에서 이름/분해형 한글 계열/#번호/드럼 필터, 동일 번호 변형, 기존 음색 재선택, Undo/Redo, 외부 수정 중 거절, 수정된 신스 복귀, 저장·재열기를 확인한다. 1024px/콘솔 열린 화면·AX·source hashes·Mach-O·codesign·kit·원본 보존을 확인한 뒤 승인된 private 저장소에 소스·문서·테스트·QA helper만 push한다. 물리 출력·실제 AU 재생은 기존 별도 검증 조건이다.

## 사용법과 구현 결과

1. 악기 서클의 `음색·악기 찾기` 또는 ⇧⌘P의 같은 명령으로 연다. 상단의 트랙 번호·이름과 `이 트랙의 모든 섹션`을 확인한다.
2. Sound Bank를 선택하고 `피아노`, `E.Piano`, `#5`처럼 입력한다. `#5`는 표시 번호가 정확히 5인 모든 변형만 찾으며 전각 `#５`도 같다. 드럼 킷 필터에서는 `#26`으로 실제 TR-808 항목을 찾을 수 있다. 이름과 가용 개수는 설치된 파일에 따라 달라진다.
3. ↑↓·Return 또는 행 클릭으로 선택한다. 같은 음색은 음악 이력을 만들지 않는다. `현재 음색 찾기`는 검색/종류/드럼 필터를 초기화하고 현재 항목을 보여준다. Esc는 취소한다.
4. 다른 음색으로 바꾼 뒤 Undo/Redo와 저장/재열기가 전체 주소를 복원한다. 원래 신스를 다시 고르면 수정한 patch를 유지한다. 검색 도중 음악이나 대상이 바뀌면 비활성 결과와 재진입 안내를 표시한다.

관련 16개·전체 Swift 445개·Python 26개 및 최종 release를 통과했다. native 16상태/AX·화면 18쌍으로 실제 기본/변형/드럼 선택, 수정 범위, 저장 복원을 검사했다. 최초 화면에서 필터 행이 늘면서 적용 범위가 압축되어 사라지는 문제가 발견됐다. 대상·현재 음색·오류 문구의 세로 크기를 보존하도록 고친 후 최종 앱에서 정상/충돌 두 화면을 직접 확인했다. AX 존재만으로 가시성을 판단하지 않는다.

읽기 전용 코드/입력 경계 검토와 QA는 순차 역할로 수행했다. 최종 독립 agent dispatch도 `agent thread limit reached`로 거절됐다. [검증 결과와 정확한 범위](../qa/sound-bank-search-review.md), [기존 MCP 쓰기 계약](17-agent-interface.md)을 함께 따른다. 후속 음색 catalog MCP 조회와 편곡안 검색은 [개발 로드맵](25-development-roadmap.md)에 분리했다.
