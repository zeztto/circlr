#!/usr/bin/env python3
"""Circlr local MCP adapter. Python standard library only; no GUI or shell execution."""
import argparse
import json
import math
import os
from pathlib import Path
import socket
import sys
import uuid

MAX_MESSAGE = 8 * 1024 * 1024
VERSIONS = {"2025-11-25", "2025-06-18", "2025-03-26"}


def schema(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


STRING = {"type": "string"}
TAIL_SECONDS = {"type": "number", "minimum": 0, "maximum": 120, "description": "Optional manual release tail in seconds. Omit for automatic estimation (2-second floor, 120-second cap). Independent of UI preferences; job.tail reports estimated/effective duration and notices."}
REVISION = {"projectID": STRING, "expectedRevision": {"type": "integer", "minimum": 0, "maximum": 9223372036854775807}}
SCOPE = {"arrangementID": STRING, "useID": STRING}
PORT_ID = {"type": "string", "minLength": 1, "maxLength": 1024}
PORT_ADDRESS = {"oneOf": [
    schema({"signal": schema({"_0": PORT_ID}, ["_0"])}, ["signal"]),
    schema({"composition": schema({"_0": PORT_ID}, ["_0"])}, ["composition"]),
    schema({"section": schema({"arrangementID": PORT_ID, "useID": PORT_ID}, ["arrangementID", "useID"])}, ["section"]),
    schema({"music": schema({"arrangementID": PORT_ID, "useID": PORT_ID, "nodeID": PORT_ID}, ["arrangementID", "useID", "nodeID"])}, ["music"]),
]}
GROUP_PARENT = {"oneOf": [PORT_ADDRESS["oneOf"][1], PORT_ADDRESS["oneOf"][2],
    schema({"album": schema({})}, ["album"]), schema({"sound": schema({})}, ["sound"])]}
GROUP_ADDRESS = schema({"group": schema({"parent": GROUP_PARENT, "id": PORT_ID}, ["parent", "id"])}, ["group"])
PORT_ADDRESS["oneOf"].append(GROUP_ADDRESS)
PORT_ENDPOINT = schema({"node": PORT_ADDRESS, "portID": PORT_ID}, ["node", "portID"])
CONNECTION_ID = schema({"edgeID": PORT_ID, "from": PORT_ADDRESS, "to": PORT_ADDRESS}, ["edgeID", "from", "to"])
OCTANT = {"type": "integer", "minimum": 0, "maximum": 7, "description": "Clockwise: 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW. Position only, not a bus."}
LAYOUT_REVISION = {"expectedLayoutRevision": {"type": "integer", "minimum": 0, "maximum": 9223372036854775806}}
PORT_PAIR = {**LAYOUT_REVISION, "first": PORT_ENDPOINT, "second": PORT_ENDPOINT, "firstOctant": OCTANT, "secondOctant": OCTANT}
PLACED_CONNECTION = schema({"id": CONNECTION_ID, "placement": schema({"from": OCTANT, "to": OCTANT}, ["from", "to"])}, ["id", "placement"])
NOTE = schema({"id": STRING, "beat": {"type": "number", "minimum": 0}, "length": {"type": "number", "exclusiveMinimum": 0}, "pitch": {"type": "integer", "minimum": 0, "maximum": 127}, "velocity": {"type": "integer", "minimum": 1, "maximum": 127}}, ["beat", "length", "pitch", "velocity"])
AUTOMATION_POINT = schema({"id": STRING, "beat": {"type": "number", "minimum": 0, "maximum": 1048576}, "value": {"type": "number", "minimum": -1, "maximum": 20000}, "shape": {"type": "string", "enum": ["linear", "hold"]}}, ["beat", "value"])
OPERATION = schema({
    "kind": {"type": "string", "enum": ["set_global", "rename_project", "set_instrument", "set_track", "add_section", "set_section", "connect_sections", "add_midi", "set_notes", "generate_midi", "set_node", "set_effect", "add_effect", "connect", "reorder_section", "set_clip", "set_step", "edit_notes", "edit_audio", "set_automation"]},
    "patternID": {"type": "string", "description": "Valid for edit_shared_audio, edit_pitch_bend and edit_sustain; explicit shared rhythm pattern ID, affecting every use. Do not combine with arrangementID/compositionID/nodeID/useID/laneID."},
    "original": {"type": "boolean", "description": "set_automation: omitted/false edits this use. edit_pitch_bend/edit_sustain normal targets require an explicit boolean. True edits shared section source while retaining existing use overrides."},
    **SCOPE, "clipID": STRING, "sourceStart": {"type": "number", "minimum": 0}, "duration": {"type": "number", "exclusiveMinimum": 0}, "laneID": STRING, "nodeID": STRING, "trackID": STRING, "name": STRING,
    "stepIndex": {"type": "integer", "minimum": 0, "description": "Zero-based step in the MIDI circle, not within the visible page."},
    "subdivisions": {"type": "integer", "enum": [1, 2, 3, 4, 6, 8], "description": "Steps per quarter note; default 4. Does not quantize existing notes."},
    "pitch": {"type": "integer", "minimum": 0, "maximum": 127},
    "velocity": {"type": "integer", "minimum": 1, "maximum": 127},
    "gate": {"type": "number", "minimum": 0.01, "maximum": 16, "description": "Note length in steps. Omit to preserve an existing note; new notes default to 0.9."},
    "enabled": {"type": "boolean", "description": "Enable a step or bypass/read an existing automation curve, according to kind."},
    "noteIDs": {"type": "array", "items": STRING, "minItems": 1, "maxItems": 100000},
    "edit": {"type": "string", "enum": ["transpose", "move", "duplicate", "quantize", "velocity", "length_delta", "velocity_delta", "delete", "split", "fade"]},
    "parameter": {"type": "string", "enum": ["gain", "pan", "synthCutoff", "synthResonance"], "description": "gain 0–4, pan -1–1, synthCutoff 40–20000 Hz. Cutoff requires a built-in synth instrument node and runtime.capabilities.synthCutoffAutomation=1. synthResonance stores 0–0.9 (display 0–90%), requires synth engine 2/3 and runtime.capabilities.synthResonanceAutomation=1."},
    "automationPoints": {"type": "array", "items": AUTOMATION_POINT, "maxItems": 4096, "description": "Replace this node parameter curve. Empty clears it. Omitted with enabled changes only bypass."},
    "sourceOffset": {"type": "number", "exclusiveMinimum": 0, "description": "Split offset in source seconds from the selected clip start."},
    "fadeIn": {"type": "number", "minimum": 0}, "fadeOut": {"type": "number", "minimum": 0},
    "velocityOffset": {"type": "integer", "minimum": -126, "maximum": 126, "description": "Signed change for edit_notes velocity_delta; preserves velocity differences. Entire edit fails if any note leaves 1–127."},
    "semitones": {"type": "integer", "minimum": -127, "maximum": 127},
    "beatOffset": {"type": "number", "minimum": -131072, "maximum": 131072},
    "strength": {"type": "number", "minimum": 0, "maximum": 1},
    "notes": {"type": "array", "items": NOTE, "maxItems": 100000},
    "pattern": {"type": "string", "enum": ["chords", "arpeggio", "bass", "pulse"]},
    "append": {"type": "boolean"}, "synthVoice": {"type": "integer", "minimum": 0, "maximum": 9, "description": "0 pad, 1 bass, 2 keys, 3 supersaw, 4 pluck, 5 lead, 6 electricPiano, 7 organ, 8 brass, 9 strings"},
    "instrument": {"type": "object", "description": "Complete Instrument object from snapshot; use synthVoice for built-in synth presets."},
    "effect": {"type": "object", "description": "Effect object: kind, amount, secondary, optional plugin. Use inspect to read the existing object."},
    "context": {"type": "object", "description": "Complete MusicContext object from snapshot, with desired fields changed."},
    "settings": {"type": "object", "description": "Complete ContextSettings from inspect, with desired inheritance or local values changed."},
    "gain": {"type": "number", "minimum": 0, "maximum": 4}, "muted": {"type": "boolean"},
    "startBeat": {"type": "number", "minimum": 0}, "lengthBeats": {"type": "number", "exclusiveMinimum": 0},
    "repeatCount": {"type": "integer", "minimum": 1, "maximum": 256}, "from": STRING, "to": STRING,
    "sidechain": {"type": "boolean"}, "bars": {"type": "integer", "minimum": 1, "maximum": 4096},
}, ["kind"])

ARRANGEMENT_OPERATIONS = ["duplicate_arrangement", "rename_arrangement"]
OPERATION["properties"]["compositionID"] = {"type": "string", "description": "Explicit owning composition ID; required for arrangement duplication, rename and selection."}
OPERATION["oneOf"] = [
    {"type": "object", "properties": {"kind": {"enum": [kind for kind in OPERATION["properties"]["kind"]["enum"] if kind != "set_automation"]}}},
    {"type": "object", "properties": {"kind": {"enum": ARRANGEMENT_OPERATIONS}},
     "required": ["compositionID", "arrangementID", "name"]},
    {"type": "object", "properties": {"kind": {"enum": ["select_arrangement"]}},
     "required": ["compositionID", "arrangementID"]},
]
# Encode parameter ranges in the advertised schema as well as IPC validation.
AUTOMATION_RANGES = {"gain": (0, 4), "pan": (-1, 1), "synthCutoff": (40, 20000), "synthResonance": (0, 0.9)}
for parameter, (minimum, maximum) in AUTOMATION_RANGES.items():
    point = {**AUTOMATION_POINT, "properties": {**AUTOMATION_POINT["properties"],
             "value": {"type": "number", "minimum": minimum, "maximum": maximum}}}
    OPERATION["oneOf"].append({"type": "object", "properties": {
        "kind": {"enum": ["set_automation"]}, "parameter": {"enum": [parameter]},
        "automationPoints": {"type": "array", "items": point, "maxItems": 4096}},
        "required": ["parameter"]})
OPERATION["properties"]["at"] = schema({"x": {"type": "number", "exclusiveMinimum": -10000000, "exclusiveMaximum": 10000000}, "y": {"type": "number", "exclusiveMinimum": -10000000, "exclusiveMaximum": 10000000}}, ["x", "y"])
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["insert_section"]}}, "required": ["arrangementID", "useID", "name", "bars", "at"]})
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["edit_shared_audio"]},
    "edit": {"type": "string", "enum": ["split", "duplicate", "fade", "delete"]}},
    "required": ["patternID", "trackID", "clipID", "edit"]})
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["clear_use_tempo_override"]}}, "required": ["arrangementID", "useID"]})
OPERATION["properties"]["kind"]["enum"].append("clear_use_tempo_override")
OPERATION["properties"]["kind"]["enum"].extend(ARRANGEMENT_OPERATIONS + ["select_arrangement", "insert_section", "edit_shared_audio"])
OPERATION["description"] = "clear_use_tempo_override requires arrangementID/useID, removes only that use tempo override, and requires midiTempoImport=1. edit_shared_audio requires patternID, trackID, clipID and edit (split/duplicate/fade/delete). patternID is rejected except on edit_shared_audio/edit_pitch_bend/edit_sustain; arrangementID/compositionID/nodeID/useID/laneID are rejected on edit_shared_audio. original is rejected on kinds other than set_automation/edit_pitch_bend/edit_sustain. It edits the shared rhythm pattern across its uses; split uses sourceOffset seconds, duplicate uses beatOffset, fade uses fadeIn/fadeOut seconds, as in edit_audio. set_automation accepts original: omitted/false edits this use, true edits the shared section source and retains existing use overrides. insert_section requires arrangementID, useID (insert after), name (1–120 trimmed characters), bars (1–4096), and at {x,y}; it atomically inserts a new section into a linear path, preserving editing selection. Branches, loops and non-default transitions fail without changes. duplicate_arrangement and rename_arrangement require explicit compositionID, arrangementID and name (1–120 characters after trimming whitespace). Duplicate shares section sources and assets, preserving every owner's playback choice and the editing canvas. Rename changes only the arrangement name. select_arrangement requires compositionID and arrangementID (no name needed); it deliberately changes the owner's playback choice and visible editing branch."


