// The README's Dart samples, as written there, so that `flutter analyze`
// checks they compile; the test below fails when the README changes without
// this file. A sample reads as an excerpt of an app: the names it takes from
// that app are parameters here.
// ignore_for_file: avoid_print, unused_local_variable, dead_code, deprecated_member_use
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/wajub_mobile.dart';

String newIdempotencyKey() => 'a UUID per press of Pay';

Future<void> quickStart(BuildContext context, String authorizationToken) async {
  final result = await presentWajubCheckout(
    context,
    PresentOptions(sessionToken: authorizationToken),
  );

  switch (result) {
    case CheckoutComplete(:final payment):
      // Paid: payment.id is Wajub's payment id. Confirm it on your server.
      break;
    case CheckoutProcessing():
      // Closed while a payment was running: money may still move. Your server
      // learns the outcome from the webhook.
      break;
    case CheckoutFailed(:final error):
      // A failure, an ended or expired payment, or a load error (error.code).
      break;
    case CheckoutCancelled(:final reason):
      // "Cancel payment", or closed before any payment (reason.wireName).
      break;
  }
}

PresentOptions options(String authorizationToken) {
  return PresentOptions(
    sessionToken: authorizationToken,
    locale: 'fr', // 'fr' | 'en'; else the payment's, else the device's
    appearance: const Appearance(theme: 'night'), // see Appearance below
    loader: WajubLoader.skeleton, // or WajubLoader.spinner
    readyTimeout: const Duration(seconds: 15), // Duration.zero waits forever
    returnUrl: 'https://shop.example.com/app/return', // an https universal/app link into your app
    mobileMoney: const MobileMoneyOptions(
      country: 'CI', // the country to start on
      countryLocked: true, // hide the country selector
      operatorMode: OperatorMode.detect, // the operator comes from the number
    ),
    realtime: const RealtimeOptions(host: 'ws.shop.example', port: 443, tls: true), // or enabled: false
    cancelOnDismiss: true, // a dismiss before any payment cancels it on Wajub
    autoCloseSuccess: const Duration(seconds: 3), // Duration.zero keeps the success screen
    stripe: const StripeOptions(appPublishableKey: 'pk_live_…'), // your app's own Stripe key, if it has one
    callbacks: CheckoutCallbacks(/* … */),
  );
}

CheckoutCallbacks callbacks() {
  return CheckoutCallbacks(
    onReady: (e) {}, // ReadyEvent: sessionId, environment, amount, currency, methods (slugs)
    onStateChange: (e) {}, // StateChangeEvent: state (CheckoutState), method
    onLoadError: (error) {}, // the sheet could not offer a payment
    onPaymentStarted: (e) {}, // first accepted request: from now on a dismiss resolves `processing`
    onRedirect: (e) {}, // e.url, right before the system browser opens
    onSuccess: (payment) {}, // PaymentSuccess: id, reference, amount, currency, method, timestamp, receiptUrl
    onError: (error) {}, // every failure the payer sees, retryable ones included
    onCancel: (e) {}, // CancelEvent: reason, redirectUrl
    onComplete: (result) {}, // the CheckoutResult presentWajubCheckout resolves with
  );
}

void appearances(String appearanceJson) {
  const appearance = Appearance(
    theme: 'stripe', // presets: stripe, night, flat, none — or light, dark, auto
    colorScheme: 'auto', // light | dark | auto (follows the phone, live)
    variables: AppearanceVariables(
      colorPrimary: '#0F766E',
      colorBackground: '#FFFFFF',
      colorText: '#171717',
      colorDanger: '#B91C1C',
      fontFamily: 'Inter', // used when your app ships it
      borderRadius: '12px',
      spacingUnit: '4px',
    ),
    buttonTextColor: '#FFFFFF', // Wajub.js's top-level keys work too
    disableAnimations: false,
  );

  // Or the very object your web checkout uses:
  final shared = Appearance.fromMap(jsonDecode(appearanceJson) as Map<String, Object?>);
}

