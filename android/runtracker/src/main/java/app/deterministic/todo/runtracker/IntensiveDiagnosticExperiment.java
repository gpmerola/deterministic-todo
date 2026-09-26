package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** Stable experiment identity and absolute expiry survive process restarts and app updates. */
final class IntensiveDiagnosticExperiment {
    static final int DURATION_DAYS = 7;
    private static final String PREFS = "movement_intensive_experiment";
    private static final String ID = "experiment_id";
    private static final String STARTED_AT = "started_at_ms";
    private static final String END_AT = "end_at_ms";

    record State(String id, long startedAtMillis, long endAtMillis) {
        boolean active(long nowMillis) { return id != null && endAtMillis > nowMillis; }
    }

    private IntensiveDiagnosticExperiment() {}

    static synchronized State enable(Context context, long nowMillis) {
        State existing = state(context);
        if (existing.active(nowMillis)) return existing;
        State created = new State(UUID.randomUUID().toString(), nowMillis,
            nowMillis + TimeUnit.DAYS.toMillis(DURATION_DAYS));
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(ID, created.id()).putLong(STARTED_AT, created.startedAtMillis())
            .putLong(END_AT, created.endAtMillis()).apply();
        return created;
    }

    static State state(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        return new State(p.getString(ID, null), p.getLong(STARTED_AT, 0),
            p.getLong(END_AT, 0));
    }

    static boolean active(Context context) {
        return state(context).active(System.currentTimeMillis());
    }

    static void disable(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(END_AT).apply();
    }
}
