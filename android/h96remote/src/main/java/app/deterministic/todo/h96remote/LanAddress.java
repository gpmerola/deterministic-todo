package app.deterministic.todo.h96remote;

import java.util.Locale;

/** The remote only talks to private IPv4 ranges and link-local IPv6, never the Internet. */
public final class LanAddress {
    private LanAddress() {}

    public static boolean isPrivate(String host) {
        if (host == null) return false;
        String h = host.trim();
        if (h.matches("\\d{1,3}(\\.\\d{1,3}){3}")) {
            String[] parts = h.split("\\.");
            for (String part : parts) if (Integer.parseInt(part) > 255) return false;
            int a = Integer.parseInt(parts[0]);
            int b = Integer.parseInt(parts[1]);
            return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
        }
        return h.toLowerCase(Locale.ROOT).startsWith("fe80:");
    }
}
