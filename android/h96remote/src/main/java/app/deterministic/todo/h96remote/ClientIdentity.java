package app.deterministic.todo.h96remote;

import java.security.GeneralSecurityException;
import java.security.interfaces.RSAPublicKey;

import javax.net.ssl.X509KeyManager;

/** The phone's TLS client certificate. The TV remembers it as the paired remote. */
public interface ClientIdentity {
    X509KeyManager keyManager() throws GeneralSecurityException;

    RSAPublicKey publicKey() throws GeneralSecurityException;
}
