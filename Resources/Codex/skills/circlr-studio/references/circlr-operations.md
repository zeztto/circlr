# circlr 0.12 operational contract

Discover the actual MCP tool catalog before work. The bundled adapter has 14 tools; custom specialists use its `--read-only` mode exposing snapshot, inspect, job and events only. Runtime configuration is inherited; inspect availability instead of assuming the tools are registered in an already open session.

## Time, identity and sound

- The hierarchy is album → composition/movement → section use → MIDI/audio/instrument/effect circles. A circle is a clock/orbit, not merely a graph dot. Spatial coordinates do not define pitch, musical order or cable semantics.
- Use IDs from snapshot/inspect. A reusable section and its occurrence (`useID`) differ; edit a use variation without silently changing the source or all occurrences. Instruments and track gain can affect multiple sections.
- Read effective context per use. Beat positions and MIDI durations use **quarter-note beats**: one bar = numerator × 4 / denominator. In 6/8, a bar is 3 quarter beats, not 6. Seconds = quarter beats × 60 / effective BPM only across a constant-tempo span. MIDI pitch is an integer 0–127; velocity 1–127. Audio sourceStart/duration are **seconds**, startBeat is quarter beats. An explicitly permitted pickup or release may cross a section boundary; determine current render behavior before relying on it.
- Global rhythmic grid/accent/subdivision and an actual repeating rhythm pattern are separate. Tempo, scale and meter may inherit or differ locally. Avoid flattening local context to a global setting.
- Current engine prepares PCM before playback. Editing a playing graph requires preparation/replay to hear changes. Live synth input exists, but continuous graph processing, universal plug-in latency compensation and crash isolation are not established.

## Read → propose → apply → verify

1. `circlr_snapshot` returns project/revision, tracks, assets, arrangements, selection and runtime/job state. `circlr_inspect` with useID (and arrangementID when needed) returns effective lanes, notes, graph, clocks and context.
2. `circlr_apply` requires `projectID`, `expectedRevision`, 1–128 operations; accepted batch = one Undo. Validate against the current inputSchema. `set_notes` and `generate_midi` **replace** a lane unless append=true. Preserve unrelated notes when replacing. `generate_midi` has simple chords/arpeggio/bass/pulse patterns; nuanced music usually needs deliberate `set_notes` or `add_midi` notes.
3. Supported operations: set_global, rename_project, set_instrument, set_track, add_section, set_section, connect_sections, add_midi, set_notes, generate_midi, set_node, set_effect, add_effect, connect, reorder_section, set_clip. Missing imports/lyrics/automation/mastering features cannot be invented as tools. Inspect complete context/instrument/effect objects before modifying them. Built-in synthVoice: 0 pad, 1 bass, 2 keys, 3 supersaw, 4 pluck, 5 lead.
4. `add_effect` inserts after an audio node and rewires its ordinary outputs; inspect sidechain and parallel paths before insertion. `connect` requires compatible real endpoints; cable direction is signal semantics, not canvas orientation. A musical intent such as “2 dB at 3 kHz” is not an `amount` value until the actual effect schema/implementation establishes its units.
5. `circlr_bounce` renders a section track with effects and preserves restorable originals. `circlr_restore_bounce` restores originals and leaves the audio archive disconnected. Wait for `circlr_job` terminal status, then inspect the returned node and routing. Rendering is asynchronous, not finished merely because a jobID exists.
6. `circlr_export` writes a **new absolute** WAV path, presently 48 kHz stereo 24-bit master. Other formats/stems are not arguments to this tool. `circlr_save` persists a .circlr project with embedded assets; `circlr_open` requires a clean project, is asynchronous, and may need macOS file access. Inspect the new project after open completes. Rendering and reading do not imply permission to overwrite other works.
7. `circlr_events` uses a sequence cursor and retains the last 500 events; poll no faster than once per second. `circlr_stop` globally stops playback and cancels the active render: it is not cancellation of one specialist. `circlr_focus` is optional presentation, unnecessary for editing. Avoid interrupting the artist's view or transport during background analysis.

## Limits and provenance

A read-only adapter rejects mutation and transport calls, including direct tools/call attempts. Filesystem sandbox settings alone do not constrain all MCP servers. This is not a system-wide capability sandbox or the future run-lease gateway: other inherited connectors and raw socket access are outside this adapter. Specialists must not use them to evade scope.

Record sample source, asset ID, acquisition/license evidence when available, and transformations. Ownership does not follow from a filename. Existing paid assets may be reused within the artist's authorized project; new purchases and credits require the current task's budget. Keep licensed media out of the public skill/app bundle. Keep creator credits, lyric authorship and artist review separate from generated technical logs.

## Engine 2 patches (circlr 0.13)

New synth patches use engineVersion=2: mono bass, velocity-shaped harmonic keys, TPT low-pass, resonance 0–0.9, stereoWidth 0–1, filterEnvelope -4–4 octaves. Bass and keys remain mono by design; width applies to the unison voices. Missing engineVersion decodes as legacy engine 1. Changing voice selects a new patch; editing a legacy patch preserves its engine unless explicitly upgraded. New reverb effects use renderVersion=2 for damped stereo diffusion. Missing renderVersion retains the legacy reverb. Never silently rewrite an existing song's engine version.
