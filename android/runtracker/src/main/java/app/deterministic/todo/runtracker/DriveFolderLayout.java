package app.deterministic.todo.runtracker;

/** Stable Drive subfolders selected only from app-owned file names. */
final class DriveFolderLayout {
    static final String SESSIONS = "01 Sessions";
    static final String PASSIVE = "02 Passive";
    static final String INTENSIVE = "03 Intensive";
    static final String APP_DIAGNOSTICS = "04 App diagnostics";
    static final String BIP_U = "05 Bip U";

    private DriveFolderLayout() {}

    static String folderFor(String name) {
        if (name.startsWith("movement_snapshot_") || name.startsWith("daily_audit_"))
            return PASSIVE;
        if (name.startsWith("intensive_")) return INTENSIVE;
        if (name.startsWith("todo_diagnostics_")) return APP_DIAGNOSTICS;
        if (name.startsWith("bip_u_")) return BIP_U;
        if (name.matches("\\d+_(walk|run)_session-\\d+.*")
            || name.matches("(walk|run)-\\d+\\.gpx")) return SESSIONS;
        return null;
    }
}
