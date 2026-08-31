package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;
import androidx.room.migration.Migration;
import androidx.sqlite.db.SupportSQLiteDatabase;

@Database(entities = {RunSession.class, TrackPoint.class, DailyMovement.class,
    BipUActivitySample.class}, version = 4, exportSchema = false)
public abstract class RunDatabase extends RoomDatabase {
    private static volatile RunDatabase instance;
    public abstract RunDao runs();

    static final Migration MIGRATION_1_2 = new Migration(1, 2) {
        @Override public void migrate(SupportSQLiteDatabase database) {
            database.execSQL("CREATE TABLE IF NOT EXISTS `daily_movement` (`day` TEXT NOT NULL, `zoneId` TEXT NOT NULL, `source` TEXT NOT NULL, `steps` INTEGER NOT NULL, `estimatedDistanceMeters` REAL NOT NULL, `estimatedActiveCalories` REAL NOT NULL, `updatedAtMillis` INTEGER NOT NULL, PRIMARY KEY(`day`, `zoneId`, `source`))");
        }
    };

    static final Migration MIGRATION_2_3 = new Migration(2, 3) {
        @Override public void migrate(SupportSQLiteDatabase database) {
            database.execSQL("ALTER TABLE `run_sessions` ADD COLUMN `activityType` TEXT NOT NULL DEFAULT 'run'");
        }
    };

    static final Migration MIGRATION_3_4 = new Migration(3, 4) {
        @Override public void migrate(SupportSQLiteDatabase database) {
            database.execSQL("CREATE TABLE IF NOT EXISTS `bip_u_activity_samples` (`timestampMillis` INTEGER NOT NULL, `source` TEXT NOT NULL, `rawKind` INTEGER NOT NULL, `rawIntensity` INTEGER NOT NULL, `steps` INTEGER NOT NULL, `heartRate` INTEGER NOT NULL, `unknown1` INTEGER NOT NULL, `sleep` INTEGER NOT NULL, `deepSleep` INTEGER NOT NULL, `remSleep` INTEGER NOT NULL, `importedAtMillis` INTEGER NOT NULL, PRIMARY KEY(`timestampMillis`, `source`))");
        }
    };

    public static RunDatabase get(Context context) {
        RunDatabase current = instance;
        if (current != null) return current;
        synchronized (RunDatabase.class) {
            if (instance == null) {
                instance = Room.databaseBuilder(
                    context.getApplicationContext(), RunDatabase.class, "run_tracker.sqlite"
                ).addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4).build();
            }
            return instance;
        }
    }
}
