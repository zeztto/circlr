# 써클러(circlr)

macOS용 앨범·송폼 궤도 편집기. **앨범 → 곡·악장 → 섹션 → MIDI·오디오·악기·이펙터**를 하나의 자유로운 캔버스에서 다룬다.

최종 목표는 **아티스트 프로필을 선택하고 작품·세계관·자료·창작 이력을 함께 관리하는 도구**다. 음악 제작 기능을 바탕으로 텍스트·이미지·영상까지 연결하는 [아티스트 창작 세계 설계](docs/21-artist-universe.md)를 정리했다. 프로필과 통합 생성물 관리는 향후 범위다.

연결 UI는 [서클 둘레 8방향 IN/OUT과 다중 입출력](docs/22-eight-direction-ports.md)으로 확장 중이다. 포트의 신호 의미와 연결점 배치를 분리한다. 아래 일반 사용법은 배포된 0.19 앱 기준이며 새 포트 기능은 독립 개발 브랜치에서 검증한다.

현재 **`codex/daw-integration`의 0.20.0 build 109**에 녹음 lifecycle과 8방향·다중 bus·그룹 포트를 통합했다. 같은 캔버스의 연결 편집·녹음 상태·스텝·오토메이션이 공존하며, 녹음 시작·정리 중 음악 편집과 Undo의 경쟁을 차단한다. build 23의 실제 편집·바운스·Undo·저장/재열기·닫기 최소화 및 출력별 모션 검증은 [통합 QA](qa/daw-integration-review.md)에 기록했다.

**build109는 앱별 출력 선택과 공유 리듬 표시를 추가했다.** 최종 Release40.31초·mock/fixture38개16.992초·UI-only mock 출력9개/리듬6개 상태 checker와 시각/source 검토를 통과했다. 출력 설정의 키보드 선택·Esc·누락 유지·실패 재시도·조회 취소, 공유 패턴 변경/Undo·strict 재열기를 확인했다. 네 helper를 필수 패키징하며 명시 장치를 자동 대체하지 않고 마지막 확인 장치를 별도로 표시한다. 조회5초는 deadline이며 종료 회수는 플랫폼 동작에 의존한다. 실제 readback/hotplug/물리 재생과 HAL stall 해결은 미검증이며 사용자 앱 PID86114를 보존했다. [구현·검증](docs/125-output-device-implementation.md).

**build108은 테이크를 canvas 검색과 키보드로 선택한다.** 최종 Release39.82초와 실제 ⌥⌘T·Down/Return·검색0·Esc·Undo·명령 진입·stale 거절을 확인했다. 검색 중 목록 높이는 유지되며 시각/source 검토를 통과했다. checker9개 상태·검색 AX·테이크5개·자산2개·output0·r30 strict 복원/재열기/disk 대조도 통과했다. 물리 I/O 없이 사용자 앱을 보존했다. [계약](docs/124-take-search.md).

**build107은 테이크 내용 요약과 offline AU instrument 격리를 추가했다.** 최종 Release40.16초·관련 테스트27개와 패키지 악기4개 PCM 비교를 통과했다. 실제 테이크 선택/재선택·Undo·r22 strict 재열기를 확인했으며 UI checker8개 상태·자산2개·테이크5개·strict r22 재열기도 통과했다. 내용 일치는 active 체크가 아니며 키보드 메뉴 선택·실제 물리 출력은 미검증이다. CLI 개발 시 악기 helper도 함께 빌드해야 한다. [테이크](docs/122-take-summary.md) · [악기](docs/123-au-instrument-worker.md).

**build106은 바운스 경로와 여운 안내를 각각 표시한다.** Release38.64초와 실제 두 경고·여운 설정/취소·자동 추정 복귀를 확인했다. QA6개 상태·음악r22/자산2개·strict 재열기·시각 검토를 통과했다. 실제 바운스·물리 I/O·경로 복구 실행은 이번에 검증하지 않았다. [계약](docs/121-bounce-notice-visibility.md).

**build105는 작은 오토메이션 편집기의 곡선 공간과 수치 이동을 개선했다.** Release38.43초와 실제 약160px plot·초안 왕복·위치/gain/pan 입력·Undo·수치 버튼을 확인했다. QA10개 상태·자산2개·strict r28 재열기와 시각 검토를 통과했다. 동시 drag/resize·IME·대량 점 등은 미검증이다. [계약](docs/120-automation-compact-layout.md).

**build104는 연결 편집기의 폭 전환에서 입력 focus와 선택 행을 유지한다.** 최종 Release40.00초와 실제 target/search/filter 왕복·caret 삽입·목록 이동·키보드 재연결/취소를 확인했다. QA11개 상태·음악r36/자산2개·strict 재열기와 시각 검토를 통과했다. 케이블 적용·IME 조합 등은 미검증이다. [계약](docs/119-connection-focus-continuity.md).

**build103은 작은 오디오 편집기의 파형과 수치 입력을 분리해 배치한다.** Release39.90초와 실제 초안/줌 왕복·invalid focus·trim/Undo·첫/마지막 입력 접근을 확인했다. QA4개 상태·자산2개·physical0과 r38 strict 재열기를 통과했다. 전체8필드 연속 Tab·본문180 미만·녹음 busy는 미검증이다. [계약](docs/118-audio-compact-layout.md).

**build102는 좁은 연결 편집기의 목록·입력으로 바로 이동한다.** 최종 Release38.32초와 실제 키보드 이동·재연결 입력 focus·대상/방향 보존·취소·wide/compact 왕복을 확인했다. QA14개 상태·focus AX5개·음악36/자산2개·strict 재열기를 통과했다. build102 당시 폭 전환 focus 이탈은 build104에서 개선했다. 실제 케이블 적용은 미검증이다. [계약](docs/117-connection-workspace-access.md).

**build101은 좁은 편집기 header를 두 줄로 배치해 양끝 동작을 표시한다.** 최종 Release37.87초와 실제 한국어 초안/포커스 왕복·Esc·설정/연결·상위 이동을 확인했다. QA7개 상태·초안AX2개·음악r36/자산2개·strict 재열기 대조를 통과했다. 녹음 busy/takes·IME 조합·모드 Tab 순서와 body 하단 스크롤은 미검증이다. [계약](docs/116-inline-header-layout.md).

**build100은 작은 MIDI 편집기의 inspector와 도구를 폭에 맞게 배치한다.** 최종 Release41.85초와 실제 step 필드·수평 page·검색/줌·노트 이동/Undo·Orbit 초안 보존·하단 접근을 확인했다. QA18개 상태·AX5개·자산2개·physical0과 r36 저장/재열기/disk strict 일치도 통과했다. 긴 셋잇단 메뉴 적용과 header 일부 잘림은 남아 있다. [계약](docs/115-midi-compact-layout.md).

**build99는 편곡 후보를 현재 안으로 적용하지 않고 직접 복제한다.** Core11개·Release41.58초·strict 서명과 실제 행/키보드 복제·취소·한 Undo·검색0개·stale 거절·strict 저장 재열기를 확인했다. QA14개 상태·AX5개 검사·자산2개·physical0 대조와 PNG7개 직접 검토도 통과했다. 음악 재생 없이 자산2개와 사용자 앱을 보존했다. [계약](docs/114-arrangement-candidate-duplicate.md).

**build98은 섹션 연결 메뉴의 선택 판정과 끝 안내를 통일한다.** Core6개·Release39.03초·패키지 strict 서명 검사와 실제 단일 선택 무변경·끝 해제/Undo를 확인했다. 체크 glyph의 시각 확인은 미검증이며 AX highlight를 체크 증거로 계산하지 않는다. output/audition은0회다. [계약](docs/113-section-flow-menu.md).

**build97은 MIDI 작업 도구를 전체 편집 폭에 배치한다.** 작은 창의 Orbit·step·drum step·piano에서 메뉴·bounce·record 표시를 확인했다. Release38.38초와 실제 노트/직접 단축키 편집·Undo·바운스·strict 저장 재열기를 검증했으며 QA20개 상태·AX 내용6개·원본 자산2개·바운스1개·physical0 대조도 통과했다. 메뉴 항목 노출과 동작 검증은 구분하며 실제 MIDI 녹음·물리 출력은 실행하지 않았다. [계약](docs/112-midi-workspace-actions.md) · [QA](qa/workflow-visibility-review.md).

**build96은 offline AU effect를 별도 process에서 처리한다.** 최종 관련46개 테스트·Release47.10초·패키지3개 실행 파일 검증을 통과했다. 패키지 helper의 실제 Apple AU 두 설정에서 각12000-frame PCM이 기준과 정확히 일치했다. host 취소는 테스트했으며 GUI 즉시 STOP race는 코드 guard·compile 확인에 한정한다. 보안 sandbox가 아닌 crash/hang 격리다. [계약](docs/111-au-effect-worker.md) · [QA](qa/au-effect-worker-review.md).

**build95는 현재 대상과 같은 단일 탐색 버튼을 생략한다.** header 복귀와 다중 오디오·effect·source 검색은 유지한다. parse·Release40.30초와 실제 header/단축키/검색 왕복, revision62 음악 불변·strict 저장 재열기를 확인했다. QA10개 상태·AX12개·자산2개·physical0 대조도 통과했다. MIDI/effect는 use-only 안내 상태의 탐색만 검증했다. [계약](docs/110-route-density.md) · [QA](qa/route-density-review.md).

**build94는 콘솔 로그 높이를40–180px로 조절한다.** drag와 입력창의 ⌃⌘1/2/3으로 작게·기본122·크게를 선택하며 초안과 편집 공간을 유지한다. parse·최종 Release40.59초와 실제 단축키·drag·왕복·wheel·명령·저장 재열기를 확인했다. music revision62와 전체 manifest는 유지됐고 QA18개 상태·최종AX10개·자산2개·physical0 대조와 높이82px 감소를 확인했다. 앱 재시작 시 기본122px로 돌아가는 세션 설정이다. [계약](docs/109-console-height.md) · [QA](qa/console-height-review.md).

