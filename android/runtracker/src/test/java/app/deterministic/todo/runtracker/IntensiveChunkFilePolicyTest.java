package app.deterministic.todo.runtracker;

import org.junit.Test;

import java.io.File;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class IntensiveChunkFilePolicyTest {
    @Test public void completedChunkKeepsImmutableJsonlName() {
        assertEquals("intensive_exp_segment_123.jsonl",
            IntensiveChunkFilePolicy.completedName("intensive_exp_segment_123.jsonl.active"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesUnexpectedActiveName() {
        IntensiveChunkFilePolicy.completedName("unrelated.tmp");
    }

    @Test public void collisionGetsDeterministicSuffix() throws Exception {
        File directory = Files.createTempDirectory("intensive-policy").toFile();
        String first = IntensiveChunkFilePolicy.uniqueActiveName(directory, "exp", "segment", 123);
        File completed = new File(directory, IntensiveChunkFilePolicy.completedName(first));
        if (!completed.createNewFile()) throw new IllegalStateException("fixture_failed");
        String second = IntensiveChunkFilePolicy.uniqueActiveName(directory, "exp", "segment", 123);
        assertNotEquals(first, second);
        assertEquals("intensive_exp_segment_123_1.jsonl.active", second);
    }

    @Test public void completionRenamesWithoutDeletingData() throws Exception {
        File directory = Files.createTempDirectory("intensive-complete").toFile();
        File active = new File(directory, "intensive_exp_segment_123.jsonl.active");
        Files.write(active.toPath(), "evidence\n".getBytes(StandardCharsets.UTF_8));
        assertTrue(IntensiveChunkFilePolicy.complete(active));
        File completed = new File(directory, "intensive_exp_segment_123.jsonl");
        assertTrue(completed.isFile());
        assertEquals("evidence\n", new String(Files.readAllBytes(completed.toPath()),
            StandardCharsets.UTF_8));
        assertFalse(active.exists());
    }
}
