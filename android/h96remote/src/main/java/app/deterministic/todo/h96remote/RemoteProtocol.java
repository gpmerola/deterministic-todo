package app.deterministic.todo.h96remote;

/**
 * Pure handler for incoming remote messages: answers the handshake and pings and keeps the
 * little state the UI needs. It never sees or stores typed text from the TV.
 */
public final class RemoteProtocol {
    /** Volume as reported by the box; level -1 means unknown. */
    public static final class Volume {
        public final int level;
        public final int max;
        public final boolean muted;

        Volume(int level, int max, boolean muted) {
            this.level = level;
            this.max = max;
            this.muted = muted;
        }
    }

    private int activeFeatures = RemoteMessages.REQUESTED_FEATURES;
    private boolean started;
    private Volume volume = new Volume(-1, 0, false);
    private String deviceModel = "";
    private long imeCounter;
    private long fieldCounter;
    private boolean hasImeCounter;
    private boolean hasFieldCounter;
    private boolean textFieldFocused;

    public boolean started() { return started; }
    public Volume volume() { return volume; }
    public String deviceModel() { return deviceModel; }
    public boolean textFieldFocused() { return textFieldFocused; }

    /** Handles one incoming payload; returns the reply to send, or null. */
    public byte[] handle(byte[] payload) throws ProtoReader.ProtocolException {
        ProtoReader message = new ProtoReader(payload);
        ProtoReader body;
        if ((body = message.message(RemoteMessages.F_CONFIGURE)) != null) {
            activeFeatures &= (int) body.varint(1, 0);
            ProtoReader info = body.message(2);
            if (info != null) deviceModel = info.string(1, "");
            return RemoteMessages.configure(activeFeatures);
        }
        if (message.has(RemoteMessages.F_SET_ACTIVE)) return RemoteMessages.setActive(activeFeatures);
        if ((body = message.message(RemoteMessages.F_PING_REQUEST)) != null)
            return RemoteMessages.pingResponse(body.varint(1, 0));
        if ((body = message.message(RemoteMessages.F_START)) != null) {
            started = body.varint(1, 0) != 0 || !body.has(1);
            return null;
        }
        if ((body = message.message(RemoteMessages.F_SET_VOLUME_LEVEL)) != null) {
            volume = new Volume((int) body.varint(7, -1), (int) body.varint(6, 0), body.varint(8, 0) != 0);
            return null;
        }
        if ((body = message.message(RemoteMessages.F_IME_KEY_INJECT)) != null) {
            ProtoReader app = body.message(1);
            ProtoReader field = body.message(2);
            imeCounter = app == null ? 0 : app.varint(1, 0);
            fieldCounter = field == null ? 0 : field.varint(1, 0);
            hasImeCounter = imeCounter != 0;
            hasFieldCounter = fieldCounter != 0;
            textFieldFocused = field != null;
            return null;
        }
        if ((body = message.message(RemoteMessages.F_IME_SHOW_REQUEST)) != null) {
            ProtoReader field = body.message(2);
            if (field != null) {
                fieldCounter = field.varint(1, 0);
                hasFieldCounter = true;
                textFieldFocused = true;
            }
            return null;
        }
        if ((body = message.message(RemoteMessages.F_IME_BATCH_EDIT)) != null) {
            if (!hasImeCounter) imeCounter = body.varint(1, 0);
            if (!hasFieldCounter) fieldCounter = body.varint(2, 0);
            return null;
        }
        return null;
    }

    public byte[] text(String text) {
        return RemoteMessages.text(text, imeCounter, fieldCounter);
    }
}