**build93은 음악 그래프 편집의 공유 원본·이번 사용 범위를 분리한다.** scope snapshot과 대상 guard, use-only 안내·범위 선택을 연결했다. 관련31개·최종 Release45.48초와 실제 이름 수정·초안/scope 전환·group router 생성·Undo·strict 저장 재열기를 확인했다. QA18개 상태·AX9개·자산2개·physical0 대조도 통과했다. 실제 AU 비동기 plugin 검증은 남아 있으며 물리 출력 문제와 별개다. [계약](docs/108-music-graph-edit-scope.md) · [QA](qa/music-scope-review.md).

**build92는 router 경로 전송량을 dB로 편집하고 기존 정밀도·경로 순서를 보존한다.** Core19개·최종 Release41.35초와 실제 네 경로 Tab 입력·slider·Undo·원본 대상 분리·오래된 입력 거절·저장 재열기를 확인했다. QA baseline3개·후보25개·AX12개·자산2개 대조도 통과했다. 원본 안전성은 이번 route helper 검증 범위이며 physical 출력0회로 사용자 앱을 유지한다. [계약](docs/106-router-route-levels.md) · [QA](qa/router-level-review.md).

**build91은 effect·mix·router 출력 볼륨을 dB로 통일하고 작은 창의 router 하단 접근을 복구했다.** 선형 저장값은 유지한다. 최종 관련17개 테스트·Release20.04초와 실제 하단 위치의 편집기 왕복·gain/Undo·저장 재열기 보존을 확인했다. 앞선 후보에서 광범위 dB 입력을 검증했으며 QA 최종 대조도 통과했다. physical 출력0회로 사용자 앱을 유지한다. [계약](docs/105-signal-level-decibels.md) · [QA](qa/signal-level-review.md).

**build90은 포트별 출력 경로와 탐색 대상의 판정을 통일한다.** router 실제 route·mute/gain0 구조 연결·sidechain 제외·lane 소유 미연결 대상을 구분한다. 대상 Swift36개·Release73.47초와 실제 독립 bus·현재 트랙 추론·router 교차 변경/Undo를 확인했다. QA10개 상태·AX7개·자산2개 보존과 저장/재열기 manifest 전체 일치도 통과했다. 읽기 전용 장치 조사로 출력 원인을 확정하거나 정상 재생을 확인하지 않았다. [계약](docs/104-port-aware-navigation.md) · [QA](qa/port-navigation-review.md) · [장치 관측](qa/output-device-review.md).

**build89는 현재 트랙의 ⌘1/⌘2/⌘3 대상을 일관되게 선택한다.** parser·Release42.42초와 실제0/1/여러 대상·MIDI/audio 혼합·미연결 대상 Return·종류 전환·현재 찾기를 확인했다. 저장/재열기의 음악·선택·camera 보존과 QA13개 캡처·AX7개 대조를 통과했다. 신규 Swift unit 테스트는 추가하지 않았다. 출력 재대조에서는 서명 보존 helper2회와 동시간 raw2회가 모두 믹서 획득 단계에서 timeout했다. strict 서명 보존은 가능하지만 출력 해결 근거는 아니다. [계약](docs/103-track-shortcuts-and-output-recheck.md) · [단축키 QA](qa/track-shortcut-review.md) · [출력 대조](qa/output-signature-review.md).

**build88은 선택 섹션 뒤에 연결을 유지하며 삽입하고 출력 준비 단계를 기록한다.** 기존 A→B를 A→새 섹션→B로 바꾸며 불명확한 연결은 거절한다. Audio26개·Core7개·MCP23개·kit9개·file worker16개·Release52.87초를 통과했고 실제 MIDI 편집 중 명령 삽입·Undo/Redo를 확인했다. 섹션 QA22개 상태·자산2개 보존 대조도 통과했다. raw Release helper2회는 성공했으나 패키지 worker는 앱 host와 독립 CLI 실행 모두 각각 두 번 mixerAcquisition에서 timeout했다. 패키지 byte 동일 외부 사본·재서명한 raw 외부 사본도 각2회 timeout했다. 실제 단계 표시·Space 취소·정리는 확인했으며 서명 관련 인과는 미확정이다. [계약](docs/102-section-insertion-and-output-preparation.md) · [섹션 QA](qa/section-insertion-review.md) · [출력 관측](qa/output-preparation-native-review.md).

**build87은 바운스·export의 잔향 길이를 자동 추정하거나0–120초로 지정한다.** 상한·미확정 안내와 끝 구간 측정을 제공하고 긴 보존 클립의 끝을 유지한다. Audio30개·Core3개·MCP22개·kit9개·Release52.98초를 통과했다. 실제 자동74초/직접34초 렌더의 앞34초 PCM 일치와 바운스·export의 재열기 전후 바이트 일치, 입력 거절·취소를 확인했다. QA checker22개 문서 캡처와 RPC 오류·취소 기록 대조도 통과했다. 자동 추정은 무손실 보장이 아니며 실제 청취는 미검증이다. [계약](docs/101-render-tail-policy.md) · [QA](qa/render-tail-review.md).

**build86은 오디오의 공유 원본·이번 사용 범위를 표시하고 전용 클립으로 복귀한다.** 파형 높이를 유지하며 Return으로 빈 범위에서 클립 편집으로 돌아온다. 출력 음소거 상태에서도 pre-output 바운스가 음악을 포함하도록 수정했다. Audio21개·최종 Release41.19초와 실제 범위별 트림/Undo·바운스·클립 복귀·저장 재열기를 확인했으며 QA checker28개 상태·자산2개·바운스1개와 WAV PCM/checksum 대조도 통과했다. 실제 출력·audition은0회로 사용자 앱을 유지한다. [계약](docs/100-audio-scope-and-bounce-mute.md) · [QA](qa/audio-scope-review.md).

**build85는 바운스의 연결 문제와 현재 서클 제외 상태를 기존 편집 줄에서 보여준다.** 연결 보기·명령 검색으로 정확한 출력 IN에 이동한다. Core28개·AudioRouterAudio15개·최종 Release40.86초와 실제 연결 해제/Undo·오토메이션 경고·오래된 명령 거절·저장 재열기를 확인했다. QA checker의 native20개·compact12개 상태, 자산2개·재열기 manifest·source SHA 대조도 통과했다. 이번 범위에서 바운스 렌더·실제 출력·audition은 실행하지 않았으며 사용자 앱과 물리 I/O 출고 조건을 유지한다. [계약](docs/99-bounce-visibility.md) · [QA](qa/bounce-visibility-review.md).

**build84는 편곡안 목록에서 연결 순서·반복·경로 제외 섹션과 오류를 보여준다.** `ArrangementCompiler`와 경로 cursor를 공유한다. Swift401개·Release68.85초와 실제 작은 창의 같은 이름 비교·키보드 전환·연결 수정 반영·Undo·재열기를 확인했다. QA checker의 native15개 상태·자산2개·source SHA 대조도 통과했으며 오디오 시작은 모두0회다. [계약](docs/98-arrangement-route-preview.md) · [QA](qa/arrangement-route-review.md).

**build83은 편곡안의 생성·이름 변경·전환을 한 목록으로 모았다.** MIDI·섹션 편집 중에도 상단에서 현재 편곡 번호와 이름을 확인한다. 목록에서 ⇧⌘N으로 이름을 바꾸고 ⇧⌘D로 이름을 정해 복제하며, 서클 색상과 원안을 보존한다. MCP 복제는 현재 재생 편곡을 유지하고, `select_arrangement`로 명시적으로 전환한다. UI 복제는 새 편곡을 바로 선택한다.

MCP의 복제·이름 변경·명시적 선택을 지원한다. 관련 Core30개·MCP21개와 최종 Release68.50초를 통과했다. 실제 MCP 복제의 편곡 선택·MIDI 편집기 보존, 명시적 전환의 곡 포커스, Undo 다섯 번의 음악 복원·재열기를 확인했다. UI·키보드·원안 보존 검증도 완료했다. [계약](docs/97-arrangement-workspace.md) · [QA](qa/arrangement-workspace-review.md).

**build82는 이전 재생의 늦은 실패가 새 출력 세션을 취소하지 않도록 수정했다.** timeout/catch의 세션 ID 확인과 취소를 같은 lock 안에서 처리하며 외부 STOP 동작은 유지한다. OutputWorkerProcess/Protocol 관련16개 테스트를 통과했다. build81 무음 helper의 실제 장치 시작·STOP·EOF·세션 교체와 별도 재생 시계 0→1초·자연 종료를 확인했으며, build82 release 빌드는 46.09초에 통과했다. 실제 host 첫 시도는 장치 단계 timeout 뒤 idle로 복구했고, 다른 세션의 재시도는 출력 시작·시계 1.1145625초 진행·STOP 후 idle을 확인했다. 세 번째 세션은 약34초 진행 후 자연 종료했으나 간헐적인 최초 시작 실패가 남아 있다. 청취·입력·장치 변경·MP4 검증과 과거 HAL 정지 원인 확인은 남아 있다. [출력 세션 QA](qa/output-session-review.md).

**build81은 서클 색상을 구분하고 직접 지정한다.** 서클 종류별 기본색과 개별 사용자 지정·복원 메뉴를 추가했다. 저장 모델과 history 14개 테스트를 통과했으며 실제 색상 선택·Undo·저장/재열기와 패널 초기화 회귀를 확인했다. [계약](docs/96-circle-colors.md).

이펙트·오토메이션·바운스의 저장/재열기와 보관된 WAV 자동화 반영을 재검증했다. 물리 출력·청취 결과와 구분한 [통합 흐름 QA](qa/automation-flow-review.md)를 제공한다.

**build80은 바운스 대상과 연결 문제를 실행 전에 보여준다.** 편집기의 공통 버튼에 트랙명을 표시하고, 연결 없는 출력은 UI·MCP에서 렌더 시작 전에 거절한다. 관련17개 테스트·실제 바운스/원본 복원/Undo·native7상태를 검증했다. [계약](docs/95-bounce-target-preflight.md) · [QA](qa/bounce-target-review.md).

