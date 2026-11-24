package app.deterministic.todo.h96remote;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import java.math.BigInteger;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPublicKey;
import java.util.Calendar;
import java.util.Date;

import javax.net.ssl.X509KeyManager;
import javax.security.auth.x500.X500Principal;

/** RSA client key generated inside the Android Keystore; the private key never leaves it. */
public final class KeyStoreIdentity implements ClientIdentity {
    static final String ALIAS = "h96remote_client_v1";
    private static final String PROVIDER = "AndroidKeyStore";

    @Override
    public X509KeyManager keyManager() throws GeneralSecurityException {
        KeyStore store = ensureKey();
        PrivateKey key = (PrivateKey) store.getKey(ALIAS, null);
        X509Certificate certificate = (X509Certificate) store.getCertificate(ALIAS);
        return new X509KeyManager() {
            @Override public String chooseClientAlias(String[] keyType, Principal[] issuers, Socket socket) { return ALIAS; }
            @Override public X509Certificate[] getCertificateChain(String alias) { return new X509Certificate[]{certificate}; }
            @Override public PrivateKey getPrivateKey(String alias) { return key; }
            @Override public String[] getClientAliases(String keyType, Principal[] issuers) { return new String[]{ALIAS}; }
            @Override public String[] getServerAliases(String keyType, Principal[] issuers) { return null; }
            @Override public String chooseServerAlias(String keyType, Principal[] issuers, Socket socket) { return null; }
        };
    }

    @Override
    public RSAPublicKey publicKey() throws GeneralSecurityException {
        return (RSAPublicKey) ensureKey().getCertificate(ALIAS).getPublicKey();
    }

    /** Revokes this phone as a remote: a new key means the TV must be paired again. */
    public static void delete() {
        try {
            KeyStore store = KeyStore.getInstance(PROVIDER);
            store.load(null);
            if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS);
        } catch (Exception ignored) {
            // Nothing to revoke.
        }
    }

    private static KeyStore ensureKey() throws GeneralSecurityException {
        KeyStore store = KeyStore.getInstance(PROVIDER);
        try {
            store.load(null);
        } catch (java.io.IOException e) {
            throw new GeneralSecurityException(e);
        }
        if (store.containsAlias(ALIAS)) return store;
        Calendar end = Calendar.getInstance();
        end.add(Calendar.YEAR, 10);
        KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER);
        generator.initialize(new KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256,
                KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1,
                KeyProperties.SIGNATURE_PADDING_RSA_PSS)
            .setCertificateSubject(new X500Principal("CN=atvremote"))
            .setCertificateSerialNumber(BigInteger.ONE)
            .setCertificateNotBefore(new Date())
            .setCertificateNotAfter(end.getTime())
            .build());
        generator.generateKeyPair();
        return store;
    }
}
