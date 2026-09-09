# build 68 편집 위치 유지 검증

2026-09-09. `codex/daw-integration`, baseline `acf8490`. 사용자 요청에 따라 read-only 검토 에이전트를 다시 할당했으나 `agent thread limit reached`로 거절됐다. 실제 1 slot에서 UX → Core/native utility → code/security review → QA를 순차 수행했다. 독립 에이전트 검토 결과는 아니다. 전체 DAW/UX 목표는 진행 중이다.

## 산출물과 검사

- 최종 앱: `qa/generated/editor-position/refined/써클러 통합 검증.app`, 0.20.0 build68, UUID `5AF3A3A3-5813-3AB2-B67A-E86D8AED0610`. 최초 후보 UUID `A370BB84-B539-3CEA-A386-9F8F34A05F65`. 이 작업의 두 앱은 종료했다.
- 사본: `~/Library/Application Support/circlr-integration-qa/fixtures/editor-position.circlr`, ID `926DF9B0-369A-57F8-A08F-DD2221CD5999`. 직접 작성한 3트랙·2 tone 자산, 32섹션·2분기와 다른 곡의 편곡을 사용했다.
- 새 scratch `.build/editor-position-quality`: Swift485개, 실패0, 26.234초. 새 보기 상태 Core 검사8개 포함. Python28개, 실패0, 0.228초. 기존 물리 출력 의존 `testArrangementRenderExportAndPlayback`만 제외했다.
- release70.12초. 이후 App의 최초 피아노롤 최소 음역 보정만 추가하고 release39.16초 및 최종 native 검사를 수행했다. Core와 Python은 전체 테스트 이후 동일하다.
- `python3 qa/check-editor-position-evidence.py` 통과: 문서/상태19개, 화면43개, 최종 소스17개 hash, Mach-O37개 section, Codex kit25개 hash, 두 앱 codesign. 최초 후보14상태·38화면과 최종 후보5상태·5화면을 구분했다. 잘못된 프로세스를 가리킨 화면2개는 제외했다.
- 원본 fixture manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 자산 checksum 유지. root `d88ea5d`, ports `1d304eb`, 사용자 앱0.19.0 build21 및 기존 프로세스를 보존했다. 물리 출력·audition 시도0, 녹음 시작0.

## 실제 동작과 근거

| 검사 | 결과 |
|---|---|
| 스텝 위치 | 첫 서클의 3페이지·C♯6 음역·스크롤 y140.5가 설정 왕복과 다른 서클 방문 뒤 유지. `step-position/return`, `first-circle-return`, `step-saved` |
| 서클별 분리 | 두 번째 서클은 처음에 1페이지·C♯5로 열림. 1/32·2페이지·드럼 모드·추가 행97·검색97을 따로 저장. 원래 서클은 3페이지·음정 모드 유지. `second-circle`, `drum-query/saved` |
| 피아노롤 | 가로 x1943.5·세로 y227.5를 연결 왕복과 같은 문서 재열기에서 유지. 재열기 뒤 음역을 C♯6→C♯7로 변경해 재저장. `piano-position/return/reopened/warm-edited`, `piano-saved/warm-saved` |
| 오디오 | 16–24초 확대 범위가 설정 왕복·이번 사용/공유 원본 전환·재열기 뒤 유지. 공유 원본은 처음 전체32초로 열리고 독립적으로8–24초로 확대. `audio-position/original-fresh/original-position/scope-return/reopened` |
| 설정 스크롤 | 약55% 위치가 오디오 페이지 왕복과 재열기에서 유지. `settings-scroll-set/page-return/reopened`, `audio-settings-saved`. 원본 체크박스를 AX로 선택하면 그 항목이 있는 위쪽으로 이동하므로 해당 조작 전후 스크롤 값의 동등성을 요구하지 않음 |
| 오토메이션 | 129박에 점을 옮기는 편집은 표시 길이를 자동으로 바꾸지 않음. 명시적 ‘선택 오토메이션 점 보기’로128박 길이까지 펼친 뒤 팬64박과 별도로 기억. 파라미터 왕복·Undo·재열기 후128박 유지. `automation-fitted/return/undone/reopened`, `automation-pan-separate` |
| 음악 Undo | 두 차례의 점 추가→위치 변경→Undo2회로 r14→18→22. 전체 음악 데이터는 원래와 같음. `automation-undone`, `automation-fitted-saved`. 보기 조작 자체로 revision 증가 없음 |
| 궤도 MIDI | 2마디씩·5–6마디·2옥타브 E♭4–D6을 설정 왕복 및 앱 종료/재실행 후 유지. 이후7–8마디로 바꿔 재저장. `orbit-position/return/cold-open/cold-edited`, `orbit-saved/cold-saved` |
| 길이 축소 | 사본의 해당 사용만16→1마디로 바꾸고 오래된 스텝15페이지를 주입. 궤도·스텝 모두 유효한 첫 페이지로 보정. `shorter-input/orbit/step/saved`. 변경 전 문서로 복원 |
| 드럼 재열기 | 저장한 두 번째 서클의 view만 사본에 복원해 검색97·추가 행97·1/32·2페이지 확인. 검색73으로 바꾸고 설정 왕복/재저장. `drum-input/reopened/warm-edited/warm-saved` |
| 최종 경계 보정 | 최종 후보에서 저장 topPitch−400을 열어 피아노롤의 최소 topPitch27(D1)로 보정. 정상 행 렌더링과 가로·세로 스크롤 왕복/재열기 확인. `low-pitch-input/saved`, `refined-low-pitch`, `refined-piano-position/return/reopened` |
| 최종 복원 | `final-restored` 전체 manifest가 `orbit-cold-saved`와 정확히 같음. 길이·노트·음색·오디오·효과·포트 binding 전부 원래 상태. 보기 layout만 초기 freeform에서 사용자가 QA 중 선택한 orbit으로 변경 |

