# build90 포트 경로 탐색 native QA

최종 후보는 build90, Release 73.47초, arm64 UUID `02B23788-DB57-3B8F-890E-4FC7A283B28C`다. Core 관련 Swift 36개 통과는 root가 별도로 확인했다. 이 문서의 native 근거는 `qa/generated/port-navigation`의 baseline89 및 final90 기록이며, checker는 앱 호출 없이 저장된 증거와 실제 자산 파일을 읽는다.

`python3 qa/check-port-navigation-evidence.py` 결과: **PASS — native snapshot 10개, AX 7개, 원본 자산 2개 보존, physical output/audition attempts 0**.

## 재현 및 최종 동작

| 시나리오 | 실제 근거 및 판정 |
| --- | --- |
| baseline89 독립 bus 오염 | `baseline/track2-effects` AX에 출력 2의 이펙트 2개가 잘못 노출된다. `track2-effect-source`는 출력 2 오디오 `검증 톤 2`를 선택한다. 기존 결함 재현이며 통과 동작으로 취급하지 않는다. |
| final90 독립 bus | `final/track2-effects` AX/PNG에 출력 2 이펙트 0개, `track1-effects` AX에 출력 1 이펙트 2개가 나타난다. |
| 이펙트에서 트랙 추론 | 출력 2를 선택했던 상태에서 실제 이펙트에 MCP focus 후 `effect-track-inference`에 출력 1의 source 3개가 나타난다. 원본 오디오, 미연결 복제 오디오, MIDI를 포함한다. |
| router 교차 변경 | root가 GUI에서 bus1→bus2 및 bus2→bus1을 클릭했다. `crossed` r17은 해당 use의 router override 하나만 추가한다. AX 결과는 출력 2 이펙트 2개, 출력 1 이펙트 0개로 바뀐다. |
| 실제 Undo | root의 Escape 및 Command-Z 후 `undone` r18의 음악 전체가 r16과 일치한다. source section, 다른 use, tracks, assets 등 다른 음악 필드는 모두 보존된다. |
| 저장 및 재열기 | `saved` 저장 후 MCP open job의 completed를 확인하고 `reopened`를 저장했다. 두 전체 manifest가 strict equality로 일치한다. 재열기 비교에는 제외 필드가 없다. |

## 보존과 비교 경계

fixture는 검증된 build89 `track-shortcut/baseline/prepared.json`을 새로운 project ID로 복사했다. `baseline/fixture-origin.json`의 원본 evidence SHA를 실제 파일과 대조하고, ID 변경 외 음악 전체가 동일함을 검사한다. 탐색용 use-local 복제 오디오·빈 MIDI·이펙트가 들어간 기존 QA fixture이며 사용자 곡을 수정하지 않았다.

음악 비교는 탐색 카메라·선택 상태를 담은 `hierarchyView`와 의도적으로 증가한 `musicRevision`만 제외한다. `circleColors`의 alternating key/value 배열은 중복 key를 거절하고 사전 의미로 정규화한다. revision은 별도로 r16→교차 r17→Undo r18을 정확히 검사한다. 교차 상태는 원본 모델에 두 router route를 바꾼 override 하나를 넣은 예상 모델과 전체 비교한다. 그 외 캡처와 최종 디스크 fixture는 원래 음악 모델과 일치해야 한다.

원본 `studio.circlr/manifest.json` SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`로 유지된다. 원본과 QA fixture의 자산 2개를 각각 실제 파일 checksum으로 확인했다. 캡처는 integration QA bundle/project로 제한했고 모든 캡처에서 output/audition attempts 0, 재생·녹음 비활성, 저장 상태를 확인했다. QA 앱 종료는 root가 담당했다.

이 검증은 포트 경로 metadata에 따른 UI 후보와 트랙 추론, 실제 GUI 교차 편집, Undo, 저장·재열기 계약을 확인한다. 물리 재생이나 DSP 신호 청취를 검증한 것은 아니며, 전체 DAW 완료를 주장하지 않는다. Core 테스트 수치와 native snapshot/AX 수치는 서로 대체하지 않는다.
