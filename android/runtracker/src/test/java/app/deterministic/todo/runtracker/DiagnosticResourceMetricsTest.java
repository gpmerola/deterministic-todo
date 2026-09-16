package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class DiagnosticResourceMetricsTest {
    @Test public void normalizesCpuAndNetworkByElapsedTime() {
        assertEquals(2.0, DiagnosticResourceMetrics.cpuPercentOfOneCore(72_000L, 3_600_000L), 0.001);
        assertEquals(120_000.0, DiagnosticResourceMetrics.bytesPerHour(60_000L, 1_800_000L), 0.001);
    }

    @Test public void rejectsMissingOrZeroDuration() {
        assertNull(DiagnosticResourceMetrics.cpuPercentOfOneCore(null, 100L));
        assertNull(DiagnosticResourceMetrics.bytesPerHour(100L, 0L));
    }
}
