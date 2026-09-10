# MIDI 서스테인 파일 가져오기·내보내기

상태: build150 SMF 연결의 회귀·Release·아래 native 파일 검증을 완료했다. 최종 import/export 독립 감사도 PASS했다. [DSP 검증175](175-midi-sustain-render.md)의 내장 신스 지원과 이번 파일·preview·내보내기를 구분한다. GUI/MCP의 페달 이벤트 직접 편집과 실제 장치 연주는 아직 별도 후속 범위다.

## 파일과 적용 계약

raw scanner는 파일 전체 track/channel 순서에서 CC64의 raw 0…127을 보존한다. 0…63은 off, 64…127은 down이며 원본 값을 이진 숫자로 정규화하지 않는다. CC121=0은 sustain off를 추가하고 기존 wheel/selector reset 계약을 유지한다. reset-only 파일에는 불필요한 표현 객체를 만들지 않으며 0이 아닌 reset은 미지원 issue다.

`preserve`가 기본이며 `omit`을 명시한 경우 pitch bend와 sustain을 모두 제외한다. GUI와 MCP preview는 같은 선택 track의 표현·issue를 보여준다. 선택한 미지원 표현은 적용을 막고, channel 9의 표현도 지원하는 것으로 처리하지 않는다. 단순 미리보기는 음악을 바꾸지 않는다.

Core typed import는 기존 schema7 저장·offset·말미 이벤트를 포함한 길이·합산 예산·atomic 처리를 사용한다. 이제 SMF parser가 sustain을 전달한다는 점이 이전 typed 입력만 가능한 단계와 다르다. MCP `import_midi`는 기존 tempo/pitch capability와 함께 `midiSustainImport: 1`을 요구한다. track별 sustain summary는 이벤트 수·초기/최종 raw와 down 상태·마지막 event beat를 제공한다. 실제 wire와 GUI 적용 결과는 통합 검증에서 대조한다.

## 명시적 내보내기 끝

`MIDIExpressionExport`는 sustain이 있으면 유효한 `sustainEndBeat`를 요구한다. source별 raw CC64 초기값·순서와 종료 tick의 원본 이벤트를 기록한 뒤 명시적 끝에 pedal-up을 합성한다. 표현 없는 source도 해당 파일 안에서 필요한 off seed를 받아 이전 상태 유입을 막는다. 합성 종료를 원래 raw 이벤트와 동일한 데이터라고 주장하지 않는다.

노트·표현이 저장 끝을 넘으면 거절하고 PPQN 960 양자화 뒤 최소 note tick도 끝 안에 있어야 한다. 한 source의 실제 key-held 동음 중첩은 거절하며 페달 유지 중 재타건과 혼동하지 않는다. 독립 source channel 배정·channel 9 예약과 기존 표현 없는 파일 경로를 유지한다. 파일 생성 성공을 모든 backend의 pedal 지원으로 해석하지 않는다.

## 통합 검증 기준

- CC64 양끝·경계·같은 tick 순서·cross-track carry·CC121 reset/issue, preserve/omit·channel 선택과 말미 이벤트를 확인한다.
- 명시적 끝·합성 pedal-up·PPQN·동음 중첩/재타건·표현 없는 source seed·legacy bytes 및 SMF 재가져오기 의미를 비교한다.
- GUI/MCP preview·적용·오류·취소·Undo·schema·다른 use 보존과 저장/재열기를 실제 실행 범위로 기록한다.
- 지원하는 내장 신스의 오프라인 파일 연주·바운스/복원과 raw/의미 왕복을 구분한다. 실제 I/O·청취와 페달 이벤트 직접 편집은 별도다.

실제 테스트·Release·native 결과와 남은 검증 경계를 아래에 기록한다. 기존 source·프로젝트와 다른 작업자의 변경은 보존한다.

## build150 실행 결과

Swift 회귀 666개·실패 0개가 28.581초에 통과했다 (`.build/sustain-smf-regression-final.log`). Python MCP 최종 재실행도 24개·실패 0개, 0.015초에 통과했다 (`.build/sustain-smf-mcp-final.log`). Release는 86.84초였으며 (`.build/build150-release.log`) package·QA 서명도 PASS했다.

`sustain150`의 JPEG/AX 7쌍에서 initial r233/schema6→GUI preserve import r234/schema7과 omit preview 전환을 확인했다. 실제 `exported150.mid`는 beat 64의 종료 off를 포함했다. Undo r235·Redo r236 뒤 저장하고 재열기 r236을 캡처했다. 최종 manifest 독립 비교도 PASS했다.

MCP melodic 파일은 이벤트 5개, exported 재가져오기는 종료 합성을 포함한 7개·마지막 beat 64를 확인했고 명시적 연장이 필요한 preview issue를 표시했다. drum channel 9는 preserve 미지원과 omit preview 정상을 확인했다. GUI drum 적용·취소는 이번에 실행하지 않았으므로 이 MCP preview 결과로 대체하지 않는다.

Documents에서 NSOpenPanel로 선택하지 않은 drum 파일의 MCP read가 Darwin `open`(`__open`)에서 대기했다 (`preview-hang.sample.txt`). Stop으로 복구하고 같은 직접 작성 fixture를 QA AppSupport에 복사한 뒤 preserve/omit preview를 완료했다. OS 권한과 관련됐을 가능성은 있으나 원인은 확정하지 않았고 Undo 문제로 해석하지 않는다. 소스 수정 없이 파일 접근 경로를 구분해 검증했다.

물리 I/O는 실행하지 않았으며 시도 수는 0이었다. QA 앱을 종료하고 사용자 production PID 86114를 유지했다. 다음은 페달 이벤트 직접 편집과 파일 읽기 권한 대기의 사용자 안내·취소 경험이다. 전체 DAW·실제 청취 완료로 확대하지 않는다.

`independent-import-export-audit.json`은 Undo r235=initial r233/schema6 음악, Redo r236=import r234/schema7 음악을 revision/hierarchy 제외 기준으로 확인했다. final r236=reopened r236은 전체 manifest·hierarchyView가 정확히 같았으며 실제 PID는 65593→66286으로 바뀌었다.
