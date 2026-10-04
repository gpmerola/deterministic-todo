package app.deterministic.todo.deterministic_todo;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Calendar changed (content trigger), retry after a failed upload, or
 * hourly check: see {@link AgendaBackground}. A wake-up whose fingerprint
 * did not change ends after one provider query, without uploading.
 */
public final class AgendaBackgroundJob extends JobService {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();

    @Override
    public boolean onStartJob(JobParameters params) {
        int id = params.getJobId();
        boolean calendar = id == AgendaBackground.CALENDAR_JOB;
        boolean retry = id == AgendaBackground.RETRY_JOB;
        Handler main = new Handler(Looper.getMainLooper());
        IO.execute(() -> {
            String fingerprint =
                AgendaBackground.fingerprint(getApplicationContext(), System.currentTimeMillis());
            boolean changed = fingerprint != null
                && !AgendaBackground.sameFingerprint(getApplicationContext(), fingerprint);
            if ((calendar || retry) && !changed) {
                main.post(() -> finish(params, calendar));
                return;
            }
            // The hourly run also uploads a changed calendar: a failed
            // upload is never left waiting for the next calendar change.
            main.post(() -> AgendaBackground.run(getApplicationContext(),
                changed ? "calendar" : "periodic", outcome -> {
                    if (outcome == AgendaBackground.Outcome.STOP) {
                        jobFinished(params, false);
                        AgendaBackground.cancel(getApplicationContext());
                        return;
                    }
                    if (outcome == AgendaBackground.Outcome.DONE) {
                        if (changed) AgendaBackground.saveFingerprint(getApplicationContext(), fingerprint);
                        AgendaBackground.resetRetries(getApplicationContext());
                    } else if (changed) {
                        AgendaBackground.scheduleRetry(getApplicationContext());
                    }
                    finish(params, calendar);
                }));
        });
        return true;
    }

    private void finish(JobParameters params, boolean calendar) {
        jobFinished(params, false);
        // Content-triggered jobs fire once: re-arm. The hourly job restores
        // it after a reboot, when content triggers are dropped.
        if (calendar || !AgendaBackground.calendarJobPending(getApplicationContext())) {
            AgendaBackground.scheduleCalendarJob(getApplicationContext());
        }
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        // Interrupted (constraints lost): run again later.
        return true;
    }
}
