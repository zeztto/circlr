# 써클러 개발 방향과 실행 계획

갱신: 2026-09-09. 계획 시작 기준: 0.11 native 앱, 0.12 음악 에이전트 키트 소스. 사용 앱은 0.19.0, 개발 검증 후보는 0.20.0 build 61이다. 목표는 송폼 중심의 전문 음악 제작을 먼저 완성하고, 이를 아티스트의 작품·세계관 관리로 확장하는 것이다.

**build 61에서 Sound Bank의 실제 음색 이름·변형 뱅크·드럼 킷을 검색한다.** 한글 계열과 정확한 표시 번호 #1–128을 지원하고, 저장·로더의 program/MSB/LSB 주소를 일치시켰다. 적용 범위·현재 선택·충돌 안내의 높이 압축도 수정했다. Swift 445개·Python 26개, native 16상태/18화면과 최종 패키지는 [계약](75-sound-bank-program-search.md) · [QA](../qa/sound-bank-search-review.md)에 있다. 다음 독립 작업은 (1) 실제 음색 목록을 검색하는 읽기 전용 MCP 계약과 agent 사용법, (2) 편곡안의 긴 메뉴를 이름·현재 위치·키보드 검색으로 바꾸는 UI다. MCP는 실제 설치 catalog의 안정된 주소를 반환하고 음악·재생·선택을 바꾸지 않아야 한다. 편곡안 검색은 동명 항목·현재 선택·취소·외부 변경·저장 복원을 검증한다. 물리 장치 출력·실제 입력은 아래 별도 출고 조건이다.

**build 60에서 음색·Audio Unit 선택을 직접 검색으로 합쳤다.** 내장 신스 10개와 실제 설치 목록을 이름/제조사로 찾으며 같은 음색의 사용자 설정을 보존한다. 서클/전역 AU 검색, 오래된 요청 차단, 명령·키보드 조작과 저장 복원을 검증했다. Swift 437개·Python 26개·native 23상태/20화면의 [계약](74-sound-selection-search.md) · [QA](../qa/sound-selection-review.md). Sound Bank 프로그램 이름·계열과 번호 기준은 build 61에서 개선했다. 편곡안의 긴 메뉴는 후속 대상이다.

**build 59에서 작업 검색을 실제 서클로 연결했다.** 검색된 이펙트의 Return이 MIDI로 가던 흐름을 바꾸고 빈 섹션·종류 필터·명시적 번호·현재 위치 찾기·다중 역할 검색을 제공한다. 검색 전후 음악 이력·그룹 상태·다른 사용을 유지하며 외부 이름 변경에 목록이 갱신된다. Swift 429개·Python 26개·최종 검색 6개, 13섹션·137대상의 native 근거는 [계약](73-direct-work-navigation.md) · [QA](../qa/direct-work-navigation-review.md)에 있다. 음색·Audio Unit은 build 60, Sound Bank 세부 선택은 build 61에서 개선했다. 편곡안의 긴 메뉴는 남아 있다.

**build 58에서 오디오 대상 트랙의 긴 메뉴를 검색 화면으로 바꿨다.** 번호·이름·해당 섹션 사용량으로 동명 트랙을 구별하고 선택 후에도 번호를 유지한다. 요청/파일 변경 거절, 파일 검색·선택·시작 박 보존과 99트랙 실제 import/Undo/Redo·재열기를 검사했다. Swift 423개·Python 26개, [계약](72-library-track-search.md) · [QA](../qa/library-track-search-review.md). 작업 검색의 실제 대상·다중 서클 메뉴·긴 경로·키보드 포커스는 build 59에서 개선했다. 음색/플러그인 등 나머지 선택 메뉴는 후속 대상이다.

**build 57에서 접힌 그룹 내부로 이동하는 단계를 줄였다.** ⌘J/역할 버튼/MCP focus는 선택 경로만 화면에서 펼치며 Undo/Redo·저장된 그룹 상태를 보존한다. Esc와 재열기는 현재 경로의 camera/편집 화면을 복원한다. Swift 419개·Python 26개·최종 경로 검사 6개, 실제 음악/그룹 Undo·MCP·재실행 근거는 [계약](71-navigation-group-reveal.md) · [QA](../qa/navigation-reveal-review.md)에 있다. 오디오 가져오기 대상의 긴 트랙 목록은 build 58에서 검색으로 전환했다. 이동 시 키보드 포커스는 후속 검사 대상이다. 메뉴 전환 직후 연속 키 입력은 도구 입력 타이밍과 사용자 재현을 구분해 확인한다.

**build 56에서 캔버스 보기와 편집 이력을 분리했다.** 궤도/자유 배치·그리드·스냅은 저장되지만 음악 Undo/Redo와 revision을 소비하지 않는다. 음악 및 실제 서클 이동의 Undo는 현재 보기를 유지한다. Swift 413개·Python 26개, 실제 Undo→보기 변경→Redo·키보드 이동·⌘S·재열기 검증은 [계약](70-canvas-view-history.md) · [QA](../qa/view-history-review.md)에 있다. 작업 이동의 자동 펼침과 복귀 포커스는 build 57에서 처리했다.

**build 55에서 음악 위치의 표시 기준을 통일했다.** 가져오기·오디오·MIDI·오토메이션·부모 안 시작이 첫 위치 1박을 사용한다. 길이/초·모델/MCP·원시 정밀도는 보존하며 오류와 접근성 설명도 일치한다. Swift 406개·Python 26개, 실제 입력·편집 방식 왕복·가져오기·Undo·재열기와 소스/앱 검사는 [계약](69-beat-position-display.md) · [QA](../qa/beat-position-review.md)에 있다. 보기 전환의 Undo 혼입은 build 56에서 분리했다.

