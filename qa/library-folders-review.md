# 라이브러리 폴더 관리와 오류 복구 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `e41983c`, 0.20.0 build 53. [사용 흐름과 수락 기준](../docs/67-library-folder-workspace.md)에 따라 development-lead → UI/UX → native Swift utility → 읽기 전용 security/code review → QA를 순차 수행했다. 직전 실제 sub-agent dispatch는 `agent thread limit reached`로 거절됐고, 이번 turn에서는 변하지 않은 한도를 다시 호출하거나 독립 리뷰로 표현하지 않았다.

## 검사와 최종 후보

- Swift **396개**, 실패 0, **24.770초**. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. 기존 물리 출력 장치 검사는 제외했다. 새 5개 검사는 고유 이름 유지, 짧은/깊은 공통 parent 구분, 없는/같은 경로 fallback, Unicode 정규화와 대소문자를 확인한다.
- Python **26개**, 실패 0, **0.204초**. 첫 release **34.39초**, 파일 수와 경고의 병기 **27.77초**, 명시적 Escape 단축키 **25.63초**. 후속 수정은 App 표시/키보드 경로이며 순수 표시 계산과 Python은 검사 뒤 바뀌지 않았다.
- 첫 후보 UUID **9DC0D485-4A44-3E9B-B1EC-C599C349F93A**에서 실제 동명 폴더를 등록했다. 경고가 있는 폴더에서 정상 파일 수가 사라져 두 값을 함께 표시하도록 보완했다. 관리 화면에서 검색창 포커스가 없어지는 경로에는 닫기 버튼의 명시적 Escape shortcut을 추가했다.
- 최종 `qa/generated/library-folders/final/써클러 통합 검증.app`, UUID **C6266E15-DBD6-3607-AC02-FB2B3D9C1F33**. `python3 qa/check-library-folders-evidence.py`는 native snapshot **9개**(최종 7개), 최종 AX **14개**/JPEG **13개**, 소스 hash **4개**, Mach-O file section **37개**, Codex kit **25개**, build/version·strict ad-hoc codesign과 원본 보존을 확인했다. 메뉴 screenshot 한 번은 도구에서 unavailable을 반환해 해당 메뉴는 AX만 보관했다.

## 실제 흐름

**1019×768** 창에서 콘솔을 열고 기존 **850×560** overlay 안에서만 작업했다. 원래 등록된 `library-editing/samples`와 그 파일 4개를 보존했다. 직접 작성한 두 tone을 `Nordic/Samples`, `Citypop/Samples`에 같은 이름 `Folder tone.wav`로 복사하고, Nordic에는 0-byte WAV, Citypop에는 1-note MIDI를 작성했다. 0-byte 파일은 catalog에서 제외되며 Nordic에 `1개 파일 · 1개 항목을 읽지 못했습니다`가 표시된다. 이 파일은 QA 전용이며 제품 음악으로 포함하지 않는다.

| 검사 | 관측 결과 |
| --- | --- |
| 동명 폴더 | 세 폴더가 `library-editing/samples`, `Nordic/Samples`, `Citypop/Samples`로 구분됐다. 각 행은 실제 전체 경로·파일 수·읽기 상태와 파일 보기/등록 해제를 표시했다. 원본을 삭제하지 않는다는 안내가 목록 위에 있었다. |
| 재시작·Escape | 최종 앱을 새로 실행한 뒤 세 bookmark를 다시 읽었다. 검색창이 없는 관리 화면에서 Escape로 overlay가 닫히며 r14를 유지했다. |
| 검색 왕복 | `Folder tone` 검색→Shift Down으로 두 파일 선택→폴더 관리→파일 검색을 실행했다. 같은 검색어·선택 2개·현재 파일이 유지되고 음악/r14는 그대로였다. 결과 행에도 폴더 경로가 표시됐다. |
| 바로 보기 | Citypop의 파일 보기는 검색어를 비우고 해당 폴더의 오디오/MIDI 2개를 표시했다. 필터 메뉴는 같은 경로 구분을 사용하고 제거 하위 메뉴는 없어졌다. |
| 혼합 오류 | 전체 선택과 Return은 MIDI 혼합을 거절했다. 이유가 footer 한 곳에만 나타났고, MIDI 행 하나를 선택하면 혼합 오류가 없어지고 기존 MIDI 트랙 선택 버튼이 활성화됐다. |
| 입력 오류 복구 | 0개 선택에서 Return은 입력 오류와 안내 닫기를 표시했다. 오디오 체크박스를 선택하면 그 오류가 없어졌다. 다시 같은 오류를 띄워 안내 닫기를 눌러도 Nordic의 읽기 경고는 유지됐다. 모두 r14였다. |
| 가져오기·등록 해제 | 같은 파일명의 서로 다른 tone 두 개를 가져오면 r15/트랙 5개/asset 4개가 됐다. 관리에서 Nordic과 Citypop의 등록을 각각 직접 해제한 뒤에도 imported 음악·미디어 4개 checksum이 유지됐다. 기존 폴더 1개/파일 4개는 남았다. |
| 원본 복원 | Escape로 캔버스 복귀 후 Cmd-Z 한 번으로 r16/원래 음악을 복원했다. 저장·재열기 후 name/global/tracks/sections/arrangements/assets/patterns/signal/portLayout/circleLayout을 baseline과 비교했다. portLayout revision만 제외했다. |

## 검토와 남은 범위

표시용 root 위치는 bookmark를 읽는 기존 비동기 scan 안에서 얻고 MainActor/generation 검사를 통과한 결과만 반영한다. 파일 ID·bookmark 형식·경로 검증·batch staging/Undo·프로젝트 schema는 유지한다. root 위치/폴더 경고는 메모리와 UI에만 있으며 프로젝트나 MCP snapshot에 추가하지 않았다. 관리 화면 진입은 preview를 취소하며 해당 화면에서는 preview 실행을 거절한다. 선택·필터 오류와 scan 경고의 저장소가 분리돼 있다. 추가 차단 결함은 찾지 못했다.

실제 VoiceOver 발화, 등록 16개 전체의 긴 경로 조합, 읽기 권한 철회/디스크 분리 중 scan, 관리 화면의 Alt-Space 실제 입력은 별도 미검증이다. 물리 출력은 시작하지 않았고 preview guard는 코드로 확인했다. 중첩 폴더의 물리 파일 catalog dedup, 자동 감시, file promise/Splice 직접 drop, 미해결 bookmark를 다른 위치로 재연결하는 흐름은 후속이다.

원본 `studio.circlr` manifest SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**, 원본 tone 2개와 QA 파일 4개 checksum, root `d88ea5d`, ports `1d304eb`, 사용자 앱 **0.19.0 build 21**을 보존했다. QA 프로젝트 ID는 **80DD8E13-FF7D-50BD-A48B-F365F96E625B**이며 원래 음악을 복원해 저장했다. 두 QA 앱은 정상 종료했다. 출력/audition 시도는 **0회**다. 실제 재생/녹음·MP4 회귀와 사용 앱 교체는 이번 변경에 포함하지 않는다. 소스·문서·테스트·QA 도구만 private branch에 반영한다.
