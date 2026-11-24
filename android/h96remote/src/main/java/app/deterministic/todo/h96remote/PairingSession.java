package app.deterministic.todo.h96remote;

import java.io.IOException;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * Polo pairing on port 6467. {@link #start} makes the TV show a six-digit code;
 * {@link #finish} sends the secret derived from it. Blocking: call off the main thread.
 */
public final class PairingSession implements AutoCloseable {
    /** The TV rejected the code. */
    public static final class BadSecretException extends IOException {
        public BadSecretException() {
            super("bad secret");
        }
    }

    static final long STEP_TIMEOUT_MS = 10_000;
    private static final byte[] CLOSED = new byte[0];

    private final TvTransport transport;
    private final String clientName;
    private final BlockingQueue<byte[]> inbox = new LinkedBlockingQueue<>();

    public PairingSession(TvTransport transport, String clientName) {
        this.transport = transport;
        this.clientName = clientName;
    }

    public void start() throws IOException {
        transport.open(new TvTransport.Listener() {
            @Override public void onMessage(byte[] payload) { inbox.add(payload); }
            @Override public void onClosed(Exception cause) { inbox.add(CLOSED); }
        });
        transport.send(PairingMessages.pairingRequest(clientName));
        expect(PairingMessages.F_PAIRING_REQUEST_ACK);
        transport.send(PairingMessages.options());
        expect(PairingMessages.F_OPTIONS);
        transport.send(PairingMessages.configuration());
        expect(PairingMessages.F_CONFIGURATION_ACK);
    }

    public void finish(byte[] secret) throws IOException {
        transport.send(PairingMessages.secret(secret));
        expect(PairingMessages.F_SECRET_ACK);
    }

    private void expect(int field) throws IOException {
        byte[] payload;
        try {
            payload = inbox.poll(STEP_TIMEOUT_MS, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("interrupted");
        }
        if (payload == null) throw new IOException("timeout");
        if (payload == CLOSED) throw new IOException("closed");
        try {
            ProtoReader message = new ProtoReader(payload);
            long status = message.varint(PairingMessages.F_STATUS, PairingMessages.STATUS_OK);
            if (status == PairingMessages.STATUS_BAD_SECRET) throw new BadSecretException();
            if (status != PairingMessages.STATUS_OK) throw new IOException("status " + status);
            if (!message.has(field)) throw new IOException("unexpected message");
        } catch (ProtoReader.ProtocolException e) {
            throw new IOException(e.getMessage());
        }
    }

    @Override
    public void close() {
        transport.close();
    }
}