LENGTH_OPERATIONS = ["set_use_length_override", "clear_use_length_override"]
OPERATION["properties"]["kind"]["enum"].extend(LENGTH_OPERATIONS)
for kind in LENGTH_OPERATIONS:
    required = ["kind", "arrangementID", "useID"] + (["bars"] if kind == "set_use_length_override" else [])
    OPERATION["oneOf"].append(schema({key: ({"enum": [kind]} if key == "kind" else OPERATION["properties"][key]) for key in required}, required))
OPERATION["description"] += " set_use_length_override requires exactly kind/arrangementID/useID/bars (integer 1–4096); clear_use_length_override requires exactly kind/arrangementID/useID and restores the shared source length. Both require sectionLengthEditing=1. Legacy set_section retains its existing shape and final batch validation. Changes preserve source data and editing selection; unsafe truncation fails atomically."


BEND_RANGE = schema({"semitones": {"type": "integer", "minimum": 0, "maximum": 127}, "cents": {"type": "integer", "minimum": 0, "maximum": 127}}, ["semitones", "cents"])
BEND_CHANGE = schema({"kind": {"type": "string", "enum": ["insert", "update", "remove", "setInitial", "clear"]},
    "beat": {"type": "number", "minimum": 0, "maximum": 131072}, "rawValue": {"type": "integer", "minimum": 0, "maximum": 16383},
    "range": BEND_RANGE, "index": {"type": "integer", "minimum": 0, "maximum": 99999}, "channel": {"type": "integer", "minimum": 0, "maximum": 15}}, ["kind"])