**build79은 오디오 가져오기 대상을 파일 창에서 보여준다.** 섹션에서는 새 트랙, 개별 음악 서클에서는 선택 트랙을 사용해 이전 트랙에 뜻하지 않게 섞이는 일을 막는다. 관련16개 테스트와 실제 파일 가져오기·Undo·재열기를 확인했다. [계약](docs/94-audio-import-destination.md) · [QA](qa/import-destination-review.md).

**build78은 이동 직후 저장해도 편집 위치를 복원한다.** 대기 중인 이동을 반영하고 진행 중에는 목적지 카메라를 저장한다. 사용자가 취소한 이동은 중단 위치를 유지한다. 관련18개 테스트·실제8상태와 음악/패키지 보존을 검증했다. [계약](docs/93-save-focus-destination.md) · [QA](qa/save-focus-review.md).

**build77에서 생성 메뉴는 현재 위치의 작업을 먼저 표시한다.** 빈 Sound Bank 드럼도 기본 8행에서 바로 입력하며 검색·Undo·저장 복원을 유지한다. 관련 Swift7개와 실제 앱10상태를 검증했다. [계약](docs/92-creation-and-drum-entry.md) · [QA](qa/creation-interface-review.md).

**build76은 출력이 응답하지 않아도 정리 후 다시 재생을 요청할 수 있다.** 별도 helper를 기본 재생에 연결하고 준비·정리·다시 재생 가능 표시를 키웠다. Swift513개·helper16개와 실제 앱의 timeout/재시도/Space 취소·음악 보존을 검증했다. build76 당시 정상 장치 출력은 미검증이었다. [계약](docs/91-output-recovery.md) · [QA](qa/output-host-review.md).

**build 75에서 키보드 사용법을 검색한다.** 현재 작업의 조작을 먼저 보여주고 전체/MIDI/오디오/오토메이션 등으로 좁힌다. 명령 검색은 단축키도 찾고 제목 일치를 우선 표시한다. [계약](docs/89-searchable-shortcuts.md) · [QA](qa/shortcut-search-review.md).

**build 74에서 오디오 수치를 키보드로 바로 편집한다.** 파형의 Tab/Shift+Tab과 수치 입력 버튼으로 진입하고 Return/Esc로 복귀한다. 복제 공간이 부족하면 실행 전에 이유를 표시한다. [계약](docs/88-audio-keyboard-preflight.md) · [QA](qa/audio-keyboard-review.md).

**build 73에서 오디오 편집의 좌우 스크롤 폼을 없앴다.** 전체 폭 파형 아래 두 줄에서8개 수치를 직접 입력하고 상단에서 분할·복제·템포 추종을 조작한다. 작은 창에서도 모두 보인다. [계약](docs/87-audio-editor-layout.md) · [QA](qa/audio-layout-review.md).

**build 72에서 피아노 롤의 선택 위치로 바로 이동한다.** 상단 ‘선택 보기’ 또는 F로 가려진 노트를 찾는다. 작은 창의 눈금 가림을 수정하고, 넓은 선택은 기준 노트로 이동한다. [계약](docs/86-midi-selection-reveal.md) · [검증](qa/selection-reveal-review.md).

**build 71에서 편집 선택을 복원한다.** 서클·원본 범위별 MIDI 선택, 볼륨/팬별 점과 오디오 원본 시간 커서를 기억하고 현재 작업의 선택을 문서에 저장한다. 삭제된 참조를 제외하며 트림 Undo/Redo에서도 커서 시간을 유지한다. Swift496개·Python29개, native30상태/34화면과 전체 음악/자산 보존 통과. [계약](docs/85-editor-selection-memory.md) · [QA](qa/selection-memory-review.md).

**build 70에서 캔버스의 접근성 클릭 위치를 바로잡았다.** 스텝 행·셀, MIDI 노트, 오토메이션 점, 서클·포트·케이블이 창 이동과 스크롤을 따라간다. 스텝의 행 객체를 유지해 경계 행의 클릭 실패를 수정했다. AppKit14개·Swift491개·Python29개, 실제14상태/21화면과 음악 보존을 확인했다. [계약](docs/84-accessibility-geometry.md) · [QA](qa/accessibility-geometry-review.md).

**build 69에서 여러 MIDI 노트를 수치로 함께 편집한다.** 단일/다중 선택을 같은2열 입력으로 정리하고 복제·삭제를 선택 개수 옆에 두었다. 다중 선택은 음정·시작·길이·세기를 입력한 차이만큼 함께 조절하며, 차이를 보존할 수 없으면 전체를 거절한다. MCP도 상대 길이·세기 편집을 지원한다. Swift491개·Python29개, native14상태/25화면·전체 음악/키트 비교 통과. [계약](docs/83-midi-selection-inspector.md) · [QA](qa/midi-inspector-review.md).

**build 68에서 편집하던 페이지 안의 위치를 유지한다.** 서클·원본 범위별 스텝 페이지/행 검색·음역, 피아노롤 스크롤, 궤도 마디·음역, 오디오 확대 범위와 오토메이션 표시 길이를 기억한다. 현재 서클의 보기는 저장·재열기에서 복원하며 음악 이력과 분리한다. 길이가 줄면 범위를 보정한다. Swift485개·Python28개, native19상태·43화면과 음악/패키지 비교를 통과했다. [계약](docs/82-editor-view-position.md) · [QA](qa/editor-position-review.md).

**build 67에서 저장한 작업 페이지로 돌아온다.** 연결·전환·오토메이션·설정과 MIDI 스텝, 편집 범위·현재 서클의 연결 검색/선택을 보기 정보로 복원한다. 사라진 서클은 유효한 상위 화면으로 이동하고 삭제된 케이블의 재연결은 해제한다. 같은 문서 재열기 후 검색 재저장 결함을 수정했다. Swift477개·Python28개, 최종 native18상태·20화면과 전체 음악 비교를 통과했다. [계약](docs/81-saved-workspace.md) · [QA](qa/saved-workspace-review.md).

**build 66에서 연결 작업을 오가도 선택을 유지한다.** 같은 프로젝트 세션에서 서클별 검색·IN/OUT·대상·8방향·재연결을 기억하고, 상단 편집·연결·최근 전환으로 바로 돌아간다. 연결 본문과 상단 버튼을 Tab/Shift-Tab/Return으로 이동한다. 삭제된 케이블의 재연결은 해제하며 명시적 포트 요청이 기억보다 우선한다. Swift469개·Python28개, 실제27상태·상태 복원34화면·최종 키보드7화면과 전체 음악 보존을 확인했다. 임시 작업은 재실행 후 초기화한다. [계약](docs/80-workspace-return.md) · [QA](qa/workspace-return-review.md).

**build 65에서 음악 설정의 조작 단계를 줄였다.** 마디·반복과 MIDI 시작·길이를 위로 모으고 리듬을 우선 표시한다. 기본값·앨범·개별 출처를 버튼으로 바로 바꾸며 보관값 도움말과 Tab/Shift-Tab/Return을 지원한다. Swift463개·Python28개, 실제23상태·최종21화면에서 출처 복원·직접 입력·Undo/Redo·연결 왕복·저장 재열기를 확인했다. [계약](docs/79-music-settings-visibility.md) · [QA](qa/music-settings-review.md).

**build 64에서 섹션 연결과 전환을 한 작업 화면으로 모았다.** 설정 맨 위의 `섹션 순서·전환` 또는 L에서 대상 검색·재생 분기·전환·재연결·해제를 다룬다. 동명 섹션은 #번호와 곡/편곡 경로로 구분하고 전환 앞·뒤에도 번호를 표시한다. 기존 케이블 ID·효과와 다른 곡을 보존하며 Undo/Redo를 지원한다. Swift463개·Python28개, 실제 27상태·22화면과 저장 복원을 확인했다. [계약](docs/78-section-connection-workspace.md) · [QA](qa/section-connection-review.md).

**build 63에서 편곡안을 바로 검색한다.** 곡·악장 서클의 `편곡안`, 설정 맨 위의 현재 편곡, ⌥⌘J·명령 검색에서 같은 캔버스의 목록을 연다. 이름·#번호·섹션 수·재생 선택으로 동명 대안을 구분하고, 현재 재선택은 편집 위치와 Undo/Redo를 유지한다. 실제 2곡/67편곡의 선택·충돌 거절·저장 복원과 작은 창 가시성을 확인했다. Swift457개·Python28개, [계약](docs/77-arrangement-search.md) · [QA](qa/arrangement-search-review.md). 사용자 앱0.19.0 build21은 유지하며 물리 I/O 검증은 남아 있다.

build 62는 **에이전트가 화면 조작 없이 실제 음색을 검색한다.** 읽기 전용 `circlr_sounds`로 내장 신스·Sound Bank·설치된 AU의 이름·계열·번호·변형을 조회한다. 페이지와 목록 변경 감지, 정확한 적용 주소, 전문 역할 사용 지침을 함께 제공한다. Swift **451개**·Python **28개**, 실제 MCP 3회 검증과 최소화·적용/Undo·재열기·GUI 대조를 통과했다. [연결 계약](docs/76-agent-sound-catalog.md) · [QA](qa/agent-sounds-review.md).

build 61은 **Sound Bank를 실제 악기 이름·계열·번호로 검색한다.** `음색·악기 찾기`의 Sound Bank에서 `피아노`, `E.Piano`, `#5`처럼 검색하고 멜로디/드럼 킷을 고른다. 같은 번호의 변형 음색도 이름과 뱅크 값으로 구별하며 ↑↓·Return으로 바로 적용한다. 이 Mac의 실제 목록 235개, Swift **445개**·Python **26개**, native 상태 16개·화면 18개로 선택·Undo·설정 보존·저장 복원과 안내 표시를 확인했다. 새 변형 음색은 build 61 이상에서 사용한다. 물리 재생은 이번 검증에 포함하지 않았다. [사용법](docs/75-sound-bank-program-search.md) · [QA](qa/sound-bank-search-review.md).

