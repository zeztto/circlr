# 음악 설정을 현재 값에서 바로 편집

2026-09-09. 기준 `17778eb`, 목표 build 30. build 29는 검증·private push까지 progress다. 전체 개발 목표와 E 출고 gate는 유지한다.

## 계획 gate

Owner: development-lead → UI/UX → Core/Swift utility → 읽기 전용 코드·입력 검토 → QA. 현재 실제 agent 생성 한도 거절을 반복하지 않고 순차 역할 전환하며 독립 빌드/검사는 병렬 실행한다. 기존 `codex/daw-integration`에 source/docs/tests만 commit/push한다. 사용자 앱·원본 곡·라이선스 샘플은 보존한다.

현재 계층 음악 설정은 출처 선택→값 노출→편집→전체 적용으로 이어진다. 화면을 연 뒤 외부 편집이 있어도 오래된 설정 전체를 적용할 수 있다. 이번 목표는 현재 유효값을 항상 보여주고 템포·박자·스케일·박 분할/강세·리듬을 해당 항목 단위로 바로 변경하는 것이다.

## UX·데이터 계약

- 동일 캔버스·다크 화면·기존 숫자 필드를 사용한다. 각 음악 항목에 유효값과 `기본값 / 앨범 / 개별` 출처를 함께 표시한다. 상속 중에도 값을 직접 바꾸면 그 항목만 개별 설정이 된다. 기본값은 상위 서클/공유 섹션 원본의 현행 상속 규칙을 뜻하며 앨범 값과 혼동하지 않는다.
- 별도 전체 적용 버튼을 없앤다. 숫자는 기존 Return/Tab·Esc 계약, 선택 메뉴/정수 버튼은 한 번의 변경으로 적용한다. 사용자 지정 강세는 입력 문자열을 검증해 Return 또는 행의 확정 버튼으로 한 번 적용한다. 정수 1–64, 최대 64개 묶음을 허용하며 잘못된 문자열을 조용히 삭제하지 않는다.
- 출처만 전환할 때 보관된 개별값은 유지한다. 처음 개별로 전환할 때는 현재 유효값을 복사한다. 보기·포커스만으로 상속이나 정밀도를 바꾸지 않는다.
- tempo, meter의 각 성분, scale root/mode, beatGrid의 각 성분, rhythm을 현재 모델에서 부분 수정한다. stale 프로젝트/세션/선택/공유 편집 대상과 dirty 입력은 거절한다. 한 항목의 확정은 한 Undo이며 다른 항목을 덮어쓰지 않는다.
- 음악 서클의 공유 원본 편집 상태를 설정 위에 표시한다. 원본 편집은 원본 노드의 설정만 바꾸고 해당 사용의 다른 override를 원본에 복사하지 않는다. 현재 사용에만 추가한 노드는 공유 원본 편집 대상이 아니다.
- 섹션 길이/반복과 경로 작업은 기존 기능을 보존한다. 전역 signal, 레이아웃 그룹에는 동작하지 않는 음악 출처 컨트롤을 노출하지 않는다. legacy 사각 편집 창의 전체 설정 draft는 이번 화면 범위가 아니다.

## 구현 소유와 검증

Core: 새 `Sources/CirclrCore/MusicContextEditing.swift`와 테스트. 계층 주소에 따른 현재 context/settings 조회, 부분 변경, 공유 원본 보존, 잘못된 입력의 원자적 거절과 저장 호환성을 검증한다. 현행 inheritance/compiler/schema를 재사용한다.

Swift app: 새 `Sources/CirclrApp/MusicContextEditor.swift`, `InlineCircleEditor.swift`, `AlbumWorkspace.swift`. 공통 build 29 숫자 필드를 소비하며 현재 모델의 작은 명령만 전달한다. 새 패널은 만들지 않는다. `Resources/Info.plist` build 30, README/CHANGELOG/roadmap을 갱신한다.

QA: Swift 전체 `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, Python 26개, release `.build/integration-release`. 새 authored QA 사본과 build 30 앱에서 기본값 표시→직접 local 전환→앨범/기본값 복귀, 박자·스케일·리듬 성분 보존, 강세 오류·확정·취소/외부 충돌, 개별 Undo·재열기, 최소 창·콘솔 상태를 검증한다. Core 공유 원본/숨은 사용/잘못된 대상 검증과 Native 실행 범위를 구분한다. 실제 마이크·재생·계정 상태는 변경하지 않는다.

## 실행 결과

build 30 소스·최종 QA 앱을 구현했다. Swift 272개·Python 26개와 release를 통과하고 실제 최소 창의 직접 입력/출처 전환/강세 오류·충돌/리듬 연결/Undo·저장 복원을 확인했다. 강세의 중복 문자열 이벤트에서 생긴 잔여 draft 버튼을 수정했다. [QA 근거와 미검증 범위](../qa/context-editing-review.md). 생성 요청한 독립 리뷰 agent는 한도 오류로 실행되지 않았으며 동일 실행자가 리뷰 역할을 수행했다. 전체 목표와 사용자 앱 출고 gate는 유지한다.
