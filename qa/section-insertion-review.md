# 섹션 경로 삽입 — build88 검증

2026-09-10. authored 원본 section을 공유하는 도입→절→후렴과 별도 보존 대조 편곡을 만들었다. build87의 ⌘K 독립 섹션 추가는 기존 경로를 그대로 두고 경로 밖 use를 추가했다. 이는 기존 독립 추가 동작으로 보존하며 명시적인 경로 삽입과 구분한다. 전체 경로에 포함되지 않은 use가 있어 기존 MCP reorder가 거절됐고 sequence 외 snapshot이 그대로였다. Undo로 baseline 음악 전체가 복원됐다.

초기 build88 UUID `41AB0A48-032C-3EC4-ADBE-F87A6C5E8AE6`에서 절 MIDI를 편집하다 명시적인 삽입 명령을 실행해 도입→절→새 섹션→후렴이 됐다. 기존 절→후렴 edge ID와 transition을 유지하며 목적지만 새 use로 바꾸고 새 use→후렴 edge를 추가했다. 새 use는 새 section을 참조하며 기존 세 use·원본 section·보존 대조 편곡은 그대로다. 새 section으로 이동하고 이름 입력이 선택된 화면을 root가 확인했으며 `initial/inserted.png/ax.txt`로 보존했다.

초기 후보에서 Undo는 baseline 음악 전체를 복원했고 Redo는 삽입된 문서 전체를 복원했다. 다시 Undo한 `initial/restored`도 baseline과 musicRevision/hierarchyView만 제외한 전체 비교가 일치했다.

최종 build88 UUID `DE8AF525-6D22-39AA-A7EE-FA95F22E4442`의 UI before/inserted/undone/redone/restored도 같은 삽입·이름 입력·Undo/Redo 계약을 확인했다. 초기 후보와 최종 후보의 증거는 분리 보존한다.

최종 후보에서 추가 bounded MCP 검증을 수행했다. 후렴 뒤 terminal 삽입은 기존 후렴의 isEnd를 false로 바꾸고 새 use만 끝으로 지정했다. Undo 뒤 절 다음에 중간 삽입하고 새 use를 절 앞으로 reorder해 도입→새 use→절→후렴이 되는 것을 확인했다. reorder 이전의 독립 추가 실패와 달리 명시적 삽입은 전체 선형 경로를 유지하므로 이 후속 편집이 성공한다. 각 MCP 삽입은 기존 canvas selection을 유지했고 다른 편곡·원본 section·asset과 다른 음악 필드를 보존했다.

추가 편집을 모두 Undo하고 저장한 뒤 같은 QA 프로젝트의 실제 open job completed를 확인했다. mcp-restored/reopened는 전체 manifest가 같고 최종 fixture는 baseline 음악으로 복원됐다. 이 검증 뒤 MCP 제어권을 root에 반환했고 추가 앱 호출은 하지 않았다.

checker는 baseline4·initial5·final13의 문서 캡처22개와 reorder 거절 기록을 읽어 passed를 출력한다. 원본 studio manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 원본·fixture authored asset2개의 실제 checksum이 일치한다. section 검증 캡처의 output/audition attempts는0이고 재생·마이크·MIDI 입력을 시작하지 않았다. 별도 출력 진단과 이 검증을 혼합하지 않는다.