OPERATION["properties"]["change"] = BEND_CHANGE
OPERATION["properties"]["kind"]["enum"].append("edit_pitch_bend")
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["edit_pitch_bend"]}}, "required": ["change"]})
OPERATION["description"] += " edit_pitch_bend requires midiPitchBendEditing=1 and change. Normal target: arrangementID/useID/laneID/original boolean (explicit); shared target: patternID/trackID only. change: insert uses beat and exactly one rawValue or range; update adds index; remove uses index; setInitial uses channel/rawValue/range; clear has only kind. Indices address current revision; inspect lanes and snapshot patterns expose the stored pitchBend sequence."


SUSTAIN_CHANGE = schema({"kind": {"type": "string", "enum": ["insert", "update", "remove", "setInitial", "clear"]},
    "beat": {"type": "number", "minimum": 0, "maximum": 131072}, "rawValue": {"type": "integer", "minimum": 0, "maximum": 127},
    "index": {"type": "integer", "minimum": 0, "maximum": 99999}, "channel": {"type": "integer", "minimum": 0, "maximum": 15}}, ["kind"])
OPERATION["properties"]["sustainChange"] = SUSTAIN_CHANGE
OPERATION["properties"]["kind"]["enum"].append("edit_sustain")
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["edit_sustain"]}}, "required": ["sustainChange"]})
OPERATION["description"] += " edit_sustain requires fresh midiSustainEditing=1 and sustainChange. Exactly one target: arrangementID/useID/laneID/original boolean (explicit), or shared patternID/trackID. sustainChange: insert uses beat/rawValue; update uses index/beat/rawValue; remove uses index; setInitial uses channel/rawValue; clear has only kind. Raw CC64 values are 0–127, down at 64; indices address the current revision. Inspect lanes and snapshot patterns expose sustain. Clear removes sustain only; pitch bend and notes remain. Shared edits affect every use; normal original=true retains use overrides. All operations in a batch validate before any mutation."


