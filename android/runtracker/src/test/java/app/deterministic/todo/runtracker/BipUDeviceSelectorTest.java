package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BipUDeviceSelectorTest {
    @Test public void acceptsBipUNameRegardlessOfCase() {
        assertTrue(BipUDeviceSelector.matchesName("Amazfit Bip U"));
        assertTrue(BipUDeviceSelector.matchesName("AMAZFIT BIP U PRO"));
    }

    @Test public void rejectsMissingOrDifferentDeviceNames() {
        assertFalse(BipUDeviceSelector.matchesName(null));
        assertFalse(BipUDeviceSelector.matchesName("Galaxy Buds"));
        assertFalse(BipUDeviceSelector.matchesName("Amazfit Bip 5"));
    }
}
