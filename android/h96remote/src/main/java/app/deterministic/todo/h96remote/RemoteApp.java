package app.deterministic.todo.h96remote;

/** App shortcuts: links the box resolves to the installed app (Android TV app links). */
public enum RemoteApp {
    YOUTUBE("https://www.youtube.com"),
    NETFLIX("https://www.netflix.com/title"),
    PRIME_VIDEO("https://app.primevideo.com"),
    GOOGLE_PLAY("market://launcher");

    public final String link;

    RemoteApp(String link) {
        this.link = link;
    }

    /** Parses the name used by the Flutter channel; null when unknown. */
    public static RemoteApp parse(String name) {
        if (name == null) return null;
        for (RemoteApp app : values()) if (app.name().equalsIgnoreCase(name)) return app;
        return null;
    }
}
