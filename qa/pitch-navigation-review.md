# build 46 MIDI 음역 탐색 검증

## 결과와 범위

`codex/daw-integration`, baseline `bca805c`. MIDI 0–127의 실제 연주 분포와 현재 12/24개 반음 범위를 기존 궤도 편집 영역 안에 표시한다. 클릭·잡은 위치를 유지하는 드래그, 좌우 반음·Shift 좌우 옥타브·Home/End 탐색을 지원한다. Return/Esc는 궤도로 포커스를 돌려주며 노트를 만들지 않는다. 접근성 slider의 범위·값 변경도 같은 viewport를 사용한다.

선택 또는 가리키는 음의 이름을 궤도 중앙에 표시하고 공간이 있으면 MIDI 번호를 함께 표시한다. 반음 행을 강조하며 C 기준 음명은 실제 텍스트 사각형이 겹치지 않을 때만 그린다. 음악의 시간·pitch hit·노트 원호는 기존 계산을 유지한다. 편집 방식과 이전/다음 노트·MIDI 메뉴·바운스·녹음 버튼은 기존 영역의 위/아래에 고정했다. 신호 엔진·장치·음악 생성 경로는 변경하지 않았다.

직전 실제 subagent 한도 오류 이후 동일한 거절 호출을 반복하지 않았다. UI/UX → native Swift utility → 읽기 전용 code/input review → QA를 순차 전환했다. 독립 에이전트 검증으로 주장하지 않는다.

## 자동 검사와 패키지

- Swift **366개**, 실패 0, 24.818초: `.build/pitch-navigation-tests-final.log`. 기존 물리 출력 의존 `testArrangementRenderExportAndPlayback` 1개 제외. 새 Core 3개는 두 범위에서 128개 pitch 전체 도달, 시간 페이지 유지, 반음/옥타브/Int 경계, pixel fraction의 전체 셀/비유한 입력을 검사한다. 실제 드래그의 grab offset은 Native 조작으로 검증했다.
- Python **26개**, 실패 0, 0.218초: `.build/pitch-navigation-python.log`.
- 최종 release **24.10초**: `.build/pitch-navigation-release-pinned.log`.
- 최종 앱: `qa/generated/pitch-navigation/pinned/써클러 통합 검증.app`, `com.circlr.integrationqa`, 0.20.0 build 46, UUID `6C2E6520-8DEE-309D-AF23-1994A5056929`.
- `python3 qa/check-pitch-navigation-evidence.py`: **passed**. Native snapshot **15개**, JPEG **8개**, 소스 **5개**, kit **25개**, 실행 섹션 **37개**와 strict codesign, 원본 자산 SHA 및 음악/배치 복원을 검사한다. 결과는 `qa/generated/pitch-navigation/pinned/verification.json`이다.

## 실제 앱 시나리오

전용 사본 `~/Library/Application Support/circlr-integration-qa/fixtures/pitch-navigation.circlr`, ID `32E6C19C-BA3A-5769-8879-29A3D3C6F1F2`. 직접 작성한 3트랙·2 tone asset의 사본이다. 첫 MIDI lane에 0/24/48/60–76/96/127의 검사용 노트 14개를 추가해 총 17개, 서로 다른 음높이 16개를 만들었다. 기준 music r14, 추가 후 r15다. 실제 캔버스는 1024×673, JPEG는 1019×768이다.

