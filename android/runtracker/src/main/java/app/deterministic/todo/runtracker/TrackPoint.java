package app.deterministic.todo.runtracker;

import androidx.annotation.Nullable;
import androidx.room.Entity;
import androidx.room.ForeignKey;
import androidx.room.Index;
import androidx.room.PrimaryKey;

@Entity(
    tableName = "track_points",
    foreignKeys = @ForeignKey(
        entity = RunSession.class,
        parentColumns = "id",
        childColumns = "sessionId",
        onDelete = ForeignKey.CASCADE
    ),
    indices = {@Index("sessionId"), @Index(value = {"sessionId", "timestampMillis"})}
)
public class TrackPoint {
    @PrimaryKey(autoGenerate = true) public long id;
    public long sessionId;
    public long timestampMillis;
    public double latitude;
    public double longitude;
    public float accuracyMeters;
    public boolean accepted;
    @Nullable public String rejectionReason;
    public double accumulatedDistanceMeters;
}
