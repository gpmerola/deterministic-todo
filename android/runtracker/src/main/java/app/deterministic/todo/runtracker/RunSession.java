package app.deterministic.todo.runtracker;

import androidx.annotation.Nullable;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

@Entity(tableName = "run_sessions")
public class RunSession {
    @PrimaryKey(autoGenerate = true) public long id;
    public long startedAtMillis;
    @Nullable public Long endedAtMillis;
    public double distanceMeters;
    public String status = "recording";
}
