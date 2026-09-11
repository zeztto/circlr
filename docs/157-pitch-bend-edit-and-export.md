# 피치 벤드 편집과 SMF 내보내기 계약

상태: build135 구현·최종 회귀·Release 및 아래 native 검증을 완료했다. UI/artifact 최종 독립 감사도 PASS했다. 완료 범위는 아래에 기록한 편집·파일 왕복과 검증 시나리오에 한정한다. [파일 가져오기 검증](156-midi-pitch-bend-import.md)과 이번 편집·내보내기를 구분한다.

## 같은 캔버스의 직접 편집

노트·스텝·피치 벤드는 같은 MIDI workspace의 동등한 직접 선택 모드다. 별도 고정 사이드바나 악기 오토메이션 화면으로 이동하지 않는다. 선택 source의 시간·raw wheel·range와 시작 seed를 표시하고 이벤트 추가·삭제·표현 전체 해제를 제공한다. raw 정확값과 해석된 반음은 구분하며 MIDI의 hold 의미를 유지한다.

키보드만으로 모드 이동, seed와 선택 이벤트의 수치 편집, 추가·삭제·해제, 오류 복구와 취소가 가능해야 한다. 빈 이벤트 목록에도 도달 가능한 편집 지점이 있어야 한다. 입력 오류는 해당 수치 근처에서 드러내고 이름·수치의 미확정 입력을 해결하지 않은 채 다른 source에 적용하지 않는다. 실제 UI 구조는 독립 UI/접근성 검토를 거쳐 검증한다.

이번 use의 lane과 공유 pattern 원본을 구분해 표시한다. 공유 원본 편집은 모든 consumer에 영향을 주므로 단순히 현재 화면의 한 use만 바뀐다고 표현하지 않는다. 저장된 workspace에는 피치 벤드 모드와 필요한 편집 상태를 포함하고, MIDI 가져오기 취소 시 원래 모드·주소·선택으로 돌아온다. 가져오기 적용 성공의 새 target 선택과 stale project 복원 방지 계약을 유지한다.

## Core와 MCP

Core 편집 helper가 seed 변경, 이벤트 추가·수정·삭제, 전체 해제와 검증을 한 후보에 적용한다. 이벤트 index는 현재 sequence와 함께 검증하며 stale index로 다른 이벤트를 수정하지 않는다. 값·시간·정렬·개수·schema 경계를 위반하면 음악을 부분적으로 변경하지 않는다. 한 명령의 Undo와 저장/재열기로 raw·range·순서를 보존한다.

MCP는 표현 조회와 편집 capability를 명시하고 GUI와 같은 Core helper를 사용한다. 일반 arrangement/use/lane 주소와 공유 pattern/track 주소를 혼합하지 않는다. revision·event index·선택 범위 검증과 batch atomic 처리를 유지한다. 명령 이름과 wire 필드는 아래 build135 계약에 기록했다.

## SMF 표현 내보내기

raw pitch bend와 RPN range 및 source의 초기 상태를 SMF에 쓴다. 서로 독립된 source는 MIDI channel을 독립 배정하며 원래 channel과 다른 channel로 remap할 수 있다. channel 9는 예약하므로 독립 melodic source는 최대 15개다. 이를 넘으면 source를 조용히 병합하지 않고 명시적으로 거절한다.

시간은 PPQN 960으로 양자화한다. 원래 beat와 기록된 tick의 차이를 검증하고 동일 tick의 controller·note 순서를 결정적으로 유지한다. 초기 tempo와 tempo map 변경을 기록해 내보내기·재가져오기에서 음악 시간을 대조한다. 원래 source channel 번호 보존과 독립 표현 보존은 다른 계약이며 remap을 곡선 손실로 오해하지 않도록 안내한다.

표현이 있는 한 source 안에서 같은 pitch의 노트가 겹치면 note-off의 대응을 보장할 수 없는 export는 명시적으로 거절한다. 여러 source의 같은 pitch는 독립 channel 배정으로 구분한다. 표현도 없고 tempo 변경도 없는 기존 내보내기는 legacy byte-exact를 유지한다. AU/sampler의 표현 재생 지원이나 MPE·음표별 bend를 이번 내보내기로 추가한다고 주장하지 않는다.

## 검증 계획

- Core: seed/raw/range 경계, 같은 beat 이벤트 순서, index 범위와 stale index, add/edit/delete/clear, invalid 후보 불변, 공유 consumer 영향, Undo·schema·저장 왕복을 확인한다.
- MCP: 조회·편집 capability, 일반/공유 주소와 혼합 거절, GUI와 동일 결과, 잘못된 revision/index, 실패 batch의 완전한 불변을 확인한다.
- SMF: raw/RPN byte 순서와 초기 seed, 독립 source remap, channel 9 예약과 15개 한도, 동음 중첩 거절, PPQN 960 오차와 동일 tick 순서, tempo map을 실제 파일 재가져오기와 대조한다. no-expression/no-tempo-change legacy byte-exact를 별도로 검사한다.
- 음악: 내장 신스의 편집 전후 음정 및 source 독립성, 내보내기·재가져오기 후 의미와 PCM을 비교한다. SMF 양자화 차이는 허용 계약 안에서 설명하며 무조건 byte-exact PCM을 약속하지 않는다.
- Native: 작은 창과 콘솔을 유지한 같은 캔버스에서 노트/스텝/피치 벤드 직접 전환, 빈 곡선 접근, 선택 수치·키보드·오류·Undo·가져오기 취소 복귀·저장/재열기를 AX/JPEG 및 전체 hierarchyView로 대조한다. 실제 창 크기와 실행한 항목을 결과에 기록한다.

