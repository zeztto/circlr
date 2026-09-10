# 현행 개발 계획

기준: 2026-09-11, integration-worktree의 build120 소스(`b06c4a9`)에서 시작해 build127의 소스·검증 기록을 기준으로 build150 검증 결과까지 반영했다. 이 문서는 다음 실행과 완료 판단을 위한 계획이며 [누적 로드맵](25-development-roadmap.md)의 과거 검증 결과를 새로 수행한 검사로 바꾸지 않는다. 전체 DAW·음악 품질·접근성은 아직 완료되지 않았다.

## 제품의 완료 방향

써클러는 송라이터와 편곡자가 한 화면에서 곡의 구성을 만들고 소리까지 완성하는 도구다. 서클은 시간·마디·반복을 가진 궤도이고, 섹션 그룹 안의 MIDI·오디오·악기·이펙터 서클은 다중 IN/OUT으로 연결된다. 자유 배치와 그리드 정렬은 음악의 시간·연결 의미를 임의로 바꾸지 않는다. 전역과 서클별 템포·스케일·박자, 리듬 기준과 실제 공유 리듬 패턴을 구분한다.

단일 다크 캔버스, 필요 위치의 편집, 휠 확대·축소, 키보드 접근, 종류별 기본색과 사용자색을 유지한다. 고정 좌우·하단 편집 패널을 늘리는 방식으로 깊이를 해결하지 않는다. 사용자가 요청한 하단 에이전트 콘솔은 작업 로그와 대화의 영역이며 음악 편집을 별도 창으로 분산시키는 근거가 아니다. GUI·키보드·MCP는 같은 명령·revision·Undo를 사용해야 한다.

## 현재 근거와 한계

| 영역 | 현재 확인 가능한 구현·기록 | 아직 증명하지 못한 것 |
|---|---|---|
| 악기 미리 듣기 | 기본 `AuditionTransport`가 `WorkerAuditionBackend`를 사용하며 service에서 native backend 생성. build118 mock lifecycle·Release 패키징 기록 | 실제 synth/sampler/AU의 소리·latency·note-off·장치 복구. 프로세스 격리는 HAL 정상화 증거가 아님 |
| 편집 접근 | build149 높이240미만·폭600..<800의 plot/controls 배치·wheel·draft resize 검증([계획](172-automation-guidance.md)).  build148 신스 수치→같은 범위 곡선 진입·초안 확정/오류 보호 검증, 최종 감사 완료([계획](171-synth-automation-shortcuts.md)).  build146 낮은 오디오 화면의 첫4수치·파형·action 및 입력/Undo 검증, data 감사 PASS_DATA_ONLY·UI 감사 PASS_WITH_SCOPE_LIMITS([계획](168-audio-compact-layout.md)).  build145 좁은 트랙 경로 배치·역할 탐색 검증, data 감사 PASS_DATA_ONLY·UI 감사 PASS_WITH_SCOPE_LIMITS([계획](167-track-route-density.md)).  build144 공유 오디오 최초 수치 4개·파형/작업 동시 표시와 Tab·Undo/Redo·재열기 검증([계획](166-shared-audio-editor-density.md)).  build143 일반·공유 오디오 history의 조건부 파형/focus 복귀 및 다른 탐색 유지 검증([계획](165-audio-edit-history-return.md)).  build142 가져오기 대상/트랙 가시성·새 MIDI 이번 use piano 진입·오디오 action 접근 및 native import/split 검증([계획](164-import-and-audio-workflow.md)).  build141 공통 요청·창 활성화 재시도 및 두 출발 rapid 음악 불변 검증([계획](163-editor-focus-intent.md)).  build140 MIDI·오디오 진입 포커스 부분 개선 검증, 당시 빠른 모드 전환 async focus 경쟁은 위 build141에서 후속 검증([계획](162-editor-navigation-focus.md)).  build139 서클별 첫 방문·재방문·명시적 스텝 진입과 invalid draft 탐색 보호·r166 재시작 검증([계획](161-circle-editor-memory.md)).  build138 섹션 설정↔원래 child 편집 복귀·앨범 대상 표시, 정상 변경/오류·삭제/길이 축소·r166 재시작 검증([기록](160-section-settings-return.md)).  build137 섹션 길이 출처·복귀와 4자리 가시성, 4096/4097 경계·r156 재시작 검증 완료.  build116 공유 리듬 오디오, build117 오디오 수치 접근, build119 신스 포커스 노출, build120 콘솔 설정 복원. build136 네 MIDI 모드의 직접 파일 작업·수치 확정·취소 복귀·작은 창 배치 및 Core 13개 검증 | 한 곡 전체의 연속 사용성, 모든 폼·최소 높이·VoiceOver·IME 조합 |
| 전자음악 편집 | 스텝·노트 편집·비파괴 오디오 편집·gain/pan automation. build129 내장 신스 cutoff의 GUI/MCP·PCM·바운스/복원, build131 MIDI tempo map의 이번 use 적용·해제·오프라인 출력·저장/재열기 검증. build133–135 내장 신스 pitch bend 렌더·SMF 가져오기·GUI/MCP 편집·내보내기 왕복 검증 | CC/페달, pitch bend의 모든 backend 지원, cutoff 외 신스 파라미터·plugin 자동화, 실시간 write/touch/latch, comping/time warp. 실제 연주·청취는 별도 |
| 입출력·영상 | 출력 helper, 녹음 상태·파일 처리, `CanvasMovieWriter`의 H.264/AAC·PCM timestamp 경로 | 정상 장치에서의 녹음→편집→재생, 실제 출력과 영상 동기·최소화/복원 |
| AI·아티스트 | 로컬 socket/MCP, revision 검증·실제 작업 로그, 전문 음악 역할 kit | 앱 내 Codex 계정 대화, 통합 아티스트·멀티미디어 catalog |

