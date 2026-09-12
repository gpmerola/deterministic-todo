package app.deterministic.todo.runtracker;

final class DriveWriteVerification {
    private DriveWriteVerification() {}

    static boolean matchesSize(long expectedBytes, Long observedBytes) {
        return observedBytes == null || observedBytes < 0 || observedBytes == expectedBytes;
    }

    static boolean completeImmutableFile(long expectedBytes, Long observedBytes) {
        return expectedBytes > 0 && (observedBytes == null || observedBytes < 0
            || observedBytes == expectedBytes && observedBytes > 0);
    }

    static boolean renameCompleted(boolean providerReturnedUri,
                                   boolean finalFileVerified) {
        return providerReturnedUri || finalFileVerified;
    }

    static boolean verifiedFinalFile(long expectedBytes, Long observedBytes) {
        return expectedBytes > 0 && observedBytes != null
            && observedBytes == expectedBytes;
    }
}
