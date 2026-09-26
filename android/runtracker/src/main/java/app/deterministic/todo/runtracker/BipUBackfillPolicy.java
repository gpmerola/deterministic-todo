package app.deterministic.todo.runtracker;

/** Bounded, overlapping history request so reconnects recover data without gaps. */
final class BipUBackfillPolicy {
    static final long MAX_BACKFILL_MILLIS = 7L * 24 * 60 * 60 * 1000;
    static final long OVERLAP_MILLIS = 60L * 60 * 1000;
    static final long STALE_CURSOR_MILLIS = 12L * 60 * 60 * 1000;

    record Request(long sinceMillis, int requestedHours, boolean historyCapApplied) {}

    private BipUBackfillPolicy() {}

    static Request request(long nowMillis, Long latestStoredMillis) {
        long floor = nowMillis - MAX_BACKFILL_MILLIS;
        long desired;
        if (latestStoredMillis == null) {
            desired = floor;
        } else if (nowMillis - latestStoredMillis > STALE_CURSOR_MILLIS) {
            // Some Bip U responses contain only the beginning of a large range. Do not
            // remain pinned forever to that old overlap: prioritize a bounded recent
            // window so daily movement can catch up on the next automatic attempt.
            desired = nowMillis - STALE_CURSOR_MILLIS;
        } else {
            desired = latestStoredMillis - OVERLAP_MILLIS;
        }
        long since = Math.max(floor, Math.min(nowMillis, desired));
        int hours = (int) Math.max(1, (nowMillis - since + 3_599_999L) / 3_600_000L);
        return new Request(since, hours, desired < floor);
    }
}
