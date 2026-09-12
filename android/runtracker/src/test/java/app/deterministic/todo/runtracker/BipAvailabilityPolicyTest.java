package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class BipAvailabilityPolicyTest {
    @Test public void distinguishesMissingStaleAndCurrentSamples() {
        long now = 10L * 60 * 60 * 1000;
        assertEquals("no_samples_in_measurement_window", BipAvailabilityPolicy.status(null, now));
        assertEquals("local_samples_stale", BipAvailabilityPolicy.status(1L, now));
        assertEquals("local_samples_current", BipAvailabilityPolicy.status(now - 60_000, now));
        assertEquals("explicit_watch_import_required",
            BipAvailabilityPolicy.recoveryAction("local_samples_stale"));
    }
}
