# DAW 통합 · 0.20.0 build 23 검증

2026-09-08, macOS 26.5.1 / Apple Silicon. `codex/daw-integration`에서 포트 `1d304eb`와 녹음 `d88ea5d`를 합쳤다. 사용 앱은 0.19.0이며 이 문서는 통합 QA 체크포인트다. 전체 DAW 완료나 출고 판정이 아니다.

실제 런타임은 root 포함 1슬롯이다. development-lead → Swift/Python 구현 → 같은 실행자의 읽기 전용 코드·보안 검토 → QA 순서이며 독립 서브 에이전트 리뷰로 계산하지 않는다. [실행 계약](../docs/37-daw-integration.md).

## 빌드와 자동 검사

- `swift test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`: **226개, 실패 0**, 19.742초. 실제 출력 장치에 의존하는 기존 1개 검사는 제외했다. 로그: `qa/generated/integration/final-swift-tests.log`.
- `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`: **26개, 실패 0**. MCP 17개·kit 9개. 22개 도구와 읽기 전용 specialist의 변경 거절, adapter·operations·25개 파일 hash 계약을 검사한다. 로그: `final-python-tests.log`.
- `swift build -c release --scratch-path .build/integration-release`: **성공, 47.99초**. 로그: `merge-release.log`. 동일 release binary의 전용 앱 UUID: `D2205ECB-AA68-3B75-BCC0-A9128ABA2FE5`.
- 새 `RecordingRoundTripTests.testTakeFinalizationPreservesRouterGroupAndLayoutUndo`는 제어된 WAV를 take로 추가한 후 router의 명시적 bus·그룹 binding·layout Undo의 take 보존·프로젝트 저장/재열기·양 채널 PCM 정확 일치를 검사한다. 기존 controlled CAF → take → embedded 프로젝트 → WAV bounce 왕복 검사도 함께 통과했다. 실제 입력 장치를 연 검사는 아니다.

## Native 환경과 결과

앱은 `qa/generated/integration/써클러 통합 검증.app`, bundle ID `com.circlr.integrationqa`다. 저장소/socket은 `~/Library/Application Support/circlr-integration-qa`로 분리했다. `qa/prepare-integration-qa.py`는 기존 대상이 있으면 거절하며 두 개의 직접 작성한 tone을 가진 port QA fixture만 복사한다. 원본 manifest hash는 전후 동일했고 내장 kit hash·adapter byte 일치 및 ad-hoc signature를 확인했다.

프로젝트 `B29AF867-91DE-55DB-9958-EC7EFCF0ADDF`, `fixtures/studio.circlr`. Native 증거는 모두 `qa/generated/integration/` 아래 로컬 전용이며 Git에는 포함하지 않는다. `qa/verify-integration-native.py`는 bundle·version·프로젝트 경로/ID·입력 미진행을 확인한다. 아래 조작은 이 프로젝트에서만 실행했다.

| 시나리오 | 결과와 증거 |
|---|---|
| 입력 없이 녹음 대상 guard | 앨범 선택 상태의 `record`를 녹음 대상 부재로 거절. 권한 요청·마이크 수집을 시작하지 않았고 recording은 idle. `mixed-midi-layout.json` |
| MIDI 추가와 배치 Undo | 3음 MIDI/EP 트랙 추가 후 port 방향 변경과 Undo. MIDI/graph/binding 유지, music r2·layout r2. 같은 파일 저장. `mixed-midi-layout.json` |
| 키보드 스텝 입력 | ⌘4 → Return으로 선택 셀 note 추가(r3), ⌘Z로 원래 3음 복원(r4), ⌘2로 음색 전환. `step-entered.json/png` |
| 오토메이션 | ⌘5 → Return으로 gain 점 추가(r5), Right로 0.25박 이동(r6). ⌘Z 두 번으로 0박(r7)·빈 곡선(r8) 순서 복원. `automation-edited.json/png`, `automation-undo-one.json`, `automation-undone.json` |
| 오디오 분할 | 같은 캔버스의 오디오 파형에서 ⌘T로 32초를 16초씩 분할(r9), ⌘Z로 음악/그룹 원상 복원(r10). `audio-split.json/png`, `audio-bounce-roundtrip-v2.json` |
| 페이드와 바운스 | MCP로 fade 0.02/0.04초 적용(r11) 후 Undo(r12), 새 EP 트랙 bounce(r13). 출력은 **48 kHz·24-bit stereo·1,632,000 frames·34초**(32초 본문+2초 tail). Undo(r14)와 재열기 후 sections/tracks/uses/portLayout이 기준과 일치. `audio-bounce-roundtrip-v2.json` |
| 그룹 UI 공존 | 연결 편집기 안에서 녹음 버튼·그룹 IN/OUT 3개·포트 관리 접근 확인. 출력 이름 변경과 ⌘Z는 music r14를 유지하고 layout만 r3→r4. `group-connections.png`, `group-alias-renamed.json`, `group-alias-undone.json` |
| 닫기와 백그라운드 연결 | 현재 AX에서 식별한 닫기 버튼을 누르면 `minimized=true`, `visible=false`이며 MCP snapshot은 계속 응답. `focus minimized=false`로 복귀. `close-minimized-v2.json` |
| 실제 출력별 모션 | 전면 유지 상태에서 0.906–9.973초 **10개 표본 모두 animated=true·windowOccluded=false**. OUT1 edge `A885…`와 OUT2 `B6E3…`/IN2 `FB4E…`가 4초 간격으로 바뀌고 group level은 0.039978. MIDI·악기 경로도 별도 level을 반환. 마지막 stop과 입력 idle 확인. `integrated-unoccluded-playback.json`, 실제 화면 `integrated-visible-playback.png` |

