# 써클러 개발 방향과 실행 계획

갱신: 2026-09-10. 계획 시작 기준: 0.11 native 앱, 0.12 음악 에이전트 키트 소스. 기존 출고 표기는 0.19.0이며 실행 중 사용자 앱의 별도 관측 버전은0.14다. 개발 검증 후보는 0.20.0 build 95이다. 목표는 송폼 중심의 전문 음악 제작을 먼저 완성하고, 이를 아티스트의 작품·세계관 관리로 확장하는 것이다.

## 현재 검증 완료 — build95 탐색 밀도

현재 target과 같은 단일 버튼을 생략하고 header 복귀·다중 검색·⌘1/⌘3을 유지했다. parse·Release40.30초와 실제 router/header·audio2/effect2/source3 검색·MIDI 선택/복귀를 확인했다. revision62 음악 불변·saved/reopened 전체 manifest strict 동일이며 QA10개 상태·AX12개·자산2개·physical0 대조도 통과했다. MIDI/effect는 use-only 안내 상태의 탐색 검증에 한정한다. [계약](110-route-density.md) · [QA](../qa/route-density-review.md).

다음 구현 slice는 offline AU effect 실행 격리다. renderer의 `AudioUnitHost.process`가 앱 안에서 plugin을 호출하므로 hang/crash가 앱에 영향을 줄 수 있다. effect 처리만 child worker에 descriptor/state/PCM으로 전달하고 세션별 취소·deadline·원자적 결과 적용·임시 파일 정리를 정의한다. fake hang/crash/truncated/nonfinite/늦은 완료와 Apple AU의 offline PCM 비교를 검증한다. 현재는 미구현 계획이며 물리 출력 worker와 별개다. instrument·plugin UI·실시간 처리는 후속 범위다.

## 현재 검증 완료 — build94 콘솔 높이

로그 높이를 세션40–180px·기본122px로 조절한다. 초기 입력창 단축키 실패를 수정한 최종 parse·Release40.59초와 실제 ⌃⌘1/2/3·drag clamp·접힘/펼침·편집기 왕복·wheel·state 명령을 확인했다. music revision62·saved/reopened strict manifest와 같은 세션 높이40을 유지했다. QA18개 상태·최종AX10개·자산2개·physical0 대조와 consoleHeightReduction82를 확인했다. [계약](109-console-height.md) · [QA](../qa/console-height-review.md).

Core 변경·신규 unit 테스트는 없다. 실행 중 job 취소 버튼은 이번 native 미검증이며 앱 재시작 후 기본122px로 돌아간다. 프로젝트 재열기의 같은 세션 높이 유지와 구분한다.

route bar 중복 버튼 과제의 실제 확인 범위는 위 build95에 기록한다.

## 현재 검증 완료 — build93 음악 그래프 편집 범위

scope 전용 snapshot·원본 읽기·대상 guard·use-only 안내와 범위 선택을 구현했다. 관련31개 실패0·최종 Release45.48초와 실제 원본 이름 변경·scope/target 초안 처리·group router 생성·Undo를 확인했다. revision62 saved/reopened manifest는 strict 동일하며 QA18개 상태·AX9개·자산2개·physical0 대조도 통과했다. [계약](108-music-graph-edit-scope.md) · [QA](../qa/music-scope-review.md).

baseline92는 ID collision의 전체 실패·revision54 불변으로 확인한 경로이며 원본 오염 발생으로 표현하지 않는다. 실제 AU 비동기 plugin은 미검증으로 코드 guard 확인과 구분한다. 사용자 앱·물리 I/O 조건을 유지한다.

콘솔 로그 높이 과제의 최종 관측은 위 build94에 기록한다. 기존 물리 출력 문제와 별도 범위다.

## 현재 검증 완료 — build92 router 경로 레벨

네 경로 dB·Tab·slider 입력과 정밀도/순서 보존·명시 대상·원본 분리·expected guard를 구현했다. Core19개·최종 Release41.35초와 실제 입력·preset 충돌 거절·Undo·작은 창/scroll1·저장 재열기를 확인했다. revision54 saved/reopened manifest는 strict 동일하며 QA baseline3개·후보25개·AX12개·자산2개·physical0 대조도 통과했다. 원본 안전성은 이번 route helper 범위이고 물리 출력0회로 사용자 앱을 보존한다. [계약](106-router-route-levels.md) · [QA](../qa/router-level-review.md).

