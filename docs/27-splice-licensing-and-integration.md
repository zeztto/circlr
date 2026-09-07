# Splice 라이선스와 써클러 연동

확인일: 2026-09-08. 약관의 최종 갱신일은 2026-07-24이며, 아래 판단은 해당 공개 약관과 공식 지원 문서에 따른다. Splice와 별도 계약을 체결하거나 지원팀의 유권 해석을 받은 상태는 아니다.

## 데모의 배포 조건

| 사용 형태 | 확인 결과 | 써클러 결정 |
|---|---|---|
| 본인의 구매·라이선스 샘플로 로컬 곡 작업 | 허용된 음악 제작 범위 | 기존 v1/v2 보존 |
| 샘플을 다른 소리와 결합한 완성 WAV·음악 영상 | New Recording / Creative Work로 상업·비상업 사용 가능 | 완성 음원 사용과 샘플 재배포를 구분 |
| 원본 WAV가 들어 있는 누구나 편집 가능한 앱 튜토리얼 프로젝트 | 독립 샘플 재사용·재배포를 허용받았다고 볼 근거 없음 | Splice 원본을 포함해 배포하지 않음 |
| 샘플의 가공·바운스·파일명 변경 후 원샷 라이브러리로 배포 | 수정해도 독립 샘플 재라이선스 금지 적용 | 우회 방식으로 사용하지 않음 |

