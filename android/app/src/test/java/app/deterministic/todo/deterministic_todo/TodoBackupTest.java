package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class TodoBackupTest {
    @Rule public TemporaryFolder folder = new TemporaryFolder();

    private static final byte[] PLAIN =
        "{\"format\":\"deterministic_todo\",\"tasks\":[{\"title\":\"Synthetic àè 🧪\"}]}".getBytes(StandardCharsets.UTF_8);

    private static byte[] key(int seed) {
        byte[] key = new byte[32];
        for (int i = 0; i < key.length; i++) key[i] = (byte) (seed * 31 + i * 7);
        return key;
    }

    private static byte[] iv(int seed) {
        byte[] iv = new byte[12];
        Arrays.fill(iv, (byte) seed);
        return iv;
    }

    @Test
    public void roundTripHidesContentAndHeaderIsStable() throws Exception {
        byte[] sealed = TodoBackupCipher.encrypt(key(1), PLAIN, iv(1));
        assertArrayEquals(PLAIN, TodoBackupCipher.decrypt(key(1), sealed));
        assertFalse(new String(sealed, StandardCharsets.ISO_8859_1).contains("Synthetic"));
        assertArrayEquals(TodoBackupCipher.MAGIC, Arrays.copyOf(sealed, 4));
        assertTrue(TodoBackupCipher.isBackup(sealed));
        assertFalse(Arrays.equals(sealed, TodoBackupCipher.encrypt(key(1), PLAIN, iv(2))));
    }

    @Test
    public void tamperingAndForeignKeysAreRejected() throws Exception {
        byte[] sealed = TodoBackupCipher.encrypt(key(1), PLAIN, iv(1));
        for (int index : new int[] {0, 6, 14, 30, sealed.length - 1}) {
            byte[] changed = sealed.clone();
            changed[index] ^= 1;
            assertThrows(GeneralSecurityException.class, () -> TodoBackupCipher.decrypt(key(1), changed));
        }
        assertThrows(TodoBackupCipher.KeyMismatchException.class, () -> TodoBackupCipher.decrypt(key(2), sealed));
        assertThrows(GeneralSecurityException.class, () -> TodoBackupCipher.decrypt(key(1), new byte[3]));
    }

    @Test
    public void recoveryCodeRoundTripsAndToleratesTyping() throws Exception {
        for (int seed = 0; seed < 50; seed++) {
            byte[] key = key(seed);
            String code = TodoBackupCipher.recoveryCode(key);
            assertEquals(64, code.length()); // 52 characters + 12 dashes.
            assertTrue(code.matches("([0-9A-HJKMNP-TV-Z]{4}-){12}[0-9A-HJKMNP-TV-Z]{4}"));
            assertArrayEquals(key, TodoBackupCipher.parseRecoveryCode(code));
            assertArrayEquals(key, TodoBackupCipher.parseRecoveryCode(
                " " + code.toLowerCase().replace("-", " ").replace('1', 'l').replace('0', 'o') + " "));
        }
        byte[] all = new byte[32];
        Arrays.fill(all, (byte) 0xff);
        assertArrayEquals(all, TodoBackupCipher.parseRecoveryCode(TodoBackupCipher.recoveryCode(all)));
        String code = TodoBackupCipher.recoveryCode(key(3));
        assertThrows(TodoBackupCipher.InvalidCodeException.class,
            () -> TodoBackupCipher.parseRecoveryCode(code.substring(1)));
        assertThrows(TodoBackupCipher.InvalidCodeException.class,
            () -> TodoBackupCipher.parseRecoveryCode("U" + code.substring(1)));
        // The 4 padding bits must be zero: the last character cannot be arbitrary.
        assertThrows(TodoBackupCipher.InvalidCodeException.class,
            () -> TodoBackupCipher.parseRecoveryCode(code.substring(0, code.length() - 1) + "Z"));
    }

    @Test
    public void rotationKeepsNewestAndIgnoresForeignFiles() throws Exception {
        File dir = folder.newFolder("Todo backup");
        File foreign = new File(dir, "keep-me.txt");
        Files.write(foreign.toPath(), new byte[] {1});
        TodoBackupFiles files = new TodoBackupFiles.Directory(dir);
        for (int day = 1; day <= 5; day++) {
            TodoBackupFiles.writeAndRotate(files, String.format("todo-202610%02dT090000Z.tdb", day),
                new byte[] {(byte) day}, 3);
        }
        List<String> names = new ArrayList<>();
        for (TodoBackupFiles.Entry entry : files.list()) names.add(entry.name);
        assertEquals(Arrays.asList(
            "todo-20261003T090000Z.tdb", "todo-20261004T090000Z.tdb", "todo-20261005T090000Z.tdb"), names);
        assertArrayEquals(new byte[] {5}, files.read("todo-20261005T090000Z.tdb"));
        assertTrue(foreign.exists());
        assertEquals(0, dir.list((d, n) -> n.endsWith(".tmp")).length);
        assertThrows(IllegalArgumentException.class, () -> files.read("../todo.db"));
        assertThrows(IllegalArgumentException.class, () -> TodoBackupFiles.writeAndRotate(files, "x.tdb", new byte[0], 3));
    }
}