소스 근거: [미리 듣기 기본 연결](../Sources/CirclrAudio/AuditionTransport.swift), [worker 수명](../Sources/CirclrAudio/AuditionWorkerProcess.swift), [service](../Sources/CirclrAudio/AuditionWorkerService.swift), [gain/pan·신스 cutoff automation 계약](../Sources/CirclrCore/Automation.swift), [MIDI 노트·tempo import 범위](../Sources/CirclrAudio/MIDIImport.swift), [녹음 UI](../Sources/CirclrApp/RecordingWorkspace.swift), [영상 writer](../Sources/CirclrAudio/CanvasMovieWriter.swift), [에이전트 연결](../Sources/CirclrApp/AgentWorkspace.swift). 함수·타입의 존재만으로 실제 사용 성공을 주장하지 않는다.

## 실행 순서와 작업 흐름

1번은 오디오 출고의 선행 조건이다. 실제 장치 검증을 진행할 수 없는 동안 2번의 통합 UI 검증과 3번의 오프라인 계약 작업은 독립적으로 진행한다. 4번의 음색 측정·편곡 초안도 가능하지만 실제 청취 완료와 구분한다. 5번은 기존 MCP를 먼저 제작 흐름에 사용하고, 계정 대화 구현은 별도 단계로 수행한다. 6번은 음악 제작의 안정성이 확보된 뒤 확장한다. 모든 번호를 동시에 구현하거나 작은 UI 수정 횟수를 진척 목표로 삼지 않는다.

### 1. 실제 연주·녹음·재생의 신뢰성

**다음 행동:** build118 worker가 적용된 정확한 패키지를 기준으로 준비/연주/정지 trace, 대상 장치, process 수명과 실패 복구를 묶은 native 검증 절차를 만든다. 기존 HAL 대기의 원인을 드라이버·서명 등으로 단정하지 않는다. 실제 I/O는 이전 정지 경계를 보존하고 승인된 범위가 분명한 때 별도로 실행한다. 이 계획 자체가 재생·마이크·OS 장치 변경 지시가 아니다.

