# build118 악기 미리 듣기 프로세스 격리

상태: 소스·mock lifecycle·Release 패키징 검증 완료. 실제 HAL·가청 결과·연주 지연 검증은 별도이며 완료로 간주하지 않는다.

## 동작 계약

기본 AuditionTransport는 앱 옆의 `circlr-audition-worker`를 실행한다. 하나의 악기 target에 지속 backend를 유지하며 note마다 프로세스를 재시작하지 않는다. NativeAuditionBackend는 별도 파일에 있고 helper service에서 생성한다. 라이브 synth/sampler/AU 구현은 유지한다. helper 부재 시 명시적으로 실패하며 앱 내부 native 실행으로 fallback하지 않는다.

요청에는 전체 Project 대신 instrument와 참조 sampler 자산만 전달한다. directory0700·파일0600, owner/regular file/link 검사, manifest12MiB·AU state8MiB·자산/zone128개 제한을 적용했다. 외부 오디오 파일 자체를 요청 디렉토리에 복사하지 않는다.

JSON line IPC는 version·session UUID·단조 sequence·capabilities와 note token을 검증한다. line4096bytes·inbox256개를 제한한다. 독립 stdin reader는 native 작업 중에도 held token과 취소를 갱신하고 EOF에 종료한다. 예전 token의 release가 같은 pitch의 새 연주를 지우지 못한다.

준비 기본8초, note ack 기본2초, stop 유예 기본0.2초를 사용한다. STOP→stdin EOF→필요 시 TERM/KILL→소유 child reap→reader 종료→요청 디렉토리 정리를 수행한다. 전체 지속 세션에는 수명 제한을 두지 않는다. SIGKILL 이후 OS의 reap 완료 시간까지 절대적인 종료 상한을 보장한다는 의미는 아니다. 자손의 stdout 상속으로 reader가 끝없이 대기하지 않도록 중단 조건을 분리했다.

유휴 worker 실패와 등록 전 실패를 transport로 전달한다. 이미 queue에 있던 drain은 실패 메시지를 지우지 않는다. cancel/새 target은 intent generation을 갱신하며, 정리 후 실패 게시도 같은 lock에서 generation을 확인한다. prepare 실패 역시 요청 일치 검사와 게시를 원자적으로 수행한다. note/cleanup trace는 host가, 준비 trace는 helper가 담당한다.

## 검증

- 기존 mock factory와 diagnostic 계약 유지. 최종 `swift test --scratch-path .build/integration-default --filter 'AuditionWorkerTests|AuditionTransportTests|AuditionDiagnosticsTests'`: 32개, 실패0, 6.512초.
- Python fixture child로 persistent PID·token release·준비 hang·취소·note hang·ack 대기 중 release·stale session·oversized payload·capability 누락·idle crash·상속 stdout·소유 PID 정리를 확인했다. inbox 순서/용량·private manifest도 검사했다.
- 최초 timeout fixture는 Python 준비 시간과 note deadline을 혼용하여1건 실패했다. 준비 제한을 분리한 뒤 통과했다. `.build/build118-audition-tests.log`는 실패 이력이며 최종 성공 근거가 아니다.
- reviewer가 발견한 buffered failure→idle 문제를1개 테스트/2 assertion 실패로 재현했다 (`build118-buffered-red.log`). cleanup 중 cancel이 실패에 덮이는 callback/note throw 두 경로는1개 테스트/4 assertion 실패로 재현했다 (`build118-cancel-red.log`). 최종 성공 로그는 `.build/build118-audition-final2.log`다.
- read-only 보안/lifecycle reviewer v3: 추가 blocker0. 리뷰는 실제 오디오 실행 결과가 아니다.
- 최종 Release54.23초, main UUID `5D3E775E-07AC-3477-9C02-6A507EA92BF6`, helper UUID `304A18DA-B9CB-3DC0-8990-50BC8CDBCEB4`. 이전 Release 후보와 구분한다.
- worktree `dist/써클러.app` build118에 helper를 동봉했다. app deep/strict 서명 및 helper strict 서명, 빌드 원본과 패키지 UUID 일치를 확인했다. helper invalid arguments 실행은64로 종료하며 native backend를 생성하지 않는다.
- 패키지 SHA/UUID·원본 PID 관측: `qa/generated/audition-worker/build118-package.json` (로컬 QA 산출물, Git 제외). 사용자 원본 PID86114는 유지했고 앱을 교체하거나 물리 오디오를 재생하지 않았다.

## 남은 검증과 개발

내장 synth·sampler·AU를 실제 장치에서 연주하며 note-off/oneShot/재트리거·지연·voice 보존을 확인해야 한다. 실제 plugin의 stdout 출력과 helper 호환성, 장치 변경·HAL 정지/복구도 미검증이다. 이번 변경만으로 음질 향상이나 HAL 정상화를 주장하지 않는다. 프로세스 격리는 악기 미리 듣기 범위이며 다른 녹음·전체 transport 경로의 격리를 의미하지 않는다.

실제 연주 검증 이후 필요한 성능 개선을 결정한다. 별도 UI 작업에서는 기존 단일 캔버스를 유지하면서 작은 편집기에서 가려지는 조작과 깊은 메뉴를 계속 줄인다.
