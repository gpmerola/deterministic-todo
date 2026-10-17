package app.deterministic.todo.runtracker;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Transaction;

import java.util.List;

@Dao
public interface RunDao {
    @Query("SELECT * FROM local_step_state WHERE id = 1")
    LocalStepState localStepState();

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    void insertLocalStepState(LocalStepState state);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void replaceLocalStepMinutes(List<LocalStepMinute> minutes);

    @Query("UPDATE local_step_state SET importedThroughMillis = MAX(importedThroughMillis, :end) WHERE id = 1")
    void markLocalStepsImported(long end);

    @Transaction
    default void importLocalStepMinutes(List<LocalStepMinute> minutes, long end) {
        replaceLocalStepMinutes(minutes);
        markLocalStepsImported(end);
    }

    @Query("SELECT COALESCE(SUM(steps), 0) FROM local_step_minutes WHERE startMillis >= :start AND startMillis < :end")
    long localSteps(long start, long end);

    @Query("SELECT * FROM local_step_minutes WHERE startMillis >= :start AND startMillis < :end ORDER BY startMillis")
    List<LocalStepMinute> localStepMinutes(long start, long end);
}
