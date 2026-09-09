# build91 signal-level native QA

첫 native 후보 `final`: build91, Release 38.99초 (`.build/signal-level-release-final.log`), arm64 UUID `15CEA7CC-4CF4-3A69-BA1F-48069D8EC81C`. root가 실제 native GUI 입력 및 캡처를 수행했으며 QA checker는 앱 호출 없이 증거와 실제 파일을 검사했다.

`python3 qa/check-signal-level-evidence.py`: **PASS — snapshot 19개(baseline 3 + final 16), AX 16개, authored 자산 2개 보존, physical output/audition attempts 0**. 별도 `reopen-job.json`의 open completed와 r26도 검사한다.

| 계약 | 실제 근거와 결과 |
| --- | --- |
| 기존 표시 | baseline90 `effect`, `mix`, `router` AX는 출력 볼륨을 선형값 `1`로 표시한다. |
| dB 표시 통일 | final91 세 편집기의 `출력 볼륨 dB` 필드는 `0.00`과 `0 dB 원래 레벨 · −∞ 무음` 안내를 표시한다. effect 내부 게인 파라미터와 node 출력 볼륨은 별개이며 내부 파라미터를 변경하지 않는다. |
| −6 dB 입력 | `effect-minus6` r19, `router-minus6` r23, `mix-minus6` r25 모두 대상 node gain만 `10^(−6/20) = 0.5011872336272722`로 저장한다. 각 AX에 `-6.00`이 표시된다. |
| Undo | effect r20, router r24, mix r26에서 각각 원래 음악 전체로 복원된다. |
| 무음과 unity | `effect-silent` r21은 실제 `-inf` 입력 후 gain 0과 `−∞` 표시, `effect-unity` r22는 gain 1과 `0.00` 표시다. 물리적으로 들은 무음을 의미하지 않는다. |
| no-op·오류·취소 | `effect-noop`, 20 dB `effect-invalid`, −3 draft Escape `effect-cancelled` 모두 r22이고 음악 전체가 유지된다. invalid AX에는 `입력 범위: −∞–12.04 dB`와 입력값 `20`이 남는다. |
| focus 변경 | root의 −9 draft 후 MCP router focus를 거친 `router` r22는 음악을 바꾸지 않는다. draft 자체의 별도 snapshot은 없으며 해당 동작은 root 실행 기록에 의존한다. |
| 저장·재열기 | `saved`와 open completed 후 `reopened`는 r26이고 **전체 manifest strict equality**다. 재열기 비교 제외 필드는 없다. |

fixture는 `port-navigation/final/saved.json` r18을 새로운 project ID `FB8E3942-1B47-58A1-B81D-BDC9C88F7964`로 복사했다. 최초 manifest는 ID 외 전체가 동일하며 source evidence SHA도 검사한다. 기존 mix를 사용했으므로 신규 mix 또는 연결 추가는 없다.

각 음악 비교에서는 `hierarchyView`와 `musicRevision`만 제외하며 revision은 별도로 정확히 검사한다. `circleColors` alternating pair 배열은 중복 key를 거절하고 사전 의미로 정규화한다. effect/mix는 해당 use-local addedNode의 gain 하나, router는 원본 router를 복사한 use-local override의 gain 하나를 변경한 예상 모델과 전체 비교한다. 따라서 다른 use, source sections, router routes, effect 내부 파라미터와 모든 다른 음악 필드 보존을 함께 확인한다. 최종 디스크 fixture도 원래 음악과 일치한다.

원본 `studio.circlr/manifest.json` SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`로 유지된다. 원본과 fixture의 자산 2개 각각 실제 checksum을 확인했다. 모든 snapshot은 정확한 integration QA bundle/build/project/path, 저장 상태, revision 일치, 재생·녹음 비활성을 검사한다.

root의 1020×768 native 화면에서 router 하단 컨트롤은 스크롤 후 접근·입력이 가능했다(`final/router.png`, `router-minus6`). `router-returned`와 `reopened` AX의 router scrollbar는 0이므로 **스크롤 위치 보존은 주장하지 않는다**. 전체 manifest 보존과 화면 스크롤 위치 보존은 별개다. 앱 종료는 root가 수행했다. 실제 출력·청취, 전 gain 범위 native 입력 또는 전체 DAW 완료를 주장하지 않는다.

## 최종 scroll 수정 후보

최종 `final-scroll` 패키지는 build91 UUID `05742A9A-97FE-31C5-B729-A1109FE9A083`, Release 20.04초(`.build/signal-level-scroll-release.log`)다. root 보고 관련 테스트 17개가 통과했다(`.build/signal-level-scroll-tests.log`). CoreEditorViewportState.restored의 scroll whitelist에 빠졌던 router를 추가한 후 실제 native 검증을 완료했다. 기존 `final` 19 snapshot·16 AX는 첫 후보 근거로 보존하며 별도 UUID로 구분한다.

최종 checker 추가 결과: **PASS — final-scroll snapshot 7개, AX 4개**. 두 후보를 합치면 snapshot 26개, 검사 AX 20개이며 각 후보의 검증 범위를 합쳐 같은 바이너리에서 모두 재실행했다고 주장하지 않는다.

- `before`, `bottom`, `returned` r26: router 하단으로 스크롤한 뒤 mix→router 복귀에서 음악과 focus를 보존한다.
- `minus6` r27: 해당 router gain override만 `0.5011872336272722`로 변경한다. `undone` r28은 원래 음악 전체로 복원한다.
- `bottom`, `returned`, `undone`, `reopened`의 첫 번째 nested router scrollbar AX 값은 모두 `1`이다. 외부 console scrollbar와 구분하여 검사한다. 저장된 router scroll 좌표도 `{'x': 0, 'y': 169}`로 유지된다.
- `saved`와 completed open 이후 `reopened` r28 전체 manifest는 strict 동일하고, 최종 디스크 manifest도 reopened와 strict 동일하다. 다른 음악은 hierarchyView/musicRevision 제외 및 circleColors 사전 의미 정규화 기준으로 원래 모델과 일치한다.

root는 1020×768 reopened 화면에서 하단 컨트롤 노출을 확인하고 QA 앱을 종료했다. CUA의 이전 `sigEdit` closure가 이전 final 앱을 자동 재실행한 뒤 blank UI에서 field undefined 오류가 났다. root는 새 final-scroll 앱의 fresh element 70에 직접 입력하여 최종 7 snapshot을 생성했다. 이전 앱은 blank r0·연결 없음 상태였고 기존 Agent 연결 때문에 MCP socket을 차지하지 않았다는 root 확인과 `final-scroll/old-helper-cleanup.ax.txt` 기록이 있다. 이전 앱도 종료했다. 최종 snapshot의 정확한 build/project/path/revision 가드와 새 앱 AX 4개로 증거 경계를 유지하며 제품 입력 실패로 취급하지 않는다. physical output/audition attempts는 두 후보 모든 snapshot에서 0이며 원본 자산 2개 checksum 보존도 계속 검사한다.
