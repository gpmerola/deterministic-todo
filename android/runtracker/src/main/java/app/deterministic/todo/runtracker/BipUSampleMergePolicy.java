package app.deterministic.todo.runtracker;

/** Conservative replacement rule for repeated one-minute Bip U samples. */
final class BipUSampleMergePolicy {
    private BipUSampleMergePolicy() {}

    static boolean shouldReplace(int storedSteps, int incomingSteps) {
        return incomingSteps > storedSteps;
    }
}
