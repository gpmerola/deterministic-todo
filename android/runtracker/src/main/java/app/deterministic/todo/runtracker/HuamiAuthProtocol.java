package app.deterministic.todo.runtracker;

import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

/** Pure Huami Bip U challenge-response framing. Contains no device or key persistence. */
final class HuamiAuthProtocol {
    private static final int RESPONSE = 0x10;
    private static final int RANDOM = 0x02;
    private static final int ENCRYPTED = 0x03;
    private static final int SUCCESS = 0x01;
    private static final int CRYPT_FLAG = 0x80;

    enum Kind { CHALLENGE, AUTHENTICATED, FAILED, IGNORED }
    record Result(Kind kind, byte[] command) {}

    private HuamiAuthProtocol() {}

    static byte[] requestChallenge() {
        return new byte[] {(byte) (CRYPT_FLAG | RANDOM), 0x00, 0x02, 0x01, 0x00};
    }

    static Result handle(byte[] value, byte[] key) throws Exception {
        if (value == null || value.length < 3 || (value[0] & 0xff) != RESPONSE)
            return new Result(Kind.IGNORED, null);
        int operation = value[1] & 0x0f;
        if ((value[2] & 0xff) != SUCCESS) return new Result(Kind.FAILED, null);
        if (operation == RANDOM) {
            if (value.length < 19 || key == null || key.length != 16)
                return new Result(Kind.FAILED, null);
            Cipher cipher = Cipher.getInstance("AES/ECB/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"));
            byte[] encrypted = cipher.doFinal(Arrays.copyOfRange(value, 3, 19));
            byte[] command = new byte[18];
            command[0] = (byte) (CRYPT_FLAG | ENCRYPTED);
            command[1] = 0x00;
            System.arraycopy(encrypted, 0, command, 2, encrypted.length);
            return new Result(Kind.CHALLENGE, command);
        }
        if (operation == ENCRYPTED) return new Result(Kind.AUTHENTICATED, null);
        return new Result(Kind.IGNORED, null);
    }
}
