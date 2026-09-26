package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.content.ContextCompat;

import com.google.android.gms.location.ActivityRecognition;
import com.google.android.gms.location.ActivityTransition;
import com.google.android.gms.location.ActivityTransitionRequest;
import com.google.android.gms.location.DetectedActivity;

import java.util.ArrayList;
import java.util.List;

public final class ActivityClassifier {
    private static final String PREFS = "movement_activity_timeline";
    private ActivityClassifier() {}

    public static void register(Context context) {
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(context,
            Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            status(context, "permission_required");
            return;
        }
        List<ActivityTransition> transitions = new ArrayList<>();
        for (int activity : new int[] {DetectedActivity.WALKING, DetectedActivity.RUNNING,
            DetectedActivity.IN_VEHICLE, DetectedActivity.ON_BICYCLE, DetectedActivity.STILL,
            DetectedActivity.ON_FOOT}) {
            transitions.add(transition(activity, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            transitions.add(transition(activity, ActivityTransition.ACTIVITY_TRANSITION_EXIT));
        }
        try {
            ActivityRecognition.getClient(context).requestActivityTransitionUpdates(
                new ActivityTransitionRequest(transitions), pendingIntent(context))
                .addOnSuccessListener(ignored -> status(context, "registered"))
                .addOnFailureListener(error -> status(context,
                    "registration_failed_" + error.getClass().getSimpleName()));
        } catch (SecurityException ignored) {
            status(context, "permission_required");
        }
    }

    static PendingIntent pendingIntent(Context context) {
        Intent intent = new Intent(context, ActivityTransitionReceiver.class);
        return PendingIntent.getBroadcast(context, 8017, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
    }

    private static ActivityTransition transition(int activity, int type) {
        return new ActivityTransition.Builder().setActivityType(activity)
            .setActivityTransition(type).build();
    }

    private static void status(Context context, String value) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("registration_status", value)
            .putLong("registration_observed_at_ms", System.currentTimeMillis()).apply();
    }
}
