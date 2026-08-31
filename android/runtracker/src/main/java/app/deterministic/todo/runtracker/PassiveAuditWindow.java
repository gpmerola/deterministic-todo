package app.deterministic.todo.runtracker;

import java.time.LocalDate;
import java.util.concurrent.TimeUnit;

final class PassiveAuditWindow {
    static final int DURATION_DAYS = 7;

    private PassiveAuditWindow() {}

    static long endAt(long startedAtMillis) {
        return startedAtMillis + TimeUnit.DAYS.toMillis(DURATION_DAYS);
    }

    static boolean active(long nowMillis, long endAtMillis) {
        return endAtMillis > nowMillis;
    }

    static LocalDate completedDay(LocalDate today, int localHour) {
        return today.minusDays(localHour < 6 ? 2 : 1);
    }
}
