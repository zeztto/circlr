# 오디오 템포 구간과 빠른 편곡 입력

상태: build113 Release 73.53초·exit0, 관련 테스트 16개(tempo 13개 포함) 통과. 오디오 native checker는 9개 capture를 통과했다. 편곡 checker도 9개 JSON·AX/JPEG 7개로 통과했다. source review는 blocker0이며 시각 JPG 10장과 AX 검토는 경미한 관찰 사항을 남기고 통과했다.

## 실제 클립 구간과 선택 출력

오디오 클립이 재생되는 구간 안에서 BPM이 일정한지 검사한다. 일정 구간의 Core 공통 split와 legacy/graph render를 허용하며, 실제 BPM 변화 지점을 가로지르거나 반복 시작 BPM이 다르면 계속 명확히 거절한다. 가변 템포 오디오 stretch 전체를 지원하는 것은 아니다.

선택 트랙 바운스는 전체 section을 렌더한 뒤 추출하던 방식을 endpoint 의존성 plan으로 바꿨다. `SectionSignalSelection.swift`가 필요한 MIDI·sidechain·router bus를 유지하며, `AgentWorkspace`의 tail 계산과 render가 같은 plan을 사용한다. 관련 없는 crossing clip 때문에 선택 트랙까지 실패하지 않는다.

## 자동 검증과 Release

- 초기 tempo RED 2 failures 후 `.build/build113-tempo-final2.log`의 13 tests·0 failures를 확인했다. 중간 App compile 오류는 해소됐으며 추가 테스트 대기 상태가 아니다.
- 선택 출력 RED는 1 failure·0.133초를 재현했고 `.build/build113-output-selection-green.log`의 16 tests·0 failures·6.848초로 통과했다. 이 16개는 앞선 tempo 13개와 추가 selection 3개의 합계이며 29개의 독립 검증이 아니다. Audio A 선택 성공, B/전체 render 거절, PCM 동등성과 Core MIDI·sidechain·router bus를 포함한다. 초기 RED fixture trap은 제품 실패/성공 근거에서 제외한다.
- `.build/build113-release-final.log`: 73.53초·exit0, UUID `BAE18DB5-1AF7-3F53-824C-72C7356122CC`.

## 오디오 native와 실제 offline WAV

`qa/generated/audio-tempo-region/final`의 9개 capture, revision 14→18을 checker로 대조했다. 실제 split·bounce·Undo, crossing split의 native alert와 crossing bounce 실패, 정확한 재열기를 확인했다. restored.manifest·reopened.manifest·fixture/manifest.json은 전체 동일하며 reopen job의 open/completed/progress1과 경로도 대조했다. 원본 자산 2개의 SHA를 보존했다.

`bounced.wav`는 실제 offline 바운스 결과다. 28초·stereo·48 kHz·nonzero이며 SHA256은 `5cc29c776e07078d4a54b9966f2179a75ac90154bf202005ec9bf7ae21b4d522`다. 물리 출력 attempt는 0이다. offline 파일 성공을 실제 재생/readback/hotplug 성공으로 계산하지 않는다.

## 빠른 편곡 입력

coordinator와 안정된 field로 빠른 복제·rename 입력을 연결했다. 최종 native는 9개 capture, revision 17→20이다. cold open 후 D/paste로 복제, 계속 편집, N/paste rename, `#2` 검색 뒤 D에서 원본 B 표시를 확인하고 취소했다. 실제 B 복제 commit은 수행하지 않았다. 검색 복원·reset·Undo·재열기를 수행했으며 reset은 AX만 확보했다. 최종 checker는 9개 JSON·AX/JPEG 7개, 모든 helper SHA·원본 자산 2개·continuation·Undo·재열기·disk equality로 통과했다. `resetAXOnly=true`, `candidateBCommitVerified=false`, `IME=false`다.

preview Release 75.25초의 사전 성공은 최종 승인과 구분한다. 첫 preview timeout은 Undo 뒤 album이 선택된 상태여서 곡 편곡 picker에 진입할 수 없었던 테스트 조건이다. 이를 제품 실패로 분류하지 않는다.

## 검증 경계

명시적 output deny 환경에서 작업했고 사용자 앱은 교체하지 않았다. QA 종료 후 기존 PID86114가 유지된 것을 확인했다. 기존 build112·reader 수명 검증은 이번 수치에 합산하지 않는다. 오디오·편곡 checker는 root 재실행에서도 통과했다. 시각 JPG 10장·AX에서는 단일 입력 field와 버튼, 원본 #2/현재 #3 구분, 취소 후 검색 복원, 계속 편집과 오디오 도구의 겹침 없음을 확인했다.

## 남은 UI 개선

시각 검토는 `PASS_WITH_MINOR_OBSERVATION`이다. 0.5초 split 파형의 시작/끝 라벨이 가까우며 before에서도 비슷하게 관측됐다. reset 화면 마지막 행의 상세 일부는 스크롤 아래에 남지만 제목·복제 동작·키보드 안내는 보인다. 이 두 항목을 개선 여지로 유지하며 모든 화면 조합이 완전하다고 주장하지 않는다.
