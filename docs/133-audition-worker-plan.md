# 악기 미리 듣기 worker 격리 계획

상태: 후속 설계만 작성했으며 미구현이다. build116 공유 리듬 오디오 편집의 완료 범위와 분리한다. 실제 음·latency·voice·HAL 복구를 검증한 결과가 아니다.

## 프로세스와 연주 수명

악기 target마다 지속되는 `circlr-audition-worker` 하나를 두고 앱은 process proxy로 접근한다. note마다 offline worker를 실행하지 않는다. 지속 voice·note-off·oneShot 의미를 보존해야 한다. NativeAuditionBackend를 helper 전용 파일로 이동하고 LiveSynth/LiveSampler/AUHost를 재사용한다. 앱의 기존 mock factory는 유지한다.

wire는 session UUID·sequence·capability·prepare/ready·token별 note-on/off와 ack·trace/failure·stop/stopped를 포함한다. stdin 독립 reader는 native 작업이 막혀도 취소와 held token 상태를 갱신하여 `isCurrent`에서 관측할 수 있게 한다. host가 ack를 기다릴 때에도 STOP/current=false가 release로 전달되어야 한다. 오래된 token의 note-off가 같은 pitch의 새 note를 끄지 못하게 한다.

## 입력과 종료 경계

queue·payload·pitch/velocity를 제한하고 state8 MiB·manifest12 MiB 상한을 둔다. 전체 프로젝트 대신 악기와 필요한 sampler 자산만 owner-private0700 요청 디렉토리로 전달한다. 준비·note 처리·STOP 유예의 deadline을 분리하며 지속 worker에 전체 job deadline을 두지 않는다.

stop→stdin EOF→필요 시 TERM/KILL→reap·reader drain·임시 파일 정리가 끝난 뒤 후속 backend를 시작한다. OutputWorker의 nonblocking50ms reader·session guard·2초 tail drain, AU worker의 독립 parent EOF 패턴을 참고한다. offline의 exit0/resultCAF 성공 계약은 지속 연주에 그대로 적용하지 않는다. build115의 frozen interruption trace를 유지한다.

## 구현 분할과 검증 계획

1. protocol/service/native backend.
2. host/transport와 mock 테스트.
3. Package·tool·packaging QA.

mock child hang/crash/EOF·stale session·token 재트리거/late off·자손 pipe 상속·launch 전 취소·cleanup을 검증한다. 이 단계에서 실제 HAL은 실행하지 않는다. 실제 음·latency·voice·HAL 복구는 별도 native gate이며 HAL 자체를 정상화했다고 주장하지 않는다. 출력 장치 선택 확장도 별도 범위다.
