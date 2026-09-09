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
AUTOMATION_POINT = schema({"id": STRING, "beat": {"type": "number", "minimum": 0, "maximum": 1048576}, "value": {"type": "number", "minimum": -1, "maximum": 4}, "shape": {"type": "string", "enum": ["linear", "hold"]}}, ["beat", "value"])
OPERATION = schema({
    "kind": {"type": "string", "enum": ["set_global", "rename_project", "set_instrument", "set_track", "add_section", "set_section", "connect_sections", "add_midi", "set_notes", "generate_midi", "set_node", "set_effect", "add_effect", "connect", "reorder_section", "set_clip", "set_step", "edit_notes", "edit_audio", "set_automation"]},
    **SCOPE, "clipID": STRING, "sourceStart": {"type": "number", "minimum": 0}, "duration": {"type": "number", "exclusiveMinimum": 0}, "laneID": STRING, "nodeID": STRING, "trackID": STRING, "name": STRING,
    "stepIndex": {"type": "integer", "minimum": 0, "description": "Zero-based step in the MIDI circle, not within the visible page."},
    "subdivisions": {"type": "integer", "enum": [1, 2, 3, 4, 6, 8], "description": "Steps per quarter note; default 4. Does not quantize existing notes."},
    "pitch": {"type": "integer", "minimum": 0, "maximum": 127},
    "velocity": {"type": "integer", "minimum": 1, "maximum": 127},
    "gate": {"type": "number", "minimum": 0.01, "maximum": 16, "description": "Note length in steps. Omit to preserve an existing note; new notes default to 0.9."},
    "enabled": {"type": "boolean", "description": "Enable a step or bypass/read an existing automation curve, according to kind."},
    "noteIDs": {"type": "array", "items": STRING, "minItems": 1, "maxItems": 100000},
    "edit": {"type": "string", "enum": ["transpose", "move", "duplicate", "quantize", "velocity", "length_delta", "velocity_delta", "delete", "split", "fade"]},
    "parameter": {"type": "string", "enum": ["gain", "pan"]},
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
    {"type": "object", "properties": {"kind": {"enum": list(OPERATION["properties"]["kind"]["enum"])}}},
    {"type": "object", "properties": {"kind": {"enum": ARRANGEMENT_OPERATIONS}},
     "required": ["compositionID", "arrangementID", "name"]},
    {"type": "object", "properties": {"kind": {"enum": ["select_arrangement"]}},
     "required": ["compositionID", "arrangementID"]},
]
OPERATION["properties"]["at"] = schema({"x": {"type": "number", "exclusiveMinimum": -10000000, "exclusiveMaximum": 10000000}, "y": {"type": "number", "exclusiveMinimum": -10000000, "exclusiveMaximum": 10000000}}, ["x", "y"])
OPERATION["oneOf"].append({"type": "object", "properties": {"kind": {"enum": ["insert_section"]}}, "required": ["arrangementID", "useID", "name", "bars", "at"]})
OPERATION["properties"]["kind"]["enum"].extend(ARRANGEMENT_OPERATIONS + ["select_arrangement", "insert_section"])
OPERATION["description"] = "insert_section requires arrangementID, useID (insert after), name (1–120 trimmed characters), bars (1–4096), and at {x,y}; it atomically inserts a new section into a linear path, preserving editing selection. Branches, loops and non-default transitions fail without changes. duplicate_arrangement and rename_arrangement require explicit compositionID, arrangementID and name (1–120 characters after trimming whitespace). Duplicate shares section sources and assets, preserving every owner's playback choice and the editing canvas. Rename changes only the arrangement name. select_arrangement requires compositionID and arrangementID (no name needed); it deliberately changes the owner's playback choice and visible editing branch."


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
    tool("apply", "apply", "Atomically apply 1–128 edits as one Undo action. set_notes/generate_midi replace notes unless append=true. duplicate_arrangement/rename_arrangement require explicit compositionID, arrangementID and a name of 1–120 characters after trimming; duplicate shares section sources/assets while preserving playback choices and the editing canvas. select_arrangement requires compositionID and arrangementID and deliberately changes playback choice and the visible editing branch. Stable IDs are required; stale revisions fail without changes.", {"operations": {"type": "array", "items": OPERATION, "minItems": 1, "maxItems": 128}}, ("operations",), True),
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


def call_tool(path, name, arguments, read_only=False):
    entry = BY_NAME.get(name)
    if entry is None:
        raise ValueError("Unknown tool")
    if read_only and entry["method"] not in READ_METHODS:
        raise ValueError("This circlr session is read-only; submit an edit proposal to the coordinator.")
    validate(arguments, entry["inputSchema"])
    request = {"id": str(uuid.uuid4()), "method": entry["method"], "arguments": {k: v for k, v in arguments.items() if k not in REVISION}}
    for key in REVISION:
        if key in arguments:
            request[key] = arguments[key]
    try:
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
                result = {"protocolVersion": requested if requested in VERSIONS else "2025-11-25", "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "circlr", "version": "0.20.0"}, "instructions": ("Read-only specialist session. Return edit proposals to the coordinator. " if read_only else "") + "Read snapshot before mutations. Use stable IDs and expectedRevision. Long jobs return immediately; monitor with circlr_job/events. CUA is unnecessary."}
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
