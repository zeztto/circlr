# build 47 드럼 스텝 행 탐색 검증

## 변경과 결과

`codex/daw-integration`, baseline `4d4f0ed`. 드럼 스텝에서 행 이름·샘플 이름·MIDI 번호를 바로 검색하고, 일치/전체 행 수와 빈 결과를 표시한다. 검색은 공백으로 나눈 모든 검색어의 부분 일치를 사용한다. 대소문자·전각 문자·악센트를 정규화하고 `c#`로 `C♯` 음명도 찾는다. 드럼 모드의 효과 없는 옥타브 버튼을 검색으로 바꿨으며 음정 스텝과 피아노 롤의 조작은 유지한다.

검색 Return은 결과가 있을 때 격자로 이동하고 Esc는 검색을 지운 뒤 복귀한다. 숨겨진 선택 행도 버튼으로 다시 보여준다. 행 추가는 검색을 지우고 현재 스텝 열을 유지한 채 해당 음높이로 이동한다. 노트는 셀 클릭/Return에서만 토글하며 행 이름 클릭과 접근성 행 버튼은 선택만 한다. Home/End와 PageUp/PageDown으로 행을 이동한다.

행 목록 변경 때 같은 음높이 커서를 가능한 한 유지하고, 첫 결과 또는 유지한 커서가 실제 보이도록 스크롤한다. 그리기/AX는 화면에 보이는 행으로 제한한다. AX action은 프로젝트·세션·선택·revision, 행 번호/음높이, 페이지와 격자를 확인하며 오래된 대상에는 적용하지 않는다.

## 검증 근거

- Swift **369개**, 실패 0, **26.116초**: `.build/step-row-navigation-tests.log`. 추가 Core 테스트 3개는 관측/샘플 매핑/추가 행의 합집합, 0–127 범위/중복, Unicode/번호/이름/공백 검색을 검사한다. 실제 출력 시작 테스트 `testArrangementRenderExportAndPlayback`는 기존 HAL 문제 때문에 제외했다.
- Python **26개**, 실패 0, **0.334초**: `.build/step-row-navigation-python.log`.
- 최종 release **24.61초**: `.build/step-row-navigation-release-final.log`. 최초 release는 50.63초였다. 마지막 수정은 Core 변경 없는 App 스크롤 보정이며 release 컴파일과 native 시나리오로 재검증했다.
- 최종 앱: `qa/generated/step-row-navigation/final/써클러 통합 검증.app`, `com.circlr.integrationqa`, **0.20.0 build 47**, UUID `2B3DB782-1DC0-3502-A88E-681631BC1279`.
- `python3 qa/check-step-row-navigation-evidence.py`: **passed**. Native snapshot **15개**, JPEG **7개**, 컴파일 소스 **5개**, kit **25개**, 실행 섹션 **37개**, strict codesign과 원본/사본 자산 SHA를 대조했다. 결과는 `qa/generated/step-row-navigation/final/verification.json`에 있다.

## 실제 앱 시나리오

전용 authored 사본은 `~/Library/Application Support/circlr-integration-qa/fixtures/step-row-navigation.circlr`, ID `D5236346-59DA-5FC4-9B92-4BEE9020A424`다. 원본은 3트랙·2 tone asset이며 수정하지 않았다. 3개 노트에 98개를 더해 MIDI 0–100의 101행을 만들었다. 1024×673 캔버스, JPEG 1019×768의 작은 창에서 콘솔을 열어 둔 상태로 검사했다.

