# 출력 대기 복구 — build76

2026-09-10. [프로세스 분리 설계](90-output-process-isolation.md)의 host/Playback/package 연결이다. 앱 기본 곡 재생은 내부 circlr-output-worker를 사용하며 기존 장치 backend 주입은 테스트용으로 유지한다. helper가 없는 앱은 설치 오류를 보여주며 in-process fallback을 하지 않는다.

호스트가 렌더 PCM을 private 임시 CAF에4096frame 단위로 기록하고 자식에게 prepare/play를 전달한다. 파일은48kHz stereo Float32이고 from 위치 이후만 기록해 Playback의 기존 offset+clock 계약을 유지한다. stderr는 보관하지 않고 drain하며 stdout frame/session/순서/상태/runID를 확인한다. 출력 시계는 helper의 실제 sampleTime을 따른다.

STOP은 호스트 상태를 먼저 stopping으로 바꾸고 지연된 started/clock이 이를 되돌리지 못하게 한다. 자식은 stdin reader에서 STOP을 즉시 기억하고 장치 호출 사이와 unmute 전후에 확인한다. 정지 요청 후200ms에 EOF, 계속 살아 있으면200ms 후TERM, 다시200ms 후KILL을 해당 Process에만 적용한다. termination callback을 관측한 뒤에만 temp directory와 실행 소유를 해제한다. 정리가 완료되기 전의 시작 요청은 busy로 거절한다. 자동 재생 재시도는 없다. OS가 종료를 지연하는 상황의 강제 완료 시간이나 sample 단위 무음을 보장하지 않는다.

시계 아래 상태 글자를12pt·108pt 폭으로 늘렸다. 준비 초수, 출력 정리 중, 다시 재생 가능을 실제 lifecycle에 따라 표시한다. Space는 준비 취소/새 재생을 기존 동선에서 수행한다. 오류는 상태 줄/콘솔에 표시하며 helper 실패 때문에 음악 편집·Undo를 막지 않는다.

실제 최종 앱에서10초 출력 시간 초과→자식 종료→새 session 재시도→Space 취소를 확인했다. 출력 중이 아니라 장치 준비 대기 중 음악 편집·Undo·저장 응답도 검사했다. 정상 장치 시작은 관측되지 않아 음악 청감·자연 종료·MP4 시계 성공으로 해석하지 않는다. [QA](../qa/output-host-review.md).

MIDI audition과 마이크 입력은 기존 구현이며 이번 helper에 연결되지 않았다. 다음 전체 작업 흐름 점검에서도 그 물리 I/O 완료 조건은 분리한다.
