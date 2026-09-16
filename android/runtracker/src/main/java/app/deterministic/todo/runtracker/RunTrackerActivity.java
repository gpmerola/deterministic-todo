package app.deterministic.todo.runtracker;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.work.WorkInfo;
import androidx.work.WorkManager;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RunTrackerActivity extends ComponentActivity {
    private static final int DRIVE_FOLDER_REQUEST = 7410;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler clock = new Handler(Looper.getMainLooper());
    private TextView durationView;
    private TextView distanceView;
    private TextView paceView;
    private TextView sessionStepsView;
    private TextView accuracyView;
    private TextView dailyStepsView;
    private TextView dailyDistanceView;
    private TextView dailyCaloriesView;
    private TextView movementStatusView;
    private Button healthPermissionButton;
    private Button primaryButton;
    private Button secondaryButton;
    private Button driveButton;
    private TextView driveStatusView;
    private TextView comparisonView;
    private TextView passiveStatusView;
    private Button passiveButton;
    private TextView intensiveStatusView;
    private TextView automaticStatusView;
    private DailyStepGoalView dailyGoalView;
    private Button intensiveButton;
    private LinearLayout advancedTools;
    private String pendingActivityType = "run";
    private long sessionId;
    private long startedAt;
    private double distance;
    private long sessionSteps;
    private boolean pendingIntensiveDiagnostic;

    private final ActivityResultLauncher<Set<String>> healthPermissions = registerForActivityResult(
        HealthConnectGateway.permissionContract(), granted -> {
            refreshDailyMovement();
            compareLatestWithGoogleFit();
            retryLatestComparison();
        }
    );

    private void retryLatestComparison() {
        io.execute(() -> {
            java.util.List<RunSession> sessions = RunDatabase.get(this).runs().sessions();
            if (!sessions.isEmpty() && sessions.get(0).endedAtMillis != null)
                MovementComparisonWorker.schedule(this, sessions.get(0).id);
        });
    }

    private final BroadcastReceiver stateReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            long receivedSessionId = intent.getLongExtra(RunRecordingService.EXTRA_SESSION_ID, 0);
            sessionId = receivedSessionId;
            startedAt = intent.getLongExtra("started_at", 0);
            distance = intent.getDoubleExtra(RunRecordingService.EXTRA_DISTANCE, 0);
            float accuracy = intent.getFloatExtra(RunRecordingService.EXTRA_ACCURACY, 0);
            String gpsStatus = intent.getStringExtra(RunRecordingService.EXTRA_STATUS);
            String activityType = intent.getStringExtra(RunRecordingService.EXTRA_ACTIVITY_TYPE);
            sessionSteps = intent.getLongExtra(RunRecordingService.EXTRA_SESSION_STEPS, 0);
            String stepStatus = intent.getStringExtra(RunRecordingService.EXTRA_STEP_STATUS);
            accuracyView.setText(
                gpsStatus == null
                    ? (accuracy <= 0 ? "Ricerca del segnale GPS…" : String.format(Locale.ROOT, "Accuratezza ± %.0f m", accuracy))
                    : (accuracy <= 0 ? gpsStatus : gpsStatus + String.format(Locale.ROOT, " · ± %.0f m", accuracy))
            );
            primaryButton.setText(sessionId == 0 ? "Avvia camminata" : "Termina attività");
            primaryButton.setEnabled(true);
            secondaryButton.setEnabled(sessionId == 0);
            driveStatusView.setText(DriveTestExportManager.status(RunTrackerActivity.this));
            sessionStepsView.setText(String.format(Locale.ITALY, "%,d", sessionSteps));
            sessionStepsView.setContentDescription("Passi sessione dal sensore telefono · " + stepStatus);
            renderClock();
        }
    };

    private final ActivityResultLauncher<String[]> permissions = registerForActivityResult(
        new ActivityResultContracts.RequestMultiplePermissions(), result -> {
            ActivityClassifier.register(this);
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED) {
                if (pendingIntensiveDiagnostic) startIntensiveDiagnostic();
                else startRun(pendingActivityType);
            }
            else Toast.makeText(this, "La posizione precisa è necessaria per registrare il percorso", Toast.LENGTH_LONG).show();
            pendingIntensiveDiagnostic = false;
        }
    );

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        ActivityClassifier.register(this);
        StrideCalibrator.ensureQualitySchema(this);
        setTitle("Movimento");
        setContentView(content());
        io.execute(() -> {
            RunSession active = RunDatabase.get(this).runs().activeSession();
            if (active != null) runOnUiThread(() -> {
                sessionId = active.id;
                startedAt = active.startedAtMillis;
                distance = active.distanceMeters;
                primaryButton.setText("Termina attività");
                secondaryButton.setEnabled(false);
                renderClock();
            });
        });
        clock.post(clockTick);
        refreshDailyMovement();
        io.execute(() -> {
            java.util.List<RunSession> sessions = RunDatabase.get(this).runs().sessions();
            if (sessions.isEmpty()) return;
            String latestStatus = DriveTestExportManager.comparisonStatus(this, sessions.get(0).id);
            if (MovementComparisonRetryPolicy.needsForegroundRecovery(latestStatus))
                runOnUiThread(() -> clock.postDelayed(this::compareLatestWithGoogleFit, 750));
        });
    }

    private View content() {
        int pad = dp(14);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        LinearLayout dailyCard = sectionCard();
        dailyCard.addView(sectionTitle("OGGI"), matchWrap(0));
        LinearLayout dailyOverview = new LinearLayout(this);
        dailyOverview.setOrientation(LinearLayout.HORIZONTAL);
        dailyOverview.setGravity(Gravity.CENTER_VERTICAL);
        dailyGoalView = new DailyStepGoalView(this);
        dailyOverview.addView(dailyGoalView, new LinearLayout.LayoutParams(dp(76), dp(76)));
        LinearLayout dailyMetrics = new LinearLayout(this);
        dailyMetrics.setOrientation(LinearLayout.HORIZONTAL);
        dailyStepsView = metric("—", 20);
        dailyDistanceView = metric("— km", 20);
        dailyCaloriesView = metric("— kcal", 20);
        dailyMetrics.addView(metricBlock("PASSI", dailyStepsView), weighted());
        dailyMetrics.addView(metricBlock("DISTANZA", dailyDistanceView), weighted());
        dailyMetrics.addView(metricBlock("CALORIE", dailyCaloriesView), weighted());
        dailyOverview.addView(dailyMetrics, weighted());
        dailyCard.addView(dailyOverview, matchWrap(dp(6)));
        movementStatusView = centeredLabel("Health Connect…", 12);
        dailyCard.addView(movementStatusView, matchWrap(dp(4)));
        healthPermissionButton = new Button(this);
        healthPermissionButton.setText("Consenti Health Connect");
        healthPermissionButton.setOnClickListener(v ->
            healthPermissions.launch(HealthConnectGateway.permissions(this)));
        healthPermissionButton.setVisibility(View.GONE);
        dailyCard.addView(healthPermissionButton, matchWrap(dp(6)));
        root.addView(dailyCard, matchWrap(0));

        LinearLayout sessionCard = sectionCard();
        sessionCard.addView(sectionTitle("REGISTRA"), matchWrap(0));
        durationView = metric("00:00:00", 31);
        sessionCard.addView(durationView, matchWrap(dp(2)));
        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.HORIZONTAL);
        distanceView = metric("0,00 km", 19);
        sessionStepsView = metric("0", 19);
        paceView = metric("— /km", 19);
        metrics.addView(metricBlock("DISTANZA", distanceView), weighted());
        metrics.addView(metricBlock("PASSI", sessionStepsView), weighted());
        metrics.addView(metricBlock("PASSO", paceView), weighted());
        sessionCard.addView(metrics, matchWrap(dp(4)));
        accuracyView = centeredLabel("Pronto · GPS spento", 13);
        sessionCard.addView(accuracyView, matchWrap(dp(6)));
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        primaryButton = new Button(this);
        primaryButton.setText("Camminata");
        primaryButton.setOnClickListener(v -> {
            if (sessionId == 0) ensurePermissions("walk"); else stopRun();
        });
        actions.addView(primaryButton, weighted());
        secondaryButton = new Button(this);
        secondaryButton.setText("Corsa");
        secondaryButton.setOnClickListener(v -> ensurePermissions("run"));
        actions.addView(secondaryButton, weighted());
        sessionCard.addView(actions, matchWrap(dp(6)));
        root.addView(sessionCard, matchWrap(dp(10)));

        LinearLayout automationCard = sectionCard();
        automationCard.addView(sectionTitle("RACCOLTA DATI"), matchWrap(0));
        automaticStatusView = centeredLabel(automaticStatus(), 13);
        automationCard.addView(automaticStatusView, matchWrap(dp(5)));
        comparisonView = centeredLabel("Confronto automatico pronto", 13);
        driveStatusView = centeredLabel(DriveTestExportManager.status(this), 13);
        Button uploadAll = new Button(this);
        uploadAll.setText("Carica tutti i dati ora");
        uploadAll.setOnClickListener(v -> startCompleteUpload(uploadAll));
        automationCard.addView(uploadAll, matchWrap(dp(6)));
        root.addView(automationCard, matchWrap(dp(10)));

        passiveStatusView = centeredLabel(passiveStatus(), 13);
        passiveButton = new Button(this);
        renderPassiveButton();
        passiveButton.setOnClickListener(v -> {
            if (PassiveMovementAuditWorker.enabled(this)) PassiveMovementAuditWorker.disable(this);
            else if (!DriveTestExportManager.isConfigured(this)) {
                Toast.makeText(this, "Collega prima la cartella Drive", Toast.LENGTH_LONG).show();
                return;
            } else PassiveMovementAuditWorker.enable(this);
            renderPassiveButton();
            passiveStatusView.setText(passiveStatus());
            renderAutomaticStatus();
        });
        intensiveStatusView = centeredLabel(intensiveStatus(), 13);
        intensiveButton = new Button(this);
        renderIntensiveButton();
        intensiveButton.setOnClickListener(v -> {
            if (IntensiveDiagnosticExperiment.active(this)) {
                IntensiveDiagnosticScheduler.disable(this);
                renderIntensiveState();
            } else if (!DriveTestExportManager.isConfigured(this)) {
                Toast.makeText(this, "Collega prima la cartella Drive", Toast.LENGTH_LONG).show();
            } else ensureIntensivePermissions();
        });

        Button advancedToggle = new Button(this);
        advancedToggle.setText("Dettagli e strumenti");
        root.addView(advancedToggle, matchWrap(dp(8)));
        advancedTools = sectionCard();
        advancedTools.setVisibility(View.GONE);
        root.addView(advancedTools, matchWrap(dp(4)));
        advancedToggle.setOnClickListener(v -> {
            boolean show = advancedTools.getVisibility() != View.VISIBLE;
            advancedTools.setVisibility(show ? View.VISIBLE : View.GONE);
            advancedToggle.setText(show ? "Nascondi dettagli" : "Dettagli e strumenti");
        });
        TextView adbStatus = centeredLabel(PassiveMovementDebugState.uiSummary(this), 12);
        advancedTools.addView(adbStatus, matchWrap(0));
        advancedTools.addView(comparisonView, matchWrap(dp(8)));
        advancedTools.addView(driveStatusView, matchWrap(dp(6)));
        advancedTools.addView(passiveStatusView, matchWrap(dp(8)));
        advancedTools.addView(passiveButton, matchWrap(dp(4)));
        advancedTools.addView(intensiveStatusView, matchWrap(dp(8)));
        advancedTools.addView(intensiveButton, matchWrap(dp(4)));
        driveButton = new Button(this);
        driveButton.setText(DriveTestExportManager.isConfigured(this)
            ? "Cambia cartella Drive" : "Collega cartella Drive");
        driveButton.setOnClickListener(v -> {
            Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                    | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
            startActivityForResult(picker, DRIVE_FOLDER_REQUEST);
        });
        advancedTools.addView(driveButton, matchWrap(dp(8)));
        Button retryDrive = new Button(this);
        retryDrive.setText("Riesporta ultima sessione");
        retryDrive.setOnClickListener(v -> retryLatestPackage());
        advancedTools.addView(retryDrive, matchWrap(dp(4)));
        Button export = new Button(this);
        export.setText("Condividi ultimo GPX");
        export.setOnClickListener(v -> exportLatest());
        advancedTools.addView(export, matchWrap(dp(4)));
        Button watch = new Button(this);
        watch.setText("Bip U");
        watch.setOnClickListener(v -> BipUBleActivity.open(this));
        advancedTools.addView(watch, matchWrap(dp(4)));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
        TextView toolbar = label("Movimento", 22);
        toolbar.setTextColor(Color.WHITE);
        toolbar.setBackgroundColor(Color.rgb(32, 33, 36));
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(16), dp(10), dp(16), dp(10));
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setBackgroundColor(Color.rgb(247, 245, 250));
        shell.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        ViewCompat.setOnApplyWindowInsetsListener(shell, (view, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            toolbar.setPadding(dp(16), bars.top + dp(10), dp(16), dp(10));
            scroll.setPadding(0, 0, 0, bars.bottom);
            return insets;
        });
        return shell;
    }

    private String passiveStatus() {
        if (!PassiveMovementAuditWorker.enabled(this))
            return "Test passivo spento · nessun GPS continuo";
        long hours = Math.max(1, java.util.concurrent.TimeUnit.MILLISECONDS.toHours(
            PassiveMovementAuditWorker.endAt(this) - System.currentTimeMillis()));
        return "Test passivo attivo · snapshot ogni ora · ancora " + hours + " h";
    }

    private String automaticStatus() {
        boolean passive = PassiveMovementAuditWorker.enabled(this);
        boolean intensive = IntensiveDiagnosticExperiment.active(this);
        if (passive && intensive) return "Passivo e diagnostica intensiva attivi";
        if (passive) return "Monitor passivo attivo";
        if (intensive) return "Diagnostica intensiva attiva";
        return "Monitor automatici spenti";
    }

    private void renderAutomaticStatus() {
        if (automaticStatusView != null) automaticStatusView.setText(automaticStatus());
    }

    private void startCompleteUpload(Button button) {
        if (!DriveTestExportManager.isConfigured(this)) {
            Toast.makeText(this, "Collega prima la cartella Drive", Toast.LENGTH_LONG).show();
            return;
        }
        button.setEnabled(false);
        button.setText("Caricamento…");
        java.util.UUID finalWork = ManualDiagnosticExportScheduler.enqueue(this);
        WorkManager.getInstance(this).getWorkInfoByIdLiveData(finalWork).observe(
            this, info -> {
                if (info == null || !info.getState().isFinished()) return;
                button.setEnabled(true);
                if (info.getState() == WorkInfo.State.SUCCEEDED) {
                    button.setText("Carica tutti i dati ora");
                    driveStatusView.setText("Upload completo riuscito");
                    Toast.makeText(this, "Dati disponibili caricati su Drive",
                        Toast.LENGTH_LONG).show();
                } else {
                    button.setText("Riprova caricamento");
                    driveStatusView.setText("Upload non completato");
                }
            });
    }

    private void renderPassiveButton() {
        passiveButton.setText(PassiveMovementAuditWorker.enabled(this)
            ? "Termina test passivo" : "Avvia test passivo · 7 giorni");
    }

    private String intensiveStatus() {
        IntensiveDiagnosticExperiment.State state = IntensiveDiagnosticExperiment.state(this);
        if (!state.active(System.currentTimeMillis()))
            return "Diagnostica intensiva spenta · consumo normale";
        long hours = Math.max(1, java.util.concurrent.TimeUnit.MILLISECONDS.toHours(
            state.endAtMillis() - System.currentTimeMillis()));
        android.content.SharedPreferences p = getSharedPreferences(
            "movement_intensive_status", MODE_PRIVATE);
        String service = p.getString("status", "avvio");
        return "Diagnostica intensiva attiva · GPS e sensori continui · ancora "
            + hours + " h · " + service;
    }

    private void renderIntensiveButton() {
        intensiveButton.setText(IntensiveDiagnosticExperiment.active(this)
            ? "Termina diagnostica intensiva" : "Avvia diagnostica intensiva · 7 giorni");
    }

    private void renderIntensiveState() {
        renderIntensiveButton();
        intensiveStatusView.setText(intensiveStatus());
        renderAutomaticStatus();
    }

    private void refreshDailyMovement() {
        PhoneDailyMovementGateway.refreshToday(this, new PhoneDailyMovementGateway.Callback() {
            @Override public void onSuccess(DailyMovement movement, long phoneSteps,
                                            long bipSteps, String fusionSource) {
                dailyStepsView.setText(String.format(Locale.ITALY, "%,d", movement.steps));
                dailyDistanceView.setText(String.format(Locale.ITALY, "%.2f km", movement.estimatedDistanceMeters / 1000));
                dailyCaloriesView.setText(String.format(Locale.ITALY, "%.0f kcal", movement.estimatedActiveCalories));
                int goal = getSharedPreferences("movement_profile", MODE_PRIVATE).getInt(
                    "daily_step_goal", DailyStepGoalPolicy.DEFAULT_GOAL);
                dailyGoalView.setProgress(movement.steps, goal);
                movementStatusView.setText("Aggiornato ora · telefono/Amazfit");
                healthPermissionButton.setVisibility(View.GONE);
            }

            @Override public void onPermissionRequired() {
                movementStatusView.setText("Autorizza il riconoscimento attività per leggere il contatore del telefono");
                healthPermissionButton.setVisibility(View.VISIBLE);
            }

            @Override public void onUnavailable() {
                movementStatusView.setText("Contatore passi hardware non disponibile su questo dispositivo");
                healthPermissionButton.setVisibility(View.GONE);
            }

            @Override public void onError() {
                movementStatusView.setText("Impossibile aggiornare i passi; riproveremo alla prossima apertura");
            }
        });
    }

    private void ensurePermissions(String activityType) {
        pendingIntensiveDiagnostic = false;
        pendingActivityType = activityType;
        ArrayList<String> required = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.POST_NOTIFICATIONS);
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACTIVITY_RECOGNITION);
        if (required.isEmpty()) startRun(activityType); else permissions.launch(required.toArray(new String[0]));
    }

    private void ensureIntensivePermissions() {
        pendingIntensiveDiagnostic = true;
        ArrayList<String> required = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.POST_NOTIFICATIONS);
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACTIVITY_RECOGNITION);
        if (required.isEmpty()) { pendingIntensiveDiagnostic = false; startIntensiveDiagnostic(); }
        else permissions.launch(required.toArray(new String[0]));
    }

    private void startIntensiveDiagnostic() {
        IntensiveDiagnosticScheduler.enable(this);
        PassiveMovementAuditWorker.ensureEnabledUntil(this,
            IntensiveDiagnosticExperiment.state(this).endAtMillis());
        renderIntensiveState();
        Toast.makeText(this, "Diagnostica intensiva avviata: consumo batteria elevato per 7 giorni",
            Toast.LENGTH_LONG).show();
    }

    private void startRun(String activityType) {
        ContextCompat.startForegroundService(this, new Intent(this, RunRecordingService.class)
            .setAction(RunRecordingService.ACTION_START)
            .putExtra(RunRecordingService.EXTRA_ACTIVITY_TYPE, activityType));
    }

    private void stopRun() {
        startService(new Intent(this, RunRecordingService.class).setAction(RunRecordingService.ACTION_STOP));
        sessionId = 0;
        primaryButton.setText("Salvataggio in corso…");
        primaryButton.setEnabled(false);
        secondaryButton.setEnabled(false);
    }

    private void exportLatest() {
        io.execute(() -> {
            try {
                RunDao dao = RunDatabase.get(this).runs();
                java.util.List<RunSession> sessions = dao.sessions();
                if (sessions.isEmpty()) { runOnUiThread(() -> Toast.makeText(this, "Nessuna corsa da esportare", Toast.LENGTH_SHORT).show()); return; }
                RunSession latest = sessions.get(0);
                String gpx = GpxExporter.export(latest, dao.points(latest.id));
                File dir = new File(getCacheDir(), "runtracker");
                if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("Impossibile creare la cartella GPX");
                File file = new File(dir, latest.activityType + "-" + latest.startedAtMillis + ".gpx");
                try (FileOutputStream output = new FileOutputStream(file)) {
                    output.write(gpx.getBytes(StandardCharsets.UTF_8));
                }
                Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".runtracker.files", file);
                Intent share = new Intent(Intent.ACTION_SEND).setType("application/gpx+xml")
                    .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                runOnUiThread(() -> startActivity(Intent.createChooser(share, "Esporta GPX")));
            } catch (Exception error) {
                runOnUiThread(() -> Toast.makeText(this, "Esportazione non riuscita", Toast.LENGTH_LONG).show());
            }
        });
    }

    private void retryLatestPackage() {
        driveStatusView.setText("Sincronizzazione pacchetto in corso…");
        io.execute(() -> {
            RunDao dao = RunDatabase.get(this).runs();
            java.util.List<RunSession> sessions = dao.sessions();
            if (sessions.isEmpty()) {
                runOnUiThread(() -> driveStatusView.setText("Nessuna attività da esportare"));
                return;
            }
            RunSession latest = sessions.get(0);
            DriveTestExportManager.finish(this, latest, dao.points(latest.id), result -> runOnUiThread(() -> {
                driveStatusView.setText(DriveTestExportManager.status(this));
                if (result.success()) MovementComparisonWorker.schedule(this, latest.id);
                Toast.makeText(this,
                    result.success()
                        ? "GPX e diagnostica caricati · confronto Fit automatico programmato"
                        : "Sincronizzazione Drive non riuscita: " + result.code(),
                    Toast.LENGTH_LONG).show();
            }));
        });
    }

    private void compareLatestWithGoogleFit() {
        comparisonView.setText("Lettura riferimento Google Fit da Health Connect…");
        io.execute(() -> {
            java.util.List<RunSession> sessions = RunDatabase.get(this).runs().sessions();
            if (sessions.isEmpty()) {
                runOnUiThread(() -> comparisonView.setText("Nessuna attività locale da confrontare"));
                return;
            }
            HealthConnectGateway.compareGoogleFit(this, sessions.get(0), new HealthConnectGateway.ComparisonCallback() {
                @Override public void onSuccess(HealthConnectGateway.GoogleFitComparison c) {
                    String fitDistance = c.getDistanceMeters() == null ? "—" : String.format(Locale.ITALY, "%.3f km", c.getDistanceMeters()/1000);
                    String delta = c.getDistanceMeters() == null || c.getDistanceMeters() <= 0 ? "—" :
                        String.format(Locale.ITALY, "%+.1f%%", 100*(c.getLocalDistanceMeters()-c.getDistanceMeters())/c.getDistanceMeters());
                    String steps = c.getSteps() == null ? "—" : String.format(Locale.ITALY, "%,d", c.getSteps());
                    String stepDelta = c.getSteps() == null || c.getSteps() <= 0 ? "—" :
                        String.format(Locale.ITALY, "%+.1f%%", 100.0*(c.getLocalSteps()-c.getSteps())/c.getSteps());
                    String calories = c.getActiveCalories() == null ? "—" : String.format(Locale.ITALY, "%.1f kcal", c.getActiveCalories());
                    comparisonView.setText(String.format(Locale.ITALY,
                        "Google Fit · %s · %s passi · %s\nDeterministic Todo · %.3f km (%s) · %,d passi (%s) · intervallo %d:%02d",
                        fitDistance, steps, calories, c.getLocalDistanceMeters()/1000, delta,
                        c.getLocalSteps(), stepDelta,
                        c.getDurationMillis()/60000, (c.getDurationMillis()/1000)%60));
                    DriveTestExportManager.captureGoogleFitComparison(RunTrackerActivity.this, sessions.get(0).id, c);
                    DriveTestExportManager.captureComparisonAttempt(
                        RunTrackerActivity.this, sessions.get(0).id, "success", 1);
                    refreshDriveExportAfterComparison(sessions.get(0));
                }
                @Override public void onPermissionRequired() {
                    recordForegroundComparisonFailure(sessions.get(0), "permission_required");
                    comparisonView.setText("Concedi in Health Connect passi, distanza e calorie, poi riprova");
                    healthPermissions.launch(HealthConnectGateway.permissions(RunTrackerActivity.this));
                }
                @Override public void onUnavailable() {
                    recordForegroundComparisonFailure(sessions.get(0), "unavailable");
                    comparisonView.setText("Health Connect non disponibile");
                }
                @Override public void onError(String code) {
                    recordForegroundComparisonFailure(sessions.get(0), code);
                    comparisonView.setText("Confronto non disponibile · diagnostica salvata: " + code);
                }
            });
        });
    }

    private void recordForegroundComparisonFailure(RunSession session, String code) {
        DriveTestExportManager.captureComparisonAttempt(this, session.id, code, 1, code);
        refreshDriveExportAfterComparison(session);
    }

    private void refreshDriveExportAfterComparison(RunSession session) {
        io.execute(() -> DriveTestExportManager.exportComparison(this, session, result -> runOnUiThread(() -> {
                driveStatusView.setText(DriveTestExportManager.status(this));
                if (result.success()) comparisonView.append("\nConfronto salvato su Drive.");
                else comparisonView.append("\nDrive: " + result.code());
            })));
    }

    private final Runnable clockTick = new Runnable() {
        @Override public void run() { renderClock(); clock.postDelayed(this, 1000); }
    };

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != DRIVE_FOLDER_REQUEST || resultCode != RESULT_OK || data == null || data.getData() == null) return;
        try {
            DriveTestExportManager.setFolder(this, data.getData(), data.getFlags());
            driveButton.setText("Drive test collegato · cambia cartella");
            driveStatusView.setText(DriveTestExportManager.status(this));
            Toast.makeText(this, "Cartella test collegata", Toast.LENGTH_SHORT).show();
        } catch (RuntimeException error) {
            Toast.makeText(this, "Impossibile conservare l’accesso alla cartella scelta", Toast.LENGTH_LONG).show();
        }
    }

    private void renderClock() {
        long elapsed = startedAt == 0 ? 0 : Math.max(0, System.currentTimeMillis() - startedAt);
        long seconds = elapsed / 1000;
        durationView.setText(String.format(Locale.ROOT, "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60));
        distanceView.setText(String.format(Locale.ITALY, "%.2f km", distance / 1000));
        if (distance >= 20 && elapsed > 0) {
            double secondsPerKm = elapsed / 1000.0 / (distance / 1000.0);
            paceView.setText(String.format(Locale.ROOT, "%d:%02d /km", (int) secondsPerKm / 60, (int) secondsPerKm % 60));
        } else paceView.setText("— /km");
        if (sessionId == 0) renderAutomaticComparisonStatus();
    }

    private void renderAutomaticComparisonStatus() {
        String status = DriveTestExportManager.comparisonStatus(this);
        if ("success".equals(status)) comparisonView.setText(DriveTestExportManager.comparisonSummary(this));
        else if ("scheduled".equals(status) || "waiting".equals(status)) comparisonView.setText("Attendo la sincronizzazione Google Fit…");
        else if ("fit_not_synced".equals(status) || "timeout".equals(status) || "health_error".equals(status)) comparisonView.setText("Google Fit non è ancora pronto · riprovo automaticamente");
        else if ("permission_required".equals(status)) comparisonView.setText("Health Connect richiede l’autorizzazione");
        else if ("unavailable".equals(status)) comparisonView.setText("Health Connect non disponibile");
        else if ("drive_failed".equals(status) || "drive_timeout".equals(status)) comparisonView.setText("Confronto trovato · nuovo tentativo Drive");
    }

    private LinearLayout metricBlock(String caption, TextView value) {
        LinearLayout box = new LinearLayout(this); box.setOrientation(LinearLayout.VERTICAL); box.setGravity(Gravity.CENTER);
        box.addView(value); box.addView(label(caption, 12)); return box;
    }
    private LinearLayout sectionCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.WHITE);
        background.setCornerRadius(dp(18));
        background.setStroke(dp(1), Color.rgb(231, 228, 235));
        card.setBackground(background);
        card.setElevation(dp(1));
        return card;
    }
    private TextView sectionTitle(String value) {
        TextView title = label(value, 12);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(Color.rgb(92, 88, 98));
        return title;
    }
    private TextView centeredLabel(String value, int size) {
        TextView view = label(value, size);
        view.setGravity(Gravity.CENTER);
        return view;
    }
    private TextView metric(String value, int size) { TextView v = label(value, size); v.setGravity(Gravity.CENTER); v.setTypeface(Typeface.DEFAULT, Typeface.BOLD); return v; }
    private TextView label(String value, int size) { TextView v = new TextView(this); v.setText(value); v.setTextSize(size); return v; }
    private LinearLayout.LayoutParams matchWrap(int top) { LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2); p.topMargin = top; return p; }
    private LinearLayout.LayoutParams weighted() { return new LinearLayout.LayoutParams(0, -2, 1); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    @Override protected void onStart() {
        super.onStart();
        if (driveStatusView != null) driveStatusView.setText(DriveTestExportManager.status(this));
        if (intensiveButton != null) renderIntensiveState();
        ContextCompat.registerReceiver(this, stateReceiver, new IntentFilter(RunRecordingService.ACTION_STATE), ContextCompat.RECEIVER_NOT_EXPORTED);
    }
    @Override protected void onStop() { unregisterReceiver(stateReceiver); super.onStop(); }
    @Override protected void onDestroy() { clock.removeCallbacksAndMessages(null); io.shutdown(); super.onDestroy(); }
}
