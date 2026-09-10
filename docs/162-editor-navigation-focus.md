# 편집기로 이동한 뒤 키보드 포커스

상태: build140의 아래 포커스 개선을 검증했다. 빠른 모드 전환의 기존 async focus 경쟁은 미해결 후속 범위다. 기준 HEAD는 `6bba567`이며 현재 통합 작업 브랜치에서 진행한다. 최종 state 감사와 재시작 검증은 PASS했으며 UI 감사는 알려진 경쟁을 포함한 `PASS_WITH_KNOWN_RACE`다.

## 실제 재현

`verified/focus140-before/right`의 AX/JPEG/JSON에서 Command+J로 같은 B 통합 키보드 MIDI에 진입한 뒤 스텝 페이지 3의 Right를 누르자 MIDI 서클 내부 cursor 대신 상속한 MIDI 리듬으로 selection이 바뀌었다. 음악 revision은 r166 그대로였다. 화면이 올바른 편집기를 보여도 방향키를 받을 포커스가 그 편집기에 있다는 뜻은 아니다.

`navigateStudio`의 무조건적인 outer focus, 재사용 host의 attach 시 focus 부재와 기존 Enter의 0.32초 timer에 일부 모드가 빠진 경로를 개선한다. 현재 모드를 대상으로 하는 요청 기반 precision focus를 구현하며 지연 시간에만 의존하지 않는다.

## 완료 기준

- Command+J로 새 target 또는 같은 target의 노트·스텝·pitch 등 현재 모드에 진입한 뒤 실제 방향키가 해당 편집기를 조작하는지 확인한다. 선택 주소·음악 불변과 내부 cursor/선택 변화를 구분한다.
- host 재사용과 모드 전환 뒤에도 최신 요청 대상에만 포커스를 적용한다. 늦은 요청이 다른 서클이나 window로 이동한 사용자의 포커스를 되돌리지 않아야 한다.
- 이름·수치의 invalid draft 보호와 기존 Escape·Tab·섹션 설정 왕복을 유지한다. 입력 중 초점을 임의로 빼앗지 않는다.
- 같은 조건의 전후 AX/JPEG와 manifest, 실제 키 입력 결과를 비교한다. 화면 표시나 AX 속성 존재만으로 키보드 동작 성공을 선언하지 않는다.

source 변경·clamp는 별도의 읽기 전용 검토에서 확신할 만한 새 결함을 확인하지 못했다. 이번 우선 범위는 재현된 포커스 문제이며 해당 조합 전체를 새 native 검증했다고 주장하지 않는다.

## 실행 경계

기존 통합 브랜치와 QA 사본에서 검증하고 다른 작업자의 변경을 보존한다. 사용자 원본 프로젝트·앱과 비공개 저장소 경계를 유지하며 외부 공개나 전송을 추가하지 않는다. no-I/O 검증으로 물리 오디오·청취·모든 접근성 성공을 주장하지 않는다. 전체 DAW 목표는 남아 있으며 이번 완료 판단은 편집 진입 후 포커스 범위에 한정한다.

## build140 검증 결과와 한계

최종 `editorfocus140-verified` Release는 46.68초에 통과했다 (`.build/build140-audio-focus-release.log`). package.json UUID는 `2D0D8376-B1E8-37A0-8D9B-ED76465F0E9E`이며 package 감사도 PASS했다. 기반 관련 테스트 39개를 확인했다. 초기 Release 49.04초와 최종 후보를 구분한다.

초기 native에서는 step·piano·pitch 진입, automation 점 추가 r167→Undo r168과 입력 취소·console·invalid 보호를 확인했다. 오디오 Enter는 실패했다. 실제 view인 OrbitAudioView와 무관한 layout flag 분기를 사용한 문제를 content type matcher로 수정했다.

최종 후보에서 audio Enter·같은 주소 Tab의 raw 2/3 입력 취소, step Right 33→34와 Enter의 C#5 35스텝, pitch Tab의 raw 2 취소·Enter, piano Tab, 섹션 설정 왕복, invalid 수치/이름과 console 입력 `focus140x`를 확인했다. 이 결과를 전체 모드 전환의 포커스 완료로 확대하지 않는다.

빠른 Command+2→Command+5→Option+Command+0→Return 연속 입력은 기존 AutomationEditor의 attach async focus가 outer focus를 덮어 점 r169를 추가했다. Undo r170 후 음악은 revision을 제외하고 r166 baseline과 정확히 같았다. fresh AX로 outer focus를 확인한 뒤 Return은 automation plot으로 정상 이동하고 r170을 유지했다. 빠른 연속 입력의 경쟁은 여전히 알려진 P2 결함이며 해결됐다고 기록하지 않는다.

다음 실행 우선순위는 `AutomationEditor`, `PitchBendWorkspace`, `StepEditor`, `OrbitMIDIEditor`, `OrbitAudioEditor`, `EditorView`의 자동 attach 포커스를 공통 request/focus epoch로 통합하는 것이다. 모드 전환 entry request를 먼저 연결한 뒤 기존 자동 attach를 제거해 늦은 요청이 현재 의도를 덮지 않도록 한다. 실제 빠른 전환 시나리오로 후속 수정을 검증한다.

최종 state 감사는 캡처 9개·자산 6개 SHA, r169의 gain 1 점 추가와 r170 baseline 복구를 확인했다. 재시작 후 전체 manifest·hierarchyView·camera·runtime도 PASS했다. UI 감사는 AX/JPEG 22개에서 안정된 automation Enter와 재시작 후 점 0개·r170을 확인했으며 결과는 `PASS_WITH_KNOWN_RACE`다. 빠른 automation 전환 경쟁은 미해결 최우선 작업으로 유지한다. 모든 QA 앱을 종료하고 사용자 production PID 86114를 보존했다.
