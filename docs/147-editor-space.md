# 작은 편집 공간의 오디오 수치와 스텝 행

상태: 첫 후보의 스텝 표시 부족을 보완한 compact build128에서 아래 Release·native 결과를 확인했다. 최종 재열기·production 서명/UUID·독립 13개 compact capture 감사도 통과했다. 초기 후보와 최종 후보의 근거를 구분한다.

## 사용자 문제와 기준

작은 편집 공간에서 오디오의 중요한 수치를 보려면 스크롤해야 하고, MIDI의 도구·속성 배치가 스텝 행의 높이를 많이 차지한다. 같은 캔버스 안에서 파형/스텝과 필요한 편집값을 함께 보게 만드는 것이 목표다. 별도 고정 패널이나 새 창을 추가하는 방식으로 해결하지 않는다.

독립 프로젝트 `84081CB3-F73E-4707-90E4-D9496B6083BE`·musicRevision62·직접 작성한 자산4개를 사용했다. `qa/generated/editor-space/baseline-audio` JPEG/AX에서는 오디오 수치가0개 보였고 baseline-step에서는 완전한 스텝4개 행과 일부만 보이는5번째 행을 확인했다. 이 수치는 실제 관측 조건의 표시 개수이며 모든 창 크기를 뜻하지 않는다.

## 초기 후보와 보완 방향

첫 build128 Release는42.83초에 성공했고 UUID는 `677BE425-63CB-3962-954F-B3286A6D61D5`다. 실제 오디오 핵심 수치 4개는 보였으나 스텝에서는2개 행만 보여 baseline의4개 완전한 행과 일부5번째 행보다 줄었다. 빌드 성공·오디오 개선만으로 후보 전체를 승인하지 않는다.

compact 보완에서는 스텝의 공통 작업 도구·행/음역·분할·페이지 조작을 함께 배치하고 간격을 줄인다. 약44px 절감은 초기 배치 계산상 추정이었다. 최종 실제 행 수는 아래 결과로 별도 확인했다. 선택 속성은 해당 편집 영역 안에 유지한다. 수치를 숨기거나 음악 데이터·선택 의미를 바꾸어 높이를 확보하지 않는다.

수정 대상은 [AudioWorkspace](../Sources/CirclrApp/AudioWorkspace.swift), [MIDIGridWorkspace](../Sources/CirclrApp/MIDIGridWorkspace.swift), [MIDIWorkspaceToolbar](../Sources/CirclrApp/MIDIWorkspaceToolbar.swift), [StepEditor](../Sources/CirclrApp/StepEditor.swift)다. 동일 기능·키보드 포커스·음역·페이지·현재 선택을 보존해야 한다.

## 최종 검증 조건

- 같은 화면 조건에서 오디오 primary 수치의 실제 가시성과 입력/Undo, 파형 작업을 확인한다.
- 스텝은 baseline의 완전한4개 행과 일부5번째 행보다 줄어드는 문제를 해결하고 실제 표시 행 수·선택 속성·드럼/음정·페이지/음역 조작을 대조한다. 계산상 높이 절감만으로 판정하지 않는다.
- 같은 캔버스의 Tab·수치 확정/취소·스크롤/휠·선택 유지와 음악·자산 보존을 확인한다. 수행하지 않은 폭·모드·도구 조합은 별도 제한으로 남긴다.
- 저장/재열기·Release·서명/UUID·실제 AX/화면·독립 데이터 감사를 각각 기록하고 첫 후보와 최종 후보의 근거를 분리한다.
- 물리 입출력은 차단한 QA 범위를 유지하며 가시성 결과를 실제 소리·전체 제작 기능 완료로 해석하지 않는다.

다음 표현 편집은 [내장 신스 cutoff automation 계획](148-synth-cutoff-automation-plan.md)에 구체화했다. 이 계획은 구현 결과가 아니며 현재 화면 개선을 대신하는 완료 근거도 아니다. [현행 개발 계획](138-current-development-plan.md)의 전체 한 곡·오디오·아티스트 목표를 유지한다.

## compact build128 현재 결과

최종 Release는44.07초에 성공했고 UUID는 `EF6EE641-F36E-363D-8057-E3DA1FF690C1`이다. 같은 1024×768 창·122pt 콘솔에서 스텝 toolbar가 1행이며 완전한 6개 음정 행이 보였다. 드럼 검색은 추가 도구 때문에 2개 toolbar 행을 유지하며 검색어 66·Return 후 해당 grid 1행을 확인했다. 기본 음정 화면과 드럼 도구 화면을 같은 행 수라고 표현하지 않는다.

스텝 페이지를 3/16으로 수치 이동해도 음악은 변하지 않았다. MIDI 입력의 잘못된 abc는 모드 변경 시 64로 복원되고 음악 r62를 유지했다. 유효 velocity 88 적용 r63·Undo r64, Return으로 pitch 66·step 2 편집 r65·Undo r66을 확인했다.

오디오는 핵심 수치 4개가 처음부터 보였다. 잘못된 oops·Return은 r66에서 거절됐고 Escape로 취소했다. trim 0.25 적용 r67·Undo r68, Shift-Tab의 마지막 BPM 가시성, scrollbar 클릭 후 분할 동작 r69·Undo r70을 확인했다. r70을 저장하고 최종 재열기에서 MIDI 주소·페이지 3/16·스텝 33–48 복귀를 실제 확인했다.

production strict 서명과 동일 UUID를 확인했다. 독립 13개 compact128 capture 감사는 의도한 trim·velocity·스텝 노트 1개 변경 외 음악 보존, saved=reopened=disk의 r70 정확한 일치, 자산 SHA·noIO를 확인하여 PASS했다. 초기 final128 레이아웃 capture 1개는 별도 실패 후보 근거이며 최종 13개에 포함하지 않는다. QA 앱은 종료했다. 실제 수행한 입력/편집/Undo와 다른 창 크기·모드 전체·물리 오디오의 미검증 범위를 구분한다.