build 60은 **음색·악기와 Audio Unit을 같은 캔버스에서 검색해 바로 적용한다.** 내장 신스·설치된 AU를 이름/제조사로 찾으며, 서클·전역 이펙트에도 검색을 제공한다. 같은 음색은 수정한 설정을 보존하고 다른 음색은 Undo 한 번으로 복원한다. ⇧⌘P의 `음색·악기 찾기` 또는 편집기의 검색 버튼으로 열고 ↑↓·Return·Esc로 조작한다. Swift **437개**·Python **26개**, native 상태 23개·화면 20개로 실제 선택·취소·오래된 요청 차단·저장 복원을 검사했다. [사용법](docs/74-sound-selection-search.md) · [QA](qa/sound-selection-review.md).

build 59는 **⌘J 검색 결과에서 실제 섹션·서클을 바로 연다.** 이펙트를 찾고 Return을 누르면 해당 이펙트가 열리며, 전체 앨범/이 섹션·종류 필터와 현재 위치 찾기를 지원한다. 다중 서클 메뉴를 검색으로 바꾸고 긴 이름·반복 섹션·공유 이펙트의 경로를 구별한다. Swift **429개**·Python **26개**, 13섹션·137대상의 실제 이동·이력·외부 변경·재실행을 확인했다. [사용법](docs/73-direct-work-navigation.md) · [QA](qa/direct-work-navigation-review.md).

build 58은 **오디오를 넣을 트랙을 같은 라이브러리 화면에서 검색**한다. 이름·번호, 동명 트랙 구분, 현재 대상 자동 스크롤, ↑↓·Return·Esc를 지원한다. 고른 뒤에도 번호·전체 이름 도움말이 남고 파일 선택과 시작 박을 유지한다. Swift **423개**·Python **26개**, 99트랙의 실제 검색·충돌 거절·9.5박 가져오기·Undo/Redo·저장 재열기를 확인했다. [사용법](docs/72-library-track-search.md) · [QA](qa/library-track-search-review.md).

build 57은 **접힌 그룹 안의 오디오·MIDI·음색으로 바로 이동**한다. ⌘J/역할 버튼/MCP focus는 선택 경로만 화면에서 펼치고, Esc로 나오면 원래 접힘 상태를 보여준다. 음악 Undo/Redo와 그룹의 저장 상태를 유지하며 내부 편집 화면도 재열기에서 복원한다. Swift **419개**·Python **26개**, 실제 경로 왕복·음악/그룹 Undo·MCP·저장 복원을 확인했다. [사용법](docs/71-navigation-group-reveal.md) · [QA](qa/navigation-reveal-review.md).

build 56은 **궤도·그리드·스냅 보기를 음악 Undo/Redo와 분리**한다. 음악을 편집한 뒤 보기를 바꿔도 한 번의 Undo가 편집을 되돌리고, Undo 뒤 보기 변경도 Redo를 지우지 않는다. 보기 설정은 문서에 저장하며 실제 서클 이동·그룹·포트 편집의 Undo는 유지한다. Swift **413개**·Python **26개**, 실제 MIDI Undo/Redo·서클 이동·⌘S·재열기와 패키지를 확인했다. [사용법](docs/70-canvas-view-history.md) · [QA](qa/view-history-review.md).

build 55는 **가져오기와 오디오·MIDI·오토메이션·서클 설정의 시작 위치를 1 기반 박으로 통일**한다. 9.5박에 넣은 음악은 편집기에서도 9.5박이며 길이·원본 초·저장 좌표는 그대로다. Swift **406개**·Python **26개**, 실제 입력·편집 방식 왕복·경계/충돌·가져오기·Undo·저장 복원과 작은 창 표시를 확인했다. [사용법](docs/69-beat-position-display.md) · [QA와 남은 Undo 사용성](qa/beat-position-review.md).

build 54는 **샘플을 넣을 섹션·트랙·시작 박을 같은 라이브러리 화면에서 정한다.** 곡·섹션 검색과 ↑↓/Return으로 대상을 고르고, 시작 박 옆에서 마디·초를 확인한다. 대상 선택은 캔버스와 음악을 이동시키지 않는다. Swift **401개**·Python **26개**, 다른 섹션의 실제 오디오/MIDI 배치·일괄 배치·입력 충돌·한 번 Undo·저장 복원과 최종 앱을 확인했다. [사용법](docs/68-library-import-placement.md) · [QA](qa/library-placement-review.md).

build 53은 **라이브러리의 폴더 관리 단계를 줄이고 오류 복구 표시를 정리**한다. 같은 화면에서 경로·파일 수·읽기 상태를 보고 바로 검색하거나 등록을 해제한다. 동명 폴더를 상위 경로로 구분하며, 선택을 수정하면 해결된 오류만 사라진다. 검색어·다중 선택의 관리 화면 왕복과 Escape, 가져온 음악을 보존하는 등록 해제·Undo·저장 복원을 확인했다. [사용법](docs/67-library-folder-workspace.md) · [QA](qa/library-folders-review.md).

build 52는 **샘플 라이브러리에서 여러 오디오를 한 번에 가져온다.** 체크박스·⇧↑↓ 범위·모두 선택/해제로 최대 64개를 고르고 각 새 트랙의 같은 시작 박에 배치한다. 선택 수·현재 파일·대상을 표시하며 MIDI 혼합과 손상 파일의 부분 적용을 막는다. Swift **391개**·Python **26개**, 두 폴더의 실제 가져오기→한 번 Undo/Redo→저장·재열기와 원본 보존을 확인했다. [사용법](docs/66-library-batch-import.md) · [QA](qa/library-batch-review.md).

build 51은 **같은 음높이·같은 시작 박의 노트를 한 번에 선택**한다. 피아노 롤·궤도·스텝의 속성 영역에 선택 메뉴와 해제를 표시한다. ⌥P 음높이, ⌥T 시작 박, ⌥I 반전, ⇧⌘A 해제를 지원하며 화면 밖 노트도 포함한다. Swift **386개**·Python **26개**, 실제 선택→음악 편집/Undo·대상 분리·저장 복원을 확인했다. [사용법](docs/65-midi-selection-tools.md) · [QA](qa/midi-selection-tools-review.md).

build 50은 **선택한 MIDI 코드·프레이즈를 피아노 롤과 궤도에서 함께 드래그**한다. 본문은 시간·음정, 끝 손잡이는 길이를 함께 바꾸며 기존 그루브와 노트 간격을 유지한다. 화면 밖 선택도 포함하고 한 번의 Undo로 복원한다. Swift **382개**·Python **26개**, 실제 두 편집기의 이동·길이·경계·단독 선택·저장 복원을 확인했다. [사용법과 계약](docs/64-midi-group-drag.md) · [QA와 제한](qa/midi-group-drag-review.md).

build 49는 **파형 위 휠로 원본 시간을 확대·축소하고 키보드로 이동**한다. 화면 밖 분할 커서를 현재 배율로 찾고 편집/Undo·궤도 전환 중 배율을 유지한다. 하단 조작을 한 줄로 모아 작은 창의 원형 파형 높이를 확보했다. Swift **377개**·Python **26개**, 최종 앱의 실제 휠·트림/Undo·대상 전환·저장 복원을 확인했다. [사용법과 계약](docs/63-audio-source-navigation.md) · [QA](qa/audio-source-navigation-review.md).

build 48은 **오토메이션의 화면 밖 점까지 바로 탐색하고 마디 눈금도 이어 표시**한다. 이전/다음·Home/End·선택 점 보기와 마디/박/초 정보를 제공하며, 편집·Undo·자유/궤도 전환 때 범위를 유지한다. 깨끗한 빌드의 Swift **374개**·Python **26개**, 실제 탐색·편집/Undo·대상 분리·원본 복원을 확인했다. [계약](docs/62-automation-time-navigation.md) · [QA와 증분 빌드 실패 기록](qa/automation-time-navigation-review.md).

build 47은 **드럼 스텝의 행·샘플 이름·MIDI 번호를 바로 검색**한다. 행 이름 선택, 현재 열을 유지한 행 추가, Home/End·PageUp/PageDown 탐색과 숨겨진 선택 행 복귀를 지원한다. 검색은 음악을 바꾸지 않으며 보이는 행만 그린다. Swift **369개**·Python **26개**, 101행의 작은 창에서 검색·노트 입력/Undo·대상 전환·원본 복원을 확인했다. [계약](docs/61-step-row-navigation.md) · [QA와 남은 범위](qa/step-row-navigation-review.md).

build 46은 **MIDI 전체 음역에서 클릭·드래그·키보드로 바로 이동**한다. 현재 표시 범위와 연주 분포를 함께 보여주고 선택한 음명/MIDI 번호를 궤도 중앙에 표시한다. 작은 창에서도 편집 방식·노트 이동·MIDI 메뉴·바운스를 고정해 유지한다. Swift **366개**·Python **26개**, 실제 탐색·노트 편집/Undo·대상 전환·저장 복원을 확인했다. [계약](docs/60-midi-pitch-navigation.md) · [QA와 남은 범위](qa/pitch-navigation-review.md).

build 45는 **이름을 Return/Tab으로 한 번 확정하고 Esc로 취소**한다. 입력 중에는 음악 이력을 만들지 않으며 ⌘S는 이름을 확정한 뒤 저장한다. 빈 이름·외부 변경 오류를 같은 헤더에 표시하고, 한글·일본어·emoji를 보존한다. Swift **363개**·Python **26개**, 실제 입력·저장·충돌·Undo·재열기와 원본 보존을 검증했다. [계약](docs/59-name-editing.md) · [QA와 실제 IME 등 남은 범위](qa/name-editing-review.md).

