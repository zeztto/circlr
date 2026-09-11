# 바운스 경로와 여운 안내의 독립 표시

상태: build106 source review·Release38.64초·아래 native/checker·시각 검토 통과.

## 기준 재현과 표시 계약

build105에서 현재 서클이 출력 경로 밖이고 manual tail0인 경우 경로 메시지 때문에 여운 경고가 숨는 것을 실제 확인했다. 기준 근거는 `qa/generated/bounce-notices/baseline/compact.*`다.

`TrackBounceStatus`는 경로 안내와 여운 안내를 독립적으로 표시한다. 실제 표시한 경로 문자열과 정확히 같은 안내만 중복 제거한다. 의미가 다르거나 화면에 표시하지 않은 메시지를 중복으로 가정해 숨기지 않는다.

## 검증 조건

1. 경로 밖+manual0에서 경로 안내와 여운 경고가 함께 보인다.
2. 정확히 같은 표시 문자열만 dedup되고 서로 다른 안내는 유지된다.
3. 축소 편집 화면에서 안내와 기존 복구 동작에 접근한다.
4. 표시 변경으로 음악·실제 I/O·기존 바운스 판단을 변경하지 않는다. 최종 Release·native·QA 근거를 받은 범위만 완료로 기록한다.

## 최종 근거와 제한

UUID `75DB1C57-8440-38B7-B7AE-84FA7A45E078`. final dual/settings/compact JPG·AX에서 두 경고 동시 표시를, auto JPG·AX에서 여운 경고 해제를 확인했다. 여운 설정 버튼→0.00 field→Esc 취소, compact의 읽힘·파형 손잡이 비겹침, 메뉴 자동 추정 복귀 시 tail 안내만 사라지는 동작을 확인했다. compact 우측 도구는 가로 스크롤을 사용하며 시각 검토를 통과했다.

checker baseline1+final5 상태의 revision22·음악 무변경·자산2개·strict 재열기를 통과했다. 실제 audio attempts0이며 검증 앱을 종료했다.

이번 slice에서 실제 바운스·물리 I/O·경로 복구 버튼 실행은 검증하지 않았다. exact dedup은 source review로만 확인했으며 native 경고 동시 표시와 구분한다.

compact 검증은 창 resize가 아니라 헤더 wheel로 편집 화면을 축소한 결과다. 종료 후 기존 사용자 앱 PID86114만 실행 중임을 확인했다.
