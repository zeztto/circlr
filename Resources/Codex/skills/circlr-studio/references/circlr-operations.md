# circlr operational contract

Discover the actual MCP tool catalog before work. The bundled adapter has 15 tools; custom specialists use its `--read-only` mode exposing snapshot, inspect, job and events only. Runtime configuration is inherited; inspect availability instead of assuming the tools are registered in an already open session.

## Time, identity and sound

- The hierarchy is album → composition/movement → section use → MIDI/audio/instrument/effect circles. A circle is a clock/orbit, not merely a graph dot. Spatial coordinates do not define pitch, musical order or cable semantics.
- Use IDs from snapshot/inspect. A reusable section and its occurrence (`useID`) differ; edit a use variation without silently changing the source or all occurrences. Instruments and track gain can affect multiple sections.
- Read effective context per use. Beat positions and MIDI durations use **quarter-note beats**: one bar = numerator × 4 / denominator. In 6/8, a bar is 3 quarter beats, not 6. Seconds = quarter beats × 60 / effective BPM only across a constant-tempo span. MIDI pitch is an integer 0–127; velocity 1–127. Audio sourceStart/duration are **seconds**, startBeat is quarter beats. An explicitly permitted pickup or release may cross a section boundary; determine current render behavior before relying on it.
- Global rhythmic grid/accent/subdivision and an actual repeating rhythm pattern are separate. Tempo, scale and meter may inherit or differ locally. Avoid flattening local context to a global setting.
- Current engine prepares PCM before playback. Editing a playing graph requires preparation/replay to hear changes. Live synth input exists, but continuous graph processing, universal plug-in latency compensation and crash isolation are not established.

## Read → propose → apply → verify

1. `circlr_snapshot` returns project/revision, tracks, assets, arrangements, selection and runtime/job state. `circlr_inspect` with useID (and arrangementID when needed) returns effective lanes, notes, graph, clocks and context.
2. `circlr_apply` requires `projectID`, `expectedRevision`, 1–128 operations; accepted batch = one Undo. Validate against the current inputSchema. `set_notes` and `generate_midi` **replace** a lane unless append=true. Preserve unrelated notes when replacing. `generate_midi` has simple chords/arpeggio/bass/pulse patterns; nuanced music usually needs deliberate `set_notes` or `add_midi` notes.
3. Supported operations: set_global, rename_project, set_instrument, set_track, add_section, set_section, connect_sections, add_midi, set_notes, set_step, edit_notes, generate_midi, set_node, set_effect, add_effect, connect, reorder_section, set_clip, edit_audio, set_automation. Missing imports/lyrics/plugin-parameter automation/mastering features cannot be invented as tools. Inspect complete context/instrument/effect objects before modifying them. Built-in synthVoice: 0 pad, 1 bass, 2 keys, 3 supersaw, 4 pluck, 5 lead, 6 electricPiano, 7 organ, 8 brass, 9 strings.

## Gain and pan automation (circlr 0.19)

`set_automation` takes actual useID/nodeID and parameter (`gain` or `pan`). automationPoints replaces that parameter's complete curve, so inspect and preserve existing point IDs when editing. Each point has beat, value, optional id (generated when missing), optional shape (`linear` default, or `hold` for its outgoing segment). Empty points clears the curve; omit points with enabled=false/true to bypass/read it while keeping data. There are up to 4096 ordered distinct beats per parameter. gain multiplies static node gain (0–4); pan is -1 left, 0 center, 1 right with unity at center. MIDI nodes have no audio automation; use their instrument/mix/output node instead.

Point time is local quarter beats from node.startBeat, with node tempo or inherited parent tempo map. Explicit node.lengthBeats repeats the curve for node.repeatCount and then holds its final value. Without a local length the curve progresses continuously, including implicit audio source repetitions. Before/after points and section tails hold boundary values. A split copies the same clock/curve; an implicit-length audio duplicate moves its curve points by the same beatOffset and rejects negative point time. Output automation is omitted in pre-output bounce, then applied once by the retained output node. Plugin/synth parameter and global bus automation are not implemented. snapshot.automationEditor exposes visible/parameter/selectedPointID/displayBeats as read-only UI state. Edits use the existing revision and atomic Undo contract; never blindly resubmit on a conflict.

## Audio editing (circlr 0.18)

`edit_audio` takes actual useID, audio nodeID and edit. split requires sourceOffset in source seconds from the selected clip start. fade requires fadeIn and fadeOut, nonnegative source seconds whose sum cannot exceed clip duration. duplicate accepts optional beatOffset in local quarter beats; omit to place after the last repetition. delete removes the selected circle and its connections, preserving source assets. Reinspect after edits for fresh IDs; never invent them. GUI/MCP share one atomic Core command and Undo. MCP edits the current use variant.

