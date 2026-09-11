# 섹션 길이의 원본과 이번 사용 설정

상태: build137 기능과 4자리 숫자 가시성을 보완한 최종 wide 후보의 Release·native 검증을 완료했다. 최종 독립 artifact·native UI 감사도 모두 PASS했다.

## 실제 문제와 송폼 의미

build136 native의 `qa/generated/section-length137-before/section.jpg`와 AX 증거에서 섹션 설정은 마디 16만 표시했다. 이 값이 원본 섹션의 길이인지 이번 use의 override인지 구분하기 어렵고, 원본 길이로 복귀하는 동작도 없다. inline 입력은 1…1024지만 Core는 1…4096을 허용해 입력 범위도 일치하지 않는다.

섹션 서클은 반복·시간을 담는 송폼 궤도다. 원본 길이를 상속하는 use는 원본 변경을 따라가며, 이번 사용에 길이를 지정한 use는 독립된 override를 가진다. 현재 유효 마디 수가 같아도 명시적 override와 상속은 다른 상태다. 숫자가 같다는 이유로 override를 없애거나 상속으로 표시하지 않는다.

## build137 범위

같은 캔버스의 섹션 설정에서 원본 길이와 이번 사용의 길이 상태를 명확히 표시한다. Core와 같은 1…4096 마디 범위를 사용하며 이번 use의 변경과 원본 길이 복귀를 제공한다. 복귀는 유효 숫자를 복사하는 것이 아니라 해당 use의 길이 override를 해제하는 동작이다.

GUI와 MCP는 같은 Core atomic helper를 사용한다. 변경 후보의 clock·tempo·meter override를 검증한 뒤 적용하며 다른 use와 원본 음악을 바꾸지 않는다. 길이 축소 또는 원본 복귀가 기존 tempo/meter 이벤트의 유효 범위를 벗어나게 하면 명시적으로 거절한다. 실패 후 길이·override·음악·revision이 부분 변경되지 않아야 한다.

오류는 설정 화면의 고정 영역에서 표시하고 잘못된 값, stale 대상과 축소 불가 이유를 구분한다. 미확정 이름·수치 입력과 기존 Undo 계약을 유지하며 검증 오류를 피하려고 이벤트를 자동 삭제하거나 위치를 옮기지 않는다. 명령 이름과 wire 필드는 실제 구현 소스로 확정하고 이 문서의 계획을 실행 가능한 API 성공으로 제시하지 않는다.

## native 완료 기준

- 이번 use를 원본 16마디에서 20마디 override로 바꾼 뒤 원본 길이로 복귀한다. 유효 길이는 16이고 override는 nil인지, 다른 use와 원본 음악이 그대로인지 확인한다.
- 같은 값의 명시적 override와 상속을 화면과 데이터에서 구분한다. Undo로 이전 길이·상속 상태를 정확히 복원한다.
- 1…4096 밖 입력과 stale 대상은 거절하고 음악·revision을 보존한다. 축소 또는 복귀로 tempo/meter 이벤트가 범위 밖에 놓이는 후보도 같은 원칙으로 거절한다.
- 같은 캔버스에서 길이 출처·복귀 동작·오류가 보이는지 AX/JPEG로 확인한다. 저장/재열기 후 값·override·선택과 workspace를 대조한다.
- GUI와 MCP의 동일 요청 결과, 실패 batch의 불변 및 다른 use/source 보존을 비교한다. 실제 실행하지 않은 경계는 source 검증으로 구분한다.

## 별도 후속 UX

현재 MIDI에서 해당 섹션 설정으로 이동한 뒤 원래 MIDI 작업 위치로 돌아오는 흐름과 상단 global 설정의 대상 명시도 개선 필요를 발견했다. 두 항목은 이번 길이 상속 구현 범위에 포함하지 않으며 완료로 계산하지 않는다. 실제 오디오·청취와 전체 송폼 사용성 완료도 별도 검증이다.

## 기능 후보 결과와 최종 가시성 보완

`sectionlength137-final`의 기능 후보에서 Core 7개 (`.build/section-length-agent-tests.log`), Python 17개와 28개 (`.build/build137-mcp-tests.log`)가 PASS했다. 해당 후보 Release는 48.79초였다. 독립 artifact 감사도 PASS했다.

MCP r138→142에서 20마디 설정·같은 20의 no-op·해제·Undo 두 번과 7개 거절을 확인했다. 선택·음악·자산 보존도 대조했다. GUI는 r143의 20마디에서 잘못된 값 1로 해제를 차단하고 상태를 유지했다. draft 24 확정 r144→해제 r145 nil→Undo r146의 24/r147의 20/r148의 16을 확인했다. 외부 변경 r149는 다른 use A의 18마디만 바꿨으며 이전 draft의 해제는 차단했다. Undo r150과 재시작에서 baseline 복원을 확인했다.

새 `set_use_length_override`와 해제 명령은 공통 helper 및 `sectionLengthEditing: 1`을 사용한다. 기존 `set_section`은 직접 bars 적용과 최종 batch validation 계약을 유지하며 새 helper나 capability가 필요하다고 주장하지 않는다. 알려진 필드의 잘못된 요청은 native에서 거절을 확인했다. Python은 unknown/null을 엄격히 거절하지만 direct socket은 기존 decode 규약을 유지하므로 두 경로의 보장을 같다고 쓰지 않는다.

UI 독립 감사에서 기본 48pt 숫자 폭이 4자리를 자르는 문제를 발견했다. `ThemeCountControl`에 optional fieldWidth를 추가해 기본 48pt는 유지하고 섹션 길이만 64pt로 넓혔다. 이 wide 후보의 최종 Release·native 가시성 검증도 완료했다. 상단 global 대상 표시와 MIDI↔섹션 설정 복귀는 이번에도 미구현 후속 범위다.

최종 `sectionlength137-wide` Release는 warning 0개·48.47초에 통과했다. package.json에서 확인한 UUID는 `27130916-6031-3522-BF3C-15CFF27100C2`다. 기능 후보 이후 제품 변경은 섹션 길이의 숫자 폭 64pt 적용 범위이며 기존 공통 기본 폭은 유지했다. MCP r150→154, GUI 4096마디 r155→Undo r156과 4097 오류·전체 숫자 가시성을 확인했다. r156 재시작은 전체 manifest·hierarchyView·선택이 저장 상태와 정확히 같았다. wide의 `native-ui-audit.json`과 `independent-artifact-audit.json` 모두 재시작을 포함한 최종 PASS를 확인했다. 이번 테스트는 Core 7개와 Python 45개이며 이전 build135의 전체 816개를 build137 재실행 결과로 세지 않는다.