build93의 편집 과제는 일반 `updateMusic`의 effective→original 전파 위험과 편집용 scope snapshot을 다룬다. 공유 원본 편집이 이번 사용의 effective 값을 읽어 다른 override까지 원본에 저장하는 경로를 조사하고, 원본/이번 사용의 읽기 snapshot과 명시적 쓰기 대상을 일치시킨다. 대상 필드만 반영하는 계약과 scope 전환·오래된 초안·Undo·다른 use 보존을 검증한다. `addedNodes`/`addedEdges`는 원본 유입 성공과 혼동하지 않는다. ID collision으로 전체 요청이 실패하는 경우를 별도 거절 경로로 검사한다. 이번 route helper의 안전성 확인을 일반 편집기 전체로 확대하지 않는다.

후속 I/O는 [앱별 출력 장치 계획](107-app-output-device-plan.md)의 범위와 검증 조건을 확인해 연결한다. 아직 장치 구현·정상 physical 출력 완료로 계산하지 않는다.

## 현재 검증 완료 — build91 출력 dB·router 접근

출력 볼륨을 dB로 통일하고 작은 창의 router 하단 접근·위치 복원을 수정했다. 최종 관련17개 테스트·Release20.04초와 native7개 상태·AX4개에서 mix 왕복·gain/Undo·저장 재열기 뒤 하단 위치1 유지를 확인했다. saved/reopened 전체 manifest는 strict 동일하다. QA 최종 대조와 routerScroll{x:0,y:169} 보존도 통과했다. 앞선38.99초 후보의 광범위 dB 검증·스크롤 누락 발견을 최종 위치 복원 결과와 구분한다. [계약](105-signal-level-decibels.md) · [QA](../qa/signal-level-review.md).

physical 출력0회·사용자 앱 유지로 기존 장치 출력 문제와 구분한다. 새 장치 출력 성공을 확인한 작업이 아니다.

## 현재 검증 완료 — build90 포트별 출력 도달성

공통 Core structural port reachability로 탐색 후보·선택 트랙 추론·바운스 분류를 맞췄다. router 실제 route, mute/gain0의 구조 연결, sidechain-only 제외와 lane 소유 미연결 편집 접근을 구분한다. Swift36개 실패0·Release73.47초와 실제 독립 bus별 effect 분리·MCP focus 뒤 단축키의 트랙 추론·router 교차 변경/Undo를 확인했다. QA10개 상태·AX7개·자산2개·physical0과 저장/재열기 manifest 전체 일치도 확인했다. [계약](104-port-aware-navigation.md) · [QA](../qa/port-navigation-review.md).

별도 읽기 전용 장치·클라이언트 관측을 완료했다. [장치 QA](../qa/output-device-review.md). HAL 지연 원인과 정상 출력은 미해결이며 이 탐색 수정의 완료와 합산하지 않는다.

## 현재 검증 완료 — build89 현재 트랙 단축키·출력 재대조

⌘1/⌘2/⌘3의 현재 section/track 범위0/1/multi 선택과 혼합 MIDI/audio typed union을 구현했다. parser·Release42.42초와 실제 미연결 Return·종류 전환·현재 찾기 union 해제를 포함한 탐색을 확인했다. 신규 Swift unit 테스트는 없으며 저장·재열기의 음악/선택/camera 보존과 QA13개 캡처·AX7개 대조를 통과했다. [단축키 QA](../qa/track-shortcut-review.md). [계약](103-track-shortcuts-and-output-recheck.md).

출력의 동시간 raw control2회와 서명 보존 helper2회가 모두 mixerAcquisition/entered에서 timeout했다. strict 서명 보존은 가능하지만 timeout을 해결하지 못했으며 이전 서명 가설만으로 원인을 설명할 수 없다. 원본과 정책을 유지하고 지연 중 실제 관측에 필요한 조건을 정리한다. 정상 출력·물리 I/O 출고는 미완료다. [출력 대조](../qa/output-signature-review.md).

후속 UI 과제는 포트별 출력 도달성이다. 현재 node 단위 탐색이 독립 router bus의 다른 트랙 effect도 노출할 수 있어 `BounceAssessment.membership` 재사용 또는 공통 Core endpoint 역추적으로 `StudioNavigation.outputTracks`와 `build`를 함께 맞춘다. sidechain 제외·fanout·implicit port가 검증 범위다.

