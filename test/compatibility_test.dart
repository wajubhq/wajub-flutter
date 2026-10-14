// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/wajub_mobile.dart';

/// Code written against 1.5 compiles and behaves the same: an exhaustive
/// `switch` over its enums and sealed types, its entry points and callbacks.
String describe(PaymentResult result) => switch (result) {
      PaymentComplete() => 'complete',
      PaymentProcessing() => 'processing',
      PaymentRequiresAction(:final action) => switch (action) {
          ActionKind.redirect => 'redirect',
          ActionKind.confirm => 'confirm',
          ActionKind.confirm3ds => 'confirm3ds',
          ActionKind.pushApproval => 'pushApproval',
          ActionKind.clientSession => 'clientSession',
        },
      PaymentFailed() => 'failed',
    };

String describeType(WajubErrorType type) => switch (type) {
      WajubErrorType.apiError => 'api',
      WajubErrorType.authenticationError => 'authentication',
      WajubErrorType.invalidRequestError => 'invalid',
      WajubErrorType.paymentError => 'payment',
      WajubErrorType.rateLimitError => 'rate',
    };

void main() {
  test('the 1.5 public API still compiles and keeps its meaning', () {
    const transaction =
        SessionTransaction(id: 'trx_1', reference: 'R1', amount: 100, currency: 'XAF', status: 'pending');
    expect(describe(const PaymentRequiresAction(action: ActionKind.confirm, transaction: transaction)), 'confirm');
    expect(describeType(WajubError.network('down').type), 'api');

    final session = Wajub.createSession('tok');
    final Future<void> Function({
      required BuildContext context,
      required WajubSession session,
      required ValueChanged<PaymentResult> onResult,
      VoidCallback? onCancel,
      String? locale,
    }) show = showWajubPaymentSheet;
    expect(show, isNotNull);
    final sheet =
        PaymentSheet(session: session, onDismiss: () {}, onResult: (_) {}, locale: 'fr', onPaymentStarted: () {});
    expect(sheet.locale, 'fr');
    final Stream<PaymentResult> Function({Duration interval}) watch = session.watchStatus;
    expect(watch, isNotNull);
    expect(const MobileMoneyInput(channelSlug: 'cm.mtn', phone: '+237670000000', country: 'CM').operator, isNull);
    expect(const ClientSessionOptions(email: 'a@b.c').toJson(), {'email': 'a@b.c'});
  });
}
