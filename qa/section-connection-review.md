# 섹션 순서·전환 편집 검증 — build 64

2026-09-09, `codex/daw-integration`, 기준 `a37bd01629e584dbff560446a53673a2e96b2047`. 직전 실제 dispatch의 `agent thread limit reached`와 총 1 slot에 맞춰 UX → Core/native utility → 읽기 전용 검토 → QA를 순차 수행했다. 독립 agent 검토는 수행하지 않았다.

## 변경과 자동 검사

섹션 설정 안의 긴 다음 섹션 메뉴와 별도 연결 행을 기존 연결 편집기로 합쳤다. 설정 맨 위의 `섹션 순서·전환` 또는 기존 L/연결 버튼으로 검색·분기 선택·전환·재연결·해제를 다룬다. 직접 섹션은 편곡 순서의 #번호·이름·곡/편곡 경로를 사용한다. 전환 화면에도 번호와 전체 이름/도움말을 표시한다. 별도 창·dock은 추가하지 않는다.

- SectionConnectionWorkspaceTests 6개/실패0, 0.004초. 같은 이름/32개 섹션·NFD/전각/#정확 검색, generic 포트 이름 보존, 단일 연결 자동 선택/no-op, 다중 분기·종료 섹션 재개와 실제 ArrangementCompiler 경로, 다른 편곡의 선택 유지, 누락/다른 주소 거절과 전체 모델 동등성을 검사했다.
- `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`: 463개/실패0, 26.295초. 기존 HAL 환경의 물리 playback 한 테스트는 제외했다.
- `python3 -m unittest mcp.test_server qa.test_agent_kit`: 28개/실패0, 0.217초. MCP/번들 키트 계약은 변경하지 않았다.
- 초기 release66.07초, UUID `A0F917A7-592E-32BB-9797-E632F0320895`. Native에서 케이블 행의 반복 경로와 Tab 순서를 수정한 `final` 후보38.31초, UUID `9DBE8410-1FDB-3DC5-B9E7-8508B5FF0DBE`. 전환 화면의 동명 구분을 보완한 **최종 `refined` 후보36.35초**, UUID `12C08C59-8B1A-3F6F-9CC4-70B5F13A02DD`, 0.20.0 build64.
- 최초 관련 빌드는 테스트에서 존재하지 않는 Occurrence.useID를 참조해 실패했다. 실제 Occurrence.use.id로 고친 뒤 관련/전체 검사를 실행했다. 그 후 제품 Core는 바뀌지 않았다. 후속 두 후보의 수정은 케이블 행/Tab과 전환 endpoint 표시이며 각 최종 바이너리에서 관련 동작을 검사했다.

## 실제 앱·MCP 검증

`qa/prepare-section-connection-qa.py`는 원본 authored fixture의 3트랙/2asset 사본에 동명·긴 이름의 32개 section use와 다른 곡의 1개 use를 만든다. 첫 섹션은 #2/#3 두 분기와 각각 lowpass/0.125마디 전환을 갖고 처음에는 #2가 재생 경로다. 테스트용 데이터는 생성된 QA 사본에만 들어간다. ID `D6A45651-8842-5174-A74F-AD3F10A22A9E`, baseline r14. GUI 입력을 실제로 수행하고 native MCP로 정확한 프로젝트·revision·문서와 출력 카운터를 기록했다.

| 흐름 | 확인 결과 |
|---|---|
| 설정 첫 버튼 / L | 기존 연결 편집기로 직접 진입. OUT 재생 경로와 같은 편곡의 31개 대상 표시 |
| 한글 NFD / 전각 #３ / #999 | 동명 #2/#3 두 결과 / 정확히 #3 한 결과 / 빈 결과 |
| 기존 연결 재선택 / 필터로 선택을 숨긴 뒤 Return | r14 유지. 선택하지 않은 #32 한 결과도 자동 연결하지 않음 |
| 긴 #32를 ↓·Return으로 연결 / Undo·Redo·Undo | r15/16/17/18. 원래 분기·전환·다른 곡 보존, 추가된 케이블만 왕복 |
| Tab·Return으로 분기 선택 | 검색→목록→위치→범위→전환→재연결→해제→위치→다음 분기 순서를 실제 기록. #3 선택 r19, Undo r20, Redo r21 |
| 도착 #2에서 들어오는 케이블의 재생 분기 선택 | r22에 출발 #1의 chosenEdges만 수정, 현재 #2 선택과 hierarchyView 전체 보존. Undo r23 |
| 전환 편집 직접 진입 / 길이 변경 / Undo | 앞 #1→뒤 #2의 기존 전환 화면. 0.125→0.25마디 r24, Undo r25. 효과와 다른 케이블 보존 |
| 전환에서 연결 복귀 / #3을 #4로 재연결 | r26에 같은 edgeID·chosenEdges·lowpass와 길이를 유지하고 to만 변경. Undo r27 |
| #3 분기 해제 / Undo | r28에 남은 #2가 자동 재생 경로. r29에 케이블과 #3 선택 복원 |
| 원래 분기 복원 | r30에 #2를 선택. 모든 음악/편곡/연결/binding/배치가 baseline과 동일 |
| 오디오 / MIDI 포트 전환 | 그룹 노출 IN을 포함한 오디오 대상5개, MIDI OUT 대상1개. 조회 전후 manifest 전체 동일 |
| 최종 전환의 #1/#3 표시와 #3 클릭 | 번호·이름/경로 help가 일치하고 실제 세 번째 use로 이동. 음악 r30 유지 |
| 최종 저장·종료·재열기 | refined-saved/refined-reopened manifest 전체 일치. 실제 #3 선택 복원 |

