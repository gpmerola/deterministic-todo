package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import java.util.List;
import org.junit.Test;

public class ActivityTimelineTest {
    @Test public void resolvesMostRecentTransitionAtTimestamp() {
        List<ActivityTimeline.Event> events = List.of(
            new ActivityTimeline.Event(1000, ActivityTimeline.WALKING),
            new ActivityTimeline.Event(2000, ActivityTimeline.RUNNING),
            new ActivityTimeline.Event(3000, ActivityTimeline.VEHICLE));
        assertEquals(ActivityTimeline.UNKNOWN, ActivityTimeline.at(events, 999));
        assertEquals(ActivityTimeline.WALKING, ActivityTimeline.at(events, 1500));
        assertEquals(ActivityTimeline.RUNNING, ActivityTimeline.at(events, 2500));
        assertEquals(ActivityTimeline.VEHICLE, ActivityTimeline.at(events, 3500));
    }
}