내장 synth → sampler → AU 순으로 반복 note-on/off·재트리거·oneShot·겹친 voice·target 교체를 검사한다. 그다음 곡 재생 시작/정지/자연 종료·취소 후 재시도, 녹음 결과의 파일 확정·편집·Undo·재열기를 이어간다. 장치 누락/변경·실패 복구를 별도 시나리오로 포함한다. 실제 부족한 경로를 확인한 후 공통 clock·continuous render graph·PDC를 설계하며, 준비된 PCM 엔진을 실시간 엔진으로 표현하지 않는다.

**완료 증거:** 장치·sample rate·buffer·binary 식별과 연주 지연 측정 방법, 실제 청취/readback, note-off와 종료 후 소유 child 정리, 녹음 WAV 내용·파형·재열기, 오류 후 재사용 가능한 앱 상태. 영상은 실제 움직이는 궤도와 오디오 track의 시작/끝 동기·중간 정지·최소화/복원·완성 파일을 확인해야 한다. 성공 로그 없는 항목은 미검증으로 유지한다.

**의존·경계:** [미리 듣기 구현 기록](135-audition-worker-isolation.md), [기본 DAW 녹음 조건](31-daw-basics-plan.md), `AudioRecorder`·`PlaybackOutputConnection`·`CanvasMovieWriter`. mock worker·offline WAV·UI-only helper 검사는 하드웨어 결과를 대체하지 않는다. 원본 사용자 앱 교체는 이 검증과 별도 출고 판단이다.

### 2. 한 곡을 끊김 없이 만드는 단일 캔버스

build132에서 가져오기 오류의 고정 표시·대상 별명과 실제 회복/취소/재열기를 확인했다. 첫 6개 화면 독립 감사는 PASS했으며 추가 unsupported 화면의 오류 고정·keepCurrent 회복과 음악 보존도 독립 감사 PASS로 확인했다. [피드백 검증](153-midi-import-feedback.md).

build130은 가로 파라미터 선택으로 곡선 공간을 확보하고 빈 곡선 Tab의 다른 서클 이동을 수정했다. [검증150](150-automation-editing-space.md).

build128 compact의 동일 창에서 오디오 핵심 수치 4개·완전한 스텝6행과 실제 입력/Undo를 확인했다. 최종 재열기·production 서명/UUID·독립 13개 compact capture 감사도 통과했다. [가시성 검증](147-editor-space.md).

build127에서 세션 내 편곡별 오디오·automation·스텝 작업 복귀와 문서 reset·삭제 대상 fallback을 확인했다. 소스 검토·Release·최종 15개 capture 감사·r62 재열기/disk 일치·production 서명/UUID를 통과했다. 도구 한글 입력은 TextEdit와 써클러에서 동일하게 축소됐으며 실제 IME는 미검증이다. [복귀/입력 진단](146-input-delivery-and-arrangement-return.md).

build126은 적용 A를 유지한 강조 B 이름 변경·강조 유지·Undo/Redo를 검증했다. 최종 Release는 통과했고 저장/재열기·독립7개 snapshot 감사·production 서명/UUID도 통과했다. 당시 후속으로 정한 도구/앱 입력 비교와 편곡별 복귀는 위 build127에서 진행했다. 실제 한국어 IME 검증은 남아 있다. [이름 변경 검증](145-inactive-arrangement-rename.md).

