package app.deterministic.todo.deterministic_todo;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.os.Build;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The in-app updater saves each APK as deterministic-todo-VERSION-BUILD.apk
 * in files/ota_update and only replaces a file with the same name, so every
 * past update stayed on the device. Only APKs for a build already installed
 * (or older), and those with the version-only name of August 2026, are
 * removed: a newer one may still be waiting for the system installer. Nothing else in the app's storage is touched.
 */
final class DownloadedApkCleanup {
    static final String PREFS = "downloaded_apk_cleanup";
    /** Mirrors DEV_BUILD_OFFSET in tools/todo_test_fast.py and update_service.dart. */
    static final long DEV_BUILD_OFFSET = 2000;
    private static final Pattern NAME = Pattern.compile("deterministic-todo-[^/]+-(\\d+)\\.apk");
    /**
     * Name used until September 2026 (version only, no build): never written
     * by a build that runs this cleanup, so never a pending update.
     */
    private static final Pattern LEGACY_NAME = Pattern.compile("deterministic-todo-\\d+\\.\\d+\\.\\d+\\.apk");
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();

    private DownloadedApkCleanup() {}

    static final class Result {
        final int deletedFiles;
        final long deletedBytes;
        final int remainingFiles;
        final long remainingBytes;

        Result(int deletedFiles, long deletedBytes, int remainingFiles, long remainingBytes) {
            this.deletedFiles = deletedFiles;
            this.deletedBytes = deletedBytes;
            this.remainingFiles = remainingFiles;
            this.remainingBytes = remainingBytes;
        }
    }

    static File directory(Context context) {
        return new File(context.getFilesDir(), "ota_update");
    }

    /** Off the main thread; called at launch and after the package is replaced. */
    static void runAsync(Context context) {
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                Result result = clean(directory(app), installedBuild(app));
                app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putLong("last_at", System.currentTimeMillis())
                    .putInt("last_deleted_files", result.deletedFiles)
                    .putLong("last_deleted_bytes", result.deletedBytes)
                    .putLong("total_deleted_bytes",
                        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .getLong("total_deleted_bytes", 0) + result.deletedBytes)
                    .apply();
            } catch (Exception ignored) {
                // Best effort: a leftover APK costs space, never correctness.
            }
        });
    }

    static Result clean(File directory, long installedBuild) {
        int deletedFiles = 0, remainingFiles = 0;
        long deletedBytes = 0, remainingBytes = 0;
        File[] children = directory.listFiles();
        if (children == null) return new Result(0, 0, 0, 0);
        for (File child : children) {
            if (!child.isFile()) continue;
            long size = child.length();
            Long build = build(child.getName());
            boolean stale = build != null ? build <= installedBuild : isLegacy(child.getName());
            if (stale && child.delete()) {
                deletedFiles++;
                deletedBytes += size;
            } else if (child.getName().endsWith(".apk")) {
                remainingFiles++;
                remainingBytes += size;
            }
        }
        return new Result(deletedFiles, deletedBytes, remainingFiles, remainingBytes);
    }

    /** Count and size of downloaded APKs now, without deleting anything. */
    static long[] usage(File directory) {
        long files = 0, bytes = 0;
        File[] children = directory.listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isFile() && child.getName().endsWith(".apk")) {
                    files++;
                    bytes += child.length();
                }
            }
        }
        return new long[] {files, bytes};
    }

    static boolean isLegacy(String name) {
        return LEGACY_NAME.matcher(name).matches();
    }

    static Long build(String name) {
        Matcher matcher = NAME.matcher(name);
        return matcher.matches() ? Long.parseLong(matcher.group(1)) : null;
    }

    /** Same numbering as the file names: Todo Test adds 2000 to its versionCode. */
    static long logicalBuild(long versionCode, String packageName) {
        boolean dev = packageName.endsWith(".dev") || packageName.endsWith(".dev.validation");
        return dev && versionCode >= DEV_BUILD_OFFSET ? versionCode - DEV_BUILD_OFFSET : versionCode;
    }

    @SuppressWarnings("deprecation")
    private static long installedBuild(Context context) throws Exception {
        PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
        long code = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
        return logicalBuild(code, context.getPackageName());
    }

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
