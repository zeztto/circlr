# 동명 테이크 번호 표시

상태: build110 소스 구현 완료, `.build/build110-release.log`에서 Release38.99초·exit0 확인. native·checker·시각 검증을 통과했다. 이전 출력 reader 수명 수정을 포함하지만 해당 수정의 기존 테스트와 build110 검증을 구분한다.

## 표시와 검색 계약

현재 편집 대상에 적용 가능한 eligible 테이크 목록을 먼저 열거하고 각 행에 `#번호 · 이름`을 표시한다. 검색 안내는 `#번호 · 테이크 이름 · 노트 · 클립 검색`이다. 이름과 내용 요약이 같은 테이크도 번호로 구분한다.

번호는 검색 필터 적용 전 eligible 순서다. 같은 목록에서 검색 결과를 좁혀도 다시 1부터 번호를 붙이지 않는다. 목록이나 대상이 달라지면 바뀔 수 있으며 영구 ID·녹음 연번이 아니다. 실제 명령 식별과 적용은 기존 take.id를 사용한다. 표시 변경으로 프로젝트의 이름·음악 데이터·테이크 ID를 다시 쓰지 않는다.

## 검증 증거

- `.build/build110-release.log`: Release38.99초·exit0. `qa/generated/take-identity/final/package.json`: build110, UUID `DC416230-4D16-3A4F-AE22-B1E67F95A6EC`.
- 실제 UI에서 ⌥⌘T 진입·Down 키보드 이동·`#2` 검색·Return 적용·⌘Z Undo·재검색 시 query reset·Esc·저장/재열기를 수행했다. 필터 뒤에도 `#2`가 유지되고 정확한 테이크가 적용되는지 확인했다.
- `before`, `applied`, `undo`, `restored`, `reopened` 5개 snapshot의 revision은 각각30/31/32/32/32다. checker가 정확한 적용 대상과 gain·복원/재열기를 대조해 통과했다. fixture seed metadata는 runtime snapshot과 구분했다.
- `all-takes`, `keyboard-selection`, `number-filter`, `reset` AX/JPG4개와 시각 검토를 통과했다. 동명 행의 번호·검색 안내가 표시되며 잘림이 없다.
- 자산2개·output/record0을 유지했다. QA 앱은 ⌘Q로 종료했고 사용자 앱 PID86114만 남은 것을 확인했다. 이전 출력 reader 수명 수정이 이번 소스에 포함되지만 기존 회귀 테스트 수치를 새로 실행한 것으로 계산하지 않는다.

물리 출력·readback·hotplug는 이번 표시 변경의 검증에 포함하지 않는다. 별도 이름 검색 조합 전체나 목록 변경 후 번호의 영구성을 검증했다고 주장하지 않는다.
