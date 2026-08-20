package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public final class DriveFolderLayoutTest {
    @Test public void routesEveryManagedDiagnosticKind() {
        assertEquals(DriveFolderLayout.SESSIONS,
            DriveFolderLayout.folderFor("178_walk_session-000123_diagnostics.json"));
        assertEquals(DriveFolderLayout.PASSIVE,
            DriveFolderLayout.folderFor("movement_snapshot_2026-08-20_20.json"));
        assertEquals(DriveFolderLayout.PASSIVE,
            DriveFolderLayout.folderFor("daily_audit_2026-08-19.json"));
        assertEquals(DriveFolderLayout.INTENSIVE,
            DriveFolderLayout.folderFor("intensive_experiment_segment_123.jsonl"));
        assertEquals(DriveFolderLayout.APP_DIAGNOSTICS,
            DriveFolderLayout.folderFor("todo_diagnostics_2026-08-20.jsonl"));
        assertEquals(DriveFolderLayout.BIP_U,
            DriveFolderLayout.folderFor("bip_u_probe_1780000000000.json"));
    }

    @Test public void leavesUnknownFilesInTheSelectedRoot() {
        assertNull(DriveFolderLayout.folderFor("personal-note.txt"));
    }
}
