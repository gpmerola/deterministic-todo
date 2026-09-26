package app.deterministic.todo.runtracker;

final class DiagnosticResourceMetrics {
    private static final double HOUR_MS = 3_600_000.0;

    private DiagnosticResourceMetrics() {}

    static Double cpuPercentOfOneCore(Long cpuMillis, Long durationMillis) {
        if (cpuMillis == null || durationMillis == null || durationMillis <= 0) return null;
        return cpuMillis * 100.0 / durationMillis;
    }

    static Double bytesPerHour(Long bytes, Long durationMillis) {
        if (bytes == null || durationMillis == null || durationMillis <= 0) return null;
        return bytes * HOUR_MS / durationMillis;
    }
}
