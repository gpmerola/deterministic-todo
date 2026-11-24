package app.deterministic.todo.h96remote;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/** Each message on the socket is prefixed by its length as a varint. */
public final class Framing {
    /** Larger frames are rejected: real messages are a few hundred bytes. */
    static final int MAX_FRAME = 64 * 1024;

    private Framing() {}

    public static byte[] frame(byte[] payload) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(payload.length + 5);
        ProtoWriter.writeVarint(out, payload.length);
        out.write(payload, 0, payload.length);
        return out.toByteArray();
    }

    public static void write(OutputStream out, byte[] payload) throws IOException {
        out.write(frame(payload));
        out.flush();
    }

    public static byte[] read(InputStream in) throws IOException {
        int length = 0;
        for (int shift = 0; ; shift += 7) {
            if (shift > 28) throw new IOException("frame length too long");
            int b = in.read();
            if (b < 0) throw new EOFException();
            length |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
        }
        if (length < 0 || length > MAX_FRAME) throw new IOException("frame too large");
        byte[] payload = new byte[length];
        int read = 0;
        while (read < length) {
            int n = in.read(payload, read, length - read);
            if (n < 0) throw new EOFException();
            read += n;
        }
        return payload;
    }
}
