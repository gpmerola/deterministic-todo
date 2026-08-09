package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;

@Database(entities = {RunSession.class, TrackPoint.class}, version = 1, exportSchema = false)
public abstract class RunDatabase extends RoomDatabase {
    private static volatile RunDatabase instance;
    public abstract RunDao runs();

    public static RunDatabase get(Context context) {
        RunDatabase current = instance;
        if (current != null) return current;
        synchronized (RunDatabase.class) {
            if (instance == null) {
                instance = Room.databaseBuilder(
                    context.getApplicationContext(), RunDatabase.class, "run_tracker.sqlite"
                ).build();
            }
            return instance;
        }
    }
}
