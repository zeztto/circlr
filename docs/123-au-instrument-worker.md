# Offline AU instrument 실행 격리

상태: build107 관련 테스트27개·9.151초와 실제 패키지4개 PCM 비교·strict 서명 통과. physical I/O 검증과 구분한다.

soundBank/audioUnit의 offline 악기 처리를 별도 worker에 격리한다. 기존 effect worker의 deadline·cancel·reap 모델과 정확한 clock snapshot을 사용한다. 앱 내부 instantiate/render의 crash/hang 영향을 분리하되 보안 sandbox로 표현하지 않는다.

정확한 시간·MIDI 입력·설정 전달과 결과 검증, 취소·deadline·비정상 종료의 정리·늦은 결과 미적용을 확인한다. fake 오류 경로와 실제 악기의 offline PCM 비교는 별도 근거로 기록한다.

실시간 engine·plugin UI·물리 출력과 전체 DAW 완료를 이번 offline 악기 격리와 혼동하지 않는다. 실제 검증 전 모든 악기 호환이나 정상 장치 출력을 선언하지 않는다.

## 확보한 실행 근거

FIFO를 포함한 관련 테스트27개9.151초와 source/process review를 통과했다. 패키지 helper에서 soundBank/audioUnit×clock/host override4개 설정을 각각89100 frames로 비교해 maxError0을 확인했다. 임시 앱 strict 서명 통과, helper UUID `CC45143A-63BB-3A06-BD32-149627FB9184`다. 초기 Release73.20초와 UI 후속 최종 Release40.16초를 구분한다.

CLI 개발 환경에서는 앱 실행 파일뿐 아니라 instrument helper도 함께 빌드해야 한다. 위 PCM 결과를 실제 물리 출력·가상악기 UI·실시간 engine의 성공으로 확대하지 않는다.

27개 구성은 take Core4·clock Core2·instrument protocol5·instrument process8·effect process8이다. 전체를 Audio 전용 테스트 수로 표현하지 않는다.