별도 live stall probe2회는 mainMixer→AudioDeviceCreateIOProcID→HAL SetPropertyData→mach_msg 대기 stack을 확보했다 (`qa/generated/output-stall-build89/stall-summary.json`). 서명 대조 당시 sample 미확보와 구분하며 서버 원인·장치 identity는 미확정이다.

## 현재 상태 — build88 섹션 삽입 완료·출력 지연 진단

선택 섹션 뒤 연결을 유지하는 원자적 삽입과 출력 준비 trace를 추가했다. Audio26개·Core7개·MCP23개·kit9개·file worker16개·Release52.87초와 실제 MIDI 편집 중 명령 삽입·Undo/Redo를 확인했다. 섹션 QA22개 상태·자산2개 보존 대조도 통과했다. [섹션 QA](../qa/section-insertion-review.md). [계약](102-section-insertion-and-output-preparation.md).

raw Release 무음 helper2회는 started0.533/0.122초·자연 finished·command EOF 후 exit0으로 끝났다. 패키지 worker는 앱 host의 무음 fixture와 독립 CLI 실행 모두 각각 두 번 mixerAcquisition 진입에서 timeout했다. raw Release와 패키지 binary의 UUID·기계코드 섹션은 같고 codesign·.app 위치가 다르지만 원인은 아직 확정되지 않았다. 실제 믹서 준비6초·Space 안내와 세 번째 시작의 즉시 취소·정리를 확인했지만 host 정상 출력은 여전히 실패한다. [관측](../qa/output-preparation-native-review.md). 원본을 보존한 추가 matrix에서 패키지 byte 동일 외부 사본·재서명 raw 외부 사본이 각2회 mixerAcquisition에서 timeout하고 EOF exit0으로 정리됐다. .app 위치만으로는 설명되지 않았다. 당시 없던 동시간 raw control과 서명 보존 대조는 위 build89 결과에서 모두 실패했으므로 서명 원인을 확정하지 않는다. 독립 성공을 host 복구로 일반화하지 않으며 timeout/retry/device 정책·물리 I/O 출고 조건·사용자 앱을 유지한다.

## 현재 검증 완료 — build87 렌더 tail 정책

자동 감쇠 추정·직접0–120초·상한/미확정 안내·메모리 사전 거절과 보존 클립 실제 끝을 공통 planner에 연결했다. Audio30개·Core3개·MCP22개·kit9개·Release52.98초를 통과했다. 실제 자동74초/직접34초의 앞34초 PCM, 바운스/export의 재열기 전후 바이트 일치와 설정·사전 거절·STOP 취소를 확인했다. QA checker22개 문서 캡처·RPC 오류/취소 기록 대조도 통과했다. [계약](101-render-tail-policy.md) · [QA](../qa/render-tail-review.md).

UI running 스피너 캡처·상한120초 완료 파일·실제 AU 검증은 남아 있다. AU는 단위 metadata만 확인했다. 실제 출력0회로 사용자 앱을 유지하고 검증 앱을 종료했다. 자동 추정과 오프라인 측정은 무손실·청취·물리 I/O 출고 보장이 아니다.

## 현재 검증 완료 — build86 오디오 범위·바운스 음소거

공유 원본/이번 사용 표시와 전용 클립 복귀를 기존 줄에 통합하고 파형 높이를 유지했다. 첫 후보의 Return 무응답을 수정한 최종 Release41.19초·Audio21개와 native 범위별 트림/Undo·출력 음소거 바운스·Return 복귀·원본 복원·Undo3·재열기를 확인했다. QA checker28개 상태·자산2개·바운스1개와 WAV PCM/checksum 대조도 통과했다. 실제 출력·audition0회로 사용자 앱과 물리 I/O 출고 조건을 유지한다. [계약](100-audio-scope-and-bounce-mute.md) · [QA](../qa/audio-scope-review.md).

build87의 tail 정책은 아래 build86 재현에서 시작했다. compiled renderer에서1초 body의 끝 직전 pulse에 delay1초·feedback0.8을 적용해 tail2초와5초를 비교했다. 앞3초는 같지만 잘리는3–6초에 peak0.1024(약−19.8dBFS)·RMS0.008464가 남았다. [Python 재현](../qa/probe-bounce-tail.py) · [Swift 재현](../qa/probe-bounce-tail.swift). 이 과거 재현과 build87의 자동/직접 렌더 검증을 구분하며 실제 장치 청취 조건은 유지한다.

