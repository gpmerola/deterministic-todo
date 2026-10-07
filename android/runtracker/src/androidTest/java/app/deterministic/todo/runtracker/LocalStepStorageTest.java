package app.deterministic.todo.runtracker;

import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import androidx.room.Room;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.util.List;
import java.util.UUID;
import static org.junit.Assert.*;

/** Isolated synthetic database in the test package, never the user's movement database. */
@RunWith(AndroidJUnit4.class)
public class LocalStepStorageTest {
    private Context context;
    private String name;
    private RunDatabase db;

    private RunDatabase open() {
        return Room.databaseBuilder(context, RunDatabase.class, name)
            .addMigrations(RunDatabase.MIGRATION_4_5, RunDatabase.MIGRATION_5_6).allowMainThreadQueries().build();
    }
    @Before public void setup() {
        context = InstrumentationRegistry.getInstrumentation().getContext();
        name = "synthetic-movement-" + UUID.randomUUID() + ".sqlite";
        db = open();
    }
    @After public void cleanup() { if (db != null) db.close(); context.deleteDatabase(name); }

    private LocalStepMinute minute(long start, long steps) {
        var value = new LocalStepMinute(); value.startMillis = start; value.steps = steps; return value;
    }

    @Test public void overlappingImportReplacesAndSurvivesReopen() {
        db.runs().insertLocalStepState(new LocalStepState());
        db.runs().importLocalStepMinutes(List.of(minute(60_000, 10), minute(120_000, 20)), 180_000);
        db.runs().importLocalStepMinutes(List.of(minute(120_000, 25), minute(180_000, 30)), 240_000);
        db.runs().importLocalStepMinutes(List.of(minute(120_000, 25), minute(180_000, 30)), 240_000);
        db.close(); db = open();
        assertEquals(65, db.runs().localSteps(0, 240_000));
        assertEquals(3, db.runs().localStepMinutes(0, 240_000).size());
        assertEquals(240_000, db.runs().localStepState().importedThroughMillis);
    }


    @Test public void failedBatchRollsBackRowsAndImportCursor() {
        db.runs().insertLocalStepState(new LocalStepState());
        db.runs().importLocalStepMinutes(List.of(minute(60_000, 10)), 120_000);
        LocalStepMinute invalid = minute(120_000, 20); invalid.zoneId = null;
        try {
            db.runs().importLocalStepMinutes(List.of(minute(60_000, 50), invalid), 180_000);
            fail("Constraint violation must reject the entire batch");
        } catch (RuntimeException expected) { }
        assertEquals(10, db.runs().localSteps(0, 180_000));
        assertEquals(120_000, db.runs().localStepState().importedThroughMillis);
    }

    @Test public void migrationToV6DropsArchivedDataAndKeepsSteps() {
        db.runs().insertLocalStepState(new LocalStepState());
        db.runs().importLocalStepMinutes(List.of(minute(60_000, 42)), 120_000);
        db.close();
        try (SQLiteDatabase old = SQLiteDatabase.openDatabase(context.getDatabasePath(name).getPath(), null, 0)) {
            // Synthetic version 5 tables of the archived features, with a row each.
            old.execSQL("CREATE TABLE run_sessions (id INTEGER PRIMARY KEY, activityType TEXT)");
            old.execSQL("CREATE TABLE track_points (id INTEGER PRIMARY KEY, sessionId INTEGER)");
            old.execSQL("CREATE TABLE bip_u_activity_samples (timestampMillis INTEGER, source TEXT)");
            old.execSQL("CREATE TABLE daily_movement (day TEXT, steps INTEGER)");
            old.execSQL("INSERT INTO run_sessions VALUES (1, 'walk')");
            old.execSQL("INSERT INTO track_points VALUES (1, 1)");
            old.execSQL("INSERT INTO bip_u_activity_samples VALUES (60000, 'synthetic')");
            old.execSQL("INSERT INTO daily_movement VALUES ('2026-01-01', 123)");
            old.setVersion(5);
        }
        db = open();
        assertEquals(42, db.runs().localSteps(0, 120_000));
        assertEquals(120_000, db.runs().localStepState().importedThroughMillis);
        try (var cursor = db.getOpenHelper().getReadableDatabase().query(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
                    + "('run_sessions', 'track_points', 'bip_u_activity_samples', 'daily_movement')")) {
            assertEquals(0, cursor.getCount());
        }
    }
}
