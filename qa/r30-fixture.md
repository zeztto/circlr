# R30-01 기준 곡 계약

이 곡은 직접 작성한 QA fixture이며 제품 콘텐츠·배포 샘플이 아니다. 외부 곡, 사용자 프로젝트, 다운로드 샘플 또는 seed manifest를 읽지 않는다. 생성기는 앱 실행·음원 재생·물리 I/O를 수행하지 않는다.

## 재현

저장소 루트에서 실행한다. 대상이 이미 있으면 덮어쓰지 않고 실패하므로, 이미 편집한 QA 프로젝트는 별도로 보존하고 새 출력 경로를 지정한다.

```sh
python3 qa/r30-create-fixture.py
python3 qa/r30-create-fixture.py --output "$HOME/Library/Application Support/circlr-integration-qa/fixtures/release030.circlr"
swift test --filter Release030FixtureTests/testAuthoredFixtureCompilesAndRoundTrips
```

기본 출력은 ignore된 `qa/generated/r30/release030.circlr`이다. native용 출력은 위 두 번째 명령의 별도 경로다. XCTest는 독립 임시 디렉터리에서 다시 생성하고 종료 시 그 임시 디렉터리만 지운다. 두 명령을 처음 실행하여 생성한 manifest와 PCM SHA256은 동일했다. Swift 테스트 결과는 릴리스 담당자가 별도로 기록한다.

## 기대 상태

기계 판독 기준은 `qa/r30-fixture-baseline.json`이며, 생성기는 매번 새 출력과 대조한다. manifest schemaVersion은 2로 고정되어 현재 앱의 이전 schema 읽기 검증에도 쓰인다. 새 저장에서 schema 승격이 일어날 경우 roundtrip 데이터/자산 검증과 별도로 그 변경을 기록한다.

| 항목 | 기대값 |
|---|---|
| Project / Arrangement | `R30-project` / `R30-arrangement` |
| 순서 | Intro → Verse → Chorus, 각 2 bars·8 beats·4초 |
| 길이 | 120 BPM, 4/4, 24 beats, 송폼 12초 (effect tail 제외) |
| use IDs | `R30-use-Intro`, `R30-use-Verse`, `R30-use-Chorus` |
| section IDs | `R30-section-Intro`, `R30-section-Verse`, `R30-section-Chorus` |
| 트랙 | `R30-track-drums`, `R30-track-synth`, `R30-track-audio` |
| 공유 MIDI | `R30-shared-drums`, 8개 킥/스네어 노트, Verse/Chorus source가 같은 패턴 참조 |
| 공유 source IDs | `R30-Verse-drums-source`, `R30-Chorus-drums-source` |
| 일반 MIDI 변형 | Verse 원본 `[48,51,55,58]`, Verse 이번 use `[60,51,55,58]` |
| 효과 | 각 섹션의 신스 instrument → delay → output |
| automation | 각 신스 instrument gain: beat 0=0.4, 4=0.8, 8=0.4, linear |
| 자산 | `R30-asset`, `media/R30-asset.wav`, 4초, 48 kHz, stereo PCM16, 192000 frames |
| 자산 SHA256 | `269e81783fe346377a519df0aec19da84c026f2fadd5a282a40379f9c603aed0` |
| manifest SHA256 | `934d0acedbcfc647748325ed8eab8e0de582193a74e732a71646a0aa4b55f508` |

오디오는 정수 연산으로 직접 합성한 작은 삼각파 아르페지오다. OS Sound Bank 드럼 트랙과 내장 신스 트랙도 포함한다. Sound Bank/가청 출력의 native 동작은 생성 성공이나 Core compile로 인증하지 않는다.

## 범위별 비교

- Verse 일반 MIDI 이번 use를 편집하면 `R30-Verse-lane-synth` override만 달라지고 원본 노트는 그대로다. Undo 뒤 baseline pitch를 다시 비교한다.
- 공유 MIDI를 편집하면 Verse/Chorus 공유 source 두 곳이 함께 바뀌며 Intro 일반 드럼 lane은 그대로다.
- 정렬/색상/캔버스 위치 변경 뒤 송폼 시작 `[0,4,8]`, 길이 12초, 원본/공유/변형 노트와 asset checksum을 비교한다.
- 바운스 뒤 재열기 및 원본 복원은 effect tail 포함 렌더와 12초 송폼 길이를 구분한다. 기존 원본 asset checksum은 고정값과 같아야 한다.
- 다른 편곡 왕복은 앱에서 기준 편곡을 복제한 후 검증한다. 초기 fixture에는 기준 편곡 1개만 있다.

R30-01 기준 고정은 Q01–Q10의 native 실행 PASS를 뜻하지 않는다. 선택·포커스·IME·실제 출력·정지·바운스 청취·이전 패키지 복구는 이 생성기에서 검증하지 않는다.
