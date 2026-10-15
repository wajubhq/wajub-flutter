import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/security_challenge.dart';
import '../models/wajub_error.dart';

/// The proof of work the API may ask for (spec README §15): the integer `n`
/// in `[0, maxnumber]` with `lowercase_hex(SHA-256(salt + n)) == challenge`,
/// or null when there is none.
int? solveAltcha(SecurityChallenge challenge) {
  final target = challenge.challenge.toLowerCase();
  for (var n = 0; n <= challenge.maxNumber; n++) {
    if (sha256.convert(utf8.encode('${challenge.salt}$n')).toString() == target) return n;
  }
  return null;
}

/// What `/pay/process` sends as `data.altcha` and `/pay/client-session` as
/// `altcha`.
Map<String, Object?> altchaPayload(SecurityChallenge challenge, int number) => {
      'algorithm': challenge.algorithm,
      'challenge': challenge.challenge,
      'number': number,
      'salt': challenge.salt,
      'signature': challenge.signature,
    };

/// A 422 that refuses the challenge's solution: recognised by its code; an
/// older answer had none and only its message (`validation_error` then)
/// told it apart.
bool isSecurityRefusal(WajubError error) =>
    error.httpStatus == 422 &&
    (error.code == 'security_check_failed' ||
        (error.code == 'validation_error' &&
            (error.details.containsKey('altcha') || (error.apiMessage ?? '').contains('Security challenge'))));
