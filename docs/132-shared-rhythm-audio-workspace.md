# 공유 리듬 오디오 작업 공간

상태: build116 Core7개·regression32개, frozen final3 Release42.71초·source v6 review blocker0 통과. final2 일반 시나리오17개와 final3 초안/선택 복원5개를 나눈 mixed-candidate checker 및 final3 PNG4장 시각 검토를 통과했다.

## 편집 동작 계약

공유 리듬의 `.rhythmAudio`가 AudioLane만 보여 파형·수치 편집을 할 수 없던 흐름을 같은 캔버스에서 연결한다. 클립 선택과 공유 범위 안내를 제공하고 trim·fade in/out·volume·beat·tempo, split·duplicate·delete를 지원한다. 일반 오디오와 동일한 작업 공간을 사용하되 변경이 공유 패턴을 쓰는 모든 곳에 반영됨을 표시한다.

Core 변경은 pattern.audio에만 원자적으로 적용한다. 일반 graph와 다른 패턴·클립·원본 자산을 보존하고 오래된 편집 identity의 요청을 거절한다. 한 Undo 단위와 정확한 저장/재열기 계약을 유지한다.

## 확인된 baseline과 Core 검증

`qa/generated/shared-audio-workspace/baseline115/before.*`에 실제 build115 `.rhythmAudio`의 AudioLane2개 clip만 보이고 waveform/numeric 편집이 없는 상태를 PNG·AX·snapshot revision14로 확보했다. baseline 앱은 종료했고 사용자 앱 PID86114를 유지했다.

`.build/shared-rhythm-audio-tests.log`:7개 테스트·0 failures·0.390초. 반복 pattern의 변경 전/후 offline PCM max error<1e-6 assertion과 graph·legacy의 expanded cycle beat offset 배열을 확인했다. legacy 전체 PCM 동등성은 검증하지 않았으며 Core ordinary graph를 변경하지 않는다.

UI3개 파일과 AppStore cache 연결을 적용했고 최대2개 keyed cache로 같은 프로젝트 검증을 반복하지 않도록 했다. 공유 mute 범위를 명확히 표시한다. non-follow split은 서로 다른/가변 tempo를 거절하며 followsTempo는 sourceBPM delta와 전체 sample boundary를 검사한다. native 결과는 아래 final2 일반 범위와 final3 보완 범위를 구분한다.

## final2와 final3의 증거 경계

`.build/build116-release-final2.log`: final2 Release44.04초·exit0. Core7개와 별도 regression32개를 통과했다. final2 native에서 shared15개 상태와 ordinary gain/Undo를 포함한17개 상태를 확인했고 마지막 clip 삭제 후 부모 섹션으로 복귀했다.

초기 final 후보의 마지막 삭제 흐름과 final2의 추가 발견을 구분한다. final2에서는 잘못된99 초안을 입력한 뒤 clip을 전환해도 이전 초안이 남고, 저장한 clip2 대신 clip1으로 재열리는 문제가 발견됐다. 이를 정상 동작이나 완료 증거로 처리하지 않는다. `.id(clip.id)`·`EditorSelectionMemory` 복원·부모 asset viewport 초기화를 수정했다. `.build/build116-release-final3.log`는 빌드 도중 source 변경으로 실패했으며 성공 근거가 아니다. source freeze 후 `.build/build116-release-final3-frozen.log`에서42.71초·exit0을 확인했다.

final3 package UUID는 `7DD71FA1-C126-34EA-82C5-E1CF34853EDE`, main source binary SHA256은 `77c1efd234a34ed29536453c5d9732e477a9801e180cccfa078bee222f26688b`다. before34에서99 invalid draft를 캡처한 뒤 clip2로 전환한 draft-switched34는4.000초 baseline과 오류 없음이었다. trimmed35는 source4.25/duration1.75, trim-undo36은 baseline 복원, reopened36은 clip2·4..6초를 유지했다. save/open job 완료도 확인했다. 최종 checker는 final2의17개 시나리오와 final3의5개 보완 상태를 구분해 통과했다. 이를 final3에서 모든 시나리오를 재실행한 것으로 표현하지 않는다. trim-undo·reopened·disk는 정확히 동일하며 final3 signed main SHA와 UUID guard도 통과했다. PNG4장 시각 검토에서 draft-switched 수치는 AX로만 확인했고 재열기 상태는 실제 화면으로 확인했다.

## 검증 범위 요약

- Core에서 원자성·다른 데이터 보존·잘못된 값과 stale 대상 거절을 확인했다.
- 실제 같은 캔버스에서 클립 선택, 파형·수치 변경, split/duplicate/delete와 공유 사용 반영을 확인했다.
- Undo·저장/재열기·원본 자산과 ordinary graph 보존을 strict 비교한다.
- noIO 환경에서 편집을 검증했으며 물리 오디오 성공으로 계산하지 않는다.

compact 전체 배치·물리 I/O·legacy 전체 PCM은 미검증이다. QA 앱을 종료했고 기존 사용자 PID86114를 유지했다. 별도 [audition worker 격리](133-audition-worker-plan.md)는 계획 범위이며 이 편집 UI 변경에 포함하지 않는다. 사용자 실행 앱은 보존한다.
