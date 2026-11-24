package app.deterministic.todo.h96remote;

import java.io.IOException;

/** A framed, bidirectional connection to the box. Replaceable without touching UI or session. */
public interface TvTransport {
    interface Listener {
        void onMessage(byte[] payload);

        /** Called once, from the reader thread, when the connection ends for any reason. */
        void onClosed(Exception cause);
    }

    interface Factory {
        TvTransport create(String host, int port);
    }

    void open(Listener listener) throws IOException;

    void send(byte[] payload) throws IOException;

    void close();
}
