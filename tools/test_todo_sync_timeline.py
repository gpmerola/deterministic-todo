"""Pure Java regression: historical success versus an unfinished current cycle."""
import pathlib
import subprocess
import tempfile
import unittest


class TodoSyncTimelineTest(unittest.TestCase):
    def test_latest_cycle_wins_over_historical_success(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        source = root / 'android/app/src/main/java/app/deterministic/todo/deterministic_todo/TodoSyncTimeline.java'
        with tempfile.TemporaryDirectory(prefix='todo-timeline-') as directory:
            harness = pathlib.Path(directory) / 'TimelineTest.java'
            harness.write_text('''
import app.deterministic.todo.deterministic_todo.TodoSyncTimeline;
public class TimelineTest {
  public static void main(String[] args) {
    String a = "2026-09-11T10:00:00Z", b = "2026-09-11T10:01:00Z", c = "2026-09-11T10:02:00Z";
    assert TodoSyncTimeline.unfinished(b, a, null, null) : "old success hid new cycle";
    assert !TodoSyncTimeline.unfinished(b, c, null, null) : "completion stayed busy";
    assert !TodoSyncTimeline.unfinished(b, a, c, null) : "failure stayed busy";
    assert !TodoSyncTimeline.unfinished(b, a, null, c) : "cancellation stayed busy";
    assert !TodoSyncTimeline.unfinished(null, a, null, null);
    assert TodoSyncTimeline.unfinished(b, null, null, null);
  }
}
''', encoding='utf-8')
            subprocess.run(['javac', '-d', directory, str(source), str(harness)], check=True, capture_output=True)
            subprocess.run(['java', '-ea', '-cp', directory, 'TimelineTest'], check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