## 현재 검증 완료 — build85 바운스 상태·연결 복구

build84 실제 앱에서 경로 밖 복제본의 제외 안내 누락과 비활성 버튼의 help에만 있는 원인을 재현했다. build85는 typed assessment와 기존 route bar의 원인·제외 상태·연결 보기, 명령 검색의 정확한 출력 IN 이동을 구현했다. 초기 추가 행의 파형 축소는 최종 한 줄 배치로 복원했다. Core28개·AudioRouterAudio15개·최종 Release40.86초와 native 연결 해제/Undo·오토메이션 경고·오래된 명령 거절·저장 재열기를 확인했고 QA checker native20개·compact12개 상태·자산2개·재열기 manifest·source SHA 대조도 통과했다. [계약](99-bounce-visibility.md) · [QA](../qa/bounce-visibility-review.md).

이번 범위의 바운스 렌더는 미실행이며 실제 출력·audition은0회다. 기존 사용자 앱과 물리 I/O 출고 조건을 유지한다. 다음은 가져오기→편집→오토메이션→바운스 전체 도구 왕복에서 남은 작업을 실제 시나리오로 확인한다. 이번 연결 복구 검증을 전체 제작 흐름 완료로 계산하지 않는다.

## 현재 검증 완료 — build84 편곡 연결 경로 미리보기

기존 편곡안 행에 연결 순서·반복·경로 제외·오류를 표시하고 `ArrangementCompiler`의 경로 cursor를 공유했다. Swift401개 실패0·Release68.85초와 실제1020×768의 같은 이름 비교·키보드 전환·연결/순서/반복 수정 반영·Undo5·재열기를 확인했다. QA checker native15개 상태·자산2개·source SHA 대조도 통과했다. [QA](../qa/arrangement-route-review.md). 오디오 시작0회로 사용자 앱을 보존하고 검증 앱을 종료했다. 음원 유효성·재생 시간·실제 청취와 출력 출고 조건은 별도 유지한다. [계획과 계약](98-arrangement-route-preview.md).

## 직전 완료 — build83 편곡 대안의 복제·이름 변경

build83에서 편곡안 목록에 이름 변경·명명 복제를 모으고, MIDI·섹션 편집 중에도 현재 편곡 번호·이름을 표시했다. ⇧⌘N/⇧⌘D와 MCP 명시 대상 작업을 지원한다. 복제 시 서클 색상을 유지하고 공유 섹션 원본과 이번 사용 편집의 차이를 알린다.

MCP `duplicate_arrangement`·`rename_arrangement`·`select_arrangement`를 지원한다. 같은 곡/다른 곡의 MCP 복제는 재생 선택·active·selection·MIDI 편집기를 유지하고, 명시적 선택은 대상 곡과 편곡으로 포커스를 맞춘다. UI 복제는 새 편곡을 선택한다. Core30개·MCP21개·최종 Release68.50초와 실제 MCP 복제·전환·Undo 다섯 번의 음악 복원·재열기를 확인했다. UI·키보드·원안 use/graph/lanes 보존·저장 복원 검증도 완료했다. [계약](97-arrangement-workspace.md) · [QA](../qa/arrangement-workspace-review.md).

실제 A/B 청취와 출력의 간헐적 첫 연결 실패는 별도 재생 조건으로 유지한다.

## 현재 추가 요청 — 서클 색상

build81에서 종류별 색상과 사용자 지정·복원을 구현하고 검증했다. 색상/history 14개 테스트를 통과했다. 실제 메뉴·키보드·저장/재열기·패널 초기화 회귀를 확인했다. 기존 한 곡 제작 동선과 물리 오디오 출고 조건은 계속 유효하다. [색상 계약](96-circle-colors.md).

## 통합 흐름 검증 갱신

이펙트→오토메이션→바운스 산출물을 해시·PCM으로 재검증하고, build81에서 저장 프로젝트 전체 복원을 확인했다. 궤도 화면에서도 음악 데이터가 유지된다. [통합 근거와 검증 경계](../qa/automation-flow-review.md). 다음은 실제 장치 출력 재점검과 같은 곡의 편곡 대안이다.

