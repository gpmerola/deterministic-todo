package app.deterministic.todo.h96remote;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import javax.net.ssl.SSLHandshakeException;

import org.junit.After;
import org.junit.Test;

public class RemoteSessionTest {
    private static final byte[] START = Hex.parse("c202020801");

    private final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    private final List<FakeTransport> transports = new CopyOnWriteArrayList<>();
    private final List<String> states = new CopyOnWriteArrayList<>();
    private IOException openFailure;

    @After public void tearDown() {
        executor.shutdownNow();
    }

    private RemoteSession session() {
        return new RemoteSession((host, port) -> {
            FakeTransport transport = new FakeTransport();
            transports.add(transport);
            return transport;
        }, "192.168.1.2", 6466, executor, new RemoteSession.Listener() {
            @Override public void onState(RemoteSession.State state, RemoteSession.Failure failure) {
                states.add(state + "/" + failure);
            }
            @Override public void onVolume(RemoteProtocol.Volume volume) {}
        });
    }

    private void drain() throws Exception {
        executor.submit(() -> {}).get(2, TimeUnit.SECONDS);
    }

    @Test public void commandsAreDroppedUntilTheBoxSaysStarted() throws Exception {
        RemoteSession session = session();
        session.start();
        drain();
        assertFalse(session.send(RemoteCommand.OK));
        transports.get(0).deliver(START);
        drain();
        assertEquals(RemoteSession.State.READY, session.state());
        assertTrue(session.send(RemoteCommand.OK));
        drain();
        assertEquals(1, transports.get(0).sent.size());
        assertEquals("520408171003", Hex.of(transports.get(0).sent.get(0)));
    }

    @Test public void reconnectionNeverReplaysEarlierCommands() throws Exception {
        RemoteSession session = session();
        session.start();
        drain();
        transports.get(0).deliver(START);
        drain();
        session.send(RemoteCommand.HOME);
        drain();
        transports.get(0).drop(new IOException("wifi lost"));
        drain();
        assertEquals(RemoteSession.State.RECONNECTING, session.state());
        assertFalse(session.send(RemoteCommand.BACK));
        Thread.sleep(RemoteSession.RETRY_DELAYS_MS[0] + 300);
        drain();
        assertEquals(2, transports.size());
        transports.get(1).deliver(START);
        drain();
        assertEquals(RemoteSession.State.READY, session.state());
        assertEquals(0, transports.get(1).sent.size());
    }

    @Test public void handshakeRejectionMeansNotPairedWithoutRetry() throws Exception {
        openFailure = new SSLHandshakeException("bad certificate");
        RemoteSession session = session();
        session.start();
        drain();
        assertEquals(RemoteSession.State.FAILED, session.state());
        assertTrue(states.contains("FAILED/NOT_PAIRED"));
        assertEquals(1, transports.size());
    }

    @Test public void stopClosesTheTransportAndIgnoresLateMessages() throws Exception {
        RemoteSession session = session();
        session.start();
        drain();
        session.stop();
        drain();
        assertTrue(transports.get(0).closed);
        transports.get(0).deliver(START);
        drain();
        assertEquals(RemoteSession.State.IDLE, session.state());
    }

    @Test public void lateClosureAfterShutdownDoesNotThrow() throws Exception {
        RemoteSession session = session();
        session.start();
        drain();
        session.stop();
        drain();
        executor.shutdown();
        // The socket reader thread reports the closure after the executor is gone.
        transports.get(0).listener.onClosed(new IOException("socket closed"));
        transports.get(0).listener.onMessage(START);
        assertFalse(session.send(RemoteCommand.OK));
    }

    private final class FakeTransport implements TvTransport {
        final List<byte[]> sent = new ArrayList<>();
        Listener listener;
        boolean closed;

        @Override public void open(Listener listener) throws IOException {
            if (openFailure != null) throw openFailure;
            this.listener = listener;
        }

        @Override public void send(byte[] payload) throws IOException {
            if (closed) throw new IOException("closed");
            sent.add(payload);
        }

        @Override public void close() {
            closed = true;
        }

        void deliver(byte[] payload) {
            listener.onMessage(payload);
        }

        void drop(Exception cause) {
            closed = true;
            listener.onClosed(cause);
        }
    }
}
