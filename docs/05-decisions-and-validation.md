# 결정과 검증

> 0.4.0 갱신: 사용자가 설계 후 실제 프로토타입 제작을 요청해 문서 전용 단계가 끝났다. Swift·AppKit/SwiftUI·AVAudioEngine·CoreMIDI로 로컬 macOS 앱을 구현했다. 아래 S01–S32는 제품 전체의 설계 기준으로 유지한다. 현재 인수 기준 A01–A11과 실제 실행 결과는 [구현 계약](08-prototype-contract.md), [검증 기록](09-prototype-verification.md)에 있다. 초기 판단과 현재 상태를 혼합하지 않는다.

버전: 0.3 · 소유 역할: development-lead · 상태: 설계 초안 검토

2026-09-07: [중첩 서클 모델](13-nested-circle-model.md)이 최신 방향이다. Q03은 사용자 발언으로 해결됐으며, P01·P07·P11·P12는 내부 음악 그래프와 부모/자식 설정을 고려해 갱신한다.

## 확인된 요구

최신 전체 제품 방향은 [아티스트 프로필과 창작 세계](21-artist-universe.md)다. 아래 초기 제안 중 정밀 사각 편집 창은 같은 캔버스 편집으로 대체됐으며 현재 음악 동작은 [궤도 타임라인](19-orbit-timeline.md)을 따른다.

| ID | 상태 | 내용 | 근거 |
|---|---|---|---|
| U01 | Confirmed | verse·bridge·chorus 등 섹션을 원형으로 표현 | 최초 사용자 요청 |
| U02 | Confirmed | 노드를 연결·반복·이펙팅 | 최초 사용자 요청 |
| U03 | Confirmed | 송라이터·편곡자의 곡 전체 구성 설계가 중심 | 작업 목적에 대한 사용자 답변 |
| U04 | Confirmed | 오디오 녹음·샘플 + MIDI·가상악기 | 음악 재료에 대한 사용자 답변 |
| U05 | Confirmed | 섹션 음색 처리와 섹션 간 전환 효과 모두 | 이펙팅 범위에 대한 사용자 답변 |
| U06 | Historical | 최초에는 아이디어·문서·기본 아키텍처만 작성; 이후 구현 요청으로 전환 | 최초 및 후속 사용자 요청 |
| U07 | Confirmed | 제품명은 써클러(circlr), 영문 소문자 표기 | 제품명에 대한 사용자 지정 |
| U08 | Confirmed | 첫 대상 플랫폼은 macOS 앱 | Mac 사용 환경에 대한 사용자 지정 |
| U09 | Confirmed | ComfyUI 같은 프리폼 노드 에디터, 그리드·정렬·그룹 | 화면 방향에 대한 사용자 지정 |
| U10 | Confirmed | 원형 노드의 테두리로 섹션 길이·마디·박 표현 | 서클 표현에 대한 사용자 지정 |
| U11 | Confirmed | 글로벌 tempo·scale·박자와 각 서클의 독립 설정 | 음악 설정에 대한 사용자 지정 |
| U12 | Confirmed | 리듬 기준과 실제 드럼·리듬 패턴을 별도 글로벌 설정으로 모두 지원 | 글로벌 비트 의미에 대한 사용자 답변 |
| U13 | Confirmed | 모든 음악 요소가 서클이며 섹션 그룹 안에 오디오·MIDI·이펙터 서클과 연결을 포함 | 2026-09-07 사용자 개념 명확화 |
| U14 | Confirmed | 단일 다크 캔버스·휠 줌·확대하면 같은 캔버스에서 정밀 편집 | 별도 사각 창 이후의 사용자 변경 결정 |
| U15 | Confirmed | 서클 자체가 타임라인이자 궤도이며 그 위에 작은 서클이 연결됨 | 우주·궤도에 대한 사용자 설명 |
| U16 | Confirmed | 음악·텍스트·영상·이미지를 통합하는 아티스트 세계관 도구 지향 | 최종 제품 목적에 대한 사용자 설명 |
| U17 | Confirmed | 게임 캐릭터 선택처럼 아티스트 프로필을 만들고 생성물을 종합 관리 | 최신 사용자 요구 |
| U18 | Confirmed | 사용자 자신의 Codex 계정으로 앱 안에서 대화하는 기능을 향후 계획 | Codex 공식 문서 기반 계획 요청 |
| U19 | Confirmed | 서클 둘레 8방향에 자유롭게 연결하고 IN/OUT 표시와 멀티 입력·출력을 지원 | 최신 사용자 연결 요구; 상세는 22-eight-direction-ports.md |

