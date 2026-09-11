# build95 route-density native QA

최종 build95 UUID `59D93FC8-5A1C-3898-9FB3-42B37997255F`, Release 40.30초. 신규 unit test는 없으며 root의 parse/Release/native 검증을 구분한다.

`python3 qa/check-route-density-evidence.py`: **PASS — snapshot10개(baseline1+final9), AX검사12개, 자산2개 보존, physical output/audition attempts0**.

fixture는 `console-height/final-shortcuts/reopened.json` r62를 새 ID `4ABFF3B2-38A4-5D26-B76C-7C94A316DDAA`로 복사했다. ID 외 최초 전체 manifest가 동일하며 원본 evidence SHA와 원본/fixture 자산2개 실제 checksum을 확인했다.

| 실제 시나리오 | 결과 |
| --- | --- |
| baseline94 router | AX/PNG에 현재 node와 같은 `출력 1 · 라우터` inline 버튼이 존재한다. |
| final router | 동일 inline 버튼은 없고 `독립 스테레오 출력` header는 남는다. |
| settings·connections 복귀 | root가 각 화면에서 header로 돌아온 `settings-returned`, `connections-returned`는 정확한 router selection이며 header 유지·중복 없음이다. |
| 다중 audio | audio 검색 버튼 클릭 시2결과, Return 후 원본 audio1 selection. 현재 audio여도 `오디오 검색 · 2개`가 유지된다. |
| Command-3 | effect 검색2결과에서 Down/Return으로 첫 번째 게인을 선택하고 `이펙트 검색 · 2개`를 유지한다. |
| Command-1 | source3결과(audio2+MIDI1)에서 Down2/Return으로 MIDI를 선택한다. 단일 MIDI inline 버튼은 없고 MIDI header는 남는다. |
| 다른 role 이동 | MIDI에서 router 버튼을 눌러 돌아오면 router selection과 MIDI inline 버튼이 복원된다. |
| 저장·재열기 | open job completed r62 확인. saved/reopened/최종 디스크 전체 manifest는 strict 동일하다. reopened AX에서도 router header 유지·중복 제거를 확인한다. |

모든 snapshot은 정확한 QA bundle/build/project/path·저장 상태·r62·재생/녹음 비활성·physical0을 검사한다. 음악 비교에서는 hierarchyView/musicRevision만 제외하고 revision62는 별도 exact 검사한다. circleColors pair 배열은 중복 key를 거절하며 사전 의미로 정규화한다. 저장·재열기 strict 비교에는 제외 필드가 없다. 원본 studio SHA는 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`로 보존된다.

root가 1020×768 native 화면과 AX를 확인하고 앱을 종료했다. 원본 scope에서 use-only MIDI/effect 선택 후 표시되는 원본에 없다는 안내는 유지되며 이번 검증은 탐색 동선이다. 해당 node 편집 성공, 물리 출력·청취 또는 전체 DAW 완료를 주장하지 않는다.
