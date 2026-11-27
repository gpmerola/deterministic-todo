package app.deterministic.todo.h96remote;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * WiZ bulbs' local protocol: small JSON messages over UDP port 38899 on the LAN, no cloud.
 * The bulb needs "Allow local communication" enabled in the WiZ app. Hand-written JSON keeps
 * the module dependency-free and testable on the JVM.
 */
public final class WizProtocol {
    public static final int PORT = 38899;
    public static final int MIN_DIMMING = 10;
    public static final int MAX_DIMMING = 100;
    public static final int MIN_KELVIN = 2200;
    public static final int MAX_KELVIN = 6500;

    /** Last state reported by a bulb; unknown numbers are -1. */
    public static final class Pilot {
        public final String mac;
        public final boolean on;
        public final int dimming;
        public final int r;
        public final int g;
        public final int b;
        public final int kelvin;

        Pilot(String mac, boolean on, int dimming, int r, int g, int b, int kelvin) {
            this.mac = mac;
            this.on = on;
            this.dimming = dimming;
            this.r = r;
            this.g = g;
            this.b = b;
            this.kelvin = kelvin;
        }
    }

    private WizProtocol() {}

    public static String getPilot() {
        return "{\"method\":\"getPilot\",\"params\":{}}";
    }

    public static String power(boolean on) {
        return setPilot("\"state\":" + on);
    }

    public static String dimming(int percent) {
        return setPilot("\"state\":true,\"dimming\":" + clamp(percent, MIN_DIMMING, MAX_DIMMING));
    }

    public static String color(int r, int g, int b) {
        return setPilot(String.format(Locale.ROOT, "\"state\":true,\"r\":%d,\"g\":%d,\"b\":%d",
            clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)));
    }

    public static String white(int kelvin) {
        return setPilot("\"state\":true,\"temp\":" + clamp(kelvin, MIN_KELVIN, MAX_KELVIN));
    }

    /** Parses a getPilot or setPilot reply; null when it is not a pilot state. */
    public static Pilot parsePilot(String json) {
        if (json == null || !json.contains("\"result\"")) return null;
        Boolean state = bool(json, "state");
        if (state == null) return null;
        return new Pilot(string(json, "mac"), state, number(json, "dimming"),
            number(json, "r"), number(json, "g"), number(json, "b"), number(json, "temp"));
    }

    /** True for a successful setPilot acknowledgement. */
    public static boolean isSuccess(String json) {
        Boolean success = json == null ? null : bool(json, "success");
        return success != null && success;
    }

    private static String setPilot(String params) {
        return "{\"method\":\"setPilot\",\"params\":{" + params + "}}";
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static int number(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?\\d+)").matcher(json);
        return m.find() ? Integer.parseInt(m.group(1)) : -1;
    }

    private static Boolean bool(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(true|false)").matcher(json);
        return m.find() ? Boolean.valueOf(m.group(1)) : null;
    }

    private static String string(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([0-9a-fA-F:]{1,32})\"").matcher(json);
        return m.find() ? m.group(1).toLowerCase(Locale.ROOT) : "";
    }
}
