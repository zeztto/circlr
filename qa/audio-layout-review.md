# build 73 오디오 편집 배치 검증

2026-09-09. 기준18eeb4a, `codex/daw-integration`. 실제 슬롯 제한에 따라 UX/native utility/review/QA를 순차 수행했다.

## 변경

좌우 ScrollView 수치 폼을 제거하고 전체 폭 파형 아래에8개 필드를 두 줄로 배치했다. 분할·복제·바운스·템포 추종·음소거·삭제는 상단에서 조작한다. 전체 파일·선택 구간·확대·커서 보기는 파형 바로 아래에 있다. 편집 함수와 유효성/원본 범위는 변경하지 않았다.

1019×768·콘솔 펼침 화면에서8개 필드와 주요 조작이 스크롤 없이 보인다. 파형이 이전 좌우 폼 사이 약480px에서 약930px로 넓어졌다(화면 관찰값). 작은 창의 파형 높이는 약85px로 줄어들지만 확대·시간 편집은 직접 조작 가능하며, 큰 창에서는 가용 높이를 채운다. 숫자 필드 순서는 기존 NumberFieldFocus를 유지해 배치→Tab→원본 시작을 확인했다.

## 검사

- release37.83초, debug/test 빌드1.92초. 관련 AudioEditing/AudioSourceViewport14개 테스트 실패0(0.018초). 레이아웃 범위에 맞춰 관련 회귀만 실행했으며 전체496개를 이번 빌드에서 재실행했다고 주장하지 않는다.
- 최종UUID `A8166669-02F1-3FF6-A9AC-1BA94AF75F73`, source2개 hash·release Mach-O sections·codesign·kit25개 hash 대조.
- `python3 qa/check-audio-layout-evidence.py`: native11개 전체 문서/음악 상태 통과. 원본 및 다른 사용/노드/자산/연결을 포함해 비교했다.
- 분할 커서7.25초→원본 시작2초(r15), 상대 커서는5.25초로 보정. 페이드100/200ms(r17). 세 번 Undo 후 원본 BPM90·템포 추종(r22), 재생 길이24초 표시. 실제 재생은 하지 않았다.
- 템포 두 번 Undo 후7.25초에서 상단 분할(r25): 앞7.25초, 뒤24.75초/배치14.5박, 같은 source render window 유지. Undor26 전체 음악 복원.
- 32초 전체 구간 복제는 공간 부족으로 기존 오류 알림을 표시했다(`duplicated.jpg`). 성공 근거가 아니다. 끝을16초로 줄인 뒤 복제r28: 원본16초/복제16초·배치32박. 두 번 Undor30 전체 음악 복원.
- 파형 확대8–24초 표시, 저장 재열기 job `200709A8-3630-4B5B-8E51-F665B38AC336` completed. 확대 보기와 음악 유지. 큰 창 검사 후 원래 작은 창 복원, 앱 종료.
- 상태: baseline14/trimmed15/fades17/tempo22/split25/split-undo26/duplicate-fit28/restored30/zoomed30/reopened30/small-restored30. 화면·AX는 로컬 `qa/generated/audio-layout`에 보관한다. 추가 화면field-tab/large-window 및 실패duplicated도 보존한다.
- 사본ID `F85AA82A-2452-580B-ABFA-222C0F886186`, `audio-layout.circlr`. 최종r30 음악은 초기r14와 같으며 hierarchyView/revision만 다르다. 원본manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 authored tone2개 checksum 유지. 재생/audition attempts0, 녹음false.

## 후속

파형에서 Tab으로 수치 필드에 바로 들어가는 별도 경로는 아직 없다. 재열기 직후 Tab은 캔버스로 이동했으며, 필드 안의 Tab 이동만 검증됐다. 복제 공간 부족을 실행 전 알려주는 흐름과 함께 다음 작업으로 다룬다. 물리 출력/입력·VoiceOver·바운스·사용 앱 교체는 이번 레이아웃 검증에 포함하지 않는다. root/ports/사용 앱은 보존한다.
