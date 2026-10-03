package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** UI reads only local storage; Recording API import runs independently. */
public final class PhoneDailyMovementGateway {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private PhoneDailyMovementGateway() {}

    public record DailySteps(String day, long steps) {}

    public interface Callback {
        void onSuccess(DailySteps steps);
        void onError();
    }

    /** Phone steps of a civil day; archived Bip U samples are no longer merged. */
    static long stepsForDay(Context context, LocalDate day, ZoneId zone) {
        RunDao dao = RunDatabase.get(context).runs();
        long start = day.atStartOfDay(zone).toInstant().toEpochMilli();
        long end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli();
        LocalStepState state = dao.localStepState();
        if (state == null || end <= state.startMillis) {
            SharedPreferences old = context.getSharedPreferences("phone_daily_steps", Context.MODE_PRIVATE);
            return Math.max(0, old.getLong("steps|" + day + "|" + zone.getId(), 0));
        }
        long steps = dao.localSteps(start, end);
        if (state.legacyDay.equals(day.toString()) && state.legacyZoneId.equals(zone.getId()))
            steps += state.legacySteps;
        return steps;
    }

    public static void refreshToday(Context context, Callback callback) {
        Context app = context.getApplicationContext();
        LocalStepRecording.refreshIfDue(app);
        IO.execute(() -> {
            Handler main = new Handler(Looper.getMainLooper());
            try {
                ZoneId zone = ZoneId.systemDefault();
                LocalDate today = LocalDate.now(zone);
                DailySteps value = new DailySteps(today.toString(), stepsForDay(app, today, zone));
                main.post(() -> callback.onSuccess(value));
            } catch (Exception ignored) { main.post(callback::onError); }
        });
    }
}
