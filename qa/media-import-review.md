# build 26 · 파일 가져오기 검증

2026-09-08, `codex/daw-integration`, 기준 `415e62b`. 이 체크포인트는 공통 파일 import·메뉴·세션 미디어 수명을 구현한 progress다. Finder 드래그·Splice 연동 완료나 사용자 앱 출고 판정은 아니다.

## 자동 검사와 패키지

- 전체 Swift **245개, 실패 0, 21.644초**: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 기존 실제 출력 장치 의존 1개 검사를 제외했다. `qa/generated/import/history-swift-tests.log`.
- 새 Core/Audio 검사 **9개**: batch atomicity, 기존 MIDI/연결/다른 사용/마스터 위치 보존, 명시적 arrangement·pattern·track, freeform 위치와 orbit timing, 잘못된 입력/서라운드 거절, 스트리밍 취소, 원본 삭제 후 portable 렌더, 저장→Undo→저장→Redo. 마지막 사전 검증 순서 보완 후 `verified-import-tests.log`에서 9개를 재확인했다.
- Python MCP/kit **26개**, `python-tests.log`. 도구/키트 schema는 바꾸지 않았고 App의 메뉴/MCP 저장이 공통 `saveSession`을 사용한다. 새 QA Python helper 3개도 컴파일했다.
- 최종 release 성공 **16.52초**, `verified-release.log`. 최종 QA 앱은 `qa/generated/import/history/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build 26, UUID **`19280F9A-E604-3C69-99CB-02D5B07F1B39`**. 초기/중간 후보는 별도 경로로 보존했다.
- `prepare-import-qa.py --candidate history`가 kit 25개 hash와 signature를 검사한다. `check-import-evidence.py`는 최종 source/package의 파일 기반 Mach-O **37개 section** 일치와 signature, 원본 fixture manifest SHA를 재확인한다. `verification.json`은 passed다.

## Native 관찰

전용 `fixtures/import.circlr`, ID `5B220E1C-87F8-5309-B4EF-5C28D45ACA37`. 기존 authored tone 2개와 직접 작성한 MIDI만 사용했다. `verify-import-native.py`는 정확한 bundle/version/project/path와 recording idle을 검사한다. 로컬 산출물은 `qa/generated/import/`에 있으며 Git 업로드 대상이 아니다.

| 시나리오 | 관찰과 근거 |
|---|---|
| 메뉴의 다중 파일 | ⌘I에서 tone-1/2 두 파일 선택. tracks +2, assets +2, music revision +1. 기존 section 정의/포트 binding/마스터 좌표 유지. `batch.json`, `history-added.json` |
| 한 번의 Undo | 실제 ⌘Z 한 번으로 전체 이전 음악과 routing 복원. `undo.json`, `history-undo.json` |
| 오류 batch | 정상 a-valid.wav 다음에 z-broken.wav를 함께 가져와 전체 프로젝트가 변경되지 않음. `rejected.json`은 `undo.json`과 manifest 일치 |
| 캔버스 초점 | 초기 후보가 첫 audio로 확대해 다른 파일이 잘 보이지 않는 점을 수정. 다중 import 뒤 section 선택, editorAddress=null, 1024×673 canvas. `final-batch.json/png`, 최종 `history-added.json` |
| MIDI 미리보기 | authored.mid의 7개 노트 트랙, 파일 116 BPM/섹션 120 BPM, 길이 확장 선택을 표시. 최소 창에서는 내부 목록 스크롤. 취소 후 음악 변경 없음. `midi-preview-ax.txt/png` |
| 선택 중 문서 변경 | 오디오 panel을 열어 둔 상태에서 정확한 QA 프로젝트 이름을 MCP로 변경. 파일 선택 확정 시 stale revision 안내, asset 추가 없음. rename은 ⌘Z로 복원. `stale.json`, `stale-ax.txt`, `restored.json` |
| 저장/Redo 수명 | 최종 앱에서 import→저장→⌘Z→저장→⇧⌘Z. Undo 저장으로 패키지에서 새 미디어가 없어져도 세션의 owned import 경로로 복원. `history-added/undo/redo/redo-save.json` |
| Redo 이후 렌더 | 패키지 미디어가 제거된 상태에서 바로 앱의 MCP export 실행. **34초·48 kHz·stereo·24-bit**, peak **0.1191711426**, completed. `history-export.json`, `history-export-audio.json`, `history-redo.wav`. 실제 출력 장치를 열지 않은 오프라인 렌더다 |
| 한국어 오류 | 최종 앱에서 broken.wav만 선택하면 파일명과 형식·손상 확인 안내. music r24 유지. `history-rejected-ax.txt/png` |
| 복원/재열기 | 마지막 ⌘Z·저장·재열기 뒤 name/tracks/assets/sections/arrangements/signal/portLayout이 초기 QA 음악과 일치. r24, dirty=false. `history-restored/reopened.json` |

File panel의 초반 좌표/AX 클릭과 즉시 이어진 키 입력 일부는 선택 상태를 바꾸지 않았다. 경로 입력은 실제 `PathTextField`에 값을 지정했고 파일 목록의 Down/Shift Down으로 선택 상태를 확인한 뒤 Return을 눌렀다. 시도만으로 성공을 기록하지 않았다. 첫 다중채널 test fixture의 AVAudioFormat 생성 실패는 유효한 6채널 WAV fixture로 수정한 뒤 거절 동작을 검사했다.

## 코드·파일 경계 검토

동일 실행자가 `p1zza-code-reviewer`·`p1zza-security-reviewer` 기준으로 diff와 전체 새 모듈을 읽었다. 사용자 요청 후 독립 reviewer spawn을 시도했지만 `agent thread limit reached`가 반환되어 독립 검토로 세지 않는다.

검토 중 두 문제를 수정했다. 첫째, `addTrack`이 기존 master 위치를 덮으므로 import 완료 시 기존 signal 좌표를 보존한다. 둘째, 저장이 asset 경로를 패키지 상대 경로로 바꾸면 Undo 저장 이후 Redo가 파일을 잃으므로, package에는 portable copy를 유지하면서 열린 session에는 원래 local source 경로를 남긴다. 두 동작을 회귀 검사로 고정했다.

I/O는 로컬 regular file, 지원 확장자, 크기/개수/채널/길이 제한을 검사한다. 파일명은 UI 이름에만 쓰고 destination은 UUID다. 원본을 쓰거나 삭제하지 않는다. 실패 정리는 이 작업이 만든 `import-UUID` 디렉터리에 한정한다. 성공한 복사본은 Undo/Redo/복구 때문에 보존한다. MainActor의 project/revision/generation과 worker 취소가 늦은 적용을 막는다. security-scoped access는 복사가 끝나거나 실패하면 해제한다. 인증정보·외부 전송·새 권한 요청은 추가하지 않았다.

## 남은 검증과 다음 단계

- file-URL drop의 AppKit 등록/대상/overlay 제외/beat 계산/MIDI 연결은 빌드했다. **Finder↔앱의 실제 드래그 제스처, hover 화면, 혼합 파일/overlay/다수 섹션/다른 박자의 드롭은 미검증**이다. 현재 CUA는 창별 screenshot/좌표를 제공하며 교차 창의 위치를 확정하지 못해 임의 좌표로 성공을 추정하지 않았다.
- `NSFilePromiseReceiver`, Splice companion/로컬 검색, MIDI CC·tempo map, import용 MCP job과 중복 catalog/GC는 아직 구현하지 않았다. 다운로드 중 file promise를 성공한 파일 URL로 처리하지 않는다.
- 실제 STOP 버튼의 복사 도중 취소와 복사 도중 파일 교체는 native 미검증이다. worker 취소·stale Core revision·panel을 열어 둔 채 음악 변경은 각각 구분된 근거다.
- import의 새 track은 기존 graph 생성 규칙에 따라 빈 MIDI·악기·믹스·출력도 갖는다. audio-only track의 기본 노드 수를 줄이는 작업은 이후 생성/탐색 계약과 함께 다룬다.
- 실제 마이크·VoiceOver·전체 밀집 조합·장치 lifecycle·출고용 MP4 동기는 기존 E gate에 남아 있다. 사용자 0.19 앱과 다른 QA 앱, 원본 곡은 교체하지 않는다.

이 변경은 private `zeztto/circlr`의 같은 개발 branch에 source/docs/tests/helper만 기록한다. 오디오·프로젝트·빌드 앱·인증정보·로컬 설정은 제외한다.