## 이번 초안에서 제안한 결정

| ID | 상태 | 제안 | 사용자가 검토할 영향 |
|---|---|---|---|
| P01 | Superseded | 섹션 서클 = 내부 음악 서클과 그래프를 담는 그룹의 사용 위치 | U13 및 중첩 서클 모델 참조 |
| P02 | Proposed | 원본·사용 위치·재생 회차 분리 | 공통 수정과 마지막 후렴 변형을 함께 지원 |
| P03 | Proposed | 논리 graph 분리 + 같은 프리폼 canvas에서 유형별 표시 | 별도 화면 고정 제안을 대체; 진행/신호 의미는 구분 |
| P04 | Proposed | 한 바퀴 = 섹션 전체, 마디·박 링 + 선택적 시간 흐름 띠 | 원 테두리의 시간 표현은 U10 확정; 반지름·눈금 상세도는 미결 |
| P05 | Proposed | 일반 drag는 자유 배치, 명시적 삽입 모드만 순서 변경 | 선이 많은 캔버스에서 의도치 않은 재연결 방지 |
| P06 | Proposed | 유한 경로와 명시적 반복을 우선 | 편곡안별 전체 길이와 export가 결정됨 |
| P07 | Revised proposal | 악기·이펙터 서클과 processor 자원을 구분하고 명시적 공유/독립 정책 수립 | 동시 tempo·automation·잔향 고려 |
| P08 | Proposed | 이번 사용 편집을 기본으로, 공유 원본 편집은 명시 | 원본을 실수로 바꾸는 위험 완화 |
| P09 | Proposed | macOS 앱의 local-first 저장·작업 구조 | 플랫폼은 U08에서 확정; 저장 구조와 framework는 제안 상태 |
| P10 | Proposed | musicRevision을 불변 재생 계획으로 변환, layoutRevision 별도 | 정렬·그룹 작업에 음악 계획 재사용 |
| P11 | Revised proposal | 글로벌→섹션 원본→이번 사용→자식 원본→자식 사용별 override | 부모 따름과 글로벌 직접 따름을 구분 |
| P12 | Revised proposal | 정리용 CanvasGroup과 음악을 담는 섹션 그룹 분리 | 접기/이동은 음악을 바꾸지 않으며 섹션은 길이·반복·설정을 소유 |
| P13 | Proposed | 이종 tempo/meter overlap을 공통 sample 시간에 배치 | 기존 동일 tempo 제한 제안을 대체; processor 격리·render 검증 필요 |
| P14 | Proposed | 글로벌 리듬 패턴은 상속한 서클에서 재생 | 개별 패턴은 대체; 숨은 중복 재생 없음 |

Proposed는 사용자 승인이나 최종 기술 결정을 뜻하지 않는다. 이 초안의 설명과 시나리오를 일관되게 만들기 위한 작업 가정이다.

## 미결 사항

아래는 초기 검토 목록이다. Q03은 해결됐다. 새 목표 모델에서 남은 결정은 [중첩 서클 모델의 후속 설계 항목](13-nested-circle-model.md)에 모았다.

