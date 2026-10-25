package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import org.junit.Test;

public final class DownloadedApkCleanupTest {
    private static File file(File dir, String name, int bytes) throws IOException {
        File file = new File(dir, name);
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(new byte[bytes]);
        }
        return file;
    }

    @Test public void removesOnlyInstalledOrOlderUpdaterApks() throws IOException {
        File dir = Files.createTempDirectory("ota").toFile();
        File older = file(dir, "deterministic-todo-2.119.0-306.apk", 10);
        File installed = file(dir, "deterministic-todo-2.120.1-308.apk", 20);
        File pending = file(dir, "deterministic-todo-2.121.0-309.apk", 40);
        File unknown = file(dir, "ota_update.apk", 80);
        File other = file(dir, "notes.txt", 5);
        File legacy = file(dir, "deterministic-todo-2.13.2.apk", 7);

        DownloadedApkCleanup.Result result = DownloadedApkCleanup.clean(dir, 308);

        assertFalse(older.exists());
        assertFalse(installed.exists());
        assertTrue(pending.exists());
        assertTrue(unknown.exists());
        assertTrue(other.exists());
        assertFalse(legacy.exists());
        assertEquals(3, result.deletedFiles);
        assertEquals(37, result.deletedBytes);
        assertEquals(2, result.remainingFiles);
        assertEquals(120, result.remainingBytes);
        assertArrayEquals(new long[] {2, 120}, DownloadedApkCleanup.usage(dir));
        // A second run is a no-op.
        assertEquals(0, DownloadedApkCleanup.clean(dir, 308).deletedFiles);
    }

    @Test public void todoTestUsesTheLogicalBuildOfTheFileNames() {
        assertEquals(308, DownloadedApkCleanup.logicalBuild(2308, "app.x.dev"));
        assertEquals(308, DownloadedApkCleanup.logicalBuild(2308, "app.x.dev.validation"));
        assertEquals(308, DownloadedApkCleanup.logicalBuild(308, "app.x"));
        assertEquals(150, DownloadedApkCleanup.logicalBuild(150, "app.x.dev"));
    }

    @Test public void missingDirectoryIsEmpty() {
        File dir = new File(System.getProperty("java.io.tmpdir"), "ota-missing-" + System.nanoTime());
        assertEquals(0, DownloadedApkCleanup.clean(dir, 5).deletedFiles);
        assertArrayEquals(new long[] {0, 0}, DownloadedApkCleanup.usage(dir));
    }

    @Test public void parsesBuildOnlyFromUpdaterNames() {
        assertEquals(Long.valueOf(308), DownloadedApkCleanup.build("deterministic-todo-2.120.1-308.apk"));
        assertNull(DownloadedApkCleanup.build("deterministic-todo-2.120.1-308.apk.part"));
        assertNull(DownloadedApkCleanup.build("other-2.120.1-308.apk"));
        assertNull(DownloadedApkCleanup.build("deterministic-todo-2.13.2.apk"));
        assertTrue(DownloadedApkCleanup.isLegacy("deterministic-todo-2.13.2.apk"));
        assertFalse(DownloadedApkCleanup.isLegacy("deterministic-todo-2.120.1-308.apk"));
    }
}
