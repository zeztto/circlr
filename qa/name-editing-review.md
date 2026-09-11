# build 45 이름 편집 검증

## 결과와 범위

`codex/daw-integration`, baseline `eacdc8d`. 이름은 입력 중 초안으로 보관하고 Return/Tab/다른 컨트롤 클릭에서 한 번 적용한다. Esc는 현재 모델 이름을 복원하고 캔버스 키보드 포커스를 돌려준다. ⌘S/⇧⌘S와 UI 프로젝트 교체는 활성 이름을 먼저 확정한다. MCP 저장은 미확정 UI 초안을 적용하지 않는다.

빈 이름·여러 줄·256자를 넘는 새 이름과 외부 이름/revision/대상 변경을 거절한다. 오류는 기존 헤더 안의 밑줄·아이콘·AX 도움말로 표시한다. 기존 긴 이름은 건드리지 않으면 보존하며 불변인 앨범 사운드 제목은 일반 Text로 표시한다. 주 캔버스와 legacy 섹션/트랙/리듬/그룹의 live 이름 필드를 공통화했다. 기존 global 전체 적용 draft는 유지한다.

직전 subagent 호출의 `agent thread limit reached` 이후 동일한 한도를 반복 조회하지 않았다. UI/UX → native Swift utility → 읽기 전용 code/security review → QA를 순차 전환했다. 독립 에이전트 리뷰로 주장하지 않는다.

## 자동 검사와 패키지

- Swift **363개**, 실패 0, 25.191초: `.build/name-editing-tests-guard.log`. 기존 물리 출력 의존 `testArrangementRenderExportAndPlayback` 1개 제외. 새 Core 10개는 연속 입력·한 번 적용, 조합 중 확정 보류, Unicode/공백, 빈 값/여러 줄/길이 제한, 기존 긴 이름, 취소·외부 변경·초기 포커스와 reentrant 종료를 검사한다.
- Python **26개**, 실패 0: `.build/name-editing-python.log`.
- 최종 release **24.95초**: `.build/name-editing-release-guard.log`.
- 최종 앱: `qa/generated/name-editing/guard/써클러 통합 검증.app`, `com.circlr.integrationqa`, 0.20.0 build 45, Mach-O UUID `6F1150EA-78F2-3C9B-84C1-8A31F3EBD1FA`.
- `python3 qa/check-name-editing-evidence.py`: **passed**. Native snapshot **21개**, JPEG **8개**, 소스 **9개**, kit **25개**, 실행 섹션 **37개**와 strict codesign, 원본 자산 SHA 및 이름 외 음악/배치 보존을 검사한다. 결과는 `qa/generated/name-editing/guard/verification.json`이다.

## 실제 앱 시나리오

전용 사본 `~/Library/Application Support/circlr-integration-qa/fixtures/name-editing.circlr`, ID `17463B94-AEE0-561D-9498-911B1C04D649`. 직접 작성한 3트랙·2 tone asset을 복제했다. 캔버스 1024×673, JPEG 1019×768에서 검사했으며 출력·미리 듣기·마이크/MIDI 입력은 시작하지 않았다.

첫 후보의 key event 처리로는 ⌘S가 이름을 확정하지 못했다(`save-shortcut-failed.json`). `AppStore.save`/`confirmDiscard`에 활성 이름 resolver를 연결한 `save` 후보(UUID `D2B146B1-5AB0-3879-90F5-C7F9E81D865B`)에서 아래 전체 시나리오를 확인했다. `final-*` 파일은 이 후보의 근거다.