| ID | 검토할 질문 | 현재 가정 | 결정 시점 |
|---|---|---|---|
| Q01 | 기존 DAW에서 가장 답답했던 편곡 변경 한 가지는 무엇인가 | 섹션 이동·재사용·국소 변형이 핵심 | 실제 곡 작업 흐름 검토 |
| Q02 | 같은 후렴을 재사용할 때 사용 위치마다 원이 있는가, 한 원으로 되돌아오는가 | 사용 위치별 원 + 공통 원본 | 다음 개념 검토 |
| Q03 | 원을 열었을 때 내부도 node 중심인가 | 해결: 내부 음악 서클 그래프와 확대 시 같은 캔버스의 note·파형 편집 | U13·U14에서 종료 |
| Q04 | 기준 Mac·macOS 버전·audio interface와 MIDI 입력 장치는 무엇인가 | macOS 앱 확정; 최소 OS·CPU 지원 범위와 장치 미정 | 기술 후보 선정 전 |
| Q05 | 꼭 열려야 하는 가상악기·effect·plugin 포맷은 무엇인가 | 외부 hosting 핵심, 목록 미정 | 기술 후보 선정 전 |
| Q06 | 여러 섹션에 걸쳐 녹음한 take를 재배치할 때 어디까지 함께 옮기는가 | 원본 유지 + 경계 참조 + 명시적 carry | 녹음 UX 확정 전 |
| Q07 | 사용별 변형을 기본으로 할 때 공유 수정이 번거로워지는가 | 이번 사용 기본, 원본 편집 접근 제공 | 편집 범위 사용성 검토 |
| Q08 | 확정된 마디 링과 글로벌/개별 설정을 어느 확대 단계에 표시할 것인가 | 읽기 밀도에 따라 박 눈금과 설정 상세 표시 | wireframe 검토 |
| Q09 | 리듬 기준과 실제 패턴 모두 필요한가 | 해결: U12에서 별도 설정으로 둘 다 확정 | 0.3에서 종료 |
| Q10 | 한 바퀴 = 섹션 전체 방식과 원 크기 정책이 맞는가 | 마디별 큰 구간, 원 크기는 음악 길이와 분리 | 다음 개념 검토 |
| Q11 | 글로벌 패턴은 서클 경계마다 시작하는가, 연속 phase를 유지하는가 | 서클 진입·반복에서 reset, 연속 모드는 후속 제안 | 다음 리듬 UX 검토 |

## 한 곡으로 검토할 시나리오

기준 곡은 [재생 모델의 68마디 사례](03-playback-model.md)다. 실제 사용자 곡이나 생성된 음원은 아니다. 아래는 **미래 구현의 인수 기준**이며 실행 테스트 결과가 아니다.

| ID | 조작/조건 | 기대 결과 | 검증 층 |
|---|---|---|---|
| S01 | Verse A 8마디를 총 2회 재생 | occurrence 2개, 총 16마디; 원본은 8마디 | domain·scheduler |
| S02 | 반복을 사용 위치 2개로 펼치기 | 재생 시간·연주 보존, 둘째 사용만 변형 가능 | domain·UX |
| S03 | 마지막 후렴에만 보컬 추가 | 앞 두 후렴 변화 없음, 원본 베이스 수정은 전파 | domain·UX |
| S04 | 사용별 override가 있는 원본 clip 삭제 | 충돌 표시, 기존 계획 유지, 데이터 무손실 | domain·recovery |
| S05 | 브리지를 연결선 위에 옮기기 | 순서와 흐름 띠 갱신, 유효한 전환 영향 표시 | UX·compiler |
| S06 | 동일 원을 빈 곳으로 이동 | 음악 event와 전체 길이 불변 | domain·UX |
| S07 | 앞 구간 내 1마디 필인 | 68마디·136초 유지, 총 2회 중 마지막 출구에서만 실행 | compiler·audio |
| S08 | 필인을 1마디 insert로 변경 | 69마디·138초, 뒤의 모든 occurrence +1마디 | compiler·audio |
| S09 | 같은 tempo/meter의 인접 섹션 1마디 overlap | 기준 대비 1마디 감소, 의도된 두 구간만 중첩 | compiler·audio |
| S10 | 8마디 구간을 7/8, 120 BPM으로 정의 | 28 quarter notes·14초; 4/4의 16초와 구분 | time model |
| S11 | block 중간에서 섹션 경계 발생 | 목표 sample 위치에 note/automation 적용 | native engine |
| S12 | audio clip tempo 따르기 OFF 상태에서 BPM 변경 | 원본 재생 속도 유지, 범위 초과 표시 | audio·UX |
| S13 | 공통 reverb를 유지한 채 후렴으로 진입 | 앞 구간 tail 보존; 앞 tail만 처리하려면 별도 return 요구 | audio |
| S14 | 반복 섹션에서 2회 녹음 | take 2개와 회차 매핑 보존, 첫 take 무손실 | native recording |
| S15 | A를 복제한 B에서 브리지 삭제 | A의 순서 유지; 공통 원본 수정은 A/B 모두 반영 | domain·persistence |
| S16 | 재생 중 다음 구간 변경 준비 실패 | 현재 유효 계획 유지, 새 revision 적용 실패 표시 | runtime·UX |
| S17 | 미정 분기·끝 없는 경로로 전체 재생/export | 원인 위치 표시, 새 전체 실행 시작 거부 | compiler·UX |
| S18 | export 중 편곡 변경 | export는 시작 revision 고정, 새 편집은 별도 저장 | export |
| S19 | 파일 이동 후 프로젝트 열기 | missing media 표시, 다시 연결 후 clip·take 관계 복구 | persistence |
| S20 | plugin 누락/오류 | state 보존, 자동 대체 없음, 명시적 조치 전 export 보류 | hosting·recovery |
| S21 | stem export와 sidechain·공통 return | 공통 시간축, sidechain 입력 유지, return 별도 기록 | export·audio |
| S22 | 노드 수 증가·키보드만 사용 | 순서·선택·편집 범위·끝을 찾아 조작 가능 | native UI·접근성 |
| S23 | 곡 중간 seek/audition | pre-roll 상태 복원 또는 소리 차이를 명시; stale note 없음 | runtime·audio |
| S24 | global 120을 132로 변경; 벌스 inherit·브리지 96 local·후렴 128 local | 벌스만 132; 다른 값과 scale·meter·pattern 보존 | context resolver |
| S25 | 다중 정렬·group 이동/접기·grid snap | 음악 경로·context·계획 유지; 저장 후 위치와 그룹 복구 | canvas·persistence |
| S26 | 8마디 4/4 ring과 4/4+7/8 변박 ring | 각각 마디당 45도; 변박 두 마디는 192도/168도 | ring model |
| S27 | 120 BPM 4/4 8마디 → 96 BPM 7/8 4마디 | 각 링이 local 속도로 진행, 총 24.75초 | clock compiler |
| S28 | S27에서 출발 1마디 기준 2초 overlap | 총 22.75초; 두 local clock 유지, 공유 plugin context 제약 표시 | compiler·hosting |
| S29 | 글로벌 scale 변경 | 상속 표시 갱신; 기존 절대 MIDI·drum map·audio pitch 유지 | domain·UX |
| S30 | 글로벌 pattern A와 브리지 local B, 후렴 사용 안 함 | 벌스만 A·브리지 B·후렴 무패턴, 이중 글로벌 재생 없음 | rhythm compiler |
| S31 | 4/4 한 마디 pattern을 7/8 서클에 적용 | 원본 pattern 길이 유지·경계 차이 표시, 임의 note 삭제/변형 없음 | rhythm·UX |
| S32 | SectionUse의 global 정책으로 원본 local tempo 건너뛰기 | 글로벌 연결 복구; 이후 글로벌 변경에 반응 | context resolver |