| 경로 | 관찰 및 근거 |
| --- | --- |
| 작은 창 최초 후보 | 전체 연주 분포와 두 옥타브 C8/C9가 겹치지 않았다(`wide`). 노트 탐색 버튼이 아래로 밀리고 ‘연주 음역’이 줄바꿈되어, 조작 고정과 짧은 ‘맞춤’ 표시로 수정했다. |
| 직접 탐색 | `compact-click`에서 막대 클릭으로 lowest 104→50, D3–C♯5로 이동했다. 표시 창의 잡은 위치에서 오른쪽 31px를 드래그해 lowest 71이 됐다(`compact-drag-ax`). 음악 r15를 유지한다. |
| 키보드 | Right 71→72, Shift-Left 72→60, Home→0, End→104를 확인했다. Return은 궤도 first responder로 복귀하며 추가 노트·출력 시도가 없다(`compact-keyboard`). 최초 후보에서는 Esc 복귀도 확인했다. |
| 접근성 | native setValue로 lowest 60, C4–B5에 이동했다(`compact-accessibility-ax`). 전체 연주 16개 음높이와 24개 반음 범위를 AX로 읽는다. |
| 선택과 실제 편집 | 원래 F♯4 노트를 선택해 중앙 F♯4/MIDI 66·속성 66·강조 행을 확인했다. Up은 G4/67과 r16을 만들고 실제 ⌘Z 한 번으로 66·r17을 복원했다. 노트 길이/시작/세기와 다른 노트는 유지됐다. |
| 표시와 노트 탐색 | 1옥타브 전환은 72–83, 선택 보기는 66–77로 이동했다. 고정된 다음 노트 버튼은 다음 시간의 C1/MIDI 24를 선택하며 24–35로 이동했다(`compact-next`). |
| 빈 MIDI·다른 사용 | 빈 lane은 0개 음높이·빈 막대·이전/다음 버튼 비활성 상태다(r18). Undo 후 r19에서 다른 섹션 사용의 3개 노트·63–74 음역으로 전환됐으며 이전 사용의 17개 노트는 유지됐다. |
| 최종 고정 조작 | 중간 후보의 선택 보기 뒤 상단 모드가 스크롤에 일부 가려져 모드도 고정했다. 최종 `pinned-selected`/`pinned-next`에서 모드·수치·음역 막대·마디·하단 조작이 함께 보인다. 중앙 F♯4/66와 C1/24, 선택 보기/다음 노트 동작을 재검사했다. |
| 복원 | 검사용 노트를 원래 3개로 되돌린 후 맞춤은 63–74를 표시했다. 원래 자유 배치로 돌아가 저장/재열기를 검사했다. `restored`/`reopened`의 음악·신호·노트·자산·배치는 r14 기준 사본과 같다(music r20, portLayout revision 제외). |

최초 후보 UUID는 `E54D35DD-0DDA-3635-87BE-B0E93428C593`, 중간 `compact` 후보는 `AB0A44B1-A658-33A8-AB65-CC4168869F04`다. 최종 후보와 compact의 소스 hash 차이는 `MIDIOrbitWorkspace.swift` 한 파일의 모드 고정 배치뿐이다. 이전 후보/로그는 그대로 보존한다.

## 검토와 제한

viewport는 편집 화면의 로컬 상태다. 프로젝트·노트·Undo를 쓰지 않으며 세션 재열기 때 연주에 맞춰 초기화한다. 기존 노트 선택/시간 페이지/1·2옥타브 계약을 유지한다. 범위 이동의 Int overflow·비유한 입력과 0/127 경계를 처리한다. Native drag는 대상 identity/행 수 변경 때 해제하며 접근성·키보드도 같은 Core 범위를 쓴다. 새 네트워크·인증정보·파일 접근 경로는 없다.

CUA API에는 포인터만 이동하는 동작이 없어 hover만으로 행을 가리키는 시나리오는 미검증이다. 선택/수정/Undo의 중앙 표시와 두 옥타브 기준 음명은 실제 확인했지만 hover-only를 대신하지 않는다. 실제 VoiceOver 발화·보조기기 increment/decrement 전체와 10만 노트의 성능 검증도 남아 있다. 궤도 탐색을 grid/step 드럼 행 전체에 적용한 것으로 주장하지 않는다.

모든 snapshot의 output/audition attempts는 0이다. 기존 HAL 연결·정상 소리·녹음·MP4 출고 검증을 대신하지 않는다. 사용자 앱 0.19 build 21과 root `d88ea5d`, ports `1d304eb`는 유지했다. 세 QA 앱은 정상 종료했다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
