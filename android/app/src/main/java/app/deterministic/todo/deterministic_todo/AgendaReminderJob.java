package app.deterministic.todo.deterministic_todo;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.provider.CalendarContract;
import java.util.concurrent.TimeUnit;

/** Independent of sign-in and connectivity; provider trigger plus daily horizon. */
public final class AgendaReminderJob extends JobService {
    static final int CHANGED = 7310, DAILY = 7311, REFRESH = 7312;
    private static ComponentName component(Context c) { return new ComponentName(c, AgendaReminderJob.class); }
    static void schedule(Context c) {
        JobScheduler jobs = c.getSystemService(JobScheduler.class);
        if (jobs.getPendingJob(CHANGED) == null) content(c);
        if (jobs.getPendingJob(DAILY) == null) jobs.schedule(new JobInfo.Builder(DAILY, component(c))
            .setPeriodic(TimeUnit.DAYS.toMillis(1)).setPersisted(true).build());
    }
    private static void content(Context c) {
        c.getSystemService(JobScheduler.class).schedule(new JobInfo.Builder(CHANGED, component(c))
            .addTriggerContentUri(new JobInfo.TriggerContentUri(CalendarContract.CONTENT_URI,
                JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS))
            .setTriggerContentUpdateDelay(1000).setTriggerContentMaxDelay(5000).build());
    }
    static void refreshSoon(Context c) {
        if (!AgendaReminders.active(c)) return;
        schedule(c);
        c.getSystemService(JobScheduler.class).schedule(new JobInfo.Builder(REFRESH, component(c))
            .setMinimumLatency(1000).build());
    }
    static void cancel(Context c) {
        JobScheduler jobs = c.getSystemService(JobScheduler.class);
        jobs.cancel(CHANGED); jobs.cancel(DAILY); jobs.cancel(REFRESH);
    }
    private static final java.util.concurrent.ExecutorService IO = java.util.concurrent.Executors.newSingleThreadExecutor();
    private final java.util.Set<JobParameters> running = new java.util.HashSet<>();

    @Override public boolean onStartJob(JobParameters params) {
        running.add(params);
        android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
        IO.execute(() -> {
            String fingerprint = AgendaBackground.fingerprint(this, System.currentTimeMillis(), 0, 8);
            boolean unchanged = fingerprint != null && fingerprint.equals(
                AgendaReminders.prefs(this).getString("fingerprint", null));
            main.post(() -> {
                if (!running.contains(params)) return;
                if (params.getJobId() == CHANGED && unchanged) {
                    finish(params, AgendaBackground.Outcome.DONE, fingerprint);
                } else {
                    AgendaBackground.run(getApplicationContext(), "reminders",
                        outcome -> finish(params, outcome, fingerprint));
                }
            });
        });
        return true;
    }

    private void finish(JobParameters params, AgendaBackground.Outcome outcome, String fingerprint) {
        if (!running.remove(params)) return;
        if (outcome == AgendaBackground.Outcome.DONE && fingerprint != null)
            AgendaReminders.prefs(this).edit().putString("fingerprint", fingerprint).apply();
        jobFinished(params, outcome == AgendaBackground.Outcome.RETRY && params.getJobId() != CHANGED);
        if (AgendaReminders.active(this)) {
            if (params.getJobId() == CHANGED) content(this);
            schedule(this);
            if (outcome == AgendaBackground.Outcome.RETRY && params.getJobId() == CHANGED) refreshSoon(this);
        }
    }

    @Override public boolean onStopJob(JobParameters params) {
        running.remove(params);
        return true;
    }
}