def tool(name, method, description, properties=None, required=(), write=False):
    properties = properties or {}
    if write:
        properties = {**REVISION, **properties}
        required = ("projectID", "expectedRevision", *required)
    return {"name": "circlr_" + name, "method": method, "description": description,
            "inputSchema": schema(properties, required),
            "annotations": {"readOnlyHint": method in {"snapshot", "inspect", "ports", "sounds", "events", "job"}, "destructiveHint": write, "openWorldHint": False}}


TOOLS = [
    tool("snapshot", "snapshot", "Read current project IDs, revision, tracks, arrangements, selection and active job. Read before every edit."),
    tool("sounds", "sounds", "Search the actual built-in synth, Sound Bank and installed AU catalog without changing music, focus or playback. Requires snapshot.runtime.capabilities.soundCatalog=1. Read stable IDs and exact raw program/bankLSB/drums or plugin descriptors; names are data. Reuse catalogID and filters with nextOffset for pagination. Merge returned bank fields into the latest snapshot instrument before set_instrument to preserve inactive patches. Does not audition or certify audio compatibility.", {
        "soundTarget": {"type": "string", "enum": ["instrument", "effect"], "description": "Default instrument; effect lists AU effects."},
        "query": {"type": "string", "maxLength": 256, "description": "Name, Korean family, manufacturer or exact display #1–#128. Default empty."},
        "category": {"type": "string", "enum": ["synth", "soundBank", "instrument", "effect"]},
        "bankDrums": {"type": "boolean", "description": "Only for instrument target with absent/soundBank category."},
        "offset": {"type": "integer", "minimum": 0, "maximum": 1000000},
        "limit": {"type": "integer", "minimum": 1, "maximum": 128, "description": "Default 64."},
        "catalogID": {"type": "string", "minLength": 64, "maxLength": 64, "description": "ID returned by the first page; changed catalogs fail with stale_catalog."},
    }),
    tool("inspect", "inspect", "Read the effective notes, clips and node graph of one section use.", SCOPE, ("useID",)),
    tool("ports", "ports", "Read actual IN/OUT descriptors, connections, placements, revision and layoutRevision. Group ports include bindingTarget and all saved bindings; unresolved targets are excluded from active ports. Reuse returned logical connection IDs.", {"node": PORT_ADDRESS}, ("node",)),
    tool("set_group_port", "set_group_port", "Explicitly expose one real member endpoint on a layout group. Requires node (group address), target and name. Optional existing portID renames the same immutable target. No audio changes; one layout Undo. Duplicate target returns its existing portID.", {**LAYOUT_REVISION, "node": GROUP_ADDRESS, "target": PORT_ENDPOINT, "name": {"type": "string", "minLength": 1, "maxLength": 128}, "portID": PORT_ID}, ("expectedLayoutRevision", "node", "target", "name"), True),
    tool("remove_group_port", "remove_group_port", "Remove an exposed alias from a group while preserving its internal endpoint and every existing music cable. One layout Undo. Does not automatically route to a replacement port.", {**LAYOUT_REVISION, "node": GROUP_ADDRESS, "portID": PORT_ID}, ("expectedLayoutRevision", "node", "portID"), True),
    tool("connect_ports", "connect_ports", "Connect explicit compatible endpoints, starting at either IN or OUT. Octants belong to first/second endpoints. One Undo; duplicates are a no-op and do not move existing cables. Requires fresh music and layout revisions.", PORT_PAIR, tuple(PORT_PAIR), True),
    tool("reconnect_ports", "reconnect_ports", "Replace one existing cable using its complete logical connectionID and two explicit endpoints. Preserves edge ID and gain; rejects cross-graph moves, cycles and duplicates atomically. Composition sequence cables cannot be reconnected.", {**PORT_PAIR, "connectionID": CONNECTION_ID}, (*PORT_PAIR, "connectionID"), True),
    tool("disconnect_ports", "disconnect_ports", "Disconnect the exact logical cable. One Undo; other section uses stay unchanged. Composition sequence cables cannot be disconnected.", {**LAYOUT_REVISION, "connectionID": CONNECTION_ID}, ("expectedLayoutRevision", "connectionID"), True),
    tool("move_ports", "move_ports", "Atomically place 1–128 distinct existing cables in eight directions. One layout Undo; changes layoutRevision only, preserving music and audio. Unchanged placements are a no-op.", {**LAYOUT_REVISION, "moves": {"type": "array", "items": PLACED_CONNECTION, "minItems": 1, "maxItems": 128}}, ("expectedLayoutRevision", "moves"), True),
    tool("apply", "apply", "Atomically apply 1–128 edits as one Undo action. set_automation uses gain 0–4, pan -1–1, or synthCutoff 40–20000 Hz on built-in synth instrument nodes only. Cutoff batches require a fresh matching snapshot with runtime.capabilities.synthCutoffAutomation=1; unsupported apps receive no mutation. synthResonance uses 0–0.9 normalized values (display 0–90%) on built-in synth engine 2/3 instrument nodes only, and requires synthResonanceAutomation=1 from the same fresh snapshot, including clear and bypass edits. Final target and revision validation remain app-side. edit_shared_audio requires patternID, trackID, clipID and edit (split/duplicate/fade/delete), affecting all uses of the shared rhythm pattern; offsets and fades match edit_audio. set_automation original defaults to false (this use); true edits shared section source while retaining use overrides. set_notes/generate_midi replace notes unless append=true. duplicate_arrangement/rename_arrangement require explicit compositionID, arrangementID and a name of 1–120 characters after trimming; duplicate shares section sources/assets while preserving playback choices and the editing canvas. select_arrangement requires compositionID and arrangementID and deliberately changes playback choice and the visible editing branch. Stable IDs are required; stale revisions fail without changes.", {"operations": {"type": "array", "items": OPERATION, "minItems": 1, "maxItems": 128}}, ("operations",), True),
    tool("import_midi", "import_midi", "Read a local regular SMF format 0/1 file (maximum 16 MiB) in a background job. Requires midiTempoImport=1, midiPitchBendImport=1 and midiSustainImport=1 capabilities and matching project/revision. previewOnly=true returns track IDs, per-track pitchBend eventCount, initialValue/initialRange, rangeChangeCount (all range events), uniqueRangeCount (including initial range), first-seen ranges (at most 16) and hasMoreRanges, optional per-track sustain {eventCount, initialValue, initialIsDown, finalValue, finalIsDown, lastEventBeat}, selectedIssues, actual expressionPolicy, tempo metadata and optional previewIssue without changing the document. expressionPolicy defaults to preserve: supported MIDI pitch bend/RPN sensitivity and sustain CC64 raw values (0–127, pedal down at 64) are retained; CC121=0 resets sustain to off. Selected unsupported expression fails apply. Only explicit omit imports notes without either pitch bend or sustain; issues remain visible. Pitch bend and active sustain audio rendering support built-in synths (sustain engine 1/2/3); unsupported instrument backends reject active pedal expression rather than drop it. Omitted trackIDs imports all note tracks; explicit IDs are index:channel from preview. keepCurrent (default) retains current tempo; applyFile applies the file tempo to this use only and fails on tempoImportIssue. atBeat defaults to 0, extendSection defaults to false. One Undo; preserves editing selection. Read job until terminal. No playback/audition is started.", {
        **SCOPE, "path": STRING,
        "trackIDs": {"type": "array", "items": {"type": "string", "minLength": 1, "maxLength": 32}, "minItems": 1, "maxItems": 256},
        "atBeat": {"type": "number", "minimum": 0, "maximum": 131072},
        "extendSection": {"type": "boolean"}, "previewOnly": {"type": "boolean"},
        "tempoPolicy": {"type": "string", "enum": ["keepCurrent", "applyFile"]},
        "expressionPolicy": {"type": "string", "enum": ["preserve", "omit"]}
    }, ("path", "arrangementID", "useID"), True),
    tool("bounce", "bounce", "Start an asynchronous section track bounce including its internal effects and sidechain. Originals remain restorable; audio replaces output inputs. Read job until terminal state.", {**SCOPE, "trackID": STRING, "tailSeconds": TAIL_SECONDS}, ("useID", "trackID"), True),
    tool("restore_bounce", "restore_bounce", "Restore a bounced circle's original inputs; keep rendered audio as a disconnected archive.", {**SCOPE, "nodeID": STRING}, ("useID", "nodeID"), True),
    tool("export", "export", "Start asynchronous master WAV export, 48 kHz stereo 24-bit. Requires a NEW absolute .wav path. No file overwrite. Read job for completion and resolved tail/end-window measurements.", {"path": STRING, "tailSeconds": TAIL_SECONDS}, ("path",), True),
    tool("save", "save", "Save the current project, embedding assets. Optional absolute .circlr path. Cannot overwrite a different project.", {"path": STRING}, (), True),
    tool("open", "open", "Start asynchronous local .circlr open. Read job to completion, then snapshot for the new project. Rejects unsaved edits. macOS may require the user to allow first file access.", {"path": STRING}, ("path",), True),
    tool("undo", "undo", "Undo one whole edit. Requires current project ID and revision. Also supply expectedLayoutRevision from ports/snapshot to protect against concurrent layout edits.", LAYOUT_REVISION, write=True),
    tool("job", "job", "Read one job's running/completed/failed/cancelled state and output path or bounced node ID.", {"jobID": STRING}, ("jobID",)),
    tool("events", "events", "Read actual app/agent activity after a sequence cursor. Last 500 events retained. No polling faster than once per second.", {"afterSequence": {"type": "integer", "minimum": 0}}),
    tool("play", "play", "Prepare and play the album through the Mac audio output."),
    tool("stop", "stop", "Immediately stop playback and cancel the active render job."),
    tool("record", "record", "Start audio recording at the currently selected section/track. Use only when the user requests microphone recording. May require macOS permission. First two input channels (one for mono). Read snapshot.recording until started or failed; circlr_stop cancels or stops and finalizes asynchronously. Do not retry while recording.busy is true.", write=True),
    tool("playback_loop", "playback_loop", "Choose off/song/section. Requires playbackLoop=1, playbackLoopLive=1 and fresh revision. Stopped or one-shot playback: configure next Play only (no restart); section captures selection at Play. While a loop is playing: capture the current active arrangement and selected use now, render in background without stopping current audio, then schedule replacement at a hardware-acknowledged future boundary. off finishes the current cycle and exit tail before stopping. accepted_pending is acceptance, not completed application: poll snapshot.view.loopTransition until busy=false and verify loopMode. Repeated requests while rendering/scheduled are rejected; Stop cancels. Revision changes during rendering cancel the request; after scheduling they stop output safely. song means active arrangement, not whole album. Linear export PCM is unchanged.", {"loopMode": {"type": "string", "enum": ["off", "song", "section"]}}, ("loopMode",), True),
    tool("workspace_view", "workspace_view", "Set text-free viewing mode and playback follow without changing musical data. Requires workspaceView=1 and fresh project/revision. follow controls following/off; followSettings selects song/section/pinned, fit/keepZoom, off/subtle/emphasized transition. Pinned requires an explicit stable circle address, never the current selection. Validate and resolve drafts before entering viewing mode; invalid or composing input blocks entry. Follow settings persist in the project workspace. Read snapshot.view for actual settings/state. Native visibility is not certified by this tool.", {
        "viewingMode": {"type": "boolean"}, "follow": {"type": "boolean"},
        "followSettings": schema({"target": {"type": "string", "enum": ["song", "section", "pinned"]},
            "framing": {"type": "string", "enum": ["fit", "keepZoom"]},
            "transition": {"type": "string", "enum": ["off", "subtle", "emphasized"]},
            "pinned": {"oneOf": [*PORT_ADDRESS["oneOf"], schema({"album": schema({})}, ["album"]), schema({"sound": schema({})}, ["sound"])]}}, ["target", "framing", "transition"])}, write=True),
    tool("focus", "focus", "Optionally show a circle, including a group via node address (exclusive of other selectors). Omit targets for the album. With minimized=true/false, only minimize/restore the app window. With follow=true/false alone, resume/disable playback camera follow. Editing and rendering never require focus.", {**SCOPE, "node": PORT_ADDRESS, "compositionID": STRING, "nodeID": STRING, "detail": {"type": "boolean"}, "minimized": {"type": "boolean"}, "follow": {"type": "boolean"}}),
]
BY_NAME = {entry["name"]: entry for entry in TOOLS}
READ_METHODS = frozenset({"snapshot", "inspect", "ports", "sounds", "events", "job"})


