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
REVISION = {"projectID": STRING, "expectedRevision": {"type": "integer", "minimum": 0, "maximum": 9223372036854775807}}
SCOPE = {"arrangementID": STRING, "useID": STRING}
NOTE = schema({"id": STRING, "beat": {"type": "number", "minimum": 0}, "length": {"type": "number", "exclusiveMinimum": 0}, "pitch": {"type": "integer", "minimum": 0, "maximum": 127}, "velocity": {"type": "integer", "minimum": 1, "maximum": 127}}, ["beat", "length", "pitch", "velocity"])
OPERATION = schema({
    "kind": {"type": "string", "enum": ["set_global", "rename_project", "set_instrument", "set_track", "add_section", "set_section", "connect_sections", "add_midi", "set_notes", "generate_midi", "set_node", "set_effect", "add_effect", "connect", "reorder_section", "set_clip", "set_step"]},
    **SCOPE, "clipID": STRING, "sourceStart": {"type": "number", "minimum": 0}, "duration": {"type": "number", "exclusiveMinimum": 0}, "laneID": STRING, "nodeID": STRING, "trackID": STRING, "name": STRING,
    "stepIndex": {"type": "integer", "minimum": 0, "description": "Zero-based step in the MIDI circle, not within the visible page."},
    "subdivisions": {"type": "integer", "enum": [1, 2, 3, 4, 6, 8], "description": "Steps per quarter note; default 4. Does not quantize existing notes."},
    "pitch": {"type": "integer", "minimum": 0, "maximum": 127},
    "velocity": {"type": "integer", "minimum": 1, "maximum": 127},
    "gate": {"type": "number", "minimum": 0.01, "maximum": 16, "description": "Note length in steps. Omit to preserve an existing note; new notes default to 0.9."},
    "enabled": {"type": "boolean", "description": "Set step on/off; repeated enabled=true never duplicates existing onsets."},
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


def tool(name, method, description, properties=None, required=(), write=False):
    properties = properties or {}
    if write:
        properties = {**REVISION, **properties}
        required = ("projectID", "expectedRevision", *required)
    return {"name": "circlr_" + name, "method": method, "description": description,
            "inputSchema": schema(properties, required),
            "annotations": {"readOnlyHint": method in {"snapshot", "inspect", "events", "job"}, "destructiveHint": write, "openWorldHint": False}}


TOOLS = [
    tool("snapshot", "snapshot", "Read current project IDs, revision, tracks, arrangements, selection and active job. Read before every edit."),
    tool("inspect", "inspect", "Read the effective notes, clips and node graph of one section use.", SCOPE, ("useID",)),
    tool("apply", "apply", "Atomically apply 1–128 edits as one Undo action. set_notes/generate_midi replace notes unless append=true. Stable IDs are required; stale revisions fail without changes.", {"operations": {"type": "array", "items": OPERATION, "minItems": 1, "maxItems": 128}}, ("operations",), True),
    tool("bounce", "bounce", "Start an asynchronous section track bounce including its internal effects and sidechain. Originals remain restorable; audio replaces output inputs. Read job until terminal state.", {**SCOPE, "trackID": STRING}, ("useID", "trackID"), True),
    tool("restore_bounce", "restore_bounce", "Restore a bounced circle's original inputs; keep rendered audio as a disconnected archive.", {**SCOPE, "nodeID": STRING}, ("useID", "nodeID"), True),
    tool("export", "export", "Start asynchronous master WAV export, 48 kHz stereo 24-bit. Requires a NEW absolute .wav path. No file overwrite. Read job for completion.", {"path": STRING}, ("path",), True),
    tool("save", "save", "Save the current project, embedding assets. Optional absolute .circlr path. Cannot overwrite a different project.", {"path": STRING}, (), True),
    tool("open", "open", "Start asynchronous local .circlr open. Read job to completion, then snapshot for the new project. Rejects unsaved edits. macOS may require the user to allow first file access.", {"path": STRING}, ("path",), True),
    tool("undo", "undo", "Undo one whole edit. Requires current project ID and revision.", write=True),
    tool("job", "job", "Read one job's running/completed/failed/cancelled state and output path or bounced node ID.", {"jobID": STRING}, ("jobID",)),
    tool("events", "events", "Read actual app/agent activity after a sequence cursor. Last 500 events retained. No polling faster than once per second.", {"afterSequence": {"type": "integer", "minimum": 0}}),
    tool("play", "play", "Prepare and play the album through the Mac audio output."),
    tool("stop", "stop", "Immediately stop playback and cancel the active render job."),
    tool("focus", "focus", "Optionally show a circle; omit useID for the album. With minimized=true/false, only minimize/restore the app window. With follow=true/false alone, resume/disable playback camera follow. Editing and rendering never require focus.", {**SCOPE, "compositionID": STRING, "nodeID": STRING, "detail": {"type": "boolean"}, "minimized": {"type": "boolean"}, "follow": {"type": "boolean"}}),
]
BY_NAME = {entry["name"]: entry for entry in TOOLS}
READ_METHODS = frozenset({"snapshot", "inspect", "events", "job"})


def validate(value, spec, path="arguments"):
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
    elif kind in {"number", "integer"}:
        if (isinstance(value, float) and not math.isfinite(value)) or value < spec.get("minimum", float("-inf")) or value > spec.get("maximum", float("inf")) or value <= spec.get("exclusiveMinimum", float("-inf")):
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
                result = {"protocolVersion": requested if requested in VERSIONS else "2025-11-25", "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "circlr", "version": "0.16.0"}, "instructions": ("Read-only specialist session. Return edit proposals to the coordinator. " if read_only else "") + "Read snapshot before mutations. Use stable IDs and expectedRevision. Long jobs return immediately; monitor with circlr_job/events. CUA is unnecessary."}
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
    parser.add_argument("--read-only", action="store_true", help="Expose and accept only snapshot, inspect, job and events.")
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
