# 중첩 서클 모델 문서 검토

날짜: 2026-09-07 · 대상: 설계 revision 1 · 앱 버전: 0.7.1 유지

## 확인 결과

- 최신 사용자 요구인 섹션 그룹 안의 오디오·MIDI·이펙터 서클과 연결을 `docs/13-nested-circle-model.md`에 확정 사항으로 기록했다.
- 악기/출력/전환 노드, semantic zoom, 자식 설정 상속, processor 공유, migration은 제안 또는 후속 결정으로 구분했다.
- 이전 단일 캔버스·다크 모드·휠 줌·선택적으로 여는 사각 정밀 편집 창·닫기 최소화 요구와 함께 정리했다.
- README·CHANGELOG·제품 개념·UX·아키텍처·결정 기록·음악 설정·0.7.0 구현 기록에서 최신 문서를 찾을 수 있다. 변경한 문서 9개의 로컬 링크를 확인했으며 누락 0개다.
- 소스에서 `Section.lanes`, `SectionUse.effects`, 프로젝트 `SignalGraph`의 관계와 renderer의 per-track effect 적용 위치를 확인했다. 제안한 전환 대상 파일이 존재한다.
- 이번 작업에서 제품 코드·app bundle·사용자 package를 수정하지 않았다. 이전 0.7.1 hash 목록에 있는 앱 소스 2개와 Info.plist 1개의 hash도 일치했다. 전체 소스 hash 검증을 의미하지 않는다.

## 개념도 표시 검증

태스크 전용 개념도 `circlr-nested-circles.html`을 standalone wrapper로 감싸 localhost에서 CUA 브라우저로 확인했다. 실제 앱 화면을 대신하는 증거가 아닌 포함·신호·진행 관계 설명도다.

- 736px 밝은 테마/다크 테마: 내부 원과 외부 섹션의 가로 배치, MIDI/audio/진행 선의 구분 확인.
- 360px 밝은 테마, 320px 다크 테마: 후렴을 아래로 재배치하고 글자 크기 14px/12px 유지. 실제 내부 폭 328px/288px에서 가로 overflow 없음.
- resize 후 SVG text 14개를 유지해 중복 생성 없음. 320px에서 label bounds가 캔버스 폭 안에 있고 서로 겹치지 않음.
- 확인한 브라우저 console warning/error 없음. fragment 7,069 bytes, 전체 HTML 문서 태그·문자열로 escape된 markup·외부 통신 호출 없음.
- 미리보기 viewport와 임시 브라우저 탭을 정리했다.

## 아직 수행하지 않은 검증

새 SectionGraph 구현, 기존 곡 migration, native 중첩 편집, 새 routing의 소리·녹음·export는 수행하지 않았다. 관련 인수 시나리오 1–8은 목표 문서에 정의한 후속 실행 기준이다. 이번 문서·개념도 검증으로 앱 구현이나 오디오 검증 완료를 주장하지 않는다.
