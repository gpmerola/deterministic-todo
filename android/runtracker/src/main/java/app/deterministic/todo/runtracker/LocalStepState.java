package app.deterministic.todo.runtracker;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** Durable cutover; legacy steps and Recording API intervals never overlap. */
@Entity(tableName = "local_step_state")
public final class LocalStepState {
    @PrimaryKey public int id = 1;
    public long startMillis;
    public long importedThroughMillis;
    @NonNull public String legacyDay = "";
    @NonNull public String legacyZoneId = "";
    public long legacySteps;
}
