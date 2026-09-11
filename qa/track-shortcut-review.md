# 트랙 작업 단축키 — build89 검증

2026-09-10. 별도 authored `track-shortcut.circlr`의 build88 baseline과 build89 후보 UUID `52B4819A-9626-3B81-B040-D45A340763B2`를 비교했다. release 42.42초 성공 보고를 받았고, native 탐색과 별도 source parse 검증 범위를 구분한다.

setup은 첫 use에 오디오 복제·gain 이펙트2개·동일 track MIDI를 한 batch로 추가하고 복제 오디오의 연결만 해제했다. 최초 복제는 기본 위치의 공간 부족으로 전체 batch가 revision14에서 거절됐으며, beatOffset0을 명시하고 문서/revision 일치 guard를 거쳐 재시도했다. 최종 준비 문서는 r16이며 원본 section·다른 use·tracks·album·asset2개가 유지됐다. 빈 MIDI는 탐색 후보 구성용이며 제작된 음악으로 주장하지 않는다.

baseline은 ⌘1/⌘3에서 여러 후보가 있어도 첫 source/이펙트로 이동했다. final은 ⌘1에서 MIDI·오디오 union 3개를 표시하고, 아래 방향키와 Return으로 미연결 복제 오디오를 실제 열었다. ⌘3은 두 이펙트를 검색해 두 번째 행을 열었고, ⌘2는 단일 악기로 직접 이동했다. 음색 single case는 출력1 track에 생성된 단일 instrument다.

통합 키보드 track의 이펙트0개 상태는 현재 section·track 범위를 유지한 안내를 표시했고 Return/Esc 후 원래 MIDI 선택을 유지했다. 화면 오디오 버튼은2개, MIDI 종류 필터는1개로 좁혔으며 현재 찾기는 union을 해제해 전체 앨범31개 결과로 복귀했다. AX가 각 결과 수와 필터를 기록하고 JSON이 실제 도착 node를 확인한다. `source-search.png`는 1020×768 native 화면 근거다.

출력2의 이펙트2개 표시는 zero 사례가 아니다. 현재 StudioNavigation은 sidechain을 제외한 node-edge 도달성을 사용하여 effect→공유 router→두 output을 연결된 탐색 후보로 본다. checker는 해당 그래프 도달성을 확인하지만 포트별 DSP 경로가 같은 음향을 전달한다고 주장하지 않는다. 이 동작은 이번 변경 전후 유지되며 포트별 탐색 경로 정밀화는 후속 과제다.

추가 save와 실제 open job completed 후 재열기를 수행했다. 음악 전체·revision16·선택·camera는 동일하며, 저장 때 없던 기본 editor state가 재열기 후 hierarchyView.workspace.editor에 구체화된 차이만 있다. checker는 그 정확한 기본 객체를 검사한 뒤 나머지 전체 manifest 일치를 확인한다. 완전한 byte 단위 문서 일치로 표현하지 않는다.

`python3 qa/check-track-shortcut-evidence.py`는 baseline5·final8, 총13개 문서 캡처와7개 final AX 파일을 검사해 passed를 출력한다. 원본 studio manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 두 authored asset의 원본·fixture checksum은 유지됐다. output/audition attempts는0이며 물리재생·마이크·MIDI 입력은 시작하지 않았다. 전체 DAW 목표 완료나 포트별 라우팅 정밀화 완료를 주장하지 않는다.
