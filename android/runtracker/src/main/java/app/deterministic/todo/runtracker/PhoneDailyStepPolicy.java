package app.deterministic.todo.runtracker;

/** Attributes only deltas whose two counter samples belong to the same civil day. */
final class PhoneDailyStepPolicy {
    record Update(long steps, long delta, String reason) {}

    private PhoneDailyStepPolicy() {}

    static Update update(long storedSteps, float raw, float lastRaw, boolean sameBoot,
                         boolean sameCivilDay, boolean bootStartedToday,
                         boolean baselineMigrationRequired) {
        if (!Float.isFinite(raw) || raw < 0) {
            throw new IllegalArgumentException("invalid counter");
        }
        long stored = Math.max(0, storedSteps);
        if (baselineMigrationRequired) return new Update(0, 0, "accounting_migration");
        // A first-ever reading can be attributed to today only if this boot began today.
        if (lastRaw < 0) {
            if (bootStartedToday && stored == 0) {
                long delta = (long) Math.floor(raw);
                return new Update(delta, delta, "initial_boot_today");
            }
            return new Update(stored, 0, "initial_baseline");
        }
        // Returning to a previously observed day/zone must preserve its saved subtotal.
        if (!sameCivilDay) return new Update(stored, 0, "civil_boundary_baseline");
        if (!sameBoot) return new Update(stored, 0, "boot_baseline");
        if (raw < lastRaw) return new Update(stored, 0, "counter_reset_baseline");
        long delta = (long) Math.floor(raw - lastRaw);
        return new Update(stored + delta, delta, delta == 0 ? "unchanged" : "counted");
    }
}
