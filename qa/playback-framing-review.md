# 재생 화면과 편집 진입 · 0.20.0 build 24

2026-09-08, macOS 26.5.1 / Apple Silicon. 기준 `0e2e422`, branch `codex/daw-integration`. 섹션 진입과 재생 팔로우의 관심 범위를 실제 자식 서클로 바꾸고 이름표 간섭과 수동 확대 취소를 수정했다. [UX/실행 계약](../docs/38-playback-framing.md). 이 결과는 개발 체크포인트이며 전체 DAW 출고 판정이 아니다.

## 자동 검사와 패키지

- 최종 source `swift test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`: **231개, 실패 0, 20.166초**. 실제 출력 장치 의존 기존 1개 검사는 제외했다. 새 5개 검사는 실제 scene builder의 두 트랙 freeform, 창/콘솔별 경계, 반복/빈 섹션, 선택 우선 밀집 이름표와 원의 실제 거리 판정을 다룬다. `qa/generated/framing/exact-final-swift-tests.log`.
- `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`: **26개, 실패 0**. `exact-final-python-tests.log`. MCP/음악 schema와 kit 버전 0.20.0 계약은 유지했다.
- 최종 release build **성공, 23.67초**, `final-release.log`. QA 앱 UUID **`9F368D1F-758A-3D93-8777-5F8AB4D726A6`**, bundle `com.circlr.integrationqa`. 같은 release와 37개 파일 기반 Mach-O section의 SHA-256 일치, ad-hoc signature, kit 25개 파일 hash를 확인했다. 서명은 Mach-O 헤더/서명 영역을 바꾸므로 전체 binary byte 일치로 검사하지 않는다.
- 실행 앱은 `qa/generated/framing/final/써클러 통합 검증.app`. 최초/중간 후보도 별도 경로에 보존했다. 검증 중 마지막 앱 하나만 같은 socket을 사용했다. `final-package.json`, `package-verification.json`.

## Native 시나리오

별도 `~/Library/Application Support/circlr-integration-qa/fixtures/framing.circlr`, project `242F93A7-E838-56BB-8D5C-DB7DD2482BF2`를 사용했다. 기존 통합 fixture에서 복사한 두 authored tone과 3음 MIDI/EP 트랙이며 음악 품질 평가용 곡이 아니다. `verify-framing-native.py`는 정확한 bundle/version/경로/project와 입력 idle을 확인한다. 녹음이나 출력 장치 설정은 실행하지 않았다.

네 화면은 실제 재생 중 `animated=true`, `windowOccluded=false`, `follow=following`인 JSON과 screenshot으로 확인했다. 표의 크기는 AppKit canvas 기준이며 전체 창은 큰 화면에서 1440×900, 작은 화면은 폭 1024·높이 약 772다. 창은 macOS UI의 edge drag로 조정했다.

| 상태 | Canvas | Workspace | 최소 원 반지름 | 표시 이름 |
|---|---|---|---|---|
| 큰 창·콘솔 열림 | 1440×801 | 1392×498.5 | 59.79 pt | 8/8 |
| 큰 창·콘솔 닫힘 | 1440×801 | 1392×665 | 79.50 pt | 8/8 |
| 작은 창·콘솔 닫힘 | 1024×673 | 976×537 | 53.66 pt | 8/8 |
| 작은 창·콘솔 열림 | 1024×673 | 976×370.5 | 41.50 pt | 8/8 |

`large-open.json`, `large-closed.json`, `small-closed.json`, `small-open.json`과 대응 PNG를 확인했다(큰 창 열림 PNG는 `large-open-final.png`). 모든 이름표가 workspace 안에 있고 다른 이름표와 겹치지 않으며 다른 작업 원과 4pt 이상 떨어져 있다. 소리가 커졌다는 이유로 카메라나 이름표 순서를 바꾸지 않는다. 부모 궤도 일부는 화면 밖으로 이어지며 기존 상단 문구가 섹션·마디·반복을 표시한다.

