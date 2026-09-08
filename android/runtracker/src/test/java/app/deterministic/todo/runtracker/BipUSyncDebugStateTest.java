package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public final class BipUSyncDebugStateTest {
    @Test public void expectedUnavailableStatesAreSkipped() {
        assertEquals("skipped", BipUSyncDebugState.automaticPhase("bluetooth_disabled"));
        assertEquals("skipped", BipUSyncDebugState.automaticPhase("not_found"));
    }

    @Test public void importedOrEmptyHistoryIsSuccessful() {
        assertEquals("success", BipUSyncDebugState.automaticPhase("activity_sync_success"));
        assertEquals("success", BipUSyncDebugState.automaticPhase("activity_empty"));
    }

    @Test public void ProtocolFailuresRemainErrors() {
        assertEquals("error", BipUSyncDebugState.automaticPhase("authentication_failed"));
    }
}