## 현행 실행 순서 — build95 기준

build80에서 바운스 대상명과 연결 사전 검사를 통합하고 실제 UI 바운스·복원·MCP 즉시 거절을 확인했다. [QA](../qa/bounce-target-review.md). 이후 같은 곡에서 이펙트와 오토메이션을 적용한 바운스·저장/재열기는 위 통합 흐름 QA에서 확인했다. 개별 기능 검증을 한 곡 제작 완료로 계산하지 않는다.

build79에서 섹션의 오디오 가져오기가 과거 트랙을 재사용하던 기본값을 수정하고 파일 창에 목적지를 표시했다. 실제 파일→새 트랙→Undo/재열기를 확인했다. [QA](../qa/import-destination-review.md). 다음 통합 흐름은 가져온 오디오의 이펙트 연결·오토메이션·바운스다.

새 곡 제작 흐름의 첫 구간에서 생성 메뉴와 빈 드럼 입력을 개선했다. build77은 실제 MIDI 입력·생성·Undo와 저장한 스텝 편집기 복원을 검증했다. [QA](../qa/creation-interface-review.md). 다음은 같은 곡의 오디오 가져오기→연결→오토메이션→편곡→바운스 왕복이다. build78에서 MCP focus 직후 저장의 카메라 불일치를 수정하고 취소 위치·재열기까지 검증했다. [QA](../qa/save-focus-review.md).

출력 재점검: build81 무음 helper에서 실제 장치 시작·STOP·EOF·세션 교체를 확인했고, 별도 실행에서 재생 시계 0→1초·자연 종료를 확인했다. [관측 근거](../qa/output-session-review.md). 청취·입력·장치 변경·MP4 검증을 대신하지 않으며 과거 HAL 시간 초과의 원인은 여전히 미확정이다. [기존 진단](../qa/output-recheck-review.md).

build82는 이전 play의 timeout/catch가 교체 세션을 취소하지 않도록 세션 ID 확인과 취소를 같은 lock 안에서 수행한다. 외부 STOP은 유지한다. OutputWorkerProcess/Protocol 관련16개 테스트를 통과했다 (`.build/output-session-tests.log`). build82 release 빌드는 46.09초에 통과했다. 실제 native host 첫 시도는 장치 단계 timeout·didStart=false 후 idle로 복구했고, 다른 세션 재시도는 didStart=true·시계 1.1145625초 진행·STOP 후 idle을 확인했다. 간헐적 최초 시작 실패는 미해결이다. 세 번째 세션은 33.994초 진행 관측 뒤 자연 종료했다. [출력 세션 QA](../qa/output-session-review.md). build76의 timeout 후 정리·재시도·Space 취소는 해당 빌드의 [기존 QA](../qa/output-host-review.md) 범위로 유지한다. 사용자 앱 출고 조건과 입력·audition·장치 변경·영상 시계 검증은 계속 남아 있다.

이 절이 현재 우선순위다. 아래 build별 설명의 당시 ‘다음’ 문장은 개발 이력이며 새 작업 지시가 아니다. 선택 복원(build71), 선택 보기(build72), 오디오 배치(build73), 키보드 수치 입력(build74), 도움말 검색(build75)은 완료된 범위다. 모든 서클의 선택 영구 저장은 별도 설계 범위다.

1. **물리 오디오 출고 조건 재점검.** `Sources/CirclrAudio/PlaybackTransport.swift`, `PlaybackOutputConnection.swift`, `AuditionTransport.swift`의 상태와 기존 QA를 대조한다. build32의 HAL IOProc 대기는 확인됐지만 원인은 확정되지 않았다. 먼저 현재 장치/프로세스의 읽기 전용 관측과 기존 stack으로 재현 조건을 정리하고, 독립 진단 프로세스의 시간 제한·취소·정리 경계를 정의한다. 정상 출력 시작/정지/자연 종료, 입력 녹음, 장치 변경, MP4 시계 검증이 없으면 사용자 앱을 교체하지 않는다. 오프라인 렌더 성공은 실제 출력 성공으로 계산하지 않는다.
2. **한 곡 작업 흐름의 통합 사용성 검증.** 개별 편집기 통과와 별도로 섹션 생성→드럼/신스 스텝→오디오 가져오기→연결/자동화→편곡 대안→바운스/재열기의 실제 동선을 평가한다. 작은 창·긴 이름·키보드에서 숨은 상태와 되돌아가기 비용을 기록하고 재현되는 문제부터 수정한다. 별도 고정 사이드바를 추가하지 않는다.
3. **음악 품질과 아티스트 세계 확장.** f0r h3r의 단순한 클럽 리듬·악기 편성·음색과 발매 품질은 실제 청감/렌더 평가가 필요하다. 물리 I/O 신뢰성과 제작 흐름이 확보된 뒤 아티스트 프로필 및 텍스트/영상/이미지 자산의 저장·연결 계약을 구현한다. 데모 완성이나 아티스트 관리 완료를 현재 UI QA로 대신 선언하지 않는다.

