# 테이크 내용 요약과 현재 내용 비교

상태: build107 final2 Release40.16초·아래 native 확인. UI checker 최종 대조 통과.

테이크 이름과 노트/클립 수, 현재 내용과의 일치 여부를 표시한다. 일치 표시는 active 테이크 체크가 아니라 실제 내용 비교다.

Core는 정확한 target을 해석하고 legacy 자료는 첫 matching 대상을 사용한다. 비교는 비어 있지 않은 payload에만 수행한다. 이름·순서·active 상태만으로 내용 일치를 판단하지 않는다.

검증은 정확한 target·legacy 첫 matching·빈 payload 제외·노트/클립 수와 일치/불일치, 실제 header 가시성·선택 동작·음악 보존을 분리한다. 최종 근거가 확보된 범위만 완료로 기록한다.

## 최종 후보 관측과 제한

UUID `6FACD725-D2D7-3FB9-B4B9-280800305AE8`. 첫 Release73.20초 후보는 첫 선택 뒤 후속 선택 no-op를 발견했다. menu의 full identity `.id`와 고유 AX ID를 추가해 갱신했으며 캐시가 원인이었다는 설명은 추정으로 남긴다.

baseline106 revision14와 첫 후보 Undo 후 final2 initial16의 음악은 같다. 고유 AX ID click으로 short16초 적용17→first32초 전환18→Undo19→재선택20→Undo 두 번22로 음악을 완전히 복원했다. final8개 상태는 initial/applied/switched/undo-switch/reselected/undo/restored/reopened다. saved/reopened/disk revision22 strict 동일·자산2개를 확인했으며 checker8개 상태·자산2개·테이크5개·strict r22 재열기도 통과했다.

AX에서 메뉴3개·다른 arrangement 제외·MIDI1/clip1·현재 내용 일치를 확인했다. compact header 이미지는 확인했으나 popup screenshot은 확보하지 못했다. 키보드 메뉴 선택은 미확인이다. 원본 편집·name commit·stale intent·record busy는 source 확인 범위이며 해당 native 성공으로 확대하지 않는다.

종료 점검에서 기존 사용자 PID86114만 실행 중이고 검증 앱과 helper는 남아 있지 않음을 확인했다.
