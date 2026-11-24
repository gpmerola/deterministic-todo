package app.deterministic.todo.h96remote;

/** Polo pairing messages (port 6467). Field numbers follow polo.proto. */
public final class PairingMessages {
    static final int STATUS_OK = 200;
    static final int STATUS_BAD_SECRET = 402;
    static final int ENCODING_HEXADECIMAL = 3;
    static final int ROLE_INPUT = 1;
    static final int SYMBOL_LENGTH = 6;

    static final int F_STATUS = 2;
    static final int F_PAIRING_REQUEST = 10;
    static final int F_PAIRING_REQUEST_ACK = 11;
    static final int F_OPTIONS = 20;
    static final int F_CONFIGURATION = 30;
    static final int F_CONFIGURATION_ACK = 31;
    static final int F_SECRET = 40;
    static final int F_SECRET_ACK = 41;

    private PairingMessages() {}

    public static byte[] pairingRequest(String clientName) {
        return outer().message(F_PAIRING_REQUEST, new ProtoWriter()
            .string(1, "atvremote")
            .string(2, clientName)).toByteArray();
    }

    public static byte[] options() {
        return outer().message(F_OPTIONS, new ProtoWriter()
            .message(1, hexEncoding())
            .varint(3, ROLE_INPUT)).toByteArray();
    }

    public static byte[] configuration() {
        return outer().message(F_CONFIGURATION, new ProtoWriter()
            .message(1, hexEncoding())
            .varint(2, ROLE_INPUT)).toByteArray();
    }

    public static byte[] secret(byte[] secret) {
        return outer().message(F_SECRET, new ProtoWriter().bytes(1, secret)).toByteArray();
    }

    private static ProtoWriter outer() {
        return new ProtoWriter().varint(1, 2).varint(F_STATUS, STATUS_OK);
    }

    private static ProtoWriter hexEncoding() {
        return new ProtoWriter().varint(1, ENCODING_HEXADECIMAL).varint(2, SYMBOL_LENGTH);
    }
}