build 44는 **선택한 서클 이름을 최대 세 줄로 표시**한다. 밀집한 배치와 화면 가장자리에서 빈 위치를 찾고, 연결 도구·선택 포트·시간 손잡이를 피한다. 화면 밖 중심의 이름표도 클릭·접근성으로 탐색한다. Swift **353개**·Python **26개**, 실제 이름/연결/궤도 시간 조작·Undo·저장 복원을 검증했다. [계약](docs/58-canvas-readable-selection.md) · [QA와 후속 이름 입력 개선](qa/canvas-label-review.md).

build 43은 **악기 미리 듣기를 UI 밖의 worker로 분리**했다. 준비 중 놓은 건반·취소된 요청을 폐기하고, 같은 건반 재누르기·악기 교체·정리·timeout을 관리한다. 기존 transport 줄의 준비/정리 표시와 Space 취소, MCP 상태 조회를 제공한다. Swift **345개**·Python **26개**, 실제 장치 대기 중 노트/숫자 편집·취소·Undo·저장/재열기를 검증했다. 정상 음원 출력과 HAL 지연 해결은 아직 확인하지 못했다. [계약](docs/57-audition-worker.md) · [QA](qa/audition-worker-review.md).

build 42는 **MIDI 가져오기의 시작 위치를 직접 확인·수정**한다. 메뉴·라이브러리·궤도 drop이 같은 시작 박을 전달하고 파일의 선행 쉼표·노트 간격을 보존한다. 길이 초과 안내와 이번 섹션 연장, 단일 서클 편집/다중 서클 전체 보기, 외부 변경 거절을 지원한다. [작업 계약](docs/56-midi-import-placement.md) · [검증과 제한](qa/midi-placement-review.md).

build 41은 **대상 포트를 검색 목록에서 바로 선택·연결**한다. ↑↓ 선택·Return 연결, 전체/현재 포트 필터와 긴 이름 표시를 지원한다. 포트·위치·검색·연결 조작을 목록 위에 고정하고, 기존 케이블은 따로 스크롤한다. Swift **330개**·Python **26개**, 실제 IN/OUT·8방향·재연결·그룹 필터·작은 창/콘솔 확장과 Undo/저장 복원을 확인했다. [작업 계약](docs/55-connection-workspace.md) · [검증과 제한](qa/connection-workspace-review.md).

build 40은 **섹션 전환의 앞·뒤 대상, 마디/초 기준, 실제 시간과 다음 섹션 시작 변화를 같은 화면에 표시**한다. 전역·서클·전환 효과는 dB/ms/% 등 실제 단위와 공통 Tab/Shift-Tab 입력을 사용한다. 작동하지 않는 전환 효과 항목을 숨기고 연결 편집 왕복 시 전환을 유지한다. Swift **330개**·Python **26개**, 실제 수치/충돌·정밀도·저장 복원과 73초 오프라인 WAV export를 검증했다. 물리 출력·녹음 검증과 사용자 앱 교체는 남아 있다. [편집 계약](docs/54-transition-effect-workspace.md) · [검증과 제한](qa/transition-effects-review.md).

build 39는 **선택과 편집 방식이 바뀌어도 제목·트랙 경로·본문 시작 위치를 유지**한다. 같은 캔버스 상단의 MIDI/오디오·연결·오토메이션·설정으로 바로 전환하며 현재 작업을 강조한다. 긴 속성은 본문 안에서 스크롤하고 녹음 테이크는 상단에서 선택한다. Swift **325개**·Python **26개**, 작은 창의 선택·Tab 입력·작업 왕복·콘솔 접기·Undo·저장/재열기와 최종 패키지를 검증했다. [편집 계약](docs/53-editor-workspace-shell.md) · [검증과 제한](qa/editor-shell-review.md).

build 38은 **오디오 파형·시작/끝·분할·볼륨 dB·페이드 ms를 한 화면에 배치**한다. 전체 파일/선택 구간 보기는 음악을 변경하지 않고, 궤도/자유 배치 전환에서도 확대 범위를 유지한다. 숫자는 Tab으로 연속 입력하고 Return/Esc 뒤 파형으로 돌아간다. 공유 클립의 직접 편집은 선택 서클만 변경한다. Swift **325개**·Python **26개**, 실제 trim·충돌 거절·분할/복제·34초 바운스·원본 복원·저장/재열기를 검증했다. [작업 공간 계약](docs/52-audio-workspace.md) · [검증과 제한](qa/audio-workspace-review.md).

build 37은 **스텝·피아노 롤의 격자와 선택 속성을 같은 화면에 배치**한다. 스텝 번호와 피아노 롤의 박/음높이 눈금을 스크롤 중에도 유지하며, 선택 노트의 페이지·음역·스크롤을 따라간다. MIDI 속성은 Tab/Shift-Tab으로 순서대로 입력하고 Return/Esc 뒤 해당 편집기로 돌아간다. 드럼 행·분할·페이지도 편집기 왕복에서 유지한다. Swift **319개**·Python **26개**, 실제 스텝 입력·피아노 드래그·충돌 거절·Undo·저장 복원을 확인했다. [작업 공간 계약](docs/51-midi-grid-workspace.md) · [검증과 제한](qa/midi-grid-workspace-review.md).

build 36은 **MIDI 궤도·음역/마디 탐색·선택 노트 속성을 같은 화면에 배치**한다. 1/2옥타브와 1/2/4/8마디·전체 길이를 선택하고 이전/다음 노트로 이동한다. 숫자 확정 뒤 방향키로 이어서 편집하며 긴 노트도 현재 마디에서 이동한다. 궤도·스텝·자유 배치 왕복 시 표시 범위를 유지한다. Swift **318개**·Python **26개**, 최종 앱의 작은 창·키보드·원호 이동·충돌 거절·저장 복원을 검증했다. [편집 계약](docs/50-midi-orbit-workspace.md) · [QA와 남은 범위](qa/midi-orbit-workspace-review.md).

build 35는 **궤도/자유 배치 전환과 Undo에서도 현재 편집 화면의 위치·크기를 유지**한다. 메뉴와 명령 검색이 같은 동작을 하며 MIDI·스텝·오디오·오토메이션에서 확인했다. 오토메이션 전체 점 범위는 편집 중 고정하고, 겹친 점은 Option 클릭으로 순환하거나 대괄호로 선택한 뒤 그대로 드래그한다. Swift **311개**·Python **26개**, 실제 전환·끝점 드래그·범위/MCP·저장 복원을 검증했다. Option 클릭 조합의 실제 입력은 도구 제약으로 별도 검사 대상이다. [편집 계약](docs/49-canvas-editing-continuity.md) · [QA와 남은 UI](qa/editing-continuity-review.md).

build 34는 **오토메이션 곡선·선택 점·공유 원본 전환을 같은 캔버스에서 바로 편집**한다. 자유 배치는 곡선을 넓게, 궤도는 원의 높이를 유지하도록 배치한다. 볼륨 dB·팬 %·로컬 박/초를 표시하고, Return/Esc 뒤 방향키로 이어서 조절한다. ‘전체 점 보기’의 범위를 MCP에도 반영한다. Swift **307개**·Python **26개**, 최종 앱의 궤도/자유 드래그·삭제·Undo·충돌 거절·저장 복원을 검증했다. [편집 계약](docs/48-automation-workspace.md) · [QA와 제한](qa/automation-workspace-review.md).

build 33은 출력 서클에 **서클 레벨 / 트랙 전체 레벨**을 구분해 dB 입력·fader·음소거·0 dB 복원을 제공합니다. 작은 창과 콘솔 열림 상태에서도 두 범위와 볼륨/팬 오토메이션·바운스 바로가기를 함께 표시합니다. 공유 원본은 레벨만 부분 편집하며 개별 사용 설정을 유지합니다. Swift **303개**·Python **26개**, 실제 입력·드래그·Undo·충돌 거절·저장 복원을 검증했습니다. [편집 계약](docs/47-output-editing.md) · [QA와 제한](qa/output-editing-review.md).

build 32는 **재생 장치의 시작·정지·시간 조회·해제를 하나의 background worker로 분리**한다. 출력 시작/정리 상태를 기존 줄에 표시하고, 정리 중 중복 시작과 취소된 시작의 늦은 재생을 차단한다. 숫자 입력의 Return/Esc 뒤에는 캔버스 포커스가 돌아와 Space를 바로 사용할 수 있다. Swift **293개**·Python **26개**, release build와 실제 대기 중 편집·Undo·키보드를 확인했다. 현재 Mac의 HAL 출력 획득 지연은 음악 없는 별도 진단에서도 재현되어 정상 재생·청감과 사용자 앱 교체는 완료되지 않았다. [실행 계약](docs/46-playback-worker.md) · [검증과 제한](qa/playback-worker-review.md).

build 31은 상단 **샘플 / ⌥⌘L**에서 로컬 오디오·MIDI 폴더를 검색하고 바로 가져온다. 여러 폴더의 파일명·하위 경로·형식을 검색하며 **↑↓ 선택 → Return 가져오기**, **⌥Space 미리 듣기**, Esc 닫기를 지원한다. MIDI는 기존 트랙 선택 화면으로 이어진다. 대상이 외부에서 변경되면 갱신 전 가져오기를 막는다. 폴더는 읽기 전용 bookmark로 보관하며 목록 제거는 원본 파일을 삭제하지 않는다. 작은 창의 상단 표시와 검색 화면의 접근성 범위도 정리했다. [라이브러리 계약](docs/45-local-media-library.md) · [실제 검증·출력 지연 제한](qa/library-review.md).

build 30은 같은 캔버스의 **템포·박자·스케일·박 분할/강세·리듬을 현재 값에서 바로 편집**한다. 기본값/앨범/개별 출처를 함께 표시하며 상속 중 값을 바꾸면 해당 항목만 개별 설정이 된다. 전체 적용 버튼 없이 Return/Tab으로 확정하고 ⌘Z로 한 항목씩 복원한다. 강세는 `2+2+3`처럼 입력해 Return 또는 행의 적용 버튼으로 확정한다. Swift **272개**·Python **26개**, 실제 상속 전환·연속 입력·잘못된 강세·MCP 충돌·리듬 연결·Undo·저장/재열기와 최종 패키지를 검증했다. [편집 계약](docs/44-direct-music-context.md) · [build 30 QA](qa/context-editing-review.md).

