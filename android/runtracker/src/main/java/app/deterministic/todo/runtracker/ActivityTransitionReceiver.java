package app.deterministic.todo.runtracker;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;

import com.google.android.gms.location.ActivityTransition;
import com.google.android.gms.location.ActivityTransitionEvent;
import com.google.android.gms.location.ActivityTransitionResult;
import com.google.android.gms.location.DetectedActivity;

import java.util.HashSet;
import java.util.Set;

public final class ActivityTransitionReceiver extends BroadcastReceiver {
    private static final String PREFS = "movement_activity_timeline";
    private static final String ACTIVE = "active_types";

    @Override public void onReceive(Context context, Intent intent) {
        ActivityTransitionResult result = ActivityTransitionResult.extractResult(intent);
        if (result == null) return;
        Set<String> active = new HashSet<>(context.getSharedPreferences(PREFS,
            Context.MODE_PRIVATE).getStringSet(ACTIVE, Set.of()));
        for (ActivityTransitionEvent event : result.getTransitionEvents()) {
            String type = Integer.toString(event.getActivityType());
            if (event.getTransitionType() == ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                active.add(type);
            else active.remove(type);
            long eventMillis = System.currentTimeMillis() - SystemClock.elapsedRealtime()
                + event.getElapsedRealTimeNanos() / 1_000_000L;
            ActivityTimeline.append(context, eventMillis, effective(active));
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(ACTIVE, active).apply();
    }

    private static String effective(Set<String> active) {
        if (has(active, DetectedActivity.IN_VEHICLE)) return ActivityTimeline.VEHICLE;
        if (has(active, DetectedActivity.ON_BICYCLE)) return ActivityTimeline.BICYCLE;
        if (has(active, DetectedActivity.RUNNING)) return ActivityTimeline.RUNNING;
        if (has(active, DetectedActivity.WALKING) || has(active, DetectedActivity.ON_FOOT))
            return ActivityTimeline.WALKING;
        if (has(active, DetectedActivity.STILL)) return ActivityTimeline.STILL;
        return ActivityTimeline.UNKNOWN;
    }

    private static boolean has(Set<String> values, int type) {
        return values.contains(Integer.toString(type));
    }
}
