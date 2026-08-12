package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class StrideCalibrator {
    private static final String PREFS = "movement_profile";
    private static final int REQUIRED_SAMPLES = 3;
    private static final int MAX_SAMPLES = 7;

    private StrideCalibrator() {}

    static void record(Context context, RunSession session, long steps) {
        if (session == null || steps <= 0) return;
        SharedPreferences preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String sessionKey = "stride_calibrated_session_" + session.id;
        if (preferences.getBoolean(sessionKey, false)) return;
        String type = "run".equals(session.activityType) ? "running" :
            ("walk".equals(session.activityType) ? "walking" : null);
        if (type == null || !eligible(type, session.distanceMeters, steps)) return;
        double candidate = session.distanceMeters / steps;
        List<Double> samples = decode(preferences.getString(type + "_stride_samples", "[]"));
        samples.add(candidate);
        while (samples.size() > MAX_SAMPLES) samples.remove(0);
        SharedPreferences.Editor editor = preferences.edit()
            .putBoolean(sessionKey, true)
            .putString(type + "_stride_samples", encode(samples));
        if (samples.size() >= REQUIRED_SAMPLES)
            editor.putFloat(type + "_stride_meters", (float) median(samples));
        editor.apply();
    }

    static boolean eligible(String type, double distanceMeters, long steps) {
        double stride = steps <= 0 ? 0 : distanceMeters / steps;
        if ("walking".equals(type))
            return distanceMeters >= 1000 && steps >= 1000 && stride >= 0.40 && stride <= 0.95;
        if ("running".equals(type))
            return distanceMeters >= 3000 && steps >= 2000 && stride >= 0.65 && stride <= 1.60;
        return false;
    }

    static double median(List<Double> values) {
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        int middle = sorted.size() / 2;
        return sorted.size() % 2 == 0 ? (sorted.get(middle - 1) + sorted.get(middle)) / 2
            : sorted.get(middle);
    }

    private static List<Double> decode(String value) {
        List<Double> result = new ArrayList<>();
        try {
            JSONArray json = new JSONArray(value);
            for (int i = 0; i < json.length(); i++) result.add(json.getDouble(i));
        } catch (Exception ignored) { result.clear(); }
        return result;
    }

    private static String encode(List<Double> values) {
        JSONArray json = new JSONArray();
        try {
            for (double value : values) json.put(value);
        } catch (Exception impossibleForValidatedFiniteValues) {
            return "[]";
        }
        return json.toString();
    }
}
