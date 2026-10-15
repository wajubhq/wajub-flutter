// The README's Dart samples, as written there, so that `flutter analyze`
// checks they compile; the test below fails when the README changes without
// this file. A sample reads as an excerpt of an app: the names it takes from
// that app are parameters here.
// ignore_for_file: unused_local_variable

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/wajub_mobile.dart';

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
    cancelOnDismiss: true, // closing before any payment cancels it
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
    onPaymentStarted: (e) {}, // the payment was accepted: from now on, closing resolves `processing`
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
    colorScheme: 'auto', // light | dark | auto (follows the phone)
    inherit: true, // read Theme.of(context) where you set nothing
    variables: AppearanceVariables(
      colorPrimary: '#0F766E',
      colorBackground: '#FFFFFF',
      colorText: '#171717',
      colorDanger: '#B91C1C',
      fontFamily: 'Inter', // used when your app ships it
      borderRadius: '12px',
      spacingUnit: '4px',
    ),
    buttonTextColor: '#FFFFFF',
    disableAnimations: false,
  );

  // Or from a map, such as decoded JSON:
  final shared = Appearance.fromMap(jsonDecode(appearanceJson) as Map<String, Object?>);
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
    expect(samples, hasLength(4));
    for (final sample in samples) {
      // The import is at the top here; the rest of the sample in one piece.
      final body = sample.replaceAll("import'package:wajub_mobile/wajub_mobile.dart';", '');
      // Samples that are a bare expression are returned here.
      expect(here.contains(body) || here.contains('return$body;'), isTrue,
          reason: 'README sample not checked: $sample');
    }
  });
}
