package app.deterministic.todo.h96remote;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.Locale;

import javax.net.ssl.X509TrustManager;

/**
 * The box presents a self-signed certificate. During pairing ({@code expectedPin == null}) any
 * certificate is accepted and remembered: the pairing secret includes its public key, so a
 * successful pairing proves the code came from that same certificate. Afterwards only the
 * pinned certificate is accepted.
 */
public final class PinningTrustManager implements X509TrustManager {
    private final String expectedPin;
    private volatile X509Certificate seen;

    public PinningTrustManager(String expectedPin) {
        this.expectedPin = expectedPin;
    }

    public X509Certificate seen() {
        return seen;
    }

    @Override
    public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
        if (chain == null || chain.length == 0) throw new CertificateException("empty chain");
        X509Certificate leaf = chain[0];
        leaf.checkValidity();
        if (expectedPin != null && !expectedPin.equals(fingerprint(leaf)))
            throw new CertificateException("certificate pin mismatch");
        seen = leaf;
    }

    @Override
    public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {
        throw new CertificateException("client role only");
    }

    @Override
    public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
    }

    public static String fingerprint(X509Certificate certificate) throws CertificateEncodingException {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded());
            StringBuilder out = new StringBuilder(hash.length * 2);
            for (byte b : hash) out.append(String.format(Locale.ROOT, "%02x", b));
            return out.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
