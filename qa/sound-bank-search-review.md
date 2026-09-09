# Sound Bank 이름·변형 검색 검증 — build 61

2026-09-09, `codex/daw-integration`, 기준 `856d18ed5da7693167231ce40551954cee528d59`. 최종 독립 코드 검토 agent를 실제 호출했으나 `agent thread limit reached`로 거절됐다. 동일 실행자가 구현 → 읽기 전용 코드/입력 경계 검토 → QA를 순차 수행했다. 독립 agent 승인을 주장하지 않는다.

## 자동 검사와 패키지

- 관련 SoundSelection/SoundBankPreset/SoundBankCatalog 16개, 실패 0, 0.008초. 전체 `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`: 445개, 실패 0, 26.177초. 기존 HAL 환경 문제의 물리 playback test 한 항목은 제외했다.
- `python3 -m unittest mcp.test_server qa.test_agent_kit`: 26개, 실패 0, 0.224초. 로그는 `.build/bank-search-{targeted,tests,python}.log`다.
- 최초 release 65.40초, UUID `33501473-0A73-3331-A17B-0251E605D6C1`. native 가시성 결함을 수정한 최종 release 37.27초, UUID `54B8F30D-ABD1-33BB-91E6-1C91D57A1323`. 최종 QA 앱은 `qa/generated/sound-bank-search/final/써클러 통합 검증.app`, 0.20.0 build61이다.
- 최종 제품 소스 11개 hash, Mach-O file-backed section 37개, Codex kit 25개 hash, strict codesign을 비교했다. 전체 테스트 후 제품에서 바뀐 파일은 세 Text의 세로 압축을 고친 SoundPickerView.swift 하나이며 최종 release와 native 화면으로 다시 확인했다. Core/Audio 변경은 없다.

## 실제 목록과 선택

`CopyInstrumentInfoFromSoundBank`가 이 Mac의 `gs_instruments.dls`에서 235개를 반환했다. 기본 멜로디 128개, 변형 멜로디 98개, 드럼 킷 9개다. 은행 SHA는 `739d277474bddeb120372625b70c83c653faaee44de26c3191848cc6c64bfb74`다. 총 악기 검색 결과는 신스 10개·Sound Bank 235개·설치된 AU 악기 9개 = 254개다. 이 수치는 이 Mac의 실측이며 제품에 고정하지 않는다.

SDK API 설명에는 melodic/percussion MSB가 뒤바뀐 문장이 있다. 실제 `AudioUnitProperties.h` 상수와 metadata를 대조해 melodic 121, percussion 120을 사용했다. metadata 테스트는 모든 발견 항목의 program/MSB/LSB와 renderer에 넘기는 주소를 비교한다. 실제 sampler instantiate·청취를 대신하는 검사는 아니다.

원본 studio.circlr에서 만든 3트랙·2 authored audio asset·2 section use 사본을 사용했다. EP의 수정된 cutoff 731과 전체 patch를 보존 기준으로 삼았다. 캔버스/콘솔을 연 1024px 창에서 검색 입력·행 클릭·↑↓/Return/Esc·Undo/Redo·재실행을 확인했다.

| 경로 | 결과 |
|---|---|
| 분해형 한글 피아노 · 전각 #５ | 계열 21개, 표시 번호 #5의 실제 기본/변형 4개만 표시 |
| Detuned EP 1 (#5, LSB8) → 같은 항목 | r15 적용 후 재선택 r15 유지, manifest 전체 일치 |
| E.Piano 1v (#5, LSB16) → Undo → Redo | r16 → r17의 LSB8 → r18의 LSB16, 비활성 설정/다른 트랙/사용 보존 |
| 드럼 킷 → #26 | 9개 킷 중 TR-808만 검색, r19에서 program25/drums=true/기본 LSB0 적용 |
| 드럼 필터 #128 → 멜로디 | 드럼 0개, 멜로디의 #128 변형 4개. Gun Shot 선택 r20, drums=false/기본 LSB0 |
| #1 → 현재 음색 찾기 | 정확히 program0의 4개만 검색. 찾기로 전체 254개와 현재 Gun Shot 위치 복원 |
| rename + 잘못된 bankLSB128의 MCP apply | 전체 transaction 거절, 이름/음악/manifest/revision r20 유지 |
| 검색 중 외부 rename → Return | r21 유지, 기존 Gun Shot 보존, 결과 비활성·충돌 안내 |
| 기존 EP로 복귀 | r23에서 cutoff731 포함 전체 patch 복원, 비활성 program127 유지 |
| E.Piano 1v 검색·저장·종료·재열기 | r24 manifest 전체 일치, 실제 이름·#5·변형16·현재 선택 복원 |
| 최종 앱 정상·외부 변경 화면 | 적용 대상/모든 섹션 범위·현재 음색·충돌 안내 가시성 확인, r25의 외부 이름 변경 외 음악 보존. 최종 원래 이름 복원/저장 r26 |

최초 패키지는 AX에 적용 대상 Text가 있어도 실제 화면에서 세로로 압축되어 보이지 않았다. 대상·현재 음색·상태 Text에 세로 크기를 보존한 최종 패키지로 정상/충돌 화면을 재검증했다. `final-layout.jpg`, `final-stale-layout.jpg`와 AX를 함께 확인했다.

`qa/check-sound-bank-search-evidence.py`는 native 상태 16개·AX/JPEG 18쌍, 원래 fixture/최종 저장값, 각 상태의 변경 instrument 외 전체 문서 동등성, 최종 source/app/kit와 프로세스 종료를 검사한다. #1 검사에서 현재 음색 헤더의 #128까지 결과로 간주한 QA assertion을 발견해 실제 Sound Bank 결과 행 4개만 검사하도록 고쳤다. 제품 검색 결과는 정상이며 최종 checker는 통과했다. 생성 evidence·앱·은행 metadata·음원은 Git에서 제외한다.

## 코드와 입력 경계 검토

optional bankLSB의 생략/null은 이전 뱅크 0이며 기존 JSON을 읽을 수 있다. 0–127 범위를 Core 문서 검증과 로더 경계에서 검사하고 UInt8 clamping으로 잘못된 값을 다른 음색으로 바꾸지 않는다. 프로그램 번호와 드럼 여부·LSB 전체가 선택 ID다. 같은 선택은 전체 instrument를 반환하며 변경도 비활성 synth/plugin/sample을 보존한다. 새 변형이 저장된 곡은 build61 이상에서 열어야 하며 과거 앱과의 변형 재생 호환을 주장하지 않는다.

metadata는 Copy API 소유권에 따라 takeRetainedValue로 회수하고 장치/Audio Unit을 시작하지 않는다. 문자열/번호 검색은 메모리 내 연산이며 shell·네트워크·새 파일 업로드 경로가 없다. 실제 고정 시스템 bank 경로만 읽는다. 잘못된 metadata를 가짜 preset으로 채우지 않는다. UI는 기존 프로젝트·revision·세션·선택/원본 범위·녹음/준비/import guard를 통과한 뒤 한 transaction으로 적용한다. MCP 전체 instrument 교체 의미는 기존대로이며 [계약](../docs/17-agent-interface.md)에 보존 방법을 명시했다. 최종 검토에서 남은 차단 결함은 발견하지 않았다.

원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱 0.19.0 build21 보존. 등록 라이브러리 1개 유지, owned QA 프로세스 0. 모든 native capture에서 output/audition attempts 0, 재생·녹음 없음. 실제 음질·물리 I/O·VoiceOver 전체 사용·모든 DAW 기능의 출고 검증은 남아 있다.
