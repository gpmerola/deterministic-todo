package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class SecureAuthKeyStoreTest {
    @Test public void acceptsExactlySixteenBytesOfHex() {
        assertEquals(16, SecureAuthKeyStore.parseHex("00112233445566778899aabbccddeeff").length);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsMalformedKey() { SecureAuthKeyStore.parseHex("not-a-key"); }
}
