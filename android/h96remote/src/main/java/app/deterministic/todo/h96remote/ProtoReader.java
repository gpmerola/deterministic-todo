package app.deterministic.todo.h96remote;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Minimal protobuf decoder: collects top-level fields, unknown ones are kept and ignored. */
public final class ProtoReader {
    /** One decoded field. Varints use {@code value}; length-delimited fields use {@code data}. */
    public static final class Field {
        public final int number;
        public final long value;
        public final byte[] data;

        Field(int number, long value, byte[] data) {
            this.number = number;
            this.value = value;
            this.data = data;
        }

        public String string() {
            return new String(data, StandardCharsets.UTF_8);
        }

        public ProtoReader message() throws ProtocolException {
            return new ProtoReader(data);
        }
    }

    /** Malformed or unexpected wire data. */
    public static final class ProtocolException extends Exception {
        public ProtocolException(String message) {
            super(message);
        }
    }

    private final List<Field> fields = new ArrayList<>();

    public ProtoReader(byte[] buffer) throws ProtocolException {
        int[] pos = {0};
        while (pos[0] < buffer.length) {
            long key = readVarint(buffer, pos);
            int number = (int) (key >>> 3);
            int wireType = (int) (key & 7);
            switch (wireType) {
                case 0 -> fields.add(new Field(number, readVarint(buffer, pos), null));
                case 1 -> skip(buffer, pos, 8);
                case 2 -> {
                    long length = readVarint(buffer, pos);
                    if (length < 0 || length > buffer.length - pos[0]) throw new ProtocolException("length");
                    byte[] data = new byte[(int) length];
                    System.arraycopy(buffer, pos[0], data, 0, data.length);
                    pos[0] += data.length;
                    fields.add(new Field(number, 0, data));
                }
                case 5 -> skip(buffer, pos, 4);
                default -> throw new ProtocolException("wire type " + wireType);
            }
        }
    }

    public Field first(int number) {
        for (Field field : fields) if (field.number == number) return field;
        return null;
    }

    public boolean has(int number) {
        return first(number) != null;
    }

    public long varint(int number, long fallback) {
        Field field = first(number);
        return field == null ? fallback : field.value;
    }

    public String string(int number, String fallback) {
        Field field = first(number);
        return field == null || field.data == null ? fallback : field.string();
    }

    public ProtoReader message(int number) throws ProtocolException {
        Field field = first(number);
        return field == null || field.data == null ? null : field.message();
    }

    static long readVarint(byte[] buffer, int[] pos) throws ProtocolException {
        long result = 0;
        for (int shift = 0; shift < 64; shift += 7) {
            if (pos[0] >= buffer.length) throw new ProtocolException("truncated varint");
            int b = buffer[pos[0]++] & 0xFF;
            result |= (long) (b & 0x7F) << shift;
            if ((b & 0x80) == 0) return result;
        }
        throw new ProtocolException("varint too long");
    }

    private static void skip(byte[] buffer, int[] pos, int count) throws ProtocolException {
        if (buffer.length - pos[0] < count) throw new ProtocolException("truncated");
        pos[0] += count;
    }
}
