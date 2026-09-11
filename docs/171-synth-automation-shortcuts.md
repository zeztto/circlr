# 신스 수치에서 오토메이션으로 바로 이동

상태: build148 직접 이동의 Release·아래 native 검증을 완료했다. 재시작·data·native UI 감사도 완료했다. build147의 공명 구현 완료와 이번 진입 UI 검증을 구분한다.

## 변경 범위

현재 instrument 편집에서 cutoff·resonance 수치 옆 오토메이션 버튼을 제공한다. mode와 parameter를 따로 선택하던 두 단계를 한 번의 직접 이동으로 줄인다. Inspector·Inline editor·Automation의 세 UI 파일에서 현재 instrument에만 명시적으로 활성화한다.

이동은 정확히 같은 주소·track·parameter와 original 범위를 유지한다. global track/signal 화면에는 표시하지 않고, 지원하지 않는 engine v1의 resonance 버튼도 숨긴다. 화면을 열기만 해서는 곡선을 생성하거나 음악을 바꾸지 않는다.

유효한 수치와 이름은 이동 전에 확정한다. invalid 입력은 현재 화면에 남기고 stale 대상은 거절한다. 정적 synth 값은 track 전역에 적용되는 반면 곡선은 해당 편집 scope를 따르므로 도움말에서 이 차이를 설명한다.

## 검증 기준

- 현재 instrument의 cutoff/resonance에서 한 번의 클릭으로 같은 주소·track·parameter·original을 여는지 확인한다. global/signal·미지원 engine에서는 버튼이 없는지 대조한다.
- 단순 열기의 음악·revision·곡선 불변, 유효 draft의 한 번 확정과 invalid/stale 이동 차단을 확인한다.
- original/이번 use 범위를 구분하고 이전 곡선이나 다른 track을 잘못 선택하지 않는지 비교한다.
- 실제 작은 화면에서 버튼·수치·도움말 가시성과 키보드 접근을 AX/JPEG로 확인한다. 실행하지 않은 모든 scope·폭·접근성 조합은 별도로 기록한다.

아래 실제 검증 범위와 미실행 조건을 구분한다. 물리 I/O·청취·새 DSP 기능을 이번 UI 개선 완료로 주장하지 않는다.

## build148 실행 결과

최종 12pt 후보 `shortcut148-verified` Release는 48.28초에 통과했다 (`.build/build148-verified-release.log`). package·source 검토도 PASS했다. 시각/탐색 변경으로 새 unit 또는 전체 suite는 실행하지 않았으며 build147의 568개 검사를 이번 결과로 세지 않는다.

r219에서 유효 cutoff draft 3000을 버튼으로 열면 r220에서 한 번 commit했고 Undo r221에서 2400으로 복원했다. invalid `x`는 mode·오류·focus와 r221을 유지했고 빈 이름도 이동을 차단했다. cutoff/resonance 버튼은 정확한 같은 주소·parameter와 plot focus를 선택했다. End는 마지막 20% 점을 선택했으며 음악은 바꾸지 않았다.

공유 원본 scope 1에는 점 0개가 그대로 유지돼 단순 열기로 곡선을 만들지 않았다. 이번 use scope 0으로 복귀하면 기존 점 3개를 r221에서 유지했다. final-restored 뒤 실제 PID 54158→54557 재시작·재열기에서 r221 전체 manifest·hierarchyView가 정확히 일치했다. native UI 감사는 PASS_WITH_EXPLICIT_LIMITS다.

미지원 host·stale 경계는 소스 검토 범위다. 모든 폭·Tab 조합·물리 I/O는 실행하지 않았으며 전체 DAW나 접근성 완료를 뜻하지 않는다.

data 감사의 실제 상태는 `PASS_WITH_ADDITIONAL_METADATA_CHANGE`다. 캡처 6개·자산 SHA 7개와 source route145 r212 보존을 확인했다. 유효 draft 적용은 cutoff 외에 `signal.nodes[3].name`도 동기화했다. 이는 기존 AppStore.updateTrack의 명시적 동작이며 QA 사본의 이전 track 이름 불일치를 맞춘 것이다. cutoff만 바뀌었다고 주장하지 않으며 Undo는 두 필드를 모두 복원했다. package 감사도 PASS했다.

최종 native UI 감사는 JPEG/AX 12쌍에서 `PASS_WITH_EXPLICIT_LIMITS`이며 높은 확신의 결함은 없었다. 직접 버튼 진입의 plot focus는 확인했으나 재시작 focus는 canvas 26이므로 자동 plot focus 복원을 통과했다고 주장하지 않는다.
