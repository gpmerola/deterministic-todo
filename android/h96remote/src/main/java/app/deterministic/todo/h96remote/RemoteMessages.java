package app.deterministic.todo.h96remote;

/** Remote control messages (port 6466). Field numbers follow remotemessage.proto. */
public final class RemoteMessages {
    static final int F_CONFIGURE = 1;
    static final int F_SET_ACTIVE = 2;
    static final int F_ERROR = 3;
    static final int F_PING_REQUEST = 8;
    static final int F_PING_RESPONSE = 9;
    static final int F_KEY_INJECT = 10;
    static final int F_IME_KEY_INJECT = 20;
    static final int F_IME_BATCH_EDIT = 21;
    static final int F_IME_SHOW_REQUEST = 22;
    static final int F_START = 40;
    static final int F_SET_VOLUME_LEVEL = 50;
    static final int F_APP_LINK = 90;

    static final int FEATURE_PING = 1;
    static final int FEATURE_KEY = 1 << 1;
    static final int FEATURE_IME = 1 << 2;
    static final int FEATURE_POWER = 1 << 5;
    static final int FEATURE_VOLUME = 1 << 6;
    static final int FEATURE_APP_LINK = 1 << 9;
    /** Voice is deliberately not requested: no microphone, no audio leaves the phone. */
    static final int REQUESTED_FEATURES =
        FEATURE_PING | FEATURE_KEY | FEATURE_IME | FEATURE_POWER | FEATURE_VOLUME | FEATURE_APP_LINK;

    static final int DIRECTION_START_LONG = 1;
    static final int DIRECTION_END_LONG = 2;
    static final int DIRECTION_SHORT = 3;

    private RemoteMessages() {}

    public static byte[] configure(int features) {
        return new ProtoWriter().message(F_CONFIGURE, new ProtoWriter()
            .varint(1, features)
            .message(2, new ProtoWriter()
                .varint(3, 1)
                .string(4, "1")
                .string(5, "atvremote")
                .string(6, "1.0.0"))).toByteArray();
    }

    public static byte[] setActive(int features) {
        return new ProtoWriter().message(F_SET_ACTIVE, new ProtoWriter().varint(1, features)).toByteArray();
    }

    public static byte[] pingResponse(long value) {
        return new ProtoWriter().message(F_PING_RESPONSE, new ProtoWriter().varint(1, value)).toByteArray();
    }

    public static byte[] key(RemoteCommand command) {
        return key(command, DIRECTION_SHORT);
    }

    /** Press-and-hold: the box repeats the key itself until END_LONG, like a physical remote. */
    public static byte[] hold(RemoteCommand command, boolean start) {
        return key(command, start ? DIRECTION_START_LONG : DIRECTION_END_LONG);
    }

    private static byte[] key(RemoteCommand command, int direction) {
        return new ProtoWriter().message(F_KEY_INJECT, new ProtoWriter()
            .varint(1, command.keyCode)
            .varint(2, direction)).toByteArray();
    }

    /** Replaces the focused text field's content with {@code text}, cursor at the end. */
    public static byte[] text(String text, long imeCounter, long fieldCounter) {
        int end = text.length();
        return new ProtoWriter().message(F_IME_BATCH_EDIT, new ProtoWriter()
            .varint(1, imeCounter)
            .varint(2, fieldCounter)
            .message(3, new ProtoWriter()
                .varint(1, 1)
                .message(2, new ProtoWriter()
                    .varint(1, end)
                    .varint(2, end)
                    .string(3, text)))).toByteArray();
    }

    public static byte[] appLink(String link) {
        return new ProtoWriter().message(F_APP_LINK, new ProtoWriter().string(1, link)).toByteArray();
    }
}
