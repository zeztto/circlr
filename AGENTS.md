# circlr 버전 개발 운영

이 저장소에서는 [버전 운영 규약](docs/releases/README.md)과 해당 버전 문서를 개발·완료 기준으로 사용한다. 상위 지시 및 사용자의 최신 지시를 우선한다.

- 새 기능 개발 전 `docs/releases/roadmap.md`와 현재 버전 문서를 확인하고 작업 ID·완료 조건을 정한다.
- 현재 계획은 `docs/releases/0.30.0.md`다. 작은 build 수정의 종료를 제품 버전 완료로 보고하지 않는다.
- 한 버전을 계획→구현→필수 QA→독립 검토/수정→README·CHANGELOG·버전 기록→최종 commit/tag/push→GitHub Release 등록→원격 검증 순서로 닫는다.
- 필수 QA가 실패하거나 실행되지 않았으면 릴리스 완료를 선언하지 않는다. 물리 I/O·설치 앱 경계와 실제 지원 범위를 보존한다.
- 버전 중 불필요한 전체 재검사·동일 화면 반복 캡처·에이전트 과다 생성을 피한다. 변경 영향에 맞춰 검사하고 의미 있는 릴리스 검토를 한 번 통합한다.
- 완료하는 제품 버전마다 한국어·영어 릴리스 노트와 검증된 패키지·SHA256을 GitHub Releases에 등록한다. 원격 tag SHA·Release URL·draft/prerelease·자산 검증까지 통과해야 RELEASED다. 상세 명령은 버전 운영 규약을 따른다.
- 문서만 바뀐 작업은 링크·diff 검증 후 문서 commit/push로 끝내고 제품 버전/build/tag를 올리지 않는다.
- 범위 밖 기능은 다음 버전 backlog에 기록한다. 사용자 정지와 새로운 우선순위를 존중한다.