공식 [약관 §II.3.1.1.1–3](https://splice.com/terms)은 완성 음악 사용을 허용하면서 독립 샘플의 재라이선스와 샘플 팩 재배포를 제한한다. [Licensing FAQ](https://support.splice.com/en/articles/8652642-splice-sounds-licensing-faq)도 이를 확인한다. Royalty-free는 추가 royalty 없이 정해진 범위로 쓸 수 있다는 의미이며 원본 파일을 아무에게나 배포할 권리를 뜻하지 않는다.

약관이 모든 DAW 프로젝트 공유를 일률적으로 금지한다고 해석하지는 않는다. 이번 판단의 대상은 사용자 자신의 작업 파일이나 개별 협업 계약이 아니라 **써클러를 받는 불특정 사용자가 샘플을 추출·재사용할 수 있는 튜토리얼 배포물**이다. 이 형태는 위 독립 샘플 제한에 걸릴 수 있으므로 별도 허락 없이 동봉하지 않는다. 저장소가 private라는 사실만으로 샘플 사용권이 다른 사람에게 이전되지도 않는다.

기존 Splice 사용곡을 발매할 때는 계정의 Your Sounds에서 사용하는 샘플의 certified license를 발급받아 보관할 수 있다. 발급에는 법적 이름 등이 필요하므로 이번 작업에서 임의 입력·발급하지 않았다. 새 구매와 credits 사용은 없다.

## 실제 교체 결과

배포용 **f0r h3r v3**의 외부 미디어 6개를 FreePats synthesizer percussion 2022-07-18로 교체했다. 제공자 Roberto는 Yoshimi·Geonkick으로 만든 이 은행을 CC0로 공개한다. [공식 배포 페이지](https://freepats.zenvoid.org/Percussion/electric-percussion.html), [CC0 설명](https://creativecommons.org/publicdomain/zero/1.0/).

| 용도 | 사용한 CC0 원본 |
|---|---|
| 킥 | Kick04.wav |
| 스네어 | Snare14.wav |
| 하이햇 | ClosedHiHat01-01.wav |
| 셰이커 | ShakerLong01.wav |
| 탐 | HighTom02-01.wav |
| 전환 | Cymbal01-01.wav |

20Hz DC 제거, 필터 안정화용 100ms tail, 선형 peak trim을 적용했다. 전환은 기존 wave FX 대신 synth cymbal을 사용한다. MIDI·화성·68마디 송폼과 내부 신스/이펙트/킥 sidechain을 유지하고 마스터 헤드룸을 다시 계산했다. 가공 내역·원본/출력 hash·출처는 v3의 `sample-license/manifest.json`과 `production-report.json`에 들어 있다.

CC0는 저작권·관련 권리를 가능한 범위에서 포기하고 복제·수정·상업적 배포를 허용한다. 이 근거로 원샷을 프로젝트에 포함할 수 있다. 출처와 CC0 원문도 함께 보관한다. **곡 전체가 CC0라는 뜻은 아니며** CC0 선언은 교체한 FreePats 샘플에 적용한다. FreePats의 제품 보증이나 써클러 후원을 표시하지 않는다.

무료 다운로드 후보였던 [Wavparty](https://wavparty.com/license/)와 [SampleRadar](https://www.musicradar.com/news/tech/free-music-samples-royalty-free-loops-hits-and-multis-to-download-sampleradar)는 원본 재배포 제한 때문에 선택하지 않았다.

## Splice를 써클러에서 이용하는 경로

| 경로 | 공식 제공 범위 | 현재 써클러 상태 |
|---|---|---|
| 로컬 Splice 폴더에서 가져오기 | 다운로드한 샘플은 실제 로컬 파일 | 섹션 선택 → ⌘I → 샘플 파일 선택 가능 |
| Splice Desktop에서 파일 드래그 | 다른 DAW로 drag/drop 지원 | 캔버스의 외부 파일 drop 수신은 아직 없음 |
| Splice Sounds AU | 앱 안 검색·라이선스·라이브러리·파일 drag/copy | AU 검색·instantiate·로그인 화면 표시까지 실제 확인 |
| Splice Bridge AU | DAW의 key/tempo에 맞춘 미리 듣기 | 호환 후보, 현재 Mac에 Bridge는 설치되지 않았고 실시간 동기 미검증 |
| DAW 자체 브라우저 통합 | Ableton/Studio Pro/Pro Tools의 공식 통합 사례 | 써클러용 공개 SDK/API 또는 제휴 권한은 확인되지 않음 |

출처: [로컬 다운로드 위치](https://support.splice.com/en/articles/8652631-where-do-my-downloaded-samples-presets-midi-files-go), [Desktop 기능](https://support.splice.com/en/articles/8652657-how-do-i-install-the-splice-desktop-app), [Splice Sounds 시작 안내](https://support.splice.com/en/articles/12997591-getting-started-with-the-splice-sounds-plugin-now-in-beta), [Bridge 호환 안내](https://support.splice.com/en/articles/8652858-will-my-daw-work-with-splice-bridge), [공식 DAW 통합 목록](https://support.splice.com/en/collections/13461538-splice-daw-integrations).

현재 Mac의 `/Library/Audio/Plug-Ins/Components`에서 Splice Sounds 0.12.1 (`aumu`, `Splc`, `Xy8z`)와 Sounds Listener 0.12.1 (`aufx`, `Splc`, `SpC1`), Splice INSTRUMENT를 확인했다. Sounds와 INSTRUMENT는 목적이 다른 제품이다. Sounds가 샘플 탐색기이며 INSTRUMENT는 가상악기다.

실제 QA 앱에서 악기 종류 Audio Unit → Splice Sounds → Plugin 화면으로 **공식 로그인 화면이 나타났다**. 데스크톱 앱 로그인만으로 플러그인까지 로그인된 상태는 아니었다. 브라우저 device authorization 이후의 검색·다운로드·구매, tempo 동기와 미리 듣기는 실행하지 않았다. 로그인 화면의 우측이 현재 고정 편집 영역에 잘리는 문제도 확인했다. 따라서 완전한 연동 완료라고 표시하지 않는다.

[Splice Sounds FAQ](https://support.splice.com/en/articles/12997860-faq-splice-sounds-plugin-now-in-beta)는 AU/VST3를 지원하며 plugin 내 MIDI 파일은 아직 지원하지 않는다고 명시한다. MIDI는 오디오 가져오기와 별도 기능으로 설계해야 한다. 현 써클러는 AU host이며 VST3 host는 아니다.

## 구현 순서와 완료 기준

1. **공통 파일 import 경로** — `AppStore.importAudio`를 파일 선택 UI와 실제 import 명령으로 분리한다. `AlbumCanvas`가 `public.file-url`/file promise를 받아 해당 섹션·현재 박에 오디오 서클을 생성한다. `.wav/.aif` 형식 검사, 여러 파일, 클립 원본 복사, 하나의 Undo, 취소 뒤 늦은 파일 전달을 검증한다. Drop 좌표는 orbit의 시간과 freeform의 공간을 구분한다.
2. **로컬 라이브러리 선택** — 사용자가 지정한 Splice 다운로드 폴더를 읽기 전용으로 색인한다. 기본 `~/Splice` 외의 위치도 지원하고 security-scoped bookmark와 파일 변경 감시를 사용한다. 검색은 파일명·검증된 미디어 메타데이터로 시작하고 `.splice` DB/계정 캐시를 비공식 API처럼 해석하지 않는다. 폴더는 구매 완료된 파일의 보관 위치이며 클라우드 전체 카탈로그가 아니다.
3. **Splice Sounds 전용 브라우저 서클** — DSP 렌더 그래프에 가상악기로 넣기보다 companion AU를 유지하는 도구 서클로 연다. 사용자의 단일 캔버스 원칙에 맞춰 필요할 때만 펼치고 플러그인의 preferred size를 반영한다. `PluginEditorController`의 고정 영역 잘림을 먼저 해결한다. 미리 듣기를 위한 실제 오디오 경로와 host tempo/transport를 연결해야 한다. 지금의 offline-render context만으로는 충분하지 않다.
4. **인증·가져오기 검증** — Splice 공식 브라우저 로그인과 device authorization을 사용한다. 로그인 토큰을 써클러 프로젝트·MCP 로그·Git에 저장하지 않는다. 구매 완료 파일의 drag/copy → 원본 보존 import → 다시 열기까지 검증한다. 구매·credits는 공식 UI와 사용자가 정한 한도 안에서만 처리한다. 플러그인 바이너리를 써클러에 임의 재배포하지 않는다.
5. **파트너 통합 조사** — 자체 카탈로그 UI가 필요해지면 Splice에 SDK 제공, 검색·preview·라이선스·구매 권한, 브랜드 사용·배포 조건을 확인한다. 현재 공식 공개 개발자 API를 확인하지 못했으므로 사설 endpoint·로그인 쿠키·리버스 엔지니어링을 제품 의존성으로 채택하지 않는다. 이번에는 연락이나 계약 요청을 보내지 않았다.

에이전트는 로컬 asset ID와 편집 명령을 다루는 구조를 유지한다. 약관 §3.1.1.3(h)의 AI source/training 제한에 따라 Splice 원음을 외부 생성 모델의 입력·학습 재료로 전달하는 기능은 포함하지 않는다. 공식 Splice 서비스 안의 기능과 써클러가 별도로 제공할 AI 기능의 권한을 혼동하지 않는다.

## 재현과 검증

`scripts/prepare-demo-samples.py`는 약 1.9MB의 공식 archive를 받아 고정 SHA-256을 검사하고 선택한 6개 WAV와 LICENSE/readme만 읽는다. 임의 archive 경로를 디스크에 풀지 않는다. 가공 manifest도 고정 hash로 확인한다. 수정된 기존 파일이나 잘못된 archive는 설치/곡 생성 전에 거부한다.

`circlr-studio make-demo`의 기본 소스를 CC0 세트로 변경했다. v1/v2는 기존 로컬 파일로 남아 있고 새 기본 출력은 [v3](../music/f0r-h3r/v3/README.md)다. 앱 바이너리 버전은 0.13.0 그대로이며 이번 변경은 제작 CLI·샘플 산출물·문서에 한정한다.

배포용 프로젝트 안의 미디어 전부가 고정 CC0 hash 목록과 일치하고, 추가 파일·외부 절대 경로·이전 Splice hash가 없음을 `qa/verify-demo-license.py`로 확인한다. 실제 앱 열기/export와 샘플 정책 검증 기록은 [QA](../qa/0.13-license-review.md)에 있다.
