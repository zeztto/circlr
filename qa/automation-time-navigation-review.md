# build 48 오토메이션 시간 탐색 검증

## 변경과 결과

`codex/daw-integration`, baseline `af1b33f`. 전체 점 보기로 원래 서클보다 긴 범위를 표시할 때 마디 눈금도 끝까지 이어진다. `MusicClock.barContinuationBeat`는 마지막 부분 마디를 자르기 전 경계를 보관하는 표시용 metadata다. 기존 beat/seconds·DSP·반복 계산과 프로젝트 schema는 바꾸지 않는다. `AutomationRuler`는 마지막 박자를 연장하며 표시 밀도에 맞는 희소 눈금만 생성한다. 같은 캔버스의 선형 곡선과 궤도 모두 실제 글자 영역을 확인한다.

이전/다음과 Home/End는 선택한 점까지 범위를 펼친다. 현재 점 번호, 로컬 마디/박/초를 표시하고, 숫자로 화면 밖으로 이동한 점은 ‘선택 점 보기’로 돌아간다. 표시 범위는 음악 편집·Undo·배치 전환에도 유지하며 기존 ‘서클 길이 보기’로 초기화한다. 현재 점의 AX 선택은 대상·세션·revision·범위·clock·배치가 일치할 때만 수행한다.

## 빌드와 자동 검사

- **Swift 374개 통과**, 실패 0, **25.131초**: `.build/automation-time-navigation-tests-clean.log`, scratch `.build/automation-time-quality`. 새 Core 테스트 5개는 전체/부분 마디, 7/8 변박, 상속 중간 시작, tempo map, 최대 1,048,576박의 희소 눈금, 비유한 입력, 범위 확장·고정을 검사한다. 실제 출력 의존 `testArrangementRenderExportAndPlayback`는 기존 HAL 문제 때문에 제외했다.
- **Python 26개 통과**, 0.217초: `.build/automation-time-navigation-python.log`.
- 최종 release **25.15초**: `.build/automation-time-navigation-release-ruler.log`. 마지막 변경은 `AutomationEditor.swift`의 라벨 경계와 tooltip 갱신 조건이며 최종 native에서 다시 확인했다. Core는 전체 검사의 소스와 같다.
- 최종 앱: `qa/generated/automation-time-navigation/ruler/써클러 통합 검증.app`, `com.circlr.integrationqa`, **0.20.0 build 48**, UUID `23E8EED2-E5ED-3B9A-A84B-FBA1A96C192F`.
- `python3 qa/check-automation-time-navigation-evidence.py`: **passed**. Snapshot **17개**, JPEG **6개**, 소스 **5개**, kit **25개**, 실행 섹션 **37개**, strict codesign과 원본/사본 asset SHA를 검사한다. 결과는 `qa/generated/automation-time-navigation/ruler/verification.json`이다.

최초 `.build/connection-workspace-quality` 증분 검사는 `AudioRouterAudioTests.testFanOutKeepsSidechainAndOtherOutputAliveUntilLastConsumer`의 `render`에서 `objc_retain`/SIGSEGV로 종료됐다. `.build/automation-time-navigation-tests.log`와 `~/Library/Logs/DiagnosticReports/xctest-2026-09-09-115034.ips`에 근거가 있다. Core 구조 변경 후 CirclrAudio는 재컴파일됐지만 CirclrAudioTests 컴파일은 해당 로그에 없었다. **동일 소스를 새 scratch에서 전부 빌드한 뒤 374개가 통과**했다. 오래된 ABI 산출물이 섞였을 가능성이 있으나 원인이 입증된 것으로 단정하지 않는다. 이 실패를 숨기거나 테스트를 추가 제외하지 않았고 후속 테스트는 새 scratch를 사용한다.

## 실제 앱 시나리오

전용 authored 사본 `~/Library/Application Support/circlr-integration-qa/fixtures/automation-time-navigation.circlr`, ID `C2CC080C-039A-5FC0-955C-8016666AA633`. 원래 3트랙·2 tone asset은 유지했다. 첫 사용의 키보드 mix에 gain 점 0/16/96/128박, 값 0.5/1/0.75/0.25를 추가했다(r14→15). 기본 범위는 64박이며 1024×673 캔버스와 콘솔 열림 상태에서 검사했다.

