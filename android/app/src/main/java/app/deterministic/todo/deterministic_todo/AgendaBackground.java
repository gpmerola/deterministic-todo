package app.deterministic.todo.deterministic_todo;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.ContentUris;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.CalendarContract;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.plugin.common.MethodChannel;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.TimeUnit;

/**
 * Keeps the web Agenda current without polling: one job wakes only when the
 * phone's calendar provider reports a change, another runs about once an
 * hour for edits queued on the web. Both run Dart, preferably in the app's
 * own engine when it is alive (one Supabase session, never two refreshing
 * the same token), otherwise in a short-lived headless engine.
 *
 * Nothing about events is logged; the fingerprint is a one-way hash.
 */
public final class AgendaBackground {
    static final int CALENDAR_JOB = 7301;
    static final int PERIODIC_JOB = 7302;
    static final String CHANNEL = "app.deterministic.todo/agenda_background";
    private static final String PREFS = "agenda_background";
    private static final String FINGERPRINT = "fingerprint";
    private static final long HEADLESS_TIMEOUT_MS = TimeUnit.SECONDS.toMillis(90);
    private static final long DAY_MS = TimeUnit.DAYS.toMillis(1);

    /** Dart result: upload done, try again on the next trigger, or stop. */
    enum Outcome { DONE, RETRY, STOP }

    interface Callback {
        void finished(Outcome outcome);
    }

    private static MethodChannel appChannel;

    private AgendaBackground() {}

    /** The visible app's engine: background runs go there while it lives. */
    static void attachAppEngine(FlutterEngine engine) {
        MethodChannel channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        appChannel = channel;
        engine.addEngineLifecycleListener(new FlutterEngine.EngineLifecycleListener() {
            @Override public void onPreEngineRestart() {}

            @Override public void onEngineWillDestroy() {
                if (appChannel == channel) appChannel = null;
            }
        });
    }

