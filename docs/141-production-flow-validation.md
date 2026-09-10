# 스텝에서 바운스까지의 통합 제작 검증

상태: 기존 build122의 동일 바이너리에서 공유 리듬 스텝 입력 → 음색 수정 → 이펙트 추가 → GUI 바운스 → 원본 복원 → Undo → 저장/재열기를 실행했다. 새 앱 코드를 추가하거나 이번 검증을 위해 새 Release를 빌드한 것은 아니다. 독립 데이터 감사와 재현용 checker를 통과했다. 전체 DAW·한 곡 제작·실제 오디오·발매 품질 완료를 의미하지 않는다.

## 대상과 검증 경계

[스텝 대상 유지](140-step-target-navigation.md)에서 사용한 authored QA 프로젝트의 일반 MIDI와 공유 리듬이 함께 있는 트랙을 이어서 편집했다. 증거는 `qa/generated/production-flow/current122`에 보존한다. 음악revision18에서 시작했으며 사용자 원본 앱·곡을 편집하지 않았다.

fixture의 악기는 모두 engine3 synth이며 AU는 없다. 사용한 오디오의 followsTempo는false다. QA helper가 물리 입출력을 차단했고 캡처마다 output/audition attempts0을 확인했다. 따라서 아래 결과는 native 편집과 오프라인 렌더 검증이다. 실제 연주·HAL·녹음·청취·AU·템포 추종 오디오를 검증했다고 표현하지 않는다.

## 실행한 제작 흐름

| 단계 | 실제 변경·관측 | 음악 revision |
|---|---|---|
| 공유 리듬 스텝 입력 | 세 번째 스텝에 pitch66·beat0.5·length0.225·velocity96 노트 추가 | 18 → 19 |
| 음색 수정 | 트랙 `7E0D9016-E91D-4325-B807-033F233E32EA`의 synth cutoff를2400으로 적용 | 19 → 20 |
| 이펙트 | 공유 리듬 편집 A에만 reverb 추가 | 20 → 21 |
| 오프라인 내보내기·GUI 바운스 | 바운스 전 WAV 확보 후 GUI에서 오디오로 바운스하고 바운스 후 WAV 확보 | 21 → 22 |
| 원본 복원 | GUI 원본 복원 후 WAV를 다시 내보내어 바운스 전 결과와 대조 | 22 → 23 |
| 복원·바운스 Undo | Undo2회로 바운스 전 음악 상태 복귀 | 23 → 25 |
| 편집 Undo·재열기 | Undo3회로 이펙트·음색·스텝 변경을 되돌리고 저장/재열기 | 25 → 28, 재열기28 |

음색 첫 입력에서 기존 수치를 선택하지 않고 타이핑하여102400이 되어 범위 오류로 거절됐다. 이때 revision19를 유지했으며 `sound-invalid.ax.txt`·JPEG를 실패 경로로 남겼다. 올바른2400 적용 뒤의 `sound-edited` 결과와 구분한다. 입력 오류를 정상 적용으로 세지 않는다.

독립 데이터 감사에서 공유 패턴의 정확한 노트 추가, 대상 트랙의 cutoff, A에만 적용된 reverb, Undo2회 후 바운스 전 음악 일치, 추가 Undo3회 후 기준 음악 일치를 확인했다. revision 등 이력 메타데이터의 변화와 음악 내용의 복원을 구분한다. 저장/재열기는 revision28에서 확인했다.

## PCM 대조

바운스 전후 stereo WAV는 모두48kHz·24bit·1,711,456frames, 약35.655333초다. `pcm-comparison.json`의 최대 차이는1LSB, RMS 차이는0.4126398997LSB이며 signal peak는0.1365425587이다. RMS 수치는 신호 loudness가 아니라 두 결과의 정수 sample 차이임을 명시한다. 이 비교는 바운스의 음향 내용 보존 근거이며 실제 청취 또는 음악적 완성도의 판정이 아니다.

원본 복원 후 `source-restored.wav`는 `before-bounce.wav`와 파일 바이트까지 정확히 같다. 두 SHA256은 `8f98772fe965453e11c3a6c48b6a95d2fc51c34d1d3672e8a15ca8ec46268345`이며 `restored-pcm-comparison.json`에 기록했다. 바운스 전후의1LSB 허용 비교와 원본 복원 후의 byte-exact 비교를 혼동하지 않는다.

## 증거와 보존

저장 snapshot9개는 before·step-edited·sound-edited·effect-added·bounced·source-restored·bounce-undone·all-undone·reopened다. JPEG9장·AX9개도 확보했다. `sound-invalid`는 화면/AX 증거이며 별도 음악 snapshot으로 집계하지 않는다. export job/result와 PCM 비교 JSON은 위9개 저장 snapshot 수에 합산하지 않는다.

기존 build122 패키지의 식별·서명 근거와 이번 사용 패키지는 `package.json` 및 이전 검증 기록으로 구분한다. 이번 제작 동선 통과를 새 Release 성공으로 기록하지 않는다. QA 앱 종료 후 사용자 원본PID86114만 유지했고 사용자 앱을 교체하지 않았다. [증거 checker](../qa/check-production-flow-evidence.py)를 실행해9개 단계별 음악 변경·Undo·disk 일치, no-I/O, 패키지/자산 무결성, PCM 비교를 재검증했다. 마지막 root 실행은0.74초·PASS다.

Undo/save 후 fixture에서 제거된 바운스 asset은 QA Bounces 원본 중 checksum이 일치하는 파일을 `bounced-asset.wav`로 보존해 다시 검사했다. SHA256은 `9387feb5f7b38cb5a3569cf2d6bbca106f09646a953a6d84a440d9fea1aadb1e`이다. export WAV를 원본 asset으로 대체한 것이 아니다. 원본 앱·미디어·생성 증거는 source push에 포함하지 않는다.

재현 도구: [fixture·패키징](../qa/prepare-production-flow-qa.py), [native snapshot](../qa/verify-production-flow-native.py). snapshot 도구의 runtime/asset 검증과 checker의 단계별 음악 의미 검증을 구분한다. `python3 qa/check-production-flow-evidence.py`는 이미 확보한 로컬 증거만 읽으며 앱·장치·MCP를 호출하지 않는다.

## 발견한 다음 UI 문제

원본 복원 후 편집 초점이 음소거된 바운스 서클에 남고 경로 밖 표시가 나타났다. 음악은 복원됐지만 사용자는 다시 원본 작업 대상을 찾아야 한다. 이는 이번 탐색의 실제 후속 개선점이며 데이터 복원 실패라고 단정하지 않는다.

다음 단계에서는 음악 상태를 보존하면서 바운스에 저장된 outputNodeID를 따라 원본 출력 대상으로 이동하는 계약을 검토한다. 대상 존재·현재 편곡/use·scene 노출·Undo 이후 주소를 확인하고, 임의의 첫 MIDI로 옮기는 동작을 복귀로 사용하지 않는다. 아직 이 UI 개선을 구현하거나 검증한 것은 아니다.

## 남은 한 곡 작업

[현행 개발 계획](138-current-development-plan.md)의 전체 범위를 유지한다. 이번에 수행하지 않은 공유 오디오 가져오기, 오토메이션·편곡 대안의 연속 편집, 영상 동기·실제 입출력·청취는 별도 검증이 필요하다. f0r h3r의 실제 곡 제작·음색 품질·아티스트 검토 역시 authored QA 프로젝트의 PCM 일치로 대체하지 않는다. 다음 작업은 확인된 원본 복원 후 복귀 문제를 해결하면서 한 곡 제작 동선을 계속 이어간다.
