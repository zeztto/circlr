# 스텝 편집의 대상 유지와 공유 리듬 탐색

상태: build121 baseline 결함 재현 후 build122 소스·Core navigation·Release 패키징·아래 native 탐색 시나리오를 검증했다. 저장 데이터의 독립 종합 감사도 통과했다. 노트 편집/Undo·전체 한 곡 작업 흐름·물리 오디오를 통과한 것으로 판단하지 않는다.

## 문제

공유 리듬 MIDI 서클에서 ⌘4로 스텝 편집을 열면 현재 서클 대신 같은 트랙의 일반 MIDI 서클로 이동했다. 사용자는 표시 방식을 바꾸려 했지만 편집 대상이 달라져 이후 노트를 잘못된 원본에 입력할 수 있었다. 기존 openStepEditor는 `.midi`만 현재 대상으로 보존했고 StudioNavigation의 트랙 후보에서는 `.rhythmMIDI`·`.rhythmAudio`를 제외했다.

`qa/generated/step-target/baseline121`의 before/wrong-target JSON은 build121·음악revision18을 유지하면서 선택 nodeID가 `rhythm-midi:…`에서 `midi:…`로 바뀐 것을 기록한다. before/wrong-target AX·JPEG도 함께 보존한다. 이 단계는 잘못된 탐색을 재현한 것이며 음악 손상이나 실제 노트 입력까지 재현한 것은 아니다. 두 snapshot의 output/audition attempts는0이다.

## 수정 계약

- 현재 선택이 일반 MIDI 또는 공유 리듬 MIDI이면 같은 주소에서 스텝 편집을 연다. 이름 편집 확정에 실패하면 이동하지 않는다. 연결·설정·오토메이션·plugin·전환 편집 상태를 정리하여 선택한 MIDI 작업을 표시한다.
- 다른 종류의 서클에서 열면 기존 트랙 역할 탐색을 사용한다. MIDI 후보가 여러 개일 때 첫 번째를 임의 선택하지 않고 picker로 선택한다. ⌘4 메뉴의 활성 조건도 같은 canOpenStepEditor를 사용한다.
- 공유 리듬 MIDI/오디오는 일반 MIDI/오디오 역할 후보에 포함하되 이름에 공유 리듬을 표시한다. 소유 트랙은 node의 trackID로 고정하고 다른 출력으로 연결했다고 다른 트랙의 소스로 옮기지 않는다. 출력 연결 여부는 별도로 계산한다.
- 탐색 후보와 scene의 표시 조건을 맞춘다. 상속 또는 node local 설정으로 해석한 patternID와 소유 trackID가 일치해야 한다. 할당된 빈 MIDI 패턴은 편집 가능하며 오디오 후보는 클립이 있을 때만 표시한다. 미할당 패턴은 숨긴다.
- 접힌 그룹은 기존 탐색 reveal을 사용하며 탐색만으로 패턴·음악 내용을 수정하지 않는다. GUI 선택·검색·역할 탐색이 같은 Core 목적지를 사용한다.

수정 소스: [StepEditor](../Sources/CirclrApp/StepEditor.swift), [메뉴](../Sources/CirclrApp/CirclrApp.swift), [StudioNavigation](../Sources/CirclrCore/StudioNavigation.swift). 원본·변형·공유 패턴의 음악 편집 의미는 이 탐색 수정으로 바꾸지 않는다.

## 검증 결과와 범위

Core navigation 관련16개 테스트가 실패0·0.036초로 통과했다 (`.build/build122-navigation-tests.log`). 신규 [StudioNavigationRhythmTests](../Tests/CirclrCoreTests/StudioNavigationRhythmTests.swift)는 공유 소스의 미디어 역할·다른 출력 연결 후 owner 유지·그룹 reveal·프로젝트 불변·미할당/빈 패턴·node local override를 검사한다. read-only source review도 통과했으며 이 검토는 native 조작 성공과 구분한다.

최종 Release는74.64초에 성공했다 (`.build/build122-release.log`). main UUID는 `C892EA7F-76D4-3A2E-B5CC-B193ADE10064`이며 QA/production 식별과 서명 검증을 통과했다. QA helper는 물리 입출력을 차단한다.

`qa/generated/step-target/final122`에서 다음 native 동작을 확인했다.

1. 공유 리듬 MIDI에서 ⌘4 후 같은 주소·스텝 표시 유지. ⌘2로 음색에 이동한 뒤 ⌘4를 누르면 일반 MIDI와 공유 리듬의2개 후보를 구분하여 표시했다. Down/Return으로 공유 리듬에 복귀했다.
2. 일반 MIDI 후보를 Return으로 선택하고 다시 ⌘4를 눌러도 일반 MIDI 대상을 유지했다. 후보 창에서 Escape로 취소하면 기존 악기 선택을 유지했다.
3. 설정의 이름을 빈 초안으로 만든 뒤 ⌘4를 누르면 오류가 표시되고 이동을 차단했다. Escape로 이름 초안을 취소한 뒤 ⌘4로 스텝 편집을 열었다.
4. route bar의 MIDI2 후보에서 마우스로 공유 리듬을 선택해 복귀했다. 저장/정확한 프로젝트 재열기 후 공유 리듬 대상·음악revision18을 확인했다.

저장 JSON6개(before/shared-return/ordinary-kept/chooser-cancelled/restored/reopened), JPEG9장·AX9개를 확보했다. shared-kept·chooser·invalid-name·settings-to-step·routebar-return은 화면/AX 관측이며 각각의 독립 JSON snapshot이 있다고 표현하지 않는다. 독립 종합 감사에서 JSON6개의 음악revision18·seed 음악 불변·자산2개 checksum, 시나리오별 정확한 node 선택, restored/reopened/disk manifest의 전체 일치를 확인했다. QA hash·서명·helper5종 차단도 통과했다.

캡처의 output/audition attempts는0이며 실제 리듬 소리·연주 지연·녹음은 검사하지 않았다. QA 앱을 종료하고 사용자 원본PID86114만 유지했다. 사용자 앱을 교체하지 않았다. 이번 범위는 탐색이므로 노트 편집·Undo를 실행하지 않았으며, 대상별 실제 음악 변경과 Undo/재열기는 남은 통합 제작 검증 조건이다.

별도 `creation-flow121`의 빈 섹션 생성 탐색은 화면 증거만 남은 사전 탐색이며 위 final122 저장 검증에 포함하지 않는다. 저장되지 않은 QA 작업을 정리할 때 소유PID66635를 SIGTERM으로 종료했고, 재실행의 복구 대화상자에서 새로 시작을 선택했다. 이를 저장 복구 성공으로 계산하지 않는다.

## 다음 작업

이 대상 유지 수정 이후 [현행 개발 계획](138-current-development-plan.md)의 한 곡 연속 작업을 이어간다. 드럼/신스 입력에서 음색·오디오 가져오기·이펙트/연결·오토메이션·편곡·바운스·재열기까지 실제로 진행하면서 다음 작업을 방해하는 문제를 찾는다. 개별 단축키 수정으로 통합 제작 흐름 전체를 완료 처리하지 않는다.