    /**
     * Called by the app once signed in to sync. Content-triggered jobs do
     * not survive a reboot; the persisted hourly job schedules it again.
     */
    static void schedule(Context context) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        if (scheduler == null) return;
        if (scheduler.getPendingJob(CALENDAR_JOB) == null) scheduleCalendarJob(context);
        if (scheduler.getPendingJob(PERIODIC_JOB) == null) {
            scheduler.schedule(new JobInfo.Builder(PERIODIC_JOB, component(context))
                .setPeriodic(TimeUnit.HOURS.toMillis(1), TimeUnit.MINUTES.toMillis(20))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build());
        }
    }

    static void cancel(Context context) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        if (scheduler == null) return;
        scheduler.cancel(CALENDAR_JOB);
        scheduler.cancel(PERIODIC_JOB);
        prefs(context).edit().remove(FINGERPRINT).apply();
    }

    /**
     * One-shot by design: re-armed after every run. Changes are batched for
     * a minute, at most a quarter of an hour.
     */
    static void scheduleCalendarJob(Context context) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        if (scheduler == null) return;
        scheduler.schedule(new JobInfo.Builder(CALENDAR_JOB, component(context))
            .addTriggerContentUri(new JobInfo.TriggerContentUri(CalendarContract.CONTENT_URI,
                JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS))
            .setTriggerContentUpdateDelay(TimeUnit.MINUTES.toMillis(1))
            .setTriggerContentMaxDelay(TimeUnit.MINUTES.toMillis(15))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .build());
    }

    static boolean calendarJobPending(Context context) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        return scheduler != null && scheduler.getPendingJob(CALENDAR_JOB) != null;
    }

    private static ComponentName component(Context context) {
        return new ComponentName(context, AgendaBackgroundJob.class);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /**
     * Hash of what the mirror is built from (the same window), so provider
     * notifications without a real change (sync bookkeeping) cost one query
     * and no Dart. Null when the calendar cannot be read.
     */
    static String fingerprint(Context context, long now) {
        Uri.Builder uri = CalendarContract.Instances.CONTENT_URI.buildUpon();
        ContentUris.appendId(uri, now - 31 * DAY_MS);
        ContentUris.appendId(uri, now + 92 * DAY_MS);
        String[] projection = {
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.STATUS,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS,
            CalendarContract.Instances.EVENT_TIMEZONE,
        };
        try (Cursor cursor = context.getContentResolver().query(uri.build(), projection, null, null,
                CalendarContract.Instances.BEGIN + " ASC, " + CalendarContract.Instances.EVENT_ID + " ASC")) {
            if (cursor == null) return null;
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            while (cursor.moveToNext()) {
                for (int i = 0; i < projection.length; i++) {
                    String value = cursor.isNull(i) ? "\u0000" : cursor.getString(i);
                    digest.update(value.getBytes(StandardCharsets.UTF_8));
                    digest.update((byte) 0x1f);
                }
                digest.update((byte) 0x1e);
            }
            // The window moves daily: a new day is a change too.
            digest.update(Long.toString(now / DAY_MS).getBytes(StandardCharsets.UTF_8));
            return hex(digest.digest());
        } catch (SecurityException denied) {
            return null;
        } catch (Exception failed) {
            return null;
        }
    }

    static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) out.append(String.format("%02x", b));
        return out.toString();
    }

    static boolean sameFingerprint(Context context, String fingerprint) {
        return fingerprint != null && fingerprint.equals(prefs(context).getString(FINGERPRINT, null));
    }

    static void saveFingerprint(Context context, String fingerprint) {
        if (fingerprint != null) prefs(context).edit().putString(FINGERPRINT, fingerprint).apply();
    }

    /** Runs the Dart side with [reason] ("calendar" or "periodic"). Main thread. */
    static void run(Context context, String reason, Callback callback) {
        MethodChannel channel = appChannel;
        if (channel != null) {
            channel.invokeMethod("run", reason, resultTo(callback));
            return;
        }
        runHeadless(context.getApplicationContext(), reason, callback);
    }

    private static void runHeadless(Context app, String reason, Callback callback) {
        Handler main = new Handler(Looper.getMainLooper());
        FlutterLoader loader = FlutterInjector.instance().flutterLoader();
        loader.startInitialization(app);
        loader.ensureInitializationCompleteAsync(app, null, main, () -> {
            FlutterEngine engine = new FlutterEngine(app);
            AgendaChannel.registerHandlers(app, engine);
            final boolean[] finished = {false};
            Callback once = outcome -> {
                if (finished[0]) return;
                finished[0] = true;
                main.removeCallbacksAndMessages(engine);
                engine.destroy();
                callback.finished(outcome);
            };
            main.postAtTime(() -> once.finished(Outcome.RETRY), engine,
                android.os.SystemClock.uptimeMillis() + HEADLESS_TIMEOUT_MS);
            MethodChannel channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
            channel.setMethodCallHandler((call, result) -> {
                if (!call.method.equals("ready")) {
                    result.notImplemented();
                    return;
                }
                result.success(null);
                channel.invokeMethod("run", reason, resultTo(once));
            });
            engine.getDartExecutor().executeDartEntrypoint(
                new DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "agendaBackgroundMain"));
        });
    }

    private static MethodChannel.Result resultTo(Callback callback) {
        return new MethodChannel.Result() {
            @Override public void success(Object value) {
                callback.finished(parse(value));
            }

            @Override public void error(String code, String message, Object details) {
                callback.finished(Outcome.RETRY);
            }

            @Override public void notImplemented() {
                // The app is up but not signed in to sync yet.
                callback.finished(Outcome.RETRY);
            }
        };
    }

    static Outcome parse(Object value) {
        if ("done".equals(value)) return Outcome.DONE;
        if ("stop".equals(value)) return Outcome.STOP;
        return Outcome.RETRY;
    }
}
