package app.deterministic.todo.h96remote;

import java.math.BigInteger;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.interfaces.RSAPublicKey;
import java.util.Locale;

/**
 * Polo pairing secret: SHA-256 over both RSA public keys and the last four hex digits of the
 * code shown on the TV. The first byte must equal the first two digits, which lets a mistyped
 * code be rejected locally and binds the pairing to the server certificate seen in the session.
 */
public final class PairingSecret {
    private PairingSecret() {}

    /** Returns null when the code is not six hex digits. */
    public static String normalize(String code) {
        if (code == null) return null;
        String trimmed = code.trim().toUpperCase(Locale.ROOT);
        return trimmed.matches("[0-9A-F]{6}") ? trimmed : null;
    }

    /** Returns the secret, or null when the code does not match these two keys. */
    public static byte[] compute(String code, RSAPublicKey client, RSAPublicKey server) {
        return compute(code, client.getModulus(), client.getPublicExponent(),
            server.getModulus(), server.getPublicExponent());
    }

    static byte[] compute(String code, BigInteger clientModulus, BigInteger clientExponent,
                          BigInteger serverModulus, BigInteger serverExponent) {
        String normalized = normalize(code);
        if (normalized == null) return null;
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
        digest.update(unsigned(clientModulus));
        digest.update(unsigned(clientExponent));
        digest.update(unsigned(serverModulus));
        digest.update(unsigned(serverExponent));
        digest.update(hex(normalized.substring(2)));
        byte[] hash = digest.digest();
        int check = Integer.parseInt(normalized.substring(0, 2), 16);
        return (hash[0] & 0xFF) == check ? hash : null;
    }

    /** Big-endian bytes without the sign byte BigInteger adds. */
    static byte[] unsigned(BigInteger value) {
        byte[] bytes = value.toByteArray();
        if (bytes.length > 1 && bytes[0] == 0) {
            byte[] trimmed = new byte[bytes.length - 1];
            System.arraycopy(bytes, 1, trimmed, 0, trimmed.length);
            return trimmed;
        }
        return bytes;
    }

    private static byte[] hex(String digits) {
        byte[] out = new byte[digits.length() / 2];
        for (int i = 0; i < out.length; i++)
            out[i] = (byte) Integer.parseInt(digits.substring(i * 2, i * 2 + 2), 16);
        return out;
    }
}
