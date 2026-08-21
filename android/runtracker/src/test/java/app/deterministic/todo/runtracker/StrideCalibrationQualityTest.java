package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class StrideCalibrationQualityTest {
    @Test public void pureRunningSessionIsAccepted() {
        DirectStepTimeline timeline = timeline(8, 75, 0, 0);
        assertTrue(StrideCalibrationQuality.assess("running", timeline, 1_000, 241_000).pure());
    }

    @Test public void mixedRunWalkSessionIsRejectedForRunningCalibration() {
        DirectStepTimeline timeline = timeline(6, 75, 2, 60);
        StrideCalibrationQuality.Assessment quality =
            StrideCalibrationQuality.assess("running", timeline, 1_000, 241_000);
        assertFalse(quality.pure());
        assertTrue(quality.expectedShare() > 0.70 && quality.expectedShare() < 0.80);
    }

    @Test public void pureWalkingSessionIsAccepted() {
        DirectStepTimeline timeline = timeline(0, 0, 8, 60);
        assertTrue(StrideCalibrationQuality.assess("walking", timeline, 1_000, 241_000).pure());
    }

    private static DirectStepTimeline timeline(int runBuckets, long runSteps,
                                               int walkBuckets, long walkSteps) {
        DirectStepTimeline timeline = new DirectStepTimeline();
        long time = 1_000;
        long steps = 0;
        timeline.add(time, steps, "available");
        for (int i = 0; i < runBuckets; i++) {
            time += 30_000; steps += runSteps; timeline.add(time, steps, "available");
        }
        for (int i = 0; i < walkBuckets; i++) {
            time += 30_000; steps += walkSteps; timeline.add(time, steps, "available");
        }
        return timeline;
    }
}
