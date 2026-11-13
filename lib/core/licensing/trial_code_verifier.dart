import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

abstract interface class LicenseCodeVerifier {
  bool get configured;
  String get configurationId;
  Future<bool> verify(String code);
}

/// RFC 8018 PBKDF2-HMAC-SHA256, one 32-byte block. No plaintext build secret.
List<int> deriveTrialVerifier(
  List<int> password,
  List<int> salt,
  int iterations,
) {
  if (iterations < 1) throw ArgumentError.value(iterations);
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final output = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < output.length; j++) {
      output[j] ^= u[j];
    }
  }
  return output;
}

class TrialCodeVerifier implements LicenseCodeVerifier {
  final String saltBase64;
  final String verifierBase64;
  final int iterations;
  const TrialCodeVerifier({
    required this.saltBase64,
    required this.verifierBase64,
    required this.iterations,
  });
  const TrialCodeVerifier.fromEnvironment()
    : saltBase64 = const String.fromEnvironment('TRIAL_SALT_BASE64'),
      verifierBase64 = const String.fromEnvironment('TRIAL_VERIFIER_BASE64'),
      iterations = const int.fromEnvironment('TRIAL_PBKDF2_ITERATIONS');

  @override
  String get configurationId => sha256
      .convert(utf8.encode('$saltBase64:$verifierBase64:$iterations'))
      .toString();

  @override
  bool get configured {
    try {
      return iterations >= 120000 &&
          iterations <= 1000000 &&
          base64Decode(saltBase64).length >= 16 &&
          base64Decode(verifierBase64).length == 32;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> verify(String code) async {
    if (!configured || code.isEmpty || utf8.encode(code).length > 1024) {
      return false;
    }
    final salt = base64Decode(saltBase64);
    final expected = base64Decode(verifierBase64);
    final rounds = iterations;
    return Isolate.run(() {
      final candidate = deriveTrialVerifier(utf8.encode(code), salt, rounds);
      var difference = candidate.length ^ expected.length;
      for (var i = 0; i < expected.length; i++) {
        difference |= candidate[i] ^ expected[i];
      }
      return difference == 0;
    });
  }
}