**build 54에서 가져오기 대상과 시작 위치를 같은 화면에 모았다.** 곡·섹션 검색은 캔버스를 옮기지 않고 이번 사용의 대상을 지정한다. 1 기반 시작 박·마디·초와 기존/새 트랙을 직접 설정하며 MIDI와 다중 오디오에도 전달한다. Swift 401개·Python 26개, native 다른 use의 오디오/MIDI·batch 배치, 숫자 취소/경계/외부 충돌과 한 Undo·저장 복원은 [계약](68-library-import-placement.md) · [QA](../qa/library-placement-review.md)에 있다. 위치 표기 통일은 build 55에서 처리했다. 사라진 선택 트랙의 복구 흐름과 많은 트랙의 검색 접근성은 후속으로 남는다. 원본/이번 사용과 내부 0 기반 저장 의미를 보존한다.

**build 53에서 폴더 관리와 오류 복구의 불편을 줄였다.** 같은 overlay에서 전체 경로·파일 수·읽기 상태를 보고 바로 검색하거나 등록 해제한다. 동명 폴더는 최소 상위 경로로 구분하며 입력 오류와 읽기 경고를 분리했다. Swift 396개·Python 26개, 실제 관리/검색 왕복·혼합 선택 수정·imported 음악을 보존하는 등록 해제·Undo/저장 복원은 [계약](67-library-folder-workspace.md) · [QA](../qa/library-folders-review.md)에 있다. 다음 UI 검증은 긴 경로/밀집 목록·미해결 폴더의 재연결과 기존 직접 drop 흐름을 따른다.

**build 52에서 라이브러리의 반복 가져오기를 줄였다.** 여러 폴더의 오디오를 체크박스·Shift 범위·전체 선택으로 고르고 각 새 트랙에 한 번에 배치한다. 검색/필터의 숨겨진 선택을 해제하며 MIDI 혼합·손상 파일은 전체 거절한다. Swift 391개·Python 26개, 실제 2-folder import·Undo/Redo·저장/재열기·원본과 기존 폴더 보존은 [계약](66-library-batch-import.md) · [QA](../qa/library-batch-review.md)에 기록했다. 동명 폴더와 해소된 오류 표시는 build 53에서 처리했다. 중첩 폴더의 같은 물리 파일 처리와 재연결은 별도 catalog 계약으로 남는다.

**build 51에서 MIDI 파트와 코드 선택의 반복 클릭을 줄였다.** 같은 음높이·시작 박·반전/전체/해제를 세 편집기의 속성 영역과 키보드에 연결했다. 선택은 음악을 바꾸지 않으며 화면 밖 노트도 같은 명령으로 편집한다. Swift 386개·Python 26개, 실제 선택/편집/Undo·숫자 입력 보호·다른 사용 분리·저장 복원은 [계약](65-midi-selection-tools.md) · [QA](../qa/midi-selection-tools-review.md)에 있다.

**build 50에서 MIDI 다중 노트 드래그를 완성했다.** 피아노 롤과 궤도의 본문/끝 손잡이로 선택 전체의 시간·음정·길이를 편집한다. 기존 그루브·간격과 비선택 노트를 유지하며 화면 밖 선택도 공통 경계로 제한한다. Swift 382개·Python 26개, 두 편집기의 실제 조작·한 번 Undo·저장 복원은 [계약](64-midi-group-drag.md) · [QA](../qa/midi-group-drag-review.md)에 기록했다. CC/페달/피치 벤드와 고급 연주 편집은 별도 MIDI 모델·재생 계약이 필요하다.

0.20 녹음 lifecycle은 소스·전용 검증 앱과 오프라인 검사까지 진행했다. 문서 재열기·직접 녹음 버튼·단축키 안내를 확인하고 오디오 이동 메뉴의 대비를 개선했다. 실제 입력과 녹음 중 UI 검증이 남아 사용 앱은 0.19를 유지한다. [0.20 검증 상태](../qa/0.20-review.md)의 남은 acceptance를 유지한다.

포트 A–D의 실제 bus·직접 연결·키보드·가독성·MCP·그룹 노출을 구현한 `1d304eb`와 녹음 `d88ea5d`를 **`codex/daw-integration`의 0.20.0 build 23**으로 통합했다. Swift 226개·Python 26개와 release build, 실제 앱의 편집/Undo/바운스/저장 복원·그룹 신호를 검증했다. [포트 실행 계획](35-port-foundation-plan.md)의 E acceptance는 마이크·VoiceOver·전체 밀집 조합이 남아 있으며 사용자 앱에 출고한 상태는 아니다. [통합 결과](../qa/daw-integration-review.md).

**build 24에서 재생 follow의 작은 자식 서클과 라벨 겹침을 개선했다.** 섹션 진입도 내부 서클에 맞추고, 재생 중 수동 확대가 취소되던 오류를 수정했다. 큰 창 1440×900와 최소 폭 1024(캔버스 높이 673), 콘솔 열림/닫힘 네 조합에서 8개 이름표를 확인했다. Swift 231개·Python 26개 및 native 휠·더블클릭·팔로우 재개·저장 복원 근거는 [재생 화면 QA](../qa/playback-framing-review.md)에 있다.

**build 25에서 출력 연결 telemetry·nonmodal 대기·단일 물리 attempt·취소/재시도를 구현했다.** 실제 지연과 늦은 완료를 관찰했고 편집기 제거 후 Space 소실도 수정했다. [출력/포커스 QA](../qa/output-connection-review.md). 이 계측은 HAL 지연의 원인 해결이나 전체 장치 lifecycle 출고를 대신하지 않는다.

**build 26에서 공통 비동기 오디오 import와 세션 미디어 수명을 구현했다.** 메뉴의 다중 파일·atomic 적용·Undo·MIDI 미리보기·대상 revision 거절을 실제 앱에서 검사했다. file-URL drop 연결과 궤도/자유 배치 기준은 소스에 있으며 Finder 직접 제스처와 Splice promise 수신은 아직 검증되지 않았다. [실행 계약](40-media-import.md) · [검증](../qa/media-import-review.md).