Bounce job `1A7CEB34-3B31-4387-9576-297FC979D922`, 재열기 job `79844116-C83A-46BD-BF51-98F0D7AD92A6`은 모두 completed다. 바운스 후 Undo는 원래 음악을 복원하며 실제 생성한 WAV의 음질/발매 품질 평가를 뜻하지 않는다.

초기 검증 script의 `graphOverride` 필드 가정과 오래된 AX 번호 사용은 검사 도구의 오류였다. 실제 `graphEdits`/음악 객체와 새 AX 식별자로 다시 대조한 v2 결과를 사용한다. 앞선 실패 파일도 보존했다. 첫 모션 시도는 창이 다른 앱에 가려져 기존 절전 정책으로 frame 갱신을 멈췄다. 전면 유지 재검사의 10개 표본을 모션 근거로 삼는다.

## 검토와 보존

- 충돌 해결은 record와 port dispatch, layout/music Undo, 연결 편집과 녹음 상태, scalar JSON·layout revision을 모두 유지했다. MainActor에서 busy 검사 이후 편집 전까지 await가 없고, 테이크 종료는 recorder의 idle 상태 통지 후 같은 callback에서 삽입한다. 시작/정리 중 음악 편집·Undo 경쟁을 막도록 공통 guard를 보완했다.
- 로컬 MCP socket과 read-only 정책을 유지한다. `record`는 도구 계약에 사용자 입력 녹음 요청과 busy 상태 확인을 요구한다. 미선택 guard 검증 외 실제 호출로 입력을 시작하지 않았다. 리소스에 credential·계정 token을 추가하지 않았다.
- `Playback.seconds`는 실제 D2 첫 표본의 -0.02325초를 근거로 장치 시각을 시작 위치 아래로 내려가지 않게 제한했다. 출력 연결 timeout 로직이나 시스템 출력 장치는 바꾸지 않았다.
- 기존 root/ports worktree는 각 기준 commit을 유지했다. `dist/써클러.app`은 0.19.0, UUID `96FDDF3A-D327-3708-80BF-CCF68B31B6F1` 그대로다. 승인된 private 소스·문서·검사 범위만 push한다.

## 남은 범위와 다음 UI 개선

실제 마이크 capture·취소·장치 변경·종료/복구, VoiceOver 발화, 모든 MIDI/sidechain/송폼·밀집 pointer 조합, 기존 v4 음악과 MP4의 통합 회귀는 남아 있다. 이전 D2 앱의 cold start timeout은 이후 재생 성공만으로 원인이 해결됐다고 주장하지 않는다.

현재 실제 재생 화면에서는 부모 궤도를 맞출 때 자식 서클이 작게 모이고 라벨이 겹친다. 다음 UI slice에서 follow의 관심 범위·라벨 우선순위·편집 진입을 개선하고 작은 창/콘솔 상태별로 확인한다. 이 관찰을 새로운 패널이나 음악 시간/노드 위치 변경으로 해결하지 않는다.
