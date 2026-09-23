#!/usr/bin/env python3
"""Measure playback callback cadence in an isolated circlr app.

This is a main-loop diagnostic, not a measurement of compositor-presented FPS.
Start playback and wait for preparation to finish before running it.
"""

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mcp.server import call_tool


def snapshot(socket):
    reply = call_tool(socket, "circlr_snapshot", {})["structuredContent"]
    if not reply.get("ok"):
        raise RuntimeError(reply)
    return reply["result"]["playback"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--seconds", type=float, default=15.0)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")

    first = snapshot(args.socket)
    began = time.monotonic()
    time.sleep(args.seconds)
    last = snapshot(args.socket)
    elapsed = time.monotonic() - began
    count = last["frameCount"] - first["frameCount"]
    first_timing = first.get("timing") or {}
    last_timing = last.get("timing") or {}
    draw_rates = {}
    for name in ("visualUpdate", "screenDraw", "movieDraw"):
        before = (first_timing.get(name) or {}).get("calls")
        after = (last_timing.get(name) or {}).get("calls")
        if before is not None and after is not None:
            draw_rates[name] = {
                "callbacks": after - before,
                "callbackRateHz": round((after - before) / elapsed, 2),
            }
    result = {
        "seconds": round(elapsed, 3),
        "callbackCount": count,
        "callbackRateHz": round(count / elapsed, 2),
        "canvasSize": first.get("canvasSize"),
        "startPlaybackSeconds": first.get("seconds"),
        "endPlaybackSeconds": last.get("seconds"),
        "startPlaying": first.get("playing"),
        "endPlaying": last.get("playing"),
        "startFollow": first.get("followedTarget"),
        "endFollow": last.get("followedTarget"),
        "lifetimeMaximumCallbackGapSeconds": last.get("maximumFrameGap"),
        "callbackRates": draw_rates,
        "timingScope": "p50/p95/p99: last 600 callbacks (may overlap before interval); maxima: app lifetime",
        # Native timing is a rolling last-600-callback view, not this exact window.
        "trailingTimingLast600Callbacks": last.get("timing"),
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
