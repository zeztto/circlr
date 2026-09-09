# 출력 worker wire 계약 검증

2026-09-10, 기준 cca75f6. [설계](../docs/90-output-process-isolation.md)의 첫 단계다. 새 internal 타입은 아직 앱 재생 경로에 연결되지 않았다. 사용자 앱·장치·음악·기존 Playback 공개 계약은 이번 변경에서 수정하지 않았다.

`swift test --scratch-path .build/output-protocol-tests --filter OutputWorkerProtocolTests` 최종7개 실패0, 0.009초. 전체 테스트와 실제 child process/장치 테스트는 이번 단계에 포함하지 않는다. 첫6개 검사를 통과한 뒤 방향·sequence gap·chunk 제한을 보완했고, 추가 검사에 있던 괄호 컴파일 오류를 수정해 최종7개를 다시 실행했다. 최종 로그는 `.build/output-protocol-verified-tests.log`다.

검사 범위: 두 packet의 모든 byte 분할점에서 수신 복원, 다중 packet 수신, 다른 session·중복 sequence, 유효 packet 뒤 손상 데이터의 원자적 거절, newline 전16KiB 초과, 중간 EOF/정상 EOF, version/sequence0/frame 수/음수·무한 clock/UTF-8 오류 문구 한도, 반대 방향 packet, sequence gap,64KiB chunk 초과. 오류 뒤 stream은 closed이며 다시 사용할 수 없다. session 내 방향별 sequence는1부터 연속 증가한다.

같은 실행자의 코드·보안 검토: packet에는 실행 경로나 shell 명령이 없고 새로운 I/O를 실행하지 않는다. receive의 임시 복사에만 부분 적용하므로 실패 chunk의 앞쪽 명령은 반환되지 않는다. chunk/frame 크기를 모두 제한하며 이전 session을 새 상태에 적용하지 않는다. 실제 Process/Pipe 생성·stderr drain·임시 PCM 경로 보호·symlink/파일 길이 검사·자식 종료 수명은 아직 다음 구현이다. native device 성공이나 재시도 가능 상태를 이번 통과로 주장하지 않는다.

다음 구현 owner: native utility가 helper executable과 호스트 자식 수명 관리를 맡는다. 이 계약의 packets를 실제 stdin/stdout과 연결한 뒤 hang/EOF/late reply/STOP 재시도 테스트 및 native QA를 수행해야 한다. 독립 agent는 현재 슬롯 제한으로 실행되지 않았다.
