package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;
import androidx.room.migration.Migration;
import androidx.sqlite.db.SupportSQLiteDatabase;

@Database(entities = {RunSession.class, TrackPoint.class, DailyMovement.class}, version = 2, exportSchema = false)
public abstract class RunDatabase extends RoomDatabase {
    private static volatile RunDatabase instance;
    public abstract RunDao runs();

    static final Migration MIGRATION_1_2 = new Migration(1, 2) {
        @Override public void migrate(SupportSQLiteDatabase database) {
            database.execSQL("CREATE TABLE IF NOT EXISTS `daily_movement` (`day` TEXT NOT NULL, `zoneId` TEXT NOT NULL, `source` TEXT NOT NULL, `steps` INTEGER NOT NULL, `estimatedDistanceMeters` REAL NOT NULL, `estimatedActiveCalories` REAL NOT NULL, `updatedAtMillis` INTEGER NOT NULL, PRIMARY KEY(`day`, `zoneId`, `source`))");
        }
    };

    public static RunDatabase get(Context context) {
        RunDatabase current = instance;
        if (current != null) return current;
        synchronized (RunDatabase.class) {
            if (instance == null) {
                instance = Room.databaseBuilder(
                    context.getApplicationContext(), RunDatabase.class, "run_tracker.sqlite"
                ).addMigrations(MIGRATION_1_2).build();
            }
            return instance;
        }
    }
}
