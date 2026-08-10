package app.deterministic.todo.runtracker;

import java.time.LocalDate;
import java.util.concurrent.TimeUnit;

final class PassiveAuditWindow {
    private PassiveAuditWindow() {}

    static long endAt(long startedAtMillis) {
        return startedAtMillis + TimeUnit.DAYS.toMillis(4);
    }

    static boolean active(long nowMillis, long endAtMillis) {
        return endAtMillis > nowMillis;
    }

    static LocalDate completedDay(LocalDate today, int localHour) {
        return today.minusDays(localHour < 6 ? 2 : 1);
    }
}