def validate(value, spec, path="arguments"):
    if "oneOf" in spec:
        matches = 0
        for variant in spec["oneOf"]:
            try:
                validate(value, variant, path)
                matches += 1
            except ValueError:
                pass
        if matches != 1:
            raise ValueError(f"{path}: expected exactly one supported address shape")
    kind = spec.get("type")
    valid = {"object": isinstance(value, dict), "array": isinstance(value, list), "string": isinstance(value, str),
             "integer": isinstance(value, int) and not isinstance(value, bool), "number": isinstance(value, (int, float)) and not isinstance(value, bool),
             "boolean": isinstance(value, bool)}
    if kind and not valid.get(kind, True):
        raise ValueError(f"{path}: expected {kind}")
    if "enum" in spec and value not in spec["enum"]:
        raise ValueError(f"{path}: invalid value")
    if kind == "object":
        for key in spec.get("required", []):
            if key not in value:
                raise ValueError(f"{path}.{key}: required")
        if spec.get("additionalProperties") is False and set(value) - set(spec.get("properties", {})):
            raise ValueError(f"{path}: unknown fields")
        for key, item in value.items():
            if key in spec.get("properties", {}):
                validate(item, spec["properties"][key], path + "." + key)
    elif kind == "array":
        if not spec.get("minItems", 0) <= len(value) <= spec.get("maxItems", MAX_MESSAGE):
            raise ValueError(f"{path}: item count out of range")
        for item in value:
            validate(item, spec.get("items", {}), path + "[]")
    elif kind == "string":
        if not spec.get("minLength", 0) <= len(value) <= spec.get("maxLength", MAX_MESSAGE):
            raise ValueError(f"{path}: string length out of range")
    elif kind in {"number", "integer"}:
        if (isinstance(value, float) and not math.isfinite(value)) or value < spec.get("minimum", float("-inf")) or value > spec.get("maximum", float("inf")) or value <= spec.get("exclusiveMinimum", float("-inf")) or value >= spec.get("exclusiveMaximum", float("inf")):
            raise ValueError(f"{path}: number out of range")