Future<void> headless(String authorizationToken) async {
  final session = Wajub.createSession(authorizationToken);
  final data = await session.loadSession();
  final config = await session.getSdkConfig();
  // `sdk` is a string: compare it with the SdkFlavor constants (not an enum).
  final stripeCard = config.channels['card']?.sdk == SdkFlavor.stripeElements; // keyed by channel slug

  // One Idempotency-Key per press of Pay; pass the same one again only to resend
  // a payment that got no answer.
  final key = newIdempotencyKey(); // yours: a UUID per press of Pay
  final result = await session.processPayment(
    'cm.mobile',
    {'phone': '+237677123456', 'country': 'CM', 'operator': 'mtn'},
    idempotencyKey: key,
  );
  switch (result) {
    case PaymentComplete():
      // Paid.
      break;
    case PaymentProcessing(kind: ProcessingKind.approval, :final instruction):
      // Approve the push on the phone; follow the status.
      print(instruction); // the provider's words, when it gives some
    case PaymentProcessing(kind: ProcessingKind.ussd, :final instruction):
      // Dial the USSD code it gives; follow the status.
      print(instruction);
    case PaymentProcessing():
      // Pending, or no answer at all (network, timeout, 5xx): the charge may be
      // running. Follow the status; if it still reads a plain `pending` 60 s
      // later, call processPayment again with the same `key`.
      break;
    case PaymentRequiresAction(:final step?, :final stepId?):
      // confirm_otp, confirm_pin, confirm_phone, confirm_birthday, confirm_address
      final answer = await session.verifyStep(step, stepId, {'code': '123456'});
      if (!answer.success) print(WajubError.fromStep(answer).message);
    case PaymentRequiresAction(:final actionUrl?):
      // A provider page (3-D Secure, a wallet): open it, then follow the status.
      await session.handleRedirectAction(result);
      print(actionUrl);
    case PaymentRequiresAction():
      break;
    case PaymentFailed(:final error):
      // A refusal (error.code, error.message for the payer, error.retryable).
      print(error.message);
  }

  await for (final update in session.watchStatus()) {
    // PaymentProcessing on each change, then PaymentComplete or PaymentFailed.
    print(update);
  }
}

Future<void> clientSession(WajubSession session) async {
  final started = await session.startClientSession(channelSlug: 'card', email: 'payer@example.com');
  if (started is PaymentRequiresAction && started.action == ActionKind.clientSession) {
    final cs = started.clientSession!;
    await session.handleRedirectAction(started); // opens cs.hostedUrl in the system browser
    // …when the app is back in the foreground:
    final result = await session.completeClientSession(cs.id);
  }
}

Future<void> migration(
  BuildContext context,
  WajubSession session,
  String token,
  ValueChanged<PaymentResult> handle,
  VoidCallback cancelled,
) async {
  // 1.5
  await showWajubPaymentSheet(context: context, session: session, onResult: handle, onCancel: cancelled);
  // 1.6
  final result = await presentWajubCheckout(context, PresentOptions(sessionToken: token));
}

/// Every ```dart block of the README, its lines without their whitespace.
List<String> readmeSamples(String readme) {
  final samples = <String>[];
  StringBuffer? block;
  for (final line in const LineSplitter().convert(readme)) {
    final trimmed = line.trim();
    if (block == null) {
      if (trimmed == '```dart') block = StringBuffer();
    } else if (trimmed == '```') {
      samples.add(block.toString());
      block = null;
    } else {
      block.write(line.replaceAll(RegExp(r'\s+'), ''));
    }
  }
  return samples;
}

void main() {
  test('every README Dart sample is in this file, where the analyzer checks it', () {
    final readme = File('README.md').readAsStringSync();
    final here = File('test/readme_samples_test.dart').readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    final samples = readmeSamples(readme);
    expect(samples, hasLength(greaterThanOrEqualTo(7)));
    for (final sample in samples) {
      // The import is at the top here; the rest of the sample in one piece.
      final body = sample.replaceAll("import'package:wajub_mobile/wajub_mobile.dart';", '');
      // Samples that are a bare expression are returned here.
      expect(here.contains(body) || here.contains('return$body;'), isTrue,
          reason: 'README sample not checked: $sample');
    }
  });
}
