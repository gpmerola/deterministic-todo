package app.deterministic.todo.runtracker;

/** Parser for the Bluetooth SIG Heart Rate Measurement value. */
final class HeartRateMeasurementParser {
    private HeartRateMeasurementParser() {}

    static Integer parse(byte[] value) {
        if (value == null || value.length < 2) return null;
        int flags = value[0] & 0xff;
        int bpm;
        if ((flags & 0x01) == 0) bpm = value[1] & 0xff;
        else {
            if (value.length < 3) return null;
            bpm = (value[1] & 0xff) | ((value[2] & 0xff) << 8);
        }
        return bpm >= 20 && bpm <= 250 ? bpm : null;
    }
}
