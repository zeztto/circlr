# 라이브러리 일괄 가져오기 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `927c3dc`, 0.20.0 build 52. [사용 흐름과 계약](../docs/66-library-batch-import.md)을 기준으로 검사했다. 사용자 요청에 따라 독립적인 읽기 전용 리뷰를 실제 dispatch했으나 `agent thread limit reached`로 거절됐다. development-lead → UI/UX/native Swift utility → 읽기 전용 security/code review → QA를 순차 수행했으며 독립 agent 리뷰로 표현하지 않는다.

## 실행한 검사

- Swift **391개**, 실패 0, **25.212초**. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. 기존 물리 출력 장치 검사 하나는 제외했다. 새 5개 검사는 범위 확대/축소·정역방향·64개 상한·선택 제거·없는/중복 ID·표시 순서·폴더별 같은 이름·MIDI 혼합·파일/batch 크기·정수 overflow를 확인한다.
- Python **26개**, 실패 0, **0.196초**. `python3 -m unittest mcp.test_server qa.test_agent_kit`. 첫 release **34.66초**, 선택 변경 때 preview 취소를 보강한 최종 release **25.02초**. Core와 Python은 테스트 뒤 변경하지 않았으며 App의 후속 변경은 최종 release와 native로 검사했다.
- 최종 앱은 `qa/generated/library-batch/써클러 통합 검증.app`, UUID **E7A07E4E-AD8A-3FC7-920E-9173B8057A37**. `python3 qa/check-library-batch-evidence.py`는 native snapshot **9개**, AX/JPEG **각 19개**, 소스 hash **7개**, Mach-O file section **37개**, Codex kit **25개**, strict ad-hoc codesign과 원본 파일을 검사했다. 이 검사는 이번 로컬 증거 묶음에 대한 검사이며 다른 바이너리의 포괄적인 CI 검증을 대신하지 않는다.

## 실제 UI와 데이터

창 **1019×768**, 콘솔을 열어둔 상태의 단일 캔버스에서 기존 850×560 라이브러리 overlay를 사용했다. 직접 작성한 tone 2개를 QA 폴더 A/B에 복사하고, 손상 WAV 1개와 1-note MIDI 1개를 별도로 작성했다. 이 파일들은 제품용 음악이나 배포 소재가 아니다. 프로젝트는 `library-batch.circlr`, ID **51ABBBAD-3FF7-5795-8B93-8D04F89DC8B7**인 별도 사본이다.

| 검사 | 관측 결과 |
| --- | --- |
| 등록·검색 | 기존 `samples` 폴더 1개/파일 4개를 보존하며 native 파일 panel로 A/B를 등록했다. `Batch` 검색은 두 폴더의 WAV 2개만 표시했다. |
| 범위·체크박스 | 검색창 Shift Down은 1→2개, Shift Up은 2→1개로 바꿨다. 체크박스는 두 파일을 함께 선택했고 모두 선택/해제는 2/0개와 가져오기 버튼 상태를 맞췄다. 이때 r14/음악/출력 시도는 그대로였다. |
| 선택 범위 축소 | B 폴더로 필터하면 숨겨진 A 파일이 선택에서 빠졌다. 현재 정보 파일, 선택 수, 다중 오디오의 새 트랙 수를 같은 화면에서 확인했다. |
| MIDI 혼합 거절 | B의 오디오와 MIDI를 함께 선택하면 이유와 비활성 가져오기 버튼이 나타났다. 검색창 Return도 검증 오류로 거절되고 r14를 유지했다. MIDI 행 하나를 선택하면 기존 MIDI 트랙 선택 화면에서 1개 노트·채널 1을 확인할 수 있었으며 취소했다. |
| 손상 파일 | A의 정상 WAV와 손상 WAV를 함께 가져오면 복사·검증 실패를 콘솔에 표시했다. 트랙 3개·asset 2개와 전체 음악/r14가 baseline과 같았다. 정상 파일만 부분 적용되지 않았다. |
| 정상 batch | 서로 다른 A/B의 32초·48 kHz stereo WAV를 함께 가져오면 r15, 트랙 5개·asset 4개가 됐다. 새 오디오 lane 2개는 각 새 트랙의 0박에서 시작했고 sourceStart 0·duration 32초·sourceBPM 120을 가졌다. 다른 use의 음악은 그대로였다. |
| Undo·Redo·재열기 | 저장 후 Cmd-Z 한 번으로 r16/원래 음악 전체를 복원했다. Cmd-Shift-Z 한 번으로 r17/두 트랙을 복원했다. 저장·재열기 후 같은 음악과 미디어 checksum을 확인했다. portLayout revision만 음악 비교에서 제외했다. |
| 등록 정리 | A 등록을 제거하면 선택도 2→1개가 됐다. B 제거 후 0개/가져오기 비활성, 기존 폴더 1개·파일 4개를 확인했다. 검색을 비워 원래 4개 목록을 다시 확인하고 QA 앱을 정상 종료했다. |

처음 파일 panel 조작에서는 선택하려던 A 대신 상위 `samples`가 등록됐다. 새로 추가한 두 번째 항목만 제거했고, 파일 목록에 키보드로 A/B의 실제 selected row가 표시되는 것을 확인한 뒤 다시 등록했다. 기존 같은 이름의 폴더는 보존했다. 한 번의 clipboard 입력 timeout은 새 AX 상태로 확인한 뒤 경로 필드 입력으로 처리했다.

## 검토와 경계

코드 검토에서는 visible selection의 정확한 ID 일치·표시 순서·64개 상한, MIDI 단일 선택, 크기 합계의 overflow 방지, MainActor/generation/revision 보호, 한 번의 document mutation과 기존 staging/Undo를 확인했다. 파일 접근 검토에서는 등록 폴더별 read-only bookmark를 재해석하고 기존 경로·심볼릭 링크·종류·크기/mtime 검사를 각 파일에 적용함을 확인했다. 모든 `LibraryAccess`는 worker가 끝나는 Task의 defer까지 유지한다. snapshot은 선택 개수만 추가하며 파일명·경로·검색어를 추가하지 않는다. 추가 차단 결함은 찾지 못했다.

64개 UI 실입력, 실제 security-scope 권한 박탈 도중 작업, filesystem 변경 경쟁 주입, VoiceOver 발화는 미검증이다. 현재 파일 검사는 적대적인 filesystem race까지 제거했다는 보장이 아니다. 중첩 등록 폴더에서 같은 물리 파일을 표시하는 catalog dedup, 같은 이름의 폴더 표시 구분, 이미 해소한 가져오기 실패 안내의 자동 정리는 후속 UX 범위다. 이번 변경은 공식 Splice 원격 API나 file promise를 추가하지 않는다.

원본 `studio.circlr` manifest SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**, 원본 tone 2개·QA 샘플 4개 checksum, root `d88ea5d`, ports `1d304eb`, 사용 앱 **0.19.0 build 21**을 보존했다. QA 사본에는 검증 결과인 두 imported 트랙을 저장해 두었으며 원본을 덮어쓰지 않았다. 출력/audition 시도는 **0회**다. 실제 마이크·MIDI 입력·재생/MP4 회귀와 사용 앱 교체는 이번 검사에 포함하지 않는다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
