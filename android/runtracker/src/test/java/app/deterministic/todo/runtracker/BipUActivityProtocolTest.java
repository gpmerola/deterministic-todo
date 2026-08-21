package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

public class BipUActivityProtocolTest {
    @Test public void requestEncodesMinuteAndOffsetDeterministically() {
        byte[] request = BipUActivityProtocol.requestSince(
            Instant.parse("2026-08-21T10:34:56Z"), ZoneOffset.ofHours(2));
        assertArrayEquals(new byte[] {1, 1, (byte) 0xea, 0x07, 8, 21, 12, 34, 0, 8}, request);
    }

    @Test public void metadataAndEightByteSamplesKeepOriginalTimeline() {
        byte[] metadata = new byte[] {0x10, 1, 1, 16, 0, 0, 0,
            (byte) 0xea, 0x07, 8, 21, 12, 34, 0, 8};
        BipUActivityProtocol.Metadata parsed = BipUActivityProtocol.parseMetadata(metadata);
        assertNotNull(parsed);
        assertEquals(16, parsed.expectedBytes());
        assertEquals(Instant.parse("2026-08-21T10:34:00Z").toEpochMilli(),
            parsed.firstTimestampMillis());

        List<BipUActivitySample> samples = BipUActivityProtocol.decode(new byte[] {
            1, 2, 3, 70, 5, 6, 7, 8,
            9, 10, 11, 72, 13, 14, 15, 16
        }, parsed.firstTimestampMillis(), 1234);
        assertEquals(2, samples.size());
        assertEquals(3, samples.get(0).steps);
        assertEquals(70, samples.get(0).heartRate);
        assertEquals(parsed.firstTimestampMillis() + 60_000, samples.get(1).timestampMillis);
    }

    @Test public void packetBufferRejectsGapsAndDoesNotAppendThem() {
        BipUActivityProtocol.PacketBuffer buffer = new BipUActivityProtocol.PacketBuffer();
        assertTrue(buffer.append(new byte[] {0, 1, 2}));
        assertFalse(buffer.append(new byte[] {2, 9}));
        assertTrue(buffer.append(new byte[] {1, 3}));
        assertArrayEquals(new byte[] {1, 2, 3}, buffer.bytes());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnalignedPayload() {
        BipUActivityProtocol.decode(new byte[] {1, 2, 3}, 0, 0);
    }

    @Test public void bipUCanAnnounceSamplesRatherThanPayloadBytes() {
        long announced = 1440;
        int payloadBytes = 11520;
        assertEquals(payloadBytes, announced * BipUActivityProtocol.SAMPLE_BYTES);
    }
}
