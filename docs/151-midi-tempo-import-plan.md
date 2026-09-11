# MIDI tempo map 가져오기 계획

상태: cutoff 이후 한 곡 제작의 다음 범위를 위한 계획이다. 모델 필드·schema 번호는 아직 확정하지 않았으며 구현·테스트·native 결과를 뜻하지 않는다. 목표는 외부 MIDI의 템포 변화를 이번 섹션 사용에 명시적으로 적용하고 노트·오토메이션·바운스를 같은 시간 기준으로 유지하는 것이다.

## 현재 소스의 차이

[MIDIImport](../Sources/CirclrAudio/MIDIImport.swift)는 format0/1의 beat 파일을 읽지만 tempo track에서 time0의 첫 BPM만 보관한다. [MIDIImportView](../Sources/CirclrApp/MIDIImportView.swift)는 파일의 첫 BPM을 안내하고 기존 섹션 템포로 노트만 가져온다. 따라서 노트 beat는 보존돼도 파일의 실제 연주 시간은 달라질 수 있다.

[Model](../Sources/CirclrCore/Model.swift)에는 Section.tempoChanges가 있으나 SectionUse의 독립 tempo map은 없다. [ArrangementCompiler.context](../Sources/CirclrCore/Compiler.swift)는 use tempo가 inherit일 때만 원본 map을 사용하고 local/global 지정 시 map을 제외한다. [MIDIImportEditing](../Sources/CirclrCore/MIDIEditing.swift)은 새 lane을 이번 use에 추가하고 필요하면 barsOverride를 늘린다. 원본 map을 바로 변경하면 같은 section의 다른 use까지 영향을 받으므로 import의 독립 사용 계약과 충돌한다.

## 읽기와 선택 계약

전체 tempo 이벤트의 beat·BPM·파일 내 순서를 읽는다. 동일 beat의 여러 이벤트는 결정적 파일 순서의 마지막 값으로 정규화하는 방안을 검토하고 실제 format0/1 fixture로 AudioToolbox 순서 보존을 확인한다. 순서를 보장할 수 없으면 충돌로 거절하여 임의 선택하지 않는다. 첫 tempo가 beat0 이후이거나 없는 표준 MIDI는 그 앞 구간을 기본120BPM으로 해석한다. 음수/비유한 beat·범위 밖 BPM·과도한 이벤트 수는 거절하고 count/크기 제한을 고정한다.

가져오기에서 `현재 템포 유지`를 기본으로 유지하고 `파일 템포 적용`을 명시적으로 선택한다. 현재 템포 유지 경로는 기존 동작과 동일하며 새 schema를 유발하지 않는다. 파일 tempo와 meter/CC는 별개다. 박자표·CC·pitch bend까지 가져왔다고 표시하지 않는다. 선택 트랙의 마지막 note 끝을 적용 구간 끝으로 제안하며, 이후 tempo-only 이벤트는 적용하지 않는다는 범위를 UI에 표시한다. 최종 구간 기준은 구현 전에 테스트 계약으로 고정한다.

## 시작 위치와 구간 경계

파일 tempo 적용은 이번 use의 기존 유효 clock을 기준으로 import 구간만 교체한다. 파일 beat0과 모든 이벤트는 import 시작 beat `s`만큼 이동한다. 끝 `e`는 선택 MIDI의 마지막 note 끝을 옮긴 위치다. 템포 변경은 같은 use 안의 기존 노트·오디오에도 영향을 준다는 점을 적용 전에 명시한다.

- `s=0`: 파일의 초기 BPM을0에서 적용한다. 파일 구간의 끝 이후 기존 내용이 있으면 기존 clock이 e에서 갖던 BPM으로 복귀한다.
- `s>0`: s 이전의 기존 tempo 이벤트를 보존하고 s에서 파일 초기 BPM으로 전환한다. `[s,e)` 안의 기존 이벤트만 대체하고 e의 기존 유효 BPM을 경계 이벤트로 복원한다. e 이후 기존 이벤트도 보존한다.
- e가 현재 섹션 길이를 넘으면 기존 `섹션 연장` 선택을 요구한다. 연장 구간의 기존 기준 BPM은 기존 map의 마지막 값으로 연장하여 복귀 규칙을 결정한다. 마디 올림 후 생기는 나머지 구간을 임의로 파일 마지막 BPM에 묶지 않는다.
- 동일 경계의 이벤트는 하나로 정규화하며 필요 없는 연속 동일 BPM은 제거할 수 있다. 이 정규화가 기존 구간의 seconds mapping을 바꾸면 안 된다.

예: 기존120BPM인8박 섹션에 s=2로 4박 MIDI를 넣고 파일이 beat0=120, beat2=60이면 use의 beat2=120, beat4=60, beat6=120이 된다. import 구간은3초, 원래 앞2박은1초, 뒤2박은1초여서 전체5초다. s=0에서 같은 파일4박만 사용하면3초다. 파일 템포 유지가 아닌 현재 템포 유지 선택이면 기존120BPM의4박은2초다.

## 모델 도입과 충돌 처리

필드 이름을 먼저 정하지 않는다. 다음 두 표현을 비교한 뒤 하나를 선택한다.

1. 이번 use의 완전한 유효 tempo map을 저장한다. 적용 결과가 예측 가능하고 원본 변경에 흔들리지 않지만 상속 관계를 일부 복제한다.
2. 이번 use의 구간 patch와 경계 복원 정보를 저장한다. 상속을 표현할 수 있지만 원본 map 변경 후 같은 import가 다른 시간이 될 수 있어 재평가·충돌 계약이 더 복잡하다.

