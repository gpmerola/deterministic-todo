package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;
import org.junit.Test;
import java.util.HashMap;
import java.util.Map;

public final class AgendaCopyOperationTest {
    @Test public void retryAfterUncertainInsertUpdatesTheSameCopy() {
        Map<String, String> events = new HashMap<>();
        int[] inserts = {0}, updates = {0};
        AgendaCopyOperation.Store store = new AgendaCopyOperation.Store() {
            public String find(String key) { return events.get(key); }
            public String insert() {
                inserts[0]++;
                events.put("source", "copy-1");
                throw new IllegalStateException("Synthetic lost result after durable insert");
            }
            public void update(String id) { assertEquals("copy-1", id); updates[0]++; }
        };
        try { AgendaCopyOperation.apply("source", store); fail(); }
        catch (IllegalStateException expected) { /* Simulated process/result loss. */ }
        assertEquals("copy-1", AgendaCopyOperation.apply("source", store));
        assertEquals(1, inserts[0]);
        assertEquals(1, updates[0]);
        assertEquals(1, events.size());
    }
    @Test public void failedUpdateNeverFallsBackToAnInsert() {
        int[] inserts = {0};
        AgendaCopyOperation.Store store = new AgendaCopyOperation.Store() {
            public String find(String key) { return "existing"; }
            public String insert() { inserts[0]++; return "unexpected"; }
            public void update(String id) { throw new IllegalStateException("Synthetic provider failure"); }
        };
        try { AgendaCopyOperation.apply("source", store); fail(); }
        catch (IllegalStateException expected) { }
        assertEquals(0, inserts[0]);
    }
}
