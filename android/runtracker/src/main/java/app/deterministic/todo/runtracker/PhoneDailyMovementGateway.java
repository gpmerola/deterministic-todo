package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Map;
import java.util.ArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** UI reads only local storage; Recording API import runs independently. */
public final class PhoneDailyMovementGateway {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private PhoneDailyMovementGateway() {}

    public interface Callback {
        void onSuccess(DailyMovement movement, long phoneSteps, long bipSteps, String fusionSource);
        void onPermissionRequired();
        void onUnavailable();
        void onError();
    }

    public record DailyTotals(long phoneSteps, long bipSteps, long fusedSteps,
                              String fusionSource, boolean phoneObserved) {}

    static Map<String, Object> diagnosticValues(Context context) {
        return LocalStepRecording.diagnostics(context);
    }

    public static DailyTotals totalsForDay(Context context, LocalDate day, ZoneId zone) {
        RunDao dao = RunDatabase.get(context).runs();
        long start = day.atStartOfDay(zone).toInstant().toEpochMilli();
        long end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli();
        LocalStepState state = dao.localStepState();
        SharedPreferences old = context.getSharedPreferences("phone_daily_steps", Context.MODE_PRIVATE);
        String key = "steps|" + day + "|" + zone.getId();
        long phone;
        boolean observed;
        if (state == null || end <= state.startMillis) {
            phone = Math.max(0, old.getLong(key, 0));
            observed = old.contains(key);
        } else {
            phone = dao.localSteps(start, end);
            if (state.legacyDay.equals(day.toString()) && state.legacyZoneId.equals(zone.getId()))
                phone += state.legacySteps;
            observed = state.importedThroughMillis > Math.max(start, state.startMillis);
        }
        long bip = Math.max(0, dao.bipUSteps(start, end));
        DailyMovementFusion.Result fused = DailyMovementFusion.combine(phone, bip);
        String source = bip > phone ? fused.source()
            : state == null ? "legacy_phone_counter" : "local_recording_api";
        return new DailyTotals(phone, bip, fused.steps(), source, observed);
    }

    private record Snapshot(DailyMovement row, DailyTotals totals) {}

    public static void refreshToday(Context context, Callback callback) {
        Context app = context.getApplicationContext();
        LocalStepRecording.refreshIfDue(app);
        IO.execute(() -> {
            Handler main = new Handler(Looper.getMainLooper());
            try {
                ZoneId zone = ZoneId.systemDefault();
                Snapshot snapshot = RunDatabase.get(app).runInTransaction(
                    () -> calculateDay(app, LocalDate.now(zone), zone));
                main.post(() -> callback.onSuccess(snapshot.row(), snapshot.totals().phoneSteps(),
                    snapshot.totals().bipSteps(), snapshot.totals().fusionSource()));
            } catch (Exception ignored) { main.post(callback::onError); }
        });
    }

    public static DailyMovement readDay(Context context, LocalDate day, ZoneId zone) {
        return RunDatabase.get(context).runInTransaction(() -> calculateDay(context, day, zone).row());
    }

    private static Snapshot calculateDay(Context app, LocalDate day, ZoneId zone) {
        DailyTotals totals = totalsForDay(app, day, zone);
        MovementProfile profile = MovementProfile.read(app);
        RunDao dao = RunDatabase.get(app).runs();
        LocalStepState state = dao.localStepState();
        long start = day.atStartOfDay(zone).toInstant().toEpochMilli();
        long end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli();
        var gps = new ArrayList<LocalDailyMovementModel.GpsSegment>();
        LocalDailyMovementModel.Result estimate;
        if (state != null && end > state.startMillis && totals.phoneSteps() >= totals.bipSteps()) {
            long cutover = Math.max(start, state.startMillis);
            for (var session : dao.sessionsForDay(cutover, end)) {
                TrackPoint previous = null;
                for (var point : dao.acceptedPointsForDay(session.id, cutover, end)) {
                    if (previous != null) gps.add(new LocalDailyMovementModel.GpsSegment(
                        previous.timestampMillis, point.timestampMillis,
                        point.accumulatedDistanceMeters - previous.accumulatedDistanceMeters,
                        session.activityType));
                    previous = point;
                }
            }
            long legacy = state.legacyDay.equals(day.toString())
                && state.legacyZoneId.equals(zone.getId()) ? state.legacySteps : 0;
            estimate = LocalDailyMovementModel.calculate(dao.localStepMinutes(start, end),
                ActivityTimeline.read(app), gps, cutover, end, legacy, profile);
        } else {
            var fallback = MovementEstimate.fromSteps(totals.fusedSteps(),
                profile.walkingStride(), profile.weightKg());
            estimate = new LocalDailyMovementModel.Result(fallback.distanceMeters(),
                fallback.activeCalories(), 0, 0, 0, totals.fusedSteps());
        }
        DailyMovement row = new DailyMovement();
        row.day = day.toString();
        row.zoneId = zone.getId();
        row.source = totals.fusionSource();
        row.steps = totals.fusedSteps();
        row.estimatedDistanceMeters = estimate.meters();
        row.estimatedActiveCalories = estimate.activeCalories();
        row.modelVersion = 1;
        row.weightKg = profile.weightKg();
        row.walkingStrideMeters = profile.walkingStride();
        row.runningStrideMeters = profile.runningStride();
        row.updatedAtMillis = System.currentTimeMillis();
        RunDatabase.get(app).runs().upsertDailyMovement(row);
        return new Snapshot(row, totals);
    }
}