| 경로 | 실제 관찰 |
| --- | --- |
| 기본·Home | 1·3·5…15마디 눈금과 0/4 상태다. Home은 첫 점을 선택해 1/4·1마디·0초를 표시한다. r15·64박 범위 유지. |
| 다음 점 | 16박 선택은 범위를 유지하고, 다음 96박 선택은 범위를 96까지 펼친다. 25마디·1박·48초와 1/5/9/13/17/21 눈금을 확인했다(`outside`). |
| 수치·직접 보기 | 같은 점을 192박으로 입력하면 순서가 4/4로 바뀌고 49마디·96초다(r16). 범위는 96으로 유지하고 ‘선택 점 보기’가 나타난다. 버튼은 192박까지 펼치며 추가 음악 편집을 만들지 않는다. |
| 한 Undo·범위 고정 | 실제 ⌘Z 한 번은 점을 96박으로 복원한다(r17). 범위는 192박으로 유지하고 Home으로 첫 점을 선택해도 줄어들지 않는다. |
| 배치 전환 | 자유→궤도에서 128박 점·192박 범위를 유지한다. 서클 길이 보기로 64박에 돌아가면 선택 점 보기 버튼이 나타나고, End는 128박까지 펼친다. |
| 궤도 키보드 편집 | Left는 마지막 점을 127.75박·32마디 4.75박·63.88초로 이동한다(r18). ⌘Z 한 번은 128박으로 복원한다(r19). 표시 범위 128 유지. |
| 최종 눈금·AX | 작은 궤도의 아래 17마디까지 1/5/9/13/17/21/25/29가 모두 보인다(`ruler-orbit`). 현재 AX의 3번 점 선택은 96박을 선택하고 자유 배치 복귀 시도 선택·128박 범위를 유지한다(`ruler-linear`). |
| 다른 사용·원본 | 다른 섹션 사용은 64박·0/0·빈 곡선이고 이전/다음이 비활성이다. End로 음악이 바뀌지 않는다. 공유 원본이 없는 추가 mix는 점 추가 비활성·복귀 안내를 표시한다. 원본 토글을 끄면 이번 사용으로 복귀한다. |
| 복원·재열기 | 첫 사용의 검사용 automation을 제거하고 자유 배치로 복원했다(r20). `restored`/`reopened`의 음악·신호·악기·자산·배치는 r14 기준 사본과 같다(portLayout revision 제외). 두 tone asset과 원본 manifest checksum을 유지했다. |

최초 후보 UUID `09768FFA-CD71-3ABC-9DEC-7D275A4DBE86`, 중간 `final` 후보 UUID `CF1A0567-A19D-364D-B286-00E7D705950B`도 보존한다. 최초 화면의 첫 마디 라벨 누락과 SwiftUI help/label의 AX 정보 덮어쓰기를 수정했다. 중간 후보의 궤도 아래 숫자는 경계에서 약 1px 넘어가 표시되지 않아 반경을 2px 안쪽으로 옮겼다. 최종 소스 hash 차이는 `AutomationEditor.swift`뿐이며 두 배치에서 재확인했다.

## 검토와 제한

native Swift utility → 읽기 전용 code review → QA → development-lead를 순차 수행했다. 실제 root 포함 1슬롯과 직전 서브 에이전트 생성 거절을 존중했으며 독립 에이전트 리뷰로 주장하지 않는다.

새 네트워크·인증·외부 실행 경로가 없다. 표시 metadata와 viewport는 프로젝트에 저장하지 않는다. 최대 범위의 눈금은 수백만 마디 배열을 만들지 않으며 capacity를 제한한다. 위치 표시의 마디 안 박은 meter 분모 단위이고 기존 입력은 4분음표 박을 유지한다. 실제 바깥 구간의 재생 범위를 늘린 것으로 해석하지 않는다.

부분 마디·변박·tempo map·최대 범위의 수학적 검사는 Core 근거이며 모든 조합을 native로 조작한 것은 아니다. 실제 VoiceOver 발화, 보조 도구가 보관한 오래된 AX 객체 호출, 임의로 밀집된 모든 tempo map/라벨 조합은 미검증이다. 현재 AX 선택은 실제 확인했고 오래된 객체의 거절은 소스 검토로 구분한다.

모든 snapshot의 output/audition attempts는 0이다. 실제 출력/HAL, 마이크·MIDI 입력, MP4 출고 회귀는 별도다. 사용자 앱 0.19.0 build 21과 root `d88ea5d`·ports `1d304eb`를 보존했고 세 QA 앱을 정상 종료했다. 소스·문서·테스트·QA helper만 승인된 private branch에 반영한다.
