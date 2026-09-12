package app.deterministic.todo.runtracker;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.ColumnInfo;

@Entity(tableName = "daily_movement", primaryKeys = {"day", "zoneId", "source"})
public final class DailyMovement {
    @NonNull public String day = "";
    @NonNull public String zoneId = "";
    @NonNull public String source = "health_connect_aggregate";
    public long steps;
    public double estimatedDistanceMeters;
    public double estimatedActiveCalories;
    public long updatedAtMillis;
    @ColumnInfo(defaultValue = "0") public int modelVersion;
    @ColumnInfo(defaultValue = "0") public double weightKg;
    @ColumnInfo(defaultValue = "0") public double walkingStrideMeters;
    @ColumnInfo(defaultValue = "0") public double runningStrideMeters;
}
