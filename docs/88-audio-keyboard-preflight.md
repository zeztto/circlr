# 오디오 키보드 입력과 복제 사전 안내 — build74

planning-gate-v1: development-lead. 기준cefba9a. 실제 슬롯 제한에 따라 UX/native/Core/review/QA 순차 수행. integration worktree만 수정한다.

파형의 Tab/Shift+Tab 및 수치 입력 버튼으로 첫/마지막 수치에 진입한다. 기존 field Tab 순서·Return/Esc 복귀·identity guard를 보존한다. 복제 위치 계산을 AudioClipTiming.duplicateBeat로 공유하여 엔진과 UI의 반복·개별 템포·명시적 loop length 기준이 다르지 않도록 한다. 공간 부족은 버튼/도움말에 미리 표시하고 단축키는 status로 안내한다. 음악·Undo 변화는 실제 편집에만 발생한다.

소유: AudioWorkspace/OrbitAudioEditor/CommittedNumberField, Core AudioEditing, 관련 테스트/문서. 검증: 반복/tempo/loop length/offset 계산 및 engine 일치, 작은 창 키보드 진입/필드 순회/취소·적용, 복제 불가→트림 후 가능→복제/Undo, 저장 재열기. 사용자 앱/원본 음악과 물리 오디오 장치는 보존한다.

## 결과

Swift498개·Python29개와 native7상태를 통과했다. 실제 Tab 진입·취소·키보드 트림/복제·Undo·재열기 결과 및 전체 음악/자산 보존은 [QA](../qa/audio-keyboard-review.md)에 기록했다. 최근 조작을 전체 키보드 도움말/명령 검색에 일관되게 안내하는 작업은 후속이다.
