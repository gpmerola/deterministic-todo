package app.deterministic.todo.runtracker;

import java.io.ByteArrayOutputStream;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;

/** Independent, bounded decoder for the Bip U one-minute activity stream. */
final class BipUActivityProtocol {
    static final byte START = 0x01;
    static final byte FETCH = 0x02;
    static final byte RESPONSE = 0x10;
    static final byte SUCCESS = 0x01;
    static final int SAMPLE_BYTES = 8;

    private BipUActivityProtocol() {}

    static byte[] requestSince(Instant instant, ZoneOffset offset) {
        ZonedDateTime time = instant.atZone(offset);
        int year = time.getYear();
        int quarterHours = offset.getTotalSeconds() / (15 * 60);
        return new byte[] {
            START, 0x01,
            (byte) (year & 0xff), (byte) ((year >>> 8) & 0xff),
            (byte) time.getMonthValue(), (byte) time.getDayOfMonth(),
            (byte) time.getHour(), (byte) time.getMinute(),
            0x00, (byte) quarterHours
        };
    }

    static Metadata parseMetadata(byte[] value) {
        if (value == null || value.length < 15 || value[0] != RESPONSE
            || value[1] != START || value[2] != SUCCESS) return null;
        long length = uint32(value, 3);
        int year = uint16(value[7], value[8]);
        try {
            ZoneOffset offset = ZoneOffset.ofTotalSeconds(value[14] * 15 * 60);
            long start = ZonedDateTime.of(year, value[9] & 0xff, value[10] & 0xff,
                value[11] & 0xff, value[12] & 0xff, value[13] & 0xff, 0, offset)
                .toInstant().toEpochMilli();
            return new Metadata(length, start);
        } catch (RuntimeException invalidDate) {
            return null;
        }
    }

    static boolean isFetchComplete(byte[] value) {
        return value != null && value.length >= 3 && value[0] == RESPONSE
            && value[1] == FETCH && value[2] == SUCCESS;
    }

    static List<BipUActivitySample> decode(byte[] bytes, long firstTimestamp,
                                            long importedAtMillis) {
        if (bytes == null || bytes.length % SAMPLE_BYTES != 0)
            throw new IllegalArgumentException("activity payload is not aligned");
        List<BipUActivitySample> result = new ArrayList<>(bytes.length / SAMPLE_BYTES);
        for (int offset = 0; offset < bytes.length; offset += SAMPLE_BYTES) {
            BipUActivitySample sample = new BipUActivitySample();
            sample.timestampMillis = firstTimestamp + (offset / SAMPLE_BYTES) * 60_000L;
            sample.rawKind = bytes[offset] & 0xff;
            sample.rawIntensity = bytes[offset + 1] & 0xff;
            sample.steps = bytes[offset + 2] & 0xff;
            sample.heartRate = bytes[offset + 3] & 0xff;
            sample.unknown1 = bytes[offset + 4] & 0xff;
            sample.sleep = bytes[offset + 5] & 0xff;
            sample.deepSleep = bytes[offset + 6] & 0xff;
            sample.remSleep = bytes[offset + 7] & 0xff;
            sample.importedAtMillis = importedAtMillis;
            result.add(sample);
        }
        return result;
    }

    static final class PacketBuffer {
        private final ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        private int nextCounter;

        boolean append(byte[] packet) {
            if (packet == null || packet.length < 1 || (packet[0] & 0xff) != nextCounter) return false;
            bytes.write(packet, 1, packet.length - 1);
            nextCounter = (nextCounter + 1) & 0xff;
            return true;
        }

        byte[] bytes() { return bytes.toByteArray(); }
    }

    record Metadata(long expectedBytes, long firstTimestampMillis) {}

    private static int uint16(byte low, byte high) {
        return (low & 0xff) | ((high & 0xff) << 8);
    }

    private static long uint32(byte[] value, int offset) {
        return (value[offset] & 0xffL) | ((value[offset + 1] & 0xffL) << 8)
            | ((value[offset + 2] & 0xffL) << 16) | ((value[offset + 3] & 0xffL) << 24);
    }
}