Splits preserve the original resampling/stretch window, cycle and inherited fades. New fades multiply inherited envelopes; setting the new fades to zero cannot remove pre-split envelopes. Trim stays inside the preserved render window. Restoring a bounced fragment archives and disconnects its entire derived family and restores the original route when still compatible. Do not write renderWindow or familyID directly. Duplication cannot start outside the section and may be cut off by its end; extend section length first when needed. No recording/import/automation tool has been added by this feature.
4. `add_effect` inserts after an audio node and rewires its ordinary outputs; inspect sidechain and parallel paths before insertion. `connect` requires compatible real endpoints; cable direction is signal semantics, not canvas orientation. A musical intent such as “2 dB at 3 kHz” is not an `amount` value until the actual effect schema/implementation establishes its units.
5. `circlr_bounce` renders a section track with effects and preserves restorable originals. `circlr_restore_bounce` restores originals and leaves the audio archive disconnected. Wait for `circlr_job` terminal status, then inspect the returned node and routing. Rendering is asynchronous, not finished merely because a jobID exists.
6. `circlr_export` writes a **new absolute** WAV path, presently 48 kHz stereo 24-bit master. Other formats/stems are not arguments to this tool. `circlr_save` persists a .circlr project with embedded assets; `circlr_open` requires a clean project, is asynchronous, and may need macOS file access. Inspect the new project after open completes. Rendering and reading do not imply permission to overwrite other works.
7. `circlr_events` uses a sequence cursor and retains the last 500 events; poll no faster than once per second. `circlr_stop` globally stops playback and cancels the active render: it is not cancellation of one specialist. `circlr_focus` is optional presentation, unnecessary for editing. Avoid interrupting the artist's view or transport during background analysis.

## Limits and provenance

A read-only adapter rejects mutation and transport calls, including direct tools/call attempts. Filesystem sandbox settings alone do not constrain all MCP servers. This is not a system-wide capability sandbox or the future run-lease gateway: other inherited connectors and raw socket access are outside this adapter. Specialists must not use them to evade scope.

Record sample source, asset ID, acquisition/license evidence when available, and transformations. Ownership does not follow from a filename. Existing paid assets may be reused within the artist's authorized project; new purchases and credits require the current task's budget. Keep licensed media out of the public skill/app bundle. Keep creator credits, lyric authorship and artist review separate from generated technical logs.

## Engine 2 patches (circlr 0.13)

New synth patches use engineVersion=2: mono bass, velocity-shaped harmonic keys, TPT low-pass, resonance 0–0.9, stereoWidth 0–1, filterEnvelope -4–4 octaves. Bass and keys remain mono by design; width applies to the unison voices. Missing engineVersion decodes as legacy engine 1. Changing voice selects a new patch; editing a legacy patch preserves its engine unless explicitly upgraded. New reverb effects use renderVersion=2 for damped stereo diffusion. Missing renderVersion retains the legacy reverb. Never silently rewrite an existing song's engine version.

## Step editing (circlr 0.16)

`set_step` edits ordinary MIDI notes through the same command as the GUI. Use actual useID/laneID, zero-based stepIndex, pitch 0–127, enabled boolean, subdivisions 1/2/3/4/6/8 per quarter beat (default 4). Optional velocity is 1–127 and gate is 0.01–16 steps. Provide the matching MIDI nodeID when it has a local length. Existing onsets in the same pitch/cell retain their IDs, off-grid timing and unspecified values. Repeated enable is idempotent; disable removes matching onsets, not notes sustained from earlier cells. A different grid resolution never quantizes existing music. Avoid assuming every sampler maps GM percussion: inspect sample zones/rootPitch and actual notes first.

## Selection editing (circlr 0.17)

`edit_notes` takes useID, laneID, unique existing noteIDs and edit. transpose requires semitones; move and duplicate require beatOffset in quarter beats; velocity requires 1–127. quantize takes subdivisions (default 4, same supported grids as set_step) and strength 0–1 (default 1); delete needs no additional parameter. Supply the matching MIDI nodeID for a locally sized circle. Group movement preserves relative pitch/time and rejects a selection crossing the permitted boundary. Quantize changes starts and preserves length, velocity and IDs; duplicate creates new IDs. Unselected notes and audio are preserved; a no-op does not create Undo. GUI MIDI file import (format 0/1, note performances only) is available through ⌥⌘I but is not an MCP tool. snapshot includes selectedNoteIDs and recording.midi/audio/permissionPending; circlr_stop cancels a pending microphone request.


## Audio recording (0.20)

`circlr_record` starts the currently selected section/track and requires projectID plus expectedRevision. Only call it when the user requests microphone recording. First inspect the selection or focus the requested music circle; do not select an unrelated track. macOS may ask the user for microphone access. Read `snapshot.recording`: phase authorizing/starting/recording/cancelling/finishing/failed/idle, busy, seconds, peak, format (rate/channels), message and recoveryPath. A start reply is an acknowledgement, not evidence of recorded audio.

`circlr_stop` cancels pending input or closes the collection gate and finalizes asynchronously. Wait until busy=false and inspect the actual assets/takes and music revision. Never retry a pending/finishing worker, start a second capture, or bypass macOS permission. The current input is the default device's first two channels (one for mono). A disconnected or stalled input finalizes received frames. Late completion cannot write into a different project or deleted destination; recoveryPath preserves that file. There is no accompaniment/latency synchronization or input channel selector in this version.
