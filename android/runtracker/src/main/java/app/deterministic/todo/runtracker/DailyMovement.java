package app.deterministic.todo.runtracker;

import androidx.annotation.NonNull;
import androidx.room.Entity;

@Entity(tableName = "daily_movement", primaryKeys = {"day", "zoneId", "source"})
public final class DailyMovement {
    @NonNull public String day = "";
    @NonNull public String zoneId = "";
    @NonNull public String source = "health_connect_aggregate";
    public long steps;
    public double estimatedDistanceMeters;
    public double estimatedActiveCalories;
    public long updatedAtMillis;
}
