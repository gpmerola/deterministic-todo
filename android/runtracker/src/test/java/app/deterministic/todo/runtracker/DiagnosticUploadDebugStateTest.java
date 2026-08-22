package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class DiagnosticUploadDebugStateTest {
    @Test public void storesOnlyAStableErrorClass() {
        assertEquals("IllegalStateException",
            DiagnosticUploadDebugState.errorCode(new IllegalStateException("private provider text")));
        assertEquals("Unknown", DiagnosticUploadDebugState.errorCode(null));
    }
}