build75는 검색 가능한 도움말·작업 필터와 제목 우선 명령 검색을 구현했다. [계약](89-searchable-shortcuts.md) · [검증](../qa/shortcut-search-review.md). 에이전트 재시도는 현재 세션의 thread limit으로 거절됐으므로 독립 검토는 수행되지 않았다.

## 완료 이력과 당시 후속 계획

**build74에서 파형→수치 입력 키보드 이동과 복제 공간 부족 사전 안내를 구현했다.** Swift498개·Python29개와 실제 키보드 편집7상태 [QA](../qa/audio-keyboard-review.md). 다음은 키보드 도움말/명령 검색에서 최근 편집 동선을 일관되게 안내하는 작업이다.

**build 73에서 오디오 수치8개를 두 줄로 통합하고 파형을 전체 폭으로 넓혔다.** 작은 창에서 스크롤 없이 필수 조작을 제공한다. 관련14개 테스트/native11상태의 [검증](../qa/audio-layout-review.md). 다음은 파형→수치 입력의 키보드 이동과 복제 공간 부족 사전 안내다.

**build 72에서 피아노 롤의 선택 보기/F와 작은 창의 눈금 가림을 수정했다.** 선택 전체 또는 기준 노트를 현재 배율에서 직접 찾는다. Swift496개·Python29개·native9상태의 [검증](../qa/selection-reveal-review.md). 다음은 작은 창의 오디오 정밀 작업을 화면 안에서 직접 조작하는 흐름이다.

**build 71에서 편집 선택의 복귀와 현재 작업의 저장 복원을 구현했다.** MIDI 다중 선택·원본/이번 사용·볼륨/팬별 점·오디오 원본 커서를 구분하고 삭제된 참조를 제외한다. 트림 Undo/Redo의 커서 이동도 수정했다. Swift496개·Python29개, native30상태/34화면과 전체 음악/자산 보존의 [계약](85-editor-selection-memory.md) · [QA](../qa/selection-memory-review.md).

**build 70에서 캔버스 접근성 좌표와 스텝 객체 수명을 수정했다.** 스크롤 경계의 행·셀 클릭, 검색/페이지 왕복, 피아노롤·궤도·오토메이션·서클·포트·케이블의 실제 직접 선택을 확인했다. AppKit14개·Swift491개·Python29개, native14상태/21화면과 음악/자산 보존의 [계약](84-accessibility-geometry.md) · [QA](../qa/accessibility-geometry-review.md).

**build 69에서 MIDI 선택의 직접 수치 편집을 확장했다.** 단일/다중 선택을2열로 정리하고 상단 복제/삭제를 제공한다. 다중 노트의 음정·시작·길이·세기를 상대값으로 입력하고 차이/경계/Undo를 보존한다. MCP도 같은 상대 길이·세기 편집을 지원한다. Swift491개·Python29개, native14상태/25화면의 [계약](83-midi-selection-inspector.md) · [QA](../qa/midi-inspector-review.md).

작은 창의 오디오 정밀 입력·작업 가시성은 build73에서 정리했다. 선택 노트 직접 보기는 build72에서 검증했다. build71은 세션 내 서클별 선택과 현재 작업의 문서 복원을 제공한다. 모든 방문 서클의 선택을 영구 저장하는 것은 별도 범위다. 물리 장치 입출력·VoiceOver·사용 앱 출고 조건은 계속 분리한다.

