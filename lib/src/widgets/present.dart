import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../checkout/checkout_types.dart';
import '../checkout/present_options.dart';
import '../models/wajub_error.dart';
import '../wajub_session.dart';
import 'checkout_view.dart';

/// Presents the Wajub payment sheet for [PresentOptions.sessionToken] (the
/// `authorization_token` your server got when it created the payment) and
/// resolves once it closes, exactly once, with a [CheckoutResult]:
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

/// Presents the sheet of [controller], which it takes over. [exclusive]:
/// refuse it while another exclusive sheet is open (the deprecated 1.x
/// entry point stacks, as it did).
Future<CheckoutResult> presentCheckout(BuildContext context, CheckoutController controller, {bool exclusive = true}) {
  if (exclusive && _presented) {
    controller.dispose();
    return Future.error(WajubError.of('sheet_already_presented'));
  }
  if (!context.mounted) {
    // The page meant to present it is already gone: settle at once.
    controller.hostGone();
    final result = controller.result;
    controller.dispose();
    return result;
  }
  // Only the payer's own ways out are a dismiss: the close button, back and
  // the barrier (held by the PopScope, then popped here), and a swipe down
  // (the sheet pops itself as the finger lifts). Any other removal — the
  // host popping or replacing its stack — is the host going away, which
  // never cancels the payment.
  var payerLeft = false;
  var fingerLifted = false;
  final Future<void> sheet;
  try {
    sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        void leave() {
          // Not while a cancel call runs: its answer closes the sheet.
          if (controller.cancelling) return;
          payerLeft = true;
          Navigator.of(sheetContext).pop();
        }

        // An outcome closes the sheet, even under a page the host pushed.
        controller.onClose = () {
          final route = ModalRoute.of(sheetContext);
          if (route == null || !route.isActive) return;
          if (route.isCurrent) {
            Navigator.of(sheetContext).pop();
          } else {
            Navigator.of(sheetContext).removeRoute(route);
          }
        };
        return Listener(
          onPointerUp: (_) {
            fingerLifted = true;
            scheduleMicrotask(() => fingerLifted = false);
          },
          child: PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                leave();
              } else if (fingerLifted) {
                payerLeft = true;
              }
            },
            child: WajubCheckoutView(controller: controller, onDismissRequested: leave),
          ),
        );
      },
    );
  } catch (_) {
    controller.dispose();
    rethrow;
  }
  if (exclusive) _presented = true;
  // The next sheet may open as soon as this one is gone, while a dismiss's
  // cancel call still runs.
  var freed = !exclusive;
  void free() {
    if (freed) return;
    freed = true;
    _presented = false;
  }

  // Free before the callbacks run: `onComplete` may present the next sheet.
  controller.onSettling = free;
  unawaited(sheet.then((_) {
    free();
    if (payerLeft) {
      unawaited(controller.dismiss());
    } else {
      controller.hostGone();
    }
  }));
  return controller.result.whenComplete(free);
}
