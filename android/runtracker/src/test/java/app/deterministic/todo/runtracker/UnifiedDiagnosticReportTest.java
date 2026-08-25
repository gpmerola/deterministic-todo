package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import org.junit.Test;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

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

    @Test public void serializesNestedDiagnosticMapsAsJsonObjects() throws Exception {
        Object value = UnifiedDiagnosticReport.jsonValue(Map.of(
            "phase", Map.of("outcome", "success", "duration_ms", 12L)));
        org.json.JSONObject json = (org.json.JSONObject) value;
        assertEquals("success", json.getJSONObject("phase").getString("outcome"));
        assertEquals(12L, json.getJSONObject("phase").getLong("duration_ms"));
    }

    private static BipUActivitySample sample(long timestamp, int steps, int heartRate) {
        BipUActivitySample sample = new BipUActivitySample();
        sample.timestampMillis = timestamp;
        sample.steps = steps;
        sample.heartRate = heartRate;
        return sample;
    }
}
