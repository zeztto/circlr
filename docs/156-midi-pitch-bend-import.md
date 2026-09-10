# MIDI pitch bend 가져오기 계약과 검증 계획

상태: build134에서 아래 계약을 구현하고 회귀·Release·native 가져오기/저장 검증을 수행했다. 최종 재열기·stress 독립 감사와 QA 앱 종료 확인도 완료했다. [기존 내장 신스 검증](155-pitch-bend-synth-and-import-return.md)과 이번 파일 가져오기를 구분한다.

## 표현 보존 정책

기본 정책 `preserve`는 지원하는 pitch bend/RPN range 상태를 노트와 함께 보존한다. `omit`은 사용자가 명시적으로 표현 제외를 선택한 경우에만 적용한다. 지원하지 못하는 표현을 자동으로 버려 가져오기 성공으로 처리하지 않는다. 파일을 고르는 것만으로 원래 프로젝트를 변경하지 않으며 미리보기에서 영향과 오류를 확인한다.

Audio 계층은 raw MIDI scanner로 controller 정보를 읽고 기존 AudioToolbox 노트 추출 경로를 유지한다. 파일 전체에서 같은 channel의 controller 흐름을 수집하며 다른 track에 기록된 controller도 해당 channel의 노트에 적용한다. 같은 시각의 이벤트는 안정적인 파일 순서를 유지한다. 서로 다른 가져온 source의 음정 상태를 악기 전역 상태로 합치지 않는다.

RPN 0의 pitch bend sensitivity와 raw wheel 상태를 보존한다. 지원하지 못한 표현의 issue는 영향을 받는 선택 channel 또는 파일 전체 범위를 구분한다. 선택하지 않은 channel의 제한을 무조건 모든 트랙에 적용하거나, 전역 issue를 선택 변경만으로 숨기지 않는다. channel 9의 SoundBank 경로는 pitch bend 연주를 지원하지 않으므로 `preserve`에서 명시적으로 막고 `omit` 선택을 제공한다. sampler·AU의 bend 지원을 이번 importer로 추가한다고 주장하지 않는다.

## Core 적용과 길이

`MIDIImportPart.pitchBend`는 가져오기 위치 offset을 적용해 source에 저장한다. 표현을 포함한 후보는 schema5를 사용하며 노트·표현·길이·tempo를 하나의 검증된 변경으로 적용한다. 오류가 나면 부분 노트 추가, schema 승격 또는 tempo 변경을 남기지 않는다. GUI와 MCP는 동일한 Core 계약을 사용한다.

노트가 끝난 뒤의 bend도 `preserve`에서는 잃지 않는다. 가져오기 extent는 `max(notesEnd, lastBendBeat)`를 기준으로 하며 섹션 clock의 끝은 마지막 bend보다 엄격히 뒤여야 한다. 경계와 같은 길이를 성공 처리해 마지막 상태를 소실시키지 않는다. 파일 tempo 적용 범위의 끝도 노트 끝과 마지막 bend 위치의 최댓값을 반영한다. `omit`은 표현을 제외한 노트 경로이며 보존 정책의 길이 계산을 조용히 섞지 않는다.

공유 원본과 다른 use의 음악은 그대로 유지하고, 선택한 use에만 새 연주를 만든다. 기본 현재 tempo 유지와 명시적 파일 tempo 적용 정책은 표현 보존 정책과 별개로 선택한다. stale project/revision과 잘못된 대상은 후보 commit 전에 거절한다.

## GUI와 MCP

GUI는 기존 MIDI 가져오기 화면의 고정 영역에서 표현 issue와 적용 불가 이유를 보여준다. `preserve`가 기본이며 명시적 `omit`으로 회복하는 동작을 제공한다. 트랙 선택을 바꾸면 실제 선택 channel에 해당하는 issue를 다시 계산한다. 오류를 스크롤 아래에만 두거나 미지원 backend를 지원하는 것처럼 표시하지 않는다.

MCP capability는 `midiPitchBendImport: 1`로 계약을 식별한다. 가져오기 요청과 preview는 같은 표현 정책과 issue 범위를 사용한다. preview 성공은 음악 적용 성공과 다르며 issue가 있는 결과를 commit 성공으로 해석하지 않는다. revision·job·취소 및 atomic 변경 계약을 유지한다. 정확한 wire 필드와 결과 구조는 구현된 소스와 최종 검증에서 대조한다.

## 검증 계획

