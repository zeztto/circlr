# build92 router-level native QA

최종 후보 build92 UUID `F09EA2C6-0219-3705-A78B-7094AD718D6C`, Release 41.35초. root 보고 관련 테스트 19개가 통과했다. 첫 Release는 빌드 중 source 변경 감지로 exit 1 중단했고, 이 문서는 freeze 후 최종 후보의 실제 native 증거를 사용한다.

`python3 qa/check-router-level-evidence.py`: **PASS — baseline 회귀 snapshot 3개, 후보 snapshot 25개, 후보 AX 검사 12개, authored 자산 2개 보존, physical output/audition attempts 0**. 전체 snapshot은 28개다. 수집한 모든 AX를 검사했다고 주장하지 않으며 실제 검사 목록은 checker에 고정했다.

fixture는 `signal-level/final-scroll/reopened.json` r28을 새 ID `BEBD7202-BE4A-5FA1-95A5-880069F80993`로 복사했다. 최초 음악 설정은 첫 use의 router `FC5544DC-54E1-5CBB-80C3-514C5087D9C1` override에서 IN1→OUT1 gain만 `1`에서 `10^(−6/20) = 0.5011872336272722`로 바꾼 것이다. source section과 다른 use는 보존하며 신규 mix/router는 없다. checker는 최초 모델을 원본 evidence와 전체 비교하고 evidence SHA도 확인한다.

| 실제 시나리오 | 판정 |
| --- | --- |
| baseline91 무편집 Return | r28→29에서 `.5011872336272722`가 `.5`로 변하고 routes 순서가 `[11,22]`→`[22,11]`로 이동한다. 이 두 차이 외 음악은 동일하며 Undo r30에서 정확히 복원된다. 결함 재현이다. |
| 후보 무편집 Return | `numeric-entry-recheck` AX 후 `untouched-return-confirmed` r30이 정확한 gain과 route 순서를 유지한다. 최초 `untouched-return`은 focus 근거가 약해 부가 보존 기록으로만 사용한다. |
| 4행 Tab 편집 | root가 −3/−12/−18/−6을 연속 입력했다. r34 모델의 정확한 배열은 `[11(−3),22(−6),12(−12),21(−18)]`다. Undo4 후 r38은 원래 음악 전체다. 행별 r31…33 JSON은 없으며 Tab 동작 근거는 root 실행과 3개 AX/선택 텍스트, PNG다. |
| 제거·재추가 | IN1→OUT1 `−inf`로 route 제거 r39, 0 dB로 재추가 r40 후 Undo2 r42에서 원래 route 순서와 값이 복원된다. |
| GainFader | 직접 slider 클릭 r43은 약 −30 dB이며 Right r44가 정확히 +0.5 dB다. Undo2 r46 원복. 초기 Shift-Tab 탐색은 설정으로 이동했으므로 keyboard-only slider 탐색 성공은 주장하지 않는다. |
| 공유 원본 | original-view r46은 음악 불변. original-edit r47은 source IN2→OUT2 gain만 −3 dB로 변경하고 use-local precise override는 그대로다. Undo r48 원복. |
| invalid·취소·focus | invalid 20 dB, Escape 취소, −9 draft 후 mix/router 왕복 모두 r48 음악 불변이다. invalid AX에 입력 범위 오류가 보인다. |
| 이름 draft 후 preset | 이름 `라우터 프리셋 검증`을 입력하고 cross preset 첫 클릭이 이름과 cross routes를 적용한 r50이 된다. Undo2 r52 원복. |
| 숫자 draft 후 preset | −9 draft를 둔 default preset r53은 원본과 같아진 router override를 제거한다. 늦은 Return은 r53 모델을 바꾸지 않고 `편집 대상이 변경되었습니다. Esc로 취소한 뒤 다시 입력하세요`를 표시한다. Escape+Undo r54에서 precise 초기 모델 복원. |
| 저장·재열기 | completed open job r54 확인. saved/reopened 및 최종 디스크 manifest가 strict 동일하며 재열기 비교 예외가 없다. root의 1020×768 PNG와 AX에 하단 표시·원래 값이 남는다. |

음악 비교에서는 `hierarchyView`와 `musicRevision`만 제외한다. revision은 각 캡처의 예상 정수로 별도 검사하고 `circleColors` pair 배열은 중복 key를 거절하며 사전 의미로 정규화한다. 각 수정은 정확한 예상 전체 모델과 비교하므로 의도된 source 편집을 제외한 source section, 다른 use, node gain·설정 및 자산 보존도 포함한다. 표시만으로 선형 저장값을 추정하지 않는다.

원본 studio manifest SHA-256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`다. 원본과 QA fixture 자산 2개의 실제 파일 checksum을 확인했다. 모든 snapshot은 정확한 QA bundle/build/project/path·저장 상태·revision 일치·재생/녹음 비활성·physical attempts 0을 검사한다. root가 앱을 종료했다. 물리 출력·청취 및 전체 DAW 완료를 주장하지 않는다.
