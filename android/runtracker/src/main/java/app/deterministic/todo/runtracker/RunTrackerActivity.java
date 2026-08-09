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
    private final ActivityResultLauncher<Uri> driveFolder = registerForActivityResult(
        new ActivityResultContracts.OpenDocumentTree(), uri -> { if (uri != null) { DriveTestExportManager.setFolder(this, uri); Toast.makeText(this, "Cartella test collegata", Toast.LENGTH_SHORT).show(); } });
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler clock = new Handler(Looper.getMainLooper());
    private TextView durationView;
    private TextView distanceView;
    private TextView paceView;
    private TextView accuracyView;
    private TextView dailyStepsView;
    private TextView dailyDistanceView;
    private TextView dailyCaloriesView;
    private TextView movementStatusView;
    private Button healthPermissionButton;
    private Button primaryButton;
    private Button walkButton;
    private String pendingActivityType = "run";
    private long sessionId;
    private long startedAt;
    private double distance;

    private final ActivityResultLauncher<Set<String>> healthPermissions = registerForActivityResult(
        HealthConnectGateway.permissionContract(), granted -> refreshDailyMovement()
    );

    private final BroadcastReceiver stateReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            sessionId = intent.getLongExtra(RunRecordingService.EXTRA_SESSION_ID, 0);
            startedAt = intent.getLongExtra("started_at", 0);
            distance = intent.getDoubleExtra(RunRecordingService.EXTRA_DISTANCE, 0);
            float accuracy = intent.getFloatExtra(RunRecordingService.EXTRA_ACCURACY, 0);
            String gpsStatus = intent.getStringExtra(RunRecordingService.EXTRA_STATUS);
            String activityType = intent.getStringExtra(RunRecordingService.EXTRA_ACTIVITY_TYPE);
            accuracyView.setText(
                gpsStatus == null
                    ? (accuracy <= 0 ? "Ricerca del segnale GPS…" : String.format(Locale.ROOT, "Accuratezza ± %.0f m", accuracy))
                    : (accuracy <= 0 ? gpsStatus : gpsStatus + String.format(Locale.ROOT, " · ± %.0f m", accuracy))
            );
            primaryButton.setText(sessionId == 0 ? "Avvia corsa" : "Termina");
            walkButton.setEnabled(sessionId == 0);
            if (sessionId != 0 && "walk".equals(activityType)) primaryButton.setText("Termina camminata");
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
                primaryButton.setText("Termina");
                walkButton.setEnabled(false);
                renderClock();
            });
        });
        clock.post(clockTick);
        refreshDailyMovement();
    }

    private View content() {
        int pad = dp(24);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView movementTitle = label("OGGI · PASSI DEL TELEFONO", 13);
        movementTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(movementTitle, matchWrap(0));
        dailyStepsView = metric("—", 38);
        root.addView(dailyStepsView, matchWrap(dp(12)));

        LinearLayout dailyMetrics = new LinearLayout(this);
        dailyMetrics.setOrientation(LinearLayout.HORIZONTAL);
        dailyMetrics.setGravity(Gravity.CENTER);
        dailyDistanceView = metric("— km", 22);
        dailyCaloriesView = metric("— kcal", 22);
        dailyMetrics.addView(metricBlock("DISTANZA STIMATA", dailyDistanceView), weighted());
        dailyMetrics.addView(metricBlock("CALORIE ATTIVE STIMATE", dailyCaloriesView), weighted());
        root.addView(dailyMetrics, matchWrap(dp(10)));

        movementStatusView = label("Controllo Health Connect…", 14);
        movementStatusView.setGravity(Gravity.CENTER);
        root.addView(movementStatusView, matchWrap(dp(12)));

        healthPermissionButton = new Button(this);
        healthPermissionButton.setText("Consenti accesso ai passi");
        healthPermissionButton.setOnClickListener(v -> healthPermissions.launch(HealthConnectGateway.permissions()));
        healthPermissionButton.setVisibility(View.GONE);
        root.addView(healthPermissionButton, matchWrap(dp(8)));

        TextView title = label("SESSIONE GPS DEL TELEFONO", 13);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, matchWrap(0));
        durationView = metric("00:00:00", 44);
        root.addView(durationView, matchWrap(dp(28)));

        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.HORIZONTAL);
        metrics.setGravity(Gravity.CENTER);
        distanceView = metric("0,00 km", 25);
        paceView = metric("— /km", 25);
        metrics.addView(metricBlock("DISTANZA", distanceView), weighted());
        metrics.addView(metricBlock("PASSO MEDIO", paceView), weighted());
        root.addView(metrics, matchWrap(dp(18)));

        accuracyView = label("Premi Avvia corsa per attivare il GPS", 16);
        accuracyView.setGravity(Gravity.CENTER);
        root.addView(accuracyView, matchWrap(dp(20)));

        TextView privacy = label("La traccia resta sul dispositivo. I punti GPS scartati vengono conservati con il motivo per la diagnostica.", 14);
        privacy.setGravity(Gravity.CENTER);
        root.addView(privacy, matchWrap(dp(18)));

        primaryButton = new Button(this);
        primaryButton.setText("Avvia corsa");
        primaryButton.setOnClickListener(v -> { if (sessionId == 0) ensurePermissions("run"); else stopRun(); });
        root.addView(primaryButton, matchWrap(dp(24)));

        walkButton = new Button(this);
        walkButton.setText("Avvia camminata");
        walkButton.setOnClickListener(v -> ensurePermissions("walk"));
        root.addView(walkButton, matchWrap(dp(8)));

        Button drive = new Button(this);
        drive.setText(DriveTestExportManager.isConfigured(this) ? "Drive test collegato · cambia cartella" : "Collega cartella Google Drive per i test");
        drive.setOnClickListener(v -> driveFolder.launch(null));
        root.addView(drive, matchWrap(dp(12)));

        Button export = new Button(this);
        export.setText("Esporta ultima attività in GPX");
        export.setOnClickListener(v -> exportLatest());
        root.addView(export, matchWrap(dp(8)));

        Button watch = new Button(this);
        watch.setText("Bip U · prova BLE in sola lettura");
        watch.setOnClickListener(v -> BipUBleActivity.open(this));
        root.addView(watch, matchWrap(dp(8)));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
        return scroll;
    }

    private void refreshDailyMovement() {
        HealthConnectGateway.refreshToday(this, new HealthConnectGateway.Callback() {
            @Override public void onSuccess(DailyMovement movement) {
                dailyStepsView.setText(String.format(Locale.ITALY, "%,d passi", movement.steps));
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
        primaryButton.setText("Avvia corsa");
        walkButton.setEnabled(true);
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

    private final Runnable clockTick = new Runnable() {
        @Override public void run() { renderClock(); clock.postDelayed(this, 1000); }
    };

    private void renderClock() {
        long elapsed = startedAt == 0 ? 0 : Math.max(0, System.currentTimeMillis() - startedAt);
        long seconds = elapsed / 1000;
        durationView.setText(String.format(Locale.ROOT, "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60));
        distanceView.setText(String.format(Locale.ITALY, "%.2f km", distance / 1000));
        if (distance >= 20 && elapsed > 0) {
            double secondsPerKm = elapsed / 1000.0 / (distance / 1000.0);
            paceView.setText(String.format(Locale.ROOT, "%d:%02d /km", (int) secondsPerKm / 60, (int) secondsPerKm % 60));
        } else paceView.setText("— /km");
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
        ContextCompat.registerReceiver(this, stateReceiver, new IntentFilter(RunRecordingService.ACTION_STATE), ContextCompat.RECEIVER_NOT_EXPORTED);
    }
    @Override protected void onStop() { unregisterReceiver(stateReceiver); super.onStop(); }
    @Override protected void onDestroy() { clock.removeCallbacks(clockTick); io.shutdown(); super.onDestroy(); }
}
