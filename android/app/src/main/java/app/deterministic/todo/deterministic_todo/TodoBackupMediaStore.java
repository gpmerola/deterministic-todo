package app.deterministic.todo.deterministic_todo;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import androidx.annotation.RequiresApi;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Documents/Todo backup through MediaStore (Android 10+): visible in the Files
 * app, kept after uninstall, no storage permission. Only files created by this
 * installation are listed, rotated or deleted; others are never touched.
 */
@RequiresApi(Build.VERSION_CODES.Q)
final class TodoBackupMediaStore implements TodoBackupFiles {
    static final String RELATIVE_PATH = Environment.DIRECTORY_DOCUMENTS + "/Todo backup/";
    private final ContentResolver resolver;
    private final Uri collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);

    TodoBackupMediaStore(ContentResolver resolver) {
        this.resolver = resolver;
    }

    @Override
    public void write(String name, byte[] content) throws IOException {
        TodoBackupFiles.requireName(name);
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        values.put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream");
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_PATH);
        values.put(MediaStore.MediaColumns.IS_PENDING, 1);
        Uri uri = resolver.insert(collection, values);
        if (uri == null) throw new IOException("MediaStore insert failed");
        try {
            try (OutputStream out = resolver.openOutputStream(uri, "w")) {
                if (out == null) throw new IOException("No output stream");
                out.write(content);
            }
            values.clear();
            values.put(MediaStore.MediaColumns.IS_PENDING, 0);
            resolver.update(uri, values, null, null);
        } catch (IOException | RuntimeException e) {
            resolver.delete(uri, null, null);
            throw e;
        }
    }

    @Override
    public List<Entry> list() throws IOException {
        List<Entry> result = new ArrayList<>();
        try (Cursor cursor = resolver.query(collection,
                new String[] {MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE},
                MediaStore.MediaColumns.RELATIVE_PATH + "=? AND " + MediaStore.MediaColumns.IS_PENDING + "=0",
                new String[] {RELATIVE_PATH},
                MediaStore.MediaColumns.DISPLAY_NAME + " ASC")) {
            if (cursor == null) throw new IOException("MediaStore query failed");
            while (cursor.moveToNext()) {
                String name = cursor.getString(0);
                if (name != null && NAME.matcher(name).matches()) result.add(new Entry(name, cursor.getLong(1)));
            }
        }
        return result;
    }

    private Uri find(String name) throws IOException {
        TodoBackupFiles.requireName(name);
        try (Cursor cursor = resolver.query(collection,
                new String[] {MediaStore.MediaColumns._ID},
                MediaStore.MediaColumns.RELATIVE_PATH + "=? AND " + MediaStore.MediaColumns.DISPLAY_NAME + "=?",
                new String[] {RELATIVE_PATH, name}, null)) {
            if (cursor == null || !cursor.moveToFirst()) throw new IOException("Backup not found");
            return ContentUris.withAppendedId(collection, cursor.getLong(0));
        }
    }

    @Override
    public byte[] read(String name) throws IOException {
        try (InputStream in = resolver.openInputStream(find(name))) {
            if (in == null) throw new IOException("No input stream");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[16384];
            for (int n; (n = in.read(buffer)) > 0; ) out.write(buffer, 0, n);
            return out.toByteArray();
        }
    }

    @Override
    public void delete(String name) throws IOException {
        resolver.delete(find(name), null, null);
    }
}
