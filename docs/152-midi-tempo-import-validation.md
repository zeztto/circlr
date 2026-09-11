# MIDI tempo 가져오기 구현과 검증

상태: build131 소스·기계 검증 결과를 기록한다. Release는 81.94초에 성공했으며 아래 native GUI/MCP·오프라인 바운스/복원·저장/재열기 범위를 검증했다. 전체 DAW·물리 오디오 완료로 판정하지 않는다. [계획151](151-midi-tempo-import-plan.md)의 선택지를 실제 도입 계약과 구분한다.

## 적용 계약

[MIDIImport](../Sources/CirclrAudio/MIDIImport.swift)가 MIDI format0/1의 tempo 정보를 읽고, [UseTempoOverride](../Sources/CirclrCore/UseTempoOverride.swift)가 이번 SectionUse에 initialBPM·changes를 보관한다. `keepCurrent`가 기본이며 기존 clock을 유지한다. `applyFile`은 파일 tempo를 선택 note 범위에 적용하고 구간 앞/뒤의 기존 유효 tempo를 보존한다. 다른 use·공유 section 원본은 바꾸지 않는다.

[MIDIImportEditing](../Sources/CirclrCore/MIDIEditing.swift)은 노트 추가·필요한 길이 연장·tempo 적용을 하나의 candidate로 검증하고 한 Undo로 반영한다. 시작 atBeat는 로컬 4분음표 박이며 extendSection은 기본false다. 파일 tempo 문제나 기존 오디오의 지원 조건을 넘으면 적용을 거절하며 keepCurrent로 조용히 바꾸지 않는다. 새 override는 schema4 경계를 사용하고 기존 문서의 단순 읽기·현재 tempo 유지와 구분한다.

가져온 tempo가 있는 동안 이번 use의 기존 BPM/source 변경은 거절한다. [UseTempoControls](../Sources/CirclrApp/UseTempoControls.swift)의 `이전 템포 설정으로 복귀`는 override만 지워 보관된 설정으로 돌아간다. node별 독립 tempo까지 비활성화하지 않는다. MCP는 `circlr_apply`의 `clear_use_tempo_override`에 arrangementID·useID를 명시해 같은 Core 해제를 사용한다.

## 에이전트 importer

새 `circlr_import_midi`는 runtime.capabilities.midiTempoImport=1과 최신 projectID·expectedRevision을 확인한 뒤 절대 로컬 path·arrangementID·useID를 받는다. 선택 trackIDs는 preview의 `index:channel` ID이며 생략하면 모든 note 트랙이다. path는 regular SMF format0/1·최대16MiB로 제한한다.

`previewOnly:true`는 트랙 목록·tempoChanges·tempoImportIssue·이전/예상 섹션 시간·previewIssue를 job 결과로 반환하고 문서는 바꾸지 않는다. preview job의 completed는 previewIssue가 없다는 뜻이 아니므로 실제 적용 전에 내용을 읽는다. 실제 applyFile에서 tempoImportIssue가 있으면 실패한다. 수정하지 않은 최신 revision으로 실제 import를 별도 요청하며 성공은 한 Undo 단위다. 에이전트 import는 현재 편집 선택을 보존한다.

[AgentMIDIImport](../Sources/CirclrApp/AgentMIDIImport.swift)의 파일 읽기/parse만 Task.detached다. preview 계산과 Core candidate 적용은 MainActor에서 실행하므로 전체 import 연산이 background라고 표현하지 않는다. jobID 반환 후 circlr_job의 terminal 상태를 확인한다. STOP은 generation·취소 guard로 늦은 적용을 막지만 이미 실행 중인 MainActor 계산을 선점 중단하는 의미가 아니다. 파일 읽기 뒤 project/revision을 다시 검증한다.

## 기계 검증 결과

- `.build/tempo131-tests-final.log`: 관련 496개 테스트, 실패0, 0.969초. 앞선 후보 로그와 구분한다.
- `.build/tempo131-render-tests.log`: MIDITempoRender 관련1개, 실패0, 0.349초. 노트/tempo/cutoff의 실제 오프라인 렌더 경로를 검사하며 native 연주 결과는 아니다.
- `.build/tempo131-mcp-tests.log`: importer/MCP13개, 0.004초 PASS.
- `.build/tempo131-mcp-regression.log`: MCP27개, 0.113초 PASS.
- `.build/tempo131-agent-kit.log`: kit9개, 0.106초 PASS. 이후 guide 수정에 따른 kit 재생성/검사는 별도로 확인한다.

