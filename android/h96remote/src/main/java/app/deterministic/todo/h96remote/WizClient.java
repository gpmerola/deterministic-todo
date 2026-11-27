package app.deterministic.todo.h96remote;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/** UDP client for WiZ bulbs. Blocking: call off the main thread. */
public final class WizClient {
    static final int REPLY_TIMEOUT_MS = 400;

    /** One bulb found on the LAN. */
    public static final class Found {
        public final String host;
        public final WizProtocol.Pilot pilot;

        Found(String host, WizProtocol.Pilot pilot) {
            this.host = host;
            this.pilot = pilot;
        }
    }

    /** Broadcasts getPilot and collects the bulbs that answer within the window. */
    public Map<String, Found> discover(int windowMs) throws IOException {
        Map<String, Found> found = new LinkedHashMap<>();
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setBroadcast(true);
            byte[] probe = WizProtocol.getPilot().getBytes(StandardCharsets.UTF_8);
            socket.send(new DatagramPacket(probe, probe.length,
                InetAddress.getByName("255.255.255.255"), WizProtocol.PORT));
            long end = System.currentTimeMillis() + windowMs;
            byte[] buffer = new byte[1024];
            while (System.currentTimeMillis() < end) {
                socket.setSoTimeout((int) Math.max(1, end - System.currentTimeMillis()));
                DatagramPacket reply = new DatagramPacket(buffer, buffer.length);
                try {
                    socket.receive(reply);
                } catch (SocketTimeoutException e) {
                    break;
                }
                String host = reply.getAddress().getHostAddress();
                if (!LanAddress.isPrivate(host)) continue;
                WizProtocol.Pilot pilot = WizProtocol.parsePilot(
                    new String(reply.getData(), 0, reply.getLength(), StandardCharsets.UTF_8));
                if (pilot != null) found.put(host, new Found(host, pilot));
            }
        }
        return found;
    }

    /**
     * Sends one command and waits briefly for the reply; resends once if the first datagram
     * was lost. Commands are absolute (on, 40%, red), so a duplicate does no harm.
     */
    public String request(String host, String json) throws IOException {
        if (!LanAddress.isPrivate(host)) throw new IOException("not a LAN address");
        byte[] payload = json.getBytes(StandardCharsets.UTF_8);
        InetAddress address = InetAddress.getByName(host);
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(REPLY_TIMEOUT_MS);
            byte[] buffer = new byte[1024];
            for (int attempt = 0; attempt < 2; attempt++) {
                socket.send(new DatagramPacket(payload, payload.length, address, WizProtocol.PORT));
                DatagramPacket reply = new DatagramPacket(buffer, buffer.length);
                try {
                    socket.receive(reply);
                    return new String(reply.getData(), 0, reply.getLength(), StandardCharsets.UTF_8);
                } catch (SocketTimeoutException ignored) {
                    // Retry once.
                }
            }
        }
        throw new SocketTimeoutException("no reply");
    }
}