- **재생 중 편집**: MIDI AX 활성화 후 `playing=true`, `follow=suspended`, 편집기 폭 1040 (`editing-live.json/png`). 최종 원래 반복으로 복원한 음악에서 MIDI 이름표를 pointer로 더블클릭한 경우도 27.8756초에 재생 중이며 같은 MIDI 편집기 폭 964.288 (`pointer-editing-live.json`). 노트 수를 바꾸지 않았다.
- **휠과 재개**: 빈 캔버스에서 일반 휠 up 후 zoom 19.213→27.264, 재생 유지·follow suspended (`wheel-suspended.json`). 현재 AX에서 식별한 재개 버튼으로 following 복귀, editor 닫힘 (`resumed.json`). 콘솔 단축키/창 조절 과정에서 수동 입력으로 follow가 중단된 경우 재개한 뒤 네 framing 결과를 기록했다. 자동 resize만으로 follow가 유지된다는 검증으로 간주하지 않는다.
- **정지 상태 섹션 진입**: MCP focus로 같은 native 카메라 경로를 호출해 내부 서클 맞춤을 확인했다. `large-open-stopped.json`, `large-closed-stopped.json/png`는 canvas 폭 1080이며 파일 이름을 1440 근거로 사용하지 않는다.
- **복원·재열기**: 연속 QA를 위해 사본 repeat를 1→8로 변경(r14→15), 정지 후 한 번 Undo해 1로 복원(r16). 이전 창 크기 조절 시도 중 출력 서클 x가 410→768로 이동한 상태를 발견했다. 저장한 사본을 로컬 증거로 보존하고 정확한 한 좌표를 기준값으로 복원한 뒤 앱의 open job `96096536-44EC-40F9-9ADC-9EF4012A4664`로 재열기 completed를 확인했다. 네 화면 표는 x=768인 더 넓은 QA 배치이며 복원 후 pointer 검사는 x=410이다. 두 상태를 혼동하지 않는다.
- `final-save.json`의 tracks/sections/arrangements(모든 note·graph·노드 위치 포함)/assets/portLayout이 `before-revised-app.json`과 완전히 일치한다. 음악 revision만 단조 증가 r14→16, port layout r4 유지. UI camera/창 크기는 마지막 작업 상태로 저장한다. 최종 transport 정지·recording idle이다.

`python3 qa/check-framing-evidence.py`가 네 화면의 실제 원/이름 주소 일치·경계·충돌·실재생, AX/pointer 편집과 wheel/resume, 저장 음악/위치 복원을 검사해 **통과**했다. 산출물 `verification.json`. Native 증거는 로컬 전용 `qa/generated/framing/`에 두며 Git에는 코드·검사기·문서만 포함한다.

## 검토와 남은 조건

같은 실행자의 읽기 전용 코드 검토에서 새 변경에 대한 출고를 막는 결함은 발견하지 않았다. finite/빈 경계, 접힌 그룹, 화면 padding 중복, label draw/hit 공유, 수동 follow 변경과 SwiftUI animation 취소 순서를 대조했다. Python helper는 고정 QA 대상·기존 파일 보존·선언된 tone checksum·쓰기 revision 경계를 검토했다. 독립 리뷰 dispatch는 `agent thread limit reached`로 실패했으므로 서브 에이전트 검토로 계산하지 않는다.

초기 출력 연결은 여전히 지연될 수 있다. 중간 후보의 프로세스 sample은 `AVAudioEngine.mainMixerNode → GetOutputNode → AudioComponentInstanceNew → HALC_ProxyObject.HasProperty → mach_msg2_trap`에서 대기했다(`output-wait-sample.txt`). 메인 UI는 응답했고 최종 프로세스는 이후 같은 연결 작업으로 출력 준비를 마쳐 재생했다. timeout만으로 연결 작업을 반복 생성하거나 시스템 장치를 바꾸지 않았다. 이 UI 수정이 HAL 지연을 해결했다는 주장은 하지 않는다.

실제 마이크 입력/장치 변경·VoiceOver 발화·궤도 모드 및 펼친 그룹/긴 이름/다수 섹션·시간 손잡이 전체 조합·기존 v4 음악/MP4 통합은 후속이다. 큰 프로젝트의 60fps 성능을 이번 8개 서클 fixture로 일반화하지 않는다. 다음 순서는 [로드맵](../docs/25-development-roadmap.md)의 최초 출력 상태 계측 → 남은 UI 조합 → 공통 import/로컬 라이브러리다.

기존 통합 `studio.circlr` manifest SHA-256 **`12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`** 유지. 사용자 `dist/써클러.app`은 **0.19.0 build 21**, UUID **`96FDDF3A-D327-3708-80BF-CCF68B31B6F1`** 유지. 전체 목표는 progress다.
