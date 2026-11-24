package app.deterministic.todo.h96remote;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.math.BigInteger;

import org.junit.Test;

/** Expected bytes were produced by the reference protobuf schema (androidtvremote2). */
public class MessagesTest {
    @Test public void pairingMessagesMatchReferenceEncoding() {
        assertEquals("080210c80152110a0961747672656d6f74651204546f646f", Hex.of(PairingMessages.pairingRequest("Todo")));
        assertEquals("080210c801a201080a04080310061801", Hex.of(PairingMessages.options()));
        assertEquals("080210c801f201080a04080310061001", Hex.of(PairingMessages.configuration()));
    }

    @Test public void remoteMessagesMatchReferenceEncoding() {
        assertEquals("520408171003", Hex.of(RemoteMessages.key(RemoteCommand.OK)));
        assertEquals("0a1c08e704121718012201312a0961747672656d6f74653205312e302e30", Hex.of(RemoteMessages.configure(615)));
        assertEquals("4a02082a", Hex.of(RemoteMessages.pingResponse(42)));
        assertEquals("aa011a080510071a1408011210080710071a0a43697474c3a020e282ac",
            Hex.of(RemoteMessages.text("Città €", 5, 7)));
    }

    @Test public void requestedFeaturesExcludeVoice() {
        assertEquals(615, RemoteMessages.REQUESTED_FEATURES);
        assertEquals(0, RemoteMessages.REQUESTED_FEATURES & (1 << 3));
    }

    @Test public void protocolAnswersHandshakeAndPing() throws Exception {
        RemoteProtocol protocol = new RemoteProtocol();
        // The box supports 1023; we keep only what we asked for.
        assertEquals("0a1c08e704121718012201312a0961747672656d6f74653205312e302e30",
            Hex.of(protocol.handle(Hex.parse("0a0a08ff0712050a03483936"))));
        assertEquals("H96", protocol.deviceModel());
        assertEquals("120308e704", Hex.of(protocol.handle(Hex.parse("1200"))));
        assertEquals("4a02082a", Hex.of(protocol.handle(Hex.parse("4202082a"))));
        assertFalse(protocol.started());
        assertNull(protocol.handle(Hex.parse("c202020801")));
        assertTrue(protocol.started());
    }

    @Test public void protocolTracksVolumeAndImeCounters() throws Exception {
        RemoteProtocol protocol = new RemoteProtocol();
        protocol.handle(Hex.parse("920306300f38034001"));
        assertEquals(3, protocol.volume().level);
        assertEquals(15, protocol.volume().max);
        assertTrue(protocol.volume().muted);
        protocol.handle(Hex.parse("a2010f0a0908096205636f6d2e7812020804"));
        assertTrue(protocol.textFieldFocused());
        assertArrayEquals(RemoteMessages.text("x", 9, 4), protocol.text("x"));
    }

    @Test public void framingRoundTripsAndRejectsHugeFrames() throws IOException {
        byte[] payload = new byte[300];
        payload[299] = 7;
        byte[] framed = Framing.frame(payload);
        assertEquals((byte) 0xAC, framed[0]);
        assertEquals(0x02, framed[1]);
        assertArrayEquals(payload, Framing.read(new ByteArrayInputStream(framed)));
        try {
            Framing.read(new ByteArrayInputStream(Hex.parse("ffffffff0f")));
            throw new AssertionError("expected rejection");
        } catch (IOException expected) {
            // Rejected.
        }
    }

    @Test(expected = ProtoReader.ProtocolException.class)
    public void readerRejectsTruncatedData() throws Exception {
        new ProtoReader(Hex.parse("0a05"));
    }

    @Test public void pairingSecretMatchesReferenceAndChecksFirstByte() {
        BigInteger cm = BigInteger.ONE.shiftLeft(2047).add(BigInteger.valueOf(12345));
        BigInteger sm = BigInteger.ONE.shiftLeft(2047).add(BigInteger.valueOf(67890));
        BigInteger e = BigInteger.valueOf(65537);
        assertEquals("4f8d3ab4de2827dc77a9cf61967674d3e6da4d58265178d6686787b50d0e4b39",
            Hex.of(PairingSecret.compute("4f1234", cm, e, sm, e)));
        assertNull(PairingSecret.compute("4E1234", cm, e, sm, e));
        assertNull(PairingSecret.compute("4F12", cm, e, sm, e));
        assertNull(PairingSecret.compute("ZZ1234", cm, e, sm, e));
    }

    @Test public void onlyLanAddressesAreAccepted() {
        assertTrue(LanAddress.isPrivate("192.168.1.50"));
        assertTrue(LanAddress.isPrivate("10.0.0.2"));
        assertTrue(LanAddress.isPrivate("172.20.1.1"));
        assertTrue(LanAddress.isPrivate("fe80::1%wlan0"));
        assertFalse(LanAddress.isPrivate("8.8.8.8"));
        assertFalse(LanAddress.isPrivate("172.32.0.1"));
        assertFalse(LanAddress.isPrivate("192.168.1.300"));
        assertFalse(LanAddress.isPrivate("tv.example.com"));
        assertFalse(LanAddress.isPrivate(null));
    }

    @Test public void commandsParseCaseInsensitively() {
        assertEquals(RemoteCommand.VOLUME_UP, RemoteCommand.parse("volume_up"));
        assertNull(RemoteCommand.parse("reboot"));
        assertNull(RemoteCommand.parse(null));
    }
}
