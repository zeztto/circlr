# Musical session contract

## Decisions and ownership

Artist → main-session coordinator → requested specialists → coordinator integration → artist review. The producer helps decide priorities; producer advice never overrides the artist. The coordinator may perform a role directly. Use actual delegation only where it helps and is available. Avoid duplicate writing by multiple agents, including track-global instrument/gain changes proposed by owners of different sections.

Begin with a concise brief: emotional narrative, genre influences, target audience/use, vocal or instrumental focus, reference qualities, tempo/key/meter constraints, section map, available assets, output expectations. Do not turn a previous song's tempo or genre into a global default. Record what may change and what the artist wants preserved. Unknowns may be marked unknown; do not invent artist approval.

For each specialist send a `circlr-task-v1` JSON object:

- `taskID`, `role`, `intent`, `acceptance`: stable work ID, role, intended musical result, observable checks.
- `projectID`, `baseRevision`, `scope`: real project ID and revision, explicit arrangement/use/lane/node/track IDs and ownership. Include a minimal snapshot excerpt or its readable path.
- `context`: effective tempo, meter, scale, section length, inherited/local context, chord progression and existing important motifs. Label hypotheses as hypotheses.
- `preserve`: protected notes, lyrics, melody, sounds, transitions and asset originals.
- `dependencies`: decisions required before this task, shared track/global state touched, other specialist outputs actually needed.
- `capabilities`: currently available tools/instruments, listening access, render/meter availability and budget limits.

Return `circlr-proposal-v1` with `taskID`, `role`, `projectID`, `baseRevision`, `scope`, `intent`, `operations`, `artifacts`, `checks`, `risks` and `nextAction`.

`operations` is an array of exact `circlr_apply` operation objects, or empty for advice, lyrics, mastering feedback or missing capabilities. No invented IDs. New objects whose IDs are only known after creation require a later inspected proposal. `artifacts` contains only actually written files with absolute paths and purpose; without write access, place lyrics/notation/arrangement recommendations directly in the response. `checks` states method, evidence and pass/fail/not-run for each criterion. `risks` includes unresolved musical or technical questions. `nextAction` says apply, revise, inspect, render, listen or ask-artist. No proposed operation is already an applied change.

## Integration and completion

Resolve overlapping targets and musical dependencies first. Verify section-local vs track-global scope. Use a fresh snapshot, inspect affected sections, review each operation and apply with that exact revision. If the project changes, reassess the proposal against new state. Do not rebase mechanically. Keep reversible originals. Preserve user work that happened meanwhile; do not blindly undo someone else's edit.

Listen or inspect the decisive evidence once available. Timing/pitch/routing checks, waveform measurements, render success and listening are distinct evidence. `play` sends sound to the Mac, not automatically to the model. Claim listening only when an audio-capable path actually provided the audio. A peak meter does not establish tonal balance, LUFS, true peak, phase coherence or artistic quality. Give bounded technical conclusions when listening is unavailable and identify the specific artist audition needed.

Progress messages should identify the real active role, target section, action and result. An agent name is not evidence that an agent was spawned. Future in-app chat must use actual task IDs and events, not fabricated role messages. Stop at the requested deliverable; do not add album mastering, purchases, release uploads or publishing to a small MIDI task.