**build 27에서 오디오 소스의 불필요한 서클과 편집 깊이를 줄였다.** 새 오디오 lane은 세 개의 작업 서클로 시작하며 ⌘J/⌘1이 오디오를 연다. 첫 MIDI·리듬 입력 시 악기 경로를 추가하고 같은 편집기의 메뉴로 소스 뒤/출력 앞에 이펙트를 넣는다. Swift 253개·Python 26개, 최소 창의 실제 편집·WAV·개별 Undo·재열기를 확인했다. 기존 서클을 일괄 삭제하는 migration은 하지 않는다. [계약](41-source-aware-circles.md) · [검증](../qa/source-circles-review.md).

**build 28에서 효과의 실제 단위와 한 조작당 한 Undo를 구현했다.** Hz/ms/dB/압축비를 직접 읽고 슬라이더·숫자로 조절한다. Native 검사에서 발견한 방향키의 캔버스 전달과 Tab 연속 확정의 잘못된 충돌 처리를 수정했다. 다음 입력 개선은 신스·출력 볼륨 등 기존 숫자 컨트롤에 확정/취소·대상 보호 계약을 확대하고, 전역·전환 효과와 실제 VoiceOver를 검증하는 것이다. [계약](42-effect-editing.md) · [검증·비활성 창 드래그 제한](../qa/effect-editing-review.md).

**build 29에서 공통 숫자 입력의 확정/취소와 대상 보호를 확대했다.** AppKit에서 Tab 종료를 동기 처리하고 현재 모델 getter를 사용해 빠른 신스·오디오·MIDI 입력이 중간 글자를 잃거나 정상 변경을 충돌로 오인하지 않도록 수정했다. 숫자마다 개별 Undo, 정수/범위 오류, 외부 변경·다른 트랙 보호, 정밀도 보존과 저장/재열기를 확인했다. 전역/전환·legacy/오토메이션 위젯 전체 Native와 VoiceOver, 설정 전체 적용 draft의 수명은 후속 검증이다. [계획](43-number-editing.md) · [근거](../qa/number-editing-review.md).

**build 30에서 주 캔버스의 음악 설정 전체 적용 draft를 제거했다.** 현재 유효값과 출처를 함께 보여주며 항목별 즉시 확정·Undo, 보관된 개별값 복원, 엄격한 강세 입력을 지원한다. 공유 원본은 원본 settings만 부분 수정한다. Swift 272개·Python 26개, 실제 설정·리듬·충돌·저장 복원과 최종 패키지를 검증했다. legacy 전체 draft와 공유 원본/곡/악장의 Native 전체 조합은 남아 있다. [계약](44-direct-music-context.md) · [QA](../qa/context-editing-review.md).

**build 31에서 다운로드한 샘플의 로컬 검색→가져오기를 연결했다.** 여러 폴더의 read-only bookmark, 파일명/하위 경로/형식 검색, MIDI 선택 화면, 오디오 미리 듣기·취소와 대상 revision 보호를 구현했다. 작은 창의 상단과 검색 접근성도 정리했다. 실제 폴더 등록/재실행/제거·오디오/MIDI import·Undo/Redo·저장 복원을 확인했다. HAL의 장치 시작 지연을 재현했고 player 호출을 모두 백그라운드로 이동했다. [계약](45-local-media-library.md) · [QA 및 출력 제한](../qa/library-review.md).

**build 32에서 재생 시작·정지·시간 조회·해제를 직렬 background worker로 분리했다.** 실제 숫자 Return 뒤 Space 소실도 수정하고 293개 Swift·26개 Python과 별도 앱의 대기 중 편집/취소를 확인했다. Scarlett 속성 조회는 약 45 ms였으나 음악 없는 AVAudioEngine도 HAL IOProc 생성에서 7분 이상 대기했다. 특정 드라이버의 원인은 확정하지 않는다. [계약](46-playback-worker.md) · [QA](../qa/playback-worker-review.md).

**build 33에서 출력 서클의 편집 범위와 깊이를 정리했다.** 서클/트랙 전체 레벨을 dB로 조절하고 오토메이션·바운스로 바로 이동한다. 공유 원본은 부분 편집하며 native fader와 숫자 충돌 보호를 검사했다. Swift 303개·Python 26개, 두 사용의 PCM·실제 조절/Undo/저장 근거는 [계약](47-output-editing.md)과 [QA](../qa/output-editing-review.md)에 있다. 다음 레벨 확장은 track pan/solo의 신호·bus·bounce 의미를 먼저 정한 뒤 같은 편집기에 추가한다.

**build 34에서 오토메이션 곡선과 선택 점을 같은 화면에 배치했다.** dB/%·마디·박/초 표시, 원본 전환, 전체 점 보기, Return/Esc 후 곡선 포커스, 숫자/드래그의 외부 변경 보호를 추가했다. Swift 307개·Python 26개와 최종 앱의 작은 창·궤도/자유 조작·Undo·저장 복원을 확인했다. [계약](48-automation-workspace.md) · [QA](../qa/automation-workspace-review.md). 다음에는 마지막 점 편집 중 전체 범위의 고정 여부와 궤도/자유 전환 시 편집 확대 유지, 겹친 끝점 선택을 함께 다룬다. gain/pan 이외 파라미터와 실시간 write/touch/latch는 별도 신호 계약이 필요하다.

**build 35에서 배치 전환 시 편집 확대와 곡선 범위를 유지했다.** 메뉴/명령/Undo에서 MIDI·스텝·오디오·오토메이션의 편집기 위치·크기를 확인했다. 오토메이션은 범위 고정/재맞춤, 겹친 점의 선택 유지/순환을 지원한다. Swift 311개·Python 26개, 실제 끝점 드래그·저장 복원과 패키지 근거는 [계약](49-canvas-editing-continuity.md)과 [QA](../qa/editing-continuity-review.md)에 있다. Option 클릭 native 입력은 도구 제약으로 미검증이다.

