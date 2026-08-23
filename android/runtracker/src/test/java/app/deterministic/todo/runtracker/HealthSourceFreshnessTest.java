package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class HealthSourceFreshnessTest {
    private static final long NOW = 10_000_000L;

    @Test public void distinguishesMissingCurrentDelayedAndStale() {
        assertEquals("missing", HealthSourceFreshness.status(null, NOW));
        assertEquals("current", HealthSourceFreshness.status(
            NOW - HealthSourceFreshness.CURRENT_MAX_MS, NOW));
        assertEquals("delayed", HealthSourceFreshness.status(
            NOW - HealthSourceFreshness.CURRENT_MAX_MS - 1, NOW));
        assertEquals("stale", HealthSourceFreshness.status(
            NOW - HealthSourceFreshness.DELAYED_MAX_MS - 1, NOW));
    }

    @Test public void onlyCurrentDataIsFinalForComparison() {
        assertTrue(HealthSourceFreshness.finalEnoughForComparison("current"));
        assertFalse(HealthSourceFreshness.finalEnoughForComparison("delayed"));
        assertFalse(HealthSourceFreshness.finalEnoughForComparison("stale"));
        assertFalse(HealthSourceFreshness.finalEnoughForComparison("missing"));
    }
}
