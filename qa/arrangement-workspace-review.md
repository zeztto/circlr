# 편곡안 이름·복제 작업 — build83

2026-09-10. `qa/generated/arrangement-workspace/`의 별도 authored QA 프로젝트 `9B94570E-4773-5CEA-BA0A-929F6BCFA749`를 사용했다. 첫 native 후보 UUID는 `E80CCCEE-F781-31B2-9185-CA7F4A10ABB2`다. 사용자 앱 출고나 실제 A/B 청감 완료를 뜻하지 않는다.

## 확인한 편집과 보존

이름을 지정한 복제는 원본과 다른 곡의 편곡을 유지하면서 새 arrangement/use ID를 만들었다. section 원본은 공유하며 사용처별 값과 서클 색을 복제한다. 긴 한글 이름으로 변경한 상태는 1020×768 화면에서 확인했다. rename은 이름만 바꾸며 이 metadata 변경 자체는 musicRevision을 올리지 않았다. 같은 이름 확정은 manifest 전체가 그대로였고, 다음 Undo는 실제 이름 변경을 되돌렸다. rename과 clone의 Undo/Redo는 musicRevision 및 복원된 hierarchyView를 제외한 전체 문서 비교로 확인했다.

취소 전후는 hierarchyView.camera의 부동소수점 차이(최대 약 5.9e-12)만 있었다. checker는 카메라 숫자에 1e-10 한도를 적용하고 다른 모든 필드를 그대로 비교한다. 외부 편곡 이름 변경 뒤 오래된 편집창 제출은 `external-renamed`와 `stale-rejected` 전체 manifest 일치로 거절을 확인했다.

자동화는 기존 점 변경이 아니라 복제본 mixer에 gain curve를 새로 추가한 검사다. `isolation-before`에는 source/clone 모두 automation이 없고, `isolation-after`의 clone에 beat0=.4, beat64=.9인 lane이 있다. source의 use/graph/lanes는 동일하고 clone의 해당 node automation 및 use.graphEdits만 변경됐다. 원본 sections도 유지됐다.

초기 `agent-cloned`의 다른 곡 대상 MCP clone은 그 곡의 선택 편곡을 자동 변경했다. 그때 사용자가 보던 activeArrangementID와 canvas selection은 유지됐지만, 이 자동 선택은 이후 폐기한 계약이다. `same-owner-before/cloned`에서 같은 곡 대상 clone이 activeArrangementID와 재생 선택을 바꾸고 music selection을 composition으로 축소하는 결함을 실제 재현했다. 이전 before의 playback.editorAddress도 null이므로 이 과거 JSON만으로 editorAddress nonnull→null을 주장하지 않는다. 이 캡처들은 최종 기능 통과 증거가 아니라 회귀 재현 증거로 검사한다.

최종 후보 `background/package.json`의 UUID는 `4CFB513F-26F5-3FCB-AC28-A6E18054A112`다. 같은 곡·다른 곡의 MCP clone은 새 대안과 색 복제만 추가하며 두 곡의 selectedArrangementID, 사용자 activeArrangementID, music selection, nonnull playback.editorAddress를 유지한다. `background-before/same/other`는 새 arrangement/use ID·색 주소·revision 외 전체 manifest 보존까지 검사했다. `background-preserved.png/ax.txt`는 두 번 복제 후 MIDI 편집기가 유지된 화면 증거다. UI의 이름 정해 복제는 계속 새 복제본을 선택하는 별도 계약이다.

재생 편곡 전환은 명시적 `select_arrangement`로 수행한다. `background-select-other/same/current`는 다른 곡, 첫 곡, 첫 곡의 MIDI 편집 중 다른 기존 편곡으로 전환할 때 선택한 owner의 selectedArrangementID와 activeArrangementID가 일치하고 composition으로 이동함을 확인한다. 다섯 번 Undo 후 음악 문서가 복원됐고, 실제 MCP open 완료 후 `background-restored/reopened` 전체 manifest가 일치했다. circleColors는 Codable dictionary 배열 쌍을 의미적으로 정렬하며 주소 중복은 거절한다.

`python3 qa/check-arrangement-workspace-evidence.py`는 캡처 34개와 isolation 두 상태를 읽고 결과만 출력한다. 기존 증거 파일을 덮어쓰지 않는다. 원본 studio manifest SHA256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 일치한다.

최종 fixture와 원본 studio 양쪽의 authored asset 2개는 실제 파일 SHA256을 manifest checksum과 대조해 일치를 확인했다. 최종 후보의 `keyboard-final.png/ax.txt`는 1020×768 상태와 조작 표시를 보존한다.

## 검증 범위와 남은 경계

선택한 Swift 28개와 MCP 21개가 통과했다. 첫 AgentTests 실행은 fixture 가정 오류로 3개 assertion이 실패했고, fixture 수정 후 최종 28개 실패0을 확인했다. 관련 로그는 `.build/arrangement-workspace-tests.log`, `arrangement-workspace-final-tests.log`, `arrangement-workspace-mcp-tests.log`다. 첫 release는 66.38초에 성공했다. 정적 security 검토는 통과 보고를 받았다. 전체 DAW 회귀나 전체 테스트 통과로 확장하지 않는다.

background 회귀 수정 후 최종 선택 Swift 30개와 MCP 21개가 통과했고 release는 68.50초에 성공했다. 이전 28개 통과는 background 결함을 발견하기 전 범위이며 최종 통과와 구분한다. 최종 후보는 clone의 암묵적 재생 선택을 제거하고 명시적 select_arrangement와 UI focus 이동을 함께 검증했다.

CUA typeText로 한글 입력을 시도했을 때 공백만 들어갔고, Unicode setValue와 Return으로 이름 확정은 동작했다. 따라서 직접 IME 조합 검증으로 계산하지 않는다. 현재 macOS 설정에서 Tab이 SwiftUI 버튼에 포커스를 주지 않는 것을 확인해 picker 전용 ⇧⌘N 이름 변경 / ⇧⌘D 이름 정해 복제를 추가했다.

후속 build83 후보는 `keyboard/package.json`, UUID `32A66A38-2CEF-32D4-A168-FAB4BDD51754`, release 39.76초다. 검색 UI 준비를 확인한 뒤 ⇧⌘N → typeText ASCII `Keyboard rename` → Return, ⇧⌘D → typeText `Keyboard alternative` → Return이 실제 이름 변경과 새 편곡 생성으로 이어졌다. Esc와 ⌘Z 두 번으로 복원한 문서는 musicRevision만 제외하면 카메라를 포함해 baseline 전체와 일치한다. `keyboard-rename.ax.txt`, `keyboard-clone.ax.txt`는 입력창과 Return 안내를, `keyboard-list.png/ax.txt`는 새 결과와 단축키 표시를 보존한다. UI 준비 전에 shortcut을 묶어서 보낸 첫 호출은 no-op이었고 준비 확인 후 개별 호출은 동작했다. 이 검사는 picker 안에서 이름 변경·복제·복원하는 keyboard 경로를 확인하며 전체 앱 keyboard 접근성이나 한글 IME 조합까지 확대하지 않는다. 최종 후보의 MCP open job completed 후 저장한 `keyboard-reopened`는 `keyboard-restored`와 circleColors 배열 쌍의 순서만 정규화한 전체 manifest가 일치한다.

모든 캡처에서 output/audition attempts는 0이고 재생·마이크·MIDI 입력을 시작하지 않았다. 출력 장치 정상 재생, 두 편곡의 실제 청감 비교, 전체 DAW 제작 완료는 이번 검증 범위 밖이다.