실제 출력·물리 오디오·청취는 별도 검증이다. 최종 결과는 실행 로그와 native 증거를 확보한 뒤 기록하며 전체 DAW 완료로 확대하지 않는다.

## build135 현재 구현과 wire 계약

MCP `edit_pitch_bend`는 `midiPitchBendEditing: 1` capability와 `change`를 요구한다. 일반 target은 `arrangementID/useID/laneID` 및 명시적 boolean `original`, 공유 target은 `patternID/trackID`만 사용한다. 두 주소를 혼합하지 않는다. 일반 lane은 inspect 결과, 공유 pattern은 snapshot에서 저장된 `pitchBend`를 조회한다.

`change.kind`는 `insert`, `update`, `remove`, `setInitial`, `clear`다. insert는 beat와 rawValue/range 중 정확히 하나, update는 이에 index를 더한다. remove는 index, setInitial은 channel/rawValue/range를 받는다. clear는 kind만 가진다. index는 현재 revision의 배열 주소이며 최신 조회 없이 과거 index를 재사용하지 않는다.

관련 구현 검사 18개와 전체 회귀 812개·내부 skip 2개·실패 0개를 확인했다. 전체 회귀는 99.937초이며 실제 재생 포함 테스트 1개는 별도로 제외했다. MCP 28개와 6개 검사도 PASS했다. 초기 Release는 86.42초에 통과했지만 리뷰의 선택 index 보호와 range/value 시각 구분 수정 전 후보다. 최종 Release 및 native 성공으로 계산하지 않는다.

## 최종 후보 결과

선택 index 보호·range/value 구분과 표현 구간 보기 개선을 반영했다. 최종 회귀는 816개·내부 skip 2개·실패 0개, 99.432초이며 실제 재생 포함 테스트 1개는 제외했다. 관련 검사 26개와 Python 28/6개도 PASS했다. guard 수정 후보 Release 84.52초 이후 최종 viewport 후보는 47.35초에 통과했다 (`.build/build135-viewport-release.log`). 최종 UUID는 `71176C06-A88A-32AE-819E-607674A26BC7`이며 dist build135·helper 5개·서명·Codex 패키지를 확인했다.

`expression135-final`의 실제 1019×768 창·122pt 콘솔에서 MCP 일반/공유 편집 r108→112와 Undo·atomic/stale/혼합 주소 거절을 확인했다. GUI range 편집 r113→Undo r114, 같은 beat 추가 r115·삭제 r116을 수행했다. 외부 삽입 r117 뒤 Delete는 음악을 바꾸지 않았고 Undo r118로 복구했다. batch 편집/선택 전환 r119→복귀 r120 뒤에도 Delete는 무변경이며 Undo 두 번으로 r122에 복구했다. 공유 빈 목록 Tab, seed r123·추가 r124·마지막 이벤트 삭제 r125의 seed 보존·전체 해제 r126의 nil을 확인했다.

저장 SMF는 186 bytes이며 독립 export 감사에서 pitch 69·시작 2·길이 2·velocity 100, raw/RPN 의미와 tempo 120@0→60@4→120@6을 확인했다. SHA256은 `888377d261d34d3bb520dd292b8111832307b8905ebdc2e03d8302f7724996ed`다. 앱 재가져오기 preview job도 r126에서 completed·issue 없음이었다. GUI import 취소와 재시작 후 음악·전체 hierarchyView·선택·viewport가 정확히 같았으며 자산 6개·I/O 시도 0을 유지했다.

CUA 메뉴 클릭은 다른 가져오기/닫힘으로 전달됐지만 command palette를 통한 실제 MIDI 저장은 성공했다. 제품 결함 여부는 미확정이며 임시 조사 변경은 모두 복원했다. QA 앱을 종료하고 사용자 PID 86114만 유지했다. 전체 DAW·물리 청취·모든 backend·완전한 UI 접근성 검증으로 확대하지 않는다.

최종 native UI 독립 감사(`native-ui-audit.json`)도 PASS했다. JPEG 7장을 직접 확인했고 before-import→cancel→reopened→디스크의 전체 manifest는 r126/schema5로 정확히 같았다. pitch selectedIndex 4·displayedBeats 3·camera를 보존했으며 자산 6개의 실제 SHA도 일치했다. 외부/batch 선택 뒤 삭제 비활성 및 output/audition 0을 확인했다. 종료 프로세스 증거는 `.build/build135-final-processes.txt`이며 PID 86114만 유지됐다. artifact/source 최종 감사도 PASS했다.

artifact/source 독립 감사에서 baseline r108=MCP r112=before-external r116=batch-undone r122=shared-cleared/reopened r126의 음악은 revision·hierarchy를 제외하고 정확히 같았다. r117/r120은 의도한 이벤트 삽입만, r123/r125는 seed 10000과 빈 이벤트를 보존했고 r126은 nil이었다. QA·dist·최종 app-release의 UUID 일치, deep strict 서명, Codex manifest와 server parity도 PASS했다. 이전 integration-release는 구 binary이므로 최종 패키지 근거는 app-release다.