**build 68에서 페이지 안의 보기 위치를 보존한다.** 스텝 페이지/분할/행 검색·음역, 피아노롤 스크롤, 궤도 마디·음역, 오디오 확대 범위, 오토메이션 표시 길이를 세션의 서클·원본별로 기억하며 현재 서클은 재열기에서도 복원한다. Swift485개·Python28개·native19상태/43화면의 [계약](82-editor-view-position.md) · [QA](../qa/editor-position-review.md). 실제 에이전트 재할당은 thread limit으로 거절돼 순차 역할로 검증했다.

build68 당시 후속 범위였던 선택 노트·오디오 분할 커서·오토메이션 점 복귀와 좁은 편집 영역은 build71–74에서 개선했다. `MIDINoteInspector.swift`, `AudioWorkspace.swift`, `AutomationEditor.swift`에서 현재 선택과 유효 범위를 먼저 보이게 하고 필요한 조작까지 Tab 이동을 짧게 만든다. 음악 값을 임의 변경하지 않고 삭제된 선택만 해제하며, 서클/원본 전환·Undo·같은 문서 재열기·작은 창으로 확인한다. 모든 서클의 cache를 문서에 저장하는 확장은 파일 크기·삭제된 주소 정리·앱 버전 호환성을 먼저 정의한다. 실제 장치 출력·입력은 별도 출고 조건이다.

**build 67에서 저장한 작업 페이지·범위·현재 연결 작업을 복원한다.** 음악 이력과 분리한 optional 보기 정보를 사용하고, 사라진 대상은 유효한 상위 화면으로 이동하며 삭제된 재연결은 해제한다. 같은 문서 재열기 후 편집 재저장도 확인했다. Swift477개·Python28개, 최종 native18상태·20화면의 [계약](81-saved-workspace.md) · [QA](../qa/saved-workspace-review.md). 다음은 페이지 안의 스크롤·스텝 페이지/행·파형과 오토메이션의 표시 구간을 대상 변경·Undo·재열기에서 일관되게 유지하는 일이다. 물리 입출력은 별도 출고 조건이다.

**build 66에서 세션 내 연결 작업과 최근 전환 복귀를 구현했다.** 서클·원본 범위별 검색·포트·대상·8방향·재연결을 기억하며 삭제된 케이블은 안전하게 해제한다. 상단 편집/연결/전환과 본문을 같은 키보드 순서로 이동한다. Swift469개·Python28개, native27상태·상태 복원34화면·최종 키보드7화면은 [계약](80-workspace-return.md) · [QA](../qa/workspace-return-review.md)에 있다. 다음은 스크롤과 전체 작업 페이지의 재실행 복원을 음악 이력과 분리해 정의하는 일이다. 이번 임시 캐시는 세션 초기화 때 지운다. 실제 출력·입력은 별도 출고 조건이다.

**build 65에서 음악 설정의 조작 단계를 줄였다.** 마디·반복과 MIDI 시작·길이를 위로 모으고 리듬을 우선 표시한다. 기본값·앨범·개별 출처를 버튼으로 바로 바꾸며 보관값 도움말과 Tab/Shift-Tab/Return을 지원한다. Swift463개·Python28개, 실제23상태·최종21화면에서 출처 복원·직접 입력·Undo/Redo·연결 왕복·저장 재열기를 확인했다. [계약](79-music-settings-visibility.md) · [QA](../qa/music-settings-review.md). 세션 내 연결/전환 복귀는 build66에서 개선했으며 재실행 복원과 음악 편집 이력·보기 상태의 분리를 이어간다.

**build 64에서 섹션 연결·재생 분기·전환을 기존 연결 편집기로 통합했다.** 설정 첫 버튼과 L로 진입하고 동명/많은 섹션을 번호·이름·경로로 검색한다. 현재 편집 위치를 보존하는 분기 선택과 전환/재연결/해제를 지원한다. Swift463개·Python28개, 실제 27상태/22화면·저장 복원은 [계약](78-section-connection-workspace.md) · [QA](../qa/section-connection-review.md)에 있다. 다음은 `MusicContextEditor.swift`의 작은 창 가시성과 `InlineEditorHeader.swift`의 연결↔전환↔설정 복귀다. 출처/유효값·개별 값 복원·항목별 Undo를 유지하며 반복/길이/리듬까지 불필요한 스크롤 없이 접근하는 구성을 먼저 정한다. 재열기 시 페이지·검색·임시 포트 선택의 복원 범위는 음악 이력과 분리한 계약으로 다룬다. 실제 출력·입력은 별도 출고 조건이다.