| 시나리오 | 관찰 및 근거 |
| --- | --- |
| 연속 입력과 Return | `Midnight Keyboard 45`를 입력하는 동안 r16과 기존 모델 이름을 유지했다(`final-draft`). Return 한 번에 r17, 실제 ⌘Z 한 번에 원래 이름·r18로 돌아갔다. Return 후 캔버스가 first responder다. |
| Unicode와 저장 | 한글·일본어·emoji를 CUA paste로 전달했다. 입력 중 r18, ⌘S에서 r19·dirty=false이며 MCP save를 호출하기 전에 디스크 manifest를 읽어 동일한 이름을 확인했다(`final-unicode-saved`). 재열기 후에도 보존됐다(`final-unicode-reopened`). |
| 취소와 오류 | 새 초안의 Esc는 r19를 유지하고 Unicode 이름을 복원했다. 빈 입력에서 Return/⌘S를 눌러도 r19와 저장된 이름이 유지됐으며 헤더 높이 변화 없이 오류를 표시했다. |
| Tab·blur | Tab은 r20, 다른 숫자 필드 클릭은 r22에서 한 번 적용했다. 각 변경은 MCP Undo 한 번으로 복원했다. 숫자 값은 변경하지 않았다. |
| MCP 충돌 | `Local draft` 입력 중 MCP로 이름을 `Agent title`로 변경했다(r24). Return은 충돌 오류를 표시하며 로컬 초안을 보존했다. Esc는 최신 모델을 복원하고 실제 ⌘Z로 외부 변경을 복원했다. |
| 대상 전환 | `Target draft` 입력 중 다른 출력 서클로 이동했다. r25를 유지하고 이전 악기/새 출력의 이름을 변경하지 않았다(`final-target-switched`). |
| 그룹 | 편집 진입 후 자동 선택된 이름에 `Routing Group`을 입력하고 Return으로 적용했다. 그룹 변경은 기존 비음악 layout 계약대로 music r25를 유지한다. 실제 ⌘Z 한 번으로 이름을 복원했다(r26). |
| 불변 제목 | 앨범 사운드의 편집 화면에 제목은 Text로 표시되고 `서클 이름` 입력 필드는 없다(`final-sound-readonly`). |
| 복원 | Unicode 재열기 후 MCP의 단일 이름 편집으로 원래 이름을 복원했다. `final-restored`/`final-reopened`의 음악·신호·노트·자산·배치가 기준 사본과 같다(r27, portLayout revision 제외). |

읽기 전용 검토에서 모델이 변경을 거절했을 때 초안을 소비하는 경로를 발견해 native Swift 수정으로 전환했다. 최종 `guard` 후보는 setter 이후 모델 값 일치를 확인하고 거절 시 초안을 유지한다. 다른 AppStore로 view가 재사용될 때 이전 registry를 해제하는 순서도 정리했다. `save`와 `guard` 후보의 소스 hash 차이는 `CommittedNameField.swift` 한 파일뿐이다.

최종 후보에서 Unicode 초안(r27) → ⌘S 확정/디스크 저장(r28) → 빈 이름 Return/⇧⌘S 거절 → Esc → 실제 ⌘Z 한 번(r29) → 저장/재열기를 다시 수행했다. `guard-*` 근거에서 모델/초안과 포커스를 확인했다. 최종 프로젝트의 이름 외 데이터와 원래 이름은 기준 사본과 일치한다.

## 검토와 남은 범위

이름은 데이터로만 사용하며 shell/명령으로 평가하지 않는다. 인증정보·권한·MCP 저장 스키마를 변경하지 않았다. registry는 weak coordinator resolver를 보관하고 view 제거/대상 전환/성공/취소에서 해제한다. 확정 전에 identity·baseline을 검사하고 apply 전 draft를 소비해 중복 이벤트를 막는다. setter가 거절하면 보관한 draft로 돌아간다.

실제 macOS IME 조합·후보 선택은 미검증이다. Unicode 붙여넣기는 이를 대신하지 않는다. Core의 raw 여러 줄/256자 검증과 별개로 AppKit 붙여넣기의 모든 정규화 조합, legacy 창 전체·실제 VoiceOver·Save As 성공 및 프로젝트 교체 대화상자 전체 흐름도 남아 있다. 녹음 중 모델 거절 분기는 소스 검토만 수행했으며 실제 녹음은 시작하지 않았다.

모든 snapshot의 output/audition attempts는 0이다. 기존 HAL 출력 지연·실제 소리·녹음·MP4 출고 검증을 대신하지 않는다. 사용자 `dist/써클러.app` 0.19 build 21, root `d88ea5d`, ports `1d304eb`를 보존했다. 세 후보 앱은 모두 정상 종료했으며 마지막 QA 프로세스 수는 0이다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
