package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.core.content.ContextCompat;
import android.content.pm.ServiceInfo;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RunRecordingService extends Service implements LocationListener {
    public static final String ACTION_START = "app.deterministic.todo.runtracker.START";
    public static final String ACTION_STOP = "app.deterministic.todo.runtracker.STOP";
    public static final String ACTION_STATE = "app.deterministic.todo.runtracker.STATE";
    public static final String EXTRA_SESSION_ID = "session_id";
    public static final String EXTRA_DISTANCE = "distance";
    public static final String EXTRA_ACCURACY = "accuracy";
    public static final String EXTRA_ACCEPTED = "accepted";
    public static final String EXTRA_STATUS = "gps_status";
    private static final int NOTIFICATION_ID = 7401;
    private static final String CHANNEL_ID = "run_recording";

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final GpsTrackFilter filter = new GpsTrackFilter();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private LocationManager locationManager;
    private long sessionId;
    private long startedAt;
    private volatile float lastAccuracy;
    private volatile String gpsStatus = "Avvio GPS…";
    private volatile boolean receivedLocation;
    private final Runnable noFixWarning = () -> {
        if (!receivedLocation) {
            gpsStatus = "Nessun segnale GPS: vai all’aperto e controlla che Posizione sia attiva";
            broadcast(false);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID, "Registrazione corsa", NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Mantiene attivo il GPS durante una corsa");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            finishAndStop();
            return START_NOT_STICKY;
        }
        ServiceCompat.startForeground(
            this, NOTIFICATION_ID, notification(0), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        );
        io.execute(() -> {
            RunDao dao = RunDatabase.get(this).runs();
            RunSession active = dao.activeSession();
            if (active == null) {
                startedAt = System.currentTimeMillis();
                sessionId = dao.start(startedAt);
            } else {
                sessionId = active.id;
                startedAt = active.startedAtMillis;
                // Rehydrate the deterministic filter after process recreation.
                for (TrackPoint point : dao.points(sessionId)) {
                    if (point.accepted) {
                        filter.evaluate(new GpsTrackFilter.Sample(
                            point.timestampMillis, point.latitude, point.longitude, point.accuracyMeters
                        ));
                    }
                }
            }
            if (!requestLocations()) {
                dao.finish(sessionId, filter.totalMeters(), System.currentTimeMillis());
                sessionId = 0;
                startedAt = 0;
                broadcast(false);
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
                return;
            }
            broadcast(true);
        });
        return START_STICKY;
    }

    private boolean requestLocations() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) {
            gpsStatus = "Posizione precisa non concessa";
            return false;
        }
        if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            gpsStatus = "GPS del telefono disattivato: attiva Posizione nelle impostazioni Android";
            return false;
        }
        gpsStatus = "Ricerca del segnale GPS…";
        broadcast(false);
        locationManager.requestLocationUpdates(
            LocationManager.GPS_PROVIDER, 1_000L, 0f, this, Looper.getMainLooper()
        );
        mainHandler.removeCallbacks(noFixWarning);
        mainHandler.postDelayed(noFixWarning, 20_000L);
        return true;
    }

    @Override public void onLocationChanged(Location location) {
        if (sessionId == 0) return;
        receivedLocation = true;
        mainHandler.removeCallbacks(noFixWarning);
        final GpsTrackFilter.Sample sample = new GpsTrackFilter.Sample(
            location.getTime(), location.getLatitude(), location.getLongitude(), location.getAccuracy()
        );
        final GpsTrackFilter.Decision decision = filter.evaluate(sample);
        lastAccuracy = location.getAccuracy();
        gpsStatus = location.getAccuracy() > GpsTrackFilter.MAX_ACCURACY_METERS
            ? String.format(java.util.Locale.ROOT, "Segnale debole · ± %.0f m (punto scartato)", location.getAccuracy())
            : "GPS attivo";
        io.execute(() -> {
            TrackPoint point = new TrackPoint();
            point.sessionId = sessionId;
            point.timestampMillis = sample.timeMillis();
            point.latitude = sample.latitude();
            point.longitude = sample.longitude();
            point.accuracyMeters = sample.accuracyMeters();
            point.accepted = decision.accepted();
            point.rejectionReason = decision.reason();
            point.accumulatedDistanceMeters = decision.totalMeters();
            RunDao dao = RunDatabase.get(this).runs();
            dao.insertPoint(point);
            if (decision.accepted()) dao.updateDistance(sessionId, decision.totalMeters());
            getSystemService(NotificationManager.class).notify(
                NOTIFICATION_ID, notification(decision.totalMeters())
            );
            broadcast(decision.accepted());
        });
    }

    @SuppressWarnings("deprecation") @Override public void onStatusChanged(String provider, int status, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) {}
    @Override public void onProviderDisabled(String provider) {
        gpsStatus = "GPS del telefono disattivato";
        broadcast(false);
    }

    private Notification notification(double meters) {
        Intent open = new Intent(this, RunTrackerActivity.class);
        PendingIntent content = PendingIntent.getActivity(
            this, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );
        Intent stop = new Intent(this, RunRecordingService.class).setAction(ACTION_STOP);
        PendingIntent stopAction = PendingIntent.getService(
            this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );
        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Corsa in registrazione")
            .setContentText(String.format(java.util.Locale.ROOT, "%.2f km", meters / 1000.0))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(content)
            .addAction(0, "Termina", stopAction)
            .build();
    }

    private void broadcast(boolean accepted) {
        Intent state = new Intent(ACTION_STATE).setPackage(getPackageName());
        state.putExtra(EXTRA_SESSION_ID, sessionId);
        state.putExtra(EXTRA_DISTANCE, filter.totalMeters());
        state.putExtra(EXTRA_ACCURACY, lastAccuracy);
        state.putExtra(EXTRA_ACCEPTED, accepted);
        state.putExtra(EXTRA_STATUS, gpsStatus);
        state.putExtra("started_at", startedAt);
        sendBroadcast(state);
    }

    private void finishAndStop() {
        try { locationManager.removeUpdates(this); } catch (RuntimeException ignored) {}
        long id = sessionId;
        double distance = filter.totalMeters();
        sessionId = 0;
        startedAt = 0;
        if (id != 0) io.execute(() -> RunDatabase.get(this).runs().finish(id, distance, System.currentTimeMillis()));
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
        broadcast(true);
    }

    @Nullable @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        mainHandler.removeCallbacks(noFixWarning);
        try { locationManager.removeUpdates(this); } catch (RuntimeException ignored) {}
        io.shutdown();
        super.onDestroy();
    }
}
