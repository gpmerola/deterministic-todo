package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class DriveWriteVerificationTest {
    @Test public void rejectsAProviderThatKeptTheOldFileSize() {
        assertFalse(DriveWriteVerification.matchesSize(200, 100L));
        assertTrue(DriveWriteVerification.matchesSize(200, 200L));
    }

    @Test public void permitsProvidersWithoutImmediateSizeMetadata() {
        assertTrue(DriveWriteVerification.matchesSize(200, null));
        assertTrue(DriveWriteVerification.matchesSize(200, -1L));
    }

    @Test public void neverTreatsAZeroBytePlaceholderAsComplete() {
        assertFalse(DriveWriteVerification.completeImmutableFile(200, 0L));
        assertTrue(DriveWriteVerification.completeImmutableFile(200, 200L));
        assertTrue(DriveWriteVerification.completeImmutableFile(200, null));
    }
}
