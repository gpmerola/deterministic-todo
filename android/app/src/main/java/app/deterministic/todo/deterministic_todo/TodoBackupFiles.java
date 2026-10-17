package app.deterministic.todo.deterministic_todo;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Where encrypted backups live. Names sort by time
 * (todo-YYYYMMDDTHHMMSSZ.tdb); only matching files are listed or removed.
 */
interface TodoBackupFiles {
    Pattern NAME = Pattern.compile("todo-\\d{8}T\\d{6}Z\\.tdb");

    final class Entry {
        final String name;
        final long size;

        Entry(String name, long size) {
            this.name = name;
            this.size = size;
        }
    }

    void write(String name, byte[] content) throws IOException;

    /** Oldest first. */
    List<Entry> list() throws IOException;

    byte[] read(String name) throws IOException;

    void delete(String name) throws IOException;

    static void requireName(String name) {
        if (name == null || !NAME.matcher(name).matches()) {
            throw new IllegalArgumentException("Invalid backup name");
        }
    }

    /** Writes then keeps only the newest [keep] backups. */
    static void writeAndRotate(TodoBackupFiles files, String name, byte[] content, int keep) throws IOException {
        requireName(name);
        if (keep < 1) throw new IllegalArgumentException("keep");
        files.write(name, content);
        List<Entry> entries = files.list();
        for (int i = 0; i < entries.size() - keep; i++) files.delete(entries.get(i).name);
    }

    /** Plain directory with atomic writes: tests and Android before 10. */
    final class Directory implements TodoBackupFiles {
        private final File dir;

        Directory(File dir) {
            this.dir = dir;
        }

        @Override
        public void write(String name, byte[] content) throws IOException {
            requireName(name);
            if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("No backup directory");
            File temp = new File(dir, name + ".tmp");
            try (FileOutputStream out = new FileOutputStream(temp)) {
                out.write(content);
                out.getFD().sync();
            }
            if (!temp.renameTo(new File(dir, name))) {
                temp.delete();
                throw new IOException("Backup rename failed");
            }
        }

        @Override
        public List<Entry> list() {
            List<Entry> result = new ArrayList<>();
            String[] names = dir.list((d, n) -> NAME.matcher(n).matches());
            if (names != null) {
                java.util.Arrays.sort(names);
                for (String name : names) result.add(new Entry(name, new File(dir, name).length()));
            }
            return result;
        }

        @Override
        public byte[] read(String name) throws IOException {
            requireName(name);
            return Files.readAllBytes(new File(dir, name).toPath());
        }

        @Override
        public void delete(String name) {
            requireName(name);
            new File(dir, name).delete();
        }
    }
}
