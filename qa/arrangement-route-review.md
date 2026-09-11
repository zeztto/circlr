# 편곡안 재생 경로 요약 — build84

2026-09-10. 별도 `arrangement-route.circlr`와 QA 앱 UUID `5DD60BB7-2B17-3708-8485-D9E2B748FBA9`로 검증했다. Core 401개 실패0, release 68.85초 성공 보고를 받았다. 실제 출력이나 청감 비교를 실행한 검증은 아니다.

같은 이름의 두 편곡을 목록에서 경로 순서와 반복 횟수로 구분했다. 첫 안은 도입 → 주제 → 마무리, 총 3회이며 두 번째는 마무리 → 도입 ×2 → 주제 ×3, 총 6회다. 두 안 모두 경로 밖 보관 use 1개가 별도로 표시된다. 연결이 둘인데 선택하지 않은 안은 재생 경로 확인과 다음 연결 선택 안내를 표시하고, 빈 안은 섹션 추가 안내를 표시한다. `list-full.ax.txt`가 네 행의 전체 내용을 보존한다.

목록에서 아래 방향키와 Return으로 #2를 선택하고 긴 한글 이름을 적용했다. 이름 변경은 선택된 편곡 이름만 바꾸며 metadata 변경 전후 다른 필드는 유지된다. `long-name.png/ax.txt`와 `reordered.png/ax.txt`를 1020×768 native 화면에서 확인했다. 긴 이름의 전체 문자열은 AX로 확인하며 화면에 모든 글자가 동시에 보인다는 뜻은 아니다.

경로 밖 use가 남은 상태의 첫 reorder는 기존 편집 제약으로 거절됐다. `renamed`와 `reorder-rejected`의 전체 manifest 일치로 실패의 원자성을 확인했다. 이후 MCP 한 batch에서 마지막 use와 보관 use를 연결하고 주제를 마무리 앞으로 이동하며 도입 repeat를 4로 바꿨다. 결과는 주제 ×3 → 마무리 → 도입 ×4 → 경로 밖 보관, 재생 4개 섹션·총 9회·경로 제외 0개다. 변경은 #2의 경로 필드와 도입 repeat, 주제 isEnd에 한정됐고 원본 sections·다른 편곡·음표·asset은 유지됐다.

UI로 #1과 #2를 각각 다시 선택한 뒤 Undo 다섯 번으로 두 번의 선택, route batch, rename, 최초 선택을 되돌렸다. 각 단계는 대응하는 이전 문서와 musicRevision/hierarchyView만 제외한 전체 비교를 통과했다. 실제 open job 완료 후 저장한 `restored/reopened`는 전체 manifest가 의미적으로 일치한다. circleColors가 있으면 Codable dictionary 배열 쌍의 순서만 정규화한다.

재열기 뒤 ⇧⌘D로 복제 입력창을 열어 Esc로 취소하고 #4 검색으로 빈 편곡 안내를 확인한 뒤 종료했다. `clone-form.ax.txt`, `empty.png/ax.txt`를 보존했고 `reopened/cancelled` 전체 manifest가 그대로여서 취소·검색이 음악이나 저장된 뷰를 바꾸지 않았음을 확인했다.

`python3 qa/check-arrangement-route-evidence.py`는 15개 native 캡처를 읽고 결과만 출력한다. authored asset 2개는 원본 studio와 최종 fixture의 실제 파일 SHA256이 manifest checksum과 같고, 원본 studio manifest SHA256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`로 유지됐다. 모든 캡처의 output/audition attempts는 0이며 마이크·MIDI 입력·재생을 시작하지 않았다. 전체 DAW 완료, 실제 A/B 청감, 물리 출력 정상 동작으로 확장하지 않는다.
