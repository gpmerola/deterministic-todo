package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import org.junit.Test;
import java.time.ZoneId;
import java.util.List;

public class UnifiedDiagnosticReportTest {
    @Test public void stableThreeHourBucketName() {
        assertEquals("unified_diagnostics_2026-08-21_12.json",
            UnifiedDiagnosticReport.fileName(1787313600000L, ZoneId.of("UTC")));
    }

    @Test public void summarizesWatchSamplesWithoutTimeline() {
        BipUActivitySample first = sample(1_000, 12, 70);
        BipUActivitySample second = sample(61_000, 15, 74);
        UnifiedDiagnosticReport.BipSummary summary = UnifiedDiagnosticReport.summarizeBipWindow(
            List.of(first, second), 121_000, 120_000);
        assertEquals(2, summary.sampleCount());
        assertEquals(27, summary.steps());
        assertEquals(72.0, summary.heartRateMeanBpm(), 0.001);
        assertTrue(summary.minuteCoverageRatio() <= 1.0);
        assertEquals(Long.valueOf(60_000), summary.lastSampleAgeMillis());
    }

    private static BipUActivitySample sample(long timestamp, int steps, int heartRate) {
        BipUActivitySample sample = new BipUActivitySample();
        sample.timestampMillis = timestamp;
        sample.steps = steps;
        sample.heartRate = heartRate;
        return sample;
    }
}
