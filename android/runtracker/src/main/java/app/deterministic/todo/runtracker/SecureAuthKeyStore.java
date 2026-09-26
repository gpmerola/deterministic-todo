package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.ByteBuffer;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SecureAuthKeyStore {
    private static final String ALIAS = "bip_u_auth_key_encryption";
    private static final String VALUE = "encrypted_auth_key";
    private final SharedPreferences preferences;

    SecureAuthKeyStore(Context context) {
        preferences = context.getSharedPreferences("bip_u_private", Context.MODE_PRIVATE);
    }

    void saveHex(String hex) throws Exception {
        byte[] key = parseHex(hex);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey());
        byte[] encrypted = cipher.doFinal(key);
        byte[] iv = cipher.getIV();
        ByteBuffer packed = ByteBuffer.allocate(4 + iv.length + encrypted.length)
            .putInt(iv.length).put(iv).put(encrypted);
        preferences.edit().putString(VALUE, Base64.encodeToString(packed.array(), Base64.NO_WRAP)).apply();
    }

    boolean hasKey() { return preferences.contains(VALUE); }

    byte[] read() throws Exception {
        String encoded = preferences.getString(VALUE, null);
        if (encoded == null) return null;
        ByteBuffer packed = ByteBuffer.wrap(Base64.decode(encoded, Base64.NO_WRAP));
        byte[] iv = new byte[packed.getInt()]; packed.get(iv);
        byte[] encrypted = new byte[packed.remaining()]; packed.get(encrypted);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey(), new GCMParameterSpec(128, iv));
        return cipher.doFinal(encrypted);
    }

    private SecretKey encryptionKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return ((KeyStore.SecretKeyEntry) store.getEntry(ALIAS, null)).getSecretKey();
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }

    static byte[] parseHex(String value) {
        String clean = value.replace(" ", "").trim();
        if (clean.length() != 32 || !clean.matches("[0-9a-fA-F]{32}")) throw new IllegalArgumentException("La chiave deve contenere 32 caratteri esadecimali");
        byte[] result = new byte[16];
        for (int i = 0; i < result.length; i++) result[i] = (byte) Integer.parseInt(clean.substring(i * 2, i * 2 + 2), 16);
        return result;
    }
}