소리의 연속성은 event 목록 검사만으로 확인하지 않는다. click, phase, release, filter smoothing, latency, clipping은 실제 device/plugin으로 듣고 측정할 항목이다.

## 설계 위험과 대응

| 위험 | 초기 대응 | 재검토 신호 |
|---|---|---|
| graph가 복잡해 음악 구조가 안 보임 | 편곡안 하나씩 표시, 명시적 반복, 원본 참조 | 선 정리·화면 이동이 작업의 큰 비중 |
| 재사용과 복사의 차이로 의도치 않은 수정 | 편집 범위 고정 표시, 영향 범위 preview, undo | 사용자가 원본/이번 사용 결과를 오판 |
| 섹션 경계 때문에 유기적 연주가 깨짐 | take 보존, pickup/tail, 전환 문맥 편집 | 수동 bounce 없이는 자연스러운 연결 불가 |
| node effect와 송폼 연결 의미 혼란 | 같은 canvas의 유형별 보기·port type·parameter 참조 | audio 케이블로 순서를 바꾸려는 반복적 오류 |
| DAW 기능 범위가 끝없이 커짐 | 한 곡 완성에 필요한 기능부터 선정 | 필수 기능 없이 시각 prototype만 늘어남 |
| 공통 engine의 모델에 제품 경험이 종속 | 자체 domain 모델과 adapter 유지 | graph를 손실 있는 timeline으로 매번 변환 |
| 전체 가상악기 호환성 요구 | 실제 필수 plugin 목록으로 호환 범위 검증 | 검증 목록 외 지원을 홍보하게 됨 |

## 이후 단계 제안

