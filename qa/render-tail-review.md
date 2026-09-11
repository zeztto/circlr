# 렌더 잔향 길이 — build87 검증

2026-09-10. 별도 authored `render-tail.circlr`에서 build86의 고정 2초 baseline과 build87 auto/manual을 실제 offline 파일로 비교했다. 최종 QA 앱 UUID는 `834466A4-A91B-32E3-985F-E675044A8F95`다. `python3 qa/check-render-tail-evidence.py`는 baseline4·final18, 총22개 문서 캡처와 invalid/cancel job 기록을 검사해 passed를 출력한다.

## 실제 PCM과 길이

첫 use의 source 뒤에 1초 delay, feedback .8을 삽입했다. build86 bounce는 body32+tail2=34초이며 build87 수동2초도34초다. 자동은 tail42초를 추정해74초가 됐다. 두 번째 use는 경로 밖이므로 album export도 본문32초를 기준으로 하며106초가 아니다.

checker가 stereo24-bit48kHz WAV를 직접 읽어 길이·peak·RMS·마지막0.1초를 재계산했다. baseline과 수동bounce, 자동bounce의 첫34초 PCM bytes는 정확히 같다. 자동bounce 마지막0.1초 peak는3.814697265625e-6, 수동은0.028889894485473633이다. 이는 자동 파일에서 여운이 더 감소한 관측이며 청감 평가가 아니다. job의 Float 진단은24-bit 양자화 오차2LSB 이내에서 직접 계산과 일치한다. 수동bounce/export는 마지막 신호 안내를 표시했고 자동은 endWindowHasSignal=false였다.

바운스를 넣은 export도 auto74초/manual34초를 유지했다. 원래 source·다른 use·관련없는 음악은 그대로이며 render delta는 대상use의 새node/lane/edge/보관입력/배치와 asset1개뿐이다. 각 Undo는 bounce 이전 delay 문서로 돌아왔다. 파일 렌더 완료는 baseline1회와 후보6회로총7회다.

## 입력·한도·취소

121초 입력은 native API에서0–120초 범위 오류로 거절됐고 sequence 외 snapshot 상태가 같았다. UI의 수동2초 설정에는 자동추정보다 짧다는 안내를,120초를 넘는 효과구성에는 자동잔향 한도 안내를 확인했다. `manual-set`, `invalid-121`, `export-warning`, `cap-ready`의 AX와 관련 PNG를 보존했다.

한도 구성은147.9546667초 추정을120초로 제한했지만 실제 렌더는 합산출력0dBFS 초과 보호로 failed가 됐다. 따라서120초 파일 렌더 성공으로 계산하지 않는다. 자산2개·revision·음악이 유지됐다. 별도 cancel-job 기록은 같은 job의 running → STOP → cancelled를 확인했고 settled/preserved에서도 같은 취소 상태와 revision22를 유지했다. `auto-running.ax.txt` 같은 파일명만으로 실제 running 화면을 주장하지 않는다. 취소 근거는 구조화된 job 기록이다.

## 최종 저장과 보존

cap 효과를 Undo한 뒤 auto bounce를 다시 생성해 저장했다. 실제 open 완료 후 문서와 revision24가 유지됐고 재export도 74초였다. 재열기 bounce WAV는 최초 auto WAV와 바이트가 동일하며 SHA256은 `ce518cec2035591113d335d41c6bd15fe25163f8b7e6aacdc6dcc689b09fd686`이다. 재열기 export도 최초 export와 바이트가 동일하며 SHA256은 `06132c458b24398495dea79190757baa3fbcc1922c6e5a488c30060777186e72`이다. 재생성 문서는 generated IDs와 sourceRevision 외 최초 auto 문서와 일치한다.

최종 fixture는 의도적으로 원본 asset 2개와 새 auto bounce 1개를 보존한다. 실제 fixture WAV checksum을 검사했고 원본 studio manifest SHA256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 두 authored asset checksum도 유지됐다. 캡처 전체 output/audition attempts는 0이며 마이크·MIDI 입력·물리 재생은 실행하지 않았다. offline 바운스/export 검증은 청감·장치 출력·전체 DAW 완료를 대체하지 않는다.

Codex kit의 field 경로 설명만 갱신한 `kit-final` 패키지는 manifest 재생성 후 kit 9개 검사·서명·전체 kit hash 검증을 통과했고 binary UUID는 기존 final과 같은 `834466A4-A91B-32E3-985F-E675044A8F95`다. `kit-final`은 추가 GUI 실행 없이 문서만 갱신한 패키지이며 native 검증 근거는 기존 final 캡처를 유지한다.
