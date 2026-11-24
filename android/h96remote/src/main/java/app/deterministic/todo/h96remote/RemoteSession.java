package app.deterministic.todo.h96remote;

import java.io.IOException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import javax.net.ssl.SSLException;

/**
 * Keeps one remote connection alive while the remote screen is open. Commands are sent only
 * when the session is ready and are never queued or replayed, so a reconnection cannot repeat
 * a key press. All work runs on the given single-threaded executor.
 */
public final class RemoteSession {
    public enum State { IDLE, CONNECTING, READY, RECONNECTING, FAILED }

    /** Why the session failed; shown to the user as a short message. */
    public enum Failure { NONE, UNREACHABLE, NOT_PAIRED, CLOSED }

    public interface Listener {
        void onState(State state, Failure failure);

        void onVolume(RemoteProtocol.Volume volume);
    }

    static final long[] RETRY_DELAYS_MS = {1000, 2000, 4000, 8000, 8000};

    private final TvTransport.Factory factory;
    private final String host;
    private final int port;
    private final ScheduledExecutorService executor;
    private final Listener listener;

    // Confined to the executor thread.
    private TvTransport transport;
    private RemoteProtocol protocol;
    private int generation;
    private int attempts;
    private boolean running;
    private volatile State state = State.IDLE;

    public RemoteSession(TvTransport.Factory factory, String host, int port,
                         ScheduledExecutorService executor, Listener listener) {
        this.factory = factory;
        this.host = host;
        this.port = port;
        this.executor = executor;
        this.listener = listener;
    }

    public State state() {
        return state;
    }

    public void start() {
        executor.execute(() -> {
            if (running) return;
            running = true;
            attempts = 0;
            connect(State.CONNECTING);
        });
    }

    public void stop() {
        executor.execute(() -> {
            running = false;
            generation++;
            closeTransport();
            setState(State.IDLE, Failure.NONE);
        });
    }

    /** Returns false when the command was dropped because the session is not ready. */
    public boolean send(RemoteCommand command) {
        return sendIfReady(RemoteMessages.key(command), null);
    }

    public boolean sendText(String text) {
        return sendIfReady(null, text);
    }

    public boolean launch(String appLink) {
        return sendIfReady(RemoteMessages.appLink(appLink), null);
    }

    private boolean sendIfReady(byte[] payload, String text) {
        if (state != State.READY) return false;
        executor.execute(() -> {
            if (state != State.READY || transport == null) return;
            try {
                transport.send(text != null ? protocol.text(text) : payload);
            } catch (IOException e) {
                // The reader thread reports the closure and drives reconnection.
                transport.close();
            }
        });
        return true;
    }

    private void connect(State connectingState) {
        if (!running) return;
        int current = ++generation;
        closeTransport();
        setState(connectingState, Failure.NONE);
        protocol = new RemoteProtocol();
        TvTransport next = factory.create(host, port);
        try {
            next.open(new TvTransport.Listener() {
                @Override public void onMessage(byte[] payload) {
                    executor.execute(() -> handle(current, payload));
                }

                @Override public void onClosed(Exception cause) {
                    executor.execute(() -> closed(current, cause));
                }
            });
            transport = next;
        } catch (SSLException e) {
            next.close();
            fail(Failure.NOT_PAIRED);
        } catch (IOException e) {
            next.close();
            retryOrFail(Failure.UNREACHABLE);
        }
    }

    private void handle(int current, byte[] payload) {
        if (current != generation || transport == null) return;
        try {
            byte[] reply = protocol.handle(payload);
            if (reply != null) transport.send(reply);
        } catch (ProtoReader.ProtocolException | IOException e) {
            transport.close();
            return;
        }
        if (protocol.started() && state != State.READY) {
            attempts = 0;
            setState(State.READY, Failure.NONE);
        }
        listener.onVolume(protocol.volume());
    }

    private void closed(int current, Exception cause) {
        if (current != generation || !running) return;
        transport = null;
        boolean wasReady = state == State.READY;
        if (cause instanceof SSLException && !wasReady) {
            fail(Failure.NOT_PAIRED);
            return;
        }
        if (wasReady) attempts = 0;
        retryOrFail(Failure.CLOSED);
    }

    private void retryOrFail(Failure failure) {
        if (attempts >= RETRY_DELAYS_MS.length) {
            fail(failure);
            return;
        }
        long delay = RETRY_DELAYS_MS[attempts++];
        int current = generation;
        setState(State.RECONNECTING, failure);
        executor.schedule(() -> {
            if (current == generation) connect(State.RECONNECTING);
        }, delay, TimeUnit.MILLISECONDS);
    }

    private void fail(Failure failure) {
        running = false;
        closeTransport();
        setState(State.FAILED, failure);
    }

    private void closeTransport() {
        if (transport != null) transport.close();
        transport = null;
    }

    private void setState(State next, Failure failure) {
        state = next;
        listener.onState(next, failure);
    }
}
