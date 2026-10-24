package app.deterministic.todo.deterministic_todo;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** Occurrences already notified, as opaque id to expiry instant (build 306:
 * shared by the urgent-visit and Semble-conflict notifications). Expired
 * ids drop out on every read; nothing else is stored. */
final class NotificationLedger {
    private final SharedPreferences prefs;
    private final JSONObject sent = new JSONObject();
    private final long now = System.currentTimeMillis();

    NotificationLedger(Context context, String name) throws JSONException {
        prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE);
        JSONObject stored = new JSONObject(prefs.getString("sent", "{}"));
        for (Iterator<String> keys = stored.keys(); keys.hasNext();) {
            String id = keys.next();
            if (stored.getLong(id) > now) sent.put(id, stored.getLong(id));
        }
    }

    /** Events not over and not notified yet ({id, end, ...}), now recorded. */
    List<Map<String, Object>> fresh(List<Map<String, Object>> events) throws JSONException {
        List<Map<String, Object>> fresh = new ArrayList<>();
        for (Map<String, Object> event : events) {
            String id = (String) event.get("id");
            long end = ((Number) event.get("end")).longValue();
            if (end <= now || sent.has(id)) continue;
            fresh.add(event);
            sent.put(id, end);
        }
        return fresh;
    }

    void commit() {
        if (!prefs.edit().putString("sent", sent.toString()).commit()) {
            throw new IllegalStateException("Notification ledger unavailable");
        }
    }
}