처음 최소 폭1024·콘솔 펼침 화면에서 곡 경로가 케이블마다 반복되어 분기 버튼을 아래로 밀었다. 본문은 번호/이름/포트로 줄이고 전체 경로는 help·AX에 유지했다. 분기와 전환의 Tab 순서를 본문 순서로 맞췄다. 최종 화면에서 두 분기의 선택·전환 버튼을 바로 읽을 수 있으며 아래쪽 재연결/위치는 기존 연결 목록 스크롤로 접근한다. 긴 대상 이름은 두 줄과 전체 AX/help로 제공한다. 이미 존재하는 일반 음악 설정의 스크롤 깊이는 후속 범위다.

전환 화면의 이름만으로는 동명 #2/#3을 구분하지 못하는 점을 발견해 동일한 번호 표현을 추가했다. 최종 refined 바이너리에서 #1→#3 표시와 실제 대상 이동을 확인했다. Native 검증 중 한 번 CUA가 앱 상태 변경을 감지해 동작을 거절했다. 최신 AX를 다시 읽은 뒤 동일한 app handle로 이어갔고 앱을 중복 실행하지 않았다. 한글은 NFD paste로 검사했으며 하드웨어 IME 조합이나 VoiceOver 발화 검증을 주장하지 않는다.

## 읽기 전용 검토·보존·한계

SectionFlowSelection은 실제 케이블의 양 끝 주소와 편곡을 확인하고 Compiler와 같은 단일/다중/isEnd 의미를 사용한다. 선택은 해당 편곡의 chosenEdges와 출발 use.isEnd만 변경하며 activeArrangementID·다른 음악·전환을 보존한다. 이미 재생될 경로는 no-op이다. UI의 새 분기 버튼은 현재 케이블을 다시 검사하는 Core 경로로 한 mutate를 수행하며 현재 선택을 이동시키지 않는다. 전환 진입은 유효한 케이블인지 검사한 뒤 연결 화면을 닫고 기존 편집기로 이동한다. 기존 context-menu 분기 선택도 검증 경로를 공유한다.

대상 검색은 기존 scene와 CirclePortCatalog.normalize의 호환성·scope·그룹 binding 경계를 그대로 사용한다. 필터는 endpoint를 만들거나 교체하지 않으며 선택이 결과에서 사라지면 해제한다. 이름 draft는 연결 진입 전에 기존 규칙으로 확정한다. 새 네트워크·shell·파일 읽기·인증 경로는 없다. 제품과 QA helper의 입력 경계 검토에서 차단할 결함을 발견하지 않았다.

`qa/check-section-connection-evidence.py` 통과: native 상태27개, AX/JPEG22쌍, Tab sequence2개, 전체 문서 비교, 최종 소스8개, Mach-O37 section, codesign 및 Codex kit25파일. 초기/중간 hash7개에서 변경된 공통 파일은 PortConnectionsEditor.swift 하나다. refined hash에는 추가로 TransitionWorkspace.swift를 포함하고 기존7개의 hash가 중간 후보와 같음을 확인한다. 최종 바이너리가 현재 소스의 release와 일치한다.

원본 fixture SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱0.19.0 build21을 보존했다. Owned QA 프로세스0, 등록 폴더1, 모든 capture에서 output/audition attempts0·재생/녹음 없음. 생성 앱/미디어/fixture/상태/화면은 Git 제외다. 물리 재생·녹음과 전체 VoiceOver는 남아 있다. 재열기 검증은 문서와 저장된 선택/카메라의 복원이며 연결 검색어·임시 포트 선택·전환 페이지의 자동 복원을 보장하지 않는다.
