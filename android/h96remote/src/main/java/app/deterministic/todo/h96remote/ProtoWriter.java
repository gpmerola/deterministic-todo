package app.deterministic.todo.h96remote;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/** Minimal protobuf encoder: only the wire types the Android TV Remote v2 protocol uses. */
public final class ProtoWriter {
    private final ByteArrayOutputStream out = new ByteArrayOutputStream();

    public ProtoWriter varint(int field, long value) {
        tag(field, 0);
        writeVarint(out, value);
        return this;
    }

    public ProtoWriter bool(int field, boolean value) {
        return varint(field, value ? 1 : 0);
    }

    public ProtoWriter bytes(int field, byte[] value) {
        tag(field, 2);
        writeVarint(out, value.length);
        out.write(value, 0, value.length);
        return this;
    }

    public ProtoWriter string(int field, String value) {
        return bytes(field, value.getBytes(StandardCharsets.UTF_8));
    }

    public ProtoWriter message(int field, ProtoWriter nested) {
        return bytes(field, nested.toByteArray());
    }

    public byte[] toByteArray() {
        return out.toByteArray();
    }

    private void tag(int field, int wireType) {
        writeVarint(out, ((long) field << 3) | wireType);
    }

    static void writeVarint(ByteArrayOutputStream out, long value) {
        // Negative int32 values are sign extended to ten bytes, as protobuf does.
        while ((value & ~0x7FL) != 0) {
            out.write((int) ((value & 0x7F) | 0x80));
            value >>>= 7;
        }
        out.write((int) value);
    }
}
