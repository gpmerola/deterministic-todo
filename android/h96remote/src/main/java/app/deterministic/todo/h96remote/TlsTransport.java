package app.deterministic.todo.h96remote;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.security.cert.Certificate;

import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/** TLS socket with a reader thread. Writes are serialized; nothing is queued while closed. */
public final class TlsTransport implements TvTransport {
    static final int CONNECT_TIMEOUT_MS = 4000;
    /** The box pings every 5 s; three missed pings mean the link is gone. */
    static final int READ_TIMEOUT_MS = 16000;

    private final String host;
    private final int port;
    private final SSLSocketFactory factory;
    private volatile SSLSocket socket;
    private OutputStream out;

    public TlsTransport(String host, int port, SSLSocketFactory factory) {
        this.host = host;
        this.port = port;
        this.factory = factory;
    }

    @Override
    public void open(Listener listener) throws IOException {
        Socket plain = new Socket();
        try {
            plain.connect(new InetSocketAddress(host, port), CONNECT_TIMEOUT_MS);
            plain.setTcpNoDelay(true);
            plain.setSoTimeout(READ_TIMEOUT_MS);
            SSLSocket tls = (SSLSocket) factory.createSocket(plain, host, port, true);
            tls.startHandshake();
            socket = tls;
            out = tls.getOutputStream();
        } catch (IOException e) {
            plain.close();
            throw e;
        }
        InputStream in = socket.getInputStream();
        Thread reader = new Thread(() -> {
            Exception cause = null;
            try {
                while (true) listener.onMessage(Framing.read(in));
            } catch (Exception e) {
                cause = e;
            } finally {
                close();
                listener.onClosed(cause);
            }
        }, "h96remote-" + port);
        reader.setDaemon(true);
        reader.start();
    }

    /** Server certificate of the open session, for pinning and the pairing secret. */
    public Certificate peerCertificate() throws IOException {
        SSLSocket current = socket;
        if (current == null) throw new IOException("closed");
        return current.getSession().getPeerCertificates()[0];
    }

    @Override
    public synchronized void send(byte[] payload) throws IOException {
        if (socket == null) throw new IOException("closed");
        Framing.write(out, payload);
    }

    @Override
    public void close() {
        SSLSocket current = socket;
        socket = null;
        if (current != null) {
            try {
                current.close();
            } catch (IOException ignored) {
                // Closing is best effort.
            }
        }
    }
}
