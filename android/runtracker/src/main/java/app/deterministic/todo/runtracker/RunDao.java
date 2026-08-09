package app.deterministic.todo.runtracker;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.Query;
import androidx.room.Transaction;

import java.util.List;

@Dao
public interface RunDao {
    @Insert long insertSession(RunSession session);
    @Insert long insertPoint(TrackPoint point);

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
    default long start(long startedAt) {
        RunSession session = new RunSession();
        session.startedAtMillis = startedAt;
        return insertSession(session);
    }
}