build122 진행: 새 앨범에서 첫 섹션 생성 동선을 확인했고, 공유 MIDI→스텝 전환의 잘못된 대상 이동과 탐색 누락을 수정했다. 키보드·마우스 복귀와 이름 오류/저장 복원을 검증했다. [기록](140-step-target-navigation.md). 후속으로 공유 노트 입력·음색·reverb·바운스·원본 복원·Undo/재열기를 실제 수행했다. [연속 제작 검증](141-production-flow-validation.md). build123에서 원본 복원 후 저장된 출력으로 복귀하도록 개선했고 정상 복귀·오류 거절·Undo·재열기 및 독립8개 상태 감사를 통과했다. [복귀 검증](142-bounce-restore-navigation.md). build124에서 연결→오토메이션과 import→새 파형을 개선했고 실제 전환·Undo·이름 오류를 확인했다. 저장/재열기도 확인했으며 production 서명·UUID와 독립 데이터 감사도 통과했다. [오디오 전환 검증](143-audio-automation-flow.md). 다음은 오토메이션 편집·편곡 대안의 연속 흐름이다. 탐색 성공을 곡 제작 완료로 세지 않는다.

**다음 행동:** 개별 속성 폼 대신 섹션 생성 → 드럼/신스 스텝 → 음색 → 오디오 가져오기 → 이펙트/연결/automation → 편곡 대안 → 바운스 → 저장/재열기를 하나의 authored QA 곡에서 연속 수행한다. 각 단계의 진입 횟수, 상위로 돌아가야 하는 횟수, 보이지 않는 선택·수치·작업 대상, 음악과 화면 상태의 불필요한 변화부터 기록한다. 사용자가 보는 전체 흐름에서 발견된 문제에 우선순위를 둔다.

작은 창·높은 콘솔·긴/같은 이름·중첩 그룹·공유 리듬에서 마우스와 키보드 경로를 비교한다. build121 점검에서 baseline120의 compressor 임계값·압축비는 모두 보였고, 다음 Tab의 출력 볼륨0.00이 화면 밖에서 선택되는 문제를 재현했다. 공통 `NativeNumberField` focus reveal 수정 후 Release44.03초·실제 효과 왕복/입력/Undo·신스11필드 왕복·저장/재열기를 검증했다. [build121 검증](139-numeric-focus-visibility.md)을 바탕으로 다음 구현·검증은 위 한 곡 통합 흐름에서 발견되는 실제 장애를 우선한다. 수정은 현재 서클에서 작업을 이어가도록 만들고, 새 고정 패널이나 설정 메뉴의 추가로 끝내지 않는다.

**완료 증거:** 수정 전후 동일 조건의 실제 AX/화면, Tab·Shift-Tab·Escape/Return·wheel·명령 검색의 정확한 대상과 가시성, 미확정 초안·외부 revision 변경·Undo·저장 복원, 음악·자산 불변 또는 의도된 변경의 정확한 대조. 효과 편집에 성공했다고 전체 제작 흐름을 통과한 것으로 세지 않는다. VoiceOver·한국어 IME는 실제 수행한 범위를 별도로 기록한다.

**의존·경계:** [공유 리듬 오디오](132-shared-rhythm-audio-workspace.md), [오디오 배치](134-audio-workspace-layout.md), [신스 접근](136-synth-parameter-access.md), [콘솔 복원](137-console-preferences.md). 입출력을 차단한 QA로 편집 동선은 진행할 수 있지만 소리·녹음을 완료했다고 말할 수 없다.

### 3. 전자음악의 표현 편집과 엔진 계약 확장

build131은 [MIDI tempo import 계획](151-midi-tempo-import-plan.md)의 기본 keepCurrent·이번 use 파일 tempo 적용·schema4·명시적 복귀를 구현했다. 기계검증 496개·렌더 1개·MCP 13/27개·Release 81.94초를 통과했으며 native GUI/MCP·오프라인 바운스/복원·r95 저장/재열기와 production 서명까지 확인했다. [구현 검증](152-midi-tempo-import-validation.md)을 기준으로 완료 여부를 판단한다.

[신스 cutoff automation 계획](148-synth-cutoff-automation-plan.md)은 build129에서 descriptor·voice 보존 DSP·GUI/MCP·schema를 구현하고 기계검증·실제 Hz 편집/오류 거절을 확인했다. GUI/schema 독립 감사와 production 서명/UUID도 통과했으며 바운스·복원·재열기 r79 및 PCM 독립 감사도 통과했다. 최종 종합 UI 데이터 감사도 통과했다. [현재 검증](149-synth-cutoff-automation-validation.md)을 기준으로 판단한다.

