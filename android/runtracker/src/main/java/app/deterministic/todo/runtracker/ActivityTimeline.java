package app.deterministic.todo.runtracker;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

final class ActivityTimeline {
    static final String UNKNOWN = "unknown";
    static final String WALKING = "walking";
    static final String RUNNING = "running";
    static final String VEHICLE = "vehicle";
    static final String BICYCLE = "bicycle";
    static final String STILL = "still";
    private static final String PREFS = "movement_activity_timeline";
    private static final String EVENTS = "events";
    private static final long RETENTION_MS = 14L * 24 * 60 * 60 * 1000;

    record Event(long atMillis, String activity) {}

    private ActivityTimeline() {}

    static synchronized void append(Context context, long atMillis, String activity) {
        List<Event> events = read(context);
        if (!events.isEmpty() && events.get(events.size() - 1).activity().equals(activity)) return;
        events.add(new Event(atMillis, activity));
        long cutoff = System.currentTimeMillis() - RETENTION_MS;
        events.removeIf(event -> event.atMillis() < cutoff);
        events.sort(Comparator.comparingLong(Event::atMillis));
        JSONArray json = new JSONArray();
        for (Event event : events) json.put(new JSONObject()
            .put("at", event.atMillis()).put("activity", event.activity()));
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(EVENTS, json.toString()).apply();
    }

    static synchronized List<Event> read(Context context) {
        List<Event> result = new ArrayList<>();
        String encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(EVENTS, "[]");
        try {
            JSONArray array = new JSONArray(encoded);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.getJSONObject(i);
                result.add(new Event(item.getLong("at"), item.getString("activity")));
            }
        } catch (Exception ignored) { result.clear(); }
        result.sort(Comparator.comparingLong(Event::atMillis));
        return result;
    }

    static String at(List<Event> events, long atMillis) {
        String result = UNKNOWN;
        for (Event event : events) {
            if (event.atMillis() > atMillis) break;
            result = event.activity();
        }
        return result;
    }
}
