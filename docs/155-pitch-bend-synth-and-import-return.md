# 내장 신스 pitch bend와 MIDI 가져오기 취소 복귀 검증

상태: build133의 내장 신스 DSP 및 아래 MIDI 가져오기 취소 복귀 검증을 완료했다. 전체 MIDI 표현 편집·모든 backend·물리 청취 완료를 뜻하지 않는다.

## 구현 범위

[Pitch bend 계약](154-midi-pitch-bend-plan.md)의 저장·source/occurrence packet을 내장 신스 DSP에 연결한다. source별 controller 상태와 voice 소유권을 유지하며 서로 다른 연주와 반복 release를 분리하는 범위다. 실제 raw SMF pitch bend/RPN parser, GUI bend 곡선 편집, MCP 표현 명령, sampler·AU의 bend 지원은 아직 없다. 저장된 표현을 모든 backend가 재생한다고 주장하지 않는다.

MIDI 가져오기 미리보기를 취소하면 진입 전 편집 주소와 workspace로 복귀하도록 개선한다. 공유 스텝의 페이지·선택과 일반 MIDI의 viewport가 대상이다. 적용 성공 때 새로 가져온 target을 선택하는 동작을 유지하며, 프로젝트가 달라진 stale 취소로 과거 프로젝트를 복원하지 않아야 한다.

## 현재 확인한 근거

C baseline 비교는 48 kHz stereo·1초 길이의 24개 경우에서 byte-exact PASS했다 (`.build/pitch-bend-dsp-reference/comparison.json`). 이는 기존 경로 보존의 증거이며 변화하는 bend의 음정 정확도나 전체 backend 지원을 뜻하지 않는다. DSP와 UI의 독립 소스 검토는 PASS했다.

초기 주파수 테스트에서 zero-cross와 autocorrelation 측정의 octave 오류가 발생했다. C FFT의 `spectrum.json`에서 220/880 Hz를 확인하고 기대 음정은 유지한 채 Goertzel 측정으로 교체했다. 이후 Core/Audio 회귀는 780개·내부 skip 2개·실패 0개, 99.382초에 통과했다 (`.build/build133-regression-final.log`). 실제 재생 포함 테스트 1개는 별도로 제외했으며 물리 출력 성공을 뜻하지 않는다.

초기 build133 후보의 Release는 85.43초에 통과했다 (`.build/build133-release.log`, UUID `4F6F43CF-EDF4-3DF5-9221-2154F2726B37`). 이것은 아래 native 결함 수정 전 후보이며 최종 Release로 세지 않는다.

초기 후보 `final133`의 native 검증에서는 공유 스텝 페이지 2·전체 hierarchyView·음악 보존은 통과했지만 임시 cursor가 54에서 64로 초기화됐다. 일반 MIDI의 Escape 취소에서는 곡 상위로 이동하는 문제도 발견했다. 두 결함을 수정한 후보의 결과는 아래에 별도로 기록한다. 저장된 workspace 일치만으로 임시 편집 상태·키보드 복귀 전체가 정확하다고 선언하지 않는다.

## native 비교 계약

[QA 절차](../qa/midi-import-return-procedure.md)와 `qa/verify-midi-import-return-qa.py`를 사용한다. 취소 전후 project/revision/address/note selection, manifest의 전체 `hierarchyView`, 나머지 음악·자산 필드를 각각 비교한다. 실제 1024×768 창·122pt 콘솔에서 shared step page 2와 일반 MIDI viewport를 AX/JPEG로 대조한다. 저장 직전 pending 복귀가 실제 화면에 반영되는지도 확인한다.

단일 트랙 import 적용 후 새 target 선택은 취소 비교와 별도로 검사한다. stale project 경계는 실제 수행 여부를 구분한다. 실제 출력·물리 오디오·청취 및 전체 음악 제작 완료는 별도 검증이다.

## 최종 후보 결과

수정 후보 Release는 44.41초에 통과했다 (`.build/build133-release-corrected.log`). UUID는 `FD10A811-EE84-3793-93BF-DF0382790BA1`이며 최종 패키지 codesign도 PASS했다. 위 Core/Audio 회귀 780개와 별도로 실제 bounce archive 저장/읽기·원본 복원 테스트 1개가 0.232초에 통과했다.

`corrected133` native에서는 일반 MIDI의 노트 3개 선택과 안정된 전후 캡처의 viewport가 독립 비교에서 정확히 일치했다. 초기 캡처 쌍의 viewport 경고는 이 안정된 쌍의 PASS와 구분한다. 공유 스텝은 페이지 2·1/32·C4 pitch 60·19스텝를 설정하고 버튼 취소 뒤 정확히 복귀했다. Escape는 draft를 취소하며, 도움말이 열린 경우 첫 Escape는 도움말만 닫는다. 수치 `abc` 입력 뒤 첫 Escape는 4로 복구하고 draft는 유지했다.

실제 가져오기는 r96에서 새 MIDI 1개를 만들고 그 target을 선택했다. Undo 후 r97의 음악은 원본과 정확히 같았다. 저장/재열기에서도 전체 hierarchyView·음악과 자산 6개 보존을 확인했다. no-I/O helper 5개는 exit 78을 확인했고 소유한 corrected133 QA PID 4338만 종료했고 ps로 QA 종료와 사용자 production 앱 PID 86114 유지를 확인했다.

stale project·삭제된 target·늦은 UUID 경계는 소스 검토만 수행했으며 native 실행으로 검증하지 않았다. schema5 표현의 오디오 지원은 내장 신스에 한정한다. SMF bend 가져오기/내보내기, 곡선 UI, MCP 표현 편집, AU·sampler 지원은 남아 있다.
