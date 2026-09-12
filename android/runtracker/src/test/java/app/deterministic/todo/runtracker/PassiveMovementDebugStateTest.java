package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.time.LocalDateTime;

public final class PassiveMovementDebugStateTest {
    @Test public void snapshotNameUsesImmutableCivilHourBucket() {
        assertEquals("movement_snapshot_2026-08-17_21.json",
            PassiveMovementDebugState.snapshotFileName(
                LocalDateTime.of(2026, 8, 17, 21, 59, 59)));
    }
}