최종 후보에서 수행한 `refined-opened` MCP 캡처는 정상 문서 상태이지만 같은 이름의 구 후보를 다시 실행한 CUA 참조 때문에 대응 화면은 새 앨범을 가리켰다. `refined-opened.jpg`와 `low-pitch-opened.jpg`는 통과 화면 수에 넣지 않았다. 구 후보를 종료하고 CUA 세션을 초기화한 뒤 정확한 최종 경로를 새 참조로 선택했다. 이후 프로세스 목록에서 최종 후보 하나만 실행 중임을 확인하고 화면/저장 문서를 다시 대조했다. 제품 데이터 결함으로 기록하지 않는다.

## 발견·수정 및 한계

첫 debug build는 `StepRowSearch`에 잘못 전달한 scroll 인수로 실패했고, 최초 focused test는 `MusicClock`의 인수 순서 오타로 컴파일에 실패했다. 두 호출을 실제 API에 맞게 수정한 뒤 새8개 및 전체485개가 통과했다. 검토 중 발견한 피아노롤 초기 표시의 무조건 선택 reveal과 스텝의 최초 선택 reveal을 정리했다. 명시적 새 선택/행 찾기에는 reveal을 유지한다. 최종 검토에서 낮은 피아노롤 초기 음역을27 이상으로 보정했다. 초기 packaging 경로의 이전 앱 존재 guard가 복사본 생성을 거절해 경로를 수정했으며 기존 앱은 덮어쓰지 않았다.

읽기 전용 검토에서 페이지/분할/음높이/스크롤·비유한 값의 보정, 허용된 스크롤 키, asset ID 변경 시 오디오 범위 초기화, 세션 generation 경계, 원본 범위별 cache, 음악 Undo와 보기 상태 분리를 확인했다. 외부 문서 보기 정보는 검증 후 사용한다. QA 변형 도구는 고정 사본·build68·완료/clean·미재생 상태와 기존 캡처에 일치하는 현재 문서를 요구한다. 네트워크·인증·권한·플러그인 실행 경로 변경은 없다. 이 변경 범위에서 미해결 출고 차단 결함을 발견하지 못했다.

현재 선택한 서클의 보기만 문서에 저장하며 다른 서클의 기억은 세션 내 cache다. 선택 노트/오토메이션 점·오디오 분할 커서와 오디오 수치 폼/MIDI 인스펙터 등 모든 보조 스크롤을 영속화한 것은 아니다. asset 교체·비정상 숫자·스크롤 크기 축소는 Core 검사로 확인했고 실제 native asset 교체는 이번에 수행하지 않았다. 실제 장치 재생·녹음·VoiceOver 발화와 사용자 앱 교체는 별도 검증 조건이다.
