package app.deterministic.todo.runtracker;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;

public final class PassiveMinuteTimelineTest {
    @Test public void splitsRecordsAcrossUtcMinutesAndPreservesTotals() {
        long minute = 1_800_000L;
        PassiveMinuteTimeline.Builder builder = new PassiveMinuteTimeline.Builder();
        builder.addSteps(minute + 30_000, minute + 150_000, 120, true,
            List.of(new ActivityTimeline.Event(minute, ActivityTimeline.WALKING)));
        builder.addFitDistance(minute + 30_000, minute + 150_000, 90.0);

        List<PassiveMinuteTimeline.Minute> result = builder.build(120);

        assertEquals(3, result.size());
        assertEquals(30, result.get(0).todoSteps());
        assertEquals(60, result.get(1).todoSteps());
        assertEquals(30, result.get(2).todoSteps());
        assertEquals(120, result.stream().mapToLong(PassiveMinuteTimeline.Minute::todoSteps).sum());
        assertEquals(120, result.stream().mapToLong(PassiveMinuteTimeline.Minute::fitStepsRaw).sum());
        assertEquals(90.0, result.stream().mapToDouble(
            PassiveMinuteTimeline.Minute::fitDistanceMeters).sum(), 0.0001);
    }

    @Test public void reconciliationIsExactAndClassificationSurvives() {
        long minute = 3_600_000L;
        PassiveMinuteTimeline.Builder builder = new PassiveMinuteTimeline.Builder();
        builder.addSteps(minute, minute + 60_000, 51, true,
            List.of(new ActivityTimeline.Event(minute, ActivityTimeline.WALKING)));
        builder.addSteps(minute + 60_000, minute + 120_000, 50, true,
            List.of(new ActivityTimeline.Event(minute, ActivityTimeline.WALKING),
                new ActivityTimeline.Event(minute + 60_000, ActivityTimeline.RUNNING)));

        List<PassiveMinuteTimeline.Minute> result = builder.build(100);

        assertEquals(100, result.stream().mapToLong(PassiveMinuteTimeline.Minute::todoSteps).sum());
        assertEquals(50, result.get(0).walkingSteps());
        assertEquals(50, result.get(1).runningSteps());
        assertEquals(101, result.stream().mapToLong(PassiveMinuteTimeline.Minute::fitStepsRaw).sum());
    }
}
