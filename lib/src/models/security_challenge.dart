import 'json_read.dart';

/// The proof of work the API may ask for before a payment. Internal: the SDK
/// solves it.
class SecurityChallenge {
  const SecurityChallenge({
    required this.algorithm,
    required this.challenge,
    required this.salt,
    required this.signature,
    required this.maxNumber,
  });

  final String algorithm;
  final String challenge;
  final String salt;
  final String signature;
  final int maxNumber;

  static SecurityChallenge? fromJson(Object? json) {
    final map = readMap(json);
    final challenge = readText(map?['challenge']);
    final salt = readString(map?['salt']);
    if (map == null || challenge == null || salt == null) return null;
    return SecurityChallenge(
      algorithm: readString(map['algorithm']) ?? 'SHA-256',
      challenge: challenge,
      salt: salt,
      signature: readString(map['signature']) ?? '',
      maxNumber: readInt(map['maxnumber']) ?? 1000000,
    );
  }
}