**build 36에서 작은 창의 MIDI 궤도와 선택 노트 속성을 정리했다.** 표시 음역·마디·노트 탐색, 길게 이어지는 노트의 현재 페이지 편집, 숫자 확정 후 keyboard focus, 궤도/스텝/자유 배치 범위 유지를 구현했다. Swift 318개·Python 26개와 최종 앱의 실제 조작·충돌 거절·복원은 [계약](50-midi-orbit-workspace.md)과 [QA](../qa/midi-orbit-workspace-review.md)에 있다.

**build 37에서 스텝·피아노 롤의 작업 공간과 고정 눈금을 정리했다.** 공통 선택 속성, MIDI 속성의 Tab/Shift-Tab 순서, 스텝 onset/커서 일치, 드럼 행·분할·페이지 유지, 피아노 롤 음역/스크롤 따라가기를 실제 확인했다. 최종 작은 창의 선택 상태에서 스텝 약 6행·피아노 롤 약 9행과 각 눈금이 보인다. Swift 319개·Python 26개, 실제 입력·드래그·충돌 거절·복원은 [계약](51-midi-grid-workspace.md)과 [QA](../qa/midi-grid-workspace-review.md)에 있다.

**build 38에서 오디오 속성과 원본 시간 탐색을 한 화면에 배치했다.** dB/ms와 원본 시작/끝, 고정된 전체/선택 범위, 연속 Tab 입력을 구현했다. 같은 clip을 참조하는 여러 서클의 직접 편집은 선택한 서클만 변경한다. Swift 325개·Python 26개, 실제 trim·분할·복제·34초 바운스/복원·저장/재열기를 검증했다. [계약](52-audio-workspace.md) · [QA](../qa/audio-workspace-review.md).

**build 39에서 선택 전후 편집 위치와 작업 전환을 정리했다.** 제목·경로·본문·안내를 분리하고 MIDI/오디오·연결·오토메이션·설정으로 직접 전환한다. 긴 속성은 본문 안에서 스크롤하며 녹음 테이크는 상단에 배치한다. Swift 325개·Python 26개, 실제 작은 창의 선택·입력·궤도/스텝·그룹 왕복·콘솔 접기·저장 복원을 검증했다. [계약](53-editor-workspace-shell.md) · [QA](../qa/editor-shell-review.md).

**build 40에서 전환 시간과 효과 편집을 같은 화면에 정리했다.** 앞/뒤 섹션 마디의 실제 초와 다음 시작 변화를 컴파일러와 같은 계산으로 표시하며, 전역·음악·전환 효과의 dB/ms/% 입력·Tab/Shift-Tab·충돌 보호를 통합했다. 실제 적용되지 않는 전환 효과를 숨겼다. Swift 330개·Python 26개, 최종 작은 창의 입력/왕복·73초 오프라인 WAV·Undo/저장 복원과 패키지를 검증했다. [계약](54-transition-effect-workspace.md) · [QA](../qa/transition-effects-review.md).

**build 41에서 연결 대상을 직접 탐색하는 작업 공간을 구현했다.** 검색 결과의 이름/포트를 두 줄로 표시하고 ↑↓·Tab·Return으로 연결한다. 고정 조작과 결과/케이블 스크롤을 분리하며 전체/현재 논리 포트를 필터링한다. Native 검사에서 표시 누락을 발견해 조작을 목록 위에 모았다. Swift 330개·Python 26개, 실제 IN/OUT·8방향·재연결·그룹 필터·작은/확장 영역·Undo/저장 복원을 확인했다. [계약](55-connection-workspace.md) · [QA](../qa/connection-workspace-review.md).

**build 42에서 MIDI 가져오기 위치를 공통화했다.** 메뉴·라이브러리·궤도 drop의 박/배치를 전달하고 선행 쉼표와 노트 간격을 보존한다. 시작·끝 위치와 길이 초과 안내를 목록 위에 두며 새 MIDI의 편집/전체 보기로 연결한다. [계약](56-midi-import-placement.md) · [QA](../qa/midi-placement-review.md). Finder의 실제 교차 창 gesture와 Splice file promise는 별도 미검증으로 유지한다.

**build 43에서 미리 듣기 worker와 취소 수명을 구현했다.** sampler 렌더·악기 note/stop을 MainActor 밖으로 옮기고 현재 held note·재누르기·target 교체를 관리한다. 기존 transport 줄의 상태·Space 취소·MCP snapshot을 연결했다. Swift 345개·Python 26개, 실제 HAL 대기 중 편집·취소·복원과 Main/worker stack을 검증했다. 정상 재생·장치 응답 문제는 해결로 간주하지 않는다. [계약](57-audition-worker.md) · [QA](../qa/audition-worker-review.md).

**build 44에서 선택 이름의 여러 줄 표시와 가장자리 배치를 개선했다.** 실제 밀집 선택 누락을 발견해 둘레의 빈 후보를 추가했다. 화면 밖 중심의 AX·이름표 클릭, 연결 도구/그룹 IN·궤도 시간 손잡이와 Undo/저장 복원을 검사했다. Swift 353개·Python 26개, [계약](58-canvas-readable-selection.md) · [QA](../qa/canvas-label-review.md).

**build 45에서 이름의 확정·취소·한 Undo와 UI 저장을 연결했다.** 실제 ⌘S 실패를 수정하고 외부 변경·대상 전환·빈 이름·Unicode 저장/재열기·그룹 복원을 검사했다. Swift 363개·Python 26개, [계약](59-name-editing.md) · [QA](../qa/name-editing-review.md). 실제 IME 후보 선택과 legacy 전체·녹음 중 입력 검증은 남아 있다.

