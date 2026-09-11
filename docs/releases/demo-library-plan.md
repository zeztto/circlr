# 공개 MIDI·스템 데모 라이브러리 계획

상태: **RESEARCHED / PLANNED — 편곡·앱 탑재·청취 검증 전**. 조사일: 2026-09-11.

목표는 실제 편집 가능한 데모 **3~5곡**이다. 0.40.0에서 최소 3곡, 목표 4곡을 시작 화면에 제공하고 0.60.0의 검토 완료된 `f0r h3r`를 다섯 번째 곡으로 추가한다. 아래 4곡은 우선 후보이며 아직 음악 품질이나 앱 호환성을 통과한 선정곡은 아니다. 먼저 한 곡을 끝까지 제작·청취 검토한 뒤 같은 품질 기준으로 확장한다.

English: Plan a library of 3–5 editable demo songs: at least three, targeting four in 0.40.0, followed by the reviewed f0r h3r in 0.60.0. Primary sources below declare Public Domain or CC0 terms. Arrangements, downloaded asset integrity, listening quality and application integration remain unverified.

## 출처와 우선 후보

| ID / 원곡 | 공식 자료·권리 표시 | 서클러 편곡 제안 / 보여줄 기능 |
|---|---|---|
| D01 · Erik Satie — Gymnopédie No. 1 | [Mutopia #37](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=37), Evin Robertson 채보, Public Domain, MIDI·LilyPond | 첫 제작곡. 3박자와 선율을 보존한 ambient 편곡. 건반 선율·베이스·화음 패드·텍스처 4~6파트. 도입→주제 A→변형 A′→대조→재현→종결. 느린 궤도, 섹션 이동·반복과 잔향 연결을 학습한다. |
| D02 · Edvard Grieg — In the Hall of the Mountain King | [Mutopia #1888](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=1888), Grieg 피아노 편곡 / Coyau 채보, Public Domain, MIDI·LilyPond | Nordic synth 편곡. 낮은 pluck·bass·lead·pad·단순 드럼·FX 6~8파트. 동기 제시→레이어 추가→break→확장된 재현→종결. 섹션 use 변형과 음색·다이내믹 증가를 보여준다. 템포 상승은 엔진 지원/QA 확인 후 사용한다. |
| D03 · Claude Debussy — Première Arabesque | [Mutopia #1777](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=1777), Keith OHara 채보, Public Domain, MIDI·LilyPond | 건반·bell/pluck·bass·pad 중심 4~6파트. 주제→전개→대조→재현→coda. 성부와 2:3 리듬 관계를 보존하여 다른 박 분할의 궤도를 보여준다. 모든 음을 단일 16분 그리드로 양자화하지 않는다. |
| D04 · Software-Entwicklungskit — Lithium | [제작자 파일·라이선스](https://github.com/ichbinsoftware/everythingisfree/tree/main/src/2.Lithium), CC0 1.0. 공식 표기 124 BPM / G minor / 38 stems | 오디오+MIDI hybrid 편곡. 드럼·bass·pad·lead/voice·FX를 6~10개 역할 그룹으로 구성하고 필요한 원본 stem은 내부에서 개별 편집 가능하게 보존. 실제 청취로 intro→groove→break→return→outro 경계를 정한다. MIDI 보조 파트·FX send·바운스 전후 비교를 학습한다. |

이 표의 편성·섹션은 **새 편곡 제안**이며 원곡 분석 결과나 MIDI의 실제 marker가 아니다. 정확한 마디·길이·tempo map·성부 수는 원본 악보/MIDI와 청취를 대조해 확정한다. 원곡을 억지로 verse/chorus에 맞추지 않고 주제·전개·재현 같은 이름도 허용한다. 원곡명·작곡자·채보자와 circlr 편곡 크레딧을 구분한다.

직접 MIDI 위치(공식 곡 페이지에서 확인, 파일 bytes/import는 미검증):

- [Gymnopédie No. 1 MIDI](https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/gymnopedie_1.mid)
- [Première Arabesque MIDI](https://www.mutopiaproject.org/ftp/DebussyC/L66/debussy_Arabesque_1/debussy_Arabesque_1.mid)
- [Mountain King MIDI](https://www.mutopiaproject.org/ftp/GriegE/O46/Dans_l_antre_du_roi_de_la_montagne/Dans_l_antre_du_roi_de_la_montagne.mid)

예비 스템 후보: [Foozle / Potriel — Eerie Space Music](https://foozlecc.itch.io/eerie-space-music). 공식 페이지는 두 곡과 stems, CC0, 상업 이용·수정 허용을 명시한다. ZIP 449 MB이며 개별 곡명·BPM·stem 수·음질은 미확인이다. D04가 청취·규모 기준을 통과하지 못할 때 이 팩의 한 곡을 검토한다. 기본 곡 수를 불필요하게 늘리지 않는다.

## 재배포 계약

- 작곡의 권리와 해당 MIDI 채보·편곡·연주 녹음의 권리를 각각 확인한다. 오래된 클래식이라는 이유만으로 임의 사이트의 MIDI나 녹음을 가져오지 않는다.
- [Mutopia 라이선스 안내](https://www.mutopiaproject.org/legal.html)는 개별 Public Domain 기여분의 수정·판매·재배포를 허용한다. 다른 Mutopia 작품에는 CC BY/CC BY-SA가 있으므로 위의 정확한 판본만 기준으로 한다. Public Domain 표시를 임의로 CC0 표시로 바꾸지 않는다.
- Lithium은 제작자가 해당 디렉터리의 raw stems를 CC0로 공개하고 재배포·상업 이용을 명시한다. [CC0 공식 조건](https://creativecommons.org/publicdomain/zero/1.0/)을 함께 보존한다. 단순 무료 다운로드/royalty-free 표시만 있는 파일은 채택하지 않는다.
- 탑재 전에 자산별 원본 URL·수집일·원본 SHA256·판본/commit·라이선스 근거 사본·저작자·수정 내역·파생 파일 SHA256을 manifest와 notices에 기록한다. 저장소 코드 라이선스를 음원에 자동 적용하지 않는다. 번들·공개 저장소·사용자 export에 필요한 출처 안내가 따라가도록 한다.
- 음색의 sample/SoundFont 권리도 별도로 검증한다. 유료 플러그인·개인 Splice 계정·사용자 로컬 경로 없이 작동해야 한다. 채보와 배포 지역의 권리 범위가 불명확한 자산은 대체 후보로 전환한다.

## 제작·통합 순서

1. **D01 한 곡 pilot:** 원본 보존→MIDI 분석→음악적 프레이즈 경계→성부 분리→내장 음색 편곡→믹스·실제 청취→사용자 음악 검토. 이후 D02/D03/D04로 확대한다.
2. 곡 서클 아래 섹션, 그 안에 MIDI/오디오·악기·FX 서클을 구성한다. 반복되는 재료는 공유 원본+use로 재사용하고 변화가 필요한 부분은 명시적으로 독립 변형한다. 섹션 재배치가 무음·음 누락·중복 note-on을 만들지 않게 지속음과 잔향 경계를 정의한다.
3. MIDI 원본, 편곡본, 바운스 오디오의 관계를 보존한다. 전체곡 WAV와 필요한 stem을 앱에서 생성하고, 바운스 전/후가 동시에 울리지 않게 활성 경로를 관리한다. 긴 오디오 하나만 넣은 데모로 완료하지 않는다.
4. Lithium은 공식 WAV 전체가 약 3.44 GB이고 GitHub 목록에는 M4A가 있다. 실제 codec·sample rate·시작 정렬·무음·위상·용량을 검사한 후 사용할 자산을 정한다. M4A를 WAV로 바꾸어 음질이 개선됐다고 하지 않는다. 공통 원점·tail을 보존하고 복사 대신 미디어 참조를 재사용한다. 전체 38개를 무조건 번들에 넣지 않는다. 최초 패키지 크기·메모리·로드 시간 예산은 pilot 측정 후 동결한다.
5. 시작 화면에는 통과한 곡만 노출한다. 곡별 한영 소개·학습 목적·편성·재생 시간·권리 안내와 실제 편집 절차(섹션 이동→루프→음색/FX 변경→바운스)를 제공한다. 안내는 필요할 때 열며 감상·녹화 모드에 텍스트를 강제로 표시하지 않는다.

## 완료 조건 / 담당 경계

- **음악 제작:** 프로듀서가 방향과 청취 승인을 관리하고 편곡자·연주자·사운드 디자이너·믹싱 엔지니어가 곡/파트 소유 범위를 나눈다. 대량 병렬 생성 전에 pilot 한 곡의 기준을 확정한다.
- **앱 통합:** 각 곡의 schema/asset manifest, 새 ID의 쓰기 가능한 사본, 원본 checksum 불변, 취소·누락 오류·저장·재열기를 검증한다. 템플릿과 완성 데모를 구별한다.
- **음악 QA:** 최소 3곡 모두 처음부터 끝까지 실제 청취, clipping/무음/hanging note/tail·편성 균형 확인. 원 MIDI와 비교한 의도적 변경 기록, MIDI+audio 재생과 WAV/stem 바운스 정렬을 검증한다. 자동 검사만으로 음악 품질 PASS를 선언하지 않는다.
- **서클 QA:** 섹션 순서 변경·공유/독립 편집·Undo·곡/섹션 루프·곡/섹션/지정 서클 팔로우·텍스트 없는 녹화까지 실제 프로젝트로 검증한다. 녹화 성능은 R40-04 기준을 따른다.
- **배포 QA:** 새 환경에서 오프라인 로드·편집·바운스, 배포 ZIP의 모든 자산과 notices, 패키지 크기·성능 예산을 확인한다. 원본 취득·편곡·탑재·QA 상태를 곡별로 기록하며 조사 완료를 탑재 완료로 표시하지 않는다.
