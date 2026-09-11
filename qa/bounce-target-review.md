# build80 바운스 대상과 사전 검사

2026-09-10, 기준305b4d7. 단일 슬롯에서 UX→native 구현→검토→QA 순차 수행. 독립 검토가 아니다.

Core의 BounceEditing.target을 UI와 MCP job 시작 전, 최종 적용에서 재사용한다. 트랙·편곡/사용·유일한 출력·연결 입력을 확인한다. 입력 경로 존재 검사는 무음 검출이 아니며 실제 음원/플러그인 렌더 오류를 모두 예측하지 않는다. 미리 보기에 프로젝트 변경·파일 생성은 없다. 기존 revision 검사와 최종 구조 검증은 유지한다.

- 관련 Swift17개 통과: BounceTargetTests, AudioEditingTests, ProductionCoreTests. `.build/bounce-target-final-tests.log`. 최초 테스트는 존재하지 않는 graphOverride 필드 사용으로 컴파일 실패했으며 실제 section.graph를 사용하는 결함 입력 fixture로 수정했다.
- release63.73초, UUID B51EA1E5-7117-317A-90BA-81C868013981. helper 포함 독립 후보.
- 작은 창에서 오디오/출력 버튼 대상과 비활성 연결 안내를 screenshot/AX로 확인했다. `qa/generated/bounce-target/audio-ready.jpg`, `disconnected.jpg`.
- 실제 오디오 편집기 버튼으로 출력1 바운스 성공. job6423A03C-13FC-4131-977C-C28844C68CC7, 자산 duration34초. 파형/오프라인 렌더 검증이며 물리 출력/청감 검증이 아니다.
- 원본 복원 버튼 후 Undo2회로 바운스 이전 음악 복원. 출력1 케이블만 해제한 fixture에서 버튼 비활성화 확인. MCP bounce는 `출력에 연결된 연주가 없습니다`로 즉시 거절하며 기존 job과 revision이 같았다. 연결 Undo와 저장/재열기 후 음악 기준과 같다.
- `python3 qa/check-bounce-target-evidence.py`:native7상태, 성공 job·새 자산·거절 시 job 불변·전체 음악 비교·source hash·app/helper Mach-O sections·deep/strict 서명·원본 fixture 보존 통과. 음악 비교는 hierarchyView/musicRevision만 제외한다.
- MIDI/이펙트 편집기는 동일 컴포넌트로 교체하고 빌드했다. 모든 편집기의 실제 긴 이름/키보드 화면 조합을 이번에 재실행하지 않았다. 오토메이션을 새로 편집한 뒤 바운스하는 통합 시나리오는 다음 범위다.
- output/audition attempts0, 녹음 없음. 사용자 앱과 물리 I/O·MP4 출고 조건은 유지한다.
