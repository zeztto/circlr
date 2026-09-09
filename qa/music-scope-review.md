# build93 music-scope native QA

최종 build93 UUID `6DAA541E-9E77-3F78-B1D3-54F72BFADFF2`, Release 45.48초. root가 GUI를 수행하고 QA checker는 저장된 증거와 실제 자산을 읽었다.

`python3 qa/check-music-scope-evidence.py`: **PASS — baseline 2 + 후보 16 = snapshot 18개, 검사 AX baseline 1 + 후보 8 = 9개, 자산 2개 보존, physical output/audition attempts 0**. 수집한 AX 전체를 검사했다고 주장하지 않으며 목록은 checker에 고정한다.

fixture는 `router-level/final/reopened.json` r54를 새 ID `FAB1D86A-A05B-5F0E-90D4-61A6AC9111EE`로 복사했다. ID 외 최초 manifest는 strict 동일하다. A `C958E497-716C-5DA2-B597-B55375AE2A90`, B `FCC35ACD-B5C0-5625-A383-CBC5123C525B`가 section `416C51A5-7B1C-517E-8354-7F628CDB208F`를 공유한다. A의 기존 node override·edge override·layout·addedNodes를 그대로 유지하여 변경 범위 오염과 실패를 검출한다.

| 실제 시나리오 | 검증 결과 |
| --- | --- |
| baseline92 원본 이름 편집 | r54에서 공유 원본 ON 후 audio1 이름 Return이 `원본에서 변경·삭제된 음악 서클 또는 연결의 변형이 있습니다` alert로 거절된다. r54 및 전체 음악은 그대로다. 데이터 오염이 실제 발생했다고 주장하지 않는다. |
| 후보 원본 이름 편집 | `original-renamed` r55는 source audio1 이름만 `공유 원본 이름 검증`으로 바꾼다. A/B use edits 및 모든 다른 음악은 동일하다. Undo r56 원복. |
| use-only node의 원본 범위 | `use-only-blocked` r56에서 effect 이름 field가 disabled이고 공유 원본에 없다는 안내와 이번 사용 편집 버튼이 나타난다. `use-recovered`는 scope false이며 음악 변화가 없다. |
| 숫자 draft와 scope 전환 | use-local effect에 −9 dB draft 후 원본 scope를 선택한 r57은 기존 A effect amount만 `0.35481338923357547`로 확정한다. source와 B는 그대로다. Undo r58 원복. |
| group 선택 후 router 추가 | r59는 A use.graphEdits.addedNodes에 router `FFE0C2BF-9732-48AF-9792-B2D0F0050D91`와 위치 `(-216,-72)`만 추가한다. source graph나 group membership에 추가하지 않는다. Undo r60 원복. |
| 오래된 draft와 focus | effect −3 dB draft 후 MCP router focus의 `stale-switched` r60은 음악 전체가 동일하다. |
| 이름 draft와 scope 전환 | A router 이름 draft 후 원본 scope 선택 r61은 A override 이름만 `이번 사용 라우터 이름`으로 확정한다. 원본 UI에는 `독립 스테레오 출력`이 보이며 source 이름은 그대로다. 원본 header Return은 r61 no-op. Undo r62 원복. |
| 저장·재열기 | open job completed r62를 확인한다. saved/reopened/최종 디스크 전체 manifest는 strict 동일하며 비교 예외가 없다. |

각 음악 비교는 hierarchyView/musicRevision만 제외하고 revision은 별도로 정확히 검사한다. circleColors pair 배열은 중복 key를 거절하며 사전 의미로 정규화한다. 각 수정은 예상 전체 모델과 대조하므로 변경 대상 외 source nodes·edges·layout과 A/B use graph edits 및 자산 보존을 함께 확인한다. UI scope도 필요한 snapshot에서 별도 검사한다.

원본 studio manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 원본/fixture 자산 2개 실제 checksum을 확인했다. 모든 snapshot은 정확한 QA bundle/build/project/path·저장 상태·revision 일치·재생/녹음 비활성·physical attempts 0을 검사한다. root는 reopened 1020×768 화면을 확인하고 후보 앱을 종료했다. baseline의 첫 Cmd-Q는 실패한 이름 draft alert 때문에 종료되지 않았고, 확인→Escape→Cmd-Q로 종료했다. 물리 출력·청취 또는 전체 DAW 완료를 주장하지 않는다.
