package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import java.util.List;
import org.junit.Test;

public class GpsSamplingStatsTest {
    @Test public void reportsObservedCadenceAndLongTail() {
        GpsSamplingStats.Summary summary = GpsSamplingStats.summarize(List.of(
            point(1_000), point(2_000), point(3_000), point(6_000)));
        assertEquals(3, summary.intervalCount());
        assertEquals(1_000L, summary.medianMillis().longValue());
        assertEquals(3_000L, summary.p95Millis().longValue());
        assertEquals(1_666.67, summary.meanMillis(), 0.01);
    }

    private static TrackPoint point(long time) {
        TrackPoint point = new TrackPoint(); point.timestampMillis = time; return point;
    }
}