def rpc(path, request):
    packet = json.dumps(request, ensure_ascii=False, allow_nan=False, separators=(",", ":"), sort_keys=True).encode() + b"\n"
    if len(packet) > MAX_MESSAGE:
        raise ValueError("Request exceeds 8 MiB")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(15)
        client.connect(path)
        client.sendall(packet)
        data = bytearray()
        while len(data) <= MAX_MESSAGE:
            chunk = client.recv(65536)
            if not chunk:
                raise ConnectionError("Reply interrupted; inspect state before retrying a write with a NEW request ID.")
            data.extend(chunk)
            if len(data) > MAX_MESSAGE:
                raise ValueError("Reply exceeds 8 MiB")
            if b"\n" in chunk:
                return json.loads(bytes(data).split(b"\n", 1)[0])
    raise ValueError("Reply exceeds 8 MiB")


def validate_operation_scopes(operations):
    for index, operation in enumerate(operations):
        kind = operation["kind"]
        if kind in LENGTH_OPERATIONS:
            expected = {"kind", "arrangementID", "useID"} | ({"bars"} if kind == "set_use_length_override" else set())
            if set(operation) != expected:
                raise ValueError("section length operation has missing or inapplicable fields")
        if operation.get("parameter") in {"synthCutoff", "synthResonance"} and kind != "set_automation":
            raise ValueError(f"operations[{index}].parameter: synth automation requires set_automation")
        if "original" in operation and kind not in {"set_automation", "edit_pitch_bend", "edit_sustain"}:
            raise ValueError(f"operations[{index}].original: supported only by set_automation/edit_pitch_bend/edit_sustain")
        if "patternID" in operation and kind not in {"edit_shared_audio", "edit_pitch_bend", "edit_sustain"}:
            raise ValueError(f"operations[{index}].patternID: supported only by edit_shared_audio/edit_pitch_bend/edit_sustain")
        if "change" in operation and kind != "edit_pitch_bend":
            raise ValueError("change requires edit_pitch_bend")
        if "sustainChange" in operation and kind != "edit_sustain":
            raise ValueError("sustainChange requires edit_sustain")
        if kind == "edit_sustain":
            change = operation["sustainChange"]
            fields = {"insert": {"kind", "beat", "rawValue"}, "update": {"kind", "beat", "rawValue", "index"},
                      "remove": {"kind", "index"}, "setInitial": {"kind", "channel", "rawValue"}, "clear": {"kind"}}[change["kind"]]
            if set(change) != fields:
                raise ValueError("sustainChange has missing or inapplicable fields")
            address = {"patternID", "trackID"} if "patternID" in operation else {"arrangementID", "useID", "laneID", "original"}
            if set(operation) != address | {"kind", "sustainChange"}:
                raise ValueError("edit_sustain requires exactly one explicit normal or shared target")
        if kind == "edit_pitch_bend":
            change = operation["change"]
            ck = change["kind"]
            fields = {"insert": {"kind", "beat"}, "update": {"kind", "beat", "index"}, "remove": {"kind", "index"}, "setInitial": {"kind", "channel", "rawValue", "range"}, "clear": {"kind"}}[ck]
            if ck in {"insert", "update"}:
                if ("rawValue" in change) == ("range" in change):
                    raise ValueError("change requires exactly one rawValue or range")
                fields = fields | ({"rawValue"} if "rawValue" in change else {"range"})
            if set(change) != fields:
                raise ValueError("change has missing or inapplicable fields")
            address = {"arrangementID", "useID", "laneID", "original", "patternID", "trackID", "nodeID", "compositionID", "clipID"}.intersection(operation)
            expected = {"patternID", "trackID"} if "patternID" in operation else {"arrangementID", "useID", "laneID", "original"}
            if address != expected:
                raise ValueError("edit_pitch_bend requires one explicit normal or shared target")
        if kind == "edit_shared_audio":
            ambiguous = {"arrangementID", "compositionID", "nodeID", "useID", "laneID"}.intersection(operation)
            if ambiguous:
                raise ValueError(f"operations[{index}]: shared audio cannot include {', '.join(sorted(ambiguous))}")