첫 구현은 명시적 파일 tempo 적용의 예측 가능성을 우선해 완전한 override를 유력안으로 검토한다. 부재는 기존 tempo source/map 계약을 사용하고, 빈 배열과 상속·고정 BPM은 구분해야 한다. 기존 use local/global BPM 변경이 새 map을 유지할지 해제할지도 UI/Core에서 명시적으로 결정한다. 새 필드가 있다고 기존 tempo source를 무시하는 우선순위를 암묵적으로 만들지 않는다.

원본 tempo map·다른 use·다른 편곡은 보존한다. 적용된 이번 use override를 해제하면 원본 상속 또는 이전 tempo 정책으로 돌아가는 동작을 제공한다. 편곡 복제·연장·저장·Undo/Redo·원본 적용과의 관계를 함께 정의하며 active 편곡만 검사하지 않는다.

## 저장 호환과 오디오 제약

cutoff 도입 후 현재 schema3 경계를 기준으로 새 tempo 표현을 구버전이 무시하지 못하게 해야 한다. schema 승격이나 필수 capability 경계 중 안전한 도입 방식을 결정하고 [ProjectStore](../Sources/CirclrCore/ProjectStore.swift)의 header 검증과 모든 compiler/migration guard를 대조한다. 기존 문서를 읽기만 할 때는 bytes/schema를 변경하지 않는다. 처음 tempo override를 적용한 Undo는 이전 schema와 음악을 정확히 복원한다.

[ClipAudioRenderer](../Sources/CirclrAudio/ClipAudioRenderer.swift)의 tempo 추종 비율0.25–4 제한과 기존 clip 구간의 tempo 조건을 지킨다. 새 map이 기존 followsTempo 오디오의 지원 범위를 넘으면 tempo만 일부 적용하거나 오디오를 조용히 무시하지 말고 전체 import를 원자적으로 거절한다. 이때 사용자가 `현재 템포 유지`로 다시 적용할 수 있도록 실제 원인을 알린다. 자동 time-warp·자동 bounce·새 오디오 분할은 별도 동의 없는 fallback으로 사용하지 않는다.

followsTempo=false의 PCM 재생 길이와 beat 기반 배치의 관계도 실제 clock으로 검증한다. 새 clock을 모든 오디오가 지원한다고 미리 약속하지 않는다. 필요한 경우 후속 time-warp 범위로 남기되 기존 지원 조건 안의 전체 MIDI→tempo→automation→bounce 흐름은 끝까지 구현한다.

## GUI·MCP 원자적 적용

GUI는 파일 이름·선택 트랙·삽입 시작 위치·tempo 적용 구간·BPM 변화·섹션 전체 시간 변화·이번 use 영향·연장 여부를 같은 import 화면에 표시한다. 새 영구 패널을 추가하지 않는다. 노트 선택과 tempo 선택을 바꾸면 미리보기 범위를 다시 계산한다.

Core의 단일 candidate에서 노트 추가·필요한 use 길이 변경·tempo override·최종 구조/렌더 가능성 검증을 수행하고 성공할 때 한 Undo로 적용한다. projectID·expectedRevision·arrangementID·useID를 명시해 background MCP도 정확한 대상에 적용한다. [AgentProtocol](../Sources/CirclrCore/AgentProtocol.swift)과 [MCP schema](../mcp/server.py)는 같은 정책 enum·이벤트 단위·범위·개수 제한을 사용한다. 노트 추가와 tempo 변경을 별도 성공으로 나누지 않는다.

파일 파싱·사용자 선택 중 project/revision/대상이 바뀌면 거절하며 취소 뒤 늦은 완료가 적용되지 않는다. 실패 batch·잘못된 이벤트·오디오 제한·schema 오류는 lane/track/asset/tempo 일부도 남기지 않는다. 미지원 tempo 적용을 현재 템포로 자동 바꾸지 않는다.

## 오프라인 검증과 실제 한 곡 흐름

- format0/1·첫 tempo 없음/지연·동일 beat 충돌·비정상 BPM·이벤트 한도·선택 트랙 끝 이후 이벤트를 검사한다.
- 위 s=0/s=2 숫자 예제, 기존 가변 map 안의 삽입, 구간 끝 복귀, 섹션 연장·마디 올림을 독립 seconds 기대값으로 검사한다.
- A에만 적용하고 공유 section B·원본 map·다른 편곡이 불변인지 확인한다. 현재 템포 유지 경로는 기존 import 결과와 같다.
- cutoff의 beat 곡선과 MIDI note-off가 새 MusicClock의 같은 sample 시간에 도달하고 바운스 PCM이 독립 기대 렌더와 일치하는지 검사한다.
- followsTempo=false 배치 및 지원 가능한 추종 구간·지원 불가 구간의 원자적 거절을 실제 PCM/상태로 검사한다.
- GUI/MCP 동일 결과·한 Undo·Redo·schema·편곡 복제·정확한 저장/재열기·실패 후 음악 불변을 확인한다.
- authored 한 곡에서 MIDI 가져오기→tempo 선택→A/B 비교→cutoff 편집→바운스→원본 복원→재열기를 실행한다. 실제 화면의 BPM/시간·작업 위치를 확인한다.

이 경로는 하드웨어나 실시간 입력 없이 소스·오프라인 PCM·native 편집으로 검증할 수 있다. 실제 출력·청취·MIDI 녹음·CC/pitch bend는 별도이며 본 계획 작성 시점에는 어떤 구현이나 검증도 완료했다고 주장하지 않는다.
