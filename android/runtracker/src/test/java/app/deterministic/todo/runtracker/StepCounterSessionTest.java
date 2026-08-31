package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public final class StepCounterSessionTest {
    @Test public void countsMonotonicHardwareDeltasWithoutDuplicates() {
        StepCounterSession counter = new StepCounterSession();
        assertEquals(0, counter.accept(1000).steps());
        assertEquals(3, counter.accept(1003).steps());
        assertEquals(3, counter.accept(1003).steps());
        assertEquals(8, counter.accept(1008).steps());
    }

    @Test public void resetStartsANewBaselineWithoutNegativeSteps() {
        StepCounterSession counter = new StepCounterSession();
        counter.accept(500);
        counter.accept(510);
        assertEquals("counter_reset", counter.accept(2).status());
        assertEquals(10, counter.accept(2).steps());
        assertEquals(14, counter.accept(6).steps());
    }

    @Test public void rejectsInvalidReadings() {
        StepCounterSession counter = new StepCounterSession();
        assertEquals("invalid", counter.accept(Float.NaN).status());
        assertEquals(0, counter.steps());
    }

    @Test public void resumesPersistedSessionWithoutLosingEarlierSteps() {
        StepCounterSession counter = new StepCounterSession(42);
        assertEquals(42, counter.accept(900).steps());
        assertEquals(45, counter.accept(903).steps());
    }
}
