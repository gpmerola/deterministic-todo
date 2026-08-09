package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class AutomaticTestGpxExporterTest {
    @Test public void fileNameIncludesActivityAndStableTimestamp() {
        RunSession session = new RunSession();
        session.activityType = "walk";
        session.startedAtMillis = 1786301338319L;
        assertEquals("movement-test-walk-1786301338319.gpx", AutomaticTestGpxExporter.fileName(session));
    }
}
