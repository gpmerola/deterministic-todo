package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

import java.io.ByteArrayInputStream;

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

    @Test public void acceptsAnAmbiguousRenameOnlyAfterFinalVerification() {
        assertTrue(DriveWriteVerification.renameCompleted(true, false));
        assertTrue(DriveWriteVerification.renameCompleted(false, true));
        assertFalse(DriveWriteVerification.renameCompleted(false, false));
        assertTrue(DriveWriteVerification.verifiedFinalFile(200, 200L));
        assertFalse(DriveWriteVerification.verifiedFinalFile(200, null));
        assertFalse(DriveWriteVerification.verifiedFinalFile(200, 0L));
    }

    @Test public void exactReadbackRejectsStaleContentEvenWithTheSameSize() throws Exception {
        byte[] expected = "new-bundle".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        assertTrue(DriveTestExportManager.contentEquals(
            new ByteArrayInputStream(expected), expected));
        assertFalse(DriveTestExportManager.contentEquals(
            new ByteArrayInputStream("old-bundle".getBytes(
                java.nio.charset.StandardCharsets.UTF_8)), expected));
        assertFalse(DriveTestExportManager.contentEquals(
            new ByteArrayInputStream("new-bundle-extra".getBytes(
                java.nio.charset.StandardCharsets.UTF_8)), expected));
    }
}
