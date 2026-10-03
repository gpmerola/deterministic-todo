import json
import tempfile
import unittest
from pathlib import Path

from analyze_movement_intensive import summarize


class AnalyzeMovementIntensiveTest(unittest.TestCase):
    def test_summarizes_and_deduplicates_windows(self):
        start = {"kind": "segment_start", "experiment_id": "exp", "segment_id": "seg",
                 "app": {"version_name": "2.25.10", "version_code": 118}}
        first = {"kind": "sensor_window", "experiment_id": "exp", "segment_id": "seg", "started_at_ms": 1000,
                 "ended_at_ms": 6000, "elapsed_ms": 5000, "activity": {"type": "walking"},
                 "step_detector_events": 4, "step_counter_delta": 5,
                 "location": {"sample_count": 5, "raw_path_distance_m": 3.5, "accuracy_mean_m": 6, "speed_mean_mps": 1},
                 "resources": {"cpu_ms": 10, "uid_rx_bytes": 20, "uid_tx_bytes": 30, "java_heap_used_bytes": 100},
                 "device": {"battery_percent": 80, "interactive": True, "power_save": False}}
        second = {**first, "started_at_ms": 7500, "ended_at_ms": 12500, "step_detector_events": 6,
                  "step_counter_delta": None, "device": {"battery_percent": 79, "interactive": False, "power_save": True}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chunk.jsonl"
            path.write_text("\n".join(json.dumps(row) for row in (start, first, first, second)) + "\n")
            report = summarize([path])
        self.assertEqual(report["integrity"]["sensor_windows"], 2)
        self.assertEqual(report["integrity"]["duplicate_windows"], 1)
        self.assertEqual(report["integrity"]["gaps_over_1s"], 1)
        self.assertEqual(report["movement"]["step_detector_events"], 10)
        self.assertEqual(report["movement"]["step_counter_missing_windows"], 1)
        self.assertEqual(report["device"]["battery_observed_drop_points"], 1)
        self.assertEqual(report["coverage"]["app_segments"], {"2.25.10+118": 1})

    def test_reports_malformed_and_invalid_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chunk.jsonl"
            path.write_text('{"kind":"sensor_window"}\nnot-json\n')
            report = summarize([path])
        self.assertEqual(len(report["integrity"]["malformed_lines"]), 1)
        self.assertEqual(report["integrity"]["invalid_windows"], 1)

    def test_reports_declared_and_cross_segment_gaps(self):
        first = {"kind": "sensor_window", "experiment_id": "exp", "segment_id": "one",
                 "started_at_ms": 1_000, "ended_at_ms": 6_000, "elapsed_ms": 5_000}
        gap = {"kind": "coverage_gap", "experiment_id": "exp", "segment_id": "two",
               "start_ms": 6_000, "end_ms": 36_000, "duration_ms": 30_000,
               "missing_expected_windows": 5, "reason": "service_restart"}
        second = {"kind": "sensor_window", "experiment_id": "exp", "segment_id": "two",
                  "started_at_ms": 36_000, "ended_at_ms": 41_000, "elapsed_ms": 5_000}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chunk.jsonl"
            path.write_text("\n".join(json.dumps(row) for row in (first, gap, second)) + "\n")
            report = summarize([path])
        self.assertEqual(report["integrity"]["cross_segment_gaps_over_1s"], 1)
        self.assertEqual(report["integrity"]["declared_coverage_gaps"], 1)
        self.assertEqual(report["integrity"]["declared_gap_total_ms"], 30_000)
        self.assertEqual(report["integrity"]["unknown_kinds"], {})


if __name__ == "__main__":
    unittest.main()