def call_tool(path, name, arguments, read_only=False):
    entry = BY_NAME.get(name)
    if entry is None:
        raise ValueError("Unknown tool")
    if read_only and entry["method"] not in READ_METHODS:
        raise ValueError("This circlr session is read-only; submit an edit proposal to the coordinator.")
    validate(arguments, entry["inputSchema"])
    if entry["method"] == "apply":
        validate_operation_scopes(arguments["operations"])
    if entry["method"] == "workspace_view":
        if not {"viewingMode", "follow", "followSettings"}.intersection(arguments):
            raise ValueError("workspace_view requires a view setting")
        settings = arguments.get("followSettings", {})
        if settings.get("target") == "pinned" and "pinned" not in settings:
            raise ValueError("pinned follow requires an explicit circle address")
    if entry["method"] == "import_midi":
        if not arguments["path"].startswith("/") or "\0" in arguments["path"]:
            raise ValueError("import_midi.path: absolute local path required")
        ids = arguments.get("trackIDs")
        if ids is not None and len(set(ids)) != len(ids):
            raise ValueError("import_midi.trackIDs: duplicate IDs")
    request = {"id": str(uuid.uuid4()), "method": entry["method"], "arguments": {k: v for k, v in arguments.items() if k not in REVISION}}
    for key in REVISION:
        if key in arguments:
            request[key] = arguments[key]
    try:
        required_capabilities = []
        if entry["method"] == "workspace_view":
            required_capabilities.append("workspaceView")
        if entry["method"] == "playback_loop":
            required_capabilities.extend(["playbackLoop", "playbackLoopLive"])
        if entry["method"] == "apply" and any(op.get("parameter") == "synthCutoff" for op in arguments["operations"]):
            required_capabilities.append("synthCutoffAutomation")
        if entry["method"] == "apply" and any(op.get("parameter") == "synthResonance" for op in arguments["operations"]):
            required_capabilities.append("synthResonanceAutomation")
        if entry["method"] == "import_midi" or (entry["method"] == "apply" and any(op["kind"] == "clear_use_tempo_override" for op in arguments["operations"])):
            required_capabilities.append("midiTempoImport")
        if entry["method"] == "import_midi":
            required_capabilities.append("midiPitchBendImport")
            required_capabilities.append("midiSustainImport")
        if entry["method"] == "apply" and any(op["kind"] == "edit_pitch_bend" for op in arguments["operations"]):
            required_capabilities.append("midiPitchBendEditing")
        if entry["method"] == "apply" and any(op["kind"] == "edit_sustain" for op in arguments["operations"]):
            required_capabilities.append("midiSustainEditing")
        if entry["method"] == "apply" and any(op["kind"] in LENGTH_OPERATIONS for op in arguments["operations"]):
            required_capabilities.append("sectionLengthEditing")
        if required_capabilities:
            # This read does not weaken the final app-side revision/atomicity guard.
            probe = rpc(path, {"id": str(uuid.uuid4()), "method": "snapshot", "arguments": {}})
            state = probe.get("result") if isinstance(probe, dict) and probe.get("ok") is True else None
            if not isinstance(state, dict):
                raise ValueError("Cannot verify app capabilities; read snapshot again")
            runtime = state.get("runtime", {})
            capabilities = runtime.get("capabilities", {}) if isinstance(runtime, dict) else {}
            for required in required_capabilities:
                capability = capabilities.get(required) if isinstance(capabilities, dict) else None
                if type(capability) is not int or capability != 1:
                    raise ValueError(f"This app does not support {required}=1; update the app before editing")
            if state.get("projectID") != request["projectID"] or type(state.get("revision")) is not int or state.get("revision") != request["expectedRevision"]:
                raise ValueError("stale_revision: snapshot differs from projectID/expectedRevision")
        result = rpc(path, request)
    except (OSError, ValueError) as error:
        result = {"ok": False, "requestID": request["id"], "error": str(error), "socket": path}
    return {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, allow_nan=False)}], "structuredContent": result, "isError": not result.get("ok", False)}


