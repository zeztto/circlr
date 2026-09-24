# 변경 이력

## 0.80.0 · build232 — 개발 중 · 출고 gate 미통과

- 콘솔에서 현재 내부 AI turn 소유 작업을 중단하면 lease·전용 socket·작업을 함께 닫는다. 일반 MCP job 취소는 작업에만 적용하고 DAW transport는 유지한다. 내부 Codex 계정 대화 기능이 출시된 것은 아니다. [build232 QA](qa/0.80-build232.md).
- 재생 팔로우가 일시 중지됐을 때 버튼·VoiceOver에 `곡·섹션·고정 팔로우 재개`처럼 복귀 대상을 표시한다. 기본 곡 팔로우가 섹션 내부 케이블을 화면 밖으로 옮기는 기존 정책은 유지한다.
- 전체 Swift **1,232개·15 skip·실패 0**, 최종 AI 통합 9개 통과. 서명된 0.80.0/build232 arm64 앱·5 helper, agent kit 25개 hash와 동봉 데모 manifest 일치를 확인했다. [격리 실제 앱](qa/0.80-build232-native.md)에서 섹션/곡 팔로우 대상에 맞는 선택 케이블·카메라, 가로·세로 7섹션, 짧은 MP4 첫 프레임과 종료 정리를 확인하고 한영 README 화면을 갱신했다. 물리 청취·Scarlett 호환성·장시간 영상·계정 연결 gate는 열려 있어 정식 Release는 보류한다.

## 0.80.0 · build231 — 개발 중 · 출고 gate 미통과

- 재생 팔로우를 다시 켜도 선택한 케이블의 전면 강조선이 편집 도구막대와 함께 사라지지 않게 했다. 영상 캡처에서는 첫 프레임을 포함해 편집 도구·강조선·끝점 핸들을 제외한다. [UI 감사](qa/0.80-qa232-ui-density.md) · [build231 QA](qa/0.80-build231.md).
- 실제 ChatGPT 로그인 Codex CLI 모델이 **격리된 build230 QA 앱**에 MCP로 네 MIDI note를 만들고 Undo·저장/재열기·70초 WAV를 완료했다. 앱 내부 계정 대화 기능으로 해석하지 않는다. [모델 QA](qa/0.80-qa232-model-native.md).
- 최종 소스 Swift **1,231개·15 skip·실패 0**, Python MCP **41개**·QA **17개** 통과. build231 arm64 앱·5 helper strict deep 서명, Codex kit 25개 hash, 동봉 데모 manifest 일치를 확인했다. 격리 native 앱의 케이블 선택·팔로우 재개·MP4 첫 프레임과 가로·세로 화면을 검사했지만 팔로우 뒤 로컬 케이블 가시성·물리 청취·녹음 take·장시간 영상은 열려 있다. 구형 Scarlett 정상 출력은 별도 호환성 항목이며 정식 tag/Release를 만들지 않는다. [native QA](qa/0.80-build231-native.md).

## 0.80.0 · build230 — 개발 중 · 출고 gate 미통과

- MIDI·오디오 녹음 준비/진행/마무리 중 프로젝트 교체·저장을 차단하고, 비동기 데모 로드의 실제 적용 직전에도 녹음 상태를 재검사한다. MIDI 녹음 시간은 별도 단조 시계로 표시하고 종료 뒤 재생 시계로 복귀한다.
- 앱 소유 내부 AI turn은 이미 선택된 `.circlr` 문서의 save와 별도로 앱이 선택한 `.wav` export만 허용한다. 모델의 경로 지정·다른 문서·stale revision·STOP 이후 게시를 거절한다. 저장 stage의 미디어 복사·checksum은 취소 가능하며 교체된 stage 폴더의 다른 파일을 재귀 삭제하지 않는다. WAV는 선택 시점의 폴더 identity를 고정해 기존 파일을 덮어쓰지 않고 게시한다. 실제 Codex 계정 대화는 공개 기능이 아니다.
- 전체 Swift **1,229개 실행·14 skip·실패 0**, 지정 통합·계약 **49개**, Python **50개**, arm64 앱·다섯 helper의 strict deep 서명을 통과했다. 격리 native 앱의 가로·세로 데모 7섹션과 MIDI 녹음 시계 00:00.4→00:25.6, 녹음 중 새 앨범 차단·종료 후 복귀를 확인하고 한영 README 화면을 갱신했다. [build230 QA](qa/0.80-build230.md) · [native](qa/0.80-build230-native.md). 구형 Scarlett의 물리 입출력, 실제 take·청취 및 장시간 MP4는 미검증이며 정식 tag/Release를 만들지 않는다.

## 0.80.0 · build229 — 개발 중 · 출고 gate 미통과

- 곡 궤도의 섹션 이름표가 자기 타임라인·마디 눈금과 하단 navigation을 가리지 않도록 배치한다. 세로 창의 긴 06 제목은 들어갈 때만 가까운 두 줄 배지로 표시하고 hover·선택 때 크기를 고정한다. [build229 QA](qa/0.80-build229.md) · [native 화면](qa/0.80-build229-native.md).
- CoreMIDI client를 프로세스 수명 동안 공유해 idle 뒤 MIDI 입력 재진입 오류 `-2`를 막고, 실제 Note On packet 회귀를 추가했다. 최종 Swift 1,202개·14 skip·실패 0, Python 50개 통과. arm64 앱·다섯 helper의 strict deep 서명 통과. [CoreMIDI 조사](qa/0.80-build226-coremidi.md).
- 공개 앱 안의 Codex 계정 대화는 [공식 App Server의 현재 production 미지원 상태](qa/0.80-build226-codex-g0.md)에 따라 G0 NO-GO다. 구형 Scarlett 정상 입출력·물리 청취·녹음 take·장시간 MP4 등 남은 0.80 gate를 완료하기 전에는 tag/Release를 만들지 않는다.

## 0.80.0 · build225 — 개발 중 · 출고 gate 미통과

- 앱이 선택된 MIDI 섹션의 한 AI turn을 전용 socket·대상·만료 시간과 함께 소유한다. 완료·STOP·문서 교체·종료에서 연결을 닫고, 완료 전 수락된 바운스만 제한적으로 마치게 한다. 실제 Codex 계정·대화 UI는 아직 연결하지 않았다. [AI QA](qa/0.80-build225-ai.md).
- 격리 실제 앱의 [build224 MCP 제작 QA](qa/0.80-build224-mcp-native.md)는 MIDI/Undo·FX/automation·70초 WAV·두 트랙 바운스·저장/재열기를 확인했다. QA harness에 격리 bundle ID/Support root 인자를 추가했다.
- 관련 Swift 27개와 Python 50개 통과, build225 arm64 앱·다섯 helper strict deep 서명 통과. 전체 Swift 1,194개 중 가상 MIDI client 생성 `-2`가 두 번 재현되어 **1개 실패**다. 원인은 미확정이며 정식 0.80 tag/Release는 보류한다. 구형 Scarlett의 정상 입출력은 합격 조건으로 간주하지 않는다.

## 0.80.0 · build224 — 개발 중

- 720×900 창에서 직접 섹션 이름표가 빠지지 않도록 가까운 배치가 막히면 화면 안의 빈 위치를 찾는다. 서클·도구·다른 이름표와 겹치지 않으며 가로·세로 README 화면을 build224 실제 앱으로 갱신했다. [build224 QA](qa/0.80-build224.md) · [native](qa/0.80-build224-native.md).
- 마지막 소스의 Swift 1,189개 중 14 skip·실패0, arm64 앱·다섯 helper·agent kit의 strict deep 서명 통과. 0.80의 실제 녹음·물리 청취·장시간 영상·완전한 제작/AI 경로 gate는 계속 열려 있다.

## 0.80.0 · build223 — 개발 중

- 저장된 화면이 없는 단일 곡을 열면 앨범 개요 대신 곡의 섹션 궤도를 먼저 보여 준다. 저장된 사용자 화면과 여러 곡 앨범의 첫 화면은 그대로 유지한다. [build222 native](qa/0.80-build222-native.md).
- 창 너비나 하단 콘솔 높이가 바뀌면 현재 곡의 context-fit을 보이는 영역에 다시 맞춘다. 사용자가 조작한 zoom/pan과 재생 팔로우는 보존한다. 최종 Swift 1,189개 중 14 skip·실패0, arm64 앱/5 helper·strict deep 서명 통과. [build223 QA](qa/0.80-build223.md).
- 실제 입력 take·물리 청취·장시간 녹화·앱 내 Codex 계정 대화는 0.80 출고 gate로 남아 있다. 구형 Scarlett의 세대와 호환성은 미확정이며 [오디오 감사](qa/0.80-daw-audio-audit.md)와 [AI/MCP 감사](qa/0.80-agent-journey-audit.md)를 분리해 기록했다.
- 격리 앱의 720×900 창에서 04·06·07 섹션 라벨이 가려졌다. 원과 AX 항목은 유지됐지만 build223은 세로 화면 사용성 **FAIL**이며 build224의 라벨 배치 보강으로 이어간다. [native QA](qa/0.80-build223-native.md).

## 0.80.0 · build221 — 개발 중

- build220의 동일 앱/곡은 `/tmp`에서 manifest 선택 저장이 약 0.7초, Documents에서 `.circlr` 폴더 선택 저장이 약 0.6초였으나 Documents의 manifest 한 파일 선택 뒤 저장만 멈췄다. GUI에서 manifest를 선택하면 같은 곡 폴더를 한 번 더 명시적으로 선택해 미디어 접근을 확보하도록 한다. macOS Documents 접근 설명도 앱에 추가했다. [build220 통제 QA](qa/0.80-build220-temp-native.md) · [build221 QA](qa/0.80-build221.md).
- 최종 Swift 회귀 1,187개 중 14 skip·실패0, arm64 앱·다섯 helper·agent kit 패키지와 strict deep 서명 통과. 실제 Documents 앱의 manifest→동일 폴더 확인→첫 `⌘S`는 약 0.5초, 미디어 6/6 hash 유지·저장 후 재열기도 통과했다. `notes.txt` 포함 QA 패키지의 저장 거부·8/8 hash 보존, 실제 가로·세로 전체 창, 앱/helper 정리까지 확인했다. 전체 0.80 출고 gate는 여전히 열려 있다. [native QA](qa/0.80-build221-native.md).

## 0.80.0 · build220 — 개발 중 · 출고 후보 제외

- 스트리밍 복사 source가 FIFO 같은 특수 파일이면 읽기 시작 전에 멈출 수 있다는 후속 리뷰를 반영했다. 미디어를 `O_NONBLOCK|O_NOFOLLOW`로 열고 일반 파일인지 확인한 뒤 복사한다. FIFO 입력과 1MiB 경계를 넘는 바이트 보존을 검증한다. [build220 QA](qa/0.80-build220.md).
- 전체 Swift 회귀 1,187개 중 14 skip·실패0, arm64 앱/다섯 helper·strict deep 서명 통과. 그러나 Documents QA 앱에서 `manifest.json` 파일만 선택한 뒤 첫 `⌘S`가 미디어 파일 `open`에서 30초 이상 멈췄다. 이 빌드는 출고 후보가 아니며 비보호 경로/폴더 선택 통제 시험으로 macOS 접근 범위를 분리한다. [native 실패](qa/0.80-build220-native.md).

## 0.80.0 · build219 — 개발 중 · 패키지 후보 제외

- build218 실제 앱의 작은 데모 저장이 macOS `clonefileat` 경로에서 30초 이상 멈췄다. 미디어를 staging 폴더로 복사할 때 고정 크기 청크로 읽고 쓰는 경로로 바꾸고, 1MiB 경계를 넘는 바이트 보존 회귀를 추가했다. [build218 native 실패](qa/0.80-build218-native.md).
- 백업 정리 경고를 agent 저장 성공 응답에도 담고, 기존 Core API wrapper에서는 stderr로 알리게 했다. 최종 앱의 재검증과 나머지 0.80 출시 gate는 [build219 QA](qa/0.80-build219.md)에 분리한다.
- 후속 리뷰에서 미디어 FIFO가 저장 복사의 파일 열기를 멈출 수 있음을 발견해 패키지 작업을 중단했고 native 앱은 실행하지 않았다. build220에서 수정·재검증한다.

## 0.80.0 · build218 — 개발 중 · 출고 후보 제외

- 후속 보안 리뷰에서 build217의 프로젝트 덮어쓰기가 일반 폴더에 함께 둔 개인 파일을 삭제할 수 있고, `manifest.json`이 FIFO이면 열기가 멈출 수 있음을 발견했다. 저장 전 폴더 소유 파일을 확인하고 일반 파일 manifest만 크기 제한을 두고 읽도록 고쳤다.
- 저장된 이전 폴더의 정리는 고정한 디렉터리 fd 아래에서만 수행하며, 정리 실패가 이미 완료된 저장을 실패로 바꾸지 않도록 GUI·agent 저장 상태와 경고를 분리했다. build218 검증 결과는 [QA 기록](qa/0.80-build218.md)에 정리한다. 전체 0.80 출시 gate는 계속 열려 있다.
- 최종 Swift 회귀와 패키지·서명은 통과했지만, 격리 실제 앱에서 작은 QA 곡의 `⌘S`가 `FileManager.copyItem → clonefileat`에서 30초 이상 멈췄다. 원본은 불변이었고 앱은 종료했다. build218은 출고 후보가 아니다. [native 기록](qa/0.80-build218-native.md).

## 0.80.0 · build217 — 개발 중 · 출고 후보 제외

- Open 패널에서 `manifest.json` 파일을 직접 선택하면 상위 `.circlr` 곡 폴더로 정규화해 열고, 곡이 아닌 폴더·파일을 선택하면 무엇을 골라야 하는지 설명한다. GUI와 MCP 열기 모두 같은 루트를 사용하며 임시 데모 사본 보호도 유지한다. [build216 오류 재현](qa/0.80-open-panel-repro.md).
- 구형 Scarlett을 제외한 CalDigit 입력의 독립 캡처도 이 Mac에서 시작 단계 timeout이 발생했다. 실제 PCM이 확인되지 않아 선택 입력 녹음은 계속 명시적으로 닫고, [0.90 입력 계획](docs/releases/0.90.0.md)의 실기기 gate를 유지한다. [입력 조사](qa/0.80-selected-input-investigation.md).
- 전체 Swift 회귀 1,184개 중 14 skip·실패0, build217 arm64 앱·다섯 helper 패키지와 strict deep 서명을 확인했다. 격리 실제 앱의 무선택 오류 안내, manifest 직접 선택·저장·폴더 재열기와 원본/미디어 보존을 확인하고 한영 README의 가로·세로 화면을 새 앱으로 교체했다. 전체 0.80 출고 gate는 열려 있어 tag·Release는 아직 만들지 않는다. [build217 QA](qa/0.80-build217.md) · [native](qa/0.80-build217-native.md).
- 후속 저장 보안 리뷰에서 일반 폴더 내 개인 파일 삭제 위험과 특수 manifest 읽기 경계가 발견돼 build217은 최종 패키지 후보에서 제외했다. 해당 테스트·native 결과는 관찰 당시 범위의 증거로 남긴다.

## 0.80.0 · build216 — 개발 중

- build215 실제 세로 창 QA에서 첫 Intro의 ‘순서 앞으로’와 마지막 Outro의 ‘순서 뒤로’가 활성처럼 보이는 결함을 발견했다. AppKit popup 검증을 모사한 테스트를 RED로 재현하고, 선택 서클 메뉴의 자동 활성화를 끄고 GREEN으로 수정했다. 키보드 이동·Undo·저장 후 명시적 재열기는 build215에서 통과했다. 첫 Open panel의 일회성 `manifest.json` 오류는 원인 미확정으로 남긴다.
- 수정 후 전체 Swift 회귀 **1,184개 항목 종료 코드 0**, 0.80.0/build216 arm64 앱·다섯 helper 패키지와 strict deep 서명이 통과했다. Python/MCP/agent kit 소스는 build215 검증 뒤 변경되지 않았다. 격리된 실제 720×900 앱에서 양쪽 경계 메뉴의 disabled·중간 섹션 enabled, 키 이동·Undo를 확인했다. 남은 0.80 출고 QA 전에는 정식 tag·Release를 만들지 않는다. [build215 native 실패](qa/0.80-build215-native.md) · [build216 QA](qa/0.80-build216.md) · [native 재검사](qa/0.80-build216-native.md).

## 0.80.0 · build215 — 개발 중

- 축소한 곡 궤도에서 선택 섹션을 `⇧⌥←/→`, 우클릭 메뉴, 명령 검색으로 한 칸 이동할 수 있게 했다. 분기·전환 제약, 공간 배치, Undo를 유지한다.
- 내부 trusted AI turn의 소유 bounce 작업에 경로 없는 읽기 전용 `job` 상태 조회를 추가했다. STOP 뒤 조회와 request ID 재사용을 거절한다. 실제 계정 대화는 아직 출시 기능이 아니다.
- 구형 기본 입력 장치에 묶이지 않을 앱 전용 입력 선택의 CoreAudio UID catalog·binding 계약을 검증했다. 이 Mac의 AUHAL 시작은 선택 UID 적용 이전에 timeout이 재현되어, 선택 입력 녹음은 명시적 미지원 오류로 닫고 기존 기본 입력 경로를 유지했다. 사용자에게 선택 입력 기능을 제공하는 단계는 아니다.
- 당시 소스 Swift 회귀 **1,184개 항목 종료 코드 0**, Python 프로젝트 **50개**, MCP 서버 **41개**, agent kit **9개** 통과. arm64 앱·다섯 helper 0.80.0/build215 패키지와 strict deep 서명을 확인했다. build214 격리 앱의 16 stems+mix GUI 내보내기는 각 197.002초·nonzero PCM이었고 앱 RSS 최고 약 1.97GiB였다. 실제 build215 키보드 이동은 통과했으나 경계 우클릭 메뉴는 FAIL이며 build216에서 수정한다. 녹음 take·물리 청취·반복 메모리 검사는 남아 있다. [build215 QA](qa/0.80-build215.md) · [대형 stems](qa/0.80-build215-stems.md). 정식 tag·Release는 아직 없다.

## 0.80.0 · build214 — 개발 중

- 곡 궤도와 섹션 라벨에 실행 순번을 표시하고, 선택·hover·접근성에서 시작·끝 시간을 볼 수 있게 했다. 반복 섹션은 현재 occurrence만 강조하며 감상 모드에서는 새 텍스트를 숨긴다.
- 일반 WAV를 백그라운드에서 청크로 기록하고 Stop과 최종 게시를 직렬화해 취소 뒤 파일 교체를 막는다. 새 렌더 전에 이전 PCM과 출력 준비 queue를 정리하고 중복 내보내기를 차단한다.
- 최종 소스의 Swift 회귀 1,169개 항목 종료 코드 0, Python 프로젝트 50개·MCP 서버 41개·agent kit 9개 통과. build214 arm64 앱·다섯 helper와 strict deep 서명을 확인했다. 격리된 실제 앱의 가로·세로 화면, 앱 전용 내장 출력 Play/Stop과 197.002초 nonzero GUI WAV를 확인했다. 구형 Scarlett의 정상 출력·물리 청취·순수 hover는 확인하지 않았다. [검증 기록](qa/0.80-build214.md) · [native QA](qa/0.80-build214-native.md). 정식 0.80 tag·Release는 아직 없다.

## 0.80.0 · build213 — 개발 중

- 두 곡 이상 앨범의 stems가 활성 편곡안에서 끝나던 결함을 수정해 일반 WAV와 같은 앨범 전체 실행 계획을 사용한다. 두 composition fixture에서 후반 stem 신호와 전체 frame 수를 비교했다.
- 기존 stem 목록이 없는 legacy 폴더는 개인 WAV를 보호하기 위해 덮어쓰지 않는다. 재생·루프 전환·agent 렌더/문서 열기와 GUI stems의 취소·재시작 경계를 보강하고, 새 PCM 할당 전에 이전 worker의 종료를 기다린다. [build213 QA](qa/0.80-build213.md).
- 최종 소스 전체 Swift 1157개·12 skip·실패0, MCP 계약39개·서버41개·agent kit9개, build213 arm64 앱/다섯 helper 패키지와 strict deep 서명을 확인했다. 격리 native QA 및 정식 0.80 출고 gate는 여전히 열려 있으며 tag·GitHub Release는 만들지 않았다.

## 0.80.0 · build212 — 개발 중

- 전체 stems를 하나씩 렌더·기록한 뒤 원자 게시하도록 바꿨다. 16트랙 QA 곡에서 이전 메모리 사전 한도 실패를 재현했고, 새 오프라인 경로는 16 stem+전체 mix 17개 WAV를 생성했다. 실제 앱의 2트랙 stems와 후속 WAV도 확인했다. 통합 리뷰에서 다중 곡 누락·일부 작업 경합·legacy 대상 보존 문제가 발견되어 build213에서 수정 중이다.
- 45pt 이하 축소 서클의 hover·선택 포트 표시·클릭·접근성 경로를 복원하고, 읽기 라벨이 기본 위치를 덮을 때 대체 anchor를 사용한다. 실제 앱에서 약 44pt의 IN/OUT 선택·AX와 가로/세로 화면을 확인했다.
- 아직 앱에 연결하지 않은 `CirclrCodex`의 offline session coordinator를 가짜 JSONL 자식으로 검증했다. 승인 거절, 모델 목록, 취소 뒤 늦은 이벤트·출력 큐 한도를 다루지만 계정 로그인·대화 UI와 production runtime G0는 여전히 미완료다.
- 당시 전체 Swift 회귀 1151개·12 skip·실패0 이후 렌더 경계 변경의 영향 필터 15개·1 skip·실패0, Python MCP 80개·agent kit 9개를 확인했다. arm64 앱/다섯 helper 패키지·strict deep 서명과 [native GUI QA](qa/0.80-build212-native.md)도 완료했다. 이 결과는 build213 수정 전 범위다. [build212 QA](qa/0.80-build212.md).

## 0.80.0 · build211 — 개발 중

- build210의 실제 37초 MP4에서 UI/디코드 프레임 수가 1118/1117로 어긋난 종료 경계를 수정했다. 유한 PCM의 원래 끝점은 유지하고 MP4 영상 session만 마지막 수용 프레임 뒤 최대 1/30초까지 열어 둔다. 유효한 마지막 프레임까지 버리던 첫 후보는 독립 리뷰 후 폐기했다.
- 아직 앱에 연결하지 않은 `CirclrCodex`에서 자식 환경의 생략 경로를 제거하고, 관리형 계정 세션을 승인된 canonical 작업 디렉터리·읽기 전용 thread ID에 묶었다. 비관리형 legacy turn 경로는 제품 기능으로 연결하지 않는다.
- 최종 전체 Swift 1137개·11 skip·실패0, MCP 계약39개·MCP 서버41개·agent kit9개, arm64 앱/다섯 helper 패키지와 strict deep 서명 통과. 최종 패키지의 격리 실제 앱 37.980초 MP4는 UI/독립 decoder 1138/1138로 일치하고 stereo PCM 신호가 있었다. 프레임 간격 P95 38.33ms·최대60ms, 두 프레임 초과 gap0이다. 이전 패키지의 38.007초 녹화에는 68.33ms gap 1곳이 있었다. 물리 청취·1080p/10분·전체 제작 동선과 AI 계정 대화는 아직 출시 gate다. [build211 QA](qa/0.80-build211.md).

## 0.80.0 · build210 — 개발 중

