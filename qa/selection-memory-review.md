# build 71 편집 선택 복귀 검증

2026-09-09, `codex/daw-integration`, 기준ef72893. 추가 agent 슬롯이 없어 UX → Core/native utility → code/security review → QA를 순차 수행했다. 전체 개발·UI 목표는 진행 중이다.

## 결과

서클/원본·이번 사용별로 MIDI 다중 선택과 anchor·삽입 박, 오디오의 원본 시간 커서, 볼륨/팬별 오토메이션 선택을 기억한다. 현재 작업의 선택은 `StudioWorkspace.selection`으로 문서에 저장한다. 방문한 다른 서클의 선택은 세션 메모리다. 현재 작업만 재열기에서 복원하며 모든 방문 이력을 문서에 저장했다고 주장하지 않는다.

삭제된 노트/점·다른 clip/asset은 복원에서 제외한다. 오디오 커서는 현재 source 구간으로 제한한다. 원본시간 기준 커서를 Undo/Redo 전후에도 보존하며 음악 서클 밖의 기존 편집 선택에는 이 처리를 적용하지 않는다. 프로젝트ID·media generation·서클·원본 범위가 세션 캐시 key이며 reset 중 캡처를 막는다. 선택 복원 자체는 음악 mutation이나 Undo 항목을 만들지 않는다.

- debug12.67초. Swift496개·실패0·26.596초, Python29개·실패0·0.222초. 신규 Core5개: ID/anchor·중복/삭제·trim/asset/clip·parameter·비유한·legacy/workspace roundtrip. 최초 test 파일의 `.5` 표기 컴파일 오류를 `0.5`로 수정한 뒤 전체 테스트를 실행했다. 통과 로그는 `.build/selection-memory-tests-fixed.log`다.
- 최초 release71.78초. Undo/Redo 커서 보정 뒤 release41.50초, 음악 서클 한정 guard 뒤 최종release38.66초. 전체 Core/MCP 검사는 이후 동일하며 두 AppStore 보완은 release/native로 확인했다.
- `python3 qa/check-selection-memory-evidence.py`: 상태/전체 문서30개, 화면34개, 최종소스8개 hash·Mach-O37개 section·kit25개 hash·세 앱 codesign과 원본/사본 자산 checksum 통과.
- 원본 manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 유지. 사본ID `9205108A-825F-5F0E-A12B-B6B33497DB3B`, `~/Library/Application Support/circlr-integration-qa/fixtures/selection-memory.circlr`. 최종r33의 전체 음악은 초기r14와 동일하며 hierarchyView/revision만 다르다.

## Native 결과

| 경로 | 실제 확인 |
|---|---|
| MIDI 사용별 선택 | 첫 사용3개 → 다른 사용 처음0개/69노트1개 선택 → 첫 사용3개 복원. 같은 lane/note ID를 가진 두 사용도 분리됨. `midi-selected`, `midi-second-empty`, `midi-second-selected`, `midi-returned`. 음악r14 유지. |
| 원본 범위 | added lane의 공유 원본에는 해당 노트가 없으므로 선택0, 이번 사용으로 복귀하면3개. `midi-original`, `midi-use-restored`. r14 유지. |
| MIDI 재열기 | 저장 문서 open job 완료 후 같은3개/anchor 복원. 최초·중간·최종 후보에서 확인. `midi-reopened`, `final-reopened`, `guard-reopened`. |
| 볼륨/팬 | 볼륨 점2개와 팬 점1개를 생성(r17). gain의 두 번째 점과 pan의 첫 점을 각각 복원. MIDI 서클 왕복과 문서 재열기 후 gain2번째 선택 유지. `gain-returned`, `automation-returned`, `automation-reopened`. |
| 삭제한 점 | MCP로 선택된 gain2번째 점을 제거(r18). 서클 왕복 후 선택0/1, 다른 남은 점을 임의 선택하지 않음. 두 curve는 MCP empty points로 제거(r19), 원래 graph와 일치. `deleted-point-return`, `remove-selected-point.json`. |
| 오디오 분리 | 첫 서클7.25초, 다른 서클2.5초 각각 복원. 트림 시작2초 뒤 첫 커서는 선택 기준5.25초/원본7.25초. `audio-first/second/returned`, `audio-trim-returned`, `audio-second-returned`. |
| 최초 Undo 결함 | 트림 Undo 뒤 원본 커서가5.25초로 이동한 문제를 발견. `audio-undo-initial`은 성공 근거가 아니다. |
| 최종 Undo/Redo | 같은 원본7.25초 유지: 트림→Undo는 상대7.25초, Redo는 상대5.25초. 원본 구간 복원 후 재열기도7.25초. `refined-audio-undo/redo`, `audio-reopened`, 최종 `guard-audio-undo`. |
| MIDI 이력/선택 | 다중 음정+2를 Undo/Redo하고 다시 원래 음악으로 복원. 서클을 나갔다 돌아와도3개 선택. 최종 guard 후보에서도 MIDI 서클 안 Undo 확인. `refined-midi-edit/undo-returned/redo`, `guard-midi-undo`. |

`refined-midi-undo` 화면은 Escape로 부모에 나온 상태에서 Undo한 장면이다. 다중 선택 복귀 근거는 `refined-midi-undo-returned`와 최종 `guard-midi-undo`로 구분한다. 모든 테스트 입력은 고유 QA 사본에 한정했으며 다른 사용·원본 MIDI·오디오·음색·포트 binding을 전체 문서로 대조했다.

후보 UUID: 최초 `B08D8900-62C1-30E1-A572-7AE4C94A3617`, refined `A5A55C6C-0035-3450-81B3-021A1F67E38C`, final `F73D69DA-43B5-3DBC-9DA5-FD2ACD302200`. 이전 AppStore 소스를 별도로 보존해 각 후보 hash를 대조했다. 세 앱은 종료했다.

## 검토·남은 범위

현재 자료에 대한 선택 검증, optional workspace decode fallback, audio clip/asset 구분, reset guard, 음악 서클에 한정된 Undo 복원을 검토했다. 새 네트워크·인증·파일 접근 권한은 없고 원래 저장 경로를 사용한다. 이 변경의 출고 차단 결함은 발견하지 못했다. 음악 서클 밖 legacy editor의 전체 native 회귀는 별도이며 guard의 보호를 전체 legacy 검증으로 표현하지 않는다.

물리 재생/audition attempts0·녹음false. 기존 HAL 출력·실제 입력·VoiceOver/사용 앱 교체는 미완료다. root `d88ea5d`·ports `1d304eb`·사용 앱0.19.0build21과 원본 음악을 보존한다. 다음 UI 검사는 고정 눈금이나 화면 밖에 가려진 선택 노트의 직접 보기와 작은 창의 오디오 정밀 작업 가시성이다.
