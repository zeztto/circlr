# 바운스 원본 복원 후 작업 대상 복귀

상태: build123 소스·read-only 검토·Release 패키징과 아래 native 복귀/실패 시나리오를 검증했다. 독립 데이터 감사도 통과했다. [build122 제작 검증](141-production-flow-validation.md)의 원본 음악 복원·PCM 결과를 이번 UI 변경의 성공 근거로 대체하지 않는다.

## 재현한 문제와 목적

기존 제작 흐름에서 원본 복원은 성공했지만 선택이 음소거된 바운스 보관 서클에 남아 경로 밖 표시가 나타났다. `qa/generated/production-flow/current122/source-restored`가 당시 화면·상태 증거다. 복원한 음악을 계속 편집하려면 사용자가 원본 경로를 다시 찾아야 했다.

복원이 성공하면 같은 arrangement/use 안에서 바운스에 저장된 outputNodeID의 출력 서클로 이동한다. 임의의 첫 MIDI를 선택하지 않으며 원본 복원과 무관한 음악 변경을 추가하지 않는다.

## 구현 계약

[AudioWorkspace](../Sources/CirclrApp/AudioWorkspace.swift)의 원본 복원 버튼은 렌더 당시 scopeIdentity를 `restoreBounce(identity:)`에 전달한다. 이전의 act 래퍼는 작업 이후 기존 오디오 대상을 다시 focus하여 복귀를 덮을 수 있으므로 이 버튼에서 제거했다. read-only 검토의 P2 대상 identity 문제를 전달 방식 수정 후 재검토했고 PASS를 받았다. 이는 native 시나리오 통과를 뜻하지 않는다.

[ProductionWorkspace](../Sources/CirclrApp/ProductionWorkspace.swift)는 전달된 identity와 현재 project/revision/대상을 대조하고 바운스 잠금·선택 node·arrangement/use를 확인한다. 이름 편집을 확정하지 못하면 복원과 이동을 수행하지 않는다. 이름 확정 뒤에는 갱신된 revision과 동일 대상·바운스 출처를 다시 확인한다.

현재 프로젝트를 복사한 candidate에서 Core 원본 복원을 수행하고, 저장된 outputNodeID가 같은 arrangement/use의 실제 출력 서클인지 scene에서 확인한다. 실패하면 오류만 표시하며 candidate를 적용하거나 이동하지 않는다. candidate를 한 음악 변경으로 적용한 뒤 실제 프로젝트가 예상 revision을 포함해 그 candidate와 정확히 같은 경우에만 navigateStudio를 호출한다. mutate가 거절되거나 stale identity·잠금·복원 충돌이 발생하면 이동하지 않는다.

## 검증 준비와 조건

[준비 스크립트](../qa/prepare-bounce-return-qa.py)는 기존 완료 바운스 snapshot과 정확한 보관 PCM으로 독립 fixture를 준비한다. main 프로젝트는 ID1C6…·revision22, conflict 사본은 ID3DD…·revision22에서 시작하며 자산3개를 동일하게 유지한다. conflict 사본에는 mix→output edge1개를 추가하여 원본 복원 충돌을 검증한다. 이 데이터 준비를 실제 버튼 동작 검증으로 계산하지 않는다.

[캡처 스크립트](../qa/verify-bounce-return-native.py)와 별도 noIO helper QA 앱으로 다음을 검증한다.

1. 정상 원본 복원 후 보관 오디오가 아닌 저장된 출력 서클에 도착하고 같은 arrangement/use·트랙을 유지한다.
2. 원본 음악 복원 내용·Undo·저장/재열기와 자산 보존을 확인한다. navigation 때문에 추가 음악 revision이 발생하지 않아야 한다.
3. 이름 확정 실패와 conflict fixture의 복원 오류에서 음악·선택을 유지하고 오류를 확인한다.
4. stale 렌더 identity·작업 잠금·mutate 거절은 실제 실행한 범위와 소스 검토 범위를 분리한다. 소스 guard의 존재만으로 모든 경쟁 조건의 native 검증을 주장하지 않는다.
5. Release·패키지 식별·서명, 화면/AX의 실제 복귀, 저장 데이터 대조를 각각 확인한다.

## 최종 native 결과

Release는44.82초에 성공했고 main UUID는 `C0F5AE60-7F5B-3464-9AF1-5368FB141B06`이다. QA/production 바이너리 식별과 서명 검증을 통과했다.

- main fixture의revision22에서 원본 복원 후23이 되었고, 저장된 output7E… 서클 화면으로 이동했다. 기존 보관 서클의 경로 밖 표시 대신 복원된 출력 화면을 확인했다.
- Undo 후revision24에서 seed 음악으로 복귀했다. 이름을 빈 초안으로 만든 상태에서 복원을 클릭하면 오류가 표시되며24와 보관 서클 선택을 유지했다. Escape로 초안을 취소하고 재복원하면25·출력 서클 선택이 되었으며 재실행/정확한 프로젝트 재열기도25에서 확인했다.
- conflict fixture의revision22에서 복원을 클릭하면 바운스 이후 출력 연결이 변경되었다는 오류가 표시됐다. 음악·revision22·원래 바운스 선택을 유지했다. 이 실패 경로는 native로 확인했다.

JSON8개·JPEG7장·AX7개를 확보했다. synth_qa_kit의 독립 데이터 감사는8개 상태, restored-again=reopened=disk의 정확한 일치, 자산3개 SHA 보존, noIO/helper·서명·UUID를 대조하여 PASS했다. 실제 화면/AX의 복귀·오류 표시와 데이터 감사의 내용 보존 검증을 구분한다.

렌더 당시 identity를 오래된 요청으로 직접 주입하는 native 테스트는 실행하지 않았다. 해당 stale guard는 소스 검토 범위다. recording lock 역시 실제 녹음 중 검증하지 않았다. Core/DSP 변경은 없으며 새 PCM 렌더 검사를 수행하지 않았다. 이전 제작 검증의 PCM 결과를 이번 변경에 대한 새 검사로 합산하지 않는다.

QA 앱을 종료하고 원본 사용자PID86114만 유지했다. 사용자 앱 교체·물리 오디오 실행은 없고 output/audition attempts0을 유지했다. 실제 소리·연주 지연·HAL·녹음은 별도 gate다.

## 다음 작업

이 복귀 동작을 검증한 뒤 [현행 개발 계획](138-current-development-plan.md)의 한 곡 제작 흐름을 이어간다. 공유 오디오 가져오기·automation·편곡 대안·영상·실제 입출력·청취의 남은 조건을 유지하며, 하나의 복귀 개선으로 전체 제작 목표를 완료 처리하지 않는다.
