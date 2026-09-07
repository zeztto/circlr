# 앨범 계층 core 1차 검증

날짜: 2026-09-07 · 상태: 부분 구현 / 전체 목표 진행 중

## 구현과 검증된 주장

- `Album`은 순서 있는 곡·악장 서클을 담는다. `Composition`은 하위 composition 또는 대안 편곡안을 담는다. 각 composition과 편곡안의 부모는 하나이며 순환·누락·중복 소유권을 거부한다.
- 기존 곡의 명시적 확장은 섹션·원본/사용 변형·이펙트 목록·편곡안·트랙·미디어/take 참조를 그대로 보존한다. version 1 decode와 version 2 package save/load를 확인했다. 기존 package를 별도로 저장하고 원본 manifest bytes가 변하지 않는 것을 테스트했다.
- 곡과 악장이 부모 설정을 상속하고 개별 tempo·meter·scale을 사용할 수 있다. 명시적 글로벌 지정은 모든 부모 override를 건너뛴다. 비활성 곡도 자신의 부모 context를 사용한다.
- 앨범 순서·악장 반복·섹션 반복을 절대 시간으로 계산했다. 테스트의 2개 악장 반복 후 다음 곡이 0·4·8·12·16초에 시작해 총 18초가 됐다. 이것은 실행 계획 검증이며 청취 검증이 아니다.
- 공간 좌표/zoom 편집은 곡 순서를 바꾸지 않는다. 잘못된 부모로 옮기는 명령은 문서를 부분 변경하지 않고 실패한다.
- 편곡안 복제가 기존 곡에 남고 선택 편곡안 변경이 앨범 계획에 반영된다. 알 수 없는 schema는 version 2로 덮어 바꾸지 않는다.

## 실행 근거

```sh
./scripts/swift-local.sh build
./scripts/swift-local.sh test --scratch-path .build/album-check --filter 'AlbumTests|CoreTests|CanvasGeometryTests|SectionGeometryTests'
```

빌드 성공. 최종 테스트 **28개, 실패 0개**: AlbumTests 9, CoreTests 10, CanvasGeometryTests 6, SectionGeometryTests 3. 로그: [album-core-fresh-tests.log](generated/album-core-fresh-tests.log).

기존 `.build`의 증분 테스트 실행은 `Project.init`/`outlined init with copy of Project`에서 SIGSEGV가 났다. 같은 소스를 새 scratch directory에서 전체 빌드하면 통과하므로 이전 layout을 사용하는 증분 산출물 충돌로 추정한다. 초기 실패 로그는 [album-core-tests.log](generated/album-core-tests.log)에 보관했다. 현재 모델 변경이 끝난 뒤 최종 release/native 검증은 깨끗한 빌드에서 다시 수행해야 한다.

## 미완료 경계

앨범/곡·악장 native 생성·중첩 화면, 내부 MIDI·오디오·effect graph, 같은 캔버스의 정밀 편집, 실제 앨범 playback/export를 검증하지 않았다. 기존 dist 앱, Info.plist, 사용자의 열려 있는 곡을 이 단계에서 변경하지 않았다. 전체 목표는 완료되지 않았으며 후속 구현과 native/audio 증거가 필요하다.
