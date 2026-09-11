# 렌더 tail 정책과 보존 범위

상태: build87 Release·대상 테스트·아래 native 검증 확인. QA checker 최종 대조 통과. [QA](../qa/render-tail-review.md).

## 문제와 목표

기존 compiled renderer probe에서 고정2초 tail이 잘라내는3–6초 구간에 peak0.1024(약−19.8dBFS)·RMS0.008464를 확인했다.1초 body의 끝 직전 pulse, delay1초·feedback0.8 조건이며 tail2초/5초의 앞3초는 동일했다. [재현 도구](../qa/probe-bounce-tail.py).

효과의 감쇠와 보존된 오디오의 실제 끝을 고려해 렌더 길이를 정하고, 직접 길이 선택·추정 한계·자원 제한을 명시한다. 자동 추정은 무손실 보장이 아니며 짧은 무음 구간을 감지해 자동 종료하지 않는다.

## 공통 계산 계약

`RenderTailPlanner`를 바운스·일반 재생·export의 공통 근거로 사용한다.

- 자동은 Swift 내부에서 `tailSeconds=nil`이며 기본 하한2초를 유지한다. 내장 DSP의 상대−80dB 감쇠, 소스 release, 보존 클립의 실제 끝을 고려한다.
- 직렬 경로는 효과 tail을 합산하고 병렬 경로는 최댓값을 사용한다. router의 bus 연결을 반영한다.
- 직접 지정은0–120초를 허용한다. 자동 추정이120초 상한에 도달하면 잘림 가능성을 알린다.
- Audio Unit처럼 tail을 확정할 수 없는 경우 미확정 안내와 fallback을 제공한다. 추정값을 확정된 실제 끝으로 표시하지 않는다.
- 기존 메모리 예산을 넘는 요청은 실행 전에 거절한다. 알리지 않고 길이를 줄여 통과시키지 않는다.
- 긴 바운스 파일의 저장뿐 아니라 일반 play/export buffer도 보존 클립의 actual duration·rate·repeat에 따른 실제 끝을 포함한다. section body와 다음 section의 시작 시각은 변경하지 않는다.

## UI·MCP 계약

기존 실행 줄에서 자동/직접 tail 설정과 필요한 상한·미확정 안내에 접근한다. 별도 반복 패널이나 불필요한 세로 행을 추가하지 않는다. 실행 job은 실제 적용 tail과 끝 구간 측정값을 구분해 보고하고 취소 가능 상태를 명시한다.

MCP의 선택 인자 `tailSeconds`는0–120초 숫자이며 생략하면 자동이다. JSON `null`은 허용하지 않는다 (`nil`은 Swift 내부 표현에만 사용한다). GUI 세션의 tail 설정과 분리해 MCP 요청이 화면 설정을 암묵적으로 상속하거나 변경하지 않도록 한다.

## 검증 완료 기준

1. 기존 probe의 고정2초 손실을 기준으로 자동 길이·직접 길이의 PCM과 끝 구간 측정을 대조한다. 상대−80dB 계산 결과와 측정값의 의미를 구분한다.
2. 소스 release·직렬 합·병렬 max·router bus·보존 클립 actual duration/rate/repeat를 대표 fixture로 검사한다. section body와 다음 section 시각이 변하지 않는다.
3. 직접0/120초 경계와 범위 밖 거절, 자동120초 상한 안내, AU 미확정/fallback, 메모리 사전 거절을 검사한다. 조용한 clamp와 짧은 silence-window 종료가 없어야 한다.
4. 일반 play/export buffer와 바운스에서 긴 보존 클립의 끝이 유지되는지 확인한다. 오프라인 확인과 실제 장치 출력 검증은 분리한다.
5. 실제 UI에서 자동/직접 선택·오류·상한/미확정 안내·job actual tail/끝 구간 측정·취소를 확인하고 작은 창의 기존 편집 공간을 보존한다.
6. MCP의 생략/직접 인자와 GUI 세션 설정의 독립성, 취소 후 늦은 결과 적용 방지, 기존 Undo·저장/재열기·음악 보존을 확인한다.
7. 최종 Release·대상 테스트·native·QA 대조 근거를 확보한 범위만 완료로 기록한다. 물리 I/O 출고와 청취 품질은 기존 별도 조건을 유지한다.

## 최종 후보의 검증 범위

- Release52.98초 (`.build/render-tail-release.log`), UUID `834466A4-A91B-32E3-985F-E675044A8F95`.
- Audio30개 실패0·16.872초 (`.build/tail-audio-focused.log`), Core `AgentTailArguments`3개·MCP22개·kit9개 통과.
- baseline/직접34초와 자동74초의 앞34초 PCM 동일. 자동 바운스74초와 export74초 모두 재열기 전후 파일 바이트 동일.
- 실제1020×768에서 Return은 설정만 적용,121 거절, 자동 tail42초·직접2초·상한120초·끝 신호 경고 확인. 파형85px 유지.
- 실제 direct RPC의121은 job 생성 전 거절. STOP 뒤 running→cancelled 전환과 이후 안정 상태 유지 확인.
- 원본2개·생성1개 자산 보존, 실제 출력0회·사용자 앱 유지·검증 앱 종료.

실제 UI running 스피너는 렌더가 빨리 끝나 캡처하지 못했다. AU는 단위 metadata 검증만 수행했다. 위 실제 관측을 전체 검증 기준이나 청취·물리 I/O 출고 완료로 확대하지 않는다. QA checker가 baseline4개+final18개 문서 캡처와 RPC 오류/취소2개 기록을 대조했다. 성공한 오프라인 렌더는7회(기준1+후보6)이며 취소1회·peak 보호 실패1회를 별도로 확인했다. 상한120초의 실제 완료 파일은 확보하지 않았다.
