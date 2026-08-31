package app.deterministic.todo.runtracker;

import java.util.concurrent.atomic.AtomicBoolean;

final class BipUSyncCoordinator {
    private static final AtomicBoolean RUNNING = new AtomicBoolean();
    private BipUSyncCoordinator() {}
    static boolean tryAcquire() { return RUNNING.compareAndSet(false, true); }
    static void release() { RUNNING.set(false); }
}
