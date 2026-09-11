# build 72 MIDI 선택 바로 보기 검증

2026-09-09. 기준767ed72, integration worktree. 독립 agent 실행은 실제 슬롯 제한으로 불가능해 UX/native utility/review/QA를 순차 수행했다.

## 결과

피아노 롤 상단 ‘선택 보기’와 F로 선택 위치를 직접 찾는다. 선택 전체가 현재 화면에 들어가면 다 함께 표시한다. 시간/음역이 너무 넓으면 anchor를 표시하며 선택ID·음악은 바꾸지 않는다. 고정 눈금20px과 건반60px을 제외하고 추가 여백은 남은 화면 크기만큼 적용한다. 27행 음역 폭/시간 배율을 유지한다. 높은 음역으로 옮긴 뒤에는 topPitch86을 그대로 두고 세로 스크롤238.5로 선택을 표시한 것을 확인했다.

최초 native에서 작은 창의 고정 여백 때문에 위쪽 노트가 가려지는 문제를 발견했다(`before`, `initial-button`). 여백을 조정한 중간 후보에서 세 노트가 모두 보였다(`final-button`). 중간 후보의 F가 상위 캔버스로 전달된 문제는 문자열 비교를 기존 단축키와 같은 keyCode3으로 수정했다. 입력 언어 영향은 추정이며 실제 event 문자열은 수집하지 않았다. 최종 후보에서 동일 F 동작이 피아노 롤 내에서 성공했다.

QA 도중 기존 앱 binding을 참조한 helper가 첫 후보를 다시 실행했다. 해당 앱의 정확한 PID/경로를 확인해 종료하고, 이후 모든 helper에 최종 app 객체를 직접 전달했다. `refined-button`은 그 잘못된 새 앨범 화면이므로 성공 증거에서 제외한다. `keyboard-reveal`은 중간 F 실패 증거다. 기존 사용자 앱/root/ports 앱은 건드리지 않았다.

## 검증 근거

- debug3.65초, Swift496개 실패0(26.135초), Python29개 실패0(0.200초).
- release38.58초 → 여백 보정37.59초 → keyCode 보정 최종37.84초. 전체 테스트 이후 두 native 변경은 최종 release/native 검사로 확인했다.
- 최종 UUID `7792ADC4-39FC-385D-A5F2-C86090649140`; 최종 소스3개 SHA·release Mach-O section·codesign·kit25개 hash 대조.
- `python3 qa/check-selection-reveal-evidence.py`: 전체 문서/선택/음악 상태9개 통과. 녹음/재생/audition attempts0.
- 최종 실제 화면: `final-keyboard`, `far-scroll`, `scroll-returned`, `empty-selection`, `wide-selection`, `undo-reveal`, `low-pitch`, `restored`, `reopened`, `upper-returned`. 각 jpg/AX는 `qa/generated/selection-reveal`에 로컬 보관한다. 1019×768 창/콘솔 펼침 상태에서 확인했다.
- r14에서 세 노트 선택·음역 아래 이동→F·양방향 스크롤→버튼 복귀. 선택 없음 버튼 비활성 확인.
- 한 노트를61박으로 이동r15, 다중 선택/F로 기준 노트61박 표시. Undor16 원래 세 노트 모두 표시.
- 한 노트를pitch0으로 이동r17, 넓은 음역 다중 선택/F에서 C−1 기준 노트 표시. Undor18 음악 전체 복원.
- 저장 재열기 job `6A44F5B5-16DA-4BF4-AEA1-15929E446B60` completed. 선택3개/스크롤 복원 및 한 옥타브 위→F 확인. 모든 QA 앱 종료.
- 사본 `selection-reveal.circlr` ID `7A768999-1E82-5E7B-BB16-E5CE8FFFF0DB`. 최종r18 음악은 초기r14와 같고 hierarchyView/revision만 다르다. 원본manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 및 두 authored tone 자산 보존.

## 남은 범위

본 변경은 피아노 롤의 직접 선택 보기다. 궤도 편집기의 기존 선택 보기는 유지하며 전체 음악 길이/음역을 자동 축소해 한 화면에 맞추지는 않는다. 물리 장치 입출력·VoiceOver 발화·사용 앱 교체는 미검증이다. 다음은 작은 창의 오디오 정밀 조작과 컨트롤 깊이를 줄이는 작업이다.
