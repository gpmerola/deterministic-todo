#!/usr/bin/env python3
"""Validate and summarize privacy-preserving Movement intensive JSONL chunks."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def _number(value: Any) -> float | None:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower, upper = math.floor(position), math.ceil(position)
    return ordered[lower] if lower == upper else ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def _activity(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in ("type", "activity", "name"):
            if isinstance(value.get(key), str):
                return value[key]
    return "unknown"


def summarize(paths: list[Path]) -> dict[str, Any]:
    events, malformed, empty = [], [], 0
    for path in paths:
        with path.open(encoding="utf-8") as source:
            for line_number, line in enumerate(source, 1):
                if not line.strip():
                    empty += 1
                    continue
                try:
                    event = json.loads(line)
                    if not isinstance(event, dict):
                        raise ValueError("root_not_object")
                    events.append(event)
                except (json.JSONDecodeError, ValueError) as error:
                    malformed.append({"file": str(path), "line": line_number, "error": str(error)})

    starts = [event for event in events if event.get("kind") == "segment_start"]
    continuations = sum(event.get("kind") == "segment_continuation" for event in events)
    raw_windows = [event for event in events if event.get("kind") == "sensor_window"]
    declared_gaps = [event for event in events if event.get("kind") == "coverage_gap"]
    unknown = Counter(str(event.get("kind", "missing")) for event in events)
    for known in ("segment_start", "segment_continuation", "sensor_window", "coverage_gap"):
        unknown.pop(known, None)

    unique, invalid = {}, 0
    for window in raw_windows:
        key = (window.get("experiment_id"), window.get("segment_id"), window.get("started_at_ms"), window.get("ended_at_ms"))
        if not all(key) or _number(window.get("elapsed_ms")) is None:
            invalid += 1
        else:
            unique.setdefault(key, window)
    windows = list(unique.values())
    duplicates = len(raw_windows) - invalid - len(windows)

    durations, activities = [], Counter()
    detector = counter = gps_samples = raw_distance = rx = tx = 0.0
    counter_missing = interactive_ms = power_save_ms = 0
    accuracy, speed, cpu, heap, battery = [], [], [], [], []
    by_segment: dict[tuple[Any, Any], list[dict[str, Any]]] = defaultdict(list)
    for window in windows:
        duration = _number(window["elapsed_ms"]) or 0
        durations.append(duration)
        activities[_activity(window.get("activity"))] += round(duration)
        detector += _number(window.get("step_detector_events")) or 0
        counter_delta = _number(window.get("step_counter_delta"))
        if counter_delta is None:
            counter_missing += 1
        else:
            counter += counter_delta
        location = window.get("location") if isinstance(window.get("location"), dict) else {}
        gps_samples += _number(location.get("sample_count")) or 0
        raw_distance += _number(location.get("raw_path_distance_m")) or 0
        for value, destination in ((location.get("accuracy_mean_m"), accuracy), (location.get("speed_mean_mps"), speed)):
            parsed = _number(value)
            if parsed is not None:
                destination.append(parsed)
        resources = window.get("resources") if isinstance(window.get("resources"), dict) else {}
        for key, destination in (("cpu_ms", cpu), ("java_heap_used_bytes", heap)):
            parsed = _number(resources.get(key))
            if parsed is not None:
                destination.append(parsed)
        rx += max(0, _number(resources.get("uid_rx_bytes")) or 0)
        tx += max(0, _number(resources.get("uid_tx_bytes")) or 0)
        device = window.get("device") if isinstance(window.get("device"), dict) else {}
        observed, level = _number(window.get("ended_at_ms")), _number(device.get("battery_percent"))
        if observed and level is not None and 0 <= level <= 100:
            battery.append((int(observed), int(level)))
        interactive_ms += round(duration) if device.get("interactive") is True else 0
        power_save_ms += round(duration) if device.get("power_save") is True else 0
        by_segment[(window.get("experiment_id"), window.get("segment_id"))].append(window)

    gaps, overlaps = [], 0
    for segment in by_segment.values():
        segment.sort(key=lambda item: item["started_at_ms"])
        for previous, current in zip(segment, segment[1:]):
            gap = int(current["started_at_ms"]) - int(previous["ended_at_ms"])
            if gap > 1_000:
                gaps.append(gap)
            elif gap < -1_000:
                overlaps += 1
    ordered_windows = sorted(windows, key=lambda item: item["started_at_ms"])
    cross_segment_gaps = []
    for previous, current in zip(ordered_windows, ordered_windows[1:]):
        if previous.get("segment_id") == current.get("segment_id"):
            continue
        gap = int(current["started_at_ms"]) - int(previous["ended_at_ms"])
        if gap > 1_000:
            cross_segment_gaps.append(gap)
    declared_gap_durations = [value for event in declared_gaps
        if (value := _number(event.get("duration_ms"))) is not None and value >= 0]
    apps = Counter()
    for event in starts:
        app = event.get("app") if isinstance(event.get("app"), dict) else {}
        apps[f'{app.get("version_name", "?")}+{app.get("version_code", "?")}'] += 1
    battery.sort()
    elapsed, cpu_total = sum(durations), sum(cpu)
    return {
        "schema_version": 1,
        "inputs": [str(path) for path in paths],
        "integrity": {"files": len(paths), "events": len(events), "empty_lines": empty, "malformed_lines": malformed,
            "sensor_windows": len(windows), "duplicate_windows": duplicates, "invalid_windows": invalid,
            "segment_starts": len(starts), "segment_continuations": continuations, "unknown_kinds": dict(sorted(unknown.items())),
            "gaps_over_1s": len(gaps) + len(cross_segment_gaps),
            "within_segment_gaps_over_1s": len(gaps),
            "cross_segment_gaps_over_1s": len(cross_segment_gaps),
            "largest_gap_ms": max(gaps + cross_segment_gaps, default=0),
            "declared_coverage_gaps": len(declared_gaps),
            "declared_gap_total_ms": round(sum(declared_gap_durations)),
            "declared_largest_gap_ms": max(declared_gap_durations, default=0),
            "overlaps_over_1s": overlaps},
        "coverage": {"elapsed_hours": round(elapsed / 3_600_000, 4), "window_elapsed_ms_p50": _percentile(durations, .5),
            "window_elapsed_ms_p95": _percentile(durations, .95), "experiments": sorted({str(key[0]) for key in by_segment}),
            "segments": len(by_segment), "app_segments": dict(sorted(apps.items()))},
        "activity_hours": {key: round(value / 3_600_000, 4) for key, value in sorted(activities.items())},
        "movement": {"step_detector_events": round(detector), "step_counter_delta": round(counter),
            "step_counter_missing_windows": counter_missing, "gps_samples": round(gps_samples), "raw_path_distance_m": round(raw_distance, 2),
            "accuracy_mean_m_p50": _percentile(accuracy, .5), "accuracy_mean_m_p95": _percentile(accuracy, .95),
            "speed_mean_mps_p95": _percentile(speed, .95)},
        "resources": {"cpu_ms_total": round(cpu_total), "cpu_share_percent": round(100 * cpu_total / elapsed, 4) if elapsed else None,
            "cpu_ms_per_window_p95": _percentile(cpu, .95), "uid_rx_bytes": round(rx), "uid_tx_bytes": round(tx),
            "java_heap_used_bytes_p50": _percentile(heap, .5), "java_heap_used_bytes_p95": _percentile(heap, .95)},
        "device": {"battery_first_percent": battery[0][1] if battery else None, "battery_last_percent": battery[-1][1] if battery else None,
            "battery_observed_drop_points": battery[0][1] - battery[-1][1] if len(battery) >= 2 else None,
            "battery_note": "Observed endpoints include charging and other apps; not app attribution.",
            "interactive_hours": round(interactive_ms / 3_600_000, 4), "power_save_hours": round(power_save_ms / 3_600_000, 4)},
    }


def render_text(report: dict[str, Any]) -> str:
    integrity, coverage, movement, resources, device = (report[key] for key in ("integrity", "coverage", "movement", "resources", "device"))
    return "\n".join((
        f"Files: {integrity['files']} | events: {integrity['events']} | windows: {integrity['sensor_windows']}",
        f"Coverage: {coverage['elapsed_hours']:.4f} h | segments: {coverage['segments']} | gaps >1s: {integrity['gaps_over_1s']}",
        f"Steps detector/counter: {movement['step_detector_events']} / {movement['step_counter_delta']} | GPS samples: {movement['gps_samples']}",
        f"Raw GPS path: {movement['raw_path_distance_m']:.2f} m | accuracy p50/p95: {movement['accuracy_mean_m_p50']} / {movement['accuracy_mean_m_p95']} m",
        f"CPU share: {resources['cpu_share_percent']}% | RX/TX: {resources['uid_rx_bytes']} / {resources['uid_tx_bytes']} bytes",
        f"Battery endpoints: {device['battery_first_percent']}% -> {device['battery_last_percent']}% (not app attribution)",
        f"Malformed/invalid/duplicates: {len(integrity['malformed_lines'])} / {integrity['invalid_windows']} / {integrity['duplicate_windows']}",
    ))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path, help="JSONL chunks")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args(argv)
    missing = [str(path) for path in args.paths if not path.is_file()]
    if missing:
        parser.error("files not found: " + ", ".join(missing))
    report = summarize(args.paths)
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) if args.json else render_text(report))
    return 2 if report["integrity"]["malformed_lines"] or report["integrity"]["invalid_windows"] else 0


if __name__ == "__main__":
    sys.exit(main())