- Parser: raw 양끝·중심, 같은 tick의 안정적 순서, 다른 track에서 같은 channel을 제어하는 경우, RPN 0 range-only 변경, 지원하지 않는 channel/global issue를 확인한다. 기존 AudioToolbox 노트 결과도 보존한다.
- Core: 가져오기 offset·schema5·Undo와 저장/재열기, late bend의 extent, 마지막 bend와 section 끝의 엄격한 경계, 파일 tempo 범위, invalid 후보의 완전한 불변을 검사한다. 다른 use와 공유 원본을 비교한다.
- GUI/MCP: preserve 기본값, 명시적 omit 회복, 선택 channel 변경, channel 9 SoundBank 거절, 같은 요청의 동일 결과와 stale 거절을 비교한다.
- Native: 1024×768 창·122pt 콘솔에서 오류의 고정 표시와 정책 변경·적용·Undo·저장/재열기를 AX/JPEG 및 manifest로 확인한다. 기존 no-I/O helper 환경을 사용하며 실제 출력·청취 성공으로 계산하지 않는다.
- 오프라인 음악 결과: 가져온 표현의 실제 내장 신스 PCM과 기대 음정 변화를 대조하고, 필요한 바운스·복원 및 자산 보존을 별도 증거로 남긴다. parser 통과만으로 음악 결과까지 통과했다고 선언하지 않는다.

테스트 수치·로그·최종 패키지와 native 결과는 실제 실행 후 기록한다. SMF bend 내보내기, 곡선 UI, MCP 표현 편집 명령, AU/sampler 및 물리 청취는 별도 후속 범위다.

## build134 구현과 검증 결과

Release는 85.97초에 통과했다 (`.build/build134-release.log`). UUID는 `4893ACF0-FFC1-39EF-9008-48C6648BB410`이며 helper 5개 빌드와 QA 패키지 strict 서명도 PASS했다. Core/Audio 회귀는 793개·내부 skip 2개·실패 0개, 99.893초였다 (`.build/build134-regression.log`). 실제 재생 포함 테스트 1개는 명시적으로 제외했다. 초기 실패는 Core 테스트의 `4.0.nextDown` 문법과 Audio fixture의 beat 0 tempo 중복을 수정한 뒤 해소했으며 제품 결함으로 계산하지 않는다. Python MCP 6개와 기존 27개 검사도 PASS했다.

소스 검토에서 MCP summary의 O(n²) 처리를 channel별 detached O(n) 집계로 수정했다. range 목록은 16개로 제한하고 전체 개수는 정확히 유지한다. GUI의 대량 flatMap 복제를 cached summary와 마지막 이벤트 조회로 바꾸고, 마지막 bend가 정확한 경계에 놓일 때 필요한 연장 표시도 수정했다. CC121 값 0은 wheel 중심 복귀·range 유지·null selector를 지원하며 reset-only drum은 nil 표현을 유지한다. 0이 아닌 값은 issue로 처리한다.

실제 native 화면은 1019×768·122pt 콘솔이었다. `qa/generated/midi-import-return/expression134`에서 unsupported 오류의 고정 표시와 적용 차단을 확인했다. 명시적 omit 적용은 r100에서 nil bend를 만들고 Undo r101에서 원래 음악과 schema를 정확히 복원했다. 지원하는 새 파일을 열면 정책이 기본값으로 돌아왔다. atBeat 1의 GUI r102와 MCP r98은 이벤트 위치 `[1, 1, 1, 2.5, 3]` 및 노트가 정확히 일치했다. MCP Undo r99도 원래 음악·schema를 복원했다. r102 저장/재열기에서 전체 hierarchyView와 표현을 확인했으며 자산 6개와 모든 I/O 시도 0을 유지했다.

255개 트랙·각 100,000개 이벤트의 stress 미리보기는 0.151초에 completed 상태와 제한 오류를 반환했다. pretty JSON은 508,107 bytes였다. UI action과 AX 확인까지 3,186ms에 budget 오류를 표시했고 Escape 후 r102 상태를 정확히 복원했다. 초기 Documents 경로의 open은 샘플링에서 `__open`에 멈췄으며 parser 지연으로 단정하지 않는다. 해당 job을 명시적으로 중단해 cancelled로 만든 뒤 QA PID 8185를 종료했다. fixture를 checksum 대조 후 QA AppSupport에 복사하고 PID 8426으로 재실행한 결과다. 하나의 연속 프로세스에서 모두 통과했다고 주장하지 않는다. 사용자 원본 PID 86114는 유지했다.

fixture 준비는 `qa/make-midi-expression-fixtures.py --stress`와 `qa/prepare-midi-expression-qa.py`를 사용한다. 위 테스트와 화면 결과는 SMF bend 내보내기·곡선 UI·MCP 표현 편집·AU/sampler 지원 또는 실제 청취 완료가 아니다.

최종 독립 감사에서 preserve/applied/reopened/stress-cancelled의 전체 manifest가 r102로 정확히 같았고, PID 8426 캡처의 JPEG viewport·AX focus 및 stress 고정 오류/적용 차단도 PASS했다. QA 앱을 Cmd+Q로 종료한 뒤 ps에서 PID 8185·8426이 없고 원본 PID 86114만 유지됨을 확인했다. 최종 codesign 재검사도 PASS했다. 번들용 `Resources/Codex` MCP server와 manifest를 생성 소스·패키지에 동기화했으며 manifest 전체 SHA와 MCP source parity도 PASS했다.
