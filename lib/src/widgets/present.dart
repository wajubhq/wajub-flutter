import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../checkout/checkout_types.dart';
import '../checkout/present_options.dart';
import '../models/wajub_error.dart';
import '../wajub_session.dart';
import 'checkout_view.dart';

/// Presents the Wajub payment sheet for [PresentOptions.sessionToken] (the
/// `authorization_token` your server got from `POST /payments`) and resolves
/// once it closes, exactly once, with a [CheckoutResult]:
///
/// - [CheckoutComplete]: paid. Confirm it server-side before delivering.
/// - [CheckoutProcessing]: closed while a payment was running; money may
///   still move.
/// - [CheckoutFailed]: closed on a failure, an ended payment or a load error.
/// - [CheckoutCancelled]: "Cancel payment", or closed before any payment.
///
/// [PresentOptions.callbacks] report each step on the way. A second call
/// while a sheet is open fails at once with the `sheet_already_presented`
/// [WajubError] and leaves the open sheet alone.
Future<CheckoutResult> presentWajubCheckout(BuildContext context, PresentOptions options) => presentCheckout(
      context,
      CheckoutController(session: WajubSession(options.sessionToken), options: options),
    );

var _presented = false;

/// Presents the sheet of [controller], which it takes over.
Future<CheckoutResult> presentCheckout(BuildContext context, CheckoutController controller) {
  if (_presented) {
    controller.dispose();
    return Future.error(WajubError.of('sheet_already_presented'));
  }
  // Set by the pops the payer makes: the close button, a swipe down, the
  // barrier, back. A route the host removes (a replacement, a reset of its
  // stack) is not popped: the sheet then settles as the host going away.
  var payerLeft = false;
  final Future<void> sheet;
  try {
    sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        // An outcome closes the sheet: pop it, unless something else covers it.
        controller.onClose = () {
          if (ModalRoute.of(sheetContext)?.isCurrent ?? false) Navigator.of(sheetContext).pop();
        };
        return PopScope<void>(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) payerLeft = true;
          },
          child: WajubCheckoutView(controller: controller, onDismissRequested: () => Navigator.of(sheetContext).pop()),
        );
      },
    );
  } catch (_) {
    controller.dispose();
    rethrow;
  }
  _presented = true;
  unawaited(sheet.then((_) => payerLeft ? controller.dismiss() : controller.hostGone()));
  return controller.result.whenComplete(() => _presented = false);
}
