package app.deterministic.todo.runtracker;

import androidx.annotation.NonNull;
import androidx.room.Entity;

/** Immutable one-minute activity sample fetched from the user's Bip U. */
@Entity(tableName = "bip_u_activity_samples", primaryKeys = {"timestampMillis", "source"})
public class BipUActivitySample {
    public long timestampMillis;
    @NonNull public String source = "bip_u";
    public int rawKind;
    public int rawIntensity;
    public int steps;
    public int heartRate;
    public int unknown1;
    public int sleep;
    public int deepSleep;
    public int remSleep;
    public long importedAtMillis;
}