**build 46에서 MIDI 전체 음역의 직접 탐색과 중앙 음명을 구현했다.** 클릭/드래그·키보드·접근성은 음역만 이동하며 작은 창의 편집 방식과 노트/MIDI 조작을 고정했다. Swift 366개·Python 26개, 실제 음역·노트 편집/Undo·대상 분리·원본 복원은 [계약](60-midi-pitch-navigation.md) · [QA](../qa/pitch-navigation-review.md)에 기록했다. Hover-only/VoiceOver와 grid/step 드럼의 전체 탐색은 별도 후속이다.

**build 47에서 드럼 스텝의 행 탐색을 구현했다.** 행/샘플 이름·MIDI 번호 검색, 표시 수·빈 결과·선택 행 복귀, 현재 열을 유지한 행 추가, Home/End·PageUp/PageDown 이동과 보이는 행의 그리기/AX를 지원한다. Swift 369개·Python 26개, 101행의 실제 검색·입력/Undo·대상 분리·복원은 [계약](61-step-row-navigation.md) · [QA](../qa/step-row-navigation-review.md)에 기록했다. VoiceOver 발화와 보관된 오래된 AX 객체 호출은 별도다.

**build 48에서 오토메이션의 길이 밖 마디 눈금과 점 탐색을 구현했다.** 부분 마디·변박을 유지한 희소 눈금, 이전/다음·Home/End의 범위 확장, 점 번호·마디/박/초와 선택 점 보기를 연결했다. 깨끗한 빌드의 Swift 374개·Python 26개, 두 배치의 실제 편집/Undo·범위·대상 분리·원본 복원은 [계약](62-automation-time-navigation.md) · [QA](../qa/automation-time-navigation-review.md)에 기록했다. 최초 증분 테스트 충돌 뒤 동일 소스의 전체 재빌드는 통과했으며, 후속 offline 검사는 `.build/automation-time-quality` scratch를 사용한다.

다음 UI 우선순위는 **남은 작업 이동 깊이와 입력 검증**이다. 궤도 배치·펼친 그룹에서 이름표/포트 hit를 먼저 확인하고 import→trim/split/fade→오토메이션→bounce 흐름의 남은 단계를 줄인다. 전역 편집↔연결의 복귀 포커스와 legacy/실제 Audio Unit 경로는 별도 대표 검사로 이어간다. 녹음 테이크가 있는 헤더와 실제 Audio Unit 편집기의 설정 전환은 별도 native 검사 대상으로 유지한다. 원본 음악과 입력 정밀도를 보존하며 실제 창에서 데이터·포커스·Undo를 함께 확인한다.

**build 49에서 오디오 파형의 휠 확대와 원본 시간 이동을 구현했다.** −/+·Page Up/Down·Home/End·0/F/C와 숨겨진 분할 커서 찾기를 지원하며, 편집/Undo·배치 전환 중 표시 범위를 유지한다. 작은 창의 파형 높이를 확보하고 숫자 작성 중 휠의 포커스 보호를 확인했다. Swift 377개·Python 26개, 최종 앱의 실제 편집·탐색·대상/원본 전환·음악/배치 복원은 [계약](63-audio-source-navigation.md) · [QA](../qa/audio-source-navigation-review.md)에 기록했다.

현재 전달 조건은 기능별로 구분한다. UI·편집 개선은 build 60 QA 앱에서 직접 검토할 수 있다. 사용 중인 0.19 앱을 교체하려면 우선 같은 Mac에서 출력 연결→실제 재생/정지→재시작과 기존 곡/MP4 회귀를 끝내야 한다. 녹음은 별도 허용이 필요한 실제 입력·취소·테이크 저장 회귀가 남았다. VoiceOver와 밀집 연결 조작은 전역의 모든 조합이라는 무한 조건 대신 MIDI/audio/sidechain/flow, 접힌 그룹, 긴 이름, 작은 창의 대표 경로를 명시한 검사표로 좁혀 수행한다. 과거 QA 수치를 새 빌드의 전체 기능 승인으로 합산하지 않는다.

다음 실행 순서는 다음과 같다. (1) 궤도 배치·다수 섹션 전환·펼친 그룹·긴 이름·시간 손잡이·VoiceOver 조합을 점검한다. 이름표/포트 hit와 그려진 위치가 일치하고 키보드로 편집/복귀가 가능해야 한다. (2) file-URL drop의 실제 제스처·orbit 위치·overlay 거절을 먼저 검증하고 file promise와 로컬 라이브러리를 연결해 import→섹션 배치→편집→바운스→저장 복원의 작업 깊이를 줄인다. 원본 참조·중복 자산·Undo 계약을 먼저 정한다. (3) 새 출력 telemetry로 장치별 cold/warm 연결 시간을 수집해 HAL 대기와 engine 시작/정지의 원인을 분리하고, 연속 render graph/PDC 전에 장치 변경·복구 수명을 확정한다. 마이크 입력의 별도 실행 조건과 E 출고 gate는 유지한다.

0.14에서 10음색 engine 3와 15트랙의 f0r h3r v4를 추가했고, 0.15에서 B의 탐색 깊이·라벨 가독성·작은 창 편집을 개선했다. 배포용 v4는 FreePats CC0 bank를 사용한다. 기존 버전·원본 곡은 보존한다. [음질·음악 검증](../qa/0.14-review.md)과 [UI 검증](../qa/0.15-review.md)을 분리한다.

추가된 기본 DAW 요청에 따라 0.16 스텝, 0.17 MIDI 일괄 편집·노트 import와 권한 대기 guard, 0.18 오디오 split/duplicate/fade, 0.19 gain/pan automation을 구현했다. 다음 실행 순서는 장치 lifecycle → E의 endpoint 데이터·표시·hit·Undo/MCP → 공통 drop/로컬 라이브러리 → 실제 MP4 재검증과 F/G/H다. 상세 완료 조건은 [기본 DAW 확장 계획](31-daw-basics-plan.md)을 따른다. Scarlett 출력 연결과 실제 재생 녹화 검증은 남아 있으며, UI 완료가 이를 대신하지 않는다. [Splice 연동 계획](27-splice-licensing-and-integration.md)은 공통 파일 import → 로컬 라이브러리 → companion AU 순서다.

