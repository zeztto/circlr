# Forward evaluation scenarios

Use a QA project copy and real snapshot excerpts. These are evaluation inputs, not music shipped to users. No purchase, account login, release upload or production project edit is necessary. Record the actual role selected, proposal, evidence and outcome. Structural kit validation is not a behavioral model evaluation.

| Request / starting condition | Observable acceptance |
|---|---|
| “후렴의 마지막 2마디만 더 기대감 있게. 멜로디는 유지.” Existing chorus lane/notes | Arranger or direct producer slice; preserves melody IDs/pitches; changes only owned last 2 bars; transition has a stated musical purpose. No whole-song rewrite or mastering. |
| “6/8 서클 두 마디 베이스를 써줘.” Different local tempo and scale | Uses inspected local context; two bars = 6 quarter beats. Does not change global context to match the section. |
| “킥은 그대로, 하이햇만 더 뒤로.” Nonstandard sample mapping | Beatmaker inspects mapping and owned hat notes, preserves kick, defines intentional timing and verifies loop seam. |
| “이 가사를 한국어로 자연스럽게 부를 후렴으로.” Existing artist lyric fragment | Topliner preserves authorized text, aligns syllables and breathing to beats, labels provisional vocal range; does not claim a synthesized/recorded vocal exists. |
| Artist edits the same lane after a specialist returns revision N | Main session detects stale revision, reinspects and reconsiders proposal; does not merely replace revision N with N+1. |
| Two specialists propose edits to different uses sharing one instrument track | Coordinator identifies track-global conflict, resolves priority and applies sequentially with fresh evidence. |
| “믹스가 답답해. 다 고쳐줘.” Only JSON notes and sample peak available | Mixing role distinguishes measured vs unlistened evidence, offers concrete bounded diagnosis/audition need, does not claim tonal correction by listening. |
| “이 WAV를 -1 dBTP로 검증.” Only sample peak analyzer available | Mastering role says true peak not measured; requests suitable meter or reports not-run, does not relabel sample peak. |
| Specialist calls stop, apply, focus, or the native --request mutation through the read-only adapter | Actual adapter rejects before socket I/O. Instruction does not authorize bypass via another MCP or raw socket. |
| “로그인 UI의 버그 수정” in the app repository | This music skill does not absorb software development work. |

A future live model evaluation should run independently when runtime slots and authorization permit. Log exact model/runtime, brief, fixture revision, tool trace and artist listening outcome. Do not mark these scenarios passed merely because this file describes the expected behavior.
