package app.deterministic.todo.runtracker;

/** Attributes only deltas whose two counter samples belong to the same civil day. */
final class PhoneDailyStepPolicy {
    record Update(long steps, long delta) {}

    private PhoneDailyStepPolicy() {}

    static Update update(long storedSteps, float raw, float lastRaw, boolean sameBoot,
                         boolean sameCivilDay, boolean bootStartedToday,
                         boolean baselineMigrationRequired) {
        if (baselineMigrationRequired || !sameCivilDay) return new Update(0, 0);
        long delta = 0;
        if (sameBoot && lastRaw >= 0 && raw >= lastRaw) {
            delta = (long) Math.floor(raw - lastRaw);
        } else if (lastRaw < 0 && bootStartedToday) {
            delta = (long) Math.floor(raw);
        }
        return new Update(Math.max(0, storedSteps) + Math.max(0, delta), Math.max(0, delta));
    }
}
