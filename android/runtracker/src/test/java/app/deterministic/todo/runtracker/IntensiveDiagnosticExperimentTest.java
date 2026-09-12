package app.deterministic.todo.runtracker;

import org.junit.Test;

import java.util.concurrent.TimeUnit;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class IntensiveDiagnosticExperimentTest {
    @Test public void absoluteExpiryDoesNotDependOnBuildOrRestart() {
        long start = 10_000;
        IntensiveDiagnosticExperiment.State state = new IntensiveDiagnosticExperiment.State(
            "stable-id", start, start + TimeUnit.DAYS.toMillis(7));
        assertTrue(state.active(start + TimeUnit.DAYS.toMillis(6)));
        assertFalse(state.active(start + TimeUnit.DAYS.toMillis(7)));
    }
}
