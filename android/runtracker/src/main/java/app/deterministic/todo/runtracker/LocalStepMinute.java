package app.deterministic.todo.runtracker;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** One complete UTC minute from the accountless on-device Recording API. */
@Entity(tableName = "local_step_minutes")
public final class LocalStepMinute {
    @PrimaryKey public long startMillis;
    public long steps;
    @NonNull public String zoneId = "UTC";
    public long importedAtMillis;
}
