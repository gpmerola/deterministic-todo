package app.deterministic.todo.deterministic_todo;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.io.File;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Encrypted automatic backups. The random data key is stored wrapped by a
 * non-exportable Android Keystore key, so weekly runs need no user action;
 * the user keeps the recovery code for another installation. Plain JSON only
 * crosses the channel in memory and is never written to disk here.
 */
public final class TodoBackupChannel {
    private static final String WRAP_ALIAS = "todo_backup_wrap_v1";
    private static final String PREFS = "todo_backup";
    private static final String WRAPPED = "wrapped_data_key";
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final SecureRandom RANDOM = new SecureRandom();

    private TodoBackupChannel() {}

    public static void register(Context context, FlutterEngine engine) {
        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        TodoBackupFiles files = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
            ? new TodoBackupMediaStore(app.getContentResolver())
            : new TodoBackupFiles.Directory(new File(
                app.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), "Todo backup"));
        boolean validation = app.getPackageName().endsWith(".dev.validation");
        Handler main = new Handler(Looper.getMainLooper());
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/backup")
            .setMethodCallHandler((call, result) -> IO.execute(() -> {
                try {
                    Object value;
                    switch (call.method) {
                        case "status":
                            value = dataKey(prefs) != null;
                            break;
                        case "setup": {
                            byte[] key = dataKey(prefs);
                            if (key == null) {
                                key = new byte[TodoBackupCipher.KEY_BYTES];
                                RANDOM.nextBytes(key);
                                prefs.edit().putString(WRAPPED, wrap(key)).commit();
                            }
                            value = TodoBackupCipher.recoveryCode(key);
                            break;
                        }
                        case "write": {
                            byte[] key = requireKey(prefs);
                            byte[] iv = new byte[12];
                            RANDOM.nextBytes(iv);
                            byte[] plain = call.argument("content");
                            Integer keep = call.argument("keep");
                            byte[] sealed = TodoBackupCipher.encrypt(key, plain, iv);
                            TodoBackupFiles.writeAndRotate(files, call.argument("name"), sealed, keep == null ? 6 : keep);
                            value = sealed.length;
                            break;
                        }
                        case "list": {
                            List<Map<String, Object>> items = new ArrayList<>();
                            for (TodoBackupFiles.Entry entry : files.list()) {
                                Map<String, Object> item = new HashMap<>();
                                item.put("name", entry.name);
                                item.put("size", entry.size);
                                items.add(item);
                            }
                            value = items;
                            break;
                        }
                        case "read":
                            value = TodoBackupCipher.decrypt(requireKey(prefs), files.read(call.argument("name")));
                            break;
                        case "decrypt": {
                            String code = call.argument("code");
                            byte[] key = code == null ? requireKey(prefs) : TodoBackupCipher.parseRecoveryCode(code);
                            value = TodoBackupCipher.decrypt(key, call.argument("content"));
                            break;
                        }
                        case "deleteAllForValidation":
                            if (!validation) throw new SecurityException("Validation package only");
                            for (TodoBackupFiles.Entry entry : files.list()) files.delete(entry.name);
                            prefs.edit().clear().commit();
                            value = true;
                            break;
                        default:
                            main.post(result::notImplemented);
                            return;
                    }
                    Object reply = value;
                    main.post(() -> result.success(reply));
                } catch (Exception e) {
                    // A code and the class name only: never names, paths or content.
                    String code = e instanceof TodoBackupCipher.KeyMismatchException ? "key_mismatch"
                        : e instanceof IllegalStateException ? "not_configured"
                        : e instanceof TodoBackupCipher.InvalidCodeException ? "invalid_code"
                        : "backup_failed";
                    String kind = e.getClass().getSimpleName();
                    main.post(() -> result.error(code, kind, null));
                }
            }));
    }

    private static byte[] requireKey(SharedPreferences prefs) throws Exception {
        byte[] key = dataKey(prefs);
        if (key == null) throw new IllegalStateException("Automatic backup not set up");
        return key;
    }

    /** Null when not set up, or when the wrapped key came from another phone. */
    private static byte[] dataKey(SharedPreferences prefs) throws Exception {
        String stored = prefs.getString(WRAPPED, null);
        if (stored == null) return null;
        byte[] raw = Base64.decode(stored, Base64.NO_WRAP);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, wrappingKey(), new GCMParameterSpec(128, Arrays.copyOf(raw, 12)));
            return cipher.doFinal(raw, 12, raw.length - 12);
        } catch (javax.crypto.AEADBadTagException e) {
            // Only a different Keystore key (e.g. preferences restored from an
            // Android cloud backup) is final; transient Keystore errors propagate.
            prefs.edit().remove(WRAPPED).commit();
            return null;
        }
    }

    private static String wrap(byte[] key) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey());
        byte[] iv = cipher.getIV();
        byte[] sealed = cipher.doFinal(key);
        byte[] out = Arrays.copyOf(iv, iv.length + sealed.length);
        System.arraycopy(sealed, 0, out, iv.length, sealed.length);
        return Base64.encodeToString(out, Base64.NO_WRAP);
    }

    private static SecretKey wrappingKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.containsAlias(WRAP_ALIAS)) return (SecretKey) keyStore.getKey(WRAP_ALIAS, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(
                WRAP_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build());
        return generator.generateKey();
    }
}
