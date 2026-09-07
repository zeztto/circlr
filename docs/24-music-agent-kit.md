# 써클러 음악 제작팀 — 0.12

`circlr-studio` 스킬과 8개의 Codex custom agent를 프로젝트에 설치했다. 원본은 `Resources/Codex`, 설치본은 `.agents/skills/circlr-studio` 및 `.codex/agents`다. 앱 패키징 시 같은 키트와 설치 도구를 `Contents/Resources/Codex`에 넣는다.

| 역할 | 담당 산출물 |
|---|---|
| 프로듀서 | 곡의 의도, 우선순위, 전문 파트 통합 판단 |
| 편곡자 | 송폼, 화성 진행, 보이싱, 악기 배치와 섹션 대비 |
| 연주자 | 악기 특성에 맞는 MIDI 프레이징·아티큘레이션 |
| 비트메이커 | 실제 샘플 매핑, 드럼·베이스 관계, 그루브·필 |
| 탑라이너 | 보컬 멜로디, 가사·운율, 음역·호흡 |
| 사운드 디자이너 | 음원·신스·이펙트 설계, 전환 사운드 |
| 믹싱 엔지니어 | 밸런스·마스킹·다이내믹·공간감과 검증 |
| 마스터링 엔지니어 | 믹스 QC, 시퀀스, 실제 납품 포맷·측정 기준 |

역할은 전문 판단 지침이다. 실제 사람의 경력·자격 또는 청취를 가장하지 않는다. 별도 학습된 8개 모델이 아니라 사용자의 Codex 모델이 역할별 계약과 도구 범위를 적용한다.

## 사용과 설치

이 프로젝트의 Codex에서 `$circlr-studio`를 호출한다. 예: “$circlr-studio로 f0r h3r의 후렴을 분석하고, 멜로디를 보존하면서 편곡자와 사운드 디자이너가 개선안을 제안하세요.” 역할의 병렬 실행은 실제 runtime 설정과 슬롯 수에 따른다. 슬롯이 없으면 동일한 역할 계약으로 순차 수행한다.

다른 프로젝트에는 Python 3.11 이상으로 다음을 실행한다. 앱을 이동했을 때는 현재 앱 번들 안의 install.py 경로를 사용한다.

```sh
python3 Resources/Codex/install.py --project /absolute/path/to/music-project --dry-run
python3 Resources/Codex/install.py --project /absolute/path/to/music-project
```

설치 도구는 대상 프로젝트에 스킬·역할 파일과 전용 `mcp_servers.circlr` 설정을 추가한다. Codex 프로젝트 신뢰 설정에 따라 로컬 MCP 설정을 사용하려면 해당 프로젝트를 신뢰해야 할 수 있다. 설치 후 스킬 검색을 갱신하거나 새 Codex 세션에서 확인한다. 기존 MCP 설정 충돌이나 사용자가 수정한 관리 파일이 있으면 덮어쓰지 않고 중단한다. 전역 모델·동시성·인증은 변경하지 않는다. MCP adapter는 Python 3.9 이상, installer는 TOML 해석을 위해 3.11 이상이 필요하다.

## AI 협업 계약

메인 세션만 프로젝트를 쓴다. 전문 에이전트는 brief, real ID, 읽은 revision, 담당 파트와 검증 조건을 받아 `circlr-proposal-v1`을 제출한다. 메인 세션은 최신 상태를 다시 읽고 서로 겹치는 변경·공유 트랙을 조정한다. 오래된 편집안의 revision 숫자만 바꿔 실행하지 않는다.

전문가용 MCP `--read-only`는 snapshot/inspect/job/events만 제공하며 쓰기·재생·정지·focus 및 `--request` 우회 호출을 실제로 거부한다. 다른 상속 connector나 raw socket까지 막는 OS 전체 권한 격리는 아니다. 향후 앱 내 run-lease gateway에서 이 경계를 강화한다.

음악 지침은 MIDI 시간과 오디오 초 단위, 섹션별 상속, 보컬 운율, 목적 있는 microtiming, gain staging, 실제 측정과 청취의 차이를 구분한다. peak 수치나 렌더 성공만으로 발매 품질을 선언하지 않는다. 현재 지원되지 않는 lyric lane·자동화·마스터링 파라미터를 API처럼 만들지 않는다.

## 앱 내 Codex 콘솔 연결

앱 내 계정 로그인과 LLM 대화 UI는 [기존 계획](20-codex-account-console-plan.md)의 후속 구현이다. 향후 App Server `skills/list`로 bundle/설치본을 확인하고 `turn/start`에 text와 실제 skill input item을 함께 전달한다. role label은 실제 spawned task의 ID·상태에 연결하며, 가상의 에이전트 대화를 표시하지 않는다.

첫 앱 통합은 프로젝트당 coordinator 1개, 전문가는 제한된 읽기·제안, native writer 1개로 구성한다. 아티스트/프로젝트 전환, 취소 및 late result 차단은 RunLease 범위와 연결한다. 이 키트 설치가 로그인·대화 UI 구현을 의미하지 않는다.

## 근거와 검증

[OpenAI 모델 가이드](https://developers.openai.com/api/docs/guides/latest-model)의 명확한 결과·범위와 위임 원칙, [Codex Skills](https://learn.chatgpt.com/docs/build-skills)의 점진적 로딩, [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)의 역할 파일 구조를 적용했다. 역할 구분은 [Berklee Producer](https://www.berklee.edu/careers/roles/music-producer), [Top-Line Songwriter](https://online.berklee.edu/careers-in-music/roles/top-line-songwriter), [Mixing Engineer](https://www.berklee.edu/careers/roles/mixing-engineer)를 참고하고 circlr 작업 계약으로 설계했다.

[검증 기록](../qa/0.12-agent-kit-review.md). 음악적 판단의 실제 모델·청취 평가는 파일 형식/설치 테스트와 별도이며, 후속 f0r h3r 재제작에 적용한다.
