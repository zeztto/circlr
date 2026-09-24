#!/usr/bin/env python3
"""Run a bounded DAW journey against an ALREADY OPEN isolated 0.80 QA app.

Three one-shot phases: author (MCP edits), finish (after GUI audio import; MCP
save/reopen/export/loops), stems (after GUI stem export; independent file checks).
No app is launched and no system audio preference is changed. A failed phase is
not safe to retry blindly: inspect the recorded state before continuing.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import time
import unicodedata
import uuid
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import EndpointResolver, call_tool  # noqa: E402


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def store(path, value):
    with path.open("x", encoding="utf-8") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write("\n")


def wav_info(path):
    with wave.open(str(path), "rb") as audio:
        info = {"channels": audio.getnchannels(), "rate": audio.getframerate(),
                "bits": audio.getsampwidth() * 8, "frames": audio.getnframes()}
        nonzero = 0
        pcm_hash = hashlib.sha256()
        while chunk := audio.readframes(8192):
            pcm_hash.update(chunk)
            nonzero += sum(bool(byte) for byte in chunk)
    info.update(nonzeroBytes=nonzero, pcmSHA256=pcm_hash.hexdigest(),
                sha256=digest(path), bytes=path.stat().st_size)
    return info


def validate_local_paths(args):
    home_support = (Path.home() / "Library/Application Support").resolve()
    support = args.qa_root.expanduser().resolve()
    fixture = args.fixture.expanduser().resolve()
    evidence = args.evidence.expanduser().resolve()
    require(support.parent == home_support and re.fullmatch(r"circlr-[a-z0-9-]+-qa", support.name),
            "QA root must be one dedicated circlr-*-qa Application Support directory")
    require(args.bundle_id.startswith("com.circlr.") and args.bundle_id.endswith("qa")
            and args.bundle_id != "com.circlr.desktop", "QA bundle ID required")
    bundle_suffix = args.bundle_id.removeprefix("com.circlr.").removesuffix("qa")
    require(re.fullmatch(r"[a-z0-9-]{1,48}", bundle_suffix) and
            support.name == f"circlr-{bundle_suffix}-qa",
            "QA Support root does not match the bundle's isolated storage name")
    require(args.build.isdigit() and int(args.build) >= 239, "build239 or later required")
    require(fixture.parent == support / "fixtures" and fixture.suffix == ".circlr"
            and fixture.is_dir(), "fixture must be one existing QA .circlr directory")
    require((fixture / "manifest.json").is_file(), "QA fixture manifest is missing")
    require(evidence.parent == ROOT / "qa/generated" and evidence.is_dir(),
            "evidence must be an existing unique qa/generated child directory")
    legacy_socket = support / "Agent/agent.sock"
    require(args.socket.expanduser().resolve() == legacy_socket,
            "socket must be this QA app's exact Agent/agent.sock")
    require(args.socket != Path.home() / "Library/Application Support/circlr/Agent/agent.sock",
            "production socket forbidden")
    return support, fixture, evidence, legacy_socket


class Session:
    def __init__(self, args, fixture, socket):
        self.args = args
        self.fixture = fixture
        self.endpoint = EndpointResolver(socket)
        self.run_id = None
        self.project_id = None

    def call(self, name, arguments=None):
        result = call_tool(self.endpoint, "circlr_" + name, arguments or {})["structuredContent"]
        require(result.get("ok") is True, f"circlr_{name} failed: {result.get('error')}")
        return result["result"]

    def snapshot(self):
        state = self.call("snapshot")
        runtime = state["runtime"]
        require(runtime["bundleID"] == self.args.bundle_id and runtime["version"] == "0.80.0"
                and runtime["build"] == self.args.build, "wrong QA app/version/build")
        require(state["path"] == str(self.fixture), "wrong open project path")
        require(not state["recording"]["busy"] and not state["recording"]["midi"],
                "recording is active")
        if self.run_id is None:
            self.run_id = runtime["runID"]
            self.project_id = state["projectID"]
        require(runtime["runID"] == self.run_id and state["projectID"] == self.project_id,
                "app run or project changed")
        return state

    def scoped(self, name, args=None):
        before = self.snapshot()
        result = self.call(name, {**(args or {}), "projectID": before["projectID"],
                                  "expectedRevision": before["revision"]})
        after = self.snapshot()
        return before, result, after

    def edit(self, operation):
        before, result, after = self.scoped("apply", {"operations": [operation]})
        require(after["revision"] == before["revision"] + 1,
                f"{operation['kind']} did not advance revision once")
        return result, after

    def inspect(self, arrangement, use):
        return self.call("inspect", {"arrangementID": arrangement, "useID": use})

    def wait_job(self, job, limit=180):
        deadline = time.monotonic() + limit
        while time.monotonic() < deadline:
            value = self.call("job", {"jobID": job["jobID"]})["job"]
            if value["state"] != "running":
                require(value["state"] == "completed", f"job ended {value['state']}: {value}")
                return value
            time.sleep(0.5)
        raise TimeoutError(f"job {job['jobID']} did not complete within {limit}s")


def arrangement_path(manifest, arrangement_id):
    arrangement = next(a for a in manifest["arrangements"] if a["id"] == arrangement_id)
    by_id = {use["id"]: use for use in arrangement["uses"]}
    edges = {edge["from"]: edge["to"] for edge in arrangement["edges"]}
    order, cursor = [], arrangement["startID"]
    while cursor is not None:
        require(cursor in by_id and cursor not in order, "invalid or cyclic section path")
        order.append(cursor)
        cursor = edges.get(cursor)
    require(len(order) == len(by_id), "disconnected section path")
    return order, by_id


def automation_curves(node):
    """An effect without automation omits the optional field in inspect JSON."""
    curves = node.get("automation", [])
    require(isinstance(curves, list), "invalid effect automation shape")
    return curves


def export(session, evidence, name, expected_revision):
    target = evidence / f"{name}.wav"
    require(not target.exists(), f"would overwrite {target}")
    before, job, after = session.scoped("export", {"path": str(target)})
    require(before["revision"] == expected_revision and after["revision"] == expected_revision,
            "export changed or raced with music revision")
    done = session.wait_job(job)
    require(target.is_file(), "completed export has no WAV")
    info = wav_info(target)
    require((info["channels"], info["rate"], info["bits"]) == (2, 48000, 24)
            and info["frames"] >= 32 * 48000 and info["nonzeroBytes"] > 0,
            "export WAV is silent, short, or wrong format")
    return {"job": done, "file": info, "path": str(target)}


def author(session, fixture, evidence):
    require(not (evidence / "author.json").exists(), "author phase already recorded; do not retry")
    step_png = session.args.step_png.expanduser().resolve()
    step_ax = session.args.step_ax.expanduser().resolve()
    require(step_png.is_file() and step_ax.is_file() and
            step_png.is_relative_to(evidence) and step_ax.is_relative_to(evidence),
            "saved GUI step PNG/AX evidence required before author")
    state = session.snapshot()
    require(not state["dirty"] and len(state["tracks"]) == 1 and len(state["assets"]) == 0,
            "author needs a saved blank song with only the GUI step")
    arrangement = state["activeArrangementID"]
    uses = next(a["uses"] for a in state["arrangements"] if a["id"] == arrangement)
    require(len(uses) == 1 and uses[0]["name"] == "섹션 1", "not the blank starter")
    first = uses[0]["id"]
    initial = session.inspect(arrangement, first)
    gui_notes = [note for lane in initial["lanes"] for note in lane["notes"]]
    require(initial["clock"]["beats"] == 16 and len(gui_notes) == 1 and
            math.isclose(gui_notes[0]["beat"], 0, abs_tol=1e-8) and gui_notes[0]["pitch"] == 60 and
            all(not lane["audio"] for lane in initial["lanes"]),
            "blank section must contain only the GUI beat-zero/pitch-60 step")
    require(state["global"]["tempo"] == 120, "blank starter is not 120 BPM")
    initial_hash = digest(fixture / "manifest.json")
    session.edit({"kind": "set_section", "arrangementID": arrangement, "useID": first, "name": "인트로"})
    ids = {first}
    session.edit({"kind": "insert_section", "arrangementID": arrangement, "useID": first,
                  "name": "벌스", "bars": 4, "at": {"x": 1000, "y": 0}})
    current = session.snapshot()
    verse = next(u["id"] for a in current["arrangements"] if a["id"] == arrangement
                 for u in a["uses"] if u["id"] not in ids)
    ids.add(verse)
    session.edit({"kind": "insert_section", "arrangementID": arrangement, "useID": verse,
                  "name": "아웃트로", "bars": 4, "at": {"x": 2000, "y": 0}})
    current = session.snapshot()
    outro = next(u["id"] for a in current["arrangements"] if a["id"] == arrangement
                 for u in a["uses"] if u["id"] not in ids)
    session.edit({"kind": "set_section", "arrangementID": arrangement, "useID": verse,
                  "repeatCount": 2})
    before_move = session.snapshot()
    session.edit({"kind": "reorder_section", "arrangementID": arrangement,
                  "useID": outro, "to": verse})
    move_state = session.snapshot()
    session.scoped("save")
    moved_order, _ = arrangement_path(json.loads((fixture / "manifest.json").read_text()), arrangement)
    require(moved_order == [first, outro, verse], "reorder did not change song path")
    undo = session.call("undo", {"projectID": move_state["projectID"],
                                 "expectedRevision": move_state["revision"],
                                 "expectedLayoutRevision": move_state["layoutRevision"]})
    restored = session.snapshot()
    require(restored["revision"] == move_state["revision"] + 1, "reorder Undo failed")
    lane_first = initial["lanes"][0]["id"]
    session.edit({"kind": "set_step", "arrangementID": arrangement, "useID": first,
                  "laneID": lane_first, "stepIndex": 8, "pitch": 62,
                  "enabled": True, "subdivisions": 4, "velocity": 80, "gate": 2})
    require(any(note["id"] == gui_notes[0]["id"] for note in
                session.inspect(arrangement, first)["lanes"][0]["notes"]),
            "MCP step replaced the GUI-authored note")
    lane_verse = session.inspect(arrangement, verse)["lanes"][0]["id"]
    verse_notes = [{"id": str(uuid.uuid4()).upper(), "beat": beat, "length": 1,
                    "pitch": pitch, "velocity": 76}
                   for beat, pitch in [(0, 64), (4, 67), (8, 69), (12, 67)]]
    session.edit({"kind": "set_notes", "arrangementID": arrangement, "useID": verse,
                  "laneID": lane_verse, "notes": verse_notes})
    lane_outro = session.inspect(arrangement, outro)["lanes"][0]["id"]
    session.edit({"kind": "set_step", "arrangementID": arrangement, "useID": outro,
                  "laneID": lane_outro, "stepIndex": 0, "pitch": 72,
                  "enabled": True, "subdivisions": 4, "velocity": 72, "gate": 4})
    baseline_revision = session.snapshot()["revision"]
    baseline = export(session, evidence, "before-fx", baseline_revision)
    graph = session.inspect(arrangement, verse)["graph"]
    track_id = state["tracks"][0]["id"]
    instrument = next(node["id"] for node in graph["nodes"]
                      if node["content"].get("instrument", {}).get("trackID") == track_id)
    session.edit({"kind": "add_effect", "arrangementID": arrangement, "useID": verse,
                  "from": instrument, "name": "QA gain",
                  "effect": {"kind": "gain", "amount": 0.65, "secondary": 0.25}})
    graph = session.inspect(arrangement, verse)["graph"]
    effects = [node for node in graph["nodes"]
               if node["content"].get("effect", {}).get("_0", {}).get("kind") == "gain"]
    require(len(effects) == 1, "gain effect missing")
    effect_id = effects[0]["id"]
    fx = export(session, evidence, "with-fx", session.snapshot()["revision"])
    points = [{"id": str(uuid.uuid4()).upper(), "beat": beat,
               "value": value, "shape": "linear"}
              for beat, value in [(0, 0.3), (12, 0.8)]]
    operation = {"kind": "set_automation", "arrangementID": arrangement,
                 "useID": verse, "nodeID": effect_id,
                 "parameter": "gain", "automationPoints": points}
    session.edit(operation)
    automated = session.inspect(arrangement, verse)
    effect = next(node for node in automated["graph"]["nodes"] if node["id"] == effect_id)
    require(any(curve["points"] == points for curve in automation_curves(effect)), "automation points missing")
    store(evidence / "automation-applied.json", {"projectID": session.project_id,
          "revision": session.snapshot()["revision"], "effectNode": effect})
    current = session.snapshot()
    session.call("undo", {"projectID": current["projectID"], "expectedRevision": current["revision"],
                          "expectedLayoutRevision": current["layoutRevision"]})
    undone = session.inspect(arrangement, verse)
    effect_after_undo = next(node for node in undone["graph"]["nodes"] if node["id"] == effect_id)
    store(evidence / "automation-after-undo.json", {"projectID": session.project_id,
          "revision": session.snapshot()["revision"], "effectNode": effect_after_undo})
    require(not any(curve["points"] == points for curve in automation_curves(effect_after_undo)),
            "automation Undo did not restore graph")
    session.edit(operation)
    automated_export = export(session, evidence, "with-automation", session.snapshot()["revision"])
    require(baseline["file"]["pcmSHA256"] != fx["file"]["pcmSHA256"] and
            fx["file"]["pcmSHA256"] != automated_export["file"]["pcmSHA256"],
            "FX or automation did not change WAV PCM")
    before, saved, after = session.scoped("save")
    require(not after["dirty"] and before["revision"] == after["revision"], "save failed")
    manifest = json.loads((fixture / "manifest.json").read_text())
    order, by_id = arrangement_path(manifest, arrangement)
    require(order == [first, verse, outro] and by_id[verse]["repeatCount"] == 2,
            "section order/repeat incorrect after Undo")
    require(all(session.inspect(arrangement, uid)["lanes"][0]["notes"] for uid in order),
            "one of three sections has no MIDI notes")
    report = {"schema": "circlr-final-daw-author-v1", "status": "MCP_PASS_GUI_PENDING",
              "bundleID": session.args.bundle_id, "build": session.args.build,
              "runID": session.run_id, "projectID": session.project_id,
              "initialManifestSHA256": initial_hash, "savedManifestSHA256": digest(fixture / "manifest.json"),
              "revision": after["revision"], "arrangementID": arrangement,
              "guiStepNote": gui_notes[0], "guiStepPNG": str(step_png), "guiStepAX": str(step_ax),
              "sectionIDs": {"intro": first, "verse": verse, "outro": outro},
              "reorderBeforeRevision": before_move["revision"],
              "reorderChangedRevision": move_state["revision"],
              "reorderRestoredRevision": restored["revision"],
              "originalTrackID": track_id,
              "effectNodeID": effect_id, "automationPoints": points,
              "exports": [baseline, fx, automated_export],
              "manualGates": ["startup UI/AX", "GUI step PNG/AX human review",
                              "audio import GUI/AX"]}
    store(evidence / "author.json", report)
    return report


def wait_loops(session, mode, use_id, timeout):
    state = session.snapshot()
    if mode == "section":
        session.call("focus", {"arrangementID": state["activeArrangementID"], "useID": use_id})
    _, changed, _ = session.scoped("playback_loop", {"loopMode": mode})
    require(changed["view"]["loopMode"] == mode, "loop setting not applied")
    session.call("play")
    deadline = time.monotonic() + timeout
    samples = []
    try:
        while time.monotonic() < deadline:
            state = session.snapshot()
            view = state["view"]
            output = state["output"]
            samples.append({"time": time.monotonic(), "iteration": view["loopIteration"],
                            "elapsedSeconds": view["elapsedSeconds"],
                            "outputPhase": output["phase"],
                            "actualOutputDeviceName": output.get("actualOutputDeviceName"),
                            "transition": view["loopTransition"]})
            if len(samples) > 1:
                require(samples[-1]["iteration"] >= samples[-2]["iteration"] and
                        samples[-1]["elapsedSeconds"] >= samples[-2]["elapsedSeconds"],
                        "loop clock or iteration moved backward")
            if view["loopIteration"] >= 2:
                require(output["phase"] == "ready" and
                        output.get("actualOutputDeviceName") == session.args.expected_output,
                        "loop played on unexpected output")
                require(view["loopTransition"]["busy"] is False, "loop transition still busy")
                return samples
            time.sleep(1)
        raise TimeoutError(f"{mode} loop did not reach two cycles in {timeout}s")
    finally:
        session.call("stop")
        state = session.snapshot()
        require(not state["playback"]["playing"], "transport still playing after Stop")


def finish(session, fixture, evidence, args):
    require((evidence / "author.json").is_file() and not (evidence / "finish.json").exists(),
            "author report required; finish phase cannot be retried blindly")
    author_report = json.loads((evidence / "author.json").read_text())
    source = args.audio_source.expanduser().resolve()
    import_png = args.import_png.expanduser().resolve()
    import_ax = args.import_ax.expanduser().resolve()
    require(source.is_file() and source.is_relative_to(evidence) and
            import_png.is_file() and import_ax.is_file() and
            import_png.is_relative_to(evidence) and import_ax.is_relative_to(evidence),
            "QA source audio and GUI import PNG/AX evidence required")
    state = session.snapshot()
    require(state["projectID"] == author_report["projectID"] and
            state["revision"] == author_report["revision"] + 1 and len(state["assets"]) == 1 and
            len(state["tracks"]) == 2, "GUI import was not the only music change")
    track_ids = {track["id"] for track in state["tracks"]}
    require(author_report["originalTrackID"] in track_ids and len(track_ids) == 2,
            "original instrument track was replaced")
    audio_track = (track_ids - {author_report["originalTrackID"]}).pop()
    asset = state["assets"][0]
    staged = Path(asset["path"]).resolve()
    staging_root = (args.qa_root.expanduser().resolve() / "Imports")
    require(staged.is_file() and staged.is_relative_to(staging_root) and
            staged.parent.parent == staging_root and staged.name == f"{asset['id']}.wav",
            "GUI import was not staged inside the isolated QA Imports directory")
    require(asset["checksum"] == digest(source), "GUI imported a different audio source")
    require(digest(staged) == digest(source), "staged audio differs from authored input")
    require(asset["sampleRate"] == 48000 and math.isclose(asset["duration"], 2, abs_tol=1e-5),
            "imported asset metadata differs from QA tone")
    intro = author_report["sectionIDs"]["intro"]
    inspected = session.inspect(author_report["arrangementID"], intro)
    clips = [(lane, clip) for lane in inspected["lanes"] for clip in lane["audio"]]
    require(len(clips) == 1, "intro must contain exactly one imported clip")
    lane, clip = clips[0]
    require(lane["trackID"] == audio_track and clip["assetID"] == asset["id"] and
            math.isclose(clip["beat"], 0, abs_tol=1e-8) and
            math.isclose(clip["sourceStart"], 0, abs_tol=1e-8) and
            math.isclose(clip["duration"], 2, abs_tol=1e-5),
            "GUI import missed intro/new-track/beat-zero/full-source placement")
    require(all(not lane["audio"] for use in (author_report["sectionIDs"]["verse"],
                                            author_report["sectionIDs"]["outro"])
                for lane in session.inspect(author_report["arrangementID"], use)["lanes"]),
            "GUI import also changed another section")
    _, _, saved = session.scoped("save")
    require(not saved["dirty"], "imported project not saved")
    saved_manifest = json.loads((fixture / "manifest.json").read_text())
    stored_asset = next((item for item in saved_manifest["assets"] if item["id"] == asset["id"]), None)
    require(stored_asset is not None, "saved package lost imported asset")
    asset_path = Path(stored_asset["path"])
    require(not asset_path.is_absolute() and asset_path.parts[0] == "media" and
            ".." not in asset_path.parts, "unsafe saved package asset path")
    imported = fixture / asset_path
    require(stored_asset["checksum"] == digest(source),
            "saved asset checksum differs from authored input")
    require(imported.is_file() and digest(imported) == digest(source),
            "saved imported audio bytes differ from authored input")
    saved_hash = digest(fixture / "manifest.json")
    before, job, after = session.scoped("open", {"path": str(fixture)})
    require(before["revision"] == after["revision"], "open changed revision before completion")
    session.wait_job(job, 30)
    reopened = session.snapshot()
    require(reopened["revision"] == saved["revision"] and not reopened["dirty"] and
            digest(fixture / "manifest.json") == saved_hash and len(reopened["assets"]) == 1,
            "native reopen did not preserve saved song")
    master = export(session, evidence, "final-master", reopened["revision"])
    section_samples = wait_loops(session, "section", author_report["sectionIDs"]["verse"], 65)
    song_samples = wait_loops(session, "song", None, 100)
    final = session.snapshot()
    require(final["revision"] == reopened["revision"] and not final["dirty"],
            "loop playback changed saved music")
    report = {"schema": "circlr-final-daw-finish-v1", "status": "MCP_AND_FILE_PASS_GUI_REVIEW_PENDING",
              "bundleID": args.bundle_id, "build": args.build, "projectID": final["projectID"],
              "runID": session.run_id, "revision": final["revision"],
              "sourceAudioSHA256": digest(source), "importedAudioSHA256": digest(imported),
              "stagedAudioSHA256": digest(staged), "stagedAudioPath": str(staged),
              "audioTrackID": audio_track, "audioClipID": clip["id"],
              "audioPlacement": {"useID": intro, "laneID": lane["id"], "beat": clip["beat"],
                                 "sourceStart": clip["sourceStart"], "duration": clip["duration"]},
              "importPNG": str(import_png), "importAX": str(import_ax),
              "savedManifestSHA256": saved_hash, "master": master,
              "sectionLoop": section_samples, "songLoop": song_samples,
              "manualGates": ["import screenshot/AX human review", "independent listening",
                              "GUI stems export and validation"]}
    store(evidence / "finish.json", report)
    return report


def stems(evidence, args):
    require((evidence / "finish.json").is_file() and not (evidence / "stems.json").exists(),
            "finish report required; stems phase already recorded")
    report = json.loads((evidence / "finish.json").read_text())
    fixture = args.fixture.expanduser().resolve()
    require(digest(fixture / "manifest.json") == report["savedManifestSHA256"],
            "song changed after finish phase")
    directory = args.stems_dir.expanduser().resolve()
    require(directory.parent == evidence and directory.is_dir(),
            "stem directory must be a direct GUI-produced child of QA evidence")
    stems_png = args.stems_png.expanduser().resolve()
    stems_ax = args.stems_ax.expanduser().resolve()
    require(stems_png.is_file() and stems_ax.is_file() and
            stems_png.is_relative_to(evidence) and stems_ax.is_relative_to(evidence),
            "GUI stems PNG/AX evidence required")
    files = list(directory.iterdir())
    require(all(not path.is_symlink() for path in files), "symlink in stem folder")
    manifest = json.loads((directory / "circlr-export.json").read_text())
    require(manifest["format"] == "circlr-stems-v1" and
            manifest["musicRevision"] == report["revision"] and
            math.isclose(manifest["bodySeconds"], 32, abs_tol=0.01),
            "stem metadata does not match saved song")
    by_name = {unicodedata.normalize("NFC", path.name): path for path in files}
    listed = [unicodedata.normalize("NFC", name) for name in manifest["stemFiles"]]
    require(len(listed) == 2 and all(name in by_name for name in listed) and
            "전체 mix.wav" in by_name, "expected two stems and mix")
    output = {name: wav_info(by_name[name]) for name in [*listed, "전체 mix.wav"]}
    master = report["master"]["file"]
    require(all((entry["channels"], entry["rate"], entry["bits"], entry["frames"])
                == (2, 48000, 24, master["frames"]) and entry["nonzeroBytes"] > 0
                for entry in output.values()), "stem WAV format, length, or PCM invalid")
    require(output["전체 mix.wav"]["pcmSHA256"] == master["pcmSHA256"],
            "GUI stem mix differs from same revision master export")
    require(not any(path.name.startswith((".circlr-export", ".circlr-backup"))
                    for path in evidence.iterdir()), "stage/backup residue remains")
    result = {"schema": "circlr-final-daw-stems-v1", "status": "FILES_PASS_GUI_REVIEW_PENDING",
              "folder": str(directory), "metadata": manifest, "wavFiles": output,
              "stemsPNG": str(stems_png), "stemsAX": str(stems_ax),
              "manualGates": ["GUI export screenshot/AX human review", "physical listening"]}
    store(evidence / "stems.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("author", "finish", "stems"))
    parser.add_argument("--qa-root", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--socket", type=Path, required=True, help="exact QA Agent/agent.sock")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--audio-source", type=Path)
    parser.add_argument("--step-png", type=Path)
    parser.add_argument("--step-ax", type=Path)
    parser.add_argument("--import-png", type=Path)
    parser.add_argument("--import-ax", type=Path)
    parser.add_argument("--expected-output", default="Mac Studio 스피커")
    parser.add_argument("--stems-dir", type=Path)
    parser.add_argument("--stems-png", type=Path)
    parser.add_argument("--stems-ax", type=Path)
    args = parser.parse_args()
    _, fixture, evidence, socket = validate_local_paths(args)
    if args.phase == "stems":
        require(args.stems_dir and args.stems_png and args.stems_ax,
                "stems phase requires --stems-dir/--stems-png/--stems-ax")
        result = stems(evidence, args)
    else:
        session = Session(args, fixture, socket)
        if args.phase == "author":
            require(args.step_png and args.step_ax,
                    "author phase requires --step-png/--step-ax from GUI editing")
            result = author(session, fixture, evidence)
        else:
            require(args.audio_source and args.import_png and args.import_ax,
                    "finish phase requires --audio-source/--import-png/--import-ax")
            result = finish(session, fixture, evidence, args)
    print(json.dumps({"phase": args.phase, "status": result["status"], "evidence": str(evidence)},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
