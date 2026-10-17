package app.deterministic.todo.deterministic_todo;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.CalendarContract;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/** Process-lifetime invalidation only: no polling, event contents or wake locks. */
final class AgendaRevision {
    private static final String PROCESS = UUID.randomUUID().toString();
    private static final AtomicLong changes = new AtomicLong();
    private static ContentObserver observer;

    private AgendaRevision() {}

    static synchronized String read(Context context) {
        if (context.checkSelfPermission(Manifest.permission.READ_CALENDAR)
                != PackageManager.PERMISSION_GRANTED) return null;
        if (observer == null) {
            ContentObserver candidate = new ContentObserver(new Handler(Looper.getMainLooper())) {
                @Override public void onChange(boolean selfChange) { changes.incrementAndGet(); }
                @Override public void onChange(boolean selfChange, Uri uri) { changes.incrementAndGet(); }
            };
            try {
                context.getContentResolver().registerContentObserver(
                    CalendarContract.CONTENT_URI, true, candidate);
                observer = candidate;
            } catch (RuntimeException unavailable) {
                return null; // Caller must perform a fresh read.
            }
        }
        return PROCESS + ":" + changes.get() + ":" + java.util.TimeZone.getDefault().getID();
    }
}
