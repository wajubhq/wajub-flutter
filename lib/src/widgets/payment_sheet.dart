import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../checkout/checkout_types.dart';
import '../checkout/present_options.dart';
import '../models/payment_result.dart';
import '../wajub_session.dart';
import 'checkout_view.dart';
import 'present.dart';

/// The 1.x payment sheet, kept for apps that embed it themselves. It now
/// draws the full checkout of [presentWajubCheckout] — methods, Mobile Money
/// operators, confirmation steps, outcomes — and reports through its 1.x
/// callbacks: [onResult] with the outcome (complete, failed, or processing
/// when the payment is still running), [onDismiss] when the payer closes it
/// or cancels, or when the payment could not load (1.x showed the load error
/// in the sheet and reported nothing else). It never cancels the payment on
/// Wajub by itself.
@Deprecated('Use presentWajubCheckout, which resolves with a CheckoutResult and reports every state.')
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.session,
    required this.onDismiss,
    required this.onResult,
    this.locale,
    this.onPaymentStarted,
  });

  final WajubSession session;
  final VoidCallback onDismiss;
  final ValueChanged<PaymentResult> onResult;

  /// `fr` or `en`. Without it the sheet follows the payment's own language.
  final String? locale;

  /// Called when the payer submits a payment, before the provider answers.
  final VoidCallback? onPaymentStarted;

  @override
  // ignore: deprecated_member_use_from_same_package
  State<PaymentSheet> createState() => _PaymentSheetState();
}

// ignore: deprecated_member_use_from_same_package
class _PaymentSheetState extends State<PaymentSheet> {
  late final _controller = CheckoutController(
    session: widget.session,
    options: PresentOptions(
      sessionToken: widget.session.token,
      locale: widget.locale,
      cancelOnDismiss: false,
    ),
  )..onSubmit = widget.onPaymentStarted;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.result.then(_report));
  }

  void _report(CheckoutResult result) {
    if (!mounted) return;
    final legacy = legacyResult(result, _controller);
    if (legacy == null) {
      widget.onDismiss();
    } else {
      widget.onResult(legacy);
    }
  }

  @override
  Widget build(BuildContext context) =>
      WajubCheckoutView(controller: _controller, onDismissRequested: () => unawaited(_controller.dismiss()));
}

/// Shows the payment sheet as a modal bottom sheet, as 1.x did.
///
/// [onResult] receives the outcome of a payment the payer submitted:
/// [PaymentComplete], [PaymentFailed], or [PaymentProcessing] when the sheet
/// closed while it was still running. [onCancel] is called when the payer
/// closed the sheet (the close button, a swipe down, the back button) or
/// cancelled before any payment — the payment is then also cancelled on
/// Wajub (`/pay/cancel`), as the hosted checkout does, but never once the
/// payer submitted one, as in 1.x — and, as in 1.x, when the payment could
/// not load.
///
/// [locale] (`fr` or `en`) picks the sheet's language; without it the sheet
/// follows the payment's own.
@Deprecated('Use presentWajubCheckout, which resolves with a CheckoutResult and reports every state.')
Future<void> showWajubPaymentSheet({
  required BuildContext context,
  required WajubSession session,
  required ValueChanged<PaymentResult> onResult,
  VoidCallback? onCancel,
  String? locale,
}) async {
  // 1.5's rule: closing cancels the payment only when nothing was submitted.
  final controller =
      CheckoutController(session: session, options: PresentOptions(sessionToken: session.token, locale: locale))
        ..cancelOnlyBeforeSubmit = true;
  // 1.x stacked a second sheet rather than refusing it: so does this one.
  final result = await presentCheckout(context, controller, exclusive: false);
  final legacy = legacyResult(result, controller);
  if (legacy == null) {
    onCancel?.call();
  } else {
    onResult(legacy);
  }
}

/// A [CheckoutResult] as 1.x reported it; null for a sheet closed without a
/// payment: cancelled, or a payment that could not load. A payment still
/// running is [PaymentProcessing] with the last transaction known, as 1.x
/// reported it.
PaymentResult? legacyResult(CheckoutResult result, CheckoutController controller) {
  final known = controller.sessionData?.transaction;
  return switch (result) {
    CheckoutComplete(:final transaction?) => PaymentComplete(transaction),
    CheckoutFailed() when controller.screen == CheckoutScreen.loadError || controller.endedAtLoad => null,
    CheckoutFailed(:final error, :final transaction) => PaymentFailed(error: error, transaction: transaction),
    CheckoutProcessing(:final transaction) when (transaction ?? known) != null =>
      PaymentProcessing((transaction ?? known)!),
    _ => null,
  };
}
