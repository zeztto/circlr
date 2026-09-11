# 같은 캔버스의 로컬 샘플 라이브러리

2026-09-09. 기준 `d318e44`, build 31. 현재 목표는 로컬 샘플을 찾기 위해 반복해서 파일 선택 창을 여는 단계를 줄이는 것이다. 전체 개발·E 출고 gate를 유지한다.

## 계획 gate와 소유

development-lead → UI/UX → Core/audio Swift utility → App Swift utility → 읽기 전용 입력·보안 검토 → QA. root를 포함한 실제 agent 한도가 1이며 직전 생성 요청이 거절되어 순차 역할 전환한다. 독립 빌드와 테스트는 병렬 실행한다. 작업 경로는 `.build/integration-worktree`, 사용자 설치 앱과 원본 샘플은 보존한다.

## 사용 흐름

상단 샘플 버튼, ⌥⌘L, 명령 검색에서 같은 캔버스 위의 검색 화면을 연다. 여러 로컬 폴더를 등록하고 파일명·하위 폴더·형식으로 검색한다. 폴더 목록 제거는 파일을 삭제하지 않는다. 폴더 추가·새로고침·다시 열기 때 비동기로 색인을 갱신한다. 검색 중 타이핑과 방향키로 선택하고 Return으로 가져온다. 오디오는 명시적 미리 듣기 버튼을 지원하며 선택/닫기/STOP/곡 재생·녹음/가져오기 때 멈춘다. MIDI는 기존 트랙 선택 미리보기로 이어진다.

등록 폴더와 검색 결과는 프로젝트 음악 데이터와 분리한다. 가져오기만 기존 atomic staging/Undo/저장 경로를 사용한다. 화면을 열 때 대상 프로젝트/revision/세션/섹션을 고정하고 외부 변경이 있으면 적용 전에 대상을 갱신하도록 표시한다. 섹션 선택 메뉴로 목적지를 직접 지정할 수 있다.

## 데이터·취소·보안 계약

- 사용자가 선택한 폴더만 읽는다. security-scoped read-only bookmark를 앱별 로컬 설정에 저장하고 프로젝트/MCP 기록/Git에 넣지 않는다. 권한/이동 오류는 폴더명과 함께 표시한다. 등록 제거·앱 종료·늦은 비동기 완료를 generation으로 보호한다.
- 숨김·package·symlink 디렉터리/파일을 제외한다. 색인과 재사용 시 정규화된 경로가 등록 root 안인지 검사한다. 파일 수/탐색 수와 가져오기 크기를 제한하며 제한 도달과 오류를 표시한다. 파일 크기/수정 시간 변경은 새로고침을 요구한다.
- 파일 확장자는 검색 분류이며 유효한 오디오/MIDI임을 보장하지 않는다. 미리 듣기/가져오기 시 실제 decoder/parser로 검증한다. BPM/스케일을 파일명에서 확정 metadata처럼 추정하지 않는다.
- preview는 별도 로컬 AVAudioPlayer로 원속도 재생한다. transport 동기/time-stretch/AU preview/클라우드 구매 기능으로 표현하지 않는다. 비동기 준비는 취소 뒤 재생하지 않는다.
- Splice 사설 DB·쿠키·구매·모델 업로드를 사용하지 않는다. 다운로드 파일의 권리와 데모 재배포 조건은 기존 [라이선스 검토](27-splice-licensing-and-integration.md)를 따른다.

## 구현과 검증

새 `CirclrAudio/MediaLibrary.swift`, App의 `MediaLibraryController.swift`·`MediaLibraryView.swift`와 AppStore/RootView/명령·키보드 gate를 수정한다. Audio 단위 테스트는 재귀 검색·검색 정렬·종류·중복·범위·심볼릭 링크·파일 변경·취소·잘못된 파일을 검사한다. 프로젝트 schema를 변경하지 않는다.

Swift 전체·Python MCP/키트·release 후 authored QA 폴더에서 등록→검색→preview/정지→오디오 가져오기→Undo/Redo→저장/재열기, MIDI 미리보기, 대상 충돌과 최소 창 UI를 검증한다. bookmark 재실행 지속성과 등록 제거의 원본 보존도 확인한다. 실제 Splice/Finder 드롭 제스처·file promise·자동 변경 감시·checksum 중복/GC·클라우드 카탈로그는 후속 범위다.

공식 근거: [읽기 전용 security-scoped bookmark](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:))와 [AVAudioPlayer 재생](https://developer.apple.com/documentation/avfaudio/avaudioplayer/play()).


## 구현 후 보완

검색 화면은 850×560의 일시적 캔버스 overlay이며 배경은 접근성 탐색에서 제외한다. 작은 창에서 상단 작업 이동은 아이콘과 접근성 이름을 사용하고 템포를 한 줄로 유지한다. 선택 정보의 시스템 decoder 오류를 한국어로 바꿨다. 검색창의 ⌥Space는 local key monitor가 처리하며 IME 조합 중에는 가로채지 않는다.

실제 QA에서 AVAudioPlayer.play가 HAL 응답을 기다리며 MainActor를 붙잡았다. `CirclrAudio/MediaPreview.swift`로 player 생성·준비·muted 시작·음량 활성화·재생 시계·정지를 전부 한 백그라운드 작업에 소유시켰다. 취소 후 늦은 시작은 muted 상태에서 정리한다. 이전 작업이 종료되기 전 재시작을 중복 실행하지 않는다. 미리 듣기는 128 MiB 이하 파일·원속도·고정 preview volume을 사용하며 오디오 가져오기는 기존 2 GiB/1시간 제한을 유지한다. 장치의 실제 지연 원인 자체는 미해결이다.

MCP `snapshot.library`는 open/folders/files/scanning/searching/previewPreparing/previewPlaying/previewPending/previewSeconds를 제공한다. 폴더 경로·bookmark·쿼리 원문은 포함하지 않는다. pending은 취소된 device 호출이 아직 정리 중인 경우에도 true이며, UI 취소와 물리 작업 종료를 구분한다. [검증 기록](../qa/library-review.md).
