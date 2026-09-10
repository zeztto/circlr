# 서클별 편집 화면 기억

상태: build139 검증 후보의 Release·native 왕복과 입력 보호를 완료했다. package·UI·최종 state 독립 감사 모두 PASS했다.

## 확인한 문제와 목표

build138에서 오토메이션을 편집한 뒤 새 오디오 서클로 이동하면 파형 대신 오토메이션 화면이 나타났다. 증거는 `qa/generated/circle-memory139-before/audio-inherits-automation`의 JPEG/AX다. 서로 다른 서클의 편집 모드가 잘못 전달되지 않도록 첫 방문과 재방문을 구분한다.

일반 사용자 탐색인 Command+J, route 이동, 캔버스 마우스·키보드·접근성 이동에 같은 규칙을 적용한다. 처음 방문하는 target은 그 source에 맞는 기본 편집 화면을 연다. 재방문은 정확한 scope별 workspace·페이지·viewport로 돌아온다. 같은 주소로 이동하는 요청은 현재 편집 상태를 불필요하게 초기화하지 않는다.

## 의도와 상태 경계

Command+4처럼 스텝 편집을 명시한 요청은 기억된 모드보다 우선한다. 여러 target 중 선택하는 chooser를 거쳐도 명시적 step 의도를 전달한다. 일반 탐색의 기억 복원 때문에 사용자가 요청한 모드가 취소되지 않아야 한다.

기억은 원본 source, 이번 use, 공유 pattern과 실제 주소를 구분한다. 서로 다른 scope의 상태를 이름이나 임의의 첫 MIDI로 매칭하지 않는다. 삭제·source 변경·길이 변경 뒤에는 현재 유효성에 맞게 선택과 표시 범위를 처리하며 오래된 이벤트 index를 다른 데이터에 적용하지 않는다.

build138의 섹션 설정 왕복은 자체 transient ticket과 복귀 guard를 유지한다. 저장된 편집 snapshot의 재시작 복원도 별도 계약이다. 서클 재방문 기억을 추가했다고 모든 transient 상태가 세션 사이에 영구 보존된다고 주장하지 않는다.

## 검증 계획

- 오토메이션→처음 방문한 오디오가 파형으로 열리는지 같은 조건의 전후 AX/JPEG로 확인한다.
- MIDI 노트·스텝·pitch, 오디오·오토메이션의 재방문에서 주소·모드·페이지·viewport와 선택을 대조한다. 같은 주소 재선택도 검사한다.
- Command+J·route·캔버스 마우스/키보드/접근성 이동이 동일한 일반 탐색 계약을 사용하는지 실행한 경로별로 기록한다.
- Command+4 직접 진입과 chooser를 통한 진입이 기억된 모드보다 우선하는지 확인한다.
- scope 전환·삭제·source 변경·현재 길이 경계, invalid draft와 stale 요청의 음악 불변을 확인한다. native 미실행 경계는 source 검증으로 분리한다.
- 섹션 설정 왕복·저장/재열기가 기존 계약을 유지하는지 회귀 확인한다. 모든 순수 탐색에서 음악·revision·자산이 불변인지 비교한다.

검증은 QA 사본에서 수행하며 실제 I/O·청취·모든 접근성 조합 완료를 뜻하지 않는다. 결과 수치는 실행 후 기록한다.

## 초기 후보 검증

`circlememory139` 후보 Release는 49.15초에 통과했으며 UUID는 `D938D744-8936-3201-83D1-656F057769E3`다. 관련 Core 검사 21개도 PASS했다. native에서는 세 번의 왕복, 스텝 페이지 5·섹션 설정 왕복·AX 캔버스 복귀, Command+4 chooser의 명시적 모드 우선과 취소 원복을 확인했다.

다만 invalid draft 상태의 캔버스 클릭이 입력을 보호하지 못하는 문제를 발견했다. 해당 경로는 당시 수정과 재검증이 필요했으며 아래 최종 후보에서 해결을 확인했다. 초기 후보 통과 항목은 이 결함의 해결 증거가 아니다. 실제 I/O는 이번에 검증하지 않았다.

## 검증 후보의 최종 결과

최종 `circlememory139-verified` UUID는 `B0A91724-8417-3E25-86DB-7B3F4092B479`다. Release는 47.96초에 통과했다 (`.build/build139-draft-fix-release.log`). 초기 workspace 관련 Core 21개와 최종 Number/Name 18개 검사를 통과했다 (`.build/build139-draft-fix-tests.log`). 이전 전체 816개를 이번에 재실행한 결과로 세지 않는다.

초기 후보와 첫 수정 후보(Release 48.10초)는 invalid canvas 입력 보호에 실패했다. 이 두 후보의 증거는 보존한다. 최종 수정은 numeric helper에서 mounted·visible·enabled·같은 key window의 dirty fallback을 검증하며 임시 monitor를 제거했다.

최종 native에서 invalid 16384 상태의 캔버스 클릭은 입력 원문·오류·편집기를 유지했고 revision r166·음악·workspace·camera도 정확히 같았다. Escape는 8192로 복구했다. Command+J의 잘못된 수치와 이름도 보호했다. 16개 AX/JPEG 및 재시작 캡처에서 instrument pan·오디오 16–32초·MIDI pitch·step 페이지 3/B4/34스텝, 같은 주소 재선택·섹션 설정·AX 캔버스 왕복을 확인했다. 비교 쌍의 음악·자산은 r166에서 불변이었다.

재시작 전후 저장된 전체 hierarchyView·camera·runtime은 정확히 일치했다. 스텝 페이지 3/16·B4 행은 유지했지만 임시 cursor는 34스텝에서 첫 열인 33스텝으로 초기화됐다. cursor와 전체 서클 기억 map은 세션 임시 상태이며 재시작 cursor까지 정확히 보존한다고 주장하지 않는다. 같은 주소 요청의 focus는 outer canvas이므로 입력 focus까지 정확히 유지한다고 주장하지 않는다. package·UI·최종 state 감사 모두 PASS했다. state 감사는 11개 캡처·7개 비교 쌍의 음악 r166과 자산 6개 SHA의 정확한 보존을 확인했다. 모든 QA 앱은 종료했으며 task dist는 build139, 사용자 원본 PID 86114는 유지했다.

source 삭제·변경·clamp·scope의 모든 조합은 이번 native에서 실행하지 않았다. 소스 계약과 기존 관련 테스트 범위로 구분한다. 실제 I/O·청취·모든 접근성 완료를 뜻하지 않는다. 다음은 한 곡의 실제 편곡 동선에서 source 변경·길이 변화가 있는 재방문을 검증하고, 확인된 손실만 수정하는 범위다.
