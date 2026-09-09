# build 56 캔버스 보기와 편집 이력 검증

2026-09-09 · `codex/daw-integration`, baseline `0eafe25a7251c562b9bf51046ae982bb4b914562`. 개발 progress이며 전체 DAW/0.20 출고 완료가 아니다. [계약](../docs/70-canvas-view-history.md).

## 변경과 검토

궤도/자유 배치·그리드·스냅 메뉴와 명령 검색을 `setCanvasViewPreferences`로 연결했다. 세 값만 candidate에 적용해 dirty/recovery를 갱신하며 음악/포트 revision, Undo/Redo, 녹음 요청에는 관여하지 않는다. 전체 snapshot 복원은 현재 circleLayout과 같은 ID 앨범의 grid/snap만 유지한다. 실제 위치·그룹·spacing, 앨범 구조와 포트 전용 restore는 기존 의미를 따른다.

사용자의 에이전트 한도 해제 안내에 따라 독립 read-only 검토를 실제 dispatch했지만 `agent thread limit reached`로 거절됐다. UI/UX → native Swift/Core utility → read-only code/security review → QA를 순차 수행했다. 독립 에이전트 검토는 아니다. 현재 값 유지 범위, nil/다른 앨범 ID, Redo 무효화, 녹음 guard, 파일 저장 경계를 검토했고 최종 변경에서 고확신 결함을 발견하지 못했다. 외부 API·권한·업로드 scope는 확장하지 않는다.

## 자동 검사

| 검사 | 결과 |
|---|---|
| `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback` | 413개 / 0 실패, 26.168초 |
| `python3 -m unittest mcp.test_server qa.test_agent_kit` | 26개 / 0 실패, 0.229초 |
| `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` | 성공, 56.27초 |
| `python3 qa/check-view-history-evidence.py` | snapshot 12개, AX 13개/JPEG 12개, source hash 5개·kit 25개·Mach-O section 37개·strict codesign 통과 |

새 Core 검사 7개는 음악 Undo/Redo 중 변경한 보기, 실제 위치·그룹·spacing 복원, 다른 앨범 ID, 앨범 생성/제거, implicit orbit nil, 포트 전용 Undo와 다른 프로젝트 거절을 다룬다. 첫 포트 테스트가 no-op에도 revision 증가를 기대해 1개 실패했다. 실제 포트 이동을 선행하고 위치 복원/증가를 확인하도록 fixture를 수정했다. `.build/view-history-tests.log`에 최초 결과를, `.build/view-history-fixed-tests.log`에 수정 후 전체 결과를 보존했다. Python/release 로그는 같은 prefix다. 제외한 물리 출력 검사가 통과한 것은 아니다.

앱: `qa/generated/view-history/써클러 통합 검증.app`, 0.20.0 build 56, bundle `com.circlr.integrationqa`, UUID `4E187A19-2CD0-361B-9B7D-5FD5E6F2EBC1`. fixture ID `6BBB382F-9A63-50C0-B8C7-C18514A751FE`는 authored `studio.circlr`의 별도 두-use 사본이다. 생성 음악/화면은 QA 전용이며 제품 콘텐츠에 포함하지 않는다.

## Native 시나리오

| 작업 | 관찰 |
|---|---|
| 보기만 변경 | freeform/그리드 on/스냅 on → orbit/off/off. r14 유지, dirty=true, 저장 가능. 명령 검색에 Undo 없음 |
| MIDI 편집 후 보기 변경 | 첫 노트의 표시 시작 1→9.5, 내부 0→8.5, 길이 0.5 유지, r15. 이후 메뉴 세 설정을 바꿔도 r15 |
| 한 번 ⌘Z | r16, 첫 노트 내부 0·표시 1로 복원. 현재 freeform/on/on 유지, 피아노 롤 선택/편집기 유지 |
| Undo 뒤 명령 검색으로 보기 변경 | orbit/off/off로 변경해도 r16. 다시 실행 명령이 남음 |
| 명령 검색에서 Redo | r17, 내부 8.5·표시 9.5 복원. 현재 orbit/off/off 유지, 궤도 편집기·길이 0.5 유지 |
| 실제 서클 이동 | MIDI Undo r18 후 freeform에서 두 번째 섹션을 ⌥⇧→로 x=700→724 이동. 보기만 변경 후 한 번 Undo하면 x=700, orbit/on/off 유지, r19 |
| 재실행·재열기 | 저장된 orbit/on/off와 r19, 원래 음악·서클 위치 복원. 전용 앱 두 실행 모두 종료 |
| 초기 보기 복원·⌘S | freeform/on/on으로 복원해 dirty=true. ⌘S 뒤 dirty=false, r19 그대로. 최종 파일과 snapshot 일치 |

전체 문서에서 세 보기 값·음악 revision·저장 camera만 분리해 비교했다. 편집한 첫 노트와 이동한 섹션 위치 외의 변경이 없으며 마지막에는 모든 음악·실제 배치·보기 설정이 baseline과 같다. 원본 section/다른 use/자산 checksum을 보존한다. 보기 전환 후 MIDI 속성 및 궤도/선형 화면과 작은 창의 콘솔 공존을 JPEG/AX로 확인했다. 재열기 메뉴의 AX는 저장했으나 CUA가 해당 메뉴 screenshot을 unavailable로 반환해 그 한 장은 없으며, 설정 값은 문서/snapshot으로 확인했다.

## 보존과 후속

`studio.circlr` SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 두 오디오 자산, 기존 라이브러리 등록 1개를 보존했다. root `d88ea5d`·ports `1d304eb`와 사용자 `dist/써클러.app` 0.19.0 build 21은 그대로다. task-owned QA 프로세스는 0개다. 미디어·앱·캡처는 Git 제외, source/docs/tests/QA helper만 private branch에 반영한다.

실제 출력·audition·마이크 시도는 0이다. HAL 지연, 실제 녹음 중 보기 변경, VoiceOver 발화는 이번 native 검증 범위가 아니다. 위치·그룹을 위한 별도 Undo revision 모델이나 모든 접힘/펼침의 이력 제외는 구현하지 않았다. 다음 UI 검증은 작업 이동이 접힌 그룹을 펼친 뒤 Undo를 소비하는 경로의 의미를 정하고, 긴 계층에서 선택·복귀 포커스와 실제 그룹 편집 이력을 함께 점검한다.
