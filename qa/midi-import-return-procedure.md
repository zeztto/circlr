# MIDI 가져오기 취소 후 편집 위치 복귀 검증

상태: 실행 준비 절차. 이 문서와 helper 작성만으로 native 검증을 완료하지 않는다. 앱·소켓 실행은 root가 수행한다.

## 대상과 캡처

기존 `~/Library/Application Support/circlr-integration-qa/fixtures/midi-import-feedback.circlr` QA 사본만 사용한다. 사용자 앱 PID 86114와 프로젝트 원본은 변경하지 않는다. 새 후보 패키지와 `package.json`은 `qa/generated/midi-import-return/<candidate>/`에 둔다. manifest 형식은 build132 feedback의 package와 같다. 빌드 번호를 명시해 다른 후보나 공유 소켓의 오래된 앱 캡처를 거절한다.

실재 MIDI 파일은 `qa/generated/midi-tempo/tempo-120-60.mid`와 `qa/generated/import/incoming/authored.mid`다. 기존에 직접 작성한 검증 MIDI이며, 생성하거나 다운로드할 필요가 없다. 단일 트랙 가져오기는 목록에서 정확히 한 트랙을 선택한다.

root는 현재 revision을 확인하고 다음 명령으로 캡처한다. `<candidate>`, `<build>`, `<revision>`은 실제 값으로 바꾸며 추정하지 않는다.

```sh
python3 qa/verify-midi-import-return-qa.py capture step-before --candidate <candidate> --build <build> --expected-revision <revision>
```

이 명령은 QA 사본 저장을 수행한다. package SHA·UUID·strict 서명·helper SHA, 정확한 project/revision, 출력/audition 시도 0, 녹음/재생 정지, 자산 SHA를 확인한다. 코드와 실제 번들 Codex manifest 전체 대조는 기존 패키지 감사에서 별도로 수행한다.

## 실제 동선

1. 1024×768 창·122pt 콘솔에서 공유 rhythm MIDI를 선택한다. 스텝 모드의 페이지 2로 이동하고 명확한 선택을 만든다. AX/JPEG와 `step-before` JSON을 남긴다.
2. MIDI 파일 미리보기를 열고 취소한다. `step-cancelled`를 캡처한다. 주소·선택·revision·음악과 manifest의 전체 `hierarchyView`를 helper로 비교하고 스텝 모드, 페이지 2, 행/노트 선택과 가시성은 AX/JPEG로도 직접 비교한다.
3. 일반 MIDI의 노트 모드에서 표시 pitch/beat 범위를 변경하고 노트를 선택한다. `note-before` → 미리보기 → 취소 → `note-cancelled`를 같은 방식으로 비교한다. state 요약과 달리 manifest의 `hierarchyView`에는 workspace·editor·스텝 페이지·카메라·선택이 저장된다. helper는 이 객체 전체와 나머지 manifest를 각각 정확히 비교한다. 저장 직전 pending 복귀가 실제 화면에 반영됐는지는 native 캡처로 확인하며 AX/JPEG로 표시 결과도 대조한다.
4. 다시 미리보기를 열어 한 트랙을 실제 적용한다. 적용 후 새 MIDI target을 선택한 기존 동작이 유지되는지 확인한다. 취소 비교기를 이 음악 변경에 사용하지 않는다. 추가 lane/node/notes와 revision 증가, 새 대상 AX/JPEG를 감사한 뒤 Undo로 음악을 복원한다.
5. stale 경계는 별도 실행한다. 미리보기의 원래 프로젝트와 다른 QA 프로젝트로 전환된 뒤 늦은 취소가 원래 project/address를 복원하지 않아야 한다. 현재 프로젝트를 캡처해 불변을 대조한다. 이 helper는 feedback project만 허용하므로 다른 project 캡처에는 기존 해당 사본 verifier를 사용한다. 실제 UI에서 stale 상태를 만들 수 없으면 source 검증으로 남기고 native PASS로 쓰지 않는다.
6. 최종 저장/재열기·음악/자산 보존을 확인하고 소유 QA 앱만 종료한다.

```sh
python3 qa/verify-midi-import-return-qa.py compare-cancel qa/generated/midi-import-return/<candidate>/step-before.json qa/generated/midi-import-return/<candidate>/step-cancelled.json
```

OpenPanel 전환 중 화면은 성공 캡처에서 제외한다. build132에서 관측한 Cmd+A/Return 전달 불일치가 재현되면 fresh AX로 정확한 파일을 선택하고 조작 실패를 기록한다. 이 경로를 앱 키보드 또는 한국어 IME 전체 통과로 계산하지 않는다. 물리 오디오·청취는 이번 검증 범위가 아니다.
