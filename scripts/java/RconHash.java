// Hash or check an RCON password the way RCON plugin 1.2.0 and newer does.
//
//   RconHash              print a new hash of the password on stdin:
//                         pbkdf2-sha512:210000:<base64 salt>:<base64 hash>
//   RconHash --check      exit 0 when the password on stdin matches the hash in
//                         the RCON_CHECK_HASH environment variable (this format,
//                         or the old <base64 salt>:<base64 hash>), 10 when not
//   RconHash --validate   exit 0 when the hash in RCON_CHECK_HASH is one the
//                         plugin accepts; else print why and exit 10
//
// Other exit codes: 2 for bad usage or an empty password, 3 for any other
// failure. "No" is 10, not 1, because a JVM that cannot start exits with 1.
//
// The password is read from stdin, exactly as given (no newline is removed),
// and the hash from the environment, so neither shows on a command line. The image compiles this file at build time (see the Dockerfile);
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

  public static void main(String[] args) {
    try {
      System.exit(run(args));
    } catch (Exception e) {
      System.err.println("RconHash: " + e);
      System.exit(3);
    }
  }

  private static int run(String[] args) throws Exception {
    String stored = System.getenv("RCON_CHECK_HASH");
    if (args.length == 1 && args[0].equals("--validate") && stored != null) {
      String problem = parse(stored, null);
      if (problem == null) {
        return 0;
      }
      System.out.println(problem);
      return 10;
    }
    boolean check = args.length == 1 && args[0].equals("--check") && stored != null;
    if (args.length != 0 && !check) {
      System.err.println("Usage: RconHash < password, RCON_CHECK_HASH=... RconHash --check < password,"
          + " or RCON_CHECK_HASH=... RconHash --validate");
      return 2;
    }
    String password = new String(System.in.readAllBytes(), StandardCharsets.UTF_8);
    if (password.isEmpty()) {
      System.err.println("RconHash: no password on stdin");
      return 2;
    }
    if (check) {
      return parse(stored, password) == null ? 0 : 10;
    }
    byte[] salt = new byte[SALT_BYTES];
    new SecureRandom().nextBytes(salt);
    Base64.Encoder b64 = Base64.getEncoder();
    System.out.println("pbkdf2-sha512:" + ITERATIONS + ":" + b64.encodeToString(salt) + ":"
        + b64.encodeToString(pbkdf2(password, salt, ITERATIONS, HASH_BYTES)));
    return 0;
  }

  // Check the hash's form and, when password is not null, the password too.
  // Returns null when all is fine, else why not.
  private static String parse(String stored, String password) throws Exception {
    String[] parts = stored.split(":", -1);
    Base64.Decoder b64 = Base64.getDecoder();
    try {
      if (parts.length == 2) {
        byte[] salt = b64.decode(parts[0]);
        byte[] hash = b64.decode(parts[1]);
        if (salt.length == 0 || hash.length != 32) {
          return "the old format needs a salt and a 32-byte hash";
        }
        if (password == null) {
          return null;
        }
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        sha.update(salt);
        sha.update(password.getBytes(StandardCharsets.UTF_8));
        return MessageDigest.isEqual(hash, sha.digest()) ? null : "wrong password";
      }
      if (parts.length == 4 && parts[0].equals("pbkdf2-sha512") && parts[1].matches("[0-9]{1,9}")) {
        int iterations = Integer.parseInt(parts[1]);
        byte[] salt = b64.decode(parts[2]);
        byte[] hash = b64.decode(parts[3]);
        if (iterations < MIN_ITERATIONS || iterations > MAX_ITERATIONS) {
          return "its iteration count must be from " + MIN_ITERATIONS + " to " + MAX_ITERATIONS;
        }
        if (salt.length == 0 || hash.length < 16 || hash.length > 64) {
          return "it needs a salt and a hash of 16 to 64 bytes";
        }
        if (password == null) {
          return null;
        }
        return MessageDigest.isEqual(hash, pbkdf2(password, salt, iterations, hash.length))
            ? null : "wrong password";
      }
    } catch (IllegalArgumentException e) {
      return "a part is not valid base64";
    }
    return "it is not a hash from gen-psswd (check for spaces or a missing part)";
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
