package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class DirectStepTimelineTest {
    @Test public void roundTripKeepsStepChangesAndStatuses() {
        DirectStepTimeline timeline = new DirectStepTimeline();
        timeline.add(1_000, 0, "active");
        timeline.add(2_000, 0, "active");
        timeline.add(3_000, 2, "active");
        timeline.add(4_000, 2, "counter_reset");

        var restored = DirectStepTimeline.decode(timeline.encode()).snapshot();
        assertEquals(3, restored.size());
        assertEquals(2, restored.get(1).steps());
        assertEquals("counter_reset", restored.get(2).status());
    }

    @Test public void invalidPersistedRowsAreIgnored() {
        var restored = DirectStepTimeline.decode("bad\n1000,4,active\n-1,5,active\n").snapshot();
        assertEquals(1, restored.size());
        assertEquals(4, restored.get(0).steps());
    }
}