Release 81.94초 성공을 확인했다. main UUID는 `CA474BEF-D894-38D2-9DD5-A20F5EFCC7B2`이며 독립 서명 검토도 PASS했다. guide 반영 후 최종 kit 9개 검사는 0.105초에 통과했다. 현재 native 결과는 아래에 기록한다. GUI의 파일 tempo 선택·오류·이전 설정 복귀, MCP preview/apply/cancel, Undo·schema·다른 use 보존·저장/재열기의 실제 확인 범위는 아래 결과를 따른다. source guard·mock 검사와 native 실행을 구분한다.

## 현재 native 결과

`qa/generated/midi-tempo/final131/mcp-summary.json`은 r90의 실제 MCP preview 무변경·keepCurrent Undo 일치·clear Undo 일치·취소 무변경·stale 요청 job 미생성·선택 보존을 확인했다. `mcp-unsupported-summary.json`에서는 오디오 구간/반복의 tempo 변화가 지원되지 않는 applyFile 요청을 원자적으로 거절했고 keepCurrent preview도 음악을 바꾸지 않았다. 두 경로의 검토는 PASS했다.

GUI에서 기본 정책·잘못된 입력·파일 tempo 적용 r91, 이전 설정 복귀 r92·Undo r93·import 취소 후 r93 유지를 확인했다. 대상은 A의 두 번째 use이며 노트 3개 모두 beat2·length4인 점을 대조했다. 독립 검토에서 공유 section 원본과 A 첫 번째 use의 보존도 확인했다. `gui-tempo-settings.jpg`와 `gui-reimport-ready.ax.txt` 등 실제 상태/화면을 근거로 사용한다.

오류 문구는 스크롤 아래에 있어 초기 JPEG에 보이지 않았다. 그 이미지를 오류 문구의 가시성 통과로 해석하지 않는다. 범위 초과의 GUI 안내와 음악 node별 설정 변경은 이번 native 검증에서 수행하지 않았다. MCP 오류 검사와 해당 GUI 미검증을 구분한다.

오프라인 export·바운스·원본 복원 및 최종 저장/재열기 결과는 다음 절에 별도로 기록한다.

## 최종 오프라인 제작·저장 결과

final131의 `tempo-production-complete.json`과 `tempo-pcm-independent.json`에서 export·바운스·원본 복원 job이 모두 completed임을 확인했다. 음악은 r93→바운스 r94→복원 r95다. 48kHz stereo 24bit 출력은 1,759,456 frames·약 36.655333초이며 body 33초와 tail 약 3.655333초를 포함한다. 바운스 전후 최대 차이는 1LSB, 원본 복원 WAV는 byte-exact다. 복원/기준 SHA256은 `f2628f4149e8ae91670c835e712285ed8cee02932a9878480975ef424050cda8`이다.

기존 자산 5개를 보존하고 바운스 archive 1개를 추가했다. saved.json=reopened.json=디스크 manifest는 r95/schema4에서 전체가 정확히 일치하며 reopen job도 completed다. QA 앱을 종료하고 원본 사용자 PID86114를 유지했다. integration-worktree/dist production 패키지의 strict 서명과 동일 UUID를 확인했고 `tempo131-production-package.log`에 기록했다. 독립 감사는 기존 보고서를 재사용하지 않고 WAV raw를 직접 계산해 PASS했다. 총 3,518,912 samples 중 618,320개 차이의 최대값은 1LSB였고 복원 PCM/SHA는 완전히 같았다. r93→r94의 edge 교체→r95 정확한 연결 복원과 muted archive, 원본 5개와 신규 자산의 checksum도 직접 확인했다.

다음 UI 점검은 스크롤 아래 오류를 수치 가까이 표시하여 Apply 불가 이유를 바로 알 수 있게 하는 것과 raw section 이름 대신 실제 대상 use의 별명을 명확히 표시하는 것이다. 현재는 후속 검토이며 구현 완료가 아니다.

## 남은 검증 범위

file tempo의 오프라인 렌더와 실제 import 바운스/복원, 오디오 지원 불가의 MCP 원자적 거절은 위 범위에서 확인했다. GUI의 모든 preview 경계·오류 가시성·음악 node별 설정은 검증 범위를 넓혀야 한다. 불필요한 실제 출력·MIDI 녹음·AU 실행은 요구하지 않는다. noIO 편집/오프라인 검증을 실제 청취·하드웨어 동기 성공으로 표현하지 않는다. 전체 DAW·CC/pitch bend·아티스트 기능은 별도 범위로 유지한다.