**현재 결과:** [MIDI pitch bend 계획154](154-midi-pitch-bend-plan.md)에서 optional 프로젝트 저장·schema5와 compiled source/occurrence packet, 미지원 렌더·typed MIDI 저장 거절까지 연결했다. build133에서 내장 신스 DSP와 기존 PCM 보존을 연결하고 MIDI 가져오기 취소 복귀를 검증했다. [최종 검증](155-pitch-bend-synth-and-import-return.md). build134에서 SMF bend/RPN 가져오기와 preserve/omit·미지원 처리, GUI/MCP 동일 적용을 구현했다. [가져오기 검증](156-midi-pitch-bend-import.md)의 최종 독립 감사도 통과했다. 곡선 UI·MCP 표현 편집과 SMF 내보내기는 [build135](157-pitch-bend-edit-and-export.md)에서 구현하고 최종 회귀 816개·내부 skip 2개·실패 0개, Release·native 편집/파일 왕복을 확인했다. UI/artifact 최종 독립 감사도 PASS했다. 다음은 실제 한 곡의 표현 편집·편곡·파일 왕복 사용성을 통합 검증하며 AU/sampler와 물리 청취 경계를 별도로 해결하는 것이다. 현재 최종 Core/Audio 회귀는 816개·내부 skip 2개·실패 0개다. 실제 재생 포함 테스트 1개는 제외했으며 AU/sampler와 물리 청취 검증은 아직 남아 있다. build131에서 확인한 가져오기 오류·대상 표시는 build132에서 개선했다. 전체 앱 사용성의 다른 장애는 실제 한 곡 동선에서 계속 확인한다. [MIDI tempo 가져오기](152-midi-tempo-import-validation.md)는 위 범위를 구현·검증했으며 새 모델 도입 단계로 다시 세지 않는다. build129에서 `AutomationParameter`에 synthCutoff를 추가했으며 native 편집·바운스·재열기와 독립 감사를 통과했다. 신스 filter 같은 다음 파라미터는 descriptor·단위·범위·초깃값·시간 의미·DSP 반영을 먼저 정한 뒤 UI에 노출한다. plugin parameter는 실제 descriptor와 state 복원 계약을 갖춘 뒤 추가한다.

MIDI CC/페달/피치 벤드·tempo map은 노트 import와 다른 이벤트·시간 계약이 필요하다. 기존 파일을 여는 것만으로 재해석하지 않으며 가져오기 전 적용 범위를 설명한다. 오디오 crossfade·comping·time warp, 실시간 automation write/touch/latch, punch/loop 녹음은 원본/테이크·공통 clock·취소 수명에 의존하므로 독립 체크박스로 쌓지 않는다. [기본 DAW 계획](31-daw-basics-plan.md)의 남은 조건을 유지한다.

build149 이후 [서스테인 계약173](173-midi-sustain-plan.md)의 optional 저장/schema7·공유 복사·단일 source/occurrence stream에 이어 내장 신스의 key-off 보류·해제 DSP를 연결했다. [렌더 검증175](175-midi-sustain-render.md)에서 전체 Core+선별 Audio635개·실패0개, 바운스/복원·반복 격리와 Release를 확인했다. SMF CC64/CC121 parser·명시적 export 종료·GUI/MCP import는 [build150](176-midi-sustain-file-workflow.md)에서 연결해 파일 실행 검증을 완료했고 최종 재열기 독립 비교도 PASS했다. 다음은 같은 캔버스의 페달 직접 편집이며 실제 장치 연주·GUI/MCP 이벤트 편집은 아직 지원하지 않는다.

