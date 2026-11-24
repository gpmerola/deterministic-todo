package app.deterministic.todo.h96remote;

import android.content.Context;
import android.content.SharedPreferences;

/** The paired box: address, name and certificate pin. Nothing here is secret or personal. */
public final class BoxStore {
    public static final class Box {
        public final String host;
        public final String name;
        public final String pin;

        Box(String host, String name, String pin) {
            this.host = host;
            this.name = name;
            this.pin = pin;
        }
    }

    private final SharedPreferences prefs;

    public BoxStore(Context context) {
        prefs = context.getSharedPreferences("h96_remote", Context.MODE_PRIVATE);
    }

    public Box load() {
        String host = prefs.getString("host", null);
        String pin = prefs.getString("pin", null);
        if (host == null || pin == null) return null;
        return new Box(host, prefs.getString("name", ""), pin);
    }

    public void save(String host, String name, String pin) {
        prefs.edit().putString("host", host).putString("name", name).putString("pin", pin).apply();
    }

    public void updateHost(String host) {
        prefs.edit().putString("host", host).apply();
    }

    public void clear() {
        prefs.edit().clear().apply();
    }
}
