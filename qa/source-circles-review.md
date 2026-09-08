# build 27 · 소스별 서클과 직접 이펙트 검증

2026-09-08, `codex/daw-integration`, 기준 `67415dc`. 새 오디오의 빈 MIDI/악기와 편집 이동 깊이를 줄인 progress다. 전체 DAW 개발 또는 E 출고 완료 판정은 아니다.

## 자동 검사와 패키지

- Swift **253개, 실패 0, 22.684초**: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 기존 실제 출력 장치 의존 검사 한 개를 제외한 전체 테스트다. `qa/generated/source-circles/swift-tests.log`.
- 새 Core **5개**: audio-only의 4개 논리/3개 표시 노드, 오디오 기본 탐색, 첫 MIDI 경로, 기존 끊김과 위치 보존, 후속 audio 편집/삭제 노드 비복원, 빈 MIDI 생성, rhythm idempotency·오류 atomicity, 출력 앞 fan-in gain·다른 출력 보존.
- 새 Audio **3개**: legacy 전체 그래프와 Low-pass 뒤 PCM 완전 일치·portable save/reload, 음소거한 오디오 lane에 첫 MIDI/리듬만으로 발음, 출력 Gain 0.5 적용 시 해당 stem만 정확히 절반이고 다른 stem은 동일함.
- Python MCP/키트 **26개**, `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`. 새 QA helper 세 개의 `py_compile`도 통과했다.
- Release **48.15초**, `.build/integration-release/release/circlr`. 최종 전용 앱 `qa/generated/source-circles/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build 27, UUID **`543B4F72-09DA-341A-8A18-7DB330F24AB4`**.
- `python3 qa/check-source-evidence.py`: 기록 14개·Undo 전이 6개·WAV hash·source/package Mach-O 파일 기반 section **37개** 일치, kit **25개** hash·signature·원본 fixture manifest 불변을 검사했다. `verification.json` 결과 passed.

## Native 확인

`prepare-source-qa.py`로 기존 authored 톤 두 개만 새 `fixtures/source-circles.circlr`에 복사했다. 프로젝트 ID는 `05E5B1C1-1769-5CD0-BE42-0AB73F9D777D`다. 정확한 QA Unix socket, bundle/version, project/path, 녹음 idle을 검사한 helper만 사용했다. 화면은 최소 폭 **1024**, canvas **1024×673**, 콘솔 열림 상태다. 실제 마이크 수집이나 장치 설정 변경은 하지 않았다.

| 시나리오 | 관찰·근거 |
|---|---|
| 두 오디오 가져오기 | ⌘I→두 파일→Return. tracks/assets +2, music r14→15. 논리 노드 +8 중 오디오·믹스·출력이 각각 2개, 비활성 rhythmAudio 2개. 새 MIDI·악기·rhythmMIDI 없음. 실제 표시 노드 +6. `before/batch.json`, `batch.png` |
| 기존 배치·곡 보존 | section 정의·portLayout·기존 signal/master 위치·기존 use graph 위치 동일. 선택은 section이고 editorAddress=null. `batch.json` |
| 기본 오디오 진입 | ⌘J에서 tone-1 검색→Return. 오디오 파형 편집기와 오디오/믹스/출력 경로 표시. `search-ax.txt`, `audio-ax.txt`, `audio.png` |
| 오디오 뒤 효과 | 편집기 이펙트 추가→Low-pass. 오디오→Low-pass→기존 mix로 변경하고 다른 edge 유지. 자동으로 효과 편집 진입. `audio-effect.json/png` |
| ⌘1 복귀 | Low-pass 편집에서 ⌘1로 동일 tone-1 오디오 편집 복귀. `shortcut-audio-ax.txt` |
| 출력 앞 효과 | 경로의 출력→이펙트 추가→Gain. 해당 mix→Gain→출력만 변경, 기존 edge ID/gain 유지. 원본 section·다른 트랙/자산 불변. `output-ax.txt`, `output-effect.json` |
| 명시적 리듬 | tone-1 선택→⇧⌘P→이 섹션의 리듬 패턴 만들기. 선택 트랙의 rhythmMIDI→instrument→mix 생성, 스텝 편집 표시. 첫 셀 클릭으로 B4/0 beat/0.225 길이/velocity96 노트 1개. `pattern-command-ax.txt`, `pattern/pattern-note.json`, `pattern-note.png` |
| 첫 MIDI 입력 | 다른 imported tone-2 lane에 MCP `set_notes` 한 노트(F♯4, beat2, length0.75, velocity88). 기존 오디오를 유지하며 MIDI→instrument→mix 경로 생성. 정확한 MIDI node에 focus 후 실제 스텝 표시 확인. `midi.json`, `midi-ax.txt/png` |
| 오프라인 WAV | 실제 앱의 MCP export completed. **34초·48 kHz·스테레오·24-bit**, peak **0.1988108158**, SHA256 `ec043d9329e067745eaaf0af4aab7cc9104c73dbcb425319d0d19f1037bc0d31`. `export-job/export-audio.json`, `source-workflow.wav`. 실제 출력 장치를 여는 재생/청감 검증과 구분한다 |
| 각각의 Undo | 실제 ⌘Z를 한 번씩 총 6회: MIDI→스텝→리듬 생성→출력 효과→오디오 효과→두 파일 추가. 매 단계 저장한 name/tracks/assets/sections/arrangements/signal/patterns/portLayout이 각각 대응하는 이전 상태와 완전 일치. `undo-*.json`, `restored.json` |
| 저장/재열기 | 초기 QA 음악으로 저장→같은 파일 open 완료, r26, dirty=false. `reopened.json`. 원본 studio fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 유지 |

로컬 캡처·manifest·로그·WAV·프로젝트·앱은 `qa/generated/source-circles`와 QA Application Support에만 보관하며 Git 업로드에서 제외한다. JSON job 응답은 `job.state` 아래의 완료 상태를 검사했다. 첫 검사 스크립트가 이를 최상위로 읽어 실패했으며, 응답을 수정해 파일 결과와 함께 검증했다.

## 코드 검토와 범위

동일 실행자가 read-only 코드/보안 검토 역할로 factory·setLane·명시적 rhythm·효과 삽입·SwiftUI 메뉴·테스트를 대조했다. 이전 독립 spawn이 실제 `agent thread limit reached`로 거절된 상태이므로 독립 서브 에이전트 리뷰로 세지 않는다.

- Migration factory는 `includeMIDI=true`를 기본으로 두어 기존 문서 마이그레이션을 유지한다. audio-only 신규 lane만 제외 경로를 사용한다. 첫 노트 추가를 별도 신규 source로 인식하되 기존 노트가 있던 사용자가 삭제한 MIDI 노드는 오디오 편집으로 복원하지 않는다.
- 새 source만 기본 연결을 만들고 이미 있는 source의 끊긴 route를 연결하지 않는다. 기존 좌표를 그대로 두고 새 노드끼리도 180 미만 거리 충돌을 피한다. 새 track은 기존 master 위치를 보존한다.
- 명시적 pattern 생성은 같은 mutation 안에서 rhythmMIDI/악기를 준비한다. 효과 삽입은 candidate graph를 검증한 후 적용하므로 실패 시 부분 변경하지 않는다. 출력의 기존 incoming gain/ID를 유지하고 새 링크는 unity다.
- 직접 효과 메뉴는 단일 오디오 출력 또는 트랙 출력에만 제공한다. 다중 bus는 명시적 포트 경로를 사용한다. Section에서 독립 effect를 추가할 때 다른 트랙의 첫 mix를 임의로 변경하지 않는다.
- 인증·외부 전송·미디어 입출력 권한을 추가하지 않았다. native 작업은 별도 QA 프로젝트에 한정했고 본래 사용자 앱·다른 검증 앱은 교체하지 않았다.

기존 문서의 빈 MIDI/악기는 보존한다. 모든 궤도·긴 이름·그룹 밀집 조합, 실제 VoiceOver·마이크·HAL 지연 해결·출고용 MP4 동기는 기존 E gate에 남아 있다. Finder 실제 file-URL 드래그·Splice file promise, CC/tempo map·중복 자산/GC는 후속이다. 패키징/검증한 개발 앱이 사용자 0.19 앱을 대체한 것은 아니다.