**완료 증거:** GUI/MCP 동등 편집·atomic stale 거절·Undo/저장 호환, 변박·반복·공유 원본의 시간 검증, 렌더된 PCM에서 의도한 파라미터 변화, native 편집 동선과 경계 오류 안내. 실시간 기능은 1번의 clock·실제 소리 검증까지 통과해야 완료다.

### 4. f0r h3r와 내장 악기의 제작 품질

**다음 행동:** 한 곡의 현재 렌더와 편곡을 먼저 평가한다. 북유럽 신스웨이브·일본 city pop 화성·future bass 후렴이라는 방향을 유지하면서 DJ가 쓸 수 있는 단순한 중심 드럼, 킥/베이스 상호작용, 분명한 구간 길이·전환·인트로/아웃트로를 설계한다. 트랙 수 증가는 register·보이싱·리듬 역할을 채울 때만 적용하며 같은 음색의 중복으로 풍성함을 대신하지 않는다.

프로듀서가 한 곡의 목표를 정하고 편곡자·연주자·비트메이커·사운드 디자이너·믹싱/마스터링 역할이 서로 다른 책임의 수정안을 만든다. 현재 synth DSP와 실제 patch를 비교 WAV·level-matched 청취로 판단한다. alias/DC·저역 stereo·note-off click·voice 누적·tail 잘림·CPU는 측정하고, 미학은 수치 통과와 분리한다.

**완료 증거:** 편집 가능한 프로젝트·직접 생성 MIDI·stereo WAV·필요한 stems, 원본 보존, 재생/바운스 내용 일치, 실제 청취와 아티스트 검토, 출처·권리 기록. Splice의 기존 10 credit 구매 한도와 프로젝트 재배포 조건은 별개이며, 이미 정한 라이선스 범위 밖의 원본 샘플을 배포하지 않는다. 새 조사/구매가 필요할 때 현재 정책을 확인한다. 이번 계획에서 음악을 제작하거나 라이선스를 새로 확인한 것은 아니다.

**의존·경계:** [Splice 계획](27-splice-licensing-and-integration.md), [음악 역할 kit](24-music-agent-kit.md), `ProductionInstrument`·`CirclrRealtime` DSP. 1번의 실제 연주와 3번의 표현 확장 결과를 반영한다. 오프라인 후보는 먼저 준비할 수 있지만 발매 가능 여부를 파일 생성만으로 선언하지 않는다.

### 5. 백그라운드 제작 에이전트와 앱 내 계정 대화

build125에서 GUI/MCP 범위 차이 중 공유 오디오4종 편집과 automation original을 연결했다. 실제 명령/Undo·A/B 값 표시와 Core/MCP/Release를 확인했으며 저장/재열기·production 서명/UUID·독립14개 snapshot 감사도 통과했다. [계약과 검증](144-agent-shared-audio-scope.md). 공유 trim/replace·계정 대화·실제 오디오는 이 결과에 포함하지 않는다.

**다음 행동:** 기존 MCP와 실제 activity 로그를 사용해 2번의 한 곡 작업을 수행하면서 명령 누락·반복 조회·대상 모호함·STOP 이후 늦은 적용을 점검한다. 전문 역할은 제안/검증을 병렬화하되 음악 변경은 revision을 확인하는 single writer가 통합한다. UI 자동화를 연결 도구가 이미 처리하는 작업의 기본 경로로 삼지 않는다.

앱 내 사용자의 Codex 계정 대화는 별도 구현 단계다. [계정 콘솔 계획](20-codex-account-console-plan.md)을 출발점으로 구현 시점의 OpenAI 공식 문서·지원되는 App Server 계약을 재확인한 뒤 로그인/로그아웃, 세션 복원, 모델/권한, 스트리밍, STOP·프로젝트 전환, 오류 복구를 실제 adapter에 연결한다. 이 문서는 최신 API 지원 여부를 새로 검증한 문서가 아니다. auth 파일 복사나 비공식 OAuth를 통합 방식으로 사용하지 않는다.

