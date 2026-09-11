# build97 workflow-visibility native QA

최종 build97 UUID `A2991ADB-048F-3EE2-B41E-3B731FB9B92E`, Release38.38초. root가 실제1020×768 GUI를 수행했다. checker 결과 **PASS — snapshot20개(baseline1+final19), AX 내용검사6개, 원본자산2개 보존, offline bounce1개, physical output/audition attempts0**다. 수집물은 AX14개·PNG13개이며 모두를 자동 판정했다고 주장하지 않는다. 일부 AX는 전체 트리가 아닌 diff이므로 부재 판단에 사용하지 않았다.

기존 root 생성 baseline96/project `68B5D3D0-07E9-5631-A611-ED78245A4C89`와 MIDI3notes를 사용했다. 후보 packager는 baseline 생성 없이 candidate만 받고 fixture bytes를 보존한다.

실제 검증:

- MIDI toolbar mode/menu/bounce/record와 orbit 이전·다음 선택의 표시를 root 화면에서 확인했다. 메뉴 AX에 import/save/전체 선택 항목이 있고 compact-midi AX에 편집 방식·바운스·MIDI 녹음이 있다. 메뉴 전체선택 항목의 클릭 동작은 확정하지 않았다.
- note-edited r15는 A addedLane의 note 하나만 F♯66→G67로 바뀌고 note-undo r16에서 음악 전체가 복원됐다.
- 중간 메뉴/CUA 입력은 예상과 달랐다. one-note-deleted r17은1note 삭제, delete-undo r17은 복원되지 않은 같은 모델이다. Edit 메뉴 Undo의 delete-restored r18에서 복원됐다. 이후 메뉴 Down 입력이 노트로 전달된 중간 편집은 snapshot이 없으며 root가 Command-Z4회 후 navigation-restored r26의 원래 음악을 확인했다. 이를 메뉴 성공이나 독립 Undo 시나리오 통과로 포장하지 않는다.
- 메뉴가 닫힌 실제 editor focus에서 Command-A의 all-selected r26은 정확히3 IDs, Delete empty r27은0notes, Undo r28은 원음악이다. empty AX의 이전·다음 버튼도 disabled다.
- step/drum-step/piano-roll r28은 음악이 변하지 않고 editor mode만 바뀐다. tail 설정 취소 r14도 음악이 동일하다.
- 실제 bounce job `BF01DF66-E8AE-4B24-A985-EB99EE6EAF4B`가 completed r29로34초(본문32+tail2)를 생성했다. A use에 audio lane/node1개·출력 edge 교체·layout1개 및 asset1개만 변경됨을 정확한 전체 모델로 검사한다. bounce-undo r30은 원래 음악과 원본자산2개로 복원된다.
- compact-midi r30은 실제 MIDI 편집기이며 console40(전체bounds110.5)을 확인한다. `compact.png`는 상위 section 화면이므로 MIDI compact 근거로 사용하지 않는다. saved/reopened/최종 디스크 전체 manifest는 strict 동일하며 reopened open job completed다.

음악 비교는 hierarchyView/musicRevision과 표시 방식인 circleLayout(orbit→freeform)만 제외한다. revision은 시나리오별 정확한 값, circleLayout은 orbit/freeform 실제 값을 별도로 검사한다. circleColors pair 배열이 있으면 중복 key를 거절하며 사전 의미로 정규화한다. 저장·재열기 strict 비교에는 제외 필드가 없다. 원본 studio SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 및 원본/fixture 자산2개 실제 checksum을 확인했다.

## WAV 실체 보존

Undo·재열기 후 fixture/media의 생성 WAV는 없어졌다. `circlr-integration-qa/Bounces/1D5A3539-C670-4B79-887D-7B884D9F8CDC.wav`가 bounced asset SHA와 정확히 일치함을 확인한 뒤 승인된 `qa/generated/workflow-visibility/final/bounce.wav`에 exclusive 복사했다. 동일 SHA 파일이45AA2C81… 이름으로도 있었다. 이 파일을 현재 실행의 원본 파일이라고 단정하지 않고 **bounced asset과 동일 bytes인 보존본**으로 기록한다. checker는 이제 이 보존본을 필수로 읽으며 Bounces 검색에 의존하지 않는다.

직접 재검사 결과 SHA `7fcfb393e3298da2c6b3fa782f1b9f1b69b5e5d26028d2aa5eea2526ba0cb566`, stereo24bit48kHz, 1,632,000frames/34초, peak0.0951693058013916, RMS약0.00955029266이다. 보고서 JSON만 신뢰하지 않고 WAV bytes를 읽어 hash·header·PCM을 검사했다.

모든 snapshot은 정확한 QA bundle/build/project/path, 저장·revision 상태, 재생/녹음 비활성 및 physical0을 검사한다. root가 QA 앱을 종료했다. 실제 녹음·장치 출력·청취와 전체 DAW 완료는 주장하지 않는다.
