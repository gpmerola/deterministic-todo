package app.deterministic.todo.runtracker;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.List;

public class LocalStepIntervalReportTest {
    private final MovementProfile profile = new MovementProfile(70, .7, 1.1);
    private LocalStepMinute minute(long at, long steps) {
        var sample = new LocalStepMinute(); sample.startMillis = at; sample.steps = steps; return sample;
    }
    @Test public void partialBoundariesExposeBoundsInsteadOfExactCounts() {
        var rows = LocalStepIntervalReport.build(new LocalStepIntervalReport.Range(90_000, 200_000),
            List.of(minute(60_000, 100), minute(120_000, 100), minute(180_000, 90)), List.of(), profile);
        assertEquals(3, rows.size());
        assertEquals(Long.valueOf(0), rows.get(0).stepsLower());
        assertEquals(Long.valueOf(100), rows.get(0).stepsUpper());
        assertEquals(50, rows.get(0).proratedSteps(), .0001);
        assertEquals(35, rows.get(0).estimatedMeters(), .0001);
        assertEquals(Long.valueOf(100), rows.get(1).stepsLower());
        assertEquals(30, rows.get(2).proratedSteps(), .0001);
    }
    @Test public void missingIsNotZeroAndEndIsExclusive() {
        var rows = LocalStepIntervalReport.build(new LocalStepIntervalReport.Range(60_000, 180_000),
            List.of(minute(60_000, 0), minute(180_000, 999)), List.of(), profile);
        assertEquals(2, rows.size());
        assertEquals(Long.valueOf(0), rows.get(0).stepsUpper());
        assertNull(rows.get(1).sample()); assertNull(rows.get(1).proratedSteps());
        assertNull(rows.get(1).estimatedMeters());
    }
    @Test public void sharesRunningAndExcludedDistanceModel() {
        var rows = LocalStepIntervalReport.build(new LocalStepIntervalReport.Range(0, 120_000),
            List.of(minute(0, 100), minute(60_000, 100)),
            List.of(new ActivityTimeline.Event(0, "running"), new ActivityTimeline.Event(60_000, "vehicle")), profile);
        assertEquals(110, rows.get(0).estimatedMeters(), .0001);
        assertEquals(0, rows.get(1).estimatedMeters(), .0001);
        assertEquals(Long.valueOf(100), rows.get(1).stepsUpper());
    }
    @Test public void rejectsInvalidAndUnboundedRanges() {
        for (long[] range : new long[][]{{0,0}, {2,1}, {-1,100}, {0,3_600_001},
            {Long.MAX_VALUE - 1,Long.MAX_VALUE}}) {
            try { new LocalStepIntervalReport.Range(range[0], range[1]); fail("invalid range"); }
            catch (IllegalArgumentException expected) { }
        }
        assertEquals(0, new LocalStepIntervalReport.Range(1,3_600_001).firstMinute());
    }
}
