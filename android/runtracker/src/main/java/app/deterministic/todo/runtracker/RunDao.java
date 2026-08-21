package app.deterministic.todo.runtracker;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import androidx.room.Transaction;

import java.util.List;

@Dao
public interface RunDao {
    @Insert long insertSession(RunSession session);
    @Insert long insertPoint(TrackPoint point);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void upsertDailyMovement(DailyMovement movement);

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    List<Long> insertBipUActivitySamples(List<BipUActivitySample> samples);

    @Query("SELECT * FROM bip_u_activity_samples WHERE timestampMillis >= :startMillis AND timestampMillis < :endMillis ORDER BY timestampMillis")
    List<BipUActivitySample> bipUSamples(long startMillis, long endMillis);

    @Query("SELECT MAX(timestampMillis) FROM bip_u_activity_samples")
    Long latestBipUSampleTimestamp();

    @Query("SELECT * FROM daily_movement WHERE day = :day AND zoneId = :zoneId ORDER BY updatedAtMillis DESC LIMIT 1")
    DailyMovement dailyMovement(String day, String zoneId);

    @Query("SELECT * FROM run_sessions ORDER BY startedAtMillis DESC")
    List<RunSession> sessions();

    @Query("SELECT * FROM run_sessions WHERE status = 'recording' ORDER BY startedAtMillis DESC LIMIT 1")
    RunSession activeSession();

    @Query("SELECT * FROM run_sessions WHERE id = :id LIMIT 1")
    RunSession session(long id);

    @Query("SELECT * FROM track_points WHERE sessionId = :sessionId ORDER BY timestampMillis, id")
    List<TrackPoint> points(long sessionId);

    @Query("UPDATE run_sessions SET distanceMeters = :distance WHERE id = :id")
    void updateDistance(long id, double distance);

    @Query("UPDATE run_sessions SET distanceMeters = :distance, endedAtMillis = :endedAt, status = 'finished' WHERE id = :id")
    void finish(long id, double distance, long endedAt);

    @Transaction
    default long start(long startedAt, String activityType) {
        RunSession session = new RunSession();
        session.startedAtMillis = startedAt;
        session.activityType = activityType;
        return insertSession(session);
    }
}
