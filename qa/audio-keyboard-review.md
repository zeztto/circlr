# build74 오디오 키보드 입력·복제 안내 검증

2026-09-09, 기준cefba9a. integration worktree에서 UX/native/Core/review/QA를 순차 수행했다. 실제 agent 슬롯 제한은 유지됐다.

## 결과

파형의 Tab/Shift+Tab으로 첫/마지막 수치에 진입하고, 수치 입력 버튼도 같은 NumberFieldFocus registry를 사용한다. OrbitAudioView의 current identity/window 검증 후 이동한다. 입력 Return/Esc는 기존 context로 파형에 복귀한다. 필드 registry의 이동 순서는 유지한다.

AudioClipTiming.duplicateBeat를 UI와 AudioEditing.apply가 공유한다. 반복/명시적 length/tempo-follow/source window에 따른 복제 시작 위치를 동일하게 계산하며 원래 공간 거절 규칙을 유지한다. 불가능하면 ‘복제 · 공간 없음’과 이유 도움말을 표시한다. ⌘D는 음악 변경/오류 창 없이 status로 안내한다. 재생 또는 파일 접근 코드는 추가하지 않았다.

## 검사

- debug4.17초, 전체Swift498개 실패0(25.600초), Python29개 실패0. 신규2개 테스트는 preflight와 실제 복제 위치 일치, tempo-follow, 반복/명시적 길이, invalid offset/공간 부족을 검사한다.
- release63.52초. UUID `192519F5-86D6-3C7D-B696-63265BB8E20A`. source5개 SHA·release Mach-O section·codesign·kit25개 hash 대조.
- `python3 qa/check-audio-keyboard-evidence.py`:7개 전체 문서/음악 상태 통과. 원본/다른 사용/연결/자산도 비교했다. physical playback/audition attempts0, 녹음false.
- 작은1019×768 창: `tab-first` 배치1 선택, `backtab-last` BPM120 선택. BPM90 draft를 Esc로 취소하고 ⌘D를 눌러 r14 음악/120BPM 유지, 오류창 없이 안내(`duplicate-blocked`).
- 수치 입력 버튼으로 첫 필드에 진입(`button-entry`), Tab 두 번으로 원본 끝32초 선택(`tab-end`), 키보드 숫자1·6·Return으로16초 트림r15. 복제 버튼 활성, Return 뒤 ⌘D로 복제r16. 새 서클에서 Tab은 새 배치33박으로 진입(`new-circle-field`).
- 두 번 Undor18로 전체 음악 복원. 재열기 job `8C16B0F0-5275-4CC4-8D39-267603464D90` completed. 저장 당시 축소 캔버스로 열렸으며, 선택된 오디오에 Return→Tab으로 첫 필드, Esc→Shift+Tab으로 마지막 필드 진입을 확인했다. 재열기가 자동으로 확대 편집기를 열었다고 주장하지 않는다.
- AX focus-line 수집 시 NativeNumberField는 selected text만 반환해 `field-order.json`은 빈 항목이다. 전체8개 포커스 이름 자동 검증 근거로 사용하지 않는다. 첫/원본 끝/마지막 필드는 실제 화면과 적용 결과로 검증했다.
- 상태: baseline14/duplicate-blocked14/trimmed15/duplicated16/restored18/reopened18/final18. 화면은별도 `.jpg/.ax.txt`로 `qa/generated/audio-keyboard`에 보관한다. restored/final JSON은 음악 비교용이며 대응 화면은 별도로 만들지 않았다.
- 사본ID `A83DADD3-E8B7-50D2-B336-2857FF1F4764`, `audio-keyboard.circlr`. 최종r18 음악은 초기r14와 같고 hierarchyView/revision만 다르다. 원본manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, authored tone2개 checksum 보존. QA 앱 종료.

## 남은 범위

키보드 도움말·명령 검색에서 최근 편집 동선을 일관되게 안내하는 작업은 후속이다. 자동 카메라 이동/전체 필드 접근성 발화/물리 입출력과 사용 앱 교체는 이번 완료 범위에 포함하지 않는다. 에이전트 MCP의 복제 거절은 기존 Core 오류 계약을 유지한다.