build 29는 신스·오디오·MIDI·출력 볼륨·반복·템포의 숫자 입력을 통일한다. **Return 또는 Tab으로 확정, Esc로 취소**하며 입력 중에는 음악을 바꾸지 않는다. 범위·정수 오류는 필드에 표시하고, 이미 입력하던 대상이 외부에서 바뀌면 덮어쓰지 않는다. Native Tab의 포커스 순서와 현재 모델 Binding을 함께 수정해 빠른 연속 입력을 검증했다. Swift **265개**·Python **26개**, 실제 앱의 개별 Undo·정밀도 보존·저장/재열기와 패키지 일치를 확인했다. [입력 계약](docs/43-number-editing.md) · [build 29 검증과 남은 범위](qa/number-editing-review.md).

build 28은 효과를 **컷오프 Hz·지연 ms·압축 임계값 dB·압축비** 등 실제 단위로 표시한다. 슬라이더를 놓거나 숫자에서 Return/Tab으로 확정하면 한 번 적용되며, Esc는 입력을 취소한다. 작성 중 다른 편집이 같은 효과를 바꾸면 덮어쓰지 않는다. 같은 편집기에서 음소거·출력 볼륨·바운스도 바로 접근한다. Swift **259개**·Python **26개**, 실제 숫자·슬라이더·연속 Tab 입력·Undo·재열기를 확인했다. [효과 편집 계약](docs/42-effect-editing.md) · [build 28 QA와 남은 범위](qa/effect-editing-review.md).

build 27의 새 오디오 lane은 **오디오·믹스·출력 서클**로 시작한다. ⌘J 검색의 Return과 ⌘1은 실제 오디오 편집을 열고, 첫 MIDI 노트 입력이나 명시적 리듬 패턴 생성 때 악기 경로를 추가한다. 편집기 상단 **이펙트 추가**에서 선택한 오디오 뒤 또는 출력 앞에 효과를 넣는다. 기존 문서의 서클·끊어 둔 연결·마스터 위치를 보존한다. Swift **253개**·Python **26개**, 실제 메뉴·MIDI/스텝·34초 WAV·6단계 Undo·저장/재열기를 검증했다. [소스별 서클 계약](docs/41-source-aware-circles.md) · [build 27 QA](qa/source-circles-review.md).

build 26은 **여러 오디오 파일을 백그라운드에서 복사·검증하고 한 번의 Undo로 적용**한다. 여러 파일은 각 트랙으로 추가한 뒤 섹션 전체를 보여준다. 파일 선택 중 대상 음악이 바뀌면 적용하지 않으며, 저장→Undo→저장→Redo에서도 가져온 오디오 참조를 유지한다. 메뉴·MIDI 미리보기와 저장 복원을 별도 앱에서 검증했다. 캔버스 file-URL drop은 구현했으며 실제 Finder 드래그·Splice file promise는 후속 검증 범위다. [파일 가져오기 계약](docs/40-media-import.md) · [build 26 검증](qa/media-import-review.md).

build 25는 **상단 시계 아래에 실제 출력 연결·대기 시간·준비 완료를 표시**한다. 10초 대기 초과는 작업을 막는 대화상자 대신 상태로 알리고, STOP 뒤에도 하나의 장치 연결을 유지한다. 늦게 연결돼도 취소한 곡은 자동 재생되지 않는다. 재생 팔로우가 편집기를 닫을 때 키보드 포커스를 캔버스로 복귀시켜 **Space 정지**를 유지하며 콘솔 입력은 보호한다. Swift **236개**·Python **26개**, 실제 연결 지연·취소·재생과 포커스를 검증했다. 장치 지연 원인 자체는 해결 전이다. [출력 상태·키보드 QA](qa/output-connection-review.md).

build 24는 **섹션 진입과 재생 팔로우를 내부 작업 서클에 맞춰 확대**한다. 이름표는 다른 원 내부와 겹치는 위치를 피하고, 재생 중 이름표를 더블클릭해도 수동 확대가 취소되지 않아 같은 캔버스의 편집기로 바로 들어간다. 휠 확대는 팔로우를 일시 정지하며 상단 재개 버튼으로 복귀한다. Swift **231개**·Python **26개**와 release build, 실제 큰 창/최소 폭 및 콘솔 열림/닫힘 네 조합에서 8개 이름표의 가독성·편집 진입·팔로우를 확인했다. 실제 마이크·VoiceOver·전체 밀집 조합과 최초 출력 장치 연결 지연은 남아 있다. [재생 화면 검증](qa/playback-framing-review.md).

개발 브랜치의 포트 표시는 **대표 지점과 실제 연결 위치**를 기본으로 보여준다. **포트를 클릭하거나 P로 선택하면 그 포트의 8방향을 펼친다.** 라우터의 네 포트를 모두 8번씩 표시하던 혼잡을 줄이고, 이름은 포트마다 한 번씩 겹치지 않게 배치한다. 드래그 중에는 가까운 호환 대상의 방향을 펼치고 도구막대를 숨긴다. 화면 밖이나 다른 조작에 가려진 지점은 클릭 대상에서 제외한다. [포트 가독성·실제 조작 검증](qa/ports-density-review.md).

`codex/eight-direction-ports` 브랜치에는 실제 포트 ID·형식·수용 정책, 8방향 geometry, 음악과 분리된 배치 revision·Undo·저장 계약을 추가했다. 독립 스테레오 **2 IN / 2 OUT 라우터**는 port별 PCM과 2×2 전송량을 사용한다. 서클 선택 후 **연결 / L**을 누르면 같은 캔버스에서 포트 검색·연결·재연결·해제와 양 끝의 8방향 배치를 편집한다. 라우터 전송량은 슬라이더나 숫자로 조절하며 숫자는 Return 또는 포커스 이동으로 한 번 적용한다.

개발 브랜치에서는 **케이블 클릭 → 재연결 / 위치 이동 → OUT·IN 끝점 드래그**로 직접 편집한다. 중앙에 놓으면 포트를 선택하고 기존 방향을 유지하며, 둘레에 놓으면 가까운 8방향을 사용한다. **Delete**는 선택 케이블 하나만 해제한다. 드래그 중 도구막대를 숨기고 중간 확대에서도 IN/OUT·bus 번호를 읽을 수 있게 했다. 실제 앱의 양 끝 16회 방향 이동·재연결·IN 시작 분기·해제·Undo·저장 복원을 확인했다. [케이블 드래그 검증](qa/ports-cable-review.md) · [직접 연결 UI 검증](qa/ports-ui-review.md).

개발 브랜치의 **K / Shift K**는 케이블, **P / Shift P**는 논리 포트를 순환한다. 선택 케이블에서 **Tab**으로 OUT/IN을 고르고 **좌우 방향키**로 둘레 위치를 바꾼다. **Return / L**은 해당 연결이나 포트가 지정된 편집기를 바로 연다. 편집기에서는 **Tab / Shift Tab**으로 항목을 이동하고, 닫힌 포트 선택 상자에서 **위아래 방향키**로 값을 바꾸고 적용 버튼에서 **Return**을 누른다. 위치 이동은 음악을 바꾸지 않으며 포트 선택 상태의 Delete는 서클을 삭제하지 않는다. [키보드·접근성 검증과 범위](qa/ports-keyboard-review.md).

케이블 모션은 **각 OUT의 실제 신호와 라우터 matrix**를 따른다. 조용한 출력에 다른 bus의 신호가 표시되던 문제와 독립 역상 출력의 노드 표시가 상쇄되던 문제를 수정했다. 시각화 전후 PCM 일치, 접힌 그룹·반복 섹션·MIDI·sidechain을 포함한 전체 Swift **190개**와 release build를 통과했다. 전용 QA 앱에서 번갈아 재생되는 두 출력의 케이블을 확인하고 **30.755초 H.264/AAC 영상**을 저장했다. 최소 너비·밀집 배치·시간 손잡이 간섭 전체 조합, 실제 VoiceOver 발화와 앱 통합은 남아 있다. [출력별 신호 검증](qa/ports-playback-review.md) · [다중 bus 검증](qa/ports-bus-review.md) · [후속 구현 단계](docs/35-port-foundation-plan.md).

