package app.deterministic.todo.runtracker;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
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
    private LinearLayout advancedTools;
    private String pendingActivityType = "run";
    private long sessionId;
    private long startedAt;
    private double distance;
    private long sessionSteps;

    private final ActivityResultLauncher<Set<String>> healthPermissions = registerForActivityResult(
        HealthConnectGateway.permissionContract(), granted -> {
            refreshDailyMovement();
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
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED) startRun(pendingActivityType);
            else Toast.makeText(this, "La posizione precisa è necessaria per registrare il percorso", Toast.LENGTH_LONG).show();
        }
    );

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
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
    }

    private View content() {
        int pad = dp(16);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView movementTitle = label("RIEPILOGO DI OGGI", 13);
        movementTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(movementTitle, matchWrap(0));
        LinearLayout dailyMetrics = new LinearLayout(this);
        dailyMetrics.setOrientation(LinearLayout.HORIZONTAL);
        dailyMetrics.setGravity(Gravity.CENTER);
        dailyStepsView = metric("—", 22);
        dailyDistanceView = metric("— km", 22);
        dailyCaloriesView = metric("— kcal", 22);
        dailyMetrics.addView(metricBlock("PASSI", dailyStepsView), weighted());
        dailyMetrics.addView(metricBlock("DISTANZA STIMATA", dailyDistanceView), weighted());
        dailyMetrics.addView(metricBlock("CALORIE STIMATE", dailyCaloriesView), weighted());
        root.addView(dailyMetrics, matchWrap(dp(8)));

        movementStatusView = label("Controllo Health Connect…", 14);
        movementStatusView.setGravity(Gravity.CENTER);
        root.addView(movementStatusView, matchWrap(dp(8)));

        healthPermissionButton = new Button(this);
        healthPermissionButton.setText("Consenti Health Connect");
        healthPermissionButton.setOnClickListener(v -> healthPermissions.launch(HealthConnectGateway.permissions(this)));
        healthPermissionButton.setVisibility(View.GONE);
        root.addView(healthPermissionButton, matchWrap(dp(8)));

        TextView title = label("NUOVA SESSIONE", 13);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, matchWrap(dp(12)));
        durationView = metric("00:00:00", 34);
        root.addView(durationView, matchWrap(dp(8)));

        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.HORIZONTAL);
        metrics.setGravity(Gravity.CENTER);
        distanceView = metric("0,00 km", 21);
        sessionStepsView = metric("0", 21);
        paceView = metric("— /km", 21);
        metrics.addView(metricBlock("DISTANZA", distanceView), weighted());
        metrics.addView(metricBlock("PASSI", sessionStepsView), weighted());
        metrics.addView(metricBlock("PASSO MEDIO", paceView), weighted());
        root.addView(metrics, matchWrap(dp(8)));

        accuracyView = label("Pronto. Il GPS si attiva soltanto durante la sessione.", 16);
        accuracyView.setGravity(Gravity.CENTER);
        root.addView(accuracyView, matchWrap(dp(10)));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        primaryButton = new Button(this);
        primaryButton.setText("Avvia camminata");
        primaryButton.setOnClickListener(v -> { if (sessionId == 0) ensurePermissions("walk"); else stopRun(); });
        actions.addView(primaryButton, weighted());

        secondaryButton = new Button(this);
        secondaryButton.setText("Avvia corsa");
        secondaryButton.setOnClickListener(v -> ensurePermissions("run"));
        actions.addView(secondaryButton, weighted());
        root.addView(actions, matchWrap(dp(12)));

        TextView automationTitle = label("TEST AUTOMATICO", 13);
        automationTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(automationTitle, matchWrap(dp(14)));
        comparisonView = label("Confronto automatico pronto", 13);
        comparisonView.setGravity(Gravity.CENTER);
        root.addView(comparisonView, matchWrap(dp(5)));

        driveStatusView = label(DriveTestExportManager.status(this), 14);
        driveStatusView.setGravity(Gravity.CENTER);
        root.addView(driveStatusView, matchWrap(dp(5)));

        Button advancedToggle = new Button(this);
        advancedToggle.setText("Strumenti avanzati");
        root.addView(advancedToggle, matchWrap(dp(10)));

        advancedTools = new LinearLayout(this);
        advancedTools.setOrientation(LinearLayout.VERTICAL);
        advancedTools.setVisibility(View.GONE);
        root.addView(advancedTools, matchWrap(0));
        advancedToggle.setOnClickListener(v -> {
            boolean show = advancedTools.getVisibility() != View.VISIBLE;
            advancedTools.setVisibility(show ? View.VISIBLE : View.GONE);
            advancedToggle.setText(show ? "Nascondi strumenti avanzati" : "Strumenti avanzati");
        });

        driveButton = new Button(this);
        driveButton.setText(DriveTestExportManager.isConfigured(this) ? "Drive test collegato · cambia cartella" : "Collega cartella Google Drive per i test");
        driveButton.setOnClickListener(v -> {
            Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
            startActivityForResult(picker, DRIVE_FOLDER_REQUEST);
        });
        advancedTools.addView(driveButton, matchWrap(dp(8)));

        Button retryDrive = new Button(this);
        retryDrive.setText("Riesporta ultima attività su Drive · GPX + JSON");
        retryDrive.setOnClickListener(v -> retryLatestToDrive());
        advancedTools.addView(retryDrive, matchWrap(dp(8)));

        Button export = new Button(this);
        export.setText("Condividi manualmente ultima attività in GPX");
        export.setOnClickListener(v -> exportLatest());
        advancedTools.addView(export, matchWrap(dp(8)));

        Button compare = new Button(this);
        compare.setText("Confronta ultima attività con Google Fit");
        compare.setOnClickListener(v -> compareLatestWithGoogleFit());
        advancedTools.addView(compare, matchWrap(dp(8)));

        Button watch = new Button(this);
        watch.setText("Bip U · prova BLE in sola lettura");
        watch.setOnClickListener(v -> BipUBleActivity.open(this));
        advancedTools.addView(watch, matchWrap(dp(8)));
        ScrollView scroll = new ScrollView(this);
        scroll.setSaveEnabled(false);
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
        root.setFocusableInTouchMode(true);
        root.requestFocus();
        scroll.post(() -> scroll.scrollTo(0, 0));
        return scroll;
    }

    private void refreshDailyMovement() {
        HealthConnectGateway.refreshToday(this, new HealthConnectGateway.Callback() {
            @Override public void onSuccess(DailyMovement movement) {
                dailyStepsView.setText(String.format(Locale.ITALY, "%,d", movement.steps));
                dailyDistanceView.setText(String.format(Locale.ITALY, "%.2f km", movement.estimatedDistanceMeters / 1000));
                dailyCaloriesView.setText(String.format(Locale.ITALY, "%.0f kcal", movement.estimatedActiveCalories));
                movementStatusView.setText("Health Connect · aggiornato ora · valori di distanza e calorie stimati");
                healthPermissionButton.setVisibility(View.GONE);
            }

            @Override public void onPermissionRequired() {
                movementStatusView.setText("Autorizza Health Connect: continuerà a raccogliere i passi anche quando l’app è chiusa");
                healthPermissionButton.setVisibility(View.VISIBLE);
            }

            @Override public void onUnavailable() {
                movementStatusView.setText("Health Connect non disponibile o da aggiornare su questo dispositivo");
                healthPermissionButton.setVisibility(View.GONE);
            }

            @Override public void onError() {
                movementStatusView.setText("Impossibile aggiornare i passi; riproveremo alla prossima apertura");
            }
        });
    }

    private void ensurePermissions(String activityType) {
        pendingActivityType = activityType;
        ArrayList<String> required = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.POST_NOTIFICATIONS);
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) required.add(Manifest.permission.ACTIVITY_RECOGNITION);
        if (required.isEmpty()) startRun(activityType); else permissions.launch(required.toArray(new String[0]));
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

    private void retryLatestToDrive() {
        driveStatusView.setText("Export Drive in corso…");
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
                Toast.makeText(this,
                    result.success() ? "GPX e JSON caricati su Drive" : "Export Drive non riuscito: " + result.code(),
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
                    refreshDriveExportAfterComparison(sessions.get(0));
                }
                @Override public void onPermissionRequired() {
                    comparisonView.setText("Concedi in Health Connect passi, distanza e calorie, poi riprova");
                    healthPermissions.launch(HealthConnectGateway.permissions(RunTrackerActivity.this));
                }
                @Override public void onUnavailable() { comparisonView.setText("Health Connect non disponibile"); }
                @Override public void onError() { comparisonView.setText("Confronto non disponibile: verifica che Google Fit condivida i dati in Health Connect"); }
            });
        });
    }

    private void refreshDriveExportAfterComparison(RunSession session) {
        io.execute(() -> {
            RunDao dao = RunDatabase.get(this).runs();
            DriveTestExportManager.finish(this, session, dao.points(session.id), result -> runOnUiThread(() -> {
                driveStatusView.setText(DriveTestExportManager.status(this));
                if (result.success()) comparisonView.append("\nConfronto aggiunto al JSON su Drive.");
            }));
        });
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
    private TextView metric(String value, int size) { TextView v = label(value, size); v.setGravity(Gravity.CENTER); v.setTypeface(Typeface.DEFAULT, Typeface.BOLD); return v; }
    private TextView label(String value, int size) { TextView v = new TextView(this); v.setText(value); v.setTextSize(size); return v; }
    private LinearLayout.LayoutParams matchWrap(int top) { LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2); p.topMargin = top; return p; }
    private LinearLayout.LayoutParams weighted() { return new LinearLayout.LayoutParams(0, -2, 1); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    @Override protected void onStart() {
        super.onStart();
        if (driveStatusView != null) driveStatusView.setText(DriveTestExportManager.status(this));
        ContextCompat.registerReceiver(this, stateReceiver, new IntentFilter(RunRecordingService.ACTION_STATE), ContextCompat.RECEIVER_NOT_EXPORTED);
    }
    @Override protected void onStop() { unregisterReceiver(stateReceiver); super.onStop(); }
    @Override protected void onDestroy() { clock.removeCallbacksAndMessages(null); io.shutdown(); super.onDestroy(); }
}