| 단계 | 현재 상태 | 다음 확인할 결과 |
|---|---|---|
| A | private 소스 이력, 로컬 패키징 구현 | CI·서명 배포는 별도 범위 |
| B | 생성/⌘J/트랙 전환/8방향 연결·follow/라벨·소스별 서클·직접 이펙트·단위/확정 입력·직접 음악 설정·출력 dB/범위·오토메이션/세 MIDI 작업 공간·고정 눈금·오디오 source 범위/dB/ms·배치 전환 편집 유지·전환 시간/단위/포커스·직접 연결 검색/논리 포트 필터·이름 확정·MIDI 전체 음역/드럼 행·오토메이션 시간 탐색·오디오 원본 휠/키보드 탐색 | 전역 왕복/legacy·밀집 조합·VoiceOver |
| C | 캡처·코덱 경로 구현 | Scarlett 실제 출력·MP4 동기/최소화 |
| D | engine 3·v4 MIDI/CC0/WAV·native bounce | 아티스트 청취 피드백 |
| E | stable ports·8방향·독립 bus·MCP·그룹 및 녹음 branch 통합 | 전체 신호/밀집 조합·native 입력·사용 앱 출고 |
| Import | CC0 대체·MIDI 노트·비동기 오디오 배치·소스별 생성/탐색·세션 미디어 참조·file-URL drop 코드·로컬 샘플 검색 | Finder/Splice promise 실제 드롭, 로컬 폴더 자동 감시·대규모 검색 검증, CC/tempo map, 중복 자산·GC |
| F | prepared PCM 기반 | 장치 lifecycle 후 연속 render graph/PDC |
| G | 공식 계정 콘솔 설계·전문 kit/MCP 구현 | App Server adapter·권한/취소·대화 UI |
| H | 아티스트 세계관 설계 | catalog/schema·파일 참조·복원 |

## 제품 원칙

1. 하나의 다크 캔버스에서 작업한다. 원은 시간·반복을 가진 궤도이며 관계 그래프의 장식이 아니다.
2. 앨범 → 곡·악장 → 섹션 → MIDI·오디오·악기·이펙터를 같은 탐색 모델로 다룬다.
3. 마우스·키보드·AI는 같은 편집 명령, 검증, Undo 및 프로젝트 데이터를 사용한다.
4. 실제 동작과 음악 품질을 검증한 기능만 UI에 표시한다. 미완성 버튼이나 가짜 에이전트 진행을 넣지 않는다.
5. 제작 중 원본과 수정본을 구분한다. 사용자 곡, 샘플 출처, 편곡 대안과 복구 가능성을 보존한다.

## 현재 문제와 우선순위

| 우선순위 | 문제 | 완료 결과 |
|---|---|---|
| P0 | 원격 이력 없음 | 비공개 GitHub 저장소, 검증한 단계별 커밋·push |
| P0 | 원형 UI의 생성·선택·조작이 발견하기 어려움 | 빈 공간 우클릭 생성, 명령 검색, 키보드 탐색·편집 |
| P0 | 내장 음색과 f0r h3r의 완성도 부족 | DSP 개선, 새로운 실제 편곡·믹스·프로젝트·MIDI·WAV |
| P1 | 재생 비주얼을 영상으로 사용할 수 없음 | 앱 캔버스 영상과 실제 재생 오디오를 함께 저장 |
| P1 | 음악 AI 역할 분담 기반 필요 | 설치된 전문 역할, 안정적인 단일 writer, 실제 도구·작업 로그 |
| P1 | 좌우 포트에 제한됨 | 8방향 IN/OUT, 다중 입출력, 연결 의미와 배치 분리 |
| P2 | prepared PCM 엔진의 한계 | 연속 실시간 엔진, PDC, 녹음·플러그인 안정성 |
| P2 | 앱 내 Codex 계정 대화 미구현 | 공식 App Server 세션·로그인·취소·권한 UI |
| P3 | 아티스트 자산이 곡 파일로 분산 | 아티스트 프로필, 작품·세계관·통합 미디어 catalog |

## 이번 실행 A — 이력과 릴리스 기반

- 현재 소스·문서·테스트·브랜드 리소스를 먼저 커밋한다. 사용자 승인된 계정의 private 저장소를 생성하고 privacy와 원격 HEAD를 검증한다.
- licensed 샘플이 들어간 .circlr/WAV, build 앱, 임시 QA 산출물, 계정·로컬 절대 경로 설정을 Git에서 제외한다. 직접 작성한 MIDI와 제작 코드는 보관한다.
- 단계마다 README의 실제 버전/사용법과 CHANGELOG를 유지한다. 새 버전은 소스·bundle Info·agent kit manifest가 일치해야 한다.
- macOS CI는 순수 Core/형식 검사를 우선하고 Audio Unit/native GUI 검증을 별도 단계로 명시한다. 서명·notarization 배포는 개발자 계정과 배포 정책을 정한 뒤 구성한다.
- 완료 기준: private=true, 원격 commit SHA 일치, 비밀정보 패턴 검사, 로컬 기존 앱 보관.

## 이번 실행 B — 캔버스 조작과 키보드

### 생성