개발 브랜치에는 **포트 MCP 도구 5개**를 추가했다. AI가 실제 IN/OUT·독립 bus를 조회하고 연결·재연결·해제·8방향 배치를 직접 편집한다. 음악/배치 revision 충돌을 함께 검사하며 GUI와 같은 Undo를 사용한다. 최소화 상태의 실제 편집·저장/재열기와 앱의 ⌘Z 복원을 확인했다. [포트 MCP 사용법](mcp/README.md#명시적-포트-편집-개발-브랜치) · [D1 검증과 제한](qa/ports-mcp-review.md). 이 기능은 개발 QA 앱에 있으며 사용 앱은 아직 기존 버전이다.

개발 브랜치의 그룹은 **연결 / L → 내부 포트 검색 → 포트 노출**로 IN/OUT을 직접 만들 수 있다. 그룹을 펼치지 않고 이름 변경·연결·노출 해제를 수행하며, 노출 해제는 기존 음악 케이블을 유지한다. 접힌 그룹도 실제 이름을 가진 포트와 주변 연결을 표시한다. 연결 적용 버튼을 편집기 상단으로 옮겼고 키보드만으로 바로 연결할 수 있다. 그룹 포트 설정·해제와 녹음을 합친 MCP는 총 22개 도구를 제공한다. [그룹 포트 사용법](docs/36-group-ports.md) · [D2 검증과 남은 범위](qa/ports-group-review.md).

현재 로컬 앱은 **0.19.0**이다. [써클러 앱](dist/써클러.app)을 열어 사용한다. 기존 실행 중인 앱은 저장하고 **⌘Q로 종료한 뒤 다시 열어야** 새 버전이 실행된다. 이전 앱은 `dist/archive/`에 보관한다. [0.19 검증·제한](qa/0.19-review.md) · [향후 상세 개발 계획](docs/25-development-roadmap.md).

0.20 소스에는 녹음 장치의 비동기 시작·취소·실패 복구, 직접 녹음 버튼·⌥⌘R, 입력 상태와 MCP `circlr_record`를 구현했다. 실제 검증 앱에서 프로젝트 재열기·녹음 버튼·단축키 안내를 확인하고, 어둡게 묻히던 선택 오디오 이동 메뉴의 글자와 접근성 표시를 개선했다. 실제 입력 검증이 남아 사용 앱은 교체하지 않았다. 오프라인 Swift 160개와 추가 녹음 왕복 검사 1개, Python 23개가 통과했다. [0.20 검증 현황과 남은 조건](qa/0.20-review.md).

빈 공간 우클릭과 **A**로 서클을 만들고, **⇧⌘P**로 명령과 서클을 검색한다. **⌘/**에서 단축키를 확인한다. **⇧⌘R**은 음악과 캔버스의 MP4 녹화다. [키보드·영상·엔진 2 사용법](docs/26-canvas-keyboard-and-recording.md).

**작업 이동 / ⌘J**에서 섹션·트랙을 검색해 MIDI·오디오·음색·이펙트·출력으로 바로 들어간다. 편집기 상단의 트랙 경로와 **⌘1 / ⌘2 / ⌘3**은 같은 트랙의 연주 / 음색 / 이펙트를 전환한다. 작은 서클의 이름도 클릭·더블클릭할 수 있다. 신스는 두 열로 배치하며 편집 영역은 상단 조작과 콘솔을 피한다. [탐색·가독성 설계](docs/30-ui-navigation-plan.md).

**⌘4 / MIDI 편집의 스텝**으로 드럼·신스를 16칸 페이지에 입력한다. 드럼은 실제 노트·sample mapping의 행을, 신스는 음정 행을 사용한다. 방향키로 선택하고 Return으로 켜기·끄기, Delete로 삭제, ⌥ 클릭으로 기존 노트를 선택한다. Tab으로 시작·길이·세기 필드에 이동한다. 페이지 복제·비우기와 1/4–1/32·셋잇단 분할을 지원하며, 분할을 바꿔도 기존 노트는 유지된다. 음색 편집과 재열기 뒤에도 스텝 모드를 유지한다. [기본 DAW 확장 계획](docs/31-daw-basics-plan.md).

**⌥⌘I / MIDI 파일 가져오기**는 format 0/1의 노트 연주를 같은 캔버스에서 확인하고 새 MIDI 서클에 넣는다. 트랙을 선택하고 필요한 이번 섹션의 길이만 늘릴 수 있다. 파일 템포·박자·CC·페달·피치 벤드는 적용하지 않고 현재 섹션의 음악 설정을 사용한다.

노트는 **⇧클릭**으로 선택을 더하고, 편집기에 키보드 포커스가 있을 때 **⌘A**로 전체 선택한다. **Q**는 박자 맞춤, **⌘D**는 선택 구간 바로 뒤 복제다. 선택 노트 아래의 명령으로 분할·강도·음정/시간 이동·삭제를 바로 조작한다. 궤도·피아노 롤의 방향키는 다중 선택도 함께 이동한다. 스텝의 방향키는 셀을 이동하며, 이조는 **이동** 메뉴를 사용한다. 각 작업은 한 번의 Undo로 복원한다.

오디오는 파형 클릭 또는 **분할 위치 초 → 분할 / ⌘T**, **복제 / ⌘D**로 편집한다. 페이드 인·아웃과 음소거·삭제를 같은 캔버스에서 조작한다. 분할 전후 원본과 소리를 보존하며, 바운스 원본 복원은 관련 조각 전체를 함께 처리한다. 텍스트 입력 중에는 음악을 분할·복제하지 않는다. [오디오 편집의 시간 의미와 사용법](docs/32-audio-editing.md).

오디오 파형 위 **휠**은 포인터의 시간을 유지하며 확대·축소하고 **가로 휠 / ⇧휠**은 원본 시간을 옮긴다. 파형에 포커스를 두고 **−/+**, **Page Up/Down**, **Home/End**, **0 전체 / F 선택 / C 커서 보기**로 탐색한다. 기존 **←→ 시작 트림 / ⌥←→ 끝 트림**은 유지한다.

**오토메이션 / ⌘5**로 선택 서클의 볼륨·팬 곡선을 연다. 궤도는 각도=시간·반경=값, 자유 배치는 가로=시간·세로=값이다. 점을 클릭·드래그하거나 숫자로 입력하고 선형/유지 구간과 적용 여부를 바꾼다. Return은 점 추가, 대괄호는 점 선택, 방향키는 시간·값 이동, Delete는 점 삭제다. MIDI에서는 같은 트랙의 악기 오토메이션으로 이동한다. [오토메이션 사용법과 시간 계약](docs/33-automation-plan.md).

민트색 이중 궤도와 위성 서클로 구성한 앱 아이콘을 적용했다. macOS 26용 Icon Composer 리소스와 이전 macOS용 ICNS를 함께 포함한다. [아이콘 원본·생성 기록·빌드 방법](Resources/Brand/README.md) · [0.10.1 아이콘 검증](qa/0.10.1-icon-review.md).

## 재생 비주얼라이저와 팔로우

재생하면 서클의 외곽과 궤도 잔상이 신호 세기에 반응하고, 연결선의 작은 빛이 OUT에서 IN으로 흐른다. 실제 재생 sample time과 준비된 오디오 envelope, MIDI 노트의 velocity를 사용한다. 연결선의 이동 속도는 방향을 보여주는 시각 표현이며 플러그인 처리 지연을 측정한 값은 아니다.

상단 **재생 팔로우**는 기본으로 켜져 있다. 현재 섹션과 마디를 표시하고 다음 섹션으로 넘어갈 때 화면이 부드럽게 따라간다. 콘솔을 접거나 펼쳐도 남은 작업 영역에 맞춘다. **휠·드래그·선택·편집을 시작하면 팔로우가 일시 중지**되며, **팔로우 재개**를 누르면 현재 섹션으로 돌아온다. 팔로우는 음악과 편집 선택을 바꾸지 않는다.

일반 재생에서 최소화하면 음악은 계속 재생하고 화면 애니메이션 작업은 멈춘다. 영상 녹화 중에는 캡처를 유지하는 경로를 사용한다. 정지하면 신호 표시가 사라진다. 재생 중 음악을 수정하면 이전 그래프의 표시를 중단하고 다시 재생해야 반영된다는 안내를 띄운다. macOS의 동작 줄이기를 따르는 경로도 구현했다. [시간·신호·카메라 계약](docs/23-playback-visualizer.md).

## 에이전트와 음악 제작

`$circlr-studio` 전용 스킬과 프로듀서·편곡자·연주자·비트메이커·탑라이너·사운드 디자이너·믹싱·마스터링 에이전트를 설치했다. 메인 세션이 편집을 통합하며 전문 역할은 읽기 전용 MCP로 분석·제안한다. [사용법과 역할 계약](docs/24-music-agent-kit.md). 0.19 앱 번들의 `Contents/Resources/Codex`에도 설치 가능한 키트가 들어 있다.

로컬 stdio MCP와 현재 사용자 전용 Unix socket을 통해 실행 중인 앱의 프로젝트를 읽고 편집한다. **화면을 클릭하지 않고, 창을 최소화한 상태에서도** MIDI 생성·악기/이펙트 편집·바운스·WAV export·저장이 가능하다. [연결 설정과 도구](mcp/README.md) · [명령 아키텍처](docs/17-agent-interface.md).

하단의 접이식 콘솔은 실제 실행 로그와 작업 상태를 보여준다. Ctrl+`로 펼치고 접는다. `help`, `state`, `play`, `stop`, `save`, `undo`를 입력할 수 있다. MIDI 서클을 선택하고 `midi arpeggio`, 트랙을 선택하고 `synth pluck`, `bounce`를 실행할 수도 있다. 외부 AI 에이전트를 연결하는 구조이며 앱 자체에 LLM 계정이나 모델을 자동 설치하지 않는다.

향후 사용자의 ChatGPT/Codex 계정으로 앱 안에서 대화하며 편집하는 [Codex 콘솔 구현 계획](docs/20-codex-account-console-plan.md)을 마련했다. 공식 App Server와 기존 MCP를 연결하며 로그인·작업 중단·대화 복원·앱 단독 배포의 완료 조건을 정의한다. 현재 0.19.0에는 외부 MCP 연결이 구현되어 있고, 앱 안의 계정 대화는 계획 단계다.

내장 synth 10종(EP·오르간·브라스·스트링 포함), 음정별 sample mapping, MIDI 패턴 생성·파일 저장과 이펙트 포함 오디오 바운스를 추가했다. 바운스는 원본 MIDI·악기·이펙트를 보존하고 출력 입력을 오디오로 교체한다. 생성된 오디오 서클의 **원본 복원** 또는 Undo로 돌아갈 수 있다.

[f0r h3r v4 프로젝트·MIDI·WAV와 튜토리얼](music/f0r-h3r/v4/README.md)은 120 BPM, 96마디·15트랙의 3분 14초 클럽 편곡이다. 정박 킥·2/4박 스네어·엇박 하이햇과 16마디 intro/outro를 사용하며, 배포 미디어는 CC0 FreePats bank다. [신스 엔진 3과 기본 음색 10종](docs/29-synth-engine3.md)은 파형 기음 상쇄를 줄이고 ensemble·velocity 배음과 새 악기를 추가한다. 기존 엔진 1/2와 v1–v3는 보존한다. [Splice 정책·공식 AU 연동 조사](docs/27-splice-licensing-and-integration.md).

## 새 캔버스 사용

1. 처음에는 빈 곡 하나를 담은 앨범으로 시작한다. **서클 추가 → 곡 서클**로 앨범에 곡을 더한다. 선택한 곡에서 **악장 서클**을 추가하면 기존 섹션을 첫 악장으로 묶고 새 악장을 만든다.
2. 곡·악장을 선택하고 **섹션 서클 / ⌘K**로 섹션을 만든다. 섹션 안에는 실제 MIDI 데이터와 연결된 MIDI·악기·믹스·출력 서클이 있다. 추가 MIDI는 **MIDI 서클**, 오디오는 **오디오 가져오기 / ⌘I**로 넣는다.
3. **휠 위로 확대, 아래로 축소**한다. 두 번 클릭하면 선택 서클에 맞춰 확대한다. 음악 서클이 충분히 커지면 **같은 캔버스 안에** 편집기가 나타난다. 별도 MIDI·오디오 편집 창을 만들지 않는다.
4. MIDI 원호의 빈 곳에 노트를 입력하고 각도로 시간, 반경으로 음높이, 끝 점으로 길이를 조절한다. 오디오 파형의 양 끝을 드래그해 원본 구간을 자르고 시작 박·볼륨·템포 추종을 편집한다. 이펙터 서클은 실제 처리 경로에 삽입되며 확대해서 파라미터를 편집한다.
5. 오른쪽 포트를 같은 그룹의 호환되는 서클에 끌어 연결한다. MIDI는 악기 입력, 오디오는 믹스·효과·출력에 연결한다. 곡·악장끼리 연결하면 같은 부모 안에서 재생 순서를 바꾼다. 궤도의 흰색 시간 손잡이는 소스 시작 또는 형제 순서를 바꾼다. 공간 이동은 자유 배치 모드에서 사용한다.
6. 상단 경로 또는 **Esc**로 상위 서클에 돌아온다. **F**는 앨범 전체, **H / 가운데 버튼**은 화면 이동, **V**는 선택 도구다. 일반 휠은 편집기 위에서도 캔버스를 확대한다. **⇧ 휠**은 편집기 안에서 스크롤하거나 캔버스를 이동한다.
7. 상단 BPM 또는 선택 서클의 설정 버튼에서 템포·박자·스케일·박 분할/강세·리듬 패턴을 설정한다. 각 항목은 부모 상속·앨범 글로벌·개별을 구분한다. 음악 설정은 적용 버튼으로 반영한다. 공유 원본과 이번 사용의 변형은 별도로 보존한다.
8. Shift 클릭 또는 우클릭의 선택 추가로 여러 서클을 고른다. **⌘G**는 원형 그룹, 그리드 메뉴는 정렬·동일 간격·접기/펼치기다. 그룹 이동은 내부 배치와 음악 연결을 함께 유지한다.
9. **앨범 사운드** 안에서 전역 이펙터·버스·마스터를 편집한다. 섹션 우클릭 또는 설정에서 연결 해제·재생 경로·전환을 편집한다.
10. **재생**과 **WAV 내보내기 / ⌘E**는 앨범의 모든 곡·악장을 순서대로 처리한다. 선택 섹션 듣기는 해당 섹션만 처리한다. `.circlr` 저장은 앨범 구조·노트·연결·미디어와 마지막 확대 위치를 함께 보관한다.

빨간 닫기 버튼과 **⌘W**는 최소화, **⌘Q**는 종료하는 동작을 유지한다. 닫기 후 앱 실행 유지와 ⌘Q 종료를 검증했다.

## 구조와 저장

- `CirclrCore`: Album/Composition 소유권, 섹션 원본·변형, typed music graph, 계층별 음악 설정과 절대 시간 실행 계획.
- `CirclrAudio`: 실제 MIDI 악기 렌더링, 오디오 구간·반복·tempo 추종, 노드별 DSP/Audio Unit 처리, 앨범 playback 및 WAV/stem export.
- `CirclrApp`: AppKit 자유 캔버스와 확대 카메라, 서클 안 SwiftUI/AppKit 편집기, 하나의 문서 상태와 undo.
- `CirclrRealtime`: 녹음 ring buffer와 내장 synth의 native MIDI queue·voice render. `mcp`: Python stdio adapter. `Tools/CirclrStudioTool`: 같은 Core/Audio로 곡을 만들고 렌더하는 CLI.
- 기존 version 1 곡은 메모리에서 version 2 앨범으로 확장한다. 파일을 바꾸려면 새 위치에 저장한다. 원본 미디어·원본/변형·편곡안과 기존 효과 순서를 유지한다.

[새 계층 아키텍처](docs/15-hierarchy-canvas-architecture.md)에 포함·시간·신호·편집의 경계를 기록했다. 전체 설계와 구현 계획은 [기본 아키텍처](docs/04-architecture.md) 및 [앨범 구현 계획](docs/14-album-circle-implementation.md)을 참조한다.

## 검증과 실행 경계

macOS 14 이상 / Swift·AppKit·SwiftUI·AVAudioEngine·CoreMIDI 기반이다. 현재 native 실행 환경은 Apple Silicon Mac이다.

앱 패키징에는 Xcode 26 이상과 `actool`, `iconutil`, `sips`가 필요하다. `build-app.sh`는 저장된 PNG에서 아이콘을 재생성하고 배포 전용 `.build/app-release` 경로에서 앱을 빌드한다. 이미지 생성 서비스 접속은 빌드에 필요하지 않다.

```sh
./scripts/build-app.sh
./scripts/swift-local.sh test
python3 -m unittest discover -s mcp -p 'test_*.py'
```

0.19의 오프라인 Swift **148개**, Python **22개**가 통과했다. 궤도·선형 점 편집, native gain/pan/hold WAV, bypass·Undo·저장 복원은 [0.19 QA](qa/0.19-review.md)에 기록했다. 실제 마이크·Scarlett 재생, plugin parameter 자동화는 후속 범위다.

0.18의 오프라인 Swift **138개**, Python **21개**가 통과했다. Native 분할 전후 PCM 동일, 페이드 감쇠, 복제·연속 키보드·텍스트 입력 보호·Undo·저장 복원을 [0.18 QA](qa/0.18-review.md)에 기록했다. 실제 마이크·Scarlett 재생 검증은 남아 있다.

0.17의 오프라인 Swift **129개**, Python **20개**가 통과했다. 실제 MIDI 가져오기·일괄 편집·Undo·재열기·MCP·바운스는 [0.17 QA](qa/0.17-review.md)에 기록했다. 녹음 권한 대기 취소와 늦은 응답의 시작 차단은 Core 테스트로 검사했으며 실제 마이크 녹음 검증과 구분한다.

0.16의 오프라인 Swift **119개**, Python **19개**가 통과했다. 실제 앱의 신스·드럼 스텝 입력, 키보드, 페이지 복제, 분할 전환, Undo·저장 복원, MCP·WAV·바운스 결과는 [0.16 QA](qa/0.16-review.md)에 기록했다. 이전 검색·탐색 검증은 [0.15 QA](qa/0.15-review.md)에 있다.

0.13의 오프라인 Swift **102개**, Python **17개** 테스트를 통과했다. 실제 QA 앱에서 우클릭 생성·명령 검색·두 배치 방식의 MIDI 단축키·오디오 trim·닫기 최소화와 f0r h3r v2 바운스/export를 확인했다. 앱 export는 제작 WAV와 정확히 일치하며 바운스 전후 차이는 24-bit PCM 최대 1단계다. 최종 Scarlett 출력 연결은 시간 초과로 실제 재생·캔버스 MP4 검증이 남았다. 코덱 테스트 통과와 실제 녹화 성공을 구분한다. [0.13 검증·장치 제한](qa/0.13-review.md).

0.11에서는 실제 재생 위치·신호, 자동 팔로우·수동 탐색 후 재개, 최소화·복원, 재생 중 편집 충돌과 정지를 검증했다. 시각화 사용 전후 PCM은 테스트 fixture에서 정확히 일치했다. [0.11 검증과 화면 증거](qa/0.11-review.md).

0.10의 native 앱에서 MCP handshake와 14개 도구, 최소화 상태의 프로젝트 열기·MIDI 편집·Undo·바운스·WAV export·저장, 중복 요청·오래된 revision·잘못된 batch·취소·작업 중 문서 변경을 검증했다. 당시 101.31초 전체 곡의 바운스 전후 차이는 24-bit PCM 최대 1단계였다. [실제 MCP 증거](qa/generated/0.10-final/0.9-mcp-native.json) · [PCM 비교](qa/generated/0.10-final/bounce-audio-comparison.json). 기존 계층 캔버스의 native 검증은 [0.8 기록](qa/hierarchy-native-review.md)에 있다.

현재 오디오는 준비된 PCM을 재생하는 방식이다. 연속 실시간 그래프 엔진, plugin crash 격리/PDC, 모든 외부 장치·플러그인 호환성을 검증한 제품이라는 의미는 아니다. WAV는 48 kHz stereo / 24-bit, 기본 잔향 2초다. 기존 0.7.1 배포본 사용 방법은 [이전 안내](README-0.7.1.md)에 보관했다.

기본 캔버스는 **12시부터 시계 방향으로 진행하는 궤도 타임라인**이다. 앨범·곡·악장·섹션의 실제 실행 시간과 반복·전환을 사용하며, 같은 캔버스의 원호형 MIDI 편집과 원형 파형 trim을 지원한다. 기존 자유 배치 좌표는 보존되며 그리드 메뉴에서 모드를 바꾼다. [시간 의미와 조작법](docs/19-orbit-timeline.md)을 참고한다. 최초 파일 접근의 macOS 권한은 사용자가 허용해야 한다. 일반 `.mcp.json` 예시를 작성한 것만으로 이미 실행 중인 에이전트의 도구 목록이 자동 등록되지는 않는다.