**완료 증거:** GUI/MCP 결과 일치, 실제 도구 로그·revision 충돌·중복 요청 처리, 취소 이후 변경 없음, 최소화 상태의 작업과 재연결. 계정 대화는 실제 로그인·대화·도구 실행·취소·복원 및 권한 경계를 따로 검증한다. 기존 MCP socket이나 콘솔 높이 복원을 계정 기능 완료로 세지 않는다.

### 6. 아티스트와 멀티미디어 세계 확장

**다음 행동:** 음악 제작의 안정적인 작업 흐름 위에 [아티스트 세계관 설계](21-artist-universe.md)의 프로필 → 작품 → 버전 → 자산·출처 계약을 적용한다. 캐릭터 선택처럼 아티스트를 전환하되 현재 프로젝트·초안·에이전트 작업의 소유권이 섞이지 않도록 한다. 텍스트·영상·이미지 자산의 연결과 음악의 시간 궤도는 의미를 구분한다.

먼저 한 아티스트의 실제 작품·관련 미디어를 등록하고 탐색·재열기·이동 복구할 수 있는 범위를 완성한다. 이후 아티스트 간 이동·발매 묶음·백업/복원을 확장한다. 샘플 catalog·file promise·폴더 감시·중복 자산 정리도 stable ID/hash·출처·참조 무결성과 연결하며 사용 중 원본을 정리 대상으로 오인하지 않는다.

**완료 증거:** 실제 자산 등록/탐색/참조, 파일 이동·삭제·오프라인 상태, 중복·권리 정보, 버전/백업 복원, 아티스트 전환 중 초안·AI 작업 격리. 현재 MIDI·오디오 서클이나 설계 문서의 존재를 통합 catalog 구현으로 세지 않는다.

## 매 작업의 종료 기준

작업을 시작할 때 위 흐름의 구체적인 사용자 문제, 수정 소유 파일, 재현/완료 조건을 고정한다. 독립 UX·소스 감사·구현·QA는 실제 사용 가능한 슬롯 안에서 분담하고 의존 결과는 순서대로 통합한다. 소스 감사, mock/오프라인 검사, native UI, 실제 오디오, 패키징·출고를 분리해서 기록한다. 이전 build의 통과 수치를 새 후보의 근거로 가져오지 않는다.

작업마다 구현·실제 결과·남은 제한을 문서화하고 제품 변경에 맞춰 README/CHANGELOG를 유지한다. 승인된 비공개 source push 범위에 미디어·QA 앱·인증정보를 섞지 않는다. 개별 개선을 통과하면 다음 실제 제작 장애로 이동하며, 이 여섯 흐름의 남은 요구가 있는 한 전체 목표를 완료 처리하지 않는다.

이전에 지목한 StudioRouteBar 폭 부족은 [build145](167-track-route-density.md)에서 개선·검증했다. 오토메이션 하단 안내는 [build149](172-automation-guidance.md)에서 명시한 화면 조건의 배치·wheel·입력 검증을 완료했다. 다음 UI 후보는 긴 캔버스 이름 tooltip의 실제 표시와 한 곡의 편집·파일 작업·송폼 연속 동선이다. 긴 이름은 전체 title+subtitle tooltip·AX가 이미 있으므로 선택이 필수라고 단정하지 않고 native 표시부터 확인한다.

현재 오프라인 음악 표현 작업은 [내장 신스 resonance 오토메이션 계획](169-synth-resonance-plan.md)의 build147 구현이다. v2/v3 지원·normalized/% 단위·schema6·cutoff 동시 DSP와 검증 계약을 정리했으며 Swift 568개·MCP 22개·Release와 native 편집/바운스/재시작을 확인했으며 data 독립 감사는 PASS_DATA_ONLY이며 UI 감사는 PASS_WITH_EXPLICIT_LIMITS이며 DSP 읽기 전용 검토도 PASS했다([기록](170-synth-resonance-automation.md)).