| 단계 | 소유 역할 | 산출물과 경로 | 종료 조건 |
|---|---|---|---|
| A. 개념 수정 | product-manager / ui-ux-designer | 이 문서와 `01-product-concept.md`, `02-interaction-model.md` | Q03·Q10·Q11과 실제 작업 흐름 합의 |
| B. 작업 흐름 검토 | ui-ux-designer | 추후 `docs/workflows/` 설계 자료 | 이동·반복·변형·전환 결과를 사용자 예측 가능 |
| C. 기술 타당성 | architecture / audio 담당 | 추후 `docs/technical-evaluation/` 비교 보고 | 필수 plugin, 녹음, 경계, 저장, export의 재현 증거 |
| D. 개발 범위 확정 | product-owner / development-lead | 추후 구체적 기능 계약과 개발 계획 | 한 곡을 끝낼 필수 범위·품질 기준 합의 |

현재 요청은 설계 문서 작성까지다. B의 실행 가능한 UI나 C의 engine code를 이번 산출물로 만들지 않는다. 후속 요청이 있을 때 macOS의 구체적인 지원 범위와 검증 환경을 정하고 진행한다.

## 이번 문서 검토 범위

- 사용자 응답 U01–U12을 제품 개념·UX·재생 모델·architecture에 반영한다.
- 문서 간 상대 링크, Markdown fence, 표 구조와 UTF-8 읽기를 확인한다.
- 설명용 사례의 마디 합·tempo 환산·occurrence 연속성을 계산으로 확인한다.
- 기존 제품/기술에 관한 사실은 공식 자료와 대조하고 설계 제안과 구분한다.
- 제품 code, audio 엔진, GUI, device, plugin, 실제 사용자 곡에 대한 실행 검증은 포함하지 않는다.

최종 점검 결과는 이 파일 하단에 기록한다. 문서 점검 통과는 제품 준비 완료나 사용자 설계 승인과 다르다.

## 2026-09-06 문서 0.1 점검 결과

| 점검 | 결과 | 근거와 한계 |
|---|---|---|
| 산출물 범위 | 통과 | README·CHANGELOG·설계 문서 6개; 제품 코드 없음 |
| 사용자 요구 반영 | 통과 | U01–U06을 개념·UX·재생/architecture에 대응 |
| 문서 무결성 | 통과 | Python 표준 라이브러리로 UTF-8, 상대 링크 12개, fence 8개, 표 열 수, trailing whitespace 점검 |
| 음악 시간 사례 | 통과 | 유리수 계산으로 68마디/136초, insert 69마디/138초, overlap 67마디/134초, 7/8 8마디/14초 확인 |
| occurrence 연속성 | 통과 | 예시 8개 occurrence의 시작·끝이 겹침/빈칸 없이 1–68마디에 대응 |
| 문서 계약 검토 | 보완 반영 | seek/pre-roll의 이력 한계, 녹음 중 구조 변경 적용, 과도한 반복의 계획 크기 제약을 명시 |
| diagram 시각 렌더 | 미실행 | Mermaid source만 작성; screenshot 기반 UI QA 아님 |
| 사용자 조작성·native audio·plugin | 미실행 | 제품을 개발하지 않았고 실제 실행을 검증하지 않음 |

위 0.1 기록의 시나리오 S01–S23과 0.3에 추가한 S24–S32는 이후의 실행 검증 과제로 남아 있다. 이번 통과 결과는 문서와 산술 점검에 한정하며, 독립 sub-agent review는 실행 슬롯 제약으로 수행하지 않았다.

## 2026-09-06 문서 0.3 점검 결과

| 점검 | 결과 | 근거와 한계 |
|---|---|---|
| 요구 반영 | 통과 | U09–U12를 캔버스·링·음악 설정·실제 리듬 패턴에 반영 |
| 문서 무결성 | 통과 | Markdown 9개·상대 링크 19개·fence 10개·표 열 수·UTF-8·공백 점검 |
| 새 시간/각도 사례 | 통과 | 유리수 산술로 순차 24.75초·overlap 22.75초, 8마디당 45도·변박 192도/168도 확인 |
| 상속 사례 | 통과 | 문서 예시에 대한 계산으로 global/local 유지·원본 건너뛰기·패턴 대체/사용 안 함 확인 |
| 이전 제안과 정합성 | 보완 반영 | 별도 화면 고정·마디 비례 보조 띠·같은 tempo 전용 overlap을 새 방향으로 수정 |
| 실행 검증 | 0.4.0 별도 기록 | native 프로토타입·자동 검증·GUI 실행 결과는 docs/09 참조. S01–S32 전체 완료를 뜻하지 않음 |