**build 63에서 편곡안의 설정 깊이와 긴 메뉴를 줄였다.** 곡·악장 버튼·설정 첫 항목·⌥⌘J·명령 검색으로 열고 순번·이름·섹션 수·현재 재생 선택을 표시한다. 음악/편집 위치/Undo를 보존하며, 다른 소유와 오래된 요청을 막는다. Swift457개·Python28개, 실제 2곡/67편곡·26상태·24화면과 저장 복원은 [계약](77-arrangement-search.md) · [QA](../qa/arrangement-search-review.md)에 있다. 섹션 연결·분기·전환의 통합은 build64에서 구현·검증했다. 음악 설정의 스크롤 깊이와 물리 I/O 조건은 남아 있다.

**build 62에서 실제 음색 catalog를 읽기 전용 MCP와 전문 에이전트에 연결했다.** GUI와 같은 검색·안정된 ID·정확한 적용 주소·페이지/목록 변경 감지와 runtime capability를 제공한다. Swift 451개·Python 28개, 실제 stdio/최소화/재열기 3회와 편집 보존은 [계약](76-agent-sound-catalog.md) · [QA](../qa/agent-sounds-review.md)에 있다. 편곡안 직접 검색은 build63에서 구현·검증했다.

**build 61에서 Sound Bank의 실제 음색 이름·변형 뱅크·드럼 킷을 검색한다.** 한글 계열과 정확한 표시 번호 #1–128을 지원하고, 저장·로더의 program/MSB/LSB 주소를 일치시켰다. 적용 범위·현재 선택·충돌 안내의 높이 압축도 수정했다. Swift 445개·Python 26개, native 16상태/18화면과 최종 패키지는 [계약](75-sound-bank-program-search.md) · [QA](../qa/sound-bank-search-review.md)에 있다. 읽기 전용 MCP catalog는 build 62에서 완료했다. 편곡안 검색은 build63에서 개선했으며 물리 장치 출력·실제 입력은 아래 별도 출고 조건이다.

**build 60에서 음색·Audio Unit 선택을 직접 검색으로 합쳤다.** 내장 신스 10개와 실제 설치 목록을 이름/제조사로 찾으며 같은 음색의 사용자 설정을 보존한다. 서클/전역 AU 검색, 오래된 요청 차단, 명령·키보드 조작과 저장 복원을 검증했다. Swift 437개·Python 26개·native 23상태/20화면의 [계약](74-sound-selection-search.md) · [QA](../qa/sound-selection-review.md). Sound Bank 프로그램 이름·계열과 번호 기준은 build 61에서 개선했다. 편곡안의 긴 메뉴는 build63에서 검색으로 전환했다.

**build 59에서 작업 검색을 실제 서클로 연결했다.** 검색된 이펙트의 Return이 MIDI로 가던 흐름을 바꾸고 빈 섹션·종류 필터·명시적 번호·현재 위치 찾기·다중 역할 검색을 제공한다. 검색 전후 음악 이력·그룹 상태·다른 사용을 유지하며 외부 이름 변경에 목록이 갱신된다. Swift 429개·Python 26개·최종 검색 6개, 13섹션·137대상의 native 근거는 [계약](73-direct-work-navigation.md) · [QA](../qa/direct-work-navigation-review.md)에 있다. 음색·Audio Unit은 build 60, Sound Bank 세부 선택은 build 61에서 개선했다. 편곡안의 긴 메뉴는 build63에서 개선했다.

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

현재 전달 조건은 기능별로 구분한다. UI·편집 개선은 build 74 QA 앱에서 직접 검토할 수 있다. 사용 중인 0.19 앱을 교체하려면 우선 같은 Mac에서 출력 연결→실제 재생/정지→재시작과 기존 곡/MP4 회귀를 끝내야 한다. 녹음은 별도 허용이 필요한 실제 입력·취소·테이크 저장 회귀가 남았다. VoiceOver와 밀집 연결 조작은 전역의 모든 조합이라는 무한 조건 대신 MIDI/audio/sidechain/flow, 접힌 그룹, 긴 이름, 작은 창의 대표 경로를 명시한 검사표로 좁혀 수행한다. 과거 QA 수치를 새 빌드의 전체 기능 승인으로 합산하지 않는다.

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
