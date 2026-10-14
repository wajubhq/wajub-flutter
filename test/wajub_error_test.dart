import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';

void main() {
  group('WajubError.fromHttp', () {
    test('reads an ended session (410) as an authentication error the payer cannot retry', () {
      final error = WajubError.fromHttp(410, 'Session expired', 'session_expired', const {}, null, null);
      expect(error.type, WajubErrorType.authenticationError);
      expect(error.retryable, isFalse);
    });

    for (final status in const [401, 404]) {
      test('reads a token that is not a session ($status) as an authentication error the payer cannot retry', () {
        final error =
            WajubError.fromHttp(status, 'Payment session not found', 'session_not_found', const {}, null, null);
        expect(error.type, WajubErrorType.authenticationError);
        expect(error.retryable, isFalse);
      });
    }

    test('reads a server error as Wajub side, not as a declined payment', () {
      final error = WajubError.fromHttp(503, 'Unavailable', 'service_unavailable', const {}, null, null);
      expect(error.type, WajubErrorType.apiError);
      expect(error.retryable, isTrue);
      expect(error.declineCode, isNull);
    });

    test('names the refused field in param when the refusal is about one field', () {
      expect(
        WajubError.fromHttp(
                422, 'Invalid phone', 'validation_error', const {'data.phone': 'Invalid phone number.'}, null, null)
            .param,
        'data.phone',
      );
      expect(
        WajubError.fromHttp(422, 'Two fields', 'validation_error', const {'phone': 'x', 'email': 'y'}, null, null)
            .param,
        isNull,
      );
    });
  });
}
