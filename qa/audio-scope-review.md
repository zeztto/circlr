# 오디오 편집 범위 — build86 native 검증

2026-09-10. 별도 authored `audio-scope.circlr`의 build85 baseline에서 use-only 복제 오디오를 만든 뒤 shared original 범위로 전환해 빈 편집 화면을 재현했다. 초기 build86의 Return 회귀와 수정한 keyboard 후보를 구분한다.

`scenario.json`의 copyNodeID는 대상 use의 graphEdits.addedNodes에만 있고 clip은 laneOverrides에만 있다. 원본 section graph/lanes에는 해당 node/clip이 없다. `baseline/empty`는 이 복제 node 선택과 workspace.original=true를 유지하지만 선택 clip ID가 없고 AX에서 오디오 파형 편집기도 사라졌다. 같은 shared original 상태에서 원본 source node로 이동하면 파형은 다시 표시되지만 편집 범위가 드러나지 않았다.

`before/duplicated/empty/shared-source` 네 캡처는 대상 use 외 원본 sections, 다른 use, 자산과 다른 모든 음악 필드가 유지됐다. 범위 전환과 source 이동 자체는 음악을 바꾸지 않았다. checker는 이 상태를 수정 전 회귀 재현으로 검사한다.

첫 build86 후보의 11개 캡처에서는 공유 원본 checkbox와 use-only 오디오의 명시적 복구 안내가 표시됐다. shared-trim은 원본 section clip의 sourceStart=.1/duration=31.9만 바꿨으며 Undo가 복원했다. use-trim은 대상 use의 laneOverride clip만 sourceStart=.2/duration=31.8로 바꾸고 원본 section·다른 use를 그대로 유지했으며 Undo가 복원했다. 범위·선택 전환은 음악 전체를 유지했다.

도움말이 열린 상태에서는 복구 버튼이 disabled이며 shared 범위가 유지됐다. 그러나 도움말 종료 후 Return은 AlbumCanvas 처리에 소비되어 복구하지 못한 `return-noop`을 관측했다. 직접 버튼 click은 같은 copy node를 유지한 채 use 범위로 복구했다. 이 초기 후보를 keyboard 복구 통과로 계산하지 않고 후속 후보에서 재검증했다.

최종 keyboard 후보 UUID `6902AC6C-552F-30C6-9B8F-C18DF5AC7B29`, release 41.19초에서 Return은 같은 copy node를 유지하면서 original=false로 전환하고 파형을 복구했다. 도움말 표시 중 Return은 범위를 변경하지 않고 disabled 상태를 유지했다.

출력 1 node를 muted=true로 설정한 상태에서 UI 바운스 job completed를 확인했다. 원본 source와 다른 use는 그대로이며 대상 use에 새 audio node/lane/edge, 원래 입력 edge 보관 metadata, 배치 위치와 새 asset 1개만 추가됐다. output node mute는 그대로 남았다. 새 바운스가 shared original에 없어도 Return으로 이번 사용으로 전환해 파형과 원본 복원 버튼에 접근했다. 원본 복원은 기존 입력 edge를 복구하고 바운스 node를 mute한 보관 상태로 남겼다. Undo 세 번으로 복원·바운스·output mute를 역순 복구했고 실제 open 완료 후 최종 문서가 일치했다.

`python3 qa/check-audio-scope-evidence.py`는 baseline4·초기final11·keyboard13의 28개 캡처에서 변경 delta와 전체 보존을 검사해 `status: passed`를 출력한다. Undo/save 뒤 미참조 render WAV가 fixture에서 정리됐으므로 Bounces의 `9142E730-0ABF-4833-85E9-C43BE10E5CFE.wav`를 checksum으로 찾아 `keyboard/bounced.wav`에 보존했다. SHA256 `d30e087cfd40bbf00901f9b05eb2255a5feee74e5eab583f3b58012a82dd7255`는 bounced manifest와 일치한다. checker가 파일을 직접 읽어 stereo 24-bit 48kHz, 1,632,000frames/34초와 peak .0799560546875, RMS .03060942668524629를 재계산했다. output node mute 상태에서도 출력 앞 오디오가 비영점으로 렌더됐으며, 실제 청감과는 별개다.

원본 studio manifest SHA256은 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 일치하고, authored asset 2개의 원본·fixture 실제 파일은 checksum을 유지했다. output/audition attempts는 0이고 재생·마이크·MIDI 입력은 시작하지 않았다. offline 바운스 렌더 1회는 물리 출력이나 청감 성공과 구분한다.
