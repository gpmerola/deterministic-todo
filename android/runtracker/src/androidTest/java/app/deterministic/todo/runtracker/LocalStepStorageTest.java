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
            .addMigrations(RunDatabase.MIGRATION_4_5).allowMainThreadQueries().build();
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

    @Test public void migrationFromV4PreservesSessionAndDailySubtotal() {
        long id = db.runs().start(60_000, "walk");
        DailyMovement day = new DailyMovement(); day.day = "2026-01-01";
        day.zoneId = "UTC"; day.steps = 123; db.runs().upsertDailyMovement(day);
        db.close();
        try (SQLiteDatabase old = SQLiteDatabase.openDatabase(context.getDatabasePath(name).getPath(), null, 0)) {
            old.execSQL("DROP TABLE local_step_minutes");
            old.execSQL("DROP TABLE local_step_state");
            old.execSQL("ALTER TABLE daily_movement RENAME TO synthetic_new_daily");
            old.execSQL("CREATE TABLE daily_movement (day TEXT NOT NULL, zoneId TEXT NOT NULL, source TEXT NOT NULL, steps INTEGER NOT NULL, estimatedDistanceMeters REAL NOT NULL, estimatedActiveCalories REAL NOT NULL, updatedAtMillis INTEGER NOT NULL, PRIMARY KEY(day, zoneId, source))");
            old.execSQL("INSERT INTO daily_movement SELECT day, zoneId, source, steps, estimatedDistanceMeters, estimatedActiveCalories, updatedAtMillis FROM synthetic_new_daily");
            old.execSQL("DROP TABLE synthetic_new_daily");
            old.setVersion(4);
        }
        db = open();
        assertEquals("walk", db.runs().session(id).activityType);
        assertEquals(123, db.runs().dailyMovement("2026-01-01", "UTC").steps);
        assertEquals(0, db.runs().dailyMovement("2026-01-01", "UTC").modelVersion);
        db.runs().insertLocalStepState(new LocalStepState());
        assertNotNull(db.runs().localStepState());
    }

    @Test public void gpsDayQueryIncludesBoundaryAnchors() {
        long id = db.runs().start(30_000, "walk");
        for (long time : new long[]{30_000, 50_000, 90_000, 130_000, 150_000}) {
            TrackPoint point = new TrackPoint(); point.sessionId = id;
            point.timestampMillis = time; point.accepted = true;
            db.runs().insertPoint(point);
        }
        var points = db.runs().acceptedPointsForDay(id, 60_000, 120_000);
        assertEquals(3, points.size());
        assertEquals(50_000, points.get(0).timestampMillis);
        assertEquals(130_000, points.get(2).timestampMillis);
    }
}
