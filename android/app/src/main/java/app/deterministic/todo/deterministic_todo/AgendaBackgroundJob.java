package app.deterministic.todo.deterministic_todo;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Calendar changed (content trigger) or hourly check: see
 * {@link AgendaBackground}. A calendar wake-up whose fingerprint did not
 * change ends after one provider query, without starting Dart.
 */
public final class AgendaBackgroundJob extends JobService {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();

    @Override
    public boolean onStartJob(JobParameters params) {
        boolean calendar = params.getJobId() == AgendaBackground.CALENDAR_JOB;
        Handler main = new Handler(Looper.getMainLooper());
        IO.execute(() -> {
            String fingerprint = calendar
                ? AgendaBackground.fingerprint(getApplicationContext(), System.currentTimeMillis())
                : null;
            if (calendar && (fingerprint == null
                    || AgendaBackground.sameFingerprint(getApplicationContext(), fingerprint))) {
                main.post(() -> finish(params, calendar));
                return;
            }
            main.post(() -> AgendaBackground.run(getApplicationContext(),
                calendar ? "calendar" : "periodic", outcome -> {
                    if (outcome == AgendaBackground.Outcome.STOP) {
                        jobFinished(params, false);
                        AgendaBackground.cancel(getApplicationContext());
                        return;
                    }
                    if (outcome == AgendaBackground.Outcome.DONE && calendar) {
                        AgendaBackground.saveFingerprint(getApplicationContext(), fingerprint);
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
