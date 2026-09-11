# MIDI 서스테인 저장·컴파일 연결

기준: `c7a7ea7`의 독립 CC64 타입 이후, [계획173](173-midi-sustain-plan.md)의 첫 연결 단계. 앱 build 번호는149이며 설치 앱은 교체하지 않았다. 이 문서는 당시 프로젝트 데이터 보존과 출력 거절 경계의 기록이다. 이후 내장 신스의 실제 오프라인 pedal DSP는 [검증175](175-midi-sustain-render.md)에서 연결했다. SMF parser·GUI/MCP 페달 편집은 여전히 후속 단계다.

## 보존되는 데이터와 편집 범위

Lane와 RhythmPattern의 optional `sustain`은 구형 파일에서 nil이며 nil 필드는 인코딩하지 않는다. 최초 명시적 데이터 편집만 schema7로 승격한다. 열기/no-op은 승격하지 않으며 clear는 이미 승격한 버전을 낮추지 않는다. 원본·이번 use override·added lane·비활성 편곡·공유 pattern·take를 모두 검사한다. 같은 source의 bend와 sustain channel이 다르면 거절한다.

공유 패턴과 편집용 Lane 사이의 복사, MIDI take의 nil을 포함한 표현 교체, audio-only take의 기존 표현 유지도 연결했다. 테이크 요약은 페달만 다른 연주를 같은 내용으로 표시하지 않는다. Core history는 이전 schema와 원본/override를 함께 복원한다. App의 실제 Undo 키 조작을 이번 검사로 주장하지 않는다.

Core의 typed `MIDIImportPart`도 sustain을 받을 수 있다. `atBeat` offset을 이벤트에 적용하고 초기 raw 값·같은 beat 배열 순서를 보존한다. 마지막 페달 이벤트를 섹션 길이와 tempo preview에 포함하고 두 표현의 이벤트 수를 합산한다. 이것은 SMF 파일에서 CC64를 읽는 parser 구현이 아니다. 현재 parser와 GUI 안내는 아직 기존 pitch bend 범위다.

## 반복과 출력의 경계

bend 또는 sustain이 있으면 한 source/occurrence당 하나의 `MIDIPerformanceStream`을 만든다. 노트를 두 번 만들지 않으며 parent tempo map·local tempo·반복별 seconds clock을 사용한다. 같은 시간의 pedal-up/down 순서를 보존하고 controller 끝은 end-exclusive다. pattern swing은 노트에만 적용한다. 실제 pedal 종료 release 처리는 후속 DSP가 담당한다.

`hasPitchBendExpression`은 sustain-only를 기존의 명시적인 center bend와 구별한다. 기존 typed initializer의 기본값은 true이며 compiler는 원본 bend 존재 여부를 전달한다. flag가 false여도 비중심 raw·변경 range·bend 이벤트가 있으면 pitch 표현으로 간주하여 우회를 막는다.

현재 렌더는 유효 raw 0…63뿐인 all-off packet을 허용한다. 64 이상 초기값/이벤트가 활성 출력 경로에 있으면 helper 실행 전에 명시적인 미지원 오류를 반환한다. 잘못된 값·시간·순서·출처·이벤트 예산도 검사한다. 실제로 출력에 기여하지 않는 음소거·분리·미사용 router port·zero route는 보관할 수 있다. pre-output bounce에서는 출력 노드의 mute/gain이 위쪽 페달 검사를 숨기지 않는다.

typed MIDI 파일 저장은 sustain이 존재하면 명시적인 off 값도 거절한다. 소리 효과가 없더라도 원본 raw 이벤트를 버린 파일을 반환하면 안 되기 때문이다. 일반 notes-only 파일의 기존 bytes는 보존한다. legacy/no-graph·전환 패턴의 표현 지원은 여전히 별도이며, 저장 support가 모든 연주 backend 지원을 의미하지 않는다.

## 검사 결과

실행 명령:

```sh
swift test --scratch-path .build/integration-tests --filter 'CirclrCoreTests|MIDISustainGuardTests|MIDIPitchBendGuardTests|MIDIPitchBendRenderTests|MIDIPitchBendExportRoundTripTests|MIDITempoRenderTests|SynthResonanceAutomationTests|SynthCutoffAutomationTests|SynthCoreTests'
```

build15.08초, 전체 Core+선별 Audio **618개·실패0개**, 검사24.437초. `.build/sustain-storage-regression.log`에 기록했다. 신규 검사는 Storage6·Performance5·typed Import/Export7·Audio guard9개이며, 앞 단계 Sustain foundation6개도 함께 재실행했다. 이 수치를 전체 Audio suite로 표현하지 않는다.

- 구형 nil 읽기, schema 승격/clear/history, 원본과 다른 use 보존, inactive/take/channel 오류의 원자적 거절.
- 실제 임시 `.circlr` 패키지 저장·재열기 및 전체 프로젝트 일치, schema7에서 송폼 섹션 추가.
- typed import offset·초기값·동시점 순서·말미 release·템포 적용·합산 한도·실패 시 불변.
- 하나의 표현 stream·노트 불변, local tempo·parent tempo override·shared overlap·반복 seed·끝 제외.
- all-off 기존 신스 PCM 일치, 활성 페달 helper 전 거절, 보관/route 경계, 표현 파일 저장 거절.
- 미래 버전 header 거절 fixture는 새 최대 버전에 맞춰8로 올렸으며, 알 수 없는 본문을 decode하기 전에 거절하는 검사를 유지했다.

`swift build --scratch-path .build/app-release -c release --product circlr`도 86.17초에 통과했다(`.build/sustain-storage-release.log`). 패키징하거나 설치 앱을 실행한 결과는 아니다. 검사 실행 뒤 소스 정리는 저장/연주 경계를 설명하는 주석 두 곳뿐이다.

저장/복사, 컴파일/시간, Audio 거절 경계의 독립 읽기 전용 리뷰에서 고확신 신규 결함은 발견되지 않았다. 실제 출력·마이크·native 화면·SMF CC64 왕복·페달 DSP 검증은 수행하지 않았다. production PID86114는 유지했다.

## 이어서 할 일

`MIDIPitchBendRenderer`의 owned voice에 pedal-down 시 key-off 보류와 pedal-up release를 연결한다. 같은 sample의 up→down, 이미 release된 음 재포착 금지, 다음 반복과 source 격리, 긴 key-held note의 종료 경계를 먼저 검증한다. 그 다음 SMF 읽기/쓰기의 종료 정책과 같은 캔버스 편집을 연결한다.

UI는 현재 궤도 또는 피아노 롤·스텝·피치 벤드의3모드에 서스테인을 더하는4모드 구조다. 별도 header의 오토메이션과 혼동하지 않는다. 같은 eager wrapping toolbar에서 파일 작업 버튼과 함께 배치해 추가 메뉴 깊이를 만들지 않는다. 소스상 예상 폭은 native 가독성 검증을 대체하지 않으며, 1019×768·콘솔122에서 compact 배치와 초안 보존을 실제 확인한 뒤 노출한다.
