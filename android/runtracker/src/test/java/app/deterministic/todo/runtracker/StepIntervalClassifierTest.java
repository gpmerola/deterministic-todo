package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import java.util.List;
import org.junit.Test;

public class StepIntervalClassifierTest {
    @Test public void splitsStepsAcrossOverlappingWalkingAndRunningStates() {
        List<ActivityTimeline.Event> timeline = List.of(
            new ActivityTimeline.Event(0, ActivityTimeline.WALKING),
            new ActivityTimeline.Event(500, ActivityTimeline.RUNNING));

        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(0, 1000, 101, timeline);

        assertEquals(51, result.walking());
        assertEquals(50, result.running());
        assertEquals(101, result.total());
    }

    @Test public void mixedTransportOverlapFallsBackToUnknownInsteadOfDroppingSteps() {
        List<ActivityTimeline.Event> timeline = List.of(
            new ActivityTimeline.Event(0, ActivityTimeline.WALKING),
            new ActivityTimeline.Event(500, ActivityTimeline.VEHICLE));

        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(0, 1000, 100, timeline);

        assertEquals(50, result.walking());
        assertEquals(50, result.unknown());
        assertEquals(0, result.excluded());
        assertEquals(100, result.total());
    }

    @Test public void excludesStepsWhenTransportDominatesTheWholeRecord() {
        List<ActivityTimeline.Event> timeline = List.of(
            new ActivityTimeline.Event(0, ActivityTimeline.VEHICLE),
            new ActivityTimeline.Event(900, ActivityTimeline.WALKING));

        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(0, 1000, 100, timeline);

        assertEquals(10, result.walking());
        assertEquals(90, result.excluded());
        assertEquals(90, result.vehicle());
        assertEquals(100, result.total());
    }

    @Test public void stepsOverrideStaleStillClassification() {
        List<ActivityTimeline.Event> timeline = List.of(
            new ActivityTimeline.Event(0, ActivityTimeline.STILL));

        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(0, 1000, 100, timeline);

        assertEquals(0, result.excluded());
        assertEquals(100, result.stillConflict());
        assertEquals(100, result.total());
    }

    @Test public void reportsBicycleSeparatelyFromVehicle() {
        List<ActivityTimeline.Event> timeline = List.of(
            new ActivityTimeline.Event(0, ActivityTimeline.BICYCLE));

        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(0, 1000, 100, timeline);

        assertEquals(100, result.bicycle());
        assertEquals(0, result.vehicle());
        assertEquals(100, result.excluded());
    }

    @Test public void zeroDurationRecordIsUnknownAndPreservesCount() {
        StepIntervalClassifier.Result result =
            StepIntervalClassifier.classify(1000, 1000, 7, List.of());

        assertEquals(7, result.unknown());
        assertEquals(7, result.total());
    }
}
