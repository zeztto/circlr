# MIDI 가져오기 피드백과 대상 표시

상태: build132 최종 Release·아래 native 화면/저장 검증을 완료했다. 독립 첫 6개 화면 감사는 PASS했으며 추가 unsupported 화면의 오류 고정·keepCurrent 회복과 음악 보존도 독립 감사 PASS로 확인했다. build131에서 발견한 불편을 해결한 범위이며 전체 사용성 완료를 뜻하지 않는다.

## 계약

가져오기를 막는 이유는 고정 실행 버튼 아래에서 스크롤 없이 보인다. 잘못된 시작 위치는 위치 오류임을 명시하며, 수정하면 실행 가능 상태로 돌아간다. 가져오기 대상은 캔버스의 use 별명과 같고 편곡명·사용 순서를 함께 표시한다. UUID는 도움말로 유지한다. 노트·템포·Undo 계약은 바꾸지 않는다.

## 검증 계획

Release typecheck와 별도 noIO 앱에서 기본 대상 별명, abc 및 범위 초과 입력의 오류/실행 차단, 수정 후 회복, 트랙 선택 해제의 고정 오류, 취소 시 음악 불변을 확인한다. 템포를 따르는 오디오가 파일 템포를 지원하지 않는 사본에서도 고정 오류를 확인하고 현재 템포 유지로 회복한다. 스크롤 전후 고정 메시지 가시성을 JPEG/AX로 대조하고 저장/재열기에서 음악 데이터가 같음을 검증한다. 원본 사용자 앱과 샘플은 보존한다.

## 최종 결과와 제한

최종 Release는 47.20초에 성공했다 (`.build/build132-release-final.log`). 첫 후보는 사용할 수 없는 accessibilityHelp API로 컴파일에 실패했고 표준 accessibilityHint로 교체한 뒤 통과했다. 최종 UUID는 `47F0637B-7DBB-3F3C-BCD2-DFCFBACAB94E`이며 production strict 서명을 확인했다.

`qa/generated/midi-import-feedback/final132`의 실제 1024×768 창·122pt 콘솔에서 default-ready의 대상 별명 B 일치, invalid-top/scrolled의 abc 오류 고정 표시, 범위 밖 65박 차단·수정 후 recovered, no-tracks의 실행 차단을 AX/JPEG로 확인했다. unsupported-error에서는 파일 tempo를 지원하지 않는 오디오의 오류를 고정 영역에서 확인했고 keepCurrent로 바꾼 unsupported-recovered도 확인했다. 첫 6개 화면과 추가 unsupported 화면 모두 독립 감사를 통과했다. 추가 감사는 r85 음악 보존과 production strict 서명·UUID도 직접 확인했다.

before=cancelled=reopened=디스크 manifest는 r95에서 전체가 정확히 같았다. unsupported 사본은 r85 음악을 유지했다. 두 사본의 자산 6개/5개 SHA와 noIO 0을 확인했다. QA 앱을 종료하고 원본 사용자 PID 86114를 유지했다.

전환 중 default.jpg/AX는 Go To 대화상자이므로 성공 화면 근거에서 제외한다. NSOpenPanel 자동화의 Cmd+A/Return 동작이 예상과 달랐고 직접 AX 입력·Open으로 파일을 선택했다. 앱 key monitor가 원인인지는 확정하지 않았으며 일반 키보드 파일 선택 전체를 검증했다고 주장하지 않는다. 물리 오디오·실제 청취는 실행하지 않았다.

다음 음악 표현 범위는 MIDI pitch bend의 저장·채널/범위·render timing·GUI/MCP 계약 계획이다. 이번 오류 표시 수정으로 전체 앱 사용성이나 DAW 기능을 완료 처리하지 않는다.