- 빈 공간 우클릭으로 생성 메뉴를 연다. 현재 계층에 맞춰 곡·악장·섹션·MIDI·오디오·이펙터를 제공한다.
- 클릭 지점과 포함 owner를 분리한다. 자유 배치에서는 클릭 좌표를 owner의 로컬 좌표로 변환해 저장한다. 궤도 모드에서는 시간 의미를 유지하며 공간 좌표가 재생 순서를 임의로 바꾸지 않는다.
- 생성 가능하지 않은 계층에서는 적절한 상위 컨테이너를 선택하거나 의미 있는 안내를 제공한다. 섹션 밖에 소유자 없는 MIDI를 만들지 않는다.
- 추가는 한 Undo 작업으로 처리하고 새 서클을 선택한다. 음악 context는 부모 상속을 유지한다.

### 명령과 포커스

- 명령 검색은 단일 캔버스 위의 짧은 overlay로 제공한다. 검색어, 결과 이동, Return 실행, Escape 닫기를 지원한다.
- 선택·확대/부모·형제·다중 선택, 생성·삭제·재사용·그룹·연결·설정, 재생·녹음·저장·내보내기를 키보드에서 접근 가능하게 한다.
- 기존 ⌘N/O/S/Z/⇧Z/I/E/W와 닫기=최소화, ⌘Q=종료 계약을 유지한다. 텍스트 입력 중 Space/Backspace/문자 핫키가 음악 명령으로 실행되면 안 된다.
- MIDI 노트는 키보드 선택, 입력, 시간/음정 이동, 길이 변경 및 삭제를 지원한다. 오디오 trim과 파라미터는 키보드로 접근 가능한 수치 입력을 갖춘다.
- 키맵은 도움말에서 확인한다. 모든 동작에 개별 핫키가 필요하지는 않지만 명령 검색/메뉴/Tab을 통한 마우스 없는 접근은 필요하다.
- Native QA: 빈 캔버스 우클릭 생성, 계층별 생성 owner, 메뉴 취소, 검색 0건, 한국어 입력, 텍스트 입력 충돌, keyboard-only 섹션→MIDI→연결→저장 흐름. 1440×900과 축소 창에서 확인.

파일 책임: AppStore/AlbumWorkspace/AlbumCanvas, 새 command UI, CirclrApp 메뉴, Orbit MIDI/Audio editor. Core에는 좌표·선택·편집 의미의 검증 가능한 공통 동작만 둔다.

## 이번 실행 C — 재생 화면 영상 녹화

- 첫 범위는 써클러 자신의 캔버스와 실제 재생 음악이다. 다른 앱·알림·마이크를 함께 녹화하지 않는다.
- 녹화 시작 전에 파일 경로를 선택하고 렌더를 준비한다. 화면 크기가 바뀌어도 영상 해상도를 고정하고 비율을 보존한다.
- 영상 timestamp를 재생 시간과 연결한다. 임의 wall-clock 증가만으로 오디오와 영상을 맞추지 않는다. 실제 준비된 PCM을 같은 구간으로 기록한다.
- 시작/녹화 중/종료 저장/실패 상태와 정지 명령을 제공한다. 자동 재생 종료, 사용자의 중간 정지, 음악 revision 변경, 최소화·화면 가림, 저장 실패를 정의한다.
- 작업 중 파일은 임시 경로에 작성하고 완료 후 확정한다. 기존 영상은 허락 없이 덮어쓰지 않는다. 오류 시 partial 파일을 최종 결과처럼 노출하지 않는다.
- AVFoundation 기반 H.264 영상·AAC 오디오 MP4를 우선 검증한다. 지원하지 않는 포맷/해상도 옵션은 표시하지 않는다.
- Native QA: 실제 움직이는 서클, 정상 오디오 track, 시작/끝 동기, 중간 정지, 프레임 누락 시 timestamp 유지, 최소화/복원, 취소·디스크 오류. 생성한 MP4의 tracks/duration/frame rate를 검사하고 표본 프레임을 확인한다.

파일 책임: 독립 recording/export 서비스, AppStore 녹화 상태, AlbumCanvas capture, toolbar/menu. 오디오 엔진과 파일 포맷을 공유하되 녹화 파일 I/O를 실시간 오디오 callback에 넣지 않는다.

## 이번 실행 D — 악기 DSP와 실제 곡 재제작

### 문제 진단

- 현재 synth는 여섯 스타일에 유사한 oscillator/2단 low-pass를 사용한다. 다중 voice의 위상·폭·velocity 반응과 envelope·필터를 검사한다.
- pitch 정확도, alias 성분, DC, note-off/stealing click, voice 누적, 높은 음역의 FM·하모닉과 stereo 저역을 측정한다.
- 믹스에서 코드/패드/키/lead가 차지하는 register와 시간, 킥·베이스 충돌, 과한 잔향과 반복 패턴을 구분한다. 단순 gain 증가로 해결하지 않는다.

### 구현과 음색

- 공유 DSP를 개선해 live preview와 offline bounce가 같은 음색을 사용하도록 한다. 기존 patch 저장 호환성을 유지한다.
- 오실레이터별 역할, 저역 중심 안정성, pad/saw 폭, keys의 타건 반응, pluck의 스펙트럼 변화, lead의 중심 음정을 분리한다.
- 범위가 명확한 표현 파라미터만 노출한다. 미구현 modulation/automation 기능을 약속하지 않는다.
- 수치 시험과 비교 WAV를 남기고 CPU 비용을 실제 조건에서 검사한다. 64 voices·event overflow·블록 크기 변경·짧은 노트·긴 release를 검증한다.

### f0r h3r

