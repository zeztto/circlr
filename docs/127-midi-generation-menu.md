# MIDI 생성 메뉴와 실행 범위

상태: final4 Release42.59초·source review·native/checker10개 snapshot·rapid 입력·시각5장 검증 통과. `.build/build111-release-final4.log`, UUID `1968E4B0-2662-3544-ACAD-DDABF1EADB95`.

## 동작 계약

기존 MIDI 메뉴의 중첩 패턴 메뉴를 없애고 네 패턴 생성 항목을 직접 배치한다. 추가 패널을 만들지 않는다. 전체 명령 검색의 기존 MIDI 생성 네 명령에도 같은 요청 snapshot과 범위 detail을 적용하여 키보드 실행 경로를 일치시킨다. 메뉴에 표시한 실행 시작 위치는1-based이며 남은 길이는 편집 끝까지의 길이다. 박의 단위는4분음표다. 생성은 기존 노트를 유지하면서 겹쳐 추가하는 동작임을 함께 안내한다.

메뉴가 설명한 대상·커서·시작/끝·음악 문맥을 요청 snapshot으로 캡처한다. 실제 실행 시 현재 요청과 달라지면 stale 요청을 거절하며 다른 대상이나 범위에 조용히 생성하지 않는다. 안내와 실행이 일치하는지 source QA와 native 증거를 각각 확인한다.

## 후보와 증거 경계

초기 final 후보는 native 메뉴에서 CUA index/Return 활성화가 불확실해 일부 다른 패턴 또는 무변경이 관측됐다. 후보 증거는 보존하되 최종 승인 근거에서 제외한다. final2는 before revision24와 아래 incident까지만 관측했으며 두 scope 생성 성공 근거가 아니다. 두 scope 성공 검증은 final3/final4에서 수행했다.

final2에서는 빠른 메뉴 Esc→⇧⌘P→`리듬 펄스` 입력 중 검색 focus가 잡히기 전에 Space가 재생으로 전달되는 제품 focus 전환 결함을 관측했다. 출력 attempt1, didStart=false, outputNodeAcquisition timeout이 incident JSON에 기록됐다. root가 요청을 정지하고 QA 앱을 종료했으며 기존 사용자 앱 PID86114는 유지했다. 이 후보도 최종 승인에서 제외하며 출력 시도가 없었다고 표시하지 않는다.

후속 소스 수정은 `CommandSearchField`의 동기 focus, window-local palette 입력 guard, 부착 전 입력 buffer를 같은 palette ID에만 전달하고 늦게 replay하지 않는 경계다. final3은 출력 helper 실행을 거절하는 명시적 QA injection을 사용하며 attempts0을 필수 검증한다. final3 native9개 검사는56박/4박 리듬 펄스·Undo·공유 B·재열기·output0으로 통과했지만 빠른 paste1회가 실패해 최종 승인으로 사용하지 않는다. focus를 기다린 paste는 성공했다. pending 입력 replay를 `NSApp.sendEvent`로 보완한 final4에서 전체10개 snapshot과 빠른 ASCII/한국어 paste 입력을 재검증해 통과했다.

native 팝업의 `getAXStateAndScreenshot`는 state만 반환하여 메뉴 JPG를 확보하지 못했다. 메뉴는 AX 증거로 검토하고 palette·editor 이미지를 별도로 검토한다. 메뉴 스크린샷을 확보했다고 표시하지 않는다.

fixture 섹션은16마디×4박=64박이며 해당 중간 커서의 남은 길이는56박이다. 이전32박 가정은 사용하지 않는다. final4는 아래 checker 결과를 최종 승인 근거로 사용한다.

한국어 `typeText`는 focus된 field에서도 Space만 전달됐으나 ASCII 입력과 한국어 paste는 정상 동작했다. 이 관측은 도구 입력 경계로 구분하며 IME 조합 입력은 미검증이다. 이를 final2의 실제 focus 전환 결함과 혼동하지 않는다.

## 최종 검증 증거

- `.build/build111-release-final4.log`: Release42.59초, UUID `1968E4B0-2662-3544-ACAD-DDABF1EADB95`.
- `python3 qa/check-midi-generation-evidence.py`: final4 10개 snapshot PASS. 일반 scope56박·공유 scope4박의 리듬 펄스 추가, 기존 노트 보존·공유 B 반영·strict Undo·저장/재열기·자산2개 유지가 확인됐다.
- 빠른 ASCII 입력과 한국어 paste 모두 통과했다. final3의 빠른 paste 실패를 기다린 뒤 성공한 결과만으로 닫지 않고 final4에서 재검증했다. IME 조합은 미검증이다.
- final4의 `denyoutput=true`, `attempts0`은 명시적 QA output-helper deny 환경에서 확인했다. 이 결과로 실제 helper 재생이나 물리 출력이 성공했다고 판단하지 않는다. final2의 출력 attempt1 incident는 위에 별도로 남긴다.
- palette·editor 시각5장 검토와 source review가 통과했다. 팝업 메뉴는 네 항목·범위/겹침의 AX 증거만 확보했으며 메뉴 JPG는 없다.

물리 오디오 출력·recording·hotplug 검증을 이 메뉴 변경으로 대체하지 않는다. QA 앱은 ⌘Q로 정상 종료했으며 이후 프로세스 검사에서 기존 사용자 앱 PID86114만 관측됐다. stale 요청 거절은 source review로 확인했으며 native에서 별도 실행 검증하지 않았다.