def serve(path, read_only=False):
    initialized = False
    negotiated = False
    while True:
        line = sys.stdin.buffer.readline(MAX_MESSAGE + 1)
        if not line:
            return
        response_id = None
        try:
            if len(line) > MAX_MESSAGE:
                raise ValueError("MCP message exceeds 8 MiB")
            request = json.loads(line)
            if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
                raise ValueError("Expected JSON-RPC 2.0 object")
            response_id = request.get("id")
            method = request.get("method")
            if "id" not in request:
                if method == "notifications/initialized" and negotiated:
                    initialized = True
                continue
            if method == "initialize":
                negotiated = True
                requested = request.get("params", {}).get("protocolVersion")
                result = {"protocolVersion": requested if requested in VERSIONS else "2025-11-25", "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "circlr", "version": "0.40.0"}, "instructions": ("Read-only specialist session. Return edit proposals to the coordinator. " if read_only else "") + "Read snapshot before mutations. Use stable IDs and expectedRevision. Long jobs return immediately; monitor with circlr_job/events. CUA is unnecessary."}
            elif method == "ping":
                result = {}
            elif not initialized:
                raise ValueError("Initialize the MCP session first")
            elif method == "tools/list":
                result = {"tools": [{k: v for k, v in entry.items() if k != "method"} for entry in TOOLS if not read_only or entry["method"] in READ_METHODS]}
            elif method == "tools/call":
                params = request.get("params", {})
                try:
                    result = call_tool(path, params.get("name"), params.get("arguments", {}), read_only=read_only)
                except ValueError as error:
                    result = {"content": [{"type": "text", "text": str(error)}], "isError": True}
            else:
                print(json.dumps({"jsonrpc": "2.0", "id": response_id, "error": {"code": -32601, "message": "Method not found"}}), flush=True)
                continue
            response = {"jsonrpc": "2.0", "id": response_id, "result": result}
        except (ValueError, TypeError, AttributeError) as error:
            response = {"jsonrpc": "2.0", "id": response_id, "error": {"code": -32600, "message": str(error)}}
        print(json.dumps(response, ensure_ascii=False, allow_nan=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", default=os.environ.get("CIRCLR_SOCKET", str(Path.home() / "Library/Application Support/circlr/Agent/agent.sock")))
    parser.add_argument("--request", help="Send one native JSON request file and exit; omit to run MCP stdio.")
    parser.add_argument("--read-only", action="store_true", help="Expose and accept only snapshot, inspect, ports, sounds, job and events.")
    args = parser.parse_args()
    if args.request:
        request = json.loads(Path(args.request).read_text())
        if args.read_only and request.get("method") not in READ_METHODS:
            parser.error("This circlr session is read-only")
        result = rpc(args.socket, request)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        serve(args.socket, read_only=args.read_only)


if __name__ == "__main__":
    main()
