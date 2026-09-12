package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public final class HuamiAuthProtocolTest {
    @Test public void requestsEncryptedBipUChallenge() {
        assertArrayEquals(new byte[] {(byte) 0x82, 0x00, 0x02, 0x01, 0x00},
            HuamiAuthProtocol.requestChallenge());
    }

    @Test public void encryptsSyntheticChallengeWithoutExposingKey() throws Exception {
        byte[] response = new byte[19];
        response[0] = 0x10; response[1] = (byte) 0x82; response[2] = 0x01;
        for (int i = 0; i < 16; i++) response[i + 3] = (byte) i;
        HuamiAuthProtocol.Result result = HuamiAuthProtocol.handle(response,
            new byte[] {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15});
        assertEquals(HuamiAuthProtocol.Kind.CHALLENGE, result.kind());
        assertEquals(18, result.command().length);
        assertEquals((byte) 0x83, result.command()[0]);
        assertEquals((byte) 0x00, result.command()[1]);
    }

    @Test public void recognizesSuccessAndFailure() throws Exception {
        HuamiAuthProtocol.Result success = HuamiAuthProtocol.handle(
            new byte[] {0x10, (byte) 0x83, 0x01}, new byte[16]);
        assertEquals(HuamiAuthProtocol.Kind.AUTHENTICATED, success.kind());
        assertNull(success.command());
        assertEquals(HuamiAuthProtocol.Kind.FAILED, HuamiAuthProtocol.handle(
            new byte[] {0x10, (byte) 0x83, 0x04}, new byte[16]).kind());
    }
}