| 경로 | 관찰 |
| --- | --- |
| 최초 검색·선택 | `96`은 1/101행을 표시한다. Return으로 격자에 복귀하고 행 버튼으로 노트를 선택해도 음악 r15·101개 노트가 유지된다. |
| 빈 검색·Esc | `no-match`는 0/101행·빈 결과와 숨겨진 선택 버튼을 표시한다. Return은 노트를 만들지 않았고, Esc는 검색을 지우며 96행이 보이도록 복귀했다. |
| 키보드 탐색 | Home 0, PageDown 4, PageUp 0, End 100행으로 이동하며 같은 1스텝 열을 유지했다. 화면의 약 5개 행만 AX에 노출된다. |
| 행 추가·Return·Undo | 새 127행 추가는 검색을 지우고 마지막 행으로 이동하며 음악 r15를 유지했다. Return은 127/beat 0/length 0.225/velocity 96 노트를 생성해 r16, ⌘Z 한 번은 r17·101개 노트로 복원한다. |
| 발견한 스크롤 결함 | 최초 후보는 음정→드럼 전환의 커서 100이 보이지 않았고 `c#` 필터 뒤 첫 결과 1도 화면 밖이었다. 목록 변경 때 커서로 스크롤하도록 보정했다. 최종 `final-mode`와 `final-filter`에서 각각 100/1행과 커서가 함께 보인다. |
| 최종 추가·AX 셀 | 검색 후 방향키로 3스텝 열을 선택한 뒤 127행을 추가해도 음악 r17을 유지했다. AX 셀 클릭은 127/beat 0.5의 노트만 추가해 r18, 실제 ⌘Z는 r19로 복원했다. |
| 샘플 이름 | 사본 악기를 기존 tone asset 2개의 sampler 매핑 125/126으로 잠시 바꿨다(r20). `검증 1`은 MIDI 번호 125/126에도 `1`이 있어 두 행, `검증 126`은 `126 · 검증 톤 1` 한 행만 표시한다. 악기는 Undo로 복원했다(r21). 샘플 청취는 하지 않았다. |
| 다른 사용·선택 복귀 | 다른 섹션 사용은 기본 음정 모드로 열리고 드럼 전환 시 검색이 비어 있으며 원래 66/69/73의 3행만 보인다. 66을 선택 후 `73` 검색으로 숨겨도 ‘선택한 드럼 행 보기’는 66으로 복귀한다. 실제 이름 좌표 클릭은 노트 토글 없이 69행을 선택했다(r21 유지). |
| 복원·재열기 | 첫 사용의 검사용 노트를 원래 3개로 복원했다. `restored`/`reopened`의 음악·악기·신호·자산·배치는 r14 기준 사본과 같다(r22, portLayout revision 제외). 원본 tone asset checksum도 유지된다. |

최초 후보 UUID는 `54F58FD9-3B82-3596-8E1D-814095A88660`다. 최종과 최초의 compiled source hash 차이는 `StepEditor.swift`의 스크롤 보정뿐이다. 이전 후보와 증거를 보존한다.

## 검토와 남은 범위

서브 에이전트 생성은 실제 `agent thread limit reached`로 거절돼 native Swift utility → 읽기 전용 code/input review → QA → development-lead를 순차 수행했다. 독립적인 서브 에이전트 리뷰로 주장하지 않는다.

새 네트워크·인증·외부 파일 접근 경로는 없다. 추가 행과 검색어는 편집 화면의 로컬 상태다. 검색/추가/선택/탐색은 프로젝트의 음악을 쓰지 않으며, 실제 셀 편집만 기존 `StepEditing`과 Undo 경로를 따른다. 지연된 행 이동은 대상 identity·요청 ID·페이지·격자·행 목록 변경 시 무효화한다.

실제 VoiceOver 발화, 보조 도구가 보관한 오래된 AX 객체의 호출은 미검증이다. 현재 AX 셀/행 동작은 native로 확인했고 오래된 객체의 거절은 소스 검토 근거다. 101행의 실제 가시 행 수를 확인했으나 전체 10만 노트 성능을 측정한 것은 아니다. 한국어 이름은 실제 Unicode 붙여넣기였으며 물리적인 IME 조합 테스트로 주장하지 않는다.

모든 snapshot의 output/audition attempts는 0이다. 기존 HAL 연결 문제, 정상 청취, 실제 MIDI/마이크 녹음과 MP4 출고 회귀는 남아 있다. 사용자 앱 0.19.0 build 21과 root `d88ea5d`·ports `1d304eb`를 유지했고 두 검증 앱을 정상 종료했다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
