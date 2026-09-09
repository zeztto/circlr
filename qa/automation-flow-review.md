# 이펙트·오토메이션·바운스 통합 흐름

검증 프로젝트는 직접 작성한 QA 톤만 사용하는 `automation-flow.circlr`다. 기존 build80 바운스 결과를 재검증하고 build81에서 앱 재실행 후 저장된 프로젝트를 열었다.

## 확인한 동작

- Gain 이펙트를 경로에 넣고 −6dB로 설정한 저장 근거가 있다.
- 볼륨 자동화 두 점(0박 −6dB,64박 0dB,선형)을 추가하고 기준/자동화 바운스를 생성했다. 두 작업 모두 completed다.
- 두 WAV는 stereo24-bit48kHz,34초이며 해시가 해당 snapshot asset checksum과 일치한다.
- 0.5–3.5,8.5–11.5,16.5–19.5,24.5–27.5초 창에서 1,152,000개 channel samples 비교. 최대 절대오차1.1460029642092195e-7, 허용2e-6 미만.
- 바운스 Undo 후 음악·자동화가 복원됐다. `reopened-build81.json` 전체 manifest는 저장된 `automation-after-bounce-undo.json`과 동일하다.
- 궤도 모드로 전환한 뒤 view/layout 외 모든 필드가 동일하다. `orbital-reopened-build81.png`에서 길이64박, 점65박, 볼륨0dB, 곡선과 점 탐색·추가/삭제 컨트롤의 표시를 확인했다. 현재 캡처 창에서는 잘림이 재현되지 않았다.

## 재검증

`python3 qa/check-automation-flow-audio.py`는 기존 파일을 변경하지 않고 결과를 출력한다. `--output`으로 새 report를 남길 수 있으며 기존 경로는 덮어쓰지 않는다. `audio-comparison-recheck.json`은 이전 report와 수치가 같다. 앱 capture helper는 build80/81을 허용하고 각 snapshot에 실제 runtime build를 남긴다.

## 검증 경계

이번 턴에 새 바운스를 생성한 것이 아니라 보관된 산출물을 재검증했다. PCM 비교는34초 중12초이며 끝점·tail 전체 정확성 또는 다른 이펙트/parameter를 증명하지 않는다. dry 원본과 비교하지 않았으므로 정적 Gain −6dB DSP 정확성은 별도 검증 범위다. output/audition attempts는0으로 물리 출력·청취·상업 음악 완성도는 검증하지 않았다.

다음은 실제 장치 출력의 재점검과 동일 곡의 편곡 대안·전체 제작 동선이다. 궤도 편집기의 더 작은 영역·다수 겹친 점 조건은 추가 사용성 검증 범위다.
