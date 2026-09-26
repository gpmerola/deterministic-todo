package app.deterministic.todo.runtracker;

import org.junit.Test;
import static org.junit.Assert.*;
import java.time.LocalDate;
import java.time.ZoneId;

public class LocalStepImportPolicyTest {
    @Test public void cutoverExcludesThePartiallyObservedMinute() {
        assertEquals(120_000, LocalStepImportPolicy.nextMinute(65_000));
        var w = LocalStepImportPolicy.window(120_000, 0, 180_900);
        assertTrue(LocalStepImportPolicy.valid(120_000, 180_000, 12, w));
        assertFalse(LocalStepImportPolicy.valid(60_000, 120_000, 12, w));
        assertFalse(LocalStepImportPolicy.valid(180_000, 180_900, 1, w));
        assertFalse(LocalStepImportPolicy.valid(120_000, 180_000, -1, w));
    }

    @Test public void replayHasStableKeysAndRecoversDelayedImports() {
        long hour = 3_600_000;
        var first = LocalStepImportPolicy.window(hour, 4 * hour, 8 * hour);
        var replay = LocalStepImportPolicy.window(hour, 4 * hour, 8 * hour + 100);
        assertEquals(first, replay);
        assertEquals(2 * hour, first.start());
        assertEquals(8 * hour, first.end());
    }

    @Test public void recoveryNeverRequestsExpiredData() {
        var w = LocalStepImportPolicy.window(60_000, 120_000, 20 * 86_400_000L);
        assertEquals(LocalStepImportPolicy.LOOKBACK, w.end() - w.start());
    }

    @Test public void civilDaysHave23Or25HoursButUtcKeysRemainUnique() {
        ZoneId zone = ZoneId.of("Europe/Rome");
        for (var entry : new Object[][]{{"2026-03-29", 23}, {"2026-10-25", 25}}) {
            LocalDate day = LocalDate.parse((String) entry[0]);
            long start = day.atStartOfDay(zone).toInstant().toEpochMilli();
            long end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli();
            assertEquals((int) entry[1] * 60, (end - start) / 60_000);
            assertEquals(start, LocalStepImportPolicy.window(start, 0, end).start());
        }
    }
}
