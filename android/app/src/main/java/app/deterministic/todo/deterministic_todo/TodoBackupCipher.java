package app.deterministic.todo.deterministic_todo;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Automatic Todo backup file:
 * "TDB2" + 8-byte key id + 12-byte IV + AES-256-GCM(gzip(JSON 2)).
 * The 24-byte header is authenticated as AAD. The 256-bit data key is random
 * and is shown once to the user as a 52-character recovery code (Crockford
 * base32), the only way to read a backup on another installation.
 */
final class TodoBackupCipher {
    static final byte[] MAGIC = "TDB2".getBytes(StandardCharsets.US_ASCII);
    static final int KEY_BYTES = 32;
    private static final int ID_BYTES = 8;
    private static final int IV_BYTES = 12;
    private static final int HEADER = 4 + ID_BYTES + IV_BYTES;
    private static final int TAG_BITS = 128;
    private static final String ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    /** Wrong recovery code or a file made with another key. */
    static final class KeyMismatchException extends GeneralSecurityException {
        KeyMismatchException() {
            super("Backup made with another key");
        }
    }

    static final class InvalidCodeException extends GeneralSecurityException {
        InvalidCodeException() {
            super("Invalid recovery code");
        }
    }

    private TodoBackupCipher() {}

    static byte[] keyId(byte[] dataKey) throws GeneralSecurityException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        digest.update("todo-backup-v2".getBytes(StandardCharsets.US_ASCII));
        return Arrays.copyOf(digest.digest(dataKey), ID_BYTES);
    }

    static byte[] encrypt(byte[] dataKey, byte[] plain, byte[] iv) throws GeneralSecurityException, IOException {
        if (dataKey.length != KEY_BYTES || iv.length != IV_BYTES) throw new GeneralSecurityException("Invalid key or IV");
        ByteArrayOutputStream packed = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(packed)) {
            gzip.write(plain);
        }
        byte[] header = new byte[HEADER];
        System.arraycopy(MAGIC, 0, header, 0, 4);
        System.arraycopy(keyId(dataKey), 0, header, 4, ID_BYTES);
        System.arraycopy(iv, 0, header, 4 + ID_BYTES, IV_BYTES);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(dataKey, "AES"), new GCMParameterSpec(TAG_BITS, iv));
        cipher.updateAAD(header);
        byte[] sealed = cipher.doFinal(packed.toByteArray());
        byte[] out = Arrays.copyOf(header, HEADER + sealed.length);
        System.arraycopy(sealed, 0, out, HEADER, sealed.length);
        return out;
    }

    static boolean isBackup(byte[] file) {
        return file.length >= HEADER + TAG_BITS / 8 && Arrays.equals(Arrays.copyOf(file, 4), MAGIC);
    }

    static byte[] decrypt(byte[] dataKey, byte[] file) throws GeneralSecurityException, IOException {
        if (!isBackup(file)) throw new GeneralSecurityException("Not a Todo backup");
        if (!MessageDigest.isEqual(keyId(dataKey), Arrays.copyOfRange(file, 4, 4 + ID_BYTES))) {
            throw new KeyMismatchException();
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(dataKey, "AES"),
            new GCMParameterSpec(TAG_BITS, Arrays.copyOfRange(file, 4 + ID_BYTES, HEADER)));
        cipher.updateAAD(file, 0, HEADER);
        byte[] packed = cipher.doFinal(file, HEADER, file.length - HEADER);
        ByteArrayOutputStream plain = new ByteArrayOutputStream();
        try (GZIPInputStream gzip = new GZIPInputStream(new ByteArrayInputStream(packed))) {
            byte[] buffer = new byte[16384];
            for (int n; (n = gzip.read(buffer)) > 0; ) plain.write(buffer, 0, n);
        }
        return plain.toByteArray();
    }

    /** 52 Crockford base32 characters in groups of four. */
    static String recoveryCode(byte[] dataKey) {
        StringBuilder out = new StringBuilder();
        int buffer = 0;
        int bits = 0;
        int chars = 0;
        for (int i = 0; i <= dataKey.length; i++) {
            if (i < dataKey.length) {
                buffer = (buffer << 8) | (dataKey[i] & 0xff);
                bits += 8;
            } else if (bits > 0) {
                buffer <<= 5 - bits;
                bits = 5;
            }
            while (bits >= 5) {
                if (chars > 0 && chars % 4 == 0) out.append('-');
                out.append(ALPHABET.charAt((buffer >> (bits - 5)) & 31));
                bits -= 5;
                chars++;
            }
        }
        return out.toString();
    }

    /** Accepts lowercase, spaces, dashes and the I/L/O look-alikes. */
    static byte[] parseRecoveryCode(String code) throws InvalidCodeException {
        String clean = code.toUpperCase(java.util.Locale.ROOT).replaceAll("[\\s-]", "")
            .replace('I', '1').replace('L', '1').replace('O', '0');
        if (clean.length() != 52) throw new InvalidCodeException();
        byte[] key = new byte[KEY_BYTES];
        int buffer = 0;
        int bits = 0;
        int index = 0;
        for (int i = 0; i < clean.length(); i++) {
            int value = ALPHABET.indexOf(clean.charAt(i));
            if (value < 0) throw new InvalidCodeException();
            buffer = (buffer << 5) | value;
            bits += 5;
            if (bits >= 8) {
                if (index < KEY_BYTES) key[index++] = (byte) (buffer >> (bits - 8));
                bits -= 8;
            }
            buffer &= (1 << bits) - 1;
        }
        if (buffer != 0) throw new InvalidCodeException();
        return key;
    }
}
