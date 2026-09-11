# 출력 서클의 레벨과 편집 범위

2026-09-09, 기준 `09b183c`, `codex/daw-integration`. development-lead → UI/UX → native Swift utility → read-only code/security review → QA. 직전 실제 spawn 한도에 따라 순차 역할 전환이며 독립 리뷰로 보고하지 않는다.

## 문제와 사용자 흐름

출력과 악기가 같은 TrackInspector를 사용해 오디오 출력에 신스 설정이 나타난다. 출력에서 보이는 볼륨/음소거는 실제로 Track 전체를 바꾼다. 개별 출력 MusicCircle의 gain/muted는 주 편집기에서 보이지 않아 설정 깊이와 범위 혼동이 생긴다.

출력 전용 화면은 `서클 레벨`과 `트랙 전체 레벨`를 바로 구분한다. 각 행에 dB 숫자·fader·음소거·0 dB 복원을 제공한다. −∞ 입력은 gain=0이며 저장된 값은 계속 선형 gain이다. 입력과 슬라이더는 한 조작당 한 Undo, 대상/값/revision 충돌 거절, Return/Esc/Tab 계약을 따른다. 원본을 건드리지 않고 화면만 읽을 때 gain 정밀도를 보존한다.

서클별 레벨은 이번 사용을 기본으로 한다. `공유 원본 편집`을 직접 전환할 수 있으며 원본에서는 gain/muted만 수정한다. 사용 override의 다른 필드나 topology를 원본에 복사하지 않는다. 원본을 덮는 개별 설정이 있으면 화면에 표시한다. Track 전체는 같은 트랙의 모든 섹션에 적용된다. 악기와 전역 트랙 출력의 화면도 음색/레벨 역할을 구분한다.

볼륨/팬 오토메이션과 track bounce로 바로 이동한다. 바운스는 기존 출력 레벨과 자동화를 보존하는 계약을 유지한다. 정밀 편집은 같은 캔버스에 남으며 별도 창/측면 패널을 추가하지 않는다. 새로운 solo/pan 데이터나 실시간 렌더 기능을 가장하지 않는다.

## 소유와 검증

- Core: 새 GainScale.swift, LevelEditing.swift, NumberEditSession.swift의 선택적 표시 형식과 테스트. MusicCircle/Track의 기존 gain/muted만 사용하며 프로젝트 schema·DSP는 변경하지 않는다.
- App: 새 GainControls.swift, OutputEditor.swift; CommittedNumberField.swift, InlineCircleEditor.swift, InspectorView.swift. 숫자 포커스와 slider tracking의 단일 적용/충돌 검사를 공유한다.
- QA: dB↔선형·−∞·precision·invalid/stale, 원본/사용 범위와 atomic 실패, 두 섹션의 출력/트랙 레벨 PCM·바운스 회귀. 전체 offline Swift/Python, release, 새 build 33 앱과 authored fixture의 최소 창 UI·keyboard/slider·Mute·Undo·저장 복원, 숫자 입력 중 외부 변경을 검사한다.
- Git: 같은 private 개발 branch에 검증 source checkpoint. 기존 사용 앱/프로젝트·검증 앱과 raw media는 보존한다. 실제 출력 장치 지연과 마이크·VoiceOver·MP4는 각각 별도 native 증거로 판정한다.

## 실행 결과와 다음 범위

build 33 최종 후보에서 Swift 303개·Python 26개, release, 두 사용의 PCM과 실제 fader/숫자/범위 전환/오류 거절/Undo/저장 복원을 확인했다. native 중간 preview의 드래그 복귀와 무변경 클릭의 부동소수 오차는 수정했다. 최종 앱 UUID는 `F119E664-A045-380F-BE1D-FDA30F90809D`이며 [검증 기록](../qa/output-editing-review.md)에 범위를 구분했다.

다음 UI 범위는 오토메이션의 값/시간 표시와 전체 신호/전환 편집기의 공통 숫자 계약이다. track pan/solo는 전역 bus·send와 mute/solo 상호작용, bounce/export 시 결과를 Core/PCM 계약으로 먼저 고정한다. 출력 장치 정상 재생·취소·재시작과 마이크 acceptance를 유지하며 사용자 앱 교체와 구분한다.
