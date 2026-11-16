// Hash or check an RCON password the way RCON plugin 1.2.0 and newer does.
//
//   RconHash              print a new hash of the password on stdin:
//                         pbkdf2-sha512:210000:<base64 salt>:<base64 hash>
//   RconHash --check      exit 0 when the password on stdin matches the hash in
//                         the RCON_CHECK_HASH environment variable (this format,
//                         or the old <base64 salt>:<base64 hash>)
//
// The password is read from stdin, exactly as given (no newline is removed),
// and the hash from the environment, so neither shows on a command line. The
// image compiles this file at build time (see the Dockerfile);
// scripts/steps/_common.sh calls it.

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

public final class RconHash {
  // Same values as the plugin's AuthenticationService
  private static final int ITERATIONS = 210_000;
  private static final int MIN_ITERATIONS = 10_000;
  private static final int MAX_ITERATIONS = 1_000_000;
  private static final int SALT_BYTES = 16;
  private static final int HASH_BYTES = 32;

  public static void main(String[] args) throws Exception {
    String password = new String(System.in.readAllBytes(), StandardCharsets.UTF_8);
    if (password.isEmpty()) {
      System.err.println("RconHash: no password on stdin");
      System.exit(2);
    }
    if (args.length == 0) {
      byte[] salt = new byte[SALT_BYTES];
      new SecureRandom().nextBytes(salt);
      Base64.Encoder b64 = Base64.getEncoder();
      System.out.println("pbkdf2-sha512:" + ITERATIONS + ":" + b64.encodeToString(salt) + ":"
          + b64.encodeToString(pbkdf2(password, salt, ITERATIONS, HASH_BYTES)));
      return;
    }
    String stored = System.getenv("RCON_CHECK_HASH");
    if (args.length == 1 && args[0].equals("--check") && stored != null) {
      System.exit(matches(password, stored) ? 0 : 1);
    }
    System.err.println("Usage: RconHash < password, or RCON_CHECK_HASH=... RconHash --check < password");
    System.exit(2);
  }

  private static boolean matches(String password, String stored) throws Exception {
    String[] parts = stored.split(":", -1);
    Base64.Decoder b64 = Base64.getDecoder();
    try {
      if (parts.length == 2) {
        byte[] salt = b64.decode(parts[0]);
        byte[] hash = b64.decode(parts[1]);
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        sha.update(salt);
        sha.update(password.getBytes(StandardCharsets.UTF_8));
        return hash.length == 32 && MessageDigest.isEqual(hash, sha.digest());
      }
      if (parts.length == 4 && parts[0].equals("pbkdf2-sha512") && parts[1].matches("[0-9]{1,9}")) {
        int iterations = Integer.parseInt(parts[1]);
        byte[] salt = b64.decode(parts[2]);
        byte[] hash = b64.decode(parts[3]);
        if (iterations < MIN_ITERATIONS || iterations > MAX_ITERATIONS
            || salt.length == 0 || hash.length < 16 || hash.length > 64) {
          return false;
        }
        return MessageDigest.isEqual(hash, pbkdf2(password, salt, iterations, hash.length));
      }
    } catch (IllegalArgumentException e) {
      return false; // bad base64
    }
    return false;
  }

  private static byte[] pbkdf2(String password, byte[] salt, int iterations, int bytes)
      throws Exception {
    PBEKeySpec spec = new PBEKeySpec(password.toCharArray(), salt, iterations, bytes * 8);
    try {
      return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA512").generateSecret(spec).getEncoded();
    } finally {
      spec.clearPassword();
    }
  }
}
