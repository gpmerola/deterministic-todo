package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public final class BipUAutomaticSyncWorkerTest {
    @Test public void automaticCadenceIsThreeHours() {
        assertEquals(3, BipUAutomaticSyncWorker.PERIOD_HOURS);
    }

    @Test public void foregroundRefreshIsRateLimited() {
        assertEquals(15L * 60 * 1000, BipUAutomaticSyncWorker.FOREGROUND_MIN_INTERVAL_MS);
    }
}