- 녹화 종료 시각과 정확히 겹친 캡처 프레임은 MP4에 기록되지 않으므로 저장 프레임 수에서도 제외했다. 유한 오디오와 예약된 루프 종료의 독립 디코드 회귀 테스트로 확인했다.
- 앱과 아직 분리된 내부 `CirclrCodex`에 계정 상태·모델 목록·읽기 전용 thread·명시적 turn 모델 RPC와 자식 프로세스 환경 제한을 추가했다. 설치 CLI의 실제 계정·한 turn은 앱 밖에서만 확인했다. [공식 App Server](https://learn.chatgpt.com/docs/app-server)의 production 지원 조건과 앱 안의 AI 음악 작업은 여전히 미완료다.
- 전체 Swift 1131개·11 skip·실패0, 최종 Codex 프로토콜 37개·실패0, MCP 39개·agent kit 9개, arm64 앱/다섯 helper의 build210 패키지·strict 서명 통과. 격리된 실제 앱의 7.438초 MP4는 UI/디코드 223프레임으로 일치했지만 37.299초 파일은 **UI 1118/디코드 1117**로 불일치가 남았다. build211에서 다시 수정·검증했다. 당시 한영 README의 가로·세로 화면은 build210에서 촬영했다. 물리 청취·장시간 영상과 0.80 출고 gate는 열린다. [build210 QA](qa/0.80-build210.md) · [native 영상](qa/0.80-build210-native-movie.md).

## 0.80.0 · build209 — 개발 중

- 재생 기본 팔로우를 곡 전체 궤도로 바꿨다. 명시적으로 저장한 섹션·고정 서클 팔로우는 유지한다. 고밀도 섹션의 재생 화면에서는 작은 FX·믹스·라우터·출력 라벨을 접고 선택·hover·정지·확대 시 복원한다.
- Codex 계정 콘솔을 위한 내부 turn 전용 socket 후보를 추가했다. capability 사전 검사와 STOP 뒤 늦은 쓰기 차단, 완료 turn의 기존 bounce 권한 보존을 실제 Unix socket 테스트로 확인했다. **계정·모델·helper와 연결된 출시 기능은 아니다.**
- 전체 Swift 1121개·11 skip·실패0, MCP Python 39개·agent kit 9개, arm64 앱/다섯 helper 패키지와 strict deep 서명 통과. 격리 build209 실제 앱에서 기본 곡 팔로우·섹션 라벨 복원과 7.805초 MP4의 234개 디코드 프레임·nonzero 오디오를 확인하고 한영 README의 가로·세로 화면을 갱신했다. 물리 청취·장시간 영상·완전한 제작 QA는 남아 있어 0.80 출고하지 않는다. [build209 QA](qa/0.80-build209.md) · [native 화면/영상](qa/0.80-build209-native.md).

## 0.80.0 · build208 — 개발 중

- 사용자 파일과 분리된 저장 루트를 주입해 실제 AppStore의 AI 권한 경계를 통합 검증했다. `snapshot → inspect → MIDI 편집 → Undo`, AI STOP 뒤 늦은 쓰기·이미 수락된 bounce commit 거절, 새 turn 재개를 확인했다. 앱 안의 Codex 계정 대화와 전용 trusted ingress는 아직 연결되지 않았다. 구형 Scarlett는 필수 출력 기준에서 제외하고 Mac 내장 출력의 native 재생 경계를 다시 검사했다. [QA](qa/0.80-build208.md).

## 0.80.0 · build207 — 개발 중

- 다른 앱이 마지막으로 선택한 뒤 종료했을 때 살아 있는 앱의 기본 MCP 경로가 빈 곳을 가리키는 문제를 분리했다. 앱은 열린 socket과 기본 선택 여부를 표시하고, 명시적 버튼으로 자기 socket을 다시 선택한다. 자동으로 다른 앱에 연결하지 않는다.
- 격리 실제 앱에서 다른 앱의 종료된 선택 정보를 재현해 기본 미선택 표시→MCP 실패→명시 재선택→새 세션 연결을 확인했다. 전체 Swift 1113개·11 skip·실패0, Python 50개 실패0, arm64 앱·다섯 helper 빌드/서명 통과. [build207 QA](qa/0.80-build207.md). 0.80 출고 gate는 계속 열린다.

## 0.80.0 · build206 — 개발 중

- 기존 Agent socket이 살아 있거나 비정상 종료로 남아 있어도 원본을 건드리지 않고 콘솔에서 이 앱의 새 연결을 선택할 수 있다. 기본 MCP 세션은 선택된 endpoint·실행 ID·socket inode에 고정되며 변경 시 쓰기를 거절한다. 구버전 경로의 연속 요청과 변경 차단도 검증했다.
- 격리 실제 앱에서 기존 socket 보존→새 연결→정상 종료→표준 경로 재시작을 확인했다. Mac Studio 내장 출력의 데모 Play/Stop도 확인했지만 물리 청취는 미확인이다. 전체 Swift 1113개·11 skip·실패0, Python 50개 실패0, arm64 앱·다섯 helper 빌드/서명 통과. [build206 QA](qa/0.80-build206.md). 0.80 출고 gate는 계속 열려 있다.

## 0.80.0 · build204 — 개발 중

- 로컬 MCP socket을 전용 임시 경로에서 준비한 뒤 기존 연결을 덮어쓰지 않는 원자 게시로 전환했다. 다른 프로세스가 공개 경로를 먼저 차지하거나 bind 직후 경로를 교체해도 그 socket을 자기 것으로 기록하지 않는다.
- 격리 실제 앱에서 데모 종료 뒤 socket·자동저장 정리, 별도 test listener의 점유 보존과 점유 해제 후 자동 재연결을 확인했다. 구버전 앱 실제 동시 실행과 crash-stale 복구 UI는 출고 전 검증이 남았다. [build204 QA](qa/0.80-build204.md).

## 0.80.0 · build203 — 개발 중

- 영상·녹음 마무리를 기다리는 종료 과정에서 새 MCP 편집을 차단하고, 대기 중 곡 상태가 바뀌면 종료를 취소한다. 종료 취소 시 연결을 되살린다. 이는 build202 코드 리뷰에서 발견된 미저장 변경 손실 경로를 닫기 위한 수정이다.
- 실제 격리 앱에서 데모의 변경 버리기→종료→재실행과 종료 취소 후 MCP socket 응답을 확인했다. 정상 종료 뒤 socket·새 복구본은 남지 않았고 구버전/사용자 복구본은 보존됐다. 비동기 영상 마무리 경합과 crash-stale 복구는 계속 출고 gate다. [build203 QA](qa/0.80-build203.md).

## 0.80.0 · build202 — 개발 중

- 정상 종료 후에도 로컬 MCP socket 경로가 남는 build201 QA 결함을 수정했다. 종료가 확정되면 소유한 socket을 닫고, 취소된 종료에서는 연결을 유지한다. [build201 발견 기록](qa/0.80-build201.md).

## 0.80.0 · build201 — 개발 중

- 구버전 `recovery.json`은 읽기 전용으로 보존하고, 이번 앱의 자동저장은 잠금이 있는 별도 `recovery-v2.json`으로 관리한다. 복구 선택이 끝나기 전에는 agent socket을 열지 않는다. 명시적 버림·저장·곡 전환 뒤 현재 세션의 복구본과 임시 데모 사본만 안전하게 정리한다. [build200 native 복구 QA](qa/0.80-build200.md).
- 복구 파일의 대형·symlink·FIFO 입력을 제한하고 QA 저장소를 production과 분리했다. 구버전 앱이 사용 중인 agent socket은 보존하고 정상 종료 뒤 재연결을 재시도한다. 비정상 종료로 남은 stale socket의 안전한 명시적 복구는 출고 전 과제다.
- 내부 `CirclrCodex`의 stdio process host에서 자식 수명·쓰기 timeout·세대 교체를 테스트했다. 실제 계정 대화 UI와 공개 배포의 지원 조건은 여전히 열려 있다. [조사](qa/0.80-codex-stdio.md).

## 0.80.0 · build200 — 개발 중

- 구버전 복구본을 그대로 둔 채 새 v2 자동저장과 명시적 버림, 다음 실행의 확인 기록, 복구 안내 중 agent socket 차단을 별도 QA 앱에서 확인했다. 후속 데모 사본 정리 리뷰 때문에 최종 후보는 아니다. [QA](qa/0.80-build200.md).

## 0.80.0 · build199 — 개발 중

- 명시적 **변경 버리기** 뒤 이전 자동 복구본이 다시 나타나는 결함을 수정했다. 한 앱 인스턴스만 복구 파일을 소유하고, 읽을 수 없는 복구본은 원본을 별도 보존한다. 파일로 앱을 여는 경로도 복구 선택을 먼저 처리한다.
- 약 702pt 실제 창에서 두 줄 케이블 도구의 OUT/IN·편집·AX를 재확인했다. clean scratch 전체 Swift 1100개·11개 skip·실패0, MCP와 agent kit 회귀, 앱·다섯 helper 빌드/서명을 통과했다. 기본 증분 테스트의 오래된 object 충돌은 별도 기록했다. [QA](qa/0.80-build199.md).
- 앱과 분리된 내부 `CirclrCodex`에 bounded stdio process host를 추가했다. 자식 프로세스 교체·쓰기에 대한 테스트는 통과했으나 실제 사용자 계정·앱 내 대화의 기능 완료나 공개 지원 G0 통과를 뜻하지 않는다. [조사](qa/0.80-codex-stdio.md).

## 0.80.0 · build198 — 개발 중

- 최소 창 폭이 700pt임을 확인하고 케이블 도구의 두 줄 배치를 해당 세로형 폭에 적용했다. 실제 앱에서 OUT/IN 선택·연결 편집과 AX 버튼을 확인했다. 종료 시 **변경 버리기** 후에도 자동 복구본이 남는 결함을 재현했으며 후속 후보에서 수정한다. [QA](qa/0.80-build198.md).

## 0.80.0 · build197 — 개발 중

- `portfocusqa` 격리 앱이 기본 circlr 복구 폴더를 참조하는 결함을 발견해 QA 번들별 Application Support 폴더를 분리했다. build196 복구 창에서는 아무 선택도 하지 않고 검증 앱만 종료했다. build197 실제 앱은 별도 저장 폴더에서 복구 창 없이 열렸고 기존 폭의 케이블 선택·편집 동작을 확인했다. [QA](qa/0.80-build197.md).

## 0.80.0 · build196 — 개발 중

- 좁은 작업 영역의 케이블 편집 도구를 두 줄로 배치했다. 실제 앱에서 복구 폴더 격리 오류를 발견해 도구 클릭 검증은 다음 후보로 이월했다. [QA](qa/0.80-build196.md).
- 설치된 Codex CLI의 App Server stdio 초기화를 모델 호출 없이 확인하고 재현 도구를 추가했다. 내부 프로세스 host의 테스트와 계정 대화·MCP 연결·production 지원 여부는 별도 gate로 유지한다. [초기화 조사](qa/0.80-codex-stdio.md).

## 0.80.0 · build195 — 개발 중

- build194 실제 앱 QA에서 발견한 정상 정지 후의 부정확한 장치 변경 안내를 수정했다. 장치 변경 복구 문구는 출력 준비 timeout에만 표시하고 일반 Stop 뒤에는 다시 재생 안내만 남긴다. build195 실제 앱에서 Mac Studio 스피커 Play/Stop 2회와 9.363초 MP4를 확인했다. 한영 README의 실행 화면도 build195로 갱신했다. [QA](qa/0.80-build195.md).

## 0.80.0 · build194 — 개발 중

- 좁은 창의 고밀도 재생에서는 비선택 연결의 화살표와 중복된 강조선을 줄이고, 기본 연결선·활성 pulse·선택 경로와 포트 hit 영역을 보존한다.
- 출력 실패 뒤 감상 모드에서 편집 화면으로 돌아와 장치 변경 안내를 볼 수 있게 하고, 취소된 재생 요청의 늦은 완료가 상태를 덮어쓰지 않도록 한다. 시스템 기본 Scarlett의 시작 timeout과 명시적 내장 스피커의 무음 시작 성공을 분리해 [출력 조사](qa/0.80-output-investigation.md)에 기록했다.
- 내부 AI RunLease에 대상·revision 권한을 확인하는 섹션·MIDI 읽기 `inspect`를 추가한다. 파일 경로·플러그인 상태는 응답에서 제외하고, 재전송과 중첩 작업의 허용되지 않은 필드는 거부한다. 실제 Codex 계정 대화와 앱 내 AI 작업 UI는 아직 연결되지 않았다.

## 0.80.0 · build193 — 개발 중

- 영상 캡처의 PTS와 궤도 시각화를 동일한 출력 시각으로 계산하고, 출력 시계가 멈추면 새 프레임을 만들지 않도록 했다. 루프 교체·종료 경계의 음악 계획과 시각 위치도 함께 전환한다.
- 전체 Swift 테스트 1085개·11개 skip·실패0, arm64 앱/다섯 helper 빌드·서명, 실제 앱의 22.277초 MP4를 확인했다. 프레임 gap P95는 build192의 53.33ms에서 40.00ms로 낮아졌지만 다른 길이·장면의 녹화이므로 통제된 비교는 아니다. 실제 청취·1080p/장시간·중간/끝 AV 동기·출력 실패 복구는 열린다. [영상 QA](qa/0.80-build193-movie.md).

## 0.80.0 · build192 — 개발 중

- build191 native QA에서 선택한 섹션의 `P → Return` 연결 편집이 열리지 않던 문제를 수정했다. 명시적 편집 요청은 위성 전체 맞춤을 거치지 않고 에디터가 표시되는 배율로 확대한다. [build191 실패와 재현](qa/0.80-build191.md).
- build192의 약 700pt 실제 앱에서 `P → Return`과 `Tab → 연결 편집`을 다시 확인했다. 전체 Swift 1084개·MCP 39개·agent kit 9개, 내장 스피커 무음 AudioQueue native 5개, arm64 빌드·서명을 통과했다. 실제 청취와 영상·전체 제작 gate는 남아 있어 출고하지 않는다. [검증 기록](qa/0.80-build192.md).
- QA 앱에서만 Mac Studio 스피커를 선택해 동봉 데모의 Play/Stop을 두 번 실행했고 재생 시계·출력 정리·재연결을 확인했다. 시스템 기본 Scarlett은 그대로였으며 실제 소리의 청취 판정은 남아 있다.
- 같은 출력으로 섹션 루프 재생 중 Bach 데모 MIDI 노트의 세기를 127→100으로 편집하고, 정지·저장·재열기 후 같은 노트와 값이 유지됨을 확인했다. 실제 소리의 변화를 청취한 증거는 아니다. [QA](qa/0.80-build192-live-midi.md).
- 같은 출력으로 짧은 MP4를 실제 앱에서 저장했다. 독립 판독은 12.499초·373개 프레임·nonzero stereo 오디오를 확인했다. 좁은 창의 프레임 간격 P95는 53ms여서 움직임·장시간/1080p 품질은 계속 개선 대상이다. [QA](qa/0.80-build192.md).

## 0.80.0 · build191 — 개발 중

- 선택한 IN/OUT 포트가 축소 상태에서도 표시되도록 하고 `P`/`Tab` 이동 시 포트가 편집 가능한 크기와 화면 안에 들어오도록 카메라를 조정했다. 더블클릭 포커스는 가까운 위성을 우선 보여 먼 수동 배치 노드 하나가 중심 궤도를 과도하게 줄이지 않는다.
- 내장 AI 작업을 위한 앱 내부 RunLease·대상별 권한·경로 없는 응답·중단 후 늦은 bounce 차단 경계를 준비한다. 계정 로그인, Codex 실행, 사용자 대화 UI와 연결된 제품 기능은 아직 아니다.
- 연결된 Scarlett의 세대·호환성은 미확정이다. 구형 장치의 출력 성공 자체는 0.80 출고 조건에서 제외하고, 명시적 내장 출력의 반복 재생·실제 청취와 출력 실패 후 앱 복구를 검증한다.

## 0.80.0 · build190 — 개발 중

- build189의 실제 데모 키보드 이동에서 출력 궤도의 아래 위성이 잘리는 문제를 수정했다. 선택 궤도 주변의 직계 위성 클러스터를 함께 맞추고, 멀리 수동 배치한 노드가 극단적인 축소를 강제하지 않는다. [같은 경로 native 재검증](qa/0.80-build190.md)에서 하단 출력 서클까지 보였다.
- 내부 Codex 프로토콜의 turn ID·승인 요청 순서, 이전 연결 writer, 늦은 중단 응답, 작은 텍스트 조각 누적을 독립 리뷰 후 보강했다. 소유 turn을 판정할 수 없는 요청은 거절하며 앱 로그인·모델 호출·AI 작업 권한은 아직 연결하지 않았다.

## 0.80.0 · build189 — 개발 중

- 키보드로 선택한 궤도와 일부 직계 위성·펼친 그룹 멤버를 함께 보여주는 첫 후보를 만들었다. 실제 `f0r h3r` 출력 궤도에서 아래 위성이 잘려 R80-01 QA에 실패했다. [native 재현](qa/0.80-build189.md).
- 앱 내 계정 대화의 Foundation 기반 Codex App Server 프로토콜 코어를 내부 테스트 대상으로 추가했다. 이 빌드에서는 첫 후보였으며 후속 build190 독립 리뷰에서 이벤트 순서·권한 귀속 경합을 찾아 수정했다. 계정 로그인·모델 호출·AI RunLease는 제공하지 않는다.
- 명시적 내장 출력의 build188 무음 native 테스트를 5회 연속 25/25 통과하고 timeout·잔류 worker 0을 확인했다. 이는 실제 청취나 Scarlett 출력 성공이 아니다. [증거](qa/evidence/r80-build188-native-repeat.json).

## 0.80.0 · build188 — 개발 중

- build187의 실제 앱 루프 종료에서 잔향이 끝난 직후 queue 정리와 장치 재검사 timer가 경합해 출력 상태 오류를 표시한 문제를 수정한다. 마지막 buffer가 끝난 경우 완료 callback을 기다리고, 장치 오류는 계속 실패로 처리한다.
- 격리 앱에서 같은 섹션 루프 2회차·해제·잔향 자연 종료를 오류 없이 확인했다. 약 15초 MP4의 441개 decoded 프레임과 nonzero AAC 오디오를 확인했다. 시스템 기본 Scarlett의 초기화 대기와 실제 물리 청취는 아직 열린다. [QA](qa/0.80-build188.md).

## 0.80.0 · build187 — 개발 중

- 키보드로 서클을 선택할 때 중심점만 보이는 경우에도 궤도 전체를 작업 영역에 맞춘다. 작은 궤도는 필요한 만큼만 이동하고 큰 궤도는 들어갈 때까지 축소한다.
- Scarlett가 기본 출력인 Mac에서 AVAudioEngine의 장치 선택 전 초기화 대기를 분리했다. 자동 복원한 내장 기본 출력 조건에서는 실제 출력 worker의 무음 시작·clock·정지가 성공했고, 기본 Scarlett를 유지한 AudioQueue 명시적 내장 출력 probe도 성공했다. 이 무음 진단만으로 곡 재생의 청감을 입증하지는 않는다.
- 명시적으로 고른 장치의 곡·섹션 재생에 AudioQueue 출력 경로를 연결했다. 내장 스피커의 무음 QA에서 실제 helper와 host의 0.1초·3초 파일 재생, 정지, 루프 교체·잔향 종료의 샘플 경계를 확인했다. 출력 시계 오류·진행 정지는 실패로 처리한다. 시스템 기본 Scarlett, 최종 앱의 실제 청취·녹화는 아직 열린다.
- 실제 앱의 f0r h3r 섹션 루프는 2회차 진입과 잔향 종료 전까지 진행했으나 종료 순간 출력 상태 오류가 재현됐다. 이 빌드는 정식 0.80 출시가 아니다.

## 0.80.0 · build186 — 개발 중

- MIDI 가져오기와 오디오 렌더·바운스·내보내기의 비동기 결과를 작업 ID·문서 revision에 묶어 취소 또는 문서 변경 뒤의 늦은 결과가 반영되지 않도록 보강했다. MIDI 가져오기 중 배치만 바뀐 경우에도 이전 프로젝트 사본으로 덮어쓰지 않는다.
- WAV 기록과 출력 레벨 검사를 취소 가능한 worker에서 작은 청크로 처리한다. 중단된 작업의 임시 WAV는 제거하고, 앱 재시작 시 전용 바운스 폴더의 버려진 임시 파일을 정리한다.
- 곡 궤도의 키보드 이동을 섹션 시작 시각에 맞춘다. 그룹으로 묶인 섹션도 그룹 서클을 통해 제 순서에 탐색하고, 접힌 그룹에서 Return을 누르면 펼친 뒤 첫 섹션에 진입한다.
- 이 빌드는 QA 중인 개발 후보이며 정식 0.80 출시가 아니다. 재생 출력의 간헐적 timeout, 최종 native 제작·취소·청취 검증과 영상 검증이 남아 있다.

## 0.80.0 · build185 — 개발 중

- MIDI·오디오 정밀 편집기를 열고 재생을 시작할 때 카메라 팔로우를 일시 중지해 같은 캔버스의 편집 화면을 유지한다. 설정·연결·가져오기 패널은 이 동작에서 제외한다.
- 실행 중인 에이전트 open/import/render 작업을 jobID로 취소하는 `circlr_cancel_job`을 추가하고 콘솔의 작업 취소 버튼에 연결했다. DAW 전체 `stop`과 구분한다. AI 세션의 후속 쓰기 권한 철회는 아직 구현되지 않았다.
- build185는 QA 중이며 정식 출시가 아니다. 재생 출력의 간헐적 timeout과 최종 native 검증은 계속 열린다.

## 0.80.0 · build184 — 개발 중

- 녹화 준비 과정에서 출력 오류가 나거나 이전 준비 작업이 늦게 끝나도 writer와 재생 요청을 정리하고, 새 녹화의 writer를 건드리지 않도록 비동기 수명 검사를 보강했다.
- 재생 중 활성 섹션 라벨과 감상 모드 포커스 표식을 native 화면에서 확인했다. 물리 청취, 영상 파일, 제작·저장 동선과 장시간 안정성은 별도 gate로 남긴다.

## 0.80.0 · build183 — 개발 중

- 재생 팔로우 중 현재 섹션 이름을 궤도 가까이 우선 배치하고, 텍스트 없는 감상 모드에서는 활성 궤도에 비문자 포커스 표식을 그린다.
- 녹화 준비 중 취소하면 첫 프레임 인코딩이 끝났더라도 MP4를 게시하지 않고 임시 파일을 폐기한다.
- 사용자 우선순위에 따라 [0.80 핵심 기능 gate](docs/releases/0.80.0.md)와 [0.90 반복·장시간 검증 계획](docs/releases/0.90.0.md)을 갱신했다. 이전 출력 timeout의 원인은 미확정이며 이 빌드는 정식 출시가 아니다.

## 0.80.0 · build182 — 개발 중

- 고밀도 재생에서 현재 화면에 걸치는 연결 수를 기준으로 비선택 케이블 몸체의 밝기와 신호 표시 수를 낮춘다. 선택 케이블이 인접한 선택·hover 경로보다 우선 보이도록 하며 연결 데이터·hit/접근성 경로는 유지한다.
- 상단의 녹화·감상 버튼을 인접한 그룹으로 유지하고, 영상 준비·녹화·저장 중 상태를 버튼 문구와 접근성 이름으로 구별한다.
- 공식 OpenAI 문서상 `codex app-server` 명령이 experimental·production 미지원이므로 공개 앱의 계정 대화 기능은 G0에서 보류했다. [0.80.0 계획과 gate](docs/releases/0.80.0.md). build182는 정식 출시가 아니다.
- 최종 소스의 전체 Swift 테스트 1007개·3개 skip·실패0, release 앱 빌드·서명, 약 700/900/1300pt 상단과 정지 상태 감상 모드의 native QA를 확인했다. 첫 테스트의 비재현 실패2개와 Scarlett/내장 스피커 양쪽의 출력 준비 timeout, 재생 중 화면·녹화·실제 FPS 미검증을 [QA 기록](docs/releases/0.80.0.md)에 남겼다.

## 0.80.0 · build181 — 개발 중

- 0.70.0 정식 출고 소스를 기준으로 별도 브랜치에서 시작했다. 첫 UI 작업은 축소된 궤도 화면의 비선택 연결선·화살표·포트 밀도를 낮추고 선택·호버·재생 경로를 강조한다. 음악 데이터·연결 hit geometry·접근성 항목은 유지한다.
- AI 계정 콘솔, 반응형 상단·녹화 상태, 고밀도/가로·세로 native QA는 [0.80.0 계획](docs/releases/0.80.0.md)의 후속 작업이다. build181은 정식 출시나 GitHub Release가 아니다.

## 0.70.0 · build180 — 2026-09-23

- 재생 프레임 경로에서 라벨 context·가시 서클·포트 연결 방향을 그리기당 한 번 계산하고, 기본 팔로우의 불필요한 탐색을 제거했다.
- 동일한 f0r h3r 첫 섹션·약 1280×1256 캔버스에서 시각 업데이트 콜백 15.27→56.82Hz, build172 화면 그리기 콜백56.30Hz를 측정했다. 이 값은 실제 표시 FPS가 아니다. build172는 포트 선택 시 라벨 겹침 회귀도 수정했다.
- 영상 캡처의 중복 그리기를 제거하고, 캡처 프레임을 녹화 중 화면에 재사용하며, 라벨 측정 캐시를 유효 폭과 512개 상한으로 관리한다. 메인 루프 timer task 대기와 프레임 캡처 비용을 계측한다.
- build179의 1080×1206pt 세로 캔버스에서 녹화 없는 재생 업데이트57.43Hz를 측정했다. 무간섭 약29초 녹화 MP4는 871프레임·평균30.01fps·2프레임 초과 간격0개였다. MCP snapshot을 녹화 중 호출하면 약350ms 공백이 생기므로 두 조건을 구분한다. 실제 표시 FPS와 장시간·가로 화면·AV 중간/끝 동기 등 정식 릴리스 gate는 아직 열려 있다. [계획과 증거](docs/releases/0.70.0.md).
- build180에서는 감상 모드 버튼을 상단 녹화 버튼 옆에 배치했다. 세로·가로·1280pt 경계의 native UI에서 진입·복귀와 겹침 여부를 확인했다. 가로 창의 1920×942 MP4는 64.93초·1939 decoded 프레임·평균29.86fps·2프레임 초과 공백0개·연속 동일 이미지0개였다. 1920×1080·10분 녹화와 실제 표시 FPS는 아직 검증하지 않았다.
- 사용자 지시에 따라 정식 출시하되 실제 표시 FPS, 정확한1080p·10분, AV 중간/끝 동기, 실제 파일 청취, 고밀도·루프·최소화 장시간 시나리오는 미검증으로 공개한다. [한영 노트](docs/releases/0.70.0-notes.md) · [QA](docs/releases/0.70.0-qa.md).

## 0.60.0 · build170 — 2026-09-12

- 내장 프리셋12개를 기존 음색 검색 및 MCP sounds에 통합. 기존 patch 보존·Undo 지원.
- 새 Drive4×oversampling, 과거 nil/1/2 렌더 보존, factory→기본 음색 선택 회귀 수정.
- f0r h3r v6의 patch·articulation·구간별 필터 오토메이션, 클래식3곡 유지.
- Twelve factory patches, compatible oversampled Drive and the refined v6 demo. [한영 노트](docs/releases/0.60.0-notes.md) · [QA](docs/releases/0.60.0-qa.md).


## 0.50.1 — build169 · 2026-09-11

- 역할별 서클 크기와 방사형 기본 배치, 소스에서 출력까지 넓어진 신호 흐름 간격을 적용했다.
- 자동 정렬 3종(방사형·가로·세로)을 우클릭·상단 도구·명령 검색에서 제공한다. 선택 범위를 표시하고 음악 시간·연결을 보존하며 한 번 Undo로 복원한다.
- 서클 이름이 다른 곡·섹션 궤도를 가리지 않도록 라벨 충돌 대상을 확장했다.
- README 스크린샷을 최종 빌드에 맞춰 갱신하는 운영 규칙을 추가했다.
- MCP 서버 회귀 검사의 오래된 도구 수 기대값을 실제 26개 카탈로그와 필수 도구 검사로 갱신했다.
- [계획](docs/releases/0.50.1.md) · [QA](docs/releases/0.50.1-qa.md) · [한영 노트](docs/releases/0.50.1-notes.md).

## 0.50.0 — build166 · 2026-09-11

- 시간 궤도 밖으로 섹션·신호 노드를 펼치고, 자손을 담기 위한 부모 확대·재귀 축소를 제거했다.
- 궤도 배치와 기존 freeform 저장 좌표를 구분하고 시간 anchor·소속·음악 데이터를 유지한다.
- 가로·세로 창 너비에 맞춘 상단 조작부·도구 메뉴·하단 콘솔 배치를 적용했다. 실제1440·1024·900·700pt 너비 및 긴 제목을 확인했다.
- 한·영 README와 macOS 설치 안내에 ad-hoc 서명·미공증 상태, 체크섬 확인 및 ‘그래도 열기’ 절차를 추가했다.
- `v0.50.0` 정식 GitHub Release 게시 및 다운로드 SHA256 검증 완료. [한영 노트](docs/releases/0.50.0-notes.md) · [검증 기록](docs/releases/0.50.0-qa.md).

## 0.40.0 — build162 · 2026-09-11

- 가시성을 우선해 궤도·연결·라벨·IN/OUT·선택·작업 상태와 MIDI/오디오 시간 표시를 개선했다.
- 텍스트 없는 감상 모드와 곡/섹션/고정 서클 팔로우, 구도·줌 전환 설정을 GUI·MCP에 연결했다.
- 연속 PCM 루프, 실행 중 안전한 경계 전환, 해제 후 잔향 종료를 구현했다. 오래된 취소 요청과 긴 섹션의 ACK timeout 결함을 수정했다.
- bounded 직접 영상 캡처·background 인코딩과 루프/교체/종료 오디오 동기화를 추가했다.
- 새 곡/템플릿 시작 화면, 취소 가능한 background demo copy와 안전한 사본 관리, 최신 f0r h3r v5 및 권리 고지된 클래식 MIDI3곡을 동봉했다.
- 코드·자동 검사·offline PCM/MP4 검증을 수행했다. 실제 GUI·청취·FPS·한글 IME는 이번 버전의 사용자 요청에 따라 USER_WAIVED다. [검증 기록](docs/releases/0.40.0-final-qa.md).

## 0.30.0 — build161 · 2026-09-11

- 공개 MIT 프로젝트로 전환하고 데모 별도 이용 조건·기여 안내·한영 문서를 갱신했다. 앱에도 MIT와 권리 고지를 포함한다. build161의 helper 5개와 서명 제거 후 메인 실행 코드는 build160과 동일하다.
- 최신 f0r h3r v5에 섹션·악기 역할 컬러를 적용하고 CC0 음원 6개 및 출처 고지와 함께 앱에 동봉했다. 음악/음원은 v4와 동일하다.
- 파일 메뉴에서 번들 원본을 보존하는 새 데모 작업 사본을 연다. 패키징 시 데모 inventory·checksum·상대 미디어 경로를 검증한다.
- 사용자가 한글 IME 및 남은 native QA를 유예하고 정식 게시를 승인했다. 유예 항목은 PASS로 처리하지 않으며 [기록](docs/releases/0.30.0-final-qa.md)에 보존한다.

## 0.30.0 개발 후보 — build159

- 상단 서클 추가 메뉴에 어두운 글자·아이콘과 민트 배경을 명시하고 plain 메뉴 버튼 스타일을 적용해 다크모드 대비를 수정했다. 최소 높이 30pt와 드롭다운 표시를 제공하며 기존 생성 동작을 유지한다.
- 앱 빌드·1019×768 다크 화면·메뉴 열기/복귀·단일 접근성 메뉴 버튼·독립 검토를 통과했다.
- 기존 배포 preview는 build158이며 정식 0.30.0 완료나 새 GitHub Release를 의미하지 않는다.

## 계획 — 섹션 팔로우 줌 전환

- 0.40.0 R40-06에 줌아웃→다음 섹션 이동→줌인 연출과 끄기/은은하게/강조 설정을 추가했다.
- 도착 배율, 짧은 섹션·루프의 과도한 줌 방지, 수동 조작·Stop 취소, 동작 줄이기와 실제 녹화 QA를 정의했다. 시간·배율은 초기 조정안이다.
- 계획 문서만 변경했으며 앱 구현·버전 변경·새 릴리스는 없다.

## 계획 — 공개 MIDI·스템 데모 라이브러리

- 0.40.0 R40-07에 최소 3곡·목표 4곡, 0.60.0 f0r h3r 포함 최대 5곡 계획을 추가했다.
- Public Domain MIDI 3곡과 CC0 stems 후보의 공식 출처·재배포 조건, 곡별 편곡·계층·튜토리얼·청취/배포 QA를 [상세 계획](docs/releases/demo-library-plan.md)에 기록했다.
- 이번 변경은 조사·문서만이며 음원 취득·편곡·앱 탑재·버전 변경·새 릴리스는 없다.

## 계획 — 재생 팔로우 대상 선택

- 0.40.0 R40-06에 현재 곡·현재 섹션·지정 서클·팔로우 끄기를 추가하고, 대상 전체 맞춤/현재 배율 유지를 별도 구도 설정으로 정의했다.
- 수동 탐색 후 재개, 재사용 섹션 식별, 대상 삭제·빠른 전환 및 감상 모드·녹화·MCP 일치 검증을 [로드맵](docs/releases/roadmap.md)에 반영했다.
- 이번 변경은 계획 문서만이며 앱 구현·버전 변경·새 릴리스는 없다.

## 계획 — 텍스트 없는 감상 모드

- 0.40.0 R40-05에 재생 중 이름·눈금·도구 문구·콘솔·버전을 숨기고 서클·시그널 흐름을 남기는 감상 모드를 추가했다.
- 단축키/Esc 복귀, 초안·선택 보존, 접근성 및 화면 녹화에 동일 적용하는 완료 조건을 [로드맵](docs/releases/roadmap.md)에 정의했다.
- 이번 변경은 계획 문서만이며 앱 구현·버전 변경·새 릴리스는 없다.

## 계획 — 화면 녹화 프레임 끊김 개선

- 사용자 제보를 원인 미확인 결함으로 기록하고 0.40.0의 R40-04에 우선 진단·개선을 배치했다.
- 캡처/인코딩 병목·프레임 간격·누락·루프 경계·AV 동기 및 저장 MP4 실재생 검증을 [로드맵](docs/releases/roadmap.md)에 추가했다. 1080p/30fps는 검증 목표이며 달성 결과가 아니다.
- 0.90.0의 영상 확장과 기존 녹화 결함 수정을 구분했다. 이번 변경은 계획 문서만이며 구현·새 릴리스는 없다.

## 계획 — 0.40.0 루프 재생·시작 화면

- 0.40.0의 우선 작업으로 전체 곡/선택 섹션의 끊김 없는 루프 재생과 새 곡·템플릿·데모 시작 화면을 추가했다.
- 루프 경계·범위 전환·잔향/지속음·실제 청취, 시작 화면의 파일 열기/복구·취소·원본 보존 완료 조건을 [로드맵](docs/releases/roadmap.md)에 정의했다.
- 기존 녹음 범위를 유지하고, 데모 로더는 0.40.0, 발매 수준 f0r h3r 갱신은 0.60.0으로 구분했다. 구현·앱 버전 변경·새 릴리스는 없다.

## 0.30.0-preview.1 — build158 평가판

- 현재 개발 브랜치를 `main`으로 통합하고 첫 GitHub prerelease를 등록한다. [한영 노트](docs/releases/0.30.0-preview.1-notes.md).
- Apple Silicon 앱·5개 오디오 helper·에이전트 키트를 ZIP과 SHA256으로 제공한다. 상단 로고 아래에 Info.plist의 버전·build를 표시하며 build158로 패키징했다.
- 실제 오디오·IME·일부 통합 QA가 남아 있는 평가판이다. 0.30.0 마일스톤과 정식 태그는 미완료 상태로 유지한다.

## 문서 — 한국어·영어 README 및 GitHub Release 절차

- README를 제품 소개·실제 실행 화면·빌드·기본 조작·기여 안내로 재구성하고 `README.ko.md`를 추가했다. 누적 build 기록은 `docs/history/readme-build157.md`에 보존했다.
- 문서·소스 안내와 기여 지침, build157의 앱 창 스크린샷 2개 및 촬영 범위를 추가하고 MCP 연결 예시의 개인 경로를 제거했다.
- 완료 버전은 한·영 노트·검증 패키지·SHA256을 포함한 GitHub Release 등록과 원격 검증까지 수행한다. 문서 수정과 미완료 build는 릴리스하지 않는다. 앱 버전·build·소스 동작 변경은 없다.
- 한·영 GFM 렌더링·실제 이미지 표시·상대 링크·독립 문서 검토를 확인했다. 참고 구성: [LMMS](https://github.com/LMMS/lmms), [OBS Studio](https://github.com/obsproject/obs-studio), [ComfyUI](https://github.com/Comfy-Org/ComfyUI).

## 0.30.0 — 개발 중, 미출고

- MIDI 파일 접근·읽기·파싱을 백그라운드 작업으로 옮기고 취소 및 늦은 결과 보호를 연결했다. 샘플 라이브러리 접근 권한은 읽기 작업 종료까지 유지한다.
- 페달 포커스 요청을 keyDown 전달 전에 재확인하고 스텝 Tab·Shift-Tab을 수치 필드에 연결했다.
- 재현 가능한 12초 QA 곡·Core 계약 검사·실제 출력 없는 helper lifecycle 및 snapshot 도구를 추가했다.
- Swift 678개·MCP 29개 통과, build155에서 MIDI 가져오기·Undo, 효과 포함 바운스·원본 복원, GUI/MCP 결과 일치와 저장·재실행을 확인했다. build157에서 높은 콘솔의 페달 필드 가림·Tab 자동 노출을 수정하고 오류·Escape 복구를 재검증했다.
- 전체 QA·실제 출력·IME 미완료. [검증과 남은 조건](docs/releases/0.30.0-qa.md). 버전 태그와 사용자 앱 교체는 아직 없다.

## 개발 운영 — 버전 단위 완료 프로세스 도입

- 0.20.0 기반에서 0.30.0·0.40.0 순으로 진행할 기능 묶음과 [릴리스 절차](docs/releases/README.md)를 정의했다.
- 0.30.0의 작업 8개·필수 QA 10개·의존/담당 파일·완료 기준과 후속 로드맵, 재사용 양식 및 저장소 AGENTS.md를 추가했다.
- 독립 계획 검토의 gate 순환 지적을 수정하고 재검토 PASS, 링크·소유 경로·문서 diff 검증을 통과했다. 이번 변경은 제품 버전 증가·구현 완료·태그 발행·앱 교체가 아니다.

## build152 — 페달 그래프 준비 중 포커스 요청 유지

- 그래프 mount 전 취소되던 요청을 유지하고 update에서도 기존 요청을 재시도한다. 기존 대상·초안·창 보호 검사는 유지한다.
- 별도 native QA에서 모드 전환·재열기 후 Home/End·Tab과 저장 데이터 보존을 확인했다. 전환 직후 즉시 입력·IME 등은 남은 범위다. [변경과 확인 절차](docs/179-pedal-focus-mount.md).

## 문서 — 2026-09-11 실사용 인수인계

- build151 기준 개발 현황·검증 한계·실사용 체크리스트·후속 업데이트 우선순위·문제 제보 양식을 [통합 문서](docs/178-development-handoff.md)에 정리했다.
- 기능 확장을 멈추고 실사용 문제 중심으로 수정하는 운영 방침을 반영했다. 앱 버전 변경·새 테스트·설치 앱 교체는 없다.

## 검증 완료 — build151 서스테인 직접 편집

- 같은 캔버스 페달 mode·초기값/이벤트 편집·명시적 MCP sustainChange와 입력/선택 보호를 연결했다. native 편집·오류·Undo/Redo·scope 복귀와 Release 89.22초를 확인했다.
- Swift 초기 686개 중 685개 통과·fixture 누락 1개 실패 후 관련 저장 복원 3개 재검사 PASS, Python MCP 29개 PASS다. 최종 data 감사는 PASS_DATA_ONLY, UI 16쌍은 PASS_WITH_SCOPE_LIMITS다.
- 실제 오디오·모든 scope native 편집·자동 focus 완료는 아니다. [기록](docs/177-midi-sustain-editing.md).

## 검증 완료 — build150 MIDI 서스테인 파일 연결

- CC64 raw·CC121·preserve/omit와 GUI/MCP 가져오기 preview를 연결했다. midiSustainImport: 1과 명시적 export 끝·합성 pedal-up을 사용한다.
- Swift 666개·MCP 24개·Release 86.84초와 native preserve import·종료 off export·Undo/Redo를 확인했다. 재열기 manifest 독립 비교도 PASS했으며 GUI drum/cancel·페달 직접 편집·물리 연주는 미검증이다. [기록](docs/176-midi-sustain-file-workflow.md).

## 개발 중 — build149 이후 내장 신스 서스테인 DSP

- 원본 Note 길이를 유지하면서 페달에 따른 key-off 보류·해제와 source/반복 격리를 연결했다. 내장 신스 engine1/2/3의 오프라인 렌더를 지원한다.
- 전체 Core+선별 Audio 635개·실패0개, 스테레오 WAV 바운스/저장/복원 2개 추가 확인, Release82.91초 및 독립 C/Swift 리뷰를 통과했다.
- 당시 SMF parser·GUI/MCP·실제 장치 연주는 후속 범위였으며 파일 연결은 위 build150에서 진행한다. 설치 앱은 교체하지 않았다. [검증 기록](docs/175-midi-sustain-render.md).

## 개발 중 — build149 이후 MIDI 서스테인 저장·컴파일

- optional sustain과 schema7, 공유 패턴·테이크 복사, typed import의 offset·길이·이벤트 예산을 연결했다. 반복별 bend/sustain은 하나의 source stream으로 준비한다.
- 당시 활성 페달의 미지원 렌더와 원본 raw를 버릴 MIDI 저장을 거절하도록 연결했다. 이후 신스 DSP 지원은 위 최신 기록에 구분했다. all-off PCM·기존 pitch 경계와 비기여 route 보관을 유지했다.
- 전체 Core+선별 Audio 618개·실패0개, 실제 패키지 저장/재열기와 독립 소스 리뷰를 확인했다. 당시 페달 DSP·SMF parser·GUI/MCP는 후속 범위였으며, DSP 구현은 위 최신 기록에 구분했다. [검증 기록](docs/174-midi-sustain-storage.md).

## 개발 중 — build149 이후 MIDI 서스테인 Core 기초

- 독립 CC64 sequence·raw 상태·순서 보존·전체 입력 검증과 상태 조회를 추가했다. 같은 beat의 pedal-up/down 이벤트를 합치지 않는다.
- 신규 Sustain 6개와 기존 PitchBend 8개 검사, 총 14개·실패 0개 및 독립 소스 리뷰를 확인했다. 앱 build·프로젝트 schema는 유지한다.
- 당시 저장·컴파일·DSP·SMF·GUI/MCP 연결은 [후속 계획](docs/173-midi-sustain-plan.md)이었다. 저장·컴파일의 후속 구현은 위 최신 기록에 구분했다. 앱의 페달 지원·native 화면·실제 연주를 검증한 단계는 아니다.

## 검증 완료 — build149 오토메이션 안내와 compact 편집

- 낮은 화면의 plot·세로 controls 병렬 배치와 줄바꿈 안내를 연결했다. controls wheel의 canvas zoom 전달과 넓은 grid 높이 감소를 수정했다.
- Release 48.72초·source/package 감사와 native draft resize·invalid 보호·범위 맞춤·wheel·r233 재시작 및 data 감사를 확인했다. 최종 UI 감사는 22쌍 PASS_WITH_EXPLICIT_LIMITS·findings 0개다.
- 추가 unit/full suite와 폭 600 미만·모든 입력·실제 momentum hardware·물리 I/O는 미실행이다. [기록](docs/172-automation-guidance.md).

## 검증 완료 — build148 신스 오토메이션 직접 이동

- cutoff/resonance 버튼으로 같은 주소·parameter·scope의 곡선 편집을 연다. 유효 수치 초안은 한 번 확정하고 invalid/빈 이름은 이동을 차단한다.
- 최종 12pt 후보 Release 48.28초·package/source 검토, native 직접 진입·scope별 곡선 불변·Undo를 확인했다. 재시작 전체 manifest는 일치했고 data 감사는 PASS_WITH_ADDITIONAL_METADATA_CHANGE다. UI 감사는 PASS_WITH_EXPLICIT_LIMITS다.
- 추가 unit/full suite는 실행하지 않았으며 미지원 host/stale는 소스 검토 범위다. [기록](docs/171-synth-automation-shortcuts.md).

## 검증 완료 — build147 신스 resonance 오토메이션

- v2/v3 내장 신스의 raw 0…0.9·0…90% 곡선을 schema6·DSP·GUI/MCP에 연결했다. cutoff 동시 적용과 linear/hold를 지원한다.
- Swift 전체 Core+선별 Audio 568개·MCP 22개와 Release 94.83초, native 값/오류·Undo/Redo·CPU 바운스/복원·앱 재시작 r219를 확인했다. data 독립 감사는 PASS_DATA_ONLY이며 UI 감사는 PASS_WITH_EXPLICIT_LIMITS이며 DSP 읽기 전용 검토도 PASS했다.
- 지원 대상은 v2/v3 내장 신스로 한정한다. 전체 Audio suite·모든 폭·물리 청취는 미검증이다. [기록](docs/170-synth-resonance-automation.md).

## 검증 완료 — build146 낮은 오디오 화면 배치

- 낮은 높이·600 이상 800 미만 폭에서 같은 subtree의 파형과 수치를 나란히 배치하고 다른 조건은 기존 stack을 유지한다.
- Release 48.74초·source/package 감사, native 일반/공유 최초 4수치·파형·action과 Tab·invalid 보호·편집/Undo를 확인했다. data 감사는 PASS_DATA_ONLY, 최종 UI 감사는 PASS_WITH_SCOPE_LIMITS다.
- binding·음악 계약은 유지했으며 전체 suite·모든 폭·Shift-Tab/drag/resize-draft·물리 I/O는 미실행이다. [기록](docs/168-audio-compact-layout.md).

## 검증 완료 — build145 트랙 경로 배치

- 약 680px 폭의 긴 트랙명·역할 7개를 트랙 행과 줄바꿈 역할 영역으로 나누고 넓은 화면은 한 행을 유지한다.
- Release 48.43초·소스/패키지 감사와 native 역할 이동·chooser·공유 오디오 Tab·MIDI 복귀를 확인했다. data 감사는 PASS_DATA_ONLY, 최종 UI 감사는 PASS_WITH_SCOPE_LIMITS다.
- compact 오디오의 최초 수치 가시성과 모든 폭·invalid draft·VoiceOver·물리 I/O는 완료하지 않았다. [기록](docs/167-track-route-density.md).

## 검증 완료 — build144 공유 오디오 상단 밀도

- 공유 picker 행에 scope 안내를 합치고 아래 중복 행을 제거해 최초 수치 4개의 가시성을 개선했다. 일반 오디오·파형 높이·키보드 guard는 유지한다.
- Release 46.26초·package 감사와 native 최초 화면·Tab·clip 전환·Undo/Redo·r208 저장/재열기를 확인했다. UI 12쌍은 PASS_WITH_SCOPE_LIMITS, state 4개 캡처는 PASS다.
- 추가 unit/full suite는 실행하지 않았다. 첫 Tab 스크롤·좁은 폭·tooltip·VoiceOver·물리 I/O의 한계를 구분한다. [기록](docs/166-shared-audio-editor-density.md).

## 검증 완료 — build143 오디오 history 작업 위치

- 일반·공유 오디오의 Undo/Redo에서 조건부로 파형과 focus를 복원하며 다른 노드 탐색은 유지한다. 공유 branch 요청과 이전 clip view의 조기 focus 소비를 수정했다.
- 관련 43개 검사·최종 Release 45.24초·package 감사와 native 복귀/Tab·r198 재시작을 확인했다. 최종 state 5개 캡처는 PASS, UI 15쌍은 PASS_WITH_SCOPE_LIMITS다.
- 공유 첫 수치 가시성·모든 scope/빠른 입력·장치 I/O·전체 suite는 완료하지 않았다. [기록](docs/165-audio-edit-history-return.md).

## 검증 완료 — build142 가져오기와 오디오 동선

- 파일·대상을 고정하고 트랙 목록을 앞에 배치했다. 단일 import는 이전 pitch/공유 범위를 이어받지 않고 이번 use의 piano로 연다. 오디오 action row·파형·수치 접근도 개선했다.
- Release 45.66초·관련 49개 검사·패키지 독립 감사와 native import/취소·다중 트랙·invalid 시작 위치·오디오 split/Undo를 확인했다. state 독립 감사 10개 캡처는 PASS, UI 16쌍은 PASS_WITH_SCOPE_LIMITS이며 r182 재열기도 일치했다.
- 전체 suite·물리 I/O·긴 파일명·모든 정책/키보드 조합은 미실행이다. [기록](docs/164-import-and-audio-workflow.md).

## 검증 완료 — build141 편집 포커스 의도

- attach와 mode entry를 공통 요청으로 통합하고 실제 창 활성화 시 기존 요청을 재시도한다. 빠른 전환에서 이전 콜백이 최신 focus를 덮던 경계를 개선했다.
- Release 48.10초·warning 0개·관련 39개 검사, 두 출발 상태의 rapid r170/0점 보존·키보드·입력 오류·저장 view 재시작을 확인했다. native 31쌍·data 7개 캡처·package 최종 독립 감사도 PASS했다.
- 모든 timing 조합·create/import 경로·물리 I/O를 새로 검증한 결과는 아니다. [기록](docs/163-editor-focus-intent.md).

## 부분 개선 검증 — build140 편집 진입 포커스

- 현재 mode/content type에 맞는 요청 기반 focus로 MIDI·오디오 진입과 키보드 조작을 개선했다. invalid 입력과 console 편집을 보호한다.
- 최종 Release 46.68초·기반 39개 검사·native 방향키/Tab/Enter와 Undo를 확인했다. 빠른 모드 전환의 기존 async attach focus 경쟁은 미해결이며 다음 우선 수정이다. 최종 state·재시작 감사는 PASS, UI 감사는 `PASS_WITH_KNOWN_RACE`다. 전체 포커스 완료로 선언하지 않는다. [기록](docs/162-editor-navigation-focus.md).

## 검증 완료 — build139 서클별 편집 화면 기억

- 첫 방문 기본 화면·재방문 scope별 기억·명시적 스텝 요청 우선을 연결했다. invalid canvas 이동 재현을 수정해 잘못된 수치·이름을 보존하고 이동을 차단한다.
- 최종 Release 47.96초, 초기 workspace 21개와 최종 Number/Name 18개 검사, native 왕복·r166 음악/자산 불변·재시작을 확인했다. 이전 실패 후보는 최종 통과와 구분해 기록한다.
- 실제 I/O와 source 변경·clamp·scope 전체 조합은 이번 native 검증이 아니다. [기록](docs/161-circle-editor-memory.md).

## 검증 완료 — build138 섹션 설정 왕복

- 원래 child 노드·모드·viewport 복귀와 앨범 대상 label·설정 단축키를 연결했다. 정상 설정 변경과 invalid/stale·삭제 경계를 구분하고 길이 축소·pitch source 변경에 맞춰 복귀한다.
- Core 21개·Release 50.20초, native MIDI/오디오/오토메이션 왕복·오류·Undo·r166 재시작을 확인했다. 실제 hardware·VoiceOver·IME·다른 document 중복 ID 실행은 미검증이다. [기록](docs/160-section-settings-return.md).

## 검증 완료 — build137 섹션 길이 출처와 복귀

- 원본/이번 use 길이를 구분하고 1…4096 범위와 원본 길이 복귀를 연결했다. 잘못된 축소·stale 대상은 음악을 바꾸지 않고 거절한다.
- Core 7개·Python 17/28개와 native GUI/MCP·Undo·r150 재시작 및 독립 artifact 감사를 통과했다. 4자리 숫자 가시성 보완 후 Release 48.47초·4096/4097 경계·r156 재시작도 확인했다. [기록](docs/159-section-length-source.md).

## 검증 완료 — build136 MIDI 공통 파일 작업

- 네 MIDI 모드에 직접 가져오기·저장·바운스와 tail을 제공하고 공통 단축키를 연결했다. 작은 창에서 동작군을 줄바꿈한다.
- 파일 작업 전에 실제 수치 초안을 확정하고 invalid/stale 입력을 차단한다. raw 12288의 실제 SMF 저장·취소 복귀·바운스/복원·재시작을 확인했다.
- Core 13개·warning 없는 Release 49.06초와 native UI 감사를 통과했다. build135 전체 회귀를 이번 검사로 다시 세지 않는다. 일부 빠른 연속 조작·모든 모드의 전체 실행·물리 청취는 미검증 범위다. [기록](docs/158-midi-file-workflow.md).

## 검증 완료 — build135 피치 벤드 편집과 SMF 내보내기

- 같은 캔버스 편집·MCP edit_pitch_bend·raw/RPN SMF 저장을 연결했다. 외부 변경 뒤 index 보호, range/value 구분과 표현 구간 보기를 개선했다.
- 관련 26개, 전체 회귀 816개·내부 skip 2개·실패 0개, Python 28/6개를 확인했다. 실제 재생 테스트 1개는 제외했다. 최종 Release 47.35초와 패키지 검증을 통과했다.
- native 편집/Undo·stale 거절·SMF 저장/재가져오기·취소/재시작 r126을 확인했다. UI/artifact 최종 독립 감사도 PASS했으며 전체 DAW·물리 청취·모든 backend 완료는 아니다. [기록](docs/157-pitch-bend-edit-and-export.md).

## 검증 완료 — 0.20.0 build134 MIDI pitch bend 가져오기

- preserve 기본·명시적 omit과 raw controller/RPN 보존, channel별 미지원 오류, schema5 atomic 적용을 GUI/MCP에 연결했다. CC121 reset과 마지막 bend의 길이 경계를 처리한다.
- 회귀 793개·내부 skip 2개·실패 0개, 별도 실제 재생 테스트 1개 제외. Python MCP 6/27개와 Release 85.97초·QA 패키지 서명을 통과했다. 실제 적용/Undo·GUI/MCP 동일 결과·저장/재열기와 stress 제한 오류를 확인했다.
- 최종 독립 감사·QA 종료와 최종 서명 재검사도 통과했다. 곡선 UI·MCP 표현 편집·SMF 내보내기·AU/sampler·실제 청취는 완료하지 않았다. [기록](docs/156-midi-pitch-bend-import.md).

## 검증 완료 — 0.20.0 build133 내장 신스 pitch bend와 가져오기 취소 복귀

- schema5의 source별 표현을 내장 신스에 연결하고, MIDI 미리보기 취소의 viewport·스텝 cursor·Escape 복귀를 수정했다. 적용 성공 시 새 MIDI 선택은 유지한다.
- Core/Audio 780개·내부 skip 2개·실패 0개, 별도 바운스 저장/복원 1개 PASS. 실제 재생 포함 테스트 1개는 제외했다. 수정 후보 Release 44.41초·패키지 서명과 native 편집 복귀·r96 적용/r97 Undo·저장/재열기를 확인했다.
- SMF bend import/export·곡선 UI·MCP 표현 편집·AU/sampler와 물리 청취는 완료하지 않았다. stale 경계는 소스 검토 범위다. [검증 기록](docs/155-pitch-bend-synth-and-import-return.md).

## 이전 개발 단계 — MIDI pitch bend 저장·컴파일 계약

- raw wheel·RPN range 상태·시간순 이벤트의 검증/직렬화/hold 조회 타입을 추가했다. 경계·순서·저장 테스트 8개와 독립 검토를 통과했다.
- optional Lane/RhythmPattern·schema5 저장과 source/occurrence packet을 연결했다. 미지원 오디오 렌더와 typed MIDI 저장은 표현을 버리는 대신 오류로 거절한다. 실제 SMF parser·GUI/MCP·DSP 지원은 다음 단계이며 패키지 앱은 build132를 유지한다. [계획과 결과](docs/154-midi-pitch-bend-plan.md).

- Core/Audio 회귀 765개·내부 skip 2개·실패 0개, 73.023초. 실제 재생 포함 테스트 1개는 AU helper 미준비 실패 후 제외했다. 추가 router guard 9개도 0.517초에 통과했다. 새 native GUI·패키지·물리 오디오 검증은 수행하지 않았다.

## 검증 완료 — 0.20.0 build132 MIDI 가져오기 피드백

- 고정 실행 영역에서 입력·선택·tempo 지원 오류를 표시하고 대상 use 별명·편곡·순서를 맞춘다.
- 최종 Release 47.20초·production 서명, 실제 오류/회복·스크롤 후 고정 표시·취소/재열기·음악/자산 보존을 확인했다. 독립 첫 6개 화면 감사는 PASS, 추가 unsupported 화면의 오류 고정·keepCurrent 회복과 음악 보존도 독립 감사 PASS로 확인했다.
- 초기 API 컴파일 실패는 수정 후 통과했다. 파일 대화상자 자동화의 키 불일치 원인은 미확정이며 전체 키보드/물리 오디오 완료를 뜻하지 않는다. [기록](docs/153-midi-import-feedback.md).

## 검증 완료 — 0.20.0 build131 MIDI tempo map 가져오기

- 기본 keepCurrent를 유지하며 applyFile은 이번 use의 tempo map을 schema4로 적용한다. 기존 설정을 보관하고 명시적 해제로 복귀한다. GUI와 MCP importer의 preview/job·revision·한 Undo 계약을 연결했다.
- 관련 기계검증 496개·렌더 통합 1개, MCP 13/27개·Release 81.94초를 통과했다. native 적용/복귀·오프라인 바운스·원본 복원·r95 저장/재열기와 production 서명도 확인했다.
- 실제 입출력·청취·MIDI CC/pitch bend 완료를 뜻하지 않는다. [기록](docs/152-midi-tempo-import-validation.md).

## 검증 완료 — 0.20.0 build130 오토메이션 편집 공간

- 가로 파라미터 선택과 자동 줄바꿈으로 같은 창의 곡선 눈금 영역을 약60→90px로 확대했다.
- 빈 곡선 Tab/Shift-Tab의 상위 캔버스 전파를 차단하고 신스 필터 도움말을 보완했다.
- 최종 Release47.75초·native 수치/Undo·재열기·패키지와 독립 7개 capture·6개 JPEG/AX 감사를 통과했다. [검증](docs/150-automation-editing-space.md).

## 검증 완료 — 0.20.0 build129 신스 cutoff 오토메이션

- 내장 신스 instrument의 절대 Hz 곡선을 voice 상태를 보존한 sample별 DSP에 전달한다. Hz 선형/log 표시·schema3·지원 타깃·GUI/MCP 범위를 연결했다.
- Core/Audio 479개와 추가 부모 tempo 1개, MCP 7/27개·kit 9개·C DSP 비교·Release 77.59초를 통과했다. 실제 GUI Hz 편집·잘못된 값 거절도 확인했다.
- native 편집·schema Undo/Redo·미지원 악기 반려·바운스/복원·재열기·독립 데이터 감사와 패키지 서명/UUID를 확인했다. 바운스 전후 최대 1LSB, 복원 WAV는 byte-exact다. 실제 청취·물리 오디오는 별도 검증 범위다. [기록](docs/149-synth-cutoff-automation-validation.md).

## 검증 완료 — 0.20.0 build128 편집 공간 가시성

- 오디오 핵심 수치 4개를 처음부터 표시하고 스텝 도구 배치를 줄여 같은 창의 완전한 음정 행을 4개에서 6개로 늘렸다. 초기 후보의 2행 미달을 보완한 compact 결과다.
- 최종 Release 44.07초·드럼 검색/페이지·MIDI 입력/Undo·오디오 오류/trim/분할/Undo를 확인했다. 최종 재열기·production 서명/UUID·독립 13개 compact capture 감사도 통과했다.
- 물리 오디오·모든 창 크기 검증은 포함하지 않는다. [기록](docs/147-editor-space.md), [후속 cutoff 계획](docs/148-synth-cutoff-automation-plan.md).

## 검증 완료 — 0.20.0 build127 편곡별 작업 복귀

- GUI/MCP 편곡 선택에서 임시 마지막 주소·workspace로 복귀한다. 문서 reset은 기억을 지우고 무효 대상은 composition으로 돌아간다.
- Release44.90초·오디오/automation/스텝 왕복·현재 재선택·stale 거절·문서 reset·삭제 fallback과 최종 15개 capture 감사·r62 재열기/disk 일치·production 서명/UUID를 통과했다.
- 한글 도구 입력은 TextEdit와 써클러에서 동일하게 축소됐다. 실제 IME·물리 오디오·새 PCM 검사는 미수행이다. [기록](docs/146-input-delivery-and-arrangement-return.md).

## 검증 완료 — 0.20.0 build126 비활성 편곡안 이름 변경

- ⇧⌘N·버튼이 강조한 편곡안을 대상으로 하며 source title/AX를 명시하고 이름 적용 후 강조를 유지한다. 현재 편곡·캔버스는 유지한다.
- 최종 Release42.19초·native B 대상/빈 이름 거절/마우스/강조 유지/A 작업 복귀·Undo/Redo를 확인했다. 저장/재열기·독립7개 snapshot 감사·production 서명/UUID도 통과했다.
- 한글 typeText 축소의 원인은 미확정이며 한글 입력 통과로 세지 않는다. 편곡 전환별 이전 위치 복귀는 후속이다. [기록](docs/145-inactive-arrangement-rename.md).

## 검증 완료 — 0.20.0 build125 공유 오디오·오토메이션 원본 범위

- edit_shared_audio의 pattern/track/clip 주소와 split/duplicate/fade/delete, set_automation의 original 범위를 연결하고 혼합 주소를 거절한다.
- Core30개·MCP27개·Release73.17초, 실제 MCP 편집/Undo·실패 batch/stale 거절·A/B automation 값 표시를 확인했다. 저장/재열기·production 서명/UUID·독립14개 snapshot 감사도 통과했다.
- 공유 오디오 trim/replace·실제 입출력은 포함하지 않는다. [기록](docs/144-agent-shared-audio-scope.md).

## 검증 완료 — 0.20.0 build124 오디오·오토메이션 전환

- ⌘5에서 이름 확정 후 연결 화면을 정리하고, 같은 선택에서 완료된 섹션 오디오 import는 이전 automation 모드를 닫아 새 파형을 표시한다.
- Release42.16초·native 연결→오토메이션·단일 WAV→파형·Undo·빈 이름 거절을 확인했다. revision28 저장/재열기·manifest 일치를 확인했으며 production 서명·UUID와 독립 데이터 감사도 통과했다.
- 실제 입출력·다른 선택 중 async 완료·취소/실패·다중 파일·pattern import는 이번 native 범위가 아니다. [검증 기록](docs/143-audio-automation-flow.md).

## 검증 완료 — 0.20.0 build123 원본 복원 후 출력 복귀

- 원본 복원 성공 후 같은 arrangement/use에 저장된 outputNodeID로 이동한다. 렌더 당시 identity를 전달하고 정확한 candidate 적용 뒤에만 탐색하여 보관 오디오에 남던 문제를 개선했다.
- 이름 오류·출력 연결 충돌의 거절, 정상 복귀·Undo·저장/재열기를 native로 확인했다. Release44.82초·QA/production 서명·독립8개 상태 감사와 자산3개 SHA 보존을 통과했다.
- stale 요청 직접 주입·실제 녹음 잠금은 native 미검증이며 새 PCM 검사·물리 입출력을 실행하지 않았다. 전체 제작 흐름은 계속 진행한다. [검증 기록](docs/142-bounce-restore-navigation.md).

## 추가 검증 — 기존 build122의 연속 제작 흐름

- 공유 스텝·신스 cutoff·reverb·GUI 바운스·원본 복원·Undo·재열기를 실제 앱에서 검증했다. 새 앱 코드나 Release 빌드는 없다.
- 바운스 전후 PCM 최대1LSB, 원본 복원 WAV byte-exact. 단계별 음악 변경과 Undo 복귀를 독립 감사했다.
- 원본 복원 후 편집 초점이 archive에 남는 UI 문제를 확인했다. 실제 입출력·청취와 전체 제작 흐름은 미완료다. [기록](docs/141-production-flow-validation.md).

## 검증 완료 — 0.20.0 build122 스텝 대상 유지·공유 리듬 탐색

- 공유 MIDI에서 ⌘4가 일반 MIDI로 바뀌던 문제를 재현·수정했다. 현재 MIDI 유지, 복수 후보 선택, 이름 오류 시 전환 차단을 같은 탐색 흐름으로 연결했다.
- 공유 MIDI/오디오는 소유 트랙과 실제 scene 표시 조건에 맞게 검색하며 공유 리듬임을 표시한다. 미할당 패턴과 빈 오디오는 제외한다.
- Core16개/0.036초·Release74.64초·실제 키보드/마우스·저장/재열기·QA/production 서명을 확인했다. 음악revision18·자산을 보존했다. 이번 후보의 노트 입력/Undo·바운스·물리 오디오는 별도 검증 범위다. [기록](docs/140-step-target-navigation.md).

## 검증 완료 — 0.20.0 build121 수치 포커스 가시성

- 공통 native 수치 필드의 focus 성공 시 자동 스크롤. Effect context 전체를 보존하며 focus registry만 교체한다.
- Release44.03초·source review·실제 효과 Tab/Shift+Tab·볼륨 변경/Undo·초안 취소·신스11필드 왕복·저장/재열기를 확인했다.
- UI-only QA와 production 패키지를 분리했다. 물리 오디오·전체 제작 흐름은 미검증이다. [검증](docs/139-numeric-focus-visibility.md), [개발 계획](docs/138-current-development-plan.md).

## 검증 완료 — 0.20.0 build120 콘솔 작업 영역 유지

- 앱별 UserDefaults에 콘솔 열림/로그높이 저장·복원. 기본true/122pt,40…180pt 범위와 잘못된 저장 타입/비유한값 보호. 음악·프로젝트·Undo 경로와 분리했다.
- helper31개·source review blocker0·Release44.77초. 실제 접힌 상태/180pt 및 열린 상태/40pt 재실행 복원과 native7개 저장 상태·JPEG8장 검토를 완료했다.
- 음악revision14·manifest/disk exact·자산2개·사용자 domain 두 키 불변 확인. QA는기본122pt/열림으로 복귀 후 종료했고 사용자PID86114 유지. 실제 오디오 실행 없음. [기록](docs/137-console-preferences.md).

## 검증 완료 — 0.20.0 build119 신스 수치 접근

- baseline118에서 Tab10회로 움직임0.55를 선택해도 화면 밖에 남는 현상을 실제 확인했다. eager2열 Layout과 엔진별6/9/11필드 focus registry·자동 스크롤로 수정했다.
- 실제 정·역방향 Tab, 초안1000. 상태에서 콘솔 높이 변경/Esc, 움직임0.55→0.7/Undo, engine1/2 및 engine3 복원, 정확한 manifest 재열기를 검증했다.
- Release45.18초·소스 review blocker0·QA/production 패키지 서명 검증. UI-only helper5종 stub과 production helpers는 분리했고 사용자 앱PID86114 유지. 물리오디오·VoiceOver 발화는 미검증. [기록](docs/136-synth-parameter-access.md).

## 제한된 검증 완료 — 0.20.0 build118 악기 미리 듣기 worker 격리

- 지속 `circlr-audition-worker`, 필요한 자산만 포함하는 private 요청 파일, 세션·순서·capability·token IPC와 독립 stdin 취소 처리.
- 준비8초·note 응답2초 제한, STOP/EOF/TERM/KILL·소유 child reap·reader/파일 정리. 실행 중 worker 유휴 종료도 실패 상태로 전달.
- buffered failure가 대기로 사라지는 문제와 cleanup 중 cancel이 실패에 덮이는 문제를 RED 재현 후 수정. 관련32개 테스트/6.512초 통과, read-only reviewer v3 blocker0.
- 실제 HAL·악기 음질·연주 latency는 미검증이며 사용자 원본 앱을 교체하지 않았다. [계약과 패키징 검증](docs/135-audition-worker-isolation.md).

## 검증 완료 — 0.20.0 build117 오디오 수치 접근·휠 분리

- 파형·도구·수치를 같은 스크롤 영역으로 연결하고640pt 미만 편집 폭에서는2열로 배치. eager field 등록으로 Tab/Shift+Tab 접근 유지.
- NSScrollView의 휠을 전체 캔버스 확대가 가로채지 않도록 수정. 파형 자체 휠 확대와 빈 공간의 캔버스 확대는 유지하며 Return/Escape 시 파형을 화면에 드러냄.
- Release46.45초·UUID `1D43D21B-ACD0-3BD6-8ABA-5AD820194588`, native9개 상태·PNG9장 직접 검토·gain/Undo·원본2개 SHA·정확한 재열기 통과. 다른 편집기 전체와 물리I/O 미검증, 사용자 앱 유지. [검증 기록](docs/134-audio-workspace-layout.md).

## 검증 완료 — 0.20.0 build116 공유 리듬 오디오 편집

- 같은 캔버스에서 공유 리듬의 클립 선택·파형/수치 편집·공유 범위 안내를 연결. trim/fades/volume/beat/tempo·split/duplicate/delete 구현.
- 실제 baseline115 AudioLane2clip/파형·수치 부재를 PNG·AX·r14로 확보. Core7개(offline PCM1개 포함)·0.390초 통과, 반복 PCM max error<1e-6 및 graph/legacy cycle offset 확인. legacy 전체 PCM은 미검증.
- 최대2개 keyed cache·공유 mute 안내, non-follow split의 다른/가변 tempo 거절 및 followsTempo sourceBPM/sample boundary 검사. final2 Release44.04초·regression32개·shared15/ordinary포함17 native 상태 확인. 마지막 삭제의 부모 복귀는 확인했으나99 초안의 clip 전환 잔류와 saved clip2→clip1 재열림을 발견해 identity/선택/viewport 복원을 수정. frozen final3 Release42.71초·UUID `7DD71FA1-C126-34EA-82C5-E1CF34853EDE`, source v6 review blocker0·보완5개 상태 확인. build 중 source 변경으로 실패한 이전 final3 로그는 성공 근거에서 제외하며 final2 17개+final3 5개 mixed-candidate checker·exact Undo/reopen/disk·signed main SHA/UUID guard·final3 PNG4장 검토 통과. draft-switched 수치는 AX only, QA 종료·PID86114 유지. [계약](docs/132-shared-rhythm-audio-workspace.md).

## 제한된 검증 완료 — 0.20.0 build115 미리 듣기 단계 진단

- optional session trace64개·첫 interruption 보존·stale guard, sourceLoad/AU/engineCreation/mixerAcquisition/routing/engineStart/note/cleanup 계측. legacy factory/status decode 보존, 두 인자 factory는 generic backendPreparation.
- 기존108pt readout·12pt label에서 pending audition 우선 표시와 경과/취소 footer 적용. progress log는 초마다 누적하지 않음.
- mocked lifecycle17개·실제 diagnostics/presentation106개 검사 및 production JSON/readout dark offscreen native15개 PNG 검증. Release78.21초·UUID `3D03E2CB-5571-3713-AC7C-9B3884F21829`, source review blocker0·시각15장 통과. preparing17초/stopping123초 fixture이며 원본 PID86114 유지.
- 전체 앱/HAL·물리 재생 검증은 아니며 initializer 실패의 Swift unwind/deinit 내부는 미계측. in-process 중단·격리·HAL 해결을 주장하지 않음. [계약](docs/131-audition-stage-diagnostics.md).

## 검증 완료 — 0.20.0 build114 짧은 파형 손잡이

- build113 final split 화면의 32초 파일·0.5초 구간에서 라벨 충돌과 linear x 거리14px 미만 trim 판정이 구간 조작을 가로채는 문제 확인.
- 짧은 구간에만 y-separated handle·공통 geometry·라벨 leader를 적용. 자동 fit 없이 직접 cursor/trim 조작을 검증했고 orbital은 source 정책 보존 범위다.
- actual helper geometry harness72개 scenario/737개 검사·source review blocker0 통과. 첫 앱 Release41.59초·exit0은 사전 후보다. standalone harness의 CoreGraphics import 누락은 명시 import로 수정했으며 제품 compile 실패와 구분. drag 중 resize 취소는 source guard 검토만 수행.
- final2 Release41.14초·UUID `8EBE5ECA-B744-3D51-874C-78794B72374A`, geometry782개·source v3 review blocker0 통과. native20개 JSON의 시작/끝/tiny/middle drag·Undo·restored/reopened32·자산2개/noIO 확보. JPG10장·AX 시각과20개 strict checker·5개 gesture·restored/reopened/disk 동일성 통과. 좌표1px tolerance는 native만 적용하고 geometry782개는 exact 검사. wide native는 F/0만이며 wide hit는 harness, orbital은 source만 검토. QA 종료·사용자 PID86114 유지. 초기 x55 plot 밖 no-op 후보는 보존하되 승인 제외.
- 별도 후속 오디오 진단은 AuditionTransport의 in-process AU→mixer/start 구간을 bounded trace로 분리할 필요가 있음. timeout이 factory를 중단시키지 못하는 경계이며 이번 UI 수정이나 HAL 해결로 합산하지 않음. [계약](docs/130-audio-waveform-handles.md).

## 검증 완료 — 0.20.0 build113 오디오 템포 구간·편곡 입력

- 실제 clip span의 일정 BPM을 허용하는 Core 공통 split와 legacy/graph render, 선택 출력의 endpoint 의존성 및 tail/render 공통 plan 적용. 실제 변화 교차·반복 시작 BPM 불일치는 거절.
- tempo RED 2 failures와 선택 출력 RED 1 failure 후 관련 테스트 16개(tempo 13개 포함)/6.848초 통과. 중간 compile 오류 해소, 초기 fixture trap 제외. Release 73.53초·UUID `BAE18DB5-1AF7-3F53-824C-72C7356122CC`.
- 오디오 checker 9개 capture·r14→18: 실제 split/bounce/Undo·crossing alert/실패·정확한 재열기·원본 자산 2개 SHA 보존. 실제 WAV 28초·stereo·48 kHz·nonzero 확인.
- 편곡 9개 capture·r17→20의 cold clone/계속 편집/rename·#2 원본 B 표시 후 취소·검색 복원/Undo/재열기 수행. 실제 B commit 없음, reset은 AX만. checker·strict persistence 통과. JPG 10장·AX 시각 검토는 짧은 파형 라벨 간격·reset 상세 스크롤의 경미한 개선점을 남김. 출력 attempt0·사용자 앱 유지. [계약](docs/129-audio-tempo-regions-and-arrangement-input.md).

## 검증 완료 — 0.20.0 build112 편곡 복제 후 편집 유지

- 현재 편곡의 정확한 audio 클립·MIDI 서클/노트 대상 continuation·⇧⌘E·workspaceOriginal=false·automation point 복원 구현. rhythm과 다른 candidate는 대상에서 제외. graph=nil·유효하지 않은 색상 주소는 원본에 보존하고 clone에는 복사하지 않음.
- Release83.26초·UUID `9FEBF1B5-482D-321E-807A-6D0AD5C45744`·Core13개·source review blocker0·시각7장 통과. checker24개 snapshot의 sharedOriginalModeForcedOff·exactCloneMusic·audio/automation 복귀·sourcePreserved·Undo/reopen·noIO 통과. stale는 UI disabled no-op이며 handler 호출 검증은 아님.
- 빠른 복제 직후 rename/다음 clone 단축키가 검색으로 입력되거나 clipboard timeout이 관측됨. 폼 확인 뒤 성공했으며 기존 picker의 빠른 연속 단축키/focus는 후속 과제. MIDI continuation UI는 native 미검증이며 Core는 주소 mapping 검증이다. nonempty 그룹/색상 native는 미검증. cached viewport 허용은 original-before editor 없음→continued의 같은 asset 구체화에 한정. 물리 출력은 QA stub 차단, QA 종료 후 사용자 PID86114만 유지. [계약](docs/128-arrangement-continuation.md).

## 검증 완료 — 0.20.0 build111 MIDI 생성 메뉴·명령 검색 focus

- 기존 MIDI 메뉴에 네 패턴 항목을 직접 배치. 1-based 시작·남은 길이(4분음표 기준)와 기존 노트 유지/겹침 안내, 명령 검색의 동일 request/range 및 stale 거절 적용. 추가 패널 없음.
- final2 빠른 메뉴 종료→명령 검색 입력에서 Space가 재생으로 누수: attempt1·didStart=false·outputNodeAcquisition timeout 후 정지·QA 앱 종료. 초기 final/final2는 승인 제외. 동기 focus·window-local 입력 guard·same-ID buffer 및 NSApp.sendEvent replay로 수정.
- final4 Release42.59초·UUID `1968E4B0-2662-3544-ACAD-DDABF1EADB95`. checker10개 snapshot·ordinary56/shared4 추가·기존 보존/공유 B/strict Undo/재열기·자산2개·attempts0 통과. rapid ASCII·한국어 paste와 시각5장 통과.
- final4는 명시적 QA output-helper deny 환경이다. 팝업 메뉴는 AX만 검증했고 메뉴 JPG 없음. stale 거절은 source review 범위이며 IME·실제 출력/readback/hotplug는 미검증이다. final2 incident를 final4 attempts0과 구분하며 QA 앱 종료 후 사용자 PID86114만 관측했다. [계약](docs/127-midi-generation-menu.md).

## 검증 완료 — 0.20.0 build110 테이크 번호 표시

- 동명 테이크 행을 `#번호 · 이름`으로 표시하고 검색 안내에 번호 추가. 번호는 필터 전 현재 대상 eligible 순서이며 영구 ID·녹음 연번이 아님. 이전 출력 reader 수정 포함.
- Release38.99초·UUID `DC416230-4D16-3A4F-AE22-B1E67F95A6EC`. 실제 ⌥⌘T·Down·#2 검색·Return 적용·⌘Z·재검색 reset·Esc·저장 재열기 확인.
- checker5개 상태·AX4개·정확한 적용 대상/gain·시각4장 잘림 없음 통과. before30/applied31/undo32/restored32/reopened32, 자산2개·output/record0 유지. QA 앱 종료·사용자 PID86114 보존. [계약](docs/126-take-identity.md).

## 소스·회귀 검증 완료 — 출력 reader 정리

- build109 Release 이후 별도 소스 수정이다. helper가 종료해도 자손 프로세스가 stdout/stderr pipe를 상속하면 reader가 host를 계속 보유하는 회귀를 재현했다.
- `.build/output-reader-baseline-3s.log`: 1 test, 2 failures, 8.587초. stdout·stderr 각각의 host 해제 assertion이 실패했다.
- 수정 후 `.build/output-reader-fixed-tests.log`의 전체 OutputWorkerProcessTests16개, 0 failures, 20.149초 및 최종 source review(blocker0) 통과. `.build/output-reader-release.log`의 앱 raw executable Release 빌드도48.26초·exit0으로 완료했다. 재패키징·GUI/UI 재검증은 수행하지 않았으며 기존 사용자 앱을 유지한다.

## 검증 완료 — 0.20.0 build109 앱별 출력 장치·공유 리듬 표시

- catalog helper·요청별 선택·capability·실제 장치 guard·장치 변경 감시 구현. 명시 장치는 자동 대체하지 않고 시스템 기본 출력 setter를 호출하지 않음. 네 helper 필수 패키징.
- 초기 Esc 실패를 native controls로, Picker 선택 후 상태 갱신 누락을 ObservedObject로 수정. 최종 Release40.31초·UUID `3FED7CA1-03C1-3701-9E28-4BF59247A1CA`·mock/fixture38개16.992초 통과.
- UI-only mock 출력9개 상태에서 ⌘,·초기 focus·Space/↑↓/Return A→B·Tab·Esc·명령 진입·설정 복원·누락 유지·실패 재시도·취소739ms 확인. 음악r14 유지. 공유 리듬6개 상태의 r16→17→18·동일 패턴 B 공유·Undo·일반 MIDI 배너 없음·strict 재열기 확인.
- 후속 실제 catalog 조회: QA 응답을 주입하지 않은 production helper로 exit0·0.514초·장치4개·기본 장치 포함·schemaValid·childReaped 확인. UID 원문은 기록하지 않았으며 재생/readback/hotplug 검증은 아님.
- checker 출력9/리듬6·시각 출력9장/리듬3장·최종 source review·각 QA packager strict 서명 검증 통과. 조회5초는 deadline이며 reap 총 시간은 플랫폼 종료에 의존. 실제 장치 readback/hotplug/물리 재생은 미검증, HAL stall 해결 아님. 사용자 앱 PID86114 유지·QA/helper 잔류 없음. [구현·검증](docs/125-output-device-implementation.md).

## 검증 완료 — 0.20.0 build108 테이크 검색

- StudioPalette·직접 버튼/⌥⌘T/전체 명령·키보드 검색 적용. 초기 shortcut이 split에 잡히던 문제를 정확한 modifier guard로 수정.
- final2 키보드 성공 뒤 final3 목록 높이를 초기3개 기준194로 줄이고 필터 중 유지. 최종 Release39.82초·실제 선택/검색0/취소/Undo·⌘T split 회귀·명령/query reset·stale 거절·시각/source 검토 통과.
- checker9개 상태·검색 AX·테이크5개·자산2개·output0·r30 strict 복원/재열기/disk 대조 통과. physical I/O0·사용자 앱 유지. 당시 앱별 출력 장치 계획은 미구현. [계약](docs/124-take-search.md).

## 개발 중 — 0.20.0 build107 테이크 요약·AU instrument worker

- 테이크 이름·노트/클립 수·현재 내용 일치, exact target·legacy 첫 matching·nonempty payload 비교. active 체크와 구분.
- 첫73.20초 후보의 후속 선택 no-op 뒤 menu full identity·고유 AX ID를 갱신한 최종 Release40.16초 확인. 실제 선택/재선택·Undo·strict r22 저장 재열기, UI checker8개 상태·자산2개·테이크5개·strict r22 재열기 통과. 첫 문제의 캐시 원인은 추정.
- 관련 테스트27개·9.151초(FIFO 포함), 패키지 soundBank/audioUnit×clock/host override4개 PCM89100 frames·maxError0·strict 서명 통과. CLI는 helper 함께 빌드 필요.
- 키보드 메뉴 선택·popup 이미지 미확보, 원본 편집/name commit/stale intent/record busy는 source 확인 범위. 물리 I/O 성공 아님. [테이크](docs/122-take-summary.md) · [악기](docs/123-au-instrument-worker.md).

## 개발 중 — 0.20.0 build106 바운스 안내

- baseline105 경로 밖+manual0의 여운 경고 숨김 재현. 경로/여운 독립 표시와 실제 표시 문자열만 dedup 적용.
- source review·Release38.64초·실제 경고 동시 표시/설정 취소/자동 추정 복귀 통과. QA baseline1+final5·음악r22/자산2개·strict 재열기·physical0 확인. 실제 바운스/경로 복구는 미검증, exact dedup은 source review만. [계약](docs/121-bounce-notice-visibility.md).

## 개발 중 — 0.20.0 build105 오토메이션 compact 배치

- compact adaptive 배치·stable identity·도구 flow·수치 버튼/Tab/reveal 적용. 실제 plot 약50→160px·64beat와1/5/9/13 눈금 확인.
- Release38.43초·초안 줌 왕복·위치/gain/pan 입력·invalid 거절·Undo·최소 폭 linear 무겹침 확인. QA baseline1+final9·자산2개·정확한 음악 delta/복원·source hash·strict r28 재열기 통과.
- physical0·사용자 앱 유지. 동시 drag/resize·원본 불가 group·IME·대량 점은 native 미검증이며 하단 안내는 우측 스크롤 아래에 남는다. [계약](docs/120-automation-compact-layout.md).

## 개발 중 — 0.20.0 build104 연결 focus·선택 행 유지

- stable identity·측정 높이·connections 전용 reanchor와 공통 `PortKeyboardFocus`의 선택 행 inner/outer reveal 적용.
- 초기 목록 공백·final2 선택 행 가림을 수정한 최종 Release40.00초 통과. 실제 target/search/filter 폭 왕복·caret·목록 heading/첫 행·키보드 재연결/취소 확인.
- QA 전체11개 상태·음악r36/자산2개·source hash·strict manifest/disk·완료 open과 시각 검토 통과. physical0·사용자 앱 유지. 케이블 적용·그룹 관리·IME 조합·숨은 jump focus 폭 전환은 미검증. [계약](docs/119-connection-focus-continuity.md).

## 개발 중 — 0.20.0 build103 오디오 compact 배치

- metadata 위·가변 높이 파형 frame·도구 Scroll 아래·action/nav flow·4열 label above 적용. audio 수치 focus만 선택적 자동 reveal.
- Release39.90초·native 초안0. 줌 왕복·invalid999 Tab focus 유지·trim0.1초/Undo·첫/마지막 입력 접근·수평 overflow 없음 확인.
- checker4개 상태·자산2개·physical0, revision38 음악 복원·strict 저장 재열기·완료 open 통과. 전체8필드 연속 Tab·본문180 미만·녹음 busy는 미검증. 사용자 앱 유지. [계약](docs/118-audio-compact-layout.md).

## 개발 중 — 0.20.0 build102 연결 목록 접근

- compact 고정 jump bar·목록 재연결의 compose/search focus·wide 두 열 유지. 첫 후보의 keyboard 우회를 수정한 최종 Release38.32초 통과.
- 실제 Shift+Tab/Return 목록 이동·재연결 입력 focus·대상/octant 보존·취소·wide/compact 왕복 확인. QA14개 상태·focus AX5개·음악36/자산2개·source SHA·strict 재열기 통과.
- 폭 전환 시 focus는 window로 돌아가는 잔여 UX. 실제 케이블 적용·빈 연결·그룹 관리·외부 intent는 native 미검증. physical0·사용자 앱 유지. [계약](docs/117-connection-workspace-access.md).

## 개발 중 — 0.20.0 build101 inline header

- stable3그룹·wide 한 줄/compact 두 줄과 Orbit 수평16 여백으로 원형 상단 잘림 수정. 이름 field의 기존 help 유지.
- 초기69.55초 후보의 잔여 잘림 뒤 최종 Release37.87초 통과. 실제 양끝 가시성·한국어 초안/focus 왕복·Esc·설정/연결·상위 이동 확인.
- QA7개 상태·초안AX2개·음악r36/자산2개·원본 SHA·strict 저장 재열기 통과. physical0·사용자 앱 유지. 녹음 busy/takes·IME 조합·mode Tab 순서·body 하단 스크롤은 미검증. [계약](docs/116-inline-header-layout.md).

## 개발 중 — 0.20.0 build100 MIDI compact 배치

- compact574·threshold700·inspector210·개별 field97/label wrap·adaptive toolbar 적용. 기존 진입 threshold·view identity 유지, Grid/StepEditor도 responsive로 수정.
- 중간 Release41.96초 후보의 Orbit 검증 뒤 step header 잘림을 발견해 수정. 최종 Release41.85초에서 step4필드·1/16 수평 page·검색/줌 보존·3노트 이동/Undo·Orbit 초안·하단 스크롤 접근 확인.
- 신규 Core 동작 없음. QA baseline2+first9+final7의18개 상태·AX5개·UUID와 revision36 saved/reopened/disk strict 일치·open 완료 통과. physical0·자산2개. 긴 셋잇단 적용 미검증·header 일부 잘림 잔여. [계약](docs/115-midi-compact-layout.md).

## 개발 중 — 0.20.0 build99 편곡 후보 직접 복제

- 행에서 직접 복제·⇧⌘D 강조 candidate·현재 이름 변경 대상 명시. 원본 ID 고정·입력 중 행 잠금·취소 무변경·clone/select 한 mutate.
- Core11개 실패0·0.007초·source guard review·Release41.58초·strict 서명 통과. 실제 행/키보드 복제·취소·한 Undo·검색0·현재 이름 변경 취소·stale 거절·저장 재열기 확인. QA14개 상태·AX5개 검사·PNG7개 직접 검토 통과. output/audition0·자산2개 유지. [계약](docs/114-arrangement-candidate-duplicate.md).

## 개발 중 — 0.20.0 build98 섹션 연결 메뉴

- `AlbumCanvas` 우클릭 체크를 `SectionFlowSelection.isSelected`로 통일하고 isEnd의 ‘끝 해제 후 재생할 연결’ 안내 추가. 기존 선택 동작 유지.
- Core6개 실패0·0.004초·Release39.03초·패키지 strict 서명 통과. 실제 단일 선택 무변경·끝 해제 안내/선택·Undo 확인. 체크 glyph 시각은 미검증이며 AX highlight와 구분. 앞선 `UnifiedSectionView`는 rg 검색에서 생성 참조를 찾지 못해 실제 수정 대상을 정정. [계약](docs/113-section-flow-menu.md).

## 개발 중 — 0.20.0 build97 MIDI 작업 도구

- Orbit/Grid의 mode·MIDI 메뉴·bounce·record를 전체 편집 폭에 배치하고 Orbit 이전/다음·count 이동. 기존 canvas 유지.
- Release38.38초·실제1020×768 콘솔122/40에서 도구 가시성, 노트 편집/Undo·직접⌘A/Delete/Undo·34초 바운스/Undo·revision30 strict 저장 재열기 확인. QA20개 상태·AX 내용6개·원본 자산2개·offline bounce1개·physical0 대조 통과.
- 메뉴 전체 선택 click 효과는 미확정이며 메뉴 Down이 노트로 전달돼 Undo 복원. 메뉴 노출과 실제 action을 구분. MIDI 녹음·물리 출력 미실행·사용자 앱 유지. [계약](docs/112-midi-workspace-actions.md) · [QA](qa/workflow-visibility-review.md).

## 개발 중 — 0.20.0 build96 offline AU effect worker

- AU effect instantiate/render를 별도 process로 이동. bounded 입력/결과·취소·deadline·child/임시 파일 정리와 App 두 outer task의 즉시 STOP 진입 경쟁 수정.
- state8MiB·request12MiB·maximumFrames268435456 상한. 기존 다중 buffer memory preflight 유지, deadline30–1800초(duration×4+15).
- 최종 관련46개 실패0·18.491초, Release47.10초·패키지3개 실행 파일 검사 통과. 패키지 Apple AU default/captured state 두 설정의 각12000-frame PCM maxError/RMS error0. [계약](docs/111-au-effect-worker.md) · [QA](qa/au-effect-worker-review.md).
- GUI 즉시 STOP race는 source guard·compile만 확인했으며 실제 host cancel 테스트와 구분. 사용자 dist 앱 유지. 보안 sandbox가 아닌 crash/hang 격리.

## 개발 중 — 0.20.0 build95 중복 탐색 버튼

- 현재 역할의 유일한 동일 target 버튼 생략. header 복귀와 다중 검색·⌘1/⌘3 유지.
- parse·Release40.30초 통과. 실제 router 단일 버튼 제거·settings/connection의 header 복귀·audio2/effect2/source3 검색·MIDI 선택과 다른 대상 복귀 확인.
- 모든 revision62 음악 불변·saved/reopened 전체 manifest strict 동일. QA10개 상태·AX12개·자산2개·physical0 대조 통과. MIDI/effect는 use-only 안내 상태의 탐색 검증이며 편집 검증 아님. [계약](docs/110-route-density.md) · [QA](qa/route-density-review.md).

## 개발 중 — 0.20.0 build94 콘솔 로그 높이

- 세션40–180px·기본122px, drag와 ⌃⌘1/2/3 지원. header·명령 입력·초안 유지.
- 초기41.28초 후보의 입력창 단축키 실패를 `CirclrAppCommands` 등록으로 수정. 최종 parse·Release40.59초와 native 단축키·clamp·접힘/펼침·편집기 왕복·wheel·명령 확인.
- 모든 music revision62 유지·saved/reopened 전체 manifest strict 동일·같은 세션 높이40 유지. QA18개 상태·최종AX10개·자산2개·physical0·높이82px 감소 확인. 신규 unit 테스트 없음. [계약](docs/109-console-height.md) · [QA](qa/console-height-review.md).
- 실행 중 job 취소 버튼은 이번 native 미검증. 앱 재시작 후 높이는122px이며 프로젝트 재열기와 구분.

## 개발 중 — 0.20.0 build93 음악 그래프 편집 범위

- scope snapshot·복합 effect 원본 읽기·AU 비동기 대상 guard·use-only 안내·직접 범위 선택. reviewer가 발견한 group router 생성 회귀의 parent 해석 수정.
- 관련31개 실패0·최종 Release45.48초 통과. baseline92 원본 이름 수정의 ID collision 전체 실패와 candidate 원본 수정·scope/target 초안 처리·group 생성·Undo를 대조.
- 1020×768·revision62 저장/재열기 전체 manifest strict 동일 확인. QA18개 상태·AX9개·자산2개·physical0 대조 통과. [계약](docs/108-music-graph-edit-scope.md) · [QA](qa/music-scope-review.md).
- 실제 AU plugin 비동기 native는 미검증이며 코드 guard만 확인. 사용자 앱·물리 출력 조건 유지.

## 개발 중 — 0.20.0 build92 router 경로 전송량

- 네 경로 dB 수치/Tab·slider 입력과 Core 명시 대상·expected guard·원본/이번 사용 분리·route 순서 보존.
- Core19개·최종 Release41.35초 통과. 수정 없는 Return 정밀도/no-op·네 경로/slider 입력·삭제/추가·원본22 경로 수정·preset 충돌 거절·각 Undo 확인.
- 1020×768·scroll1 유지와 revision54의 saved/reopened 전체 manifest strict 동일 확인. QA baseline3개·후보25개·AX12개·자산2개·physical0 대조 통과. [계약](docs/106-router-route-levels.md) · [QA](qa/router-level-review.md).
- 원본 안전성은 이번 route helper 범위. 물리 출력0회·사용자 앱 보존. 동시 수정 감지로 중단한 첫 빌드는 최종 빌드와 구분.

## 개발 중 — 0.20.0 build91 출력 dB·router 스크롤

- effect/mix/router 출력 볼륨을 기존 `.gainDecibels`로 통일. 저장·MCP·renderer·automation의 선형 값 유지.
- 1020×768 콘솔 열림의 router 하단 접근과 scroll 복원 whitelist 누락 수정. 최종 관련17개 테스트·Release20.04초 통과.
- 최종7개 상태·AX4개에서 하단 위치1의 mix 왕복·gain/Undo·저장 재열기 유지와 strict manifest 동일 확인. QA 최종 대조 통과·routerScroll{x:0,y:169} 확인. [계약](docs/105-signal-level-decibels.md) · [QA](qa/signal-level-review.md).
- 앞선38.99초 후보19개 상태·AX16개는 dB 입력 검증과 스크롤 누락 발견 이력으로 구분. physical 출력0회·사용자 앱 유지.

## 개발 중 — 0.20.0 build90 포트별 탐색

- 공통 Core structural port reachability로 `StudioNavigation.build`·`outputTracks`·`BounceAssessment` 분류 통일.
- 실제 router route·mute/gain0 구조 연결·sidechain-only 제외·lane 소유 미연결 접근 보존. Swift7개 class36개 테스트 실패0·Release73.47초 통과. 실제 독립 bus·현재 트랙 추론·router 교차 변경/Undo 확인. QA10개 상태·AX7개·자산2개·physical0 확인. 저장/재열기 manifest는 예외 없이 동일하고 Undo 음악은 musicRevision/hierarchyView 제외·circleColors 정규화 후 복원 확인. [계약](docs/104-port-aware-navigation.md) · [QA](qa/port-navigation-review.md).

## 개발 중 — 0.20.0 build89 트랙 단축키·출력 재대조

- 현재 section/track의0/1/multi 대상과 혼합 MIDI/audio를 일관되게 선택하도록 ⌘1/⌘2/⌘3 개선. parser·Release42.42초·실제 대상 선택/종류 전환/현재 찾기 통과. 저장·재열기의 음악/선택/camera 보존과 QA13개 캡처·AX7개 대조 통과. [단축키 QA](qa/track-shortcut-review.md). 신규 Swift unit 테스트 없음.
- 동시간 raw control2회와 서명 보존 helper2회 모두 mixerAcquisition timeout·started=false·EOF exit0. strict 서명 보존은 통과하지만 timeout 해결은 미입증. [계약](docs/103-track-shortcuts-and-output-recheck.md) · [출력 근거](qa/output-signature-review.md).

## 개발 중 — 0.20.0 build88 섹션 삽입·출력 준비 기록

- 선택 섹션 뒤 원자적 삽입·끝 표시 이전·독립 추가 유지. 분기/합류/loop/비기본 transition 거절. MCP는 `circlr_apply`의 `insert_section` 작업 사용.
- bounded typed 출력 준비 trace와 현재 단계 표시 추가. timeout/retry/device 정책 유지.
- Audio26개·Core7개·MCP23개·kit9개·file worker16개·Release52.87초 통과. 실제 MIDI 편집 중 명령 삽입·Undo/Redo 확인. 섹션 QA22개 상태·자산2개 보존 대조 통과. [섹션 QA](qa/section-insertion-review.md). [계약](docs/102-section-insertion-and-output-preparation.md).
- raw Release 무음 helper2회 started0.533/0.122초·자연 finished·command EOF 뒤 exit0 확인. 패키지 worker는 앱 host와 독립 CLI 실행 모두 각각 두 번 믹서 준비 단계에서 timeout. 실제6초 표시·Space 안내, 세 번째 시작의 즉시 취소·idle/didStart=false 확인. 추가 matrix의 패키지 byte 동일 외부 사본·재서명 raw 외부 사본도 각2회 timeout·EOF exit0. .app 위치만으로 설명되지 않으며 동시간 raw control이 없어 서명 인과는 미확정. 정상 앱 출력·청취 품질은 미해결. [관측](qa/output-preparation-native-review.md). 사용자 앱 변경 없음.

## 개발 중 — 0.20.0 build87 렌더 잔향 길이

- 공통 `RenderTailPlanner`로 자동 감쇠 추정·직접0–120초·상한/AU 미확정 안내·메모리 사전 거절. 보존 클립 실제 끝을 반영하며 section 시각 유지.
- 기존 줄의 설정과 job 끝 구간 측정, MCP 선택 인자 `tailSeconds` 추가. 생략 자동·null 금지·GUI 설정 독립.
- Audio30개·Core3개·MCP22개·kit9개·Release52.98초 통과. 실제 자동74초/직접34초의 앞34초 PCM 일치, 바운스/export74초의 재열기 전후 바이트 일치 확인.
- 실제1020×768 설정·121 거절·자동42초/직접2초·상한120·끝 신호 경고·파형85px, direct RPC 사전 거절·STOP 취소 후 안정 상태 확인. QA checker22개 문서 캡처·RPC 오류/취소 기록 대조 통과. [QA](qa/render-tail-review.md).
- UI running 스피너 캡처는 미확보, AU는 단위 metadata만 검증. 실제 출력0회·사용자 앱 유지·검증 앱 종료. 자동 추정은 무손실·청취 보장 아님.

## 개발 중 — 0.20.0 build86 오디오 범위·바운스 음소거

- 기존 줄에 공유 원본/이번 사용 범위와 전용 클립 복귀 표시. 첫 후보의 Return 무응답을 native에서 발견해 `AlbumCanvas` dispatch 수정 후 복귀·도움말 차단 확인.
- pre-output 바운스에서 출력 음소거 제외, upstream/정상 출력 음소거 유지. Audio21개·최종 Release41.19초 통과.
- 실제 범위별 트림0.1/0.2초·각 Undo·파형 높이 유지, 음소거 출력의34초/24bit/48kHz 바운스와 복귀·원본 복원·Undo3·재열기 확인. QA checker28개 상태·자산2개·바운스1개·WAV PCM/checksum 대조 통과. [계약](docs/100-audio-scope-and-bounce-mute.md) · [QA](qa/audio-scope-review.md).
- 실제 출력·audition0회, 사용자 앱 유지. 고정2초 tail의 효과 잘림은 compiled renderer에서 별도 재현했으며 후속 정책 과제로 유지.

## 개발 중 — 0.20.0 build85 바운스 상태·연결 복구

- typed assessment로 포트·router·sidechain을 고려한 대상/문제/현재 서클 포함 여부를 제공. 기존 route bar에 원인·경로 제외·연결 보기 표시, 명령 검색에서 출력 IN으로 이동.
- 초기 후보의 추가 행이 파형을 축소하는 native 회귀를 발견해 기존 한 줄로 통합하고 최종 compact 후보에서 파형 공간 복원.
- Core28개·AudioRouterAudio15개·최종 Release40.86초 통과. 실제 출력1 IN 이동·연결 해제/Undo·오토메이션 경고·MCP 이름 변경 뒤 stale 명령 거절/Undo·저장 재열기 확인. QA checker native20개·compact12개 상태·자산2개·manifest/source SHA 대조 통과. [계약](docs/99-bounce-visibility.md) · [QA](qa/bounce-visibility-review.md).
- 사용자 앱 유지. 실제 출력·audition0회, 이번 범위 바운스 렌더 미실행. 물리 I/O 출고 조건 미완료.

## 개발 중 — 0.20.0 build84 편곡 연결 경로 미리보기

- 기존 편곡안 행에 연결 순서·반복 횟수·경로 제외·분기 오류·빈 경로 표시. `ArrangementCompiler`의 경로 cursor 공유.
- Swift401개 실패0·Release68.85초 통과. 실제1020×768에서 같은 이름의3회/6회 경로 구분·긴 한국어 이름 변경·Down/Return 선택·원안/대안 왕복 확인.
- 연결·순서·반복 수정 후9회/제외0 갱신, Undo5·실제 재열기·복제 입력 취소·#4 검색 취소 확인. QA checker native15개 상태·자산2개·source SHA 대조 통과. [계약](docs/98-arrangement-route-preview.md) · [QA](qa/arrangement-route-review.md).
- 오디오 시작0회. 사용자 앱을 보존하고 검증 앱 종료. 음원 유효성·재생 시간·청취 및 기존 출력 출고 조건은 별도 유지.

## 개발 중 — 0.20.0 build83 편곡 복제·이름 변경

- 편곡안 목록에 이름 변경·명명 복제를 통합. 하위 편집에서도 현재 편곡 번호·이름 표시.
- 목록 전용 ⇧⌘N 이름 변경·⇧⌘D 복제, 입력·취소·오류와 동일 이름 no-op 지원.
- 소유 곡·편곡 검증, 복제 색상 유지, MCP 명시 대상 작업과 내장 Codex kit 갱신.
- MCP `duplicate_arrangement`·`rename_arrangement`·`select_arrangement` 지원. 같은 곡/다른 곡의 복제는 재생 선택·active·selection·MIDI 편집기를 유지하고 명시적 선택은 대상 곡에 포커스. UI 복제는 새 편곡 선택.
- Core30개·MCP21개·최종 Release68.50초 통과. 실제 MCP 복제·명시적 전환·Undo 다섯 번의 음악 복원·재열기 확인. UI·키보드·Undo/Redo·원안 보존·저장 복원도 검증. [QA](qa/arrangement-workspace-review.md).

## 개발 중 — 0.20.0 build82 출력 세션 취소 경계

- 이전 play의 timeout/catch가 교체된 출력 세션을 취소하지 않도록 세션 ID 확인과 취소를 같은 lock 안에서 수행. 외부 STOP 동작 유지.
- OutputWorkerProcess/Protocol 관련16개 테스트 통과 (`.build/output-session-tests.log`). build82 release 빌드46.09초 통과. 실제 host 첫 시도는 장치 단계 timeout·didStart=false 뒤 idle, 별도 세션 재시도는 didStart=true·시계1.1145625초·STOP 후 idle 확인. 간헐적 최초 시작 실패는 미해결이며 build82 세 번째 세션은 약34초 진행 후 자연 종료. [QA](qa/output-session-review.md).
- build81 무음 helper에서 실제 장치 시작·STOP·EOF·세션 교체와 별도 재생 시계 0→1초·자연 종료 확인. 청취·입력·장치 변경·MP4는 미검증이며 과거 HAL 정지 원인은 미확정.

## 검증 갱신 — 이펙트·오토메이션·바운스

- 보관 WAV 해시/PCM 재검증 및 build81 전체 프로젝트 재열기 확인.
- 궤도 모드의 음악 보존 확인, QA checker report 덮어쓰기 방지.
- 실제 출력·청취와 분리한 검증 경계 문서화.

## 개발 중 — 0.20.0 build81 서클 색상

- MIDI·오디오·이펙터·곡·섹션 등 종류별 기본색과 8색 팔레트·사용자 지정·기본값 복원.
- 주소별 저장과 Undo, 프로젝트 전환·삭제 시 색상 패널 대상 해제.
- 모델/history 14개 테스트 통과. 실제 색상 선택·Undo·재열기·기본값 복원 검증 통과.

0.1–0.3은 설계 문서 revision이며, 0.4.0부터 로컬 실행 프로토타입을 포함한다.

## 개발 중 — 0.20.0 build80 바운스 대상 사전 검사

- MIDI·오디오·이펙트·출력 편집기의 바운스 버튼 공통화, 대상 트랙과 연결 문제 안내.
- UI·MCP·최종 적용이 같은 출력/입력 검사를 사용하며 MCP는 job 생성 전에 거절.
- 관련17개 테스트·native7상태, 실제 바운스·원본 복원·Undo·음악/패키지 보존 통과. [QA](qa/bounce-target-review.md).

## 개발 중 — 0.20.0 build79 오디오 가져오기 대상

- 섹션·그룹에서 새 트랙을 기본 대상으로 사용. 개별 음악 서클은 선택 트랙 유지.
- 파일 창에 대상·시작 박·원본/이번 사용과 다중 파일 배치 안내.
- 관련16개 테스트·native5상태, 실제 새 트랙·Undo·재열기·패키지 보존 통과. [QA](qa/import-destination-review.md).

## 개발 중 — 0.20.0 build78 이동 중 화면 저장

- 이동 직후 저장하면 선택한 서클과 확대 위치가 달라지는 문제 수정.
- 대기 이동 반영·유효한 애니메이션 목적지 저장·사용자 취소 위치 보존.
- 관련18개 테스트·native8상태 및 재열기·전체 음악/패키지 보존 검증. [QA](qa/save-focus-review.md).

## 개발 중 — 0.20.0 build77 생성 메뉴와 드럼 첫 입력

- 현재 곡·섹션·사운드에 맞는 생성 메뉴를 우선 표시하고 다른 위치 작업을 분리.
- 기본 Sound Bank 드럼 8행 유지, 비활성 sampler 매핑이 다른 악기에 섞이지 않도록 수정.
- Swift7개·release·native10상태 및 입력/생성 Undo·검색·저장 복원 검증. [QA](qa/creation-interface-review.md).

## 개발 중 — 0.20.0 build76 출력 대기 복구

- 기본 곡 재생을 별도 helper에 연결. STOP/시간 초과 뒤 자식 종료와 임시파일 정리 후 새 재생 허용.
- 준비 초수·정리·다시 재생 가능 표시를12pt로 확대. 앱/helper 함께 빌드·서명.
- Swift513개·MCP/kit29개·helper16개 및 실제 timeout/재시도/Space 취소 검증. 정상 장치 출력은 미완료. [QA](qa/output-host-review.md).

## 개발 중 — 출력 helper 기반

- 고정 private PCM 파일·bounded wire를 사용하는 별도 출력 실행 파일 추가.
- 실제 프로세스15개/wire7개 검사, 출력 무응답 중 부모 연결 종료와 다음 child 실행 확인. 앱 Playback 연결과 정상 출력은 미완료. [QA](qa/output-worker-service-review.md).

## 개발 중 — 0.20.0 build75 검색 가능한 키보드 도움말

- 작업 종류 필터·검색·결과 없음에서 전체 범위 찾기·키보드 목록 이동 제공.
- 명령 검색에 단축키 포함, 정확한 제목/접두 일치 우선 정렬.
- 최종 release/native 7상태·9화면, 음악/자산/패키지 보존 검증. [QA](qa/shortcut-search-review.md).

## 개발 중 — 0.20.0 build74 오디오 키보드와 복제 안내

- Tab/Shift+Tab·수치 입력 버튼으로 첫/마지막 오디오 필드 진입, Return/Esc 파형 복귀.
- 복제 시작 위치를 Core와 공유해 공간 부족을 사전 표시. 단축키는 오류 창 대신 상태 안내.
- Swift498개·Python29개, native7상태/키보드 실제 편집 검증. [QA](qa/audio-keyboard-review.md).

## 개발 중 — 0.20.0 build 73 오디오 편집 배치

- 전체 폭 파형·두 줄 수치 입력으로 좌우 스크롤 폼 제거. 상단 분할/복제/템포 추종과 파형 아래 보기 조작 제공.
- 관련14개 테스트·native11문서 상태, 작은/큰 창·편집/Undo·재열기·음악/자산 보존 검증. [QA](qa/audio-layout-review.md).

## 개발 중 — 0.20.0 build 72 MIDI 선택 바로 보기

- 피아노 롤 상단 선택 보기/F로 선택 노트로 이동. 화면에 들어가는 다중 선택은 함께 표시하고, 넓은 선택은 기준 노트를 표시한다.
- 작은 창의 고정 눈금/건반과 여백을 고려하고 시간 배율·음역 폭·음악을 유지한다.
- Swift496개·Python29개와 native 문서9상태 검증. [QA](qa/selection-reveal-review.md).

## 개발 중 — 0.20.0 build 71 편집 선택 복귀

- 서클·원본/이번 사용별 MIDI 선택, 볼륨·팬 점 선택과 오디오 원본 시간 커서를 기억한다. 현재 작업의 선택을 workspace 보기 정보로 저장하고 재열기에서 검증해 복원한다.
- 삭제된 ID·다른 clip/asset은 복원하지 않는다. 트림 Undo/Redo가 커서를 다른 원본 시간으로 옮기던 문제를 수정하고 음악 서클에만 적용한다.
- Swift496개·Python29개, native30상태/34화면과 음악/자산/패키지 대조 통과. [계약](docs/85-editor-selection-memory.md) · [QA](qa/selection-memory-review.md).

## 개발 중 — 0.20.0 build 70 캔버스 접근성 좌표

- 가상 스텝 행·셀, MIDI 노트·오토메이션 점·서클·포트·케이블에 부모 기준 접근성 좌표를 적용한다. 창 이동·스크롤과 뒤집힌/확대 좌표를 반영한다.
- 스텝 행과 셀 객체를 같은 편집 문맥에서 유지해 스크롤 경계의 `elementHasNoFrame` 실패를 수정했다. 숨겨진 행·이전 편집 대상의 press guard를 유지한다.
- AppKit14개·Swift491개·Python29개, 실제14상태/21화면과 전체 음악/자산/패키지 비교 통과. [계약](docs/84-accessibility-geometry.md) · [QA](qa/accessibility-geometry-review.md).

## 개발 중 — 0.20.0 build 69 MIDI 선택의 직접 수치 편집

- 단일 선택의 실제 값과 다중 선택의 음정·시작·길이·세기 변화량을2열로 표시한다. 복제/삭제를 상단 선택 옆으로 옮겨 작은 창의 스크롤을 줄였다. Return/Tab 적용과 Esc 취소를 지원한다.
- 상대 길이/세기 변경은 노트 사이 차이·ID·미선택 데이터를 보존하고 범위를 벗어나면 전체를 거절한다. MCP `edit_notes`에 `length_delta`/`velocity_delta`를 추가하고 배포 kit를 맞췄다. 기존 절대 세기 계약은 유지한다.
- Swift491개·Python29개, native14상태/25화면·전체 음악/패키지 비교 통과. 실제 오류 무변경·항목별 Undo·MCP transaction·stale packet/GUI draft 거절을 확인했다. [계약](docs/83-midi-selection-inspector.md) · [QA](qa/midi-inspector-review.md).

## 개발 중 — 0.20.0 build 68 편집 위치 유지

- 세션 내 서클·원본 범위별로 스텝 페이지/분할/행 검색·음역, 궤도 MIDI 마디·음역, 오디오 원본 범위와 편집 스크롤을 기억한다. 현재 서클의 보기와 현재 오토메이션 파라미터의 표시 길이는 문서에 저장한다.
- 설정·연결 왕복의 자동 reveal이 저장 위치를 덮지 않게 정리하고, 세션 재열기 때 정밀 편집기를 새로 구성한다. 길이 축소·asset 변경·잘못된 숫자는 유효 범위로 정리하며 낮은 피아노롤 음역도 보정한다. 음악 revision/Undo는 보기 변경과 분리한다.
- Swift485개·Python28개, native19상태·43화면과 전체 음악/서명/패키지 비교 통과. 최초 후보와 최소 음역을 보정한 최종 후보의 근거를 구분했다. [계약](docs/82-editor-view-position.md) · [QA](qa/editor-position-review.md).

## 개발 중 — 0.20.0 build 67 저장한 작업 페이지 복귀

- optional 보기 정보로 현재 페이지·원본 범위·연결 검색/포트/대상/8방향/재연결·최근 전환·오토메이션 볼륨/팬을 저장한다. 이전 문서의 설정/스텝 모드를 유지하며 알 수 없는 미래 페이지는 기본 편집으로 읽는다.
- 재열기에서 현재 문서의 대상과 케이블을 재검증한다. 없는 서클은 유효한 상위 화면으로 이동하고 삭제된 전환·재연결을 정리한다. 음악 Undo는 현재 보기 정보를 보존하며, 복원은 음악이나 플러그인을 실행하지 않는다. 연결 화면에는 편집 범위를 표시한다.
- 같은 문서 재열기 후 오래된 SwiftUI 상태로 검색 저장이 누락되는 결함을 세션 identity로 수정했다. 깨끗한 Swift477개·Python28개, 최종 native18상태·20화면·전체 음악/패키지 검사 통과. 증분 빌드 실패와 수정 전 native 결함은 별도 기록했다. [계약](docs/81-saved-workspace.md) · [QA](qa/saved-workspace-review.md).

## 개발 중 — 0.20.0 build 66 연결 작업과 전환 복귀

- 같은 세션의 서클·원본 범위별 연결 검색·포트·대상·8방향·목록 범위·재연결을 기억한다. 명시적 포트/케이블 요청을 우선하며 삭제·변경된 케이블의 기억은 선택과 함께 해제한다. 음악 schema와 Undo에 임시 작업을 넣지 않는다.
- 섹션 편집과 최근 전환을 별도 상단 버튼으로 바로 오간다. 이름 draft를 먼저 확정하고 연결 본문과 상단 버튼을 같은 Tab/Shift-Tab 순서로 묶어 Return으로 이동한다. 유효하지 않은 최근 전환 버튼은 숨긴다.
- Swift469개·Python28개·release, 실제27상태·상태 복원34화면·최종 키보드7화면, 실제 재연결/Undo·세션 초기화·전체 음악 비교와 패키지 검사 통과. 재실행 후 작업 페이지 영속화와 물리 입출력은 후속이다. [계약](docs/80-workspace-return.md) · [QA](qa/workspace-return-review.md).

## 개발 중 — 0.20.0 build 65 음악 설정 가시성과 직접 출처

- 섹션 연결 진입을 한 줄로 줄이고 길이·반복을 상단에 배치했다. MIDI 시작·길이·반복은 한 행에서 입력하며 리듬 패턴을 박 분할·강세보다 먼저 보여준다.
- 기본값·앨범·개별 출처를 직접 버튼으로 바꾸고 보관값 도움말을 제공한다. 실제 검사에서 발견한 Tab 건너뛰기·캔버스 전달을 수정해 시스템 설정과 관계없이 Tab/Shift-Tab/Return으로 출처와 숫자 필드를 이동한다. 유효값·개별 보관·Undo 계약을 유지한다.
- Swift463개·Python28개·release 및 실제23상태·최종21화면 통과. 섹션/MIDI/앨범/곡의 직접 편집·전체 복원·저장 재열기를 확인했다. 물리 입출력은 미검증이다. [계약](docs/79-music-settings-visibility.md) · [QA](qa/music-settings-review.md).

## 개발 중 — 0.20.0 build 64 섹션 순서·전환 작업 통합

- 설정의 다음 섹션 메뉴와 케이블 행을 기존 연결 편집기로 모으고, 설정 첫 항목에서 바로 열도록 했다. 번호·이름·곡/편곡 경로와 한글/전각/#정확 검색으로 동명 대상을 구분한다.
- 같은 화면에서 실제 재생 분기를 고르고 전환 편집·재연결·해제를 수행한다. 단일 자동 경로·선택 분기·종료 섹션 의미를 Compiler와 맞추고, 케이블 주소와 편곡을 검증하며 현재 편집 위치·기존 효과·다른 곡을 보존한다. 전환 앞/뒤에도 번호와 전체 이름을 표시한다.
- Swift463개·Python28개·최종 release 통과. 실제 27상태/22화면에서 키보드·새 연결/분기/전환/재연결/해제·Undo/Redo·오디오/MIDI 포트·저장 복원을 검사했다. 반복 경로와 Tab 순서도 정리했다. 물리 재생·녹음은 미검증이다. [계약](docs/78-section-connection-workspace.md) · [QA](qa/section-connection-review.md).

## 개발 중 — 0.20.0 build 63 편곡안 직접 검색

- 곡·악장의 편곡안 메뉴를 한 캔버스의 검색으로 바꾸고 서클 버튼·설정 첫 항목·⌥⌘J·명령 검색을 연결했다. 선언된 순번, 이름, 섹션 수와 재생 편곡을 표시하며 한글·전각·정확한 #번호 검색을 지원한다.
- 현재 재선택은 음악/Undo/Redo/편집 위치를 유지하고 다른 선택은 한 번의 Undo로 되돌린다. 다른 곡·음악 변경·새 세션·녹음/가져오기 상태를 검사해 오래된 요청을 막고 이름 draft를 먼저 확정한다.
- Swift457개·Python28개·release 통과. 실제 2곡/67편곡·26상태·24화면에서 키보드·빈 편곡·소유 범위·충돌·저장 복원을 검사하고 가려진 설정 버튼을 맨 위로 옮겼다. 물리 재생/녹음은 미검증이다. [계약](docs/77-arrangement-search.md) · [QA](qa/arrangement-search-review.md).

## 개발 중 — 0.20.0 build 62 MCP 음색 조회

- GUI와 같은 catalog/search를 읽는 `circlr_sounds`를 추가했다. 이름·계열·제조사·정확한 #번호, 악기/효과·드럼 필터, 최대 128개 페이지와 catalogID 변경 검사를 지원한다. 실제 음색 ID와 raw program/LSB/drums 또는 state 없는 AU descriptor를 반환한다.
- snapshot.runtime에 build·soundCatalog capability를 추가하고 read-only 역할과 번들 에이전트 키트에 조회 방법·기존 patch 보존 규칙을 반영했다. 성공한 읽기는 문서·포커스·재생·activity·쓰기 캐시를 변경하지 않는다. adapter 도구는 23개다.
- Swift 451개·Python 28개·release와 패키지 검사 통과. 실제 stdio MCP 3회, 각 7페이지/254악기와 10검색, 적용/Undo/Redo·최소화·저장 재열기·GUI 4화면을 검증했다. 물리 재생·실제 AU 작동은 미검증이다. [계약](docs/76-agent-sound-catalog.md) · [QA](qa/agent-sounds-review.md).

## 개발 중 — 0.20.0 build 61 Sound Bank 이름·변형 검색

- 설치된 macOS Sound Bank metadata에서 실제 음색을 읽어 이름·한글 계열·정확한 `#1`–`#128` 번호로 검색한다. 멜로디/드럼 킷과 같은 번호의 변형 뱅크를 구별하며 숫자 stepper와 별도 드럼 toggle을 검색으로 통합했다.
- optional `Instrument.bankLSB`를 저장하고 재생 로더에 같은 주소를 전달한다. 생략은 기존 기본 뱅크 0이며 유효 범위는 0–127이다. 같은 선택은 no-op, 다른 선택은 비활성 patch/state를 보존하며 한 번의 Undo로 복원한다. 새 변형 음색은 build 61 이상이 필요하다.
- 검색 화면의 적용 범위·현재 음색·충돌 안내가 압축돼 보이지 않던 높이를 수정했다. Swift 445개·Python 26개, 최종 release·native 16상태/18화면·저장 재열기·패키지 검사 통과. 물리 출력·실제 변형 음색 청취는 미검증이다. [계약](docs/75-sound-bank-program-search.md) · [QA](qa/sound-bank-search-review.md).

## 개발 중 — 0.20.0 build 60 음색·Audio Unit 검색

- 악기 종류와 음색의 중첩 메뉴를 내장 신스·Sound Bank·설치된 AU 검색으로 합쳤다. 이름·제조사·종류 필터, 현재 음색 찾기, ↑↓·Return·Esc, 명령 검색 진입을 지원한다. 서클과 전역 이펙터도 같은 검색을 사용한다.
- 같은 신스/AU 재선택은 수정한 patch와 plugin state를 보존한다. 종류 메뉴에서 AU 검색을 열었다 취소해도 이전 효과가 유지된다. 프로젝트·세션·revision·대상이 바뀌거나 녹음/준비/import 중이면 오래된 요청을 거절한다.
- Swift 437개·Python 26개와 release build, native 23상태·20화면, Undo/Redo·외부 수정·미설치 AU·저장 재열기·패키지 검증 통과. [계약](docs/74-sound-selection-search.md) · [QA](qa/sound-selection-review.md). 서브 에이전트 dispatch는 현재 세션의 thread limit으로 실패해 역할별 순차 검토했다.

## 개발 중 — 0.20.0 build 59 섹션·서클 직접 검색

- 작업 이동 결과를 실제 섹션·MIDI·오디오·음색·이펙트·라우터·믹스·출력으로 바꿨다. Return/클릭은 표시한 대상을 열며, 빈 섹션도 바로 이동한다. 섹션 메뉴를 전체 앨범/이 섹션과 종류 필터로 대체했다.
- 같은 역할의 여러 서클 버튼은 섹션·트랙·종류가 지정된 검색을 연다. 현재 위치 찾기, 트랙 제한 해제, 이름/경로 두 줄과 전체 도움말, 번호·공유 경로 구분, 입력 포커스 복귀를 지원한다.
- Unicode·역할 동의어와 명시적 트랙/섹션 번호를 검색한다. 정규화된 catalog를 탐색 revision에 맞춰 갱신하고 오래된 행을 재검증한다. Swift 429개·Python 26개, 최종 검색 6개, native 직접 진입·Undo/Redo·외부 이름 변경·저장 재열기와 패키지 검증 통과. [계약](docs/73-direct-work-navigation.md) · [QA](qa/direct-work-navigation-review.md).

## 개발 중 — 0.20.0 build 58 라이브러리 대상 트랙 검색

- 단일 오디오의 긴 트랙 메뉴를 같은 화면의 이름·번호 검색 목록으로 바꿨다. Unicode 검색, 프로젝트 순서 번호, 대상 섹션의 오디오/MIDI 사용량, 긴 이름과 현재 대상 표시를 제공한다.
- ↑↓·Return·클릭 선택과 Esc 복귀는 파일 검색·선택·시작 박·원본/이번 사용 범위를 유지한다. 선택 후 footer도 번호로 동명 트랙을 구별한다. 요청과 파일 ID가 바뀌면 오래된 선택을 거절한다.
- Swift 423개·Python 26개, 마지막 관련 검사 9개, native 99트랙 검색·실제 import/Undo/Redo·저장 재열기와 패키지를 검증했다. [계약](docs/72-library-track-search.md) · [QA와 검증 경계](qa/library-track-search-review.md).

## 개발 중 — 0.20.0 build 57 접힌 그룹 작업 이동

- ⌘J·트랙 역할 버튼·MCP focus가 선택 경로의 그룹만 scene에서 펼친다. 이동은 그룹의 collapsed/layout override·dirty·음악/포트 revision·Undo/Redo를 바꾸지 않는다.
- Esc/다른 경로 선택 시 저장된 접힘 상태를 보여주며 현재 scene에 맞춰 복귀한다. 명시적 그룹 펼치기/접기의 Undo는 유지한다. 접힌 그룹 내부 선택과 편집 화면을 저장·재열기에서 복원한다.
- 깨끗한 Swift 419개·Python 26개, 최종 경로 테스트 6개, native 오디오 편집/Undo/Redo·상위 복귀·명시적 그룹 편집·MCP·저장 복원·패키지 검증 통과. [계약](docs/71-navigation-group-reveal.md) · [QA와 메뉴 전환 입력 범위](qa/navigation-reveal-review.md).

## 개발 중 — 0.20.0 build 56 보기 설정과 음악 이력 분리

- 궤도/자유 배치·그리드·스냅의 메뉴와 명령 검색은 dirty/recovery를 갱신하며 저장된다. Undo를 추가하거나 Redo를 지우지 않고 음악/포트 revision을 바꾸지 않는다.
- 음악 Undo/Redo는 현재 보기 설정을 유지한다. 실제 서클 위치·정렬·그룹·포트 편집의 이력은 보존하며 nil/다른 앨범 ID의 구조를 복원 과정에서 바꾸지 않는다.
- Swift 413개·Python 26개, native 보기 변경→MIDI Undo/Redo·서클 이동 Undo·⌘S·재실행 저장 복원 및 최종 앱 검증 통과. [계약](docs/70-canvas-view-history.md) · [QA](qa/view-history-review.md).

## 개발 중 — 0.20.0 build 55 음악 위치 표시 통일

- 오디오 배치·MIDI 시작·오토메이션 위치·부모 안의 서클 시작과 가져오기가 첫 위치 1박을 사용한다. 접근성 설명과 오류 범위도 같은 기준이다. 기간/길이/초와 모델·MCP의 0 기반 beat는 보존한다.
- 공통 숫자 입력의 표시/해석만 변환해 기존 미세 위치가 포커스·Tab·Return·Esc로 반올림되지 않게 한다. MIDI 가져오기는 섹션 끝을 거절하면서 끝 직전의 0.001박보다 작은 간격도 허용한다. 오토메이션 끝 위치와 전체 길이를 구별한다.
- Swift 406개·Python 26개, native 입력·세 MIDI 편집기·오토메이션 궤도/선형·서클 설정·오디오/MIDI 가져오기·Undo·재열기와 패키지 통과. 보기 모드 전환이 음악 Undo에 섞이는 기존 동작을 후속 UX 항목으로 기록했다. [계약](docs/69-beat-position-display.md) · [QA](qa/beat-position-review.md).

## 개발 중 — 0.20.0 build 54 라이브러리 가져오기 위치

- 긴 대상 메뉴를 곡·섹션 검색 목록으로 바꿨다. ↑↓/Return·클릭으로 선택하며 Esc로 파일 목록에 돌아온다. 검색어·다중 선택을 유지하고 캔버스·음악·Undo는 바꾸지 않는다.
- 같은 footer에서 1 기반 시작 박·현재 마디·초·전체 길이를 확인하고 단일 오디오의 기존 트랙/새 트랙을 정한다. 여러 오디오는 각 새 트랙, MIDI는 기존 트랙 선택 화면으로 같은 위치를 전달한다. 새 섹션 선택은 이번 사용·첫 박·새 트랙이다.
- 범위 오류는 입력란에 남기고 Return/Esc 뒤 파일 검색으로 돌아온다. 오래된 프로젝트·선택·revision·대상 입력은 거절한다. Swift 401개·Python 26개 및 최종 수치/배치 관련 13개, native 오디오/MIDI/batch·충돌·Undo·저장 복원과 패키지 검사를 통과했다. [계약](docs/68-library-import-placement.md) · [QA](qa/library-placement-review.md).

## 개발 중 — 0.20.0 build 53 폴더 관리와 오류 복구

- 라이브러리 상단에서 같은 화면의 폴더 목록으로 바로 전환한다. 전체 경로·파일 수·읽기 상태와 파일 보기/등록 해제를 제공하고, 동명 폴더는 구분되는 상위 경로로 표시한다. 기존 제거 하위 메뉴를 없앴다.
- 관리 화면 왕복에서 검색어·다중 선택을 유지한다. 관리 중 preview를 막고 Escape로 직접 닫는다. 선택/입력 오류와 폴더 읽기 경고를 분리해, 선택을 수정하면 해결된 오류만 지우고 혼합 오류의 중복 표시를 없앴다.
- Swift 396개·Python 26개, 최종 native 관리/검색/오류 복구·동명 파일 import·등록 해제·한 번 Undo·저장 복원과 패키지를 검사했다. 물리 출력·VoiceOver 발화·디스크 분리 경쟁은 미검증이다. [계약](docs/67-library-folder-workspace.md) · [QA](qa/library-folders-review.md).

## 개발 중 — 0.20.0 build 52 라이브러리 일괄 가져오기

- 기존 샘플 검색 화면에 체크박스·Shift 범위 선택·전체 선택/해제와 선택 수·현재 파일·새 트랙 수를 추가했다. 검색/필터가 바뀌면 보이는 결과만 선택에 유지하며 한 번에 최대 64개를 지원한다.
- 여러 폴더의 오디오는 같은 시작 박의 각 새 트랙으로 한 번에 적용하고 Undo도 한 번에 되돌린다. MIDI는 단일 파일의 기존 트랙 선택을 유지하며 혼합 선택·파일/batch 용량·오래된 파일 정보를 재검증한다. 작업이 끝날 때까지 모든 등록 폴더의 읽기 scope를 유지한다.
- 선택 변경은 현재 파일의 preview를 취소한다. snapshot에는 파일 정보 없이 선택 개수만 추가했다. Swift 391개·Python 26개, native 혼합/손상 거절·다중 import·Undo/Redo·저장/재열기·원본 보존과 최종 패키지를 확인했다. 물리 출력과 VoiceOver 발화는 미검증이다. [계약](docs/66-library-batch-import.md) · [QA](qa/library-batch-review.md).

## 개발 중 — 0.20.0 build 51 MIDI 파트와 코드 선택

- 피아노 롤·궤도·스텝의 속성 영역에 선택 유무와 관계없이 노출하는 메뉴와 해제 버튼을 추가했다. 전체/반전·같은 음높이·같은 시작 박 선택을 현재 서클 전체에 적용하며 여러 기준 선택과 화면 밖 노트도 포함한다.
- 편집기 포커스에서 ⌥P/⌥T/⌥I/⇧⌘A를 지원한다. 기존 anchor를 유지하고 선택만으로 음악·revision·Undo·audition을 바꾸지 않는다. 문자 입력에는 선택 단축키를 적용하지 않는다.
- 메뉴임을 보여주는 화살표와 접근성 중복 노출을 수정했다. 같은 시작 박 선택은 실제 시작의 0.0000001박 오차만 허용하며 음악을 양자화하지 않는다.
- Swift 386개·Python 26개와 최종 release/패키지 통과. 실제 세 편집기·드럼/음정 행의 선택, 음악 편집/Undo·입력 보호·다른 사용·저장 복원을 확인했다. VoiceOver 발화와 오래된 메뉴 callback 직접 재호출은 미검증이다. [계약](docs/65-midi-selection-tools.md) · [QA](qa/midi-selection-tools-review.md).

## 개발 중 — 0.20.0 build 50 MIDI 다중 노트 드래그

- 피아노 롤·궤도에서 선택 안의 노트를 잡으면 전체 선택을 유지한다. 본문은 시간·음정을 함께 이동하고 끝 손잡이는 공통 길이 증감을 적용한다. 선택 밖 노트는 단독으로 편집한다.
- 이동량을 격자에 맞춰 off-grid 그루브·노트 간격·길이 차이를 보존한다. 화면 밖 선택까지 시간/음정/최소 길이를 함께 제한하며 클릭만 하거나 경계에서 멈추면 Undo를 만들지 않는다. 키보드 다중 길이 조절도 같은 경계를 사용한다.
- 한 번의 mouse-up에 한 번 편집하며 대상·revision·선택·배치·격자·화면 변경 뒤 이전 드래그를 거절한다. 선택 영역에 직접 조작 안내를 표시하고 접근성 시간의 과도한 소수점을 정리했다.
- Swift 382개·Python 26개, 최종 앱의 피아노 롤/궤도 이동·길이·Undo·비선택 보존·저장 복원과 패키지 검증을 통과했다. 드래그 도중 외부 변경 주입·Shift 클릭 실제 입력·VoiceOver 발화는 미검증이다. [계약](docs/64-midi-group-drag.md) · [QA](qa/midi-group-drag-review.md).

## 개발 중 — 0.20.0 build 49 오디오 원본 탐색

- 파형 위 휠 확대·축소, 가로/Shift 휠 시간 이동과 확대 버튼, −/+·Page Up/Down·Home/End·0/F/C 탐색을 추가했다. 포인터의 원본 시간·최소 배율·파일 경계를 유지하며 탐색은 음악과 Undo를 변경하지 않는다.
- 캔버스의 공통 휠 처리에서 오디오 파형으로 이벤트를 전달한다. 숫자 입력 중 휠이 작성 중인 값을 확정하지 않으며, 오래된 대상/표시 변경 중 drag를 거절한다. 작은 창에서는 하단 조작을 한 줄로 합쳐 원형 파형과 시간 표시 공간을 확보했다.
- Swift 377개·Python 26개, 최종 앱의 휠·키보드·직접 트림·Undo·범위 유지·대상/원본 전환·저장 복원과 패키지 검증을 통과했다. Shift/가로 휠 hardware와 VoiceOver 발화는 미검증이다. [계약](docs/63-audio-source-navigation.md) · [QA](qa/audio-source-navigation-review.md).

## 개발 중 — 0.20.0 build 48 오토메이션 시간 탐색

- 서클 길이 밖의 오토메이션에도 마지막 박자를 이어 마디 눈금을 표시한다. 변박·부분 마디의 경계를 유지하고 긴 범위의 희소 눈금과 글자 겹침을 처리한다. 표시용 clock metadata를 추가하며 재생·보간·schema는 유지한다.
- 이전/다음·Home/End는 선택 점까지 표시 범위를 펼친다. 점 번호·마디/박/초·선택 점 보기를 제공하고 편집/Undo·배치 전환 때 범위를 유지한다. 현재 AX 점 선택의 대상·세션·범위도 검사한다.
- 깨끗한 빌드의 Swift 374개·Python 26개, 두 배치의 native 탐색·수치/키보드 편집·한 Undo·범위/대상 분리·원본 복원과 패키지 검증을 통과했다. 최초 증분 테스트 충돌은 별도 기록했다. [계약](docs/62-automation-time-navigation.md) · [QA](qa/automation-time-navigation-review.md).

## 개발 중 — 0.20.0 build 47 드럼 행 탐색

- 드럼 스텝에서 행·샘플 이름·MIDI 번호를 바로 검색한다. 일치/전체 수·빈 결과·선택 행 복귀를 표시하며 Return/Esc로 격자에 돌아간다. Unicode/전각·대소문자와 ASCII 샵/플랫을 정규화한다.
- 행 추가는 검색을 지우고 현재 스텝 열을 유지한 채 해당 pitch로 이동한다. 이름 클릭은 선택만 하며 Home/End·PageUp/PageDown으로 탐색한다. 필터·모드 변경 뒤 커서와 스크롤을 맞춘다.
- 보이는 행만 그리기/AX에 노출하고 오래된 셀 action의 대상·pitch·페이지·격자를 검사한다. Swift 369개·Python 26개, 작은 창의 실제 검색·입력/Undo·대상 분리·저장 복원 및 패키지 검증을 통과했다. [계약](docs/61-step-row-navigation.md) · [QA](qa/step-row-navigation-review.md).

## 개발 중 — 0.20.0 build 46 MIDI 음역 탐색

- 전체 MIDI 연주 분포와 현재 1/2옥타브 범위를 표시한다. 클릭·드래그·좌우/Shift 좌우·Home/End와 접근성으로 음역만 이동하며 Return/Esc는 노트 생성 없이 궤도로 복귀한다.
- 선택/가리키는 음을 중앙에 표시하고 C 기준 음명의 겹침을 피한다. 작은 창의 편집 방식·이전/다음 노트·MIDI 메뉴·바운스/녹음을 기존 영역의 위/아래에 고정한다.
- Swift 366개·Python 26개, 실제 0–127 탐색·노트 편집/Undo·빈 lane·다른 사용·저장/복원 및 패키지를 검증했다. Hover-only·VoiceOver는 별도 미검증이다. [QA](qa/pitch-navigation-review.md).

## 개발 중 — 0.20.0 build 45 이름 확정과 취소

- 이름을 초안으로 보관하고 Return/Tab/blur에서 한 번 적용한다. Esc는 최신 모델을 복원하며 Return/Esc 후 캔버스 키보드 포커스를 유지한다.
- UI 저장·프로젝트 교체는 활성 이름을 먼저 확정한다. 빈 이름·여러 줄·새 이름 길이·외부 revision/대상/값 변경을 검사하며 모델이 거절하면 초안을 유지한다. MCP 저장은 기존 committed 데이터 계약을 유지한다.
- 오류는 같은 헤더 안에 표시하고 불변인 앨범 사운드 제목은 일반 Text로 표시한다. Swift 363개·Python 26개, 실제 Unicode 저장/재열기·충돌·한 번 Undo·그룹 및 원본 보존을 검증했다. [QA](qa/name-editing-review.md).

## 개발 중 — 0.20.0 build 44 캔버스 이름과 선택

- 주 선택 이름을 320px·최대 세 줄, 한글 단어 우선 줄바꿈과 더 굵은 테두리로 표시한다. 다른 이름은 한 줄 밀도를 유지하며 hover로 크기를 바꾸지 않는다.
- 정상 배치가 실패하면 주 선택만 화면 가장자리 후보를 탐색한다. 연결 도구·선택 포트·시간 손잡이를 피하며 실제 라벨 사각형을 클릭/AX에 사용한다.
- Swift 353개·Python 26개, 실제 밀집 이름·화면 밖 중심·연결 방향·궤도 시간 이동·Undo/저장 복원과 패키지를 검증했다. 제목 입력의 확정/취소·한 Undo와 실제 VoiceOver는 후속 범위다. [QA](qa/canvas-label-review.md).

## 개발 중 — 0.20.0 build 43 미리 듣기 worker

- 신스·샘플러·Audio Unit 미리 듣기의 생성/노트/샘플 렌더/정리를 UI 밖으로 옮겼다. 현재 누른 노트만 보관하고 준비 중 release, 같은 pitch 재누르기, 오래된 자동 note-off와 target 변경을 구분한다.
- 준비·정리 중 backend를 중복 생성하지 않으며 10초 timeout/Space 취소 상태를 transport 줄과 MCP snapshot에 표시한다. 새로운 요청이 진행 중인 장치 대기 시간을 초기화하지 않는다.
- Swift 345개·Python 26개 및 실제 sampler 준비 대기 중 편집/취소·Undo/저장/재열기·worker/main stack·패키지를 검증했다. HAL 연결 완료·정상 소리·마이크·출고 MP4는 미검증으로 유지한다. [QA](qa/audition-worker-review.md).

## 개발 중 — 0.20.0 build 42 MIDI 가져오기 위치

- MIDI의 시작 박과 자유 배치 좌표를 메뉴·라이브러리·drop에서 공통 초안으로 전달한다. 1부터 세는 4분음표 박 입력, 예상 끝 위치, 초과 시 확정 비활성화와 이번 섹션 연장을 같은 화면에 제공한다.
- 선행 쉼표·노트 간격·길이·세기와 기존 트랙·공유 원본·다른 사용·전역 routing 위치를 보존한다. 성공한 여러 트랙은 한 번에 Undo하며 단일 MIDI는 편집기로, 여러 MIDI는 섹션 전체로 이동한다.
- 새 초안의 선택 상태를 초기화하고 revision/session 변경 시 이유를 표시하며 적용을 거절한다. [QA](qa/midi-placement-review.md)에 자동 검사, Native 시작 위치/길이/Undo/저장 근거와 Finder 실제 gesture 제한을 구분한다.

## 개발 중 — 0.20.0 build 41 연결 대상 직접 탐색

- 대상 포트를 이름/IN·OUT 두 줄의 검색 목록에서 직접 선택한다. 검색창과 목록의 ↑↓·Tab·Return으로 연결하며 미선택/무결과/사라진 대상은 적용하지 않는다. 그룹 관리의 기존 키보드 동작을 보존한다.
- 포트·위치·검색·연결 조작을 목록 위에 고정하고 결과 높이를 현재 작업 영역에서 계산한다. 기존 케이블은 독립 스크롤하며 전체/현재 포트 필터, 한 행의 재연결·해제·8방향 위치를 제공한다. 생략된 상속 리듬은 실제 이름을 표시한다.
- Swift 330개·Python 26개, release와 Native 검색/입력 방향·재연결·위치 Undo·그룹 필터·작은/확장 영역·저장 복원을 확인했다. 검증 중 발견한 목록 아래 조작 표시 누락을 최종 배치로 해소했다. 사용자 0.19 앱과 실제 출력/입력 출고 조건은 유지한다. [QA](qa/connection-workspace-review.md).

## 개발 중 — 0.20.0 build 40 전환·효과 작업 공간

- 앞·뒤 섹션, 전환 방식·길이 기준과 실제 초·다음 시작 변화를 같은 캔버스에 배치했다. 변박·tempo map·소수 마디 계산을 컴파일러와 공유하며 연결 편집에서 돌아와도 전환 대상과 캔버스 포커스를 유지한다.
- 전역·음악 서클·전환 효과의 수치 입력을 공통 입력기로 통합했다. 게인은 dB, 다른 파라미터는 최대 소수 세 자리로 표시하면서 원래 정밀도를 보존한다. Tab/Shift-Tab 연속 입력, 범위·외부 변경 거절과 Return/Esc 복귀를 지원한다.
- 끝부분 전환의 트랙 비우기, 리듬 없는 삽입, 자동 페이드 겹치기에 맞춰 실제 적용되지 않는 효과를 숨긴다. 기존 설정값과 저장 형식·DSP는 유지한다.
- Swift 330개·Python 26개, release 및 실제 작은 창의 전환 시간·효과 수치·오류/충돌·Undo·저장/재열기와 73초 WAV export를 검증했다. 사용자 앱은 0.19를 유지하며 물리 출력·마이크·VoiceOver는 남아 있다. [QA](qa/transition-effects-review.md).

## 개발 중 — 0.20.0 build 39 편집 위치와 작업 전환

- 편집기 제목·트랙 경로·본문·하단 안내의 배치를 분리했다. 노트 선택 속성이나 작업 전환이 상단 위치를 밀어내지 않으며, 긴 MIDI·오디오·궤도 오토메이션 속성은 본문 안에서 스크롤한다. 행 간격을 줄이고 오디오 음소거·삭제와 녹음 테이크를 위에서 바로 접근하게 했다.
- 중복 의미의 ‘편집으로’ 토글을 MIDI/오디오·연결·오토메이션·설정 버튼으로 바꾸고 현재 작업을 시각 및 접근성 selected 상태로 표시한다. 그룹 연결에서도 편집으로 직접 돌아간다. MIDI import 초안 중 전환을 막으며 설정 전환 시 열린 플러그인 편집기를 정리한다.
- 최종 Swift 325개·Python 26개, release build와 실제 작은 창의 피아노·스텝·궤도 선택, Tab 연속 입력, 작업 왕복, 오토메이션, 콘솔 접기, Undo·저장·재열기를 확인했다. 사용자 앱은 0.19를 유지하며 물리 출력·마이크·VoiceOver 검증은 남아 있다. [QA](qa/editor-shell-review.md).

## 개발 중 — 0.20.0 build 38 오디오 작업 공간

- 오디오의 배치·원본 시작/끝·분할과 볼륨 dB·페이드 ms를 파형 양옆에 배치했다. 전체 파일/선택 구간·복제·트랙 바운스와 원본 복원을 위에서 바로 수행한다. 작은 창의 파형 높이를 확보하고 초/ms 표시를 정리하며 실제 정밀도를 보존한다.
- 숫자는 명시적인 Tab 순서로 이동하고 Return/Esc 뒤 파형 키보드로 돌아간다. 궤도/자유 배치에서 같은 원본 표시 범위를 유지하며 실제 원본 끝점만 핸들로 표시한다. 바깥 섹션 시간과 안쪽 source 시간, 템포에 따른 재생 길이를 구별한다.
- 직접 클립 편집을 원자적 copy-on-write 경로로 통합했다. 공유 참조 중 선택 노드만 새 clip을 받으며 잘못된 identity/값은 전체 거절한다. 숫자·드래그·방향키는 같은 페이드/renderWindow trim 경계를 사용한다.
- Swift 325개·Python 26개와 release, 실제 연속 입력·trim·Undo·충돌 거절·분할/복제·34초 바운스/복원·저장/재열기를 확인했다. 실제 출력·마이크·VoiceOver와 사용자 앱 출고 조건은 남아 있다. [QA](qa/audio-workspace-review.md).

## 개발 중 — 0.20.0 build 37 스텝·피아노 롤 작업 공간

- 아래로 쌓였던 선택 속성을 같은 캔버스 오른쪽에 배치했다. 세 MIDI 편집기가 음높이·시작·길이·세기, 이동/퀀타이즈·복제/삭제를 공유한다. 속성은 명시적인 Tab/Shift-Tab 순서와 공통 숫자 충돌 보호를 사용한다.
- 스텝 번호를 고정하고 드럼 행 추가를 도구 줄에 넣었다. 선택 노트의 onset에 페이지·행·키보드 커서를 맞추며 분할/드럼 행/페이지는 피아노 롤·궤도 왕복 시 유지한다. 수동 페이지 변경은 선택만 해제한다.
- 피아노 롤은 20 px 행과 고정 음높이/박 눈금으로 표시하고 선택 노트의 음역·가로/세로 스크롤을 따라간다. 드래그 중 자동 스크롤은 보류하며 프로젝트·대상·revision/음역·disabled 변경 뒤 이전 드래그를 적용하지 않는다. 단순 클릭은 음악 Undo를 만들지 않는다.
- Swift 319개·Python 26개, release와 실제 작은 창의 스텝 입력·연속 수치·고정 눈금·피아노 이동/길이·개별 Undo·MCP 충돌·저장 복원을 확인했다. 사용자 앱 출고, 물리 오디오·VoiceOver·전체 밀집 조합은 남아 있다. [QA](qa/midi-grid-workspace-review.md).

## 개발 중 — 0.20.0 build 36 MIDI 궤도 작업 공간

- 작은 창에서 선택 노트 속성이 궤도를 누르지 않도록 같은 캔버스에 음역/마디 탐색, 중앙 궤도, 음높이·시작·길이·세기를 배치했다. 기본 4마디, 1/2옥타브, 전체 길이, 이전/다음 노트와 화면 밖 선택 보기로 탐색한다.
- 마디 페이지는 로컬 박자·tempo map을 따른다. 긴 노트는 현재 범위에서 계속 편집하고 실제 끝점에서만 길이를 조절한다. 그리는 격자의 밀도와 음악 입력 스냅을 분리했다. 궤도·스텝·자유 배치 왕복 시 범위를 유지한다.
- Return/Esc 뒤 궤도 키보드로 복귀하고 노트별 접근성 이름과 선택을 제공한다. 다중 선택은 일괄 편집만 표시하며 숫자/드래그의 대상·revision 보호를 적용했다.
- Swift 318개·Python 26개, release와 최종 앱의 입력·긴 노트 이동·Undo·충돌 거절·저장 복원을 확인했다. 물리 오디오·마이크·VoiceOver와 스텝/오디오 전체 UI는 후속이다. [QA](qa/midi-orbit-workspace-review.md).

## 개발 중 — 0.20.0 build 35 편집 화면 연속성

- 같은 프로젝트의 궤도/자유 배치 변경 때 선택 서클의 화면상 중심·반경을 보존한다. 메뉴의 강제 축소를 제거하고 명령 검색·Undo/Redo도 같은 장면 갱신을 사용한다. 배치 변경 중 이전 좌표의 캔버스 제스처는 취소한다.
- 오토메이션 전체 점 보기를 고정된 편집 범위로 바꿨다. 마지막 점 이동/삭제에 따라 범위가 줄어들지 않으며 밖에 생긴 점은 버튼으로 다시 맞춘다. 대상/파라미터/원본/프로젝트 전환 시 임시 범위는 초기화한다.
- 겹친 점은 Option 클릭으로 순환하고 일반 클릭은 현재 선택을 유지한다. 선택 점은 위에 그려 강조한다. Swift 311개·Python 26개, 실제 배치/끝점/범위·복원 및 최종 패키지를 검증했다. 작은 MIDI 궤도·오디오 속성 배치와 실제 출력/입력 등은 후속 범위다. [QA](qa/editing-continuity-review.md).

## 개발 중 — 0.20.0 build 34 오토메이션 작업 공간

- 긴 측면 ScrollView를 없애고 자유 배치는 전체 폭의 곡선과 입력 줄, 궤도는 중앙의 원과 같은 캔버스 양옆의 명령/선택 값을 사용한다. 볼륨 dB·팬 %·마디 눈금·로컬 박/초·공유 원본 전환을 표시한다.
- Return/Esc는 곡선 포커스로 복귀한다. 방향키의 볼륨 증감은 0.5 dB, Option은 0.1 dB, Shift는 3 dB이며 팬은 5/1/25%p다. 저장·DSP·선형 보간은 기존 신호값을 유지한다. 전체 점 보기의 실제 범위를 MCP snapshot에 반영한다.
- 숫자와 드래그가 프로젝트·세션·원본·대상·점·revision 변경 후 적용되지 않게 보호한다. Swift 307개·Python 26개, 최종 release와 실제 드래그/삭제/Undo·공유 범위·충돌·저장/재열기를 검증했다. 실제 출력·입력·VoiceOver 출고 조건과 사용자 0.19 앱은 유지한다. [QA](qa/automation-workspace-review.md).

## 개발 중 — 0.20.0 build 33 출력 레벨 편집

- 출력 전용 편집기에 서클별/트랙 전체 레벨을 분리하고 dB 숫자·fader·음소거·0 dB 복원·볼륨/팬 오토메이션 바로가기를 추가했다. 중복 제목과 여백을 줄여 작은 창에서 두 범위를 함께 표시하며 악기 편집기는 음색에 집중한다.
- 선형 gain 저장과 DSP를 유지하고 표시만 dB로 변환한다. −∞와 -inf는 무음이며 읽기만 할 때 원래 정밀도를 보존한다. 공유 원본의 gain/muted만 수정해 다른 사용 override가 원본으로 섞이지 않게 했다.
- Native 검사에서 fader의 중간 재배치와 움직이지 않은 클릭의 불필요한 Undo를 수정했다. 드래그 한 번/방향키 한 번에 적용 한 번, 외부 revision 변경 거절, Return/Esc/Tab과 저장 복원을 확인했다. Swift 303개·Python 26개 및 release 통과. 사용 앱은 0.19이며 정상 출력·마이크·VoiceOver 등 출고 조건은 남아 있다. [QA](qa/output-editing-review.md).

## 개발 중 — 0.20.0 build 32 재생 worker와 숫자 입력 포커스

- AVAudioEngine/player의 생성·연결·시작·정지·시계 조회·해제를 직렬 background worker가 소유한다. UI는 값 snapshot만 읽으며 정리 중 재시도를 거절한다. 시작 취소/timeout 후 늦은 시작은 음소거 상태에서 정리한다.
- 출력 시작·정리·실패 상태를 기존 상태 줄과 additive MCP snapshot에 표시한다. 숫자 Return/Esc 후 주 캔버스에 포커스를 돌려 Space가 소실되던 문제를 수정했다. Tab 이동과 콘솔 문자 입력을 보존한다.
- 제어된 지연/취소/실패/종료 검사 8개를 포함해 Swift 293개·Python 26개 통과. 실제 작은 창의 숫자 확정·취소·Undo·Space 요청/취소·같은 attempt 재사용과 저장 복원을 확인했다. 시스템 HAL 지연과 정상 청감은 미해결이며 사용자 0.19 앱을 교체하지 않았다. [QA](qa/playback-worker-review.md).

## 개발 중 — 0.20.0 build 31 로컬 샘플 라이브러리

- 같은 캔버스의 샘플 검색에 폴더 추가·형식/경로 검색·방향키 선택·Return 가져오기·오디오 미리 듣기·MIDI 트랙 선택을 연결했다. 폴더는 앱 로컬 read-only bookmark로 보관하며 이동 시 갱신한다. 등록 제거는 원본을 유지한다.
- 색인/검색/정보 읽기/미리 듣기를 비동기로 처리하고 stale 대상·파일 변경·외부 경로·늦은 완료를 차단한다. MCP snapshot에 경로·bookmark 없는 라이브러리 작업 상태를 추가했다.
- Native에서 확인한 작은 창의 템포 줄바꿈, 영어 decoder 오류, 검색창의 ⌥Space 공백 입력, 대상 갱신 후 잔여 안내를 수정했다. 라이브러리 표시 중 배경 UI를 접근성 탐색에서 제외한다.
- 실제 HAL 지연으로 AVAudioPlayer.play가 UI를 막던 문제를 발견해 모든 player 호출을 백그라운드로 이동했다. 취소된 늦은 시작은 음량을 올리지 않으며 이전 작업이 끝나기 전 새 출력을 중복 준비하지 않는다. Swift 285개·Python 26개, release와 실제 가져오기/Undo/Redo/저장/재열기 등을 검증했다. [상세 근거와 남은 범위](qa/library-review.md). 사용자 앱은 0.19다.

## 개발 중 — 0.20.0 build 30 직접 음악 설정

- 같은 캔버스에서 음악 설정의 유효값과 기본값/앨범/개별 출처를 함께 표시한다. 값을 바꾸면 해당 항목만 개별로 전환하며 전체 적용 버튼을 제거했다. 출처를 전환해도 기존 개별값을 보관한다.
- 박자·스케일·박 분할/강세의 성분을 현재 모델에서 부분 변경한다. 공유 원본 편집은 원본 settings만 바꾸며 사용별 override를 원본에 복사하지 않는다. 강세 문자열을 엄격히 검증하고 오래된 입력을 거절한다.
- Swift 272개·Python 26개, release와 실제 섹션/global 입력·상속 전환·오류·외부 충돌·리듬 연결·Undo·재열기를 검증했다. 강세 확정 후 버튼이 남던 Native 결함도 수정했다. [검증 및 남은 범위](qa/context-editing-review.md). 사용자 앱은 0.19를 유지한다.

## 개발 중 — 0.20.0 build 29 공통 숫자 입력

- 신스·오디오·MIDI·출력·반복·템포의 공통 숫자 필드는 타이핑을 draft로 유지하고 Return/Tab·포커스 이동으로 한 번 확정한다. Esc 취소, 범위/유한 숫자/정수 검증, 포커스 테두리·오류 아이콘과 도움말을 제공한다. 읽기만 해서는 표시 자릿수로 저장값을 반올림하지 않는다.
- AppKit의 동기 편집 종료로 Tab 순서를 맞추고, live Binding과 프로젝트/세션/대상/revision 검증으로 빠른 연속 입력과 외부 변경 충돌을 구분한다. 오토메이션 숫자는 현재 point에서 해당 값만 바꿔 앞선 시간 편집을 보존한다.
- Swift 265개·Python 26개·release와 최종 build 29 앱의 MIDI/신스/오디오 연속 Tab, 정수/범위 오류, MCP 충돌, 대상 전환, 출력/반복/템포, 개별 Undo·정밀도·저장/재열기를 검증했다. [QA 및 후보별 결함 기록](qa/number-editing-review.md). 실제 VoiceOver·녹음 중 편집·전역/전환 및 legacy 위젯별 전체 검증과 E 출고 gate는 남아 있다. 사용자 앱은 0.19를 유지한다.

## 개발 중 — 0.20.0 build 28 효과 단위와 입력

- 공통 효과 편집에 실제 DSP 단위·슬라이더·수치 입력을 추가했다. 컷오프는 로그 눈금 Hz, delay는 ms, compressor는 dB/:1이며 reverb/반복 레벨·팬·드라이브·gain도 실제 의미를 표시한다. Audio Unit의 미사용 amount/secondary는 숨긴다.
- 효과 파라미터는 Return/포커스 이동 또는 드래그 종료 때 한 번 적용한다. Esc·범위 오류·동일 값은 음악을 바꾸지 않으며 다른 프로젝트/선택/효과에 오래된 입력을 적용하지 않는다. Tab 연속 입력에서 다음 칸이 이전 확정을 충돌로 오인하던 문제를 수정했다.
- 슬라이더가 방향키를 직접 처리해 캔버스 형제 서클로 이동하던 문제를 수정했다. 접근성 value description에 실제 단위를 포함한다. 같은 편집기의 음소거·출력 볼륨·바운스 행을 왼쪽에 모았다.
- Swift 259개·Python 26개와 release, 실제 1200 Hz 입력·invalid/Esc·−18 dB/4:1 연속 Tab·외부 편집 충돌·활성 창 drag/키보드·개별 Undo·저장/재열기를 검증했다. [build 28 QA](qa/effect-editing-review.md). 비활성 창의 CUA 첫 드래그와 실제 VoiceOver 발화·전역/전환 위젯별 Native 전체 검증은 남아 있다. 사용자 앱은 0.19를 유지한다.

## 개발 중 — 0.20.0 build 27 소스별 서클과 직접 이펙트

- 새 audio-only lane에서 빈 MIDI·악기를 자동 생성하지 않는다. 기본 화면은 오디오·믹스·출력이며 상속 오디오 리듬 경로는 유지한다. 첫 MIDI 노트 입력·명시적 리듬 생성 시 필요한 경로를 추가하고, 기존 문서의 서클과 사용자가 끊은 연결을 보존한다.
- 리듬 패턴 생성은 선택한 트랙을 우선하고 해당 트랙의 리듬 MIDI·악기를 함께 준비한다. 새 트랙을 추가해도 기존 마스터 위치를 옮기지 않으며 새 서클 사이의 기본 배치 겹침을 피한다.
- 같은 캔버스의 편집 경로에 이펙트 추가 메뉴를 둔다. 선택한 출력 앞의 전체 입력에 삽입하며 다른 트랙의 첫 mix를 임의로 고르던 경로를 제거했다. 다중 bus는 기존 명시적 연결 편집을 사용한다.
- Swift 253개·Python 26개와 release build 통과. 최소 창/콘솔 열림 상태의 실제 import→⌘J→오디오→이펙트→⌘1, 리듬 스텝·첫 MIDI·34초 WAV export, 여섯 번의 개별 Undo와 저장/재열기를 확인했다. [build 27 QA](qa/source-circles-review.md). 사용자 앱은 0.19이며 E의 마이크·VoiceOver·전체 밀집/장치/영상 출고 검증은 남아 있다.

## 개발 중 — 0.20.0 build 26 파일 가져오기

- 오디오 여러 파일을 owned staging에 복사·checksum·검증하고, 모두 정상일 때 한 번의 음악 mutation으로 추가한다. 취소·대상 revision 변경·잘못된 파일은 부분 적용하지 않는다. 한 파일은 현재 트랙, 여러 파일은 각 새 트랙을 사용한다.
- 여러 파일 뒤에는 섹션 전체를 표시하며 마스터를 포함한 기존 배치·연결을 보존한다. 파일 오류에 한국어 설명과 파일명을 표시한다.
- file-URL drop과 대상/박 미리보기를 구현했다. 궤도 각도는 박, 자유 배치 좌표는 서클 위치다. MIDI 한 파일은 기존 노트 트랙 선택 화면을 사용하며 혼합 배치는 거절한다.
- 메뉴/MCP 저장은 열린 세션의 로컬 미디어 참조를 유지한다. 프로젝트 패키지는 계속 상대 경로·복사본을 사용한다. 저장→Undo→저장→Redo 뒤 미디어가 사라지던 경로를 수정했다.
- Swift 245개·Python 26개, release build 및 메뉴의 다중 가져오기·Undo·오류 거절·MIDI 미리보기·대상 변경 방어를 검사했다. [build 26 QA](qa/media-import-review.md). 실제 Finder 드롭·file promise·중복 자산/GC·실제 마이크·전체 E 출고는 남아 있다.

## 개발 중 — 0.20.0 build 25 출력 대기와 키보드 복귀

- 장치 연결과 재생 대기 요청의 수명을 분리했다. monotonic 시간으로 대기하며 timeout·취소·재시도가 동일한 물리 연결을 공유한다. 취소 후 늦은 완료는 자동 재생하지 않는다.
- 재생 시계 아래에 출력 연결·대기 초·준비 완료를 표시하고 timeout은 nonmodal 상태로 알린다. MCP snapshot의 `output`으로 phase/step/request/attempt/elapsed를 조회한다. 계정·장치 선택 기능은 추가하지 않는다.
- 영상 준비 중 상단 재생 버튼이 준비 취소로 동작하도록 맞췄다. 팔로우가 MIDI 편집기를 제거한 뒤 Space가 소실되던 오류를 수정해 내부 키보드 포커스만 캔버스로 복귀시킨다. 외부 콘솔 입력은 유지한다.
- Swift 236개·Python 26개와 release build 통과. 실제 105초/162초 연결 지연, 취소·동일 attempt·늦은 준비를 관찰했고 최종 빌드에서 편집기→재생→Space 정지와 콘솔 공백 입력을 확인했다. [build 25 QA](qa/output-connection-review.md). HAL 지연 해결·장치 전환·마이크·VoiceOver·MP4 전체 출고 검증은 남아 있다.

## 개발 중 — 0.20.0 build 24 재생 화면과 편집 진입

- 일반 섹션 진입과 재생 팔로우를 실제 자식 서클의 경계에 맞췄다. 공통 캔버스 영역에 여백을 한 번 적용하고 접힌 그룹은 하나의 원, 빈 섹션은 자체 궤도로 다룬다. 부모 시간 궤도와 음악 배치는 유지한다.
- 이름표는 다른 작업 서클 내부와 기존 이름표를 피한다. 선택·hover·직접 자식 우선순위를 적용하며 활성 섹션의 중복 이름은 기존 재생 문구로 대신한다.
- 팔로우 중단이 늦은 SwiftUI update에서 새 수동 확대까지 취소하던 오류를 수정했다. 실제 재생 중 MIDI 이름표 더블클릭과 접근성 활성화로 편집기에 진입하고 휠·팔로우 재개를 검증했다.
- Swift 231개·Python 26개, release build와 큰 창/최소 폭·콘솔 네 조합의 이름표 8개 비겹침 검사 통과. QA 음악·포트·노드 위치를 복원하고 저장/재열기를 확인했다. [build 24 QA](qa/playback-framing-review.md). 최초 CoreAudio 출력 연결 지연·마이크·VoiceOver·전체 E 출고 검증은 후속이며 사용자 앱은 0.19를 유지한다.

## 개발 중 — 0.20.0 build 23 DAW 통합

- 녹음 lifecycle과 명시적 포트·독립 bus·그룹 노출을 통합했다. 연결 편집기와 녹음 상태를 같은 캔버스에서 사용하며 음악/배치 Undo를 보존한다. 녹음 시작·정리 중 음악 편집·Undo와 에이전트 쓰기를 차단하고, 재생 초기 장치 timestamp가 음수이면 시작 위치로 제한한다.
- MCP record와 포트 명령을 합쳐 22개 도구를 제공한다. 내장 adapter·operations·25개 파일 manifest와 버전을 동기화했다.
- Swift 226개·Python 26개, release build 및 별도 QA 앱의 MIDI 스텝·오토메이션·오디오 분할/페이드·바운스·그룹 이름·Undo·저장/재열기·닫기 최소화를 확인했다. 전면 창의 10회 관측에서 출력별 신호 모션을 확인했다. [통합 QA](qa/daw-integration-review.md).
- 실제 마이크 입력·VoiceOver·전체 밀집 조합은 미검증이다. 재생 follow에서 작은 자식 서클과 겹치는 라벨은 다음 UI 개선으로 기록했다. 사용자 앱은 0.19를 유지한다.

## 개발 중 — 그룹 노출 포트 D2 체크포인트

- 그룹 안의 실제 IN/OUT을 명시적으로 노출하고 이름 변경·노출 해제를 같은 캔버스에서 수행한다. 내부 대상과 케이블은 유지하며 metadata만 layout revision과 Undo에 저장한다. 사라진 대상은 미해결 상태로 보존하고 다른 포트로 자동 연결하지 않는다.
- 그룹 포트를 통한 새 연결·재연결은 원래 endpoint로 검증한다. 접힌 그룹의 외곽에 실제 포트 이름과 케이블을 표시하고 K/P 탐색·8방향 키보드/마우스 배치를 지원한다. 주변 연결이 숨겨지던 표시 규칙과 그룹 선택 시 연결 편집 의도가 사라지던 오류를 수정했다.
- 연결 적용 버튼을 편집기 상단으로 옮겼다. 이름 변경 중 내부 대상 선택은 비활성화한다. MCP는 set_group_port/remove_group_port와 group focus를 지원하며 도구는 21개다. scalar portID가 null로 반환되던 오류도 수정했다.
- Swift 212개·Python 25개와 release build를 통과했다. 실제 앱의 그룹 노출·이름 변경·연결·해제·Undo·8방향·드래그·저장/재열기를 확인했다. [D2 QA](qa/ports-group-review.md). 이번 빌드의 재생 신호 화면은 오디오 출력 장치 연결 timeout으로 미검증이며 VoiceOver·전체 조합·0.20 통합·사용 앱 출고도 후속이다.

## 개발 중 — 명시적 포트 MCP D1 단계

- 포트 descriptor·논리 주소·연결·배치를 읽는 `ports`와 `connect_ports`·`reconnect_ports`·`disconnect_ports`·`move_ports`를 추가했다. MCP 도구는 19개이며 읽기 전용 specialist는 ports 조회만 추가로 사용할 수 있다.
- project/music/layout revision을 함께 검사하고 GUI와 동일한 Core 명령·Undo를 사용한다. 양방향 시작·명시적 router bus·케이블 ID/gain 보존을 지원한다. 배치-only 명령은 음악 revision을 유지하고 중복/no-op는 Undo를 쌓지 않는다. undo에도 선택적 layout 충돌 검사를 추가했다.
- Swift 202개·Python 24개와 release build 통과. 전용 QA 앱의 최소화 상태에서 29개 기록 단계의 편집·오류 거절·Undo·저장/재열기를 확인했고 MCP 배치 변경을 앱의 ⌘Z 한 번으로 복원했다. [D1 QA](qa/ports-mcp-review.md).
- 내장 에이전트 키트의 adapter·사용 계약을 동기화했다. 그룹 노출 binding·실제 VoiceOver 발화와 전체 신호 조합·녹음 branch 통합·사용 앱 출고는 남아 있다.

## 개발 중 — 포트 가독성 C3c 단계

- 서클 선택만으로 모든 포트의 8방향이 반복되던 표시를 줄였다. 대표 지점과 실제 연결 위치를 유지하고, 클릭/P로 선택한 논리 포트와 가까운 호환 드래그 대상의 상세 방향을 펼친다.
- 포트 이름은 논리 포트마다 한 번씩, 겹치지 않는 위치에 배치한다. 실제 포트 점·서클 이름·편집기·도구막대·시간 손잡이를 피하고, 드래그 중 도구막대를 숨겨 대상 가림을 줄였다.
- 보이는 시간 손잡이에만 hit를 제공하고 충돌하는 포트 표시를 제외한다. 실제 시간 드래그는 시작 시간만 바꾸며 케이블을 유지했다. 대각선 IN에서 OUT으로 시작한 연결과 가려진 대상 연결, 한 번의 Undo를 확인했다.
- 전체 Swift 194개와 release build 통과. 전후 화면·저장 그래프·표시 수·라벨 충돌 근거는 [C3c QA](qa/ports-density-review.md)에 기록했다. 전체 신호/그룹 밀집 조합·VoiceOver·MCP 확장·녹음 통합과 사용 앱 출고는 후속이다.

## 개발 중 — 연결 키보드·접근성 C3b 단계

- K/Shift K 케이블 순환, P/Shift P 논리 포트 순환, Tab 끝점 선택, 좌우 8방향 위치 이동과 선택 연결/포트의 Return 편집을 추가했다. 명령 검색과 단축키 도움말에도 노출한다.
- 연결 편집기의 Tab 순서를 macOS 전역 설정과 독립적으로 제공한다. 닫힌 팝업의 방향키 선택과 Return 적용으로 키보드만 사용하는 재연결을 검증했다. 포트 선택 중 Delete는 서클을 제거하지 않는다.
- 확대 중 편집기 재생성으로 검색 포커스가 빠지던 문제를 수정했다. 컨트롤 준비와 카메라 이동 완료를 확인해 초기 포커스를 전달한다.
- 논리 포트와 케이블에 이름·선택 상태를 가진 접근성 항목을 제공한다. 중복 octant와 가려진 항목을 제한하고, 사라진 포트 선택과 파일 재열기 시 편집 의도를 제거한다. 마우스로 잡은 끝점도 키보드 선택에 반영한다.
- Native 재연결·Delete의 한 Undo, OUT/IN 16회 방향 이동의 음악 불변, 검색 입력 보호, 저장/재열기와 높이를 줄인 창을 검사했다. [C3b QA](qa/ports-keyboard-review.md). 실제 VoiceOver 발화·밀집 화면 전체 조합·C3/D/E 통합과 사용 앱 출고는 남아 있다.

## 개발 중 — 출력별 시각화 C3a 단계

- 케이블에 출발 OUT의 실제 envelope와 해당 edge gain을 사용한다. 트랙 출력에서 포트와 router matrix별로 경로를 따라가므로 다른 bus·음소거·gain 0 분기의 신호를 섞지 않는다. 독립 역상 출력은 node meter에서 peak 최댓값으로 표시한다.
- 접힌 그룹에서도 logical connection ID로 신호를 조회하고, 반복 occurrence의 로컬 시간과 section gain을 한 번 적용한다. 60 Hz envelope의 메모리도 오디오 준비 한도에 포함한다. 음악 schema와 실제 PCM 처리는 유지한다.
- 전체 Swift 190개와 warning 없는 release build를 통과했다. 전용 QA 앱에서 10회 상태 확인과 30.755초 MP4를 통해 두 출력의 모션 분리를 확인했다. 가려진 일반 창에서는 기존 절전 정책이 유지되며 영상 녹화 중에는 계속 움직인다. [C3a QA와 실행 근거](qa/ports-playback-review.md).
- 키보드·VoiceOver·밀집 화면 검증은 다음 C3b 범위다. main·사용 앱 교체와 녹음 branch 통합은 아직 수행하지 않았다.

## 개발 중 — 케이블 드래그 C2 단계

- 케이블 선택과 같은 캔버스의 재연결/위치 이동/해제 도구를 추가했다. OUT 또는 IN 끝점을 끌어 편집하며 Delete는 선택 케이블 하나만 해제한다. 드래그 중 기존 연결을 보존하고 성공 시 한 번의 Undo로 적용한다.
- 음악·배치·프로젝트 변경을 확인하는 gesture snapshot과 문서 재열기 시 늦은 메뉴 선택을 차단하는 조작 식별자를 추가했다. 위치 이동은 음악 revision과 그래프를 유지한다.
- 서클 중앙 드롭이 작은 좌표 차이로 방향을 바꾸던 문제, 도구막대가 끝점을 가리던 문제, 확대 시 주변 연결이 사라지던 문제를 수정했다. 포트 bus 번호를 중간 확대에도 표시하고 선택 라벨 중복을 제거했다.
- Swift 182개, Python 22개와 release build 통과. Native OUT/IN 각각 8방향 drag·저장값 일치, 재연결·IN 시작 분기·잘못된 드롭·메뉴 Esc·Delete·Undo·재열기를 검증했다. [C2 QA와 남은 범위](qa/ports-cable-review.md). 전체 C3/D/E와 녹음 branch 통합은 후속이며 사용 앱은 0.19다.

## 개발 중 — 직접 연결 편집 C1 단계

- 같은 캔버스의 연결 버튼·L에서 포트/대상 검색, 연결·재연결·해제와 양 끝의 8방향 배치를 편집한다. 재연결은 원래 edge ID·gain·전환을 보존하며 실패 시 기존 연결을 유지한다.
- App Undo가 포트 배치와 음악 편집을 구분한다. 배치만 이동·Undo·Redo하면 음악 revision과 그래프를 유지하며 저장/재열기로 위치를 복원한다. 최종 케이블과 재생 모션은 같은 방향별 곡선을 사용한다.
- 오디오 라우터 서클 생성과 2×2 전송량 편집을 노출했다. 숫자 입력이 되돌아가고 여러 Undo를 생성하던 문제를 수정해 Return/포커스 이동 시 한 번만 적용한다. 유효하지 않은 값은 반영하지 않는다.
- 연결 편집은 폭에 따라 한 열/두 열로 표시하고 시스템 팝업 대신 다크 메뉴를 사용한다. 선택한 트랙 경로의 대비와 라우터 탐색을 보완했다. 별도 포트 QA 앱 저장소와 기존 프로젝트를 건드리지 않는 증거 수집 도구를 추가했다.
- Swift 178개, Python 22개와 release build 통과. Native IN/OUT 시작 선택, 8방향 배치, 라우터 생성·연결, 숫자 valid/invalid·한 번의 Undo, 저장 복원을 확인했다. [C1 QA와 남은 범위](qa/ports-ui-review.md). 새 연결 드래그 코드는 빌드됐으나 native drag 검증과 끝점 드래그 재연결·위치 이동은 후속이다. main·사용 앱은 0.19를 유지한다.

## 개발 중 — 독립 오디오 bus B 단계

- 오디오 라우터의 스테레오 2 IN / 2 OUT과 2×2 gain routing을 구현했다. renderer의 PCM·소비자 수를 node와 port ID별로 관리해 분기·합류·sidechain을 분리한다. gain/automation/mute는 각 출력에 적용한다.
- 선택적 연결 port ID를 compiler·scene·catalog·저장·바운스 복원에 보존한다. 기존 생략된 단일 main/sidechain 연결은 유지하며 다중 bus의 모호한 연결·효과 삽입은 무변경으로 거절한다. 효과 삽입의 Core 경로를 앱과 기존 agent 명령이 공유한다.
- 신규 Core 5개/Audio 8개를 포함한 Swift 172개와 release build를 통과했다. 독립 stereo PCM, matrix, MIDI 합류, 13개 분기, 80개 라우터 chain, 두 트랙 바운스/embedded 저장/복원 검증을 포함한다. [다중 bus QA](qa/ports-bus-review.md).
- source feature branch 단계이며 main과 사용 앱은 0.19다. 라우터 생성·matrix 편집 UI, 8방향 native 연결, 명시적 port MCP·group binding은 후속이다.

## 개발 중 — 포트 기반 A 단계

- 기존 MIDI/audio/main/sidechain/송폼 포트에 stable ID·IN/OUT·수용 정책을 부여하고 입력 시작 요청을 OUT→IN으로 정규화한다. 실제 구현하지 않은 bus는 노출하지 않는다.
- 선택적 `portLayout`과 별도 revision·atomic 배치/복원 명령, 8방향 화면 geometry·hit·곡선을 추가했다. 재사용 use와 접힌 그룹의 logical endpoint를 보존하며 음악 revision과 PCM은 유지한다.
- 중복 배치가 scene 생성에서 충돌하는 문제를 수정했다. 13개 분기와 모든 방향의 PCM 불변을 포함해 Swift 159개 및 release build가 통과했다. [포트 기반 QA](qa/ports-foundation-review.md).
- 독립 feature branch의 Core 단계다. native 8방향 UI·다중 bus·MCP·그룹 binding·앱 통합은 후속이며 사용 앱은 교체하지 않았다.

## 0.20.0 — 검증 중 · 오디오 녹음 lifecycle

- 입력 장치 시작·종료와 파일 마무리를 전용 worker로 옮기고 시작 취소·timeout·중복 시작 차단·실패 복구를 구현했다. 수집 gate를 즉시 닫으며, 응답이 없는 OS 드라이버를 강제 종료했다고 표시하지 않는다.
- 같은 캔버스의 직접 녹음 버튼·⌥⌘R, 실제 입력 frame 기반 시간·peak·기본 첫 두 채널 표시를 연결했다. 녹음 실패 원본은 보존하고 Finder에서 찾을 수 있다.
- 실제 길이의 반복 테이크와 기존 오디오를 보존하며 원래 project/arrangement/use/track/lane에 한 편집으로 저장한다. MCP `circlr_record`는 revision과 선택을 확인하고 비동기 상태를 snapshot으로 제공한다.
- Swift 160개와 추가 CAF→테이크→저장/재열기→렌더/바운스 검사 1개, Python 23개가 통과했다. 실제 앱의 record 사전 조건 거부·재열기·직접 버튼·단축키 안내도 확인했다. 실제 입력과 녹음 중 UI 검증이 남아 **사용 앱은 0.19.0을 유지**한다. [0.20 검증 현황](qa/0.20-review.md).
- 선택된 오디오 이동 메뉴의 글자가 어두운 배경에 묻히는 문제를 수정하고 선택 접근성 상태를 추가했다. 작은 창에서 GUI MIDI/오디오 이동과 데이터·revision 보존을 확인했다.

## 0.19.0 — 2026-09-08 · 볼륨·팬 오토메이션

- 오디오·악기·이펙터·믹스·출력 서클에 gain/pan 곡선을 추가했다. 로컬 박, 템포 변경, 명시 반복과 연속 진행, 선형/유지 구간을 실제 PCM 렌더·바운스·export에 적용한다. 없는/비활성 곡선은 원래 소리를 보존한다.
- 같은 캔버스의 직접 버튼·⌘5, 궤도/선형 점 드래그·숫자 입력·방향키·점 추가/삭제·적용 전환을 제공한다. 작은 창에서 곡선과 명령을 나란히 배치하고, 개별 템포 처리 서클의 편집 좌표도 로컬 시간에 맞췄다.
- GUI/MCP는 같은 Core 명령을 사용한다. `set_automation`은 stable point ID·범위·중복·atomic batch·revision을 검사한다. output automation은 바운스 뒤 한 번만 적용하며 분할/복제의 곡선 시간도 보존한다.
- Swift 148개, Python 22개 통과. Native gain/pan은 기대 WAV 대비 24-bit 최대 1 LSB, hold는 0 LSB이며 pan bypass는 gain-only 음원과 정확히 같다. 텍스트 단축키 보호·한 번의 Undo·저장/재열기와 기존 v4 WAV 보존을 검사했다. [0.19 검증](qa/0.19-review.md).
- plugin parameter·MIDI CC·전역 bus 자동화, 실제 장치 녹음, 연속 실시간 엔진은 남은 범위다.

## 0.18.0 — 2026-09-08 · 오디오 분할·복제·페이드

- 오디오와 바운스 서클의 원본을 보존하는 split/duplicate/fade/delete를 Core·GUI·MCP에 연결했다. 분할 이전의 resample/stretch 기준·envelope·반복 주기·출력/sidechain을 보존한다.
- 파형 클릭 커서, ⌘T 분할·⌘D 복제와 직접 fade 필드를 같은 캔버스에 배치했다. 궤도와 자유 배치 파형 모두 지원한다. 텍스트 입력 시점의 단축키 충돌과 복제 조각 뒤의 불필요한 간격을 수정했다.
- 바운스 파생 서클을 family로 묶어 원본 복원 시 함께 archive한다. source 범위·fade·frame 변환을 검증하고 잘못된 batch·stale revision을 거부한다. 동일 fade 값은 Undo를 추가하지 않는다.
- Swift 138개, Python 21개 통과. Native 분할·복제 PCM 보존, fade 구간 감쇠·원본 hash 보존, 연속 키보드·Undo·저장/재열기를 확인했다. [0.18 검증](qa/0.18-review.md) · [조작과 데이터 의미](docs/32-audio-editing.md).
- 분할 조각 trim은 기존 처리 window 안에서 지원한다. 실제 장치 녹음·gain/pan automation·연속 실시간 엔진은 남은 개발 범위다.

## 0.17.0 — 2026-09-08 · MIDI 가져오기·일괄 편집

- ⌥⌘I로 MIDI format 0/1 노트를 읽고, 같은 캔버스에서 트랙을 선택해 새 MIDI 서클로 가져온다. 필요한 이번 섹션의 길이만 늘리며 기존 노트와 트랙을 보존한다. 파일 tempo/meter/CC는 적용하지 않음을 사전에 안내한다.
- ⇧클릭·⌘A 선택, Q 퀀타이즈의 분할/강도, 그룹 음정·시간 이동, ⌘D 복제·삭제를 추가했다. 궤도·피아노 롤·스텝이 같은 Core 편집 명령을 사용한다. 텍스트 입력 중 Cmd+A/D가 음악을 바꾸지 않는다.
- MCP `edit_notes`와 선택 노트·녹음 상태 snapshot을 추가하고 번들 음악 스킬의 실제 명령 계약을 갱신했다. 변동 없는 편집은 Undo를 추가하지 않는다.
- 마이크 권한 응답을 요청 당시 project/revision/서클/track/lane에 묶고 STOP·대상 변경·다음 요청 이후의 늦은 시작을 차단했다. 권한 대기 중 취소 버튼을 표시한다.
- 작은 창의 선택 명령·단일 노트 필드 배치를 확인하고 퀀타이즈 라벨을 1/16 등 실제 분할로 표시한다. 섹션에서 MIDI 가져오기 미리보기가 보이지 않던 문제를 수정했다.
- Swift 129개, Python 20개 통과. Native import→편집→Undo→저장/재열기, MIDI 신스 바운스 신호와 기존 v4 WAV 보존을 확인했다. 실제 마이크·Scarlett 장치 시작, audio split/fade·automation은 남은 범위다. [0.17 검증](qa/0.17-review.md).

## 0.16.0 — 2026-09-08 · 드럼·신스 스텝 에디터

- 같은 캔버스의 MIDI 편집에 스텝 모드와 ⌘4를 추가했다. 16칸 페이지, 드럼/음정 행, 1/4–1/32·셋잇단, 페이지 복제·비우기, velocity·길이 편집을 지원한다.
- 일반 Note/Lane을 그대로 사용하며 오프그리드·이전 칸의 유지음을 보존한다. 방향키·Return·Delete·Tab과 셀 접근성을 지원한다. 저장·재열기와 같은 트랙의 음색 전환 후에도 편집 모드를 유지한다.
- 기본 표시 음역을 기존 노트에 맞추고 MIDI 0–127까지 이동한다. 폭이 제한된 선택 라벨의 세로 줄바꿈을 수정했다.
- MCP `set_step`은 같은 Core 편집 경로를 사용한다. 중복 enable은 노트·Undo를 늘리지 않으며, 유효하지 않은 batch와 stale revision을 거부한다. 번들 전문 음악 스킬에 실제 명령 계약을 추가했다.
- Swift 119개, Python 19개 통과. Native 전체 WAV는 원곡 v4와 바이트 동일, 새 스텝은 실제 PCM에 반영됐다. 이펙트 포함 바운스 전후 최대 차이는 24-bit 2 LSB다. 상세 증거와 장치 검증 경계는 [0.16 QA](qa/0.16-review.md)에 있다.
- 오디오 편집·녹음 lifecycle·MIDI 일괄 편집·오토메이션의 실행 순서와 완료 조건을 [기본 DAW 확장 계획](docs/31-daw-basics-plan.md)에 기록했다. 기본 DAW 기능 전체 완료를 의미하지 않는다.

## 0.15.0 — 2026-09-08 · 트랙 바로 이동과 캔버스 가독성

- 상단 작업 이동(⌘J)으로 전체 곡의 섹션·트랙을 검색하고 연주·음색·이펙트·믹스·출력을 바로 연다. 같은 트랙의 편집 전환 버튼과 ⌘1/2/3을 추가했다.
- 반복 섹션의 use ID와 경로, 실제 출력 경로를 사용한다. 공유 이펙트의 트랙 문맥을 유지하며 sidechain을 트랙 소유로 오인하지 않는다. 접힌 그룹의 해당 경로만 펼친다.
- 서클 이름을 고정 크기로 표시하고 충돌을 피한다. 작은 서클의 이름도 선택·확대 대상이다. 현재 곡의 상위 제목이 중복되던 문제와 축소 창의 탐색 범위 판정을 수정했다.
- 편집기를 상단 조작·콘솔 밖에 배치하고, 신스 파라미터를 두 열로 정리했다. 입력 13pt/32pt 높이, 깊은 경로 메뉴, MCP의 읽기 전용 편집 영역·라벨 좌표 진단을 추가했다.
- 오프라인 Swift 113개와 Python 18개 통과. Native 확인 범위와 실행 제약은 [0.15 QA](qa/0.15-review.md)에 기록한다. 음악 DSP·MIDI·샘플 내용은 유지한다.

## 0.14.0 — 2026-09-08 · 클럽 그루브와 신스 엔진 3

- f0r h3r v4를 120 BPM·96마디·15트랙으로 재편곡했다. 정박 킥, 2/4박 backbeat, 엇박 hat, 16마디 DJ intro/outro를 적용하고 반복 tom fill·snare roll을 제거했다.
- 신스 엔진 3에 위상 일치 sine/pulse/saw, 비균일 unison, velocity partials, ensemble motion과 배음/움직임 컨트롤을 추가했다. EP·organ·brass·strings를 포함한 기본 10음색을 UI·콘솔·MCP에서 선택한다.
- 기존 engine 1/2는 유지한다. v3 곡을 최종 바이너리에서 재렌더한 WAV가 기존 파일과 바이트 단위로 일치했다.
- 전체 준비 메모리를 RAM의 1/4, 최대 2GiB로 제한하며 15트랙 전체곡을 지원한다. 제작 CLI에 기본 음색 비교와 섹션 단위 post-effect/pre-master stem 저장을 추가했다.
- CC0 bank·라이선스 감사를 유지하고 v4 송폼/grid 감사를 추가했다. 기존 데모와 중간 후보는 보존한다. Splice 지출 0.
- Swift 오프라인 107개, Python 18개 통과. 실제 0.14 QA 앱의 WAV/바운스와 UI parameter/preset/Undo를 확인했다. 직접 청취·Scarlett 실시간 출력의 검증 범위는 [QA](qa/0.14-review.md)에 명시한다.

## 2026-09-08 · 배포용 데모 v3와 Splice 조사

- Splice 완성 음원 사용과 샘플 포함 튜토리얼 배포를 구분해 공식 약관·FAQ 근거를 기록했다.
- f0r h3r v3의 외부 미디어 6개를 FreePats CC0로 교체하고 v2의 3,119 MIDI 노트와 68마디 구성을 유지했다. v1/v2는 보존한다.
- 제작 CLI의 기본 샘플을 CC0로 바꿨다. 고정 archive·manifest·파일 hash, 출처/라이선스 동봉, 전체 프로젝트 미디어 감사와 재현 도구를 추가했다.
- 설치된 Splice Sounds AU의 실제 로그인 화면을 써클러에서 확인했다. 로그인 이후의 검색·구매·동기와 파일 drop, 고정 편집 영역 잘림은 후속 연동 과제로 문서화했다. 앱 바이너리는 0.13.0을 유지한다.

## 0.13.0 — 2026-09-08 · 생성·키보드·영상·사운드

- 빈 공간 우클릭 생성, 계층별 A 메뉴, ⇧⌘P 명령 검색, ⌘/ 도움말, 키보드 계층 탐색·노트/오디오 편집·연결/사이드체인을 추가했다.
- 단일 캔버스를 유지하며 글로벌 설정, 자유 배치 grid 이동, 컨트롤 접근성 값을 보완했다. 필터된 검색 행이 이전 제목을 재사용하는 표시 문제를 수정했다.
- 캔버스 H.264 + 동일 PCM의 AAC MP4 저장, 취소·중간 정지·staging·종료 시 마무리 경로를 추가했다. 실제 재생 녹화 검증은 QA의 장치 상태를 따른다.
- 내장 신스 엔진 2와 확산 reverb를 추가하고 기존 patch의 렌더 버전을 보존한다. 새 악기는 내장 keys를 기본으로 한다.
- 노트 미리 듣기의 늦은 note-off가 취소 후 장치를 다시 여는 문제를 수정했다. offline AU 설정 순서를 조정하고 실시간 출력 연결에 10초 제한을 추가했다.
- 섹션 그래프에서 마지막 소비자가 끝난 오디오 buffer를 해제하고 실제 동시 buffer 수로 작업 한도를 계산한다.
- f0r h3r v2, 68마디·9트랙·2분 22.7초를 별도 제작했다. 보유 Splice 6샘플, 추가 0크레딧. 청취·발매 판단을 수치 검사와 구분한다.
- 비공개 zeztto/circlr에 초기 소스를 보관하고, 상세 로드맵과 기능 사용법을 작성했다. 에이전트 키트·아이콘을 앱에 패키징했다.
- 검증: 오프라인 Swift 102개, Python 17개 통과. Scarlett 실시간 출력 재검증과 실제 영상 검사는 [QA](qa/0.13-review.md)에 별도 기록한다.

## 0.12.0 소스 — 2026-09-08 · 음악 에이전트 키트

- circlr-studio 스킬과 음악 전문 역할 8종을 작성하고 프로젝트 Codex에 설치했다.
- 역할별 상세 지침, 단일 writer·revision 계약, 모델 상속 및 실제 capability에 따른 순차/병렬 작업을 정의했다.
- MCP 읽기 전용 모드, 충돌 보호·원복 installer, 앱 번들 manifest 검증을 추가했다.
- Python 17개 테스트, 실제 Codex 스킬·역할 검색과 QA 앱 snapshot을 확인했다. 앱 패키징은 이어지는 기능 개선과 함께 수행한다. 상세: docs/24-music-agent-kit.md.

## 미출시 계획 — 2026-09-07 · 8방향 포트

- 서클 둘레 8방향 연결, IN/OUT 표시와 다중 입출력을 제품 요구로 기록했다. 방향 수와 포트·케이블 수를 분리한다.
- port ID·edge별 endpoint 배치, fan-in/fan-out과 독립 bus, sidechain, 시간 손잡이 충돌 방지, 기존 프로젝트 migration과 MCP 계약을 설계했다.
- 문서만 갱신했다. 앱 0.10.0의 좌우 포트 UI와 실행 파일은 변경하지 않았다. 상세: docs/22-eight-direction-ports.md.

## 미출시 계획 — 2026-09-07 · 아티스트 창작 세계

- 최종 제품 방향을 아티스트 프로필 중심의 작품·세계관·생성물 관리로 확장했다. 캐릭터 선택 같은 진입과 단일 캔버스 탐색을 정의했다.
- 작품·파일·버전·출처·발매 묶음, 시간 궤도와 관계 궤도, 기존 음악 문서와 상위 catalog의 경계를 제안했다.
- Codex 콘솔 계획에 아티스트별 문맥·실행권한·프로필 전환 조건을 연결했다. 문서만 갱신했으며 앱 0.10.0과 사용자 자료는 변경하지 않았다. 상세: docs/21-artist-universe.md.

## 미출시 계획 — 2026-09-07 · Codex 계정 콘솔

- OpenAI 공식 문서와 로컬 Codex 0.149.1 schema를 대조해 사용자의 ChatGPT/Codex 계정으로 대화하는 앱 내 콘솔의 구현 계획을 작성했다.
- App Server stdio·기존 MCP·공통 편집/Undo 연결, 공식 로그인, 세션별 권한, AI 중단과 음악 정지 분리, 대화 복원, 런타임 배포 및 인수 검증을 정의했다.
- 문서 변경만 수행했다. 앱 버전·실행 파일·로그인 설정·사용자 음악은 변경하지 않았다. 상세: docs/20-codex-account-console-plan.md.

## 0.11.0 — 2026-09-07 · 재생 비주얼라이저와 팔로우

- 실제 재생 sample time, 렌더된 노드별 PCM envelope와 MIDI 노트의 세기로 서클 외곽·궤도 잔상·연결선 신호를 그린다. 시각화 분석은 선택 사항이며 바운스·export PCM을 변경하지 않는다.
- 재생 팔로우를 기본으로 켜고 현재 섹션·마디를 표시한다. 섹션 경계에서 카메라가 이동하며 콘솔과 창 크기 변화에도 작업 영역을 다시 맞춘다.
- 휠·드래그·선택·편집 시 팔로우를 일시 중지하고 버튼으로 재개한다. 음악 상태·Undo·편집 선택을 자동 카메라가 변경하지 않는다.
- 최소화·가려진 창에서는 화면 프레임 작업을 멈추고 복원하면 재개한다. 정지 또는 음악 revision 불일치 시 이전 그래프의 신호를 지운다. 동작 줄이기 설정에서는 입자·파동·카메라 tween을 생략한다.
- MCP focus에 follow 설정과 snapshot에 읽기 전용 playback 진단을 추가했다. 도구는 기존 14개를 유지한다.
- Swift 92개·Python 4개 테스트와 실제 QA 앱의 재생·팔로우·최소화·stale 상태를 검증했다. 기존 아이콘을 포함한 0.11.0 로컬 앱을 패키징한다. 상세: qa/0.11-review.md.

## 0.10.1 — 2026-09-07 · 앱 아이콘

- 차콜 바탕, 민트색 이중 궤도와 위성 서클의 앱 아이콘을 제작하고 앱 번들에 적용했다. 생성 원본과 프롬프트·출처·재생성 방법을 Resources/Brand에 보관한다.
- macOS 26에서 추가되던 넓은 밝은 테두리를 Icon Composer의 명명된 Assets.car 리소스로 해결했다. 이전 macOS를 위한 16–1024px ICNS도 포함한다.
- 아이콘 생성·누락 검사·번들 복사 검증을 패키징에 연결했다. 이전 C 모듈 캐시가 release 빌드를 방해하지 않도록 앱 빌드와 캐시 경로를 분리했다.
- macOS 26.5.1에서 실제 아이콘 해석, 크기별 표시, release 빌드와 로컬 서명을 검증했다. 음악 엔진·프로젝트 포맷은 변경하지 않았다. 상세: qa/0.10.1-icon-review.md.

## 0.10.0 — 2026-09-07 · 궤도 타임라인

- 앨범·곡·악장·섹션의 실제 실행 시간을 12시부터 시계 방향으로 표현한다. 템포/변박, 반복, insert/overlap 전환과 경로 밖의 섹션을 구분한다. 빈 곡을 추가해도 기존 앨범 시간이 유지된다.
- 시간 소스는 동심 궤도에 배치하고 악기·이펙터·믹스·출력은 실제 신호 연결을 유지한다. 공간 그룹이 음악상의 owner나 상위 궤도 위치를 바꾸지 않도록 처리했다.
- 소스 시작 및 섹션·곡·악장 순서 손잡이, 원호형 MIDI 추가·이동·길이 편집, 원형 오디오 trim을 같은 캔버스에 연결했다. 한 gesture는 한 Undo이며 재생 revision과 다른 playhead는 표시하지 않는다.
- 원형 파형의 표시 배율을 조절해 조용한 오디오도 편집할 수 있다. gain은 바꾸지 않는다. 상세 편집 공간을 확대했고 작은 서클의 보이지 않는 포트가 선택을 가로채던 문제를 수정했다.
- orbit/freeform 선택을 저장하며 기존 배치 좌표를 보존한다. 자유 배치의 정렬·그룹 회귀도 유지한다.
- MCP inspect에 실제 궤도 데이터, apply에 set_clip/reorder_section, focus에 compositionID를 추가했다. 파일 범위 밖 trim과 손실되는 전환은 거부한다.
- Swift 80개, Python 3개 테스트와 실제 최소화 MCP 작업, native MIDI·오디오 손잡이 및 Undo를 검증했다. 전체 곡 바운스의 차이는 24-bit PCM 최대 1단계다. 세부 증거는 qa/0.10-review.md에 기록한다.

## 0.9.0 — 2026-09-07 · 에이전트 연결과 음악 제작

- stdio MCP adapter와 현재 사용자 전용 Unix socket을 추가했다. 14개 도구로 실제 프로젝트 상태·음악 context·노트·그래프를 읽고 편집하며 앱을 최소화한 상태에서도 작업한다.
- project ID와 expected revision, 원자적 batch, 한 번의 Undo, 동일 요청 재전송 캐시, 렌더 job·취소·실제 이벤트를 연결했다. 작업 중 문서가 바뀌면 오래된 렌더 결과를 적용하지 않는다.
- 프로젝트 열기는 비동기 job이다. macOS 파일 접근 응답이 지연돼도 상태 조회·정지가 메인 스레드에서 응답하며 취소한 열기가 뒤늦게 문서를 바꾸지 않는다.
- 단일 canvas 위에 접이식 게임 채팅 형태의 콘솔을 추가했다. 실제 작업 진행과 입력 명령을 표시하고 편집 영역의 높이를 조절해 컨트롤을 가리지 않는다. 콘솔을 펼치면 최신 로그를 표시한다.
- native synth pad/bass/keys/supersaw/pluck/lead, ADSR·filter·detune, sample 악기·drum zone mapping, scale/meter를 따르는 MIDI 패턴 생성 및 표준 MIDI 파일 저장을 추가했다.
- 실제 내부 이펙트와 sidechain을 포함해 섹션 트랙을 오디오로 바운스한다. 출력 gain은 한 번 적용하고 원본 입력·잔향·복원 정보를 보존한다. 출력에 연결되지 않은 보관 노드는 렌더하지 않는다.
- master-only 렌더에서 불필요한 stems 준비를 생략하고 메모리 추정과 진행률을 보정했다. 오디오는 기존 prepared PCM 구조를 유지한다.
- f0r h3r의 편집 프로젝트·8트랙 MIDI·101.31초 WAV·튜토리얼을 제작했다. Splice 보유 샘플 6개를 동기화했으며 추가 지출은 승인된 최대 10 credits 중 0 credits다. 원본 샘플은 로컬 산출물에만 포함한다.
- Swift 70개·Python 3개 테스트 및 native MCP 검증을 통과했다. 최소화 중 MIDI 편집·Undo·중복/충돌/취소·바운스·저장을 확인했으며 전체 곡의 바운스 전후 차이는 24-bit PCM 최대 1단계다.
- 궤도의 각도/시간 배치와 원호형 노트 편집, text/image/video 세계관 참조는 다음 구현 범위로 남겨 문서화했다.

## 0.8.0 — 2026-09-07 · 앨범 계층 캔버스

- Album/Composition 소유권·순서·반복과 부모/글로벌/개별 음악 설정을 추가하고 version 1 곡을 원본과 변형을 유지하며 version 2로 확장한다.
- 섹션 안에 MIDI·오디오·악기·믹스·이펙터·출력과 실제 typed 연결을 저장한다. 기존 per-track 비선형 효과 결과와 변형을 보존한다.
- 앨범→곡/악장→섹션→음악 서클을 하나의 AppKit 캔버스에 표시하고, 휠·핀치·더블클릭·상위 경로로 확대/복귀한다. 큰 부모 원은 캔버스 경계에서 잘라 상단 메뉴를 가리지 않도록 했다.
- 충분히 확대하면 같은 캔버스에서 MIDI 입력·이동·길이·세기, 실제 오디오 파형 구간 드래그와 clip 설정, DSP·Audio Unit 파라미터를 편집한다. 별도 editor window bridge를 메인 화면에서 제거했다.
- 오디오 import/delete와 새 MIDI lane이 실제 graph source 및 연결을 갱신한다. 기존 삭제한 노드·연결을 일반 노트 편집으로 다시 만들지 않는다.
- 오디오 서클의 개별 clock·명시적 길이·반복 경계와 원본 구간을 renderer에 연결했다. 전체 앨범 playback/export가 공통 절대 시간 계획을 사용한다.
- 원형 그룹·다중 정렬·함께 이동·접기/펼치기를 실제 Layout에 저장한다. 노드 우클릭과 섹션 설정에서 연결·재생할 경로·전환을 편집한다.
- 전역 Project.signal을 앨범 사운드 서클로 표시한다. 트랙 출력·버스·마스터·전역 이펙터를 같은 캔버스에서 연결하고 편집한다.
- 카메라·선택·설정 모드를 문서에 저장한다. 녹음 Take는 정확한 Lane/편곡안 ID를 유지하며, Audio Unit의 지연 응답과 적용은 요청한 서클과 대조한다.
- 반복 횟수만큼 동심원을 그리고 외곽 링에 포트와 hit 영역을 맞춘다. 반복된 서클도 정밀 편집 배율을 확보한다.
- 재사용 간격을 실제 서클 크기에 맞추고, Undo로 선택 대상이 없어지면 상위 서클로 돌아간다. 깊게 확대할 때 관계없는 겹친 가지가 현재 서클을 가리지 않도록 했다.
- 최종 전체 테스트 61개 통과. 실제 native MIDI/오디오/effect/group/transition 편집·저장·복원·재생·WAV를 검증했다. 전역 Gain 0.8 출력은 이전 PCM의 80%와 1 단계 이내로 일치한다.
- 로컬 app bundle을 갱신하고 이전 0.7.1을 archive에 보관한다. 검증은 별도 bundle ID와 복구 경로를 사용했다.

## 미출시 설계 변경 — 2026-09-07

- 섹션을 오디오·MIDI·이펙터 서클과 내부 연결을 담는 원형 그룹으로 정의했다.
- 단일 캔버스의 중첩 탐색, 필요할 때 여는 사각 정밀 편집 창, 포함·진행·신호 관계와 부모/자식 음악 설정을 구체화했다.
- 섹션별 그래프·typed port·compiler·저장 migration의 책임과 검증 시나리오를 문서화했다. 기존 effect 적용 범위를 보존하는 전환 조건을 명시했다.
- 문서 변경이며 앱 코드·0.7.1 실행 파일·사용자 곡은 변경하지 않았다.

## 0.7.1 — 2026-09-07

- 메인 창의 빨간 닫기 버튼과 ⌘W를 앱 종료 대신 Dock 최소화로 변경했다.
- Dock에서 앱을 다시 열면 기존 메인 창과 편집 상태를 복원한다.
- 마지막 창이 닫혔을 때의 자동 종료를 끄고, ⌘Q의 저장 확인과 실제 종료는 유지했다.
- SwiftUI 기존 window delegate 동작과 별도 음악 편집 창의 닫기/Esc를 유지했다.

## 0.7.0 — 2026-09-07

- 서클 편집 탭과 화면 전환 상태를 제거했다. 이름·길이·재생·시작/끝·음악 설정·트랙·MIDI·오디오·이펙트를 하나의 뷰에 배치했다.
- MIDI와 오디오를 공통 가로 시간축에 표시한다. 격자 왼쪽 건반, 트랙 선택·볼륨·음소거, 녹음·가져오기, 오디오 시작 위치 드래그와 클립 속성을 직접 노출한다.
- 총 재생 횟수와 동심원 수를 일치시켰다. 1…256회 모두 해당 수의 링을 만들고, 포트·클릭 영역·그룹·전체 맞추기가 외곽 반지름을 따른다. 촘촘한 링은 대비를 낮추고 숫자를 병기한다.
- 캔버스 선택 도구막대에 즉시 재생 횟수 조절과 통합 편집 버튼을 배치했다. 기본 편집 창을 넓히고 작은 창에서는 같은 뷰를 스크롤한다.
- 음악 설정은 현재 값을 바로 편집하며 실제 변경 시 개별 설정으로 전환한다. 같은 값으로 입력칸을 통과할 때 상속을 유지하도록 수정했다.
- 악기/트랙 변경 시 이전 Audio Unit 편집기를 정리하고 지연된 편집기 응답 및 적용 대상의 일치 여부를 확인한다.
- 자동 검증 22개와 실제 native UI 편집·반복·저장/재열기 검증을 기록했다. 오디오 DSP 변경과 실제 출력 장치의 재검증은 포함하지 않는다.

## 0.6.0 — 2026-09-07

- 기본 외관을 다크 모드로 바꾸고 중성 배경·민트 선택색·마디 링·도구막대·입력 컨트롤을 통일했다.
- modifier 없는 휠 위/아래를 커서 기준 확대/축소로 지정했다. 숫자 배율, 조작 안내, 선택(V)·이동(H)·전체 보기(F)를 노출한다.
- 원 내부 확대 편집을 제거했다. 서클을 더블클릭하거나 MIDI/오디오 버튼을 누르면 이동·크기 변경 가능한 사각 편집 창이 열린다.
- 편집 창 하나를 재사용하며, 캔버스 선택 변경 시 제목과 내용을 함께 전환한다. 명시적으로 열 때만 창을 앞으로 가져와 캔버스 드래그를 방해하지 않는다.
- MIDI 격자를 넓히고 오디오 가져오기·클립 속성·녹음·구성·음악 설정을 창 상단에서 전환하도록 정리했다.
- 마우스 휠 방향·자연스러운 스크롤 정규화·배율 한계·커서 고정 회귀를 추가했다. 19개 자동 검증 통과. 실제 UI 범위는 qa/0.6-review.md에 기록한다.

## 0.5.0 — 2026-09-07

- 좌측 library, 우측 inspector, 하단 editor를 제거하고 하나의 큰 캔버스로 재구성했다.
- 서클을 두 번 클릭하면 원이 펼쳐지며 내부에서 연주·구성·음악 설정·이펙트를 편집한다. Esc는 이전 화면 위치로 복귀한다.
- 트랙·리듬·편곡안은 메뉴로 접근하며 글로벌·전환·Audio Unit 편집도 동일 캔버스에 표시한다.
- 생성 시 이름 대화상자를 제거하고 원 안에서 이름을 편집하도록 바꿨다.
- 드래그 중 스냅을 제거하고 drop 시 한 번만 적용하며, 그룹의 상대 간격과 한 번의 undo를 유지한다.
- pan/zoom preview를 view 내부에서 처리하고 커서 기준 확대와 실제 전체 보기 계산을 추가했다.
- 정지 중 전역 상태를 매 tick 갱신하지 않도록 transport를 분리하고 음악 context/plan을 revision별로 캐시한다.
- 출력 장치 획득을 실제 재생까지 늦추고 장치 연결과 미리듣기가 UI를 막지 않도록 분리했다. 정지 이후 지연된 미리듣기는 무효화한다.
- 17개 장치 비의존 검증과 native 편집·저장·그룹 이동을 확인했다. 시스템 오디오 장치 대기로 최종 소리 재검증은 미완료다.
- 기존 0.4 앱의 CPU 100%·UI 응답 불가 상태와 SwiftUI layout 반복 stack을 기록하고 자동 복구본을 보존했다.

## 0.4.0 — 2026-09-06

- 후속 프로토타입 제작 요청에 따라 Swift·AppKit/SwiftUI 기반 macOS 앱을 추가했다.
- 원형 canvas, 마디 링, 포트 연결, 자유 배치, grid/snap, 다중 선택, 정렬, 그룹과 편곡안 복제를 구현했다.
- 원본 재사용/사용별 변형/독립 분리, 명시적 반복, 필드별 음악 설정 상속과 별도의 BeatGrid/RhythmPattern을 연결했다.
- 실제 piano roll·화면 건반·CoreMIDI 입력, sound bank/Audio Unit 연주, 오디오 import와 take 보존을 추가했다.
- 준비된 PCM 재생, 기본 DSP·사운드 routing·전환·stereo/stem export와 native 프로젝트 저장을 구현했다.
- MIDI 다중 packet 순회, 녹음 tap의 bounded ring buffer, 반복 take 선택, 취소된 render 게시 방지, 정지 상태 링과 WAV 임시 확장자를 수정했다.
- Core/audio 자동 검증과 실제 native UI 검증, 재현 가능한 app bundle build 및 사용 문서를 추가했다.
- 실기 마이크·외부 장치·모든 제3자 plugin·PDC·전체 realtime engine의 검증 완료를 주장하지 않는다.

## 0.3 — 2026-09-06

- 자유 배치 원형 노드 캔버스와 그리드·정렬·그룹을 기본 화면 방향으로 확정했다.
- 원 테두리의 마디·박 표시를 구체화하고 한 바퀴 = 섹션 한 회를 제안했다.
- 글로벌/서클별 tempo·scale·meter·BeatGrid·RhythmPattern 설정과 항목별 상속을 설계했다.
- 글로벌 비트가 리듬 기준과 실제 드럼·리듬 패턴을 모두 뜻한다는 사용자 답변을 반영했다.
- 동일 canvas의 유형별 연결, 시각 그룹의 독립성, 이종 tempo/meter overlap과 plugin context 경계를 보완했다.
- music/layout revision을 구분하고 새 context·ring·pattern 검증 시나리오를 추가했다.
- 캔버스·음악 설정 상세 문서와 ComfyUI 공식 참조를 추가했다. 제품 구현은 포함하지 않았다.

## 0.2 — 2026-09-06

- 제품명을 써클러(circlr)로 확정하고 가칭 표현과 영문 대문자 표기를 정리했다.
- 첫 대상 플랫폼을 macOS 데스크톱 앱으로 확정했다.
- UX·architecture·결정 기록에 macOS 기준을 반영하고 플랫폼 미정 질문을 지원 환경 확인으로 좁혔다.
- 구현 언어·framework·최소 macOS·CPU 지원 범위·plugin 포맷은 후속 결정으로 유지했다.

## 0.1 — 2026-09-06

- 송라이터·편곡자를 위한 원형 섹션 기반 DAW의 제품 개념을 정리했다.
- 오디오·MIDI 병행, 섹션 음색 처리와 전환 효과 요구를 반영했다.
- 섹션 원본·사용 위치·재생 회차와 SongGraph·SignalGraph를 구분했다.
- 이동·반복·변형·전환 UX, 재생 시간, 녹음·저장·export 규칙을 제안했다.
- 기본 architecture, 기술 후보, 미결 사항, 검증 시나리오와 공식 출처를 문서화했다.
- 제품 구현은 포함하지 않았다.
