# build 69 MIDI 선택 수치 편집 검증

2026-09-09, `codex/daw-integration`, baseline `8d83f7e`. 실제 추가 슬롯이 없어 UI/UX → Core/native utility → 코드/보안 검토 → QA를 순차 수행했다. 이전 turn의 실제 `agent thread limit reached` 뒤 슬롯 상태가 바뀌지 않아 재시도하지 않았다. 전체 DAW/UX 목표는 진행 중이다.

## 결과와 산출물

- 최종 앱: `qa/generated/midi-inspector/refined/써클러 통합 검증.app`, 0.20.0 build69, UUID `9D5D89DF-3A39-3992-9258-7F96874D2202`. 최초 후보 UUID `FD4A1BD2-CB12-312D-8D8B-ABAA7D32CFE1`. 둘 다 정상 종료했다.
- 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/midi-inspector.circlr`, ID `2FB6C728-FC54-5318-B685-B297E9DF0CD1`. 직접 작성한 3트랙·2 tone, 32섹션과 다른 곡의 편곡을 보존했다.
- 새 scratch `.build/midi-inspector-quality`: Swift491개, 실패0, 26.073초. 새 Core/agent 검사6개 포함. Python29개, 실패0, 0.203초. 물리 출력 의존 기존 `testArrangementRenderExportAndPlayback`만 제외했다.
- debug13.45초, release66.16초. 최초 native 검사 뒤 MIDI 인스펙터의 복제/삭제 위치·중복 안내·레이블 글자 크기만 수정하고 최종 release35.59초/native 검증을 수행했다. 전체 테스트 이후 Core·MCP·kit는 동일하다.
- `python3 qa/check-midi-inspector-evidence.py` 통과: 상태/전체 문서14개, 화면25개, 최종 소스8개 hash, Mach-O37개 section, kit25개 hash, 두 후보 codesign. 최초3상태/3화면과 최종11상태/22화면을 구분했다.
- 원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 두 자산 checksum 유지. 물리 출력·audition·녹음 시작0. root/ports 및 사용자 앱0.19.0 build21은 별도로 유지했다.

## 실제 작업

| 검사 | 결과와 근거 |
|---|---|
| 최초 가시성 | 네 필드는 보였으나 복제/삭제가 스크롤 아래로 밀림. `multi-initial`. 실제 UI 요구 미충족으로 판단해 수정 |
| 최종 작은 창 | 1024×768, 콘솔이 열린 상태에서 스텝/궤도의 네 상대 입력과 선택 해제·복제·삭제·퀀타이즈를 스크롤 없이 확인. 단일 선택도 네 실제 값이 같은2열로 표시됨. `multi-refined`, `orbit-multi`, `single-piano` |
| 최초 상대 입력 | 음정+2가 한 번 적용(r15), Undo 한 번으로 원래 음악(r16). `transpose-initial`, `initial-undone` |
| 키보드 입력 | 음정+2 → Tab → 시작+1박 → Tab → 길이+0.25박 → Tab → 세기+5 → Return. 각3개 노트에 정확히 적용, r16→20. 음정[68,71,75], 시작[1,2,3], 길이0.75, 세기[75,77,79]. `tab-to-start/length/velocity`, `relative-applied` |
| 원자적 오류 | 길이−1과 세기+60은 각각 모든 노트 범위 오류를 해당 입력/AX에 표시. Return 뒤 포커스·입력값을 유지하고 Esc로 취소. 음악과 revision은 r20 그대로. `length-rejected`, `velocity-rejected`, `invalid-inputs-unchanged` |
| Undo | 세기만 먼저 Undo해 세기 차이 복원, 나머지 세 항목도 Undo하여 원래 전체 음악(r24). `velocity-undone`, `relative-undone` |
| 단일 편집 | 피아노롤에서 Tab으로69번 노트를 선택. 기존 절대 세기72→84(r25), Undo로 복원(r26). 다른 노트와 타이밍/길이는 동일. `single-piano`, `single-velocity` |
| MCP 실제 적용 | 다중 선택 음정 입력에4를 미확정으로 남긴 뒤, `edit_notes` length_delta(+0.125박)와 velocity_delta(−5)를 하나의 apply로 실행(r27). 노트 ID·간격과 세기 차이 보존. `mcp-relative-result`, `mcp-applied` |
| 오래된 쓰기 거절 | 동일 MCP packet을 이전r26으로 보내 stale_revision 거절. GUI의 미확정4도 Return에서 대상 변경 오류로 거절. 음악에는 MCP 변경만 남음. `mcp-stale-rejected.txt`, `draft-stale-rejected`, `mcp-applied` |
| 복제/삭제 | 상단 복제 아이콘은 선택3개를2.75박 뒤 새 ID로 복제(r28), Undo 후 상단 삭제로3개만 제거(r30). 삭제된 상태는 입력/작업을 숨기고 선택 안내를 표시. Undo2회로 삭제와 MCP 변경을 복원(r32). `duplicate-applied`, `delete-applied`, `all-undone` |
| 재열기/궤도 | 저장 문서 재열기 후 궤도 보기로 전환, 같은 상대 세기−10을 적용(r33)하고 Undo(r34). `reopened`, `orbit-multi`, `orbit-velocity`, `final-restored` |
| 전체 보존 | 최종 r34의 음악은 초기 r14와 동일. 보기 `circleLayout`만 freeform→orbit으로 변경. 전체 문서 비교에서 노트·원본/다른 사용·음색·효과·오디오·포트 binding 보존 확인 |

Tab 캡처의 AX는 선택된 문자0을 제공하지만 포커스 항목 문장을 생략한다. 각 화면의 실제 선택 위치와 네 가지 서로 다른 입력이 반영된 전체 노트 데이터를 함께 대조했다. `single-refined`와 `single-selected`는 단일 선택을 시도하던 중 여전히 다중 선택을 표시한 화면으로, 단일 선택 통과 근거는 `single-piano`다. 모든 선택의 ‘같은 음높이’는 선택한 음높이들의 집합을 유지하므로 단일 선택을 만들지 않는다. 스텝 행 이름의 AX 클릭은 `elementHasNoFrame`으로 거절되어 피아노롤의 키보드 선택으로 이어갔다. 이 스텝 AX 프레임 경로는 이번 변경의 성공으로 주장하지 않는다.

## 검토 및 남은 범위

Core는 결과를 별도 lane에 계산하고 모든 선택이 유효할 때만 반환한다. 비유한 길이·Int 극값·최단 길이·원 밖 길이·세기 경계를 검사했다. relative0은 no-op이며 이전에 짧아진 서클 바깥의 기존 tail도 그대로 보존한다. ID/미선택 노트/오디오를 유지한다. GUI는 기존 NumberEditIdentity/commit 검증을 사용하고, 상대 입력은0을 기준으로 매번 새 변화량을 받는다. 선택 요약에서 ID 집합을 한 번 계산해 각 노트마다 전체 선택을 재검색하지 않는다.

MCP는 기존 절대 `velocity`1–127 계약을 바꾸지 않고 `velocityOffset`−126…126을 추가했다. Python에서 bool/소수/NaN/범위 초과를 거절하며 native에서도 필요한 인수·note/node ID·revision·결과 범위를 검증한다. 같은 Core를 사용해 GUI/MCP 차이를 줄였고 실제 transaction/stale/GUI draft 충돌을 확인했다. 네트워크·권한·인증 경계를 확대하지 않았다. 최종 변경 범위의 미해결 출고 차단 결함은 발견하지 못했다.

선택 노트·오디오 커서·오토메이션 점 자체의 문서 영속화, 스텝 행 이름의 AX 프레임, 보조 편집 폼의 가시성은 후속 작업이다. 전문 음악 제작의 실제 장치 재생·녹음·VoiceOver 발화와 사용 중인 앱 교체는 별도 완료 조건이며 이번 수치/화면 검사가 이를 대신하지 않는다.
