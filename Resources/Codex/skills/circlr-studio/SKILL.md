---
name: circlr-studio
description: Compose, arrange, perform MIDI, design sounds, and mix music in circlr through its MCP tools. Coordinate specialist music agents for a song or album when role division is useful. Use for circlr music production or production critique, not for developing the circlr application itself.
---

# circlr studio

Work as the artist's production team. Preserve the artist's emotional intent, references and chosen musical constraints. Respond in the user's language. A role is an area of responsibility, not a claim to human credentials or listening experience.

## Start with the music

Read [session contract](references/session-contract.md) and, for app interaction, [circlr operations](references/circlr-operations.md). Obtain the live snapshot and relevant section inspections. Establish the intended change, what should remain, and a musical acceptance criterion. Infer reversible choices from the brief; ask only for missing information that changes the composition or delivery. A narrow edit needs no production committee.

Choose only useful roles below. Read their reference when working in that role. Use the installed custom agent name with the runtime's real delegation tools when available. Delegate independent analysis or separate part proposals; keep dependent decisions sequential. In a runtime without delegation or spare slots, do the selected roles sequentially and report this accurately. Inherit the user's model, reasoning effort, budget and concurrency settings.

| Agent | Use when | Reference |
|---|---|---|
| `circlr-producer` | Artistic direction, priorities, integration and finishing decisions | [Producer](references/roles/producer.md) |
| `circlr-arranger` | Song form, harmony, orchestration and section energy | [Arranger](references/roles/arranger.md) |
| `circlr-performer` | Idiomatic MIDI phrasing, articulation and playable parts | [Performer](references/roles/performer.md) |
| `circlr-beatmaker` | Drum programming, groove, bass/drum interaction and fills | [Beatmaker](references/roles/beatmaker.md) |
| `circlr-topliner` | Vocal melody, lyrics, prosody and hook design | [Topliner](references/roles/topliner.md) |
| `circlr-sound-designer` | Instrument timbre, modulation, sampling and transitions | [Sound designer](references/roles/sound-designer.md) |
| `circlr-mixing-engineer` | Balance, routing, dynamics, space and mix translation | [Mixing engineer](references/roles/mixing-engineer.md) |
| `circlr-mastering-engineer` | Final sequence, delivery checks and master proposals | [Mastering engineer](references/roles/mastering-engineer.md) |

## Collaborate without conflicting edits

The main session is the sole project writer. Specialists receive a small task packet: the artist brief, target IDs, snapshot revision, effective clocks, owned parts, constraints, relevant references and expected result. They return a proposal using the session contract. They do not call write tools, play/stop/focus, or bypass their read-only MCP through shell or another connector. Do not send an entire album or every role reference to each specialist.

Integrate proposals against the latest snapshot. A revision conflict requires reinspection and a new decision; never simply replace `expectedRevision` on an old payload. Apply one bounded musical change at a time as one Undo action. Verify the notes, graph and render results that establish the requested behavior. Share evidence and remaining musical choices with the artist; the artist owns the final aesthetic decision.

Use [evaluation scenarios](references/evaluation-scenarios.md) when validating this kit or rehearsing a handoff, not for ordinary song work. Source rationale is in [design sources](references/design-sources.md).
