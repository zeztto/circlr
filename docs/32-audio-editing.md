# 오디오 분할·복제·페이드

0.18은 오디오 서클의 원본 파일을 보존하면서 구간을 나누고 복제하고 페이드를 적용한다. 가져온 오디오와 바운스한 오디오가 같은 편집 명령을 사용한다. 정밀 편집은 기존 캔버스 안에서 이루어진다.

## 조작

1. 오디오 서클을 확대하거나 작업 이동(⌘J)에서 오디오를 연다. 왼쪽 파형과 오른쪽 편집 필드가 같은 영역에 나타난다. 자유 배치에서는 파형이 가로로 표시된다.
2. 파형을 클릭해 분할 위치를 고르거나 **분할 위치 초**를 입력한다. 값은 선택 구간 시작부터의 **원본 파일 초**다. 템포 추종을 켜면 재생 초와 다를 수 있다.
3. **분할 / ⌘T**는 앞·뒤 두 서클을 만든다. 뒤쪽 서클을 자동 선택한다. 분할만으로 소리가 바뀌지 않도록 기존 페이드와 변환 기준을 보존한다.
4. **복제 / ⌘D**는 새 ID의 서클을 만든다. 자동 길이 서클은 마지막 반복의 실제 끝에, 개별 반복 길이가 있는 서클은 마지막 반복 뒤에 배치한다. 섹션 밖에서 시작하는 복제는 거부하므로 먼저 섹션 길이를 늘린다. 끝부분은 기존 섹션 재생 경계에 따라 잘릴 수 있다.
5. **페이드 인 초 / 페이드 아웃 초**는 선택 구간 양 끝의 선형 gain을 조절한다. 두 길이의 합은 구간 길이를 넘을 수 없다. 파형에 감쇠 모양을 표시한다. 둘 다 0으로 지정하면 현재 구간에 추가한 페이드가 해제된다.
6. 시작 박·원본 시작·길이·볼륨·템포 추종·음소거·삭제를 직접 편집한다. 각 변경은 한 번의 ⌘Z로 복원하며 동일 값 적용은 Undo를 늘리지 않는다. 텍스트 입력 중 음악 단축키는 개입하지 않는다.

작은 창에서 콘솔을 펼치면 아래쪽 템포·음소거 명령은 편집 영역의 세로 스크롤로 접근한다. Ctrl+`로 콘솔을 접으면 파형과 편집 영역이 커진다. 일반 휠은 캔버스 줌, ⇧휠은 편집 영역 이동이다.

## 데이터와 렌더 의미

`AudioEditing.apply`가 GUI/MCP의 공통 명령이다. 임시 프로젝트에서 lane·graph를 검증한 뒤 한 번에 반영한다. 선택한 use의 변형이 기본이며 GUI의 공유 원본 모드를 명시하면 원본을 편집한다. 같은 clip을 여러 node가 참조할 때 선택한 node의 clip을 분리한다.

`AudioClip.fadeIn/fadeOut`은 선택 구간에 추가하는 원본 초 단위 envelope다. 이전 파일의 nil은 기존 5 ms 자동 가장자리 처리와 바운스 tail 보존 동작을 유지한다. 새 optional 필드 때문에 기존 프로젝트를 강제로 다시 저장하지 않는다.

분할할 때 `AudioRenderWindow`에 기존 source 시작·길이·반복 기준·자동 가장자리·기존 envelope를 저장한다. `ClipAudioRenderer`는 그 범위에서 resample/time stretch를 수행한 뒤 선택 조각을 읽는다. 각 조각에서 변환기를 새 위치로 시작해 접합부를 바꾸지 않는다. 컷은 48 kHz 출력 sample 경계로 맞추며 양쪽 채널을 함께 처리한다. 재분할도 같은 window를 사용한다.

원래 envelope는 분할 뒤에도 source 위치에 고정된다. 이후 조각의 fade는 보존된 envelope에 곱해진다. 분할 이전 fade를 제거하려면 분할을 Undo한 뒤 수정한다. 분할 조각의 trim 확장은 기존 render window 안에서만 가능하다. 전체 원본으로 확장하거나 window를 해제하는 명령은 아직 없다.

자동 반복 주기는 분할 이전 source 길이를 유지한다. 명시적 반복 길이와 tempo map은 원래 반복 시작에서 조각의 재생 초 offset을 더한다. `AudioClipTiming`을 renderer와 궤도 표시가 공유한다. tempo follow는 기존 0.25–4배 범위이며, 변화하는 부모 tempo map을 추종하는 오디오는 개별 서클 tempo를 지정해야 분할할 수 있다.

분할·복제는 gain/mute/context/repeat과 일반 출력·sidechain 출력·edge gain·그룹 소속을 복사한다. 원본 asset 파일은 쓰지 않는다. 바운스 파생본은 `BounceSource.familyID`를 공유한다. 어느 조각에서 **원본 복원**을 하더라도 같은 바운스의 조각 전체를 mute·연결 해제해 보관하고 캡처된 원본 경로를 복원한다. 다른 작업으로 바뀐 출력 경로를 무조건 덮어쓰지 않는다.

## MCP 계약

`circlr_apply.operations`의 `edit_audio`는 실제 `useID`, 오디오 `nodeID`, 필요하면 `arrangementID`를 지정한다. `edit`는 다음 값이다.

| edit | 추가 인수 | 결과 |
|---|---|---|
| split | sourceOffset | 선택 시작부터의 원본 초에서 두 서클로 나눔 |
| duplicate | beatOffset 선택 | 생략하면 마지막 반복 뒤, 지정하면 로컬 4분음표 박 단위 이동 |
| fade | fadeIn, fadeOut | 원본 초, 0 이상, 합이 구간 길이 이내 |
| delete | 없음 | 해당 서클·연결 제거, 공유 asset 보존 |

모든 명령은 projectID·expectedRevision·atomic batch를 사용한다. 결과 ID를 추측하지 않고 이후 inspect에서 실제 그래프를 읽는다. `renderWindow`와 바운스 family는 내부 보존 메타데이터이며 MCP에서 직접 설정하지 않는다. 기존 `set_clip`도 source 범위와 envelope 유효성을 검사한다.

## 다음 개발

gain/pan automation의 stable target·점·curve·local clock/repeat·실제 render를 다음 편집 단계로 진행한다. 녹음 장치 시작의 비동기화와 실제 입력 검증도 별도로 남는다. 고급 time warp, crossfade, comping, destructive 처리와 연속 실시간 엔진을 이 버전에 포함했다고 보지 않는다. 각 조각이 같은 원본 window를 다시 처리하는 비용을 줄일 render cache도 후속 과제다. [기본 DAW 실행 계획](31-daw-basics-plan.md)과 [검증 기록](../qa/0.18-review.md)을 함께 참조한다.
