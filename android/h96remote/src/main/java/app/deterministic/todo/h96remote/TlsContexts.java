package app.deterministic.todo.h96remote;

import java.security.GeneralSecurityException;

import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;

/** Builds socket factories for pairing (pin recorded) and control (pin enforced). */
public final class TlsContexts {
    private TlsContexts() {}

    public static SSLSocketFactory factory(ClientIdentity identity, PinningTrustManager trust)
            throws GeneralSecurityException {
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(new KeyManager[]{identity.keyManager()}, new TrustManager[]{trust}, null);
        return context.getSocketFactory();
    }
}
