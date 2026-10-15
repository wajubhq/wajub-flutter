import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/checkout/present_options.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';

import 'fake_api.dart';

/// Records every callback of a checkout, in order.
class Recorder {
  final events = <String>[];
  final states = <CheckoutState>[];
  final stateMethods = <String?>[];
  final redirects = <String>[];
  final errors = <WajubError>[];
  ReadyEvent? ready;
  WajubError? loadError;
  PaymentSuccess? success;
  PaymentStartedEvent? started;
  CancelEvent? cancel;
  CheckoutResult? completed;
  var completions = 0;

  CheckoutCallbacks get callbacks => CheckoutCallbacks(
        onReady: (e) {
          ready = e;
          events.add('ready');
        },
        onStateChange: (e) {
          states.add(e.state);
          stateMethods.add(e.method);
          events.add('state:${e.state.wireName}');
        },
        onLoadError: (e) {
          loadError = e;
          events.add('loadError:${e.code}');
        },
        onPaymentStarted: (e) {
          started = e;
          events.add('started:${e.method}:${e.channel}');
        },
        onRedirect: (e) {
          redirects.add(e.url);
          events.add('redirect');
        },
        onSuccess: (p) {
          success = p;
          events.add('success:${p.method}');
        },
        onError: (e) {
          errors.add(e);
          events.add('error:${e.code}');
        },
        onCancel: (e) {
          cancel = e;
          events.add('cancel:${e.reason.wireName}');
        },
        onComplete: (r) {
          completed = r;
          completions++;
          events.add('complete:${r.status}');
        },
      );
}

/// A checkout on [api], loaded, inside [async].
class Checkout {
  Checkout(
    this.async,
    this.api, {
    String? locale,
    String? returnUrl,
    bool cancelOnDismiss = true,
    Duration readyTimeout = const Duration(seconds: 15),
    Duration autoCloseSuccess = const Duration(seconds: 3),
    MobileMoneyOptions mobileMoney = const MobileMoneyOptions(),
    FakeRealtime? sockets,
    this.browserOpens = true,
    String deviceLanguage = 'en',
    Future<int?> Function(AltchaChallenge challenge)? altchaSolver,
    Future<String> Function(String publishableKey, String? cardholderName)? stripePaymentMethod,
    StripeOptions stripe = const StripeOptions(),
    Future<void> Function(String appPublishableKey)? restoreStripeKey,
    bool load = true,
  }) {
    controller = checkoutController(
      api,
      options: PresentOptions(
        sessionToken: 'tok_test',
        locale: locale,
        returnUrl: returnUrl,
        cancelOnDismiss: cancelOnDismiss,
        readyTimeout: readyTimeout,
        autoCloseSuccess: autoCloseSuccess,
        mobileMoney: mobileMoney,
        stripe: stripe,
        callbacks: recorder.callbacks,
      ),
      opened: opened,
      browserOpens: browserOpens,
      realtime: sockets,
      deviceLanguage: deviceLanguage,
      altchaSolver: altchaSolver,
      stripePaymentMethod: stripePaymentMethod,
      restoreStripeKey: restoreStripeKey,
    );
    unawaited(controller.result.then((r) => _result = r));
    if (load) {
      unawaited(controller.load());
      async.flushMicrotasks();
    }
  }

  final FakeAsync async;
  final FakeApi api;
  final bool browserOpens;
  final recorder = Recorder();
  final opened = <String>[];
  late final CheckoutController controller;
  CheckoutResult? _result;

  /// What the checkout resolved with, once it has.
  CheckoutResult? get result {
    async.flushMicrotasks();
    return _result;
  }

  /// Runs [action] and the microtasks it starts.
  void run(Future<void> Function() action) {
    unawaited(action());
    async.flushMicrotasks();
  }

  void elapse(Duration duration) => async.elapse(duration);

  CheckoutMethod method(MethodFamily family) => controller.methods.firstWhere((m) => m.family == family);

  /// Opens the Mobile Money form and types [phone].
  void mobileMoney(String phone, {String? pick}) {
    if (controller.screen != CheckoutScreen.form) controller.selectMethod(method(MethodFamily.mobileMoney));
    controller.setPhone(phone);
    if (pick != null) controller.pickOperator(pick);
  }

  /// Stops what is still running.
  void end() {
    if (!controller.settled) controller.hostGone();
    async.flushMicrotasks();
  }
}

/// Runs [body] on a virtual clock, set half an hour before the fixtures'
/// `expires_at`.
void virtual(void Function(FakeAsync async) body) => fakeAsync(body, initialTime: fixtureTime);

/// The fixtures' timestamps are `2026-10-14T09:30:00+00:00`.
final fixtureTime = DateTime.utc(2026, 10, 14, 9);