- 방향: 북유럽 신스웨이브의 서늘한 공간감 + 일본 city pop의 화성과 리듬 + future bass 후렴의 대비. 곡명과 아티스트 의도는 유지한다.
- v1은 보존하고 v2 새 경로에 제작한다. 하나의 주 모티프와 호흡 있는 문장을 중심으로 인트로·절·빌드·후렴·브리지·최종 후렴·아웃트로를 설계한다.
- 베이스와 드럼의 pocket, 코드 보이싱의 voice leading, 후렴 register/폭/밀도 대비, 전환과 tail을 실제 MIDI·graph에 반영한다.
- 보유 Splice 소재부터 사용한다. 기존 승인 한도는 10 credits이며 추가 구매가 필요하면 지출과 출처를 기록한다. 다른 서비스 유료 결제는 자동으로 확장하지 않는다.
- 정적 balance → source/arrangement 조정 → 필요한 dynamics/공간 처리 → level-matched 비교 순으로 진행한다. 무조건적인 LUFS 목표 대신 목적에 맞는 dynamics를 보존하고 측정 방법을 표시한다.
- 산출물: 편집 가능한 .circlr, 전체 MIDI, stereo WAV, 가능하면 stems, 제작/출처 기록, 측정·검토 기록. 앱 재생 및 bounce/export에서 동일한 내용을 확인한다.
- 완료 기준: 기술적 오류·clipping·불필요한 silence·누락·tail 잘림 없음, 원본 보존, 실제 산출물 검증. 청취를 하지 못한 검사를 수행했다고 표현하지 않으며 발매 미학의 최종 판단은 아티스트가 한다.

파일 책임: CirclrRealtime/synth.c, CirclrCore/ProductionModel, CirclrAudio/ProductionInstrument 및 필요한 DSP, 제작 CLI, music/f0r-h3r/v2, 음질/호환성 테스트.

## 다음 개발 E — 8방향 포트와 편집 명령 통합

[8방향 계약](22-eight-direction-ports.md)을 구현한다. port ID와 cable endpoint 위치를 분리하고 종류별 입력/출력을 표시한다. Fan-in/out, sidechain, reroute, 다중 케이블 선택을 지원한다. 키보드 연결 선택과 MCP가 동일한 type/cycle 검사를 통과하도록 한다. 기존 그래프 migration·재생 동등성을 우선 검증한다.

현재 독립 branch에서 포트 Core·독립 2 IN/2 OUT bus·직접 연결 UI·케이블/포트 키보드·출력별 envelope·MCP와 그룹 alias까지 구현 체크포인트를 만들었다. [실행 기록](35-port-foundation-plan.md)과 [그룹 QA](../qa/ports-group-review.md)를 기준으로 남은 순서는 다음과 같다.

1. 그룹 경계의 실제 재생을 출력 장치가 정상 연결되는 상태에서 재검증한다. 현재 QA 앱의 10초 장치 연결 timeout을 기록했으며 장치 설정은 바꾸지 않았다.
2. MIDI/sidechain/flow·고밀도 그룹·최소 너비·실제 VoiceOver와 drag 중 외부 변경의 남은 조합을 검증한다.
3. recording-lifecycle 0.20 변경을 별도 통합 작업 디렉터리에서 보존·병합하고 전체 저장 호환성·Undo·녹음 수명 주기·기존 곡 렌더 회귀를 확인한다. 마이크 실제 캡처는 기존에 미승인된 범위로 남는다.
4. 통합 결과에 맞춰 version/README/CHANGELOG/kit·서명·UUID를 갱신하고 검증된 앱을 출고한다. 독립 개발 source push는 출고와 구분한다.

## 다음 개발 F — 연속 실시간 오디오와 녹음

미리 듣기의 별도 worker·held note 수명은 build 43에서 준비했다. 장치 연결이 정상인 환경에서 sampler/synth/AU의 실제 note-on/off·voice steal·MIDI timestamp를 확인한 뒤 공통 render graph로 통합한다. 현재 backend 분리는 연속 엔진이나 PDC의 완성이 아니다.

- immutable render graph를 오디오 callback 경계에서 교체하고 allocation/lock/file I/O를 callback 밖으로 분리한다.
- tempo map, live MIDI timestamp, pre-roll/count-in, punch/loop recording과 take 관리의 공통 clock을 설계한다.
- plug-in latency 신고/측정·PDC, latency 변화, bypass, suspend, sample rate 변경, 외부 장치 hot-plug를 검증한다.
- crash 격리 및 복구, offline render와 실시간 render 차이를 명시한다. 복잡한 plug-in의 안정성을 소스 검사만으로 선언하지 않는다.

## 다음 개발 G — 앱 내 Codex

[계정 콘솔 계획](20-codex-account-console-plan.md)과 [음악 제작팀](24-music-agent-kit.md)을 연결한다. 공식 App Server를 사용하고 별도 비공식 OAuth나 auth.json 복제를 하지 않는다. 전용 storage/runtime, 모델 목록, 로그인/로그아웃, 대화 복원, 실제 역할 로그를 구현한다.

RunLease는 projectID·revision·turn generation·권한을 묶는다. 사용자의 STOP/프로젝트 전환 뒤 늦은 결과를 적용하지 않는다. 전문 에이전트가 제안한 여러 변경은 single writer가 통합하고 승인 정책은 실제 변경 단위와 연결한다. 사용자 계정/모델/비용 정책을 UI에서 확인 가능하게 한다.

## 이후 H — 아티스트의 창작 세계

[아티스트 세계관 설계](21-artist-universe.md)를 기반으로 프로필·작품·에셋·버전·권리/출처·발매 묶음을 도입한다. 음악 시간 궤도와 텍스트/이미지의 관계 궤도를 혼동하지 않는다. 파일은 stable ID·hash·참조 무결성으로 관리하고 외부 파일 이동/삭제 및 백업·복원 흐름을 검증한다.

## 실행 방식과 진행 기록

단일 agent 슬롯에서 UX → 구현 → 코드/보안 검토 → QA를 순차 수행한다. 서로 다른 파일 책임을 명시하고 사용자 변경을 덮어쓰지 않는다. 0.13의 B/C/D 이후 0.14 음악·엔진과 0.15 탐색 UI까지 진행했다. 후속 범위는 위 표와 각 버전 QA에 유지하며, 이번 milestone만으로 전체 개발 목표를 완료 처리하지 않는다. 날짜 약속 대신 검증 완료 조건으로 다음 단계를 시작한다.
