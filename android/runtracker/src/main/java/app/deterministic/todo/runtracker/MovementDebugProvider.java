package app.deterministic.todo.runtracker;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;

import java.util.Map;

/** Read-only aggregate diagnostics. The manifest restricts callers to Android's DUMP permission. */
public final class MovementDebugProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        if (getContext() == null || !"status".equals(uri.getLastPathSegment()))
            throw new IllegalArgumentException("Supported path: /status");
        Map<String, Object> values = PassiveMovementDebugState.values(getContext());
        values.putAll(BipUSyncDebugState.values(getContext()));
        values.putAll(IntensiveDiagnosticDebugState.values(getContext()));
        String[] columns = projection == null ? values.keySet().toArray(new String[0]) : projection;
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        Object[] row = new Object[columns.length];
        for (int i = 0; i < columns.length; i++) {
            if (!values.containsKey(columns[i])) throw new IllegalArgumentException("Unknown column: " + columns[i]);
            row[i] = values.get(columns[i]);
        }
        cursor.addRow(row);
        return cursor;
    }

    @Override public String getType(Uri uri) {
        return "vnd.android.cursor.item/vnd.deterministic.todo.movement-status";
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw readOnly(); }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { throw readOnly(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { throw readOnly(); }

    private UnsupportedOperationException readOnly() {
        return new UnsupportedOperationException("Movement diagnostics are read-only");
    }
}
