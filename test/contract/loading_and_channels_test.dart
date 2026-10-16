import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

FakeApi loading(Object session, {Object config = 'sdk-config-cm-stripe.json', Object? status}) => FakeApi(routes: {
      'GET /pay/session': session,
      'GET /pay/sdk-config': config,
      if (status != null) 'GET /pay/status': status,
    });

List<String> slugsOf(List<CheckoutMethod> methods) => [
      for (final method in methods) '${method.family.wireName}:${method.channels.map((c) => c.slug).join(',')}',
    ];

void main() {
  test('LD-01 loads session and sdk-config in parallel', () {
    virtual((async) {
      final api = loading(
        FakeAnswer.fixture('session-cm-aggregate.json', delay: const Duration(seconds: 2)),
        config: const FakeAnswer(500, {'code': 500, 'status': 'Internal Server Error', 'message': 'boom'}),
      );
      final checkout = Checkout(async, api);
      expect(api.calls('/pay/session'), hasLength(1));
      expect(api.calls('/pay/sdk-config'), hasLength(1), reason: 'both start before the session answers');
      checkout.elapse(const Duration(seconds: 30));
      // sdk-config failed after its retries: Mobile Money still shows, the card does not.
      expect(api.calls('/pay/sdk-config'), hasLength(4));
      expect(checkout.controller.methods.map((m) => m.family), [MethodFamily.mobileMoney]);
      expect(checkout.controller.screen, CheckoutScreen.form);
      checkout.end();
    });

    // Without Mobile Money, a failed sdk-config leaves nothing to offer yet:
    // a load error to retry, never no_payment_method.
    final cardOnly = fixtureBody('session-cm-aggregate.json');
    cardOnly['channels'] = [
      for (final channel in cardOnly['channels'] as List)
        if ((channel as Map)['type'] == 'card') channel,
    ];
    final walletOnly = fixtureBody('session-ci-xof-wallets.json');
    walletOnly['channels'] = [
      for (final channel in walletOnly['channels'] as List)
        if ((channel as Map)['type'] == 'wallet') channel,
    ];
    for (final (name, body, config) in [
      ('card only', cardOnly, 'sdk-config-cm-stripe.json'),
      ('wallets only', walletOnly, 'sdk-config-ci-wallets.json'),
    ]) {
      for (final failure in [const FakeAnswer.network(), FakeAnswer.fixture('error-500-production.json')]) {
        virtual((async) {
          final api = loading(FakeAnswer(200, body), config: [failure, failure, failure, failure, config]);
          final checkout = Checkout(async, api);
          checkout.elapse(const Duration(seconds: 14));
          expect(checkout.controller.screen, CheckoutScreen.loadError, reason: name);
          expect(checkout.controller.error?.code, 'load_error', reason: name);
          expect(checkout.controller.error?.retryable, isTrue);
          expect(checkout.recorder.loadError?.code, 'load_error');
          checkout.run(checkout.controller.retryLoad);
          expect(checkout.controller.screen, CheckoutScreen.form, reason: 'Retry reloads: $name');
          checkout.end();
        });
      }
    }
  });

  test('LD-02 maps unknown sessions to session_not_found', () {
    for (final name in [
      'error-401-invalid-token.json',
      'error-401-missing-token.json',
      'error-403-not-a-payment-session.json',
    ]) {
      virtual((async) {
        final checkout = Checkout(async, loading(name));
        expect(checkout.controller.screen, CheckoutScreen.loadError, reason: name);
        expect(checkout.recorder.loadError?.code, 'session_not_found');
        expect(checkout.recorder.loadError?.type, WajubErrorType.authenticationError);
        expect(checkout.recorder.loadError?.retryable, isFalse);
        expect(checkout.recorder.ready, isNull, reason: 'no form');
        checkout.elapse(const Duration(seconds: 20));
        expect(checkout.recorder.events.where((e) => e.startsWith('loadError')), hasLength(1),
            reason: 'no ready_timeout after a load error');
        checkout.controller.close();
        expect((checkout.result as CheckoutFailed).error.code, 'session_not_found');
      });
    }
  });

  test('LD-03 maps both 410s to session_terminal_expired', () {
    for (final name in ['error-410-session-terminal-expired.json', 'error-410-session-expired.json']) {
      virtual((async) {
        final checkout = Checkout(async, loading(name));
        expect(checkout.recorder.loadError?.code, 'session_terminal_expired', reason: name);
        expect(checkout.recorder.loadError?.retryable, isFalse);
        checkout.end();
      });
    }
  });

  test('LD-04 shows an already paid session as success', () {
    // From the session alone, at once: sdk-config hanging changes nothing.
    virtual((async) {
      final checkout = Checkout(async, loading('session-terminal-succeeded.json', config: const FakeAnswer.hang()),
          autoCloseSuccess: Duration.zero);
      expect(checkout.controller.screen, CheckoutScreen.success);
      checkout.elapse(const Duration(seconds: 20));
      expect(checkout.recorder.loadError, isNull, reason: 'no ready_timeout');
      checkout.end();
    });
    virtual((async) {
      final checkout = Checkout(async, loading('session-terminal-succeeded.json'));
      expect(checkout.controller.screen, CheckoutScreen.success);
      expect(checkout.recorder.events.take(3), ['ready', 'state:SUCCESS', 'success:unknown']);
      expect(checkout.recorder.loadError, isNull);
      expect(checkout.recorder.success?.receiptUrl, contains('invoice.wajub.com'));
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.result, isA<CheckoutComplete>());
      expect((checkout.result as CheckoutComplete).payment.method, 'unknown');
    });
  });

  test('LD-05 reports ended sessions with Wajub.js codes', () {
    final cases = {
      'session-terminal-failed.json': ('session_terminal_failed', CheckoutState.failed),
      'session-terminal-cancelled.json': ('session_terminal_cancelled', CheckoutState.cancelled),
      'session-terminal-expired.json': ('session_terminal_expired', CheckoutState.expired),
    };
    cases.forEach((name, expected) {
      for (final config in [
        const FakeAnswer.hang(),
        FakeAnswer.fixture('error-500-production.json'),
        FakeAnswer.fixture('sdk-config-cm-stripe.json'),
      ]) {
        // From the session alone, at once, whatever sdk-config does.
        virtual((async) {
          final checkout = Checkout(async, loading(name, config: config));
          expect(checkout.controller.state, expected.$2, reason: '$name ${config.status}');
          checkout.elapse(const Duration(seconds: 20));
          expect(checkout.recorder.loadError?.code, expected.$1, reason: 'not ready_timeout');
          checkout.end();
        });
      }
      virtual((async) {
        final checkout = Checkout(async, loading(name));
        final (code, state) = expected;
        expect(checkout.controller.screen, CheckoutScreen.failed, reason: name);
        expect(checkout.controller.endedAtLoad, isTrue);
        expect(checkout.controller.state, state);
        expect(checkout.recorder.loadError?.code, code);
        expect(checkout.controller.methods.isEmpty || checkout.controller.method == null, isTrue, reason: 'no form');
        checkout.controller.close();
        expect((checkout.result as CheckoutFailed).error.code, code);
      });
    });
  });

  test('LD-06 restores a pending approval', () {
    for (final config in [const FakeAnswer.hang(), FakeAnswer.fixture('error-500-production.json')]) {
      // From the session alone, at once: sdk-config only adds methods later.
      virtual((async) {
        final api = loading('session-processing-mobile-money.json', config: config, status: 'status-processing.json');
        final checkout = Checkout(async, api);
        expect(checkout.controller.state, CheckoutState.approvalRequired);
        checkout.elapse(const Duration(seconds: 20));
        expect(checkout.controller.state, CheckoutState.approvalRequired);
        expect(checkout.recorder.loadError, isNull, reason: 'no ready_timeout');
        checkout.end();
      });
    }
    for (final name in ['session-processing-mobile-money.json', 'session-processing-mobile-money-live.json']) {
      virtual((async) {
        final api = loading(name, status: 'status-processing.json');
        final checkout = Checkout(async, api);
        expect(checkout.controller.state, CheckoutState.approvalRequired, reason: name);
        expect(checkout.controller.instruction, startsWith('Confirm the transaction on your phone.'));
        expect(api.calls('/pay/status'), hasLength(1), reason: 'watching starts at once');
        checkout.run(checkout.controller.dismiss);
        expect(checkout.result, isA<CheckoutProcessing>(), reason: 'an attempt is running');
      });
    }
  });

  test('LD-10 reads the refusal left at load', () {
    virtual((async) {
      // The form opens, without a failure; the same refusal read later is
      // the old one, not this sheet's: the watch goes on to the 60 s rule.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-pending-after-refusal.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': const FakeAnswer.network(),
        'GET /pay/status': 'status-pending-attempt-refused.json',
      });
      final checkout = Checkout(async, api);
      expect(checkout.controller.sessionData!.transaction.errorCode, isNotNull);
      expect(checkout.controller.screen, isNot(CheckoutScreen.failed));
      expect(checkout.recorder.errors, isEmpty);
      expect(checkout.recorder.loadError, isNull);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 30));
      expect(checkout.controller.state, CheckoutState.pending, reason: 'the code the session carried is not news');
      checkout.elapse(const Duration(seconds: 40));
      expect(checkout.controller.state, CheckoutState.collectingDetails, reason: 'the 60 s rule');
      expect(checkout.controller.banner, isNotNull);
      checkout.end();
    });
    virtual((async) {
      // A different code is this attempt's refusal, at once.
      final session = fixtureBody('session-pending-after-refusal.json');
      (session['transaction'] as Map)['error_code'] = 'payment_declined';
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': const FakeAnswer.network(),
        'GET /pay/status': 'status-pending-attempt-refused.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 15));
      expect(checkout.controller.state, CheckoutState.failed);
      checkout.end();
    });
    for (final keyed in [true, false]) {
      virtual((async) {
        // `error_code: null` says no refusal is left: a code read after an
        // unanswered Pay is this attempt's refusal. Without the key (an API
        // older than 2.1) nothing is known: no code is taken for this
        // attempt's refusal before the 60 s rule.
        final session = fixtureBody('session-cm-aggregate.json');
        final transaction = session['transaction'] as Map;
        expect(transaction.containsKey('error_code'), isTrue);
        if (!keyed) transaction.remove('error_code');
        final api = FakeApi(routes: {
          'GET /pay/session': FakeAnswer(200, session),
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': const FakeAnswer.network(),
          'GET /pay/status': 'status-pending-attempt-refused.json',
        });
        final checkout = Checkout(async, api);
        expect(checkout.controller.sessionData!.transaction.errorCode, isNull);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.elapse(const Duration(seconds: 15));
        if (keyed) {
          expect(checkout.controller.state, CheckoutState.failed, reason: 'null: the code is news');
          expect(checkout.controller.error?.code, 'insufficient_funds');
        } else {
          expect(checkout.controller.state, CheckoutState.pending, reason: 'no key: unknown baseline');
          checkout.elapse(const Duration(seconds: 55));
          expect(checkout.controller.state, CheckoutState.collectingDetails, reason: 'the 60 s rule');
        }
        checkout.end();
      });
    }
  });

  test('LD-08 raises ready_timeout', () {
    virtual((async) {
      final api = loading(FakeAnswer.fixture('session-cm-aggregate.json', delay: const Duration(seconds: 20)));
      final checkout = Checkout(async, api);
      checkout.elapse(const Duration(seconds: 15));
      final error = checkout.recorder.loadError!;
      expect(error.code, 'ready_timeout');
      expect(error.type, WajubErrorType.apiError);
      expect(error.retryable, isTrue);
      expect(error.apiMessage, 'Payment sheet not ready after 15000 ms');
      expect(checkout.controller.screen, CheckoutScreen.loadError);
      expect(checkout.recorder.ready, isNull);

      // The data arrives later: the sheet becomes ready and shows it.
      checkout.elapse(const Duration(seconds: 5));
      expect(checkout.recorder.ready, isNotNull);
      expect(checkout.controller.screen, CheckoutScreen.methods);
      checkout.end();
    });
    virtual((async) {
      final api = loading(FakeAnswer.fixture('session-cm-aggregate.json', delay: const Duration(seconds: 20)));
      final checkout = Checkout(async, api);
      checkout.elapse(const Duration(seconds: 15));
      checkout.run(checkout.controller.retryLoad);
      expect(api.calls('/pay/session'), hasLength(2));
      expect(checkout.controller.screen, CheckoutScreen.loading, reason: 'a new timer');
      checkout.elapse(const Duration(seconds: 21));
      expect(checkout.controller.screen, CheckoutScreen.methods);
      expect(checkout.recorder.events.where((e) => e == 'ready'), hasLength(1));
      checkout.end();
    });
  });

  test('LD-09 resolves the sheet language', () {
    virtual((async) {
      expect(Checkout(async, loading('session-cm-aggregate.json'), locale: 'en').controller.language, 'en');
      expect(Checkout(async, loading('session-cm-aggregate.json')).controller.language, 'fr');
      final ci = Checkout(async, loading('session-ci-xof-wallets.json', config: 'sdk-config-ci-wallets.json'));
      expect(ci.controller.sessionData?.sessionLocale, isNull);
      expect(ci.controller.language, 'en');
      final device = Checkout(
        async,
        loading('session-ci-xof-wallets.json', config: 'sdk-config-ci-wallets.json'),
        deviceLanguage: 'fr',
      );
      expect(device.controller.language, 'fr');
      final other = Checkout(async, loading('session-cm-aggregate.json'), locale: 'de');
      expect(other.controller.language, 'en', reason: 'anything but French reads English');
      async.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('CH-01 shows only supported channels', () {
    virtual((async) {
      final ci = Checkout(async, loading('session-ci-xof-wallets.json', config: 'sdk-config-ci-wallets.json'));
      expect(slugsOf(ci.controller.methods), ['wallet:ci.djamo', 'mobile_money:ci.mtn,ci.moov,ci.orange,ci.wave']);
      expect(ci.recorder.ready?.methods, ['ci.djamo', 'ci.mtn', 'ci.moov', 'ci.orange', 'ci.wave']);
      expect(ci.controller.state, CheckoutState.initiated);

      final sandbox = Checkout(async, loading('session-sandbox-cm.json', config: 'sdk-config-sandbox.json'));
      expect(slugsOf(sandbox.controller.methods), ['card:card', 'mobile_money:cm.eu,cm.mobile'], reason: 'API order');

      final body = fixtureBody('session-ci-xof-wallets.json');
      for (final channel in body['channels'] as List) {
        (channel as Map)['type'] = 'crypto';
      }
      final none = Checkout(async, loading(FakeAnswer(200, body), config: 'sdk-config-ci-wallets.json'));
      expect(none.recorder.loadError?.code, 'no_payment_method');
      expect(none.controller.screen, CheckoutScreen.loadError);
      async.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('CH-02 localises channel names', () {
    final session = SessionData.fromJson(fixtureBody('session-sandbox-cm.json'));
    final card = session.channels.firstWhere((c) => c.slug == 'card');
    expect(card.localizedName('fr'), 'Carte bancaire');
    expect(card.localizedName('en'), 'Card');
  });

  test('CH-03 resolves sdk-config for aggregates', () {
    final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    // 2.1: the aggregate's own entry, beside its members'.
    final config = SdkConfig.fromJson(fixtureBody('sdk-config-cm-stripe.json'));
    expect(config.channels.keys, containsAll(['cm.mobile', 'cm.mtn', 'cm.orange', 'card']));
    final methods = buildMethods(session, config);
    expect(slugsOf(methods), ['card:card', 'mobile_money:cm.mobile']);
    expect(methods.first.cardFlavour, CardFlavour.stripe);
    Map<String, dynamic> channelsOf(Map<String, dynamic> body) => body['channels'] as Map<String, dynamic>;

    // The aggregate's own entry decides, whatever its members say.
    final aggregateOff = fixtureBody('sdk-config-cm-stripe.json');
    (channelsOf(aggregateOff)['cm.mobile'] as Map)['available'] = false;
    expect(slugsOf(buildMethods(session, SdkConfig.fromJson(aggregateOff))), ['card:card']);

    // 2.0 shape (no `cm.mobile`): the members' entries.
    final members = fixtureBody('sdk-config-cm-stripe.json');
    channelsOf(members).remove('cm.mobile');
    expect(slugsOf(buildMethods(session, SdkConfig.fromJson(members))), ['card:card', 'mobile_money:cm.mobile']);
    (channelsOf(members)['cm.mtn'] as Map)['available'] = false;
    expect(slugsOf(buildMethods(session, SdkConfig.fromJson(members))), ['card:card', 'mobile_money:cm.mobile'],
        reason: 'one member is enough');
    (channelsOf(members)['cm.orange'] as Map)['available'] = false;
    expect(slugsOf(buildMethods(session, SdkConfig.fromJson(members))), ['card:card']);
  });

  test('CH-04 defaults mobile money without sdk-config', () {
    // 2.1 sends sandbox Mobile Money entries (`form` + `phone`); a 2.0
    // answer had none: the same form either way.
    final withEntries = fixtureBody('sdk-config-sandbox.json');
    final config = withEntries['channels'] as Map;
    expect((config['cm.mobile'] as Map)['sdk'], 'form');
    final withoutEntries = fixtureBody('sdk-config-sandbox.json');
    (withoutEntries['channels'] as Map).removeWhere((slug, _) => slug != 'card');
    for (final (name, body) in [('2.1', withEntries), ('2.0', withoutEntries)]) {
      virtual((async) {
        final checkout = Checkout(async, loading('session-sandbox-cm.json', config: FakeAnswer(200, body)));
        final mobile = checkout.method(MethodFamily.mobileMoney);
        expect(mobile.enabled, isTrue, reason: name);
        expect(mobile.channels.map((c) => c.slug), ['cm.eu', 'cm.mobile'], reason: name);
        checkout.controller.selectMethod(mobile);
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.fieldErrors['data.phone'], isNotNull, reason: 'the form asks for the phone ($name)');
        checkout.end();
      });
    }
  });

  test('CH-05 disables channels out of their limits', () {
    final body = fixtureBody('session-cm-aggregate.json');
    final mobile = (body['channels'] as List).firstWhere((c) => (c as Map)['slug'] == 'cm.mobile') as Map;
    mobile['min_amount'] = 30000;
    final methods =
        buildMethods(SessionData.fromJson(body), SdkConfig.fromJson(fixtureBody('sdk-config-cm-stripe.json')));
    final momo = methods.firstWhere((m) => m.family == MethodFamily.mobileMoney);
    expect(momo.enabled, isFalse);
    expect(momo.limit?.minimum, isTrue);
    expect(momo.limit?.amount, 30000);
    expect(formatAmount(momo.limit!.amount, momo.limit!.currency, 'fr'), '30 000 XAF');
    expect(methods.firstWhere((m) => m.family == MethodFamily.card).enabled, isTrue);
  });

  test('CD-01 picks the card flavour', () {
    final expected = {
      'sdk-config-card-paystack.json': CardFlavour.clientSession,
      'sdk-config-card-adyen.json': CardFlavour.clientSession,
      'sdk-config-cm-stripe.json': CardFlavour.stripe,
      'sdk-config-card-cinetpay.json': CardFlavour.hostedRedirect,
      'sdk-config-card-kkiapay.json': CardFlavour.hostedRedirect,
      'sdk-config-card-mollie.json': CardFlavour.hostedRedirect,
    };
    expected.forEach((name, flavour) {
      final config = SdkConfig.fromJson(fixtureBody(name)).channels['card'];
      expect(cardFlavour(config, sandbox: false), flavour, reason: name);
    });
    final sandbox = SdkConfig.fromJson(fixtureBody('sdk-config-sandbox.json')).channels['card'];
    expect(cardFlavour(sandbox, sandbox: true), CardFlavour.sandboxForm);
    expect(cardFlavour(sandbox, sandbox: false), isNull, reason: 'the test form never in live');
    expect(cardFlavour(const SdkChannelConfig(available: true, sdk: 'adyen_custom_card'), sandbox: false), isNull);
    expect(cardFlavour(const SdkChannelConfig(available: true, sdk: 'psp_inline'), sandbox: false), isNull);
    expect(cardFlavour(const SdkChannelConfig(available: false, sdk: 'stripe_elements'), sandbox: false), isNull);
    expect(cardFlavour(null, sandbox: false), isNull);
    // Adyen lists its encrypted card fields, which only its web component makes.
    final adyen = SdkConfig.fromJson(fixtureBody('sdk-config-card-adyen.json')).channels['card'];
    expect(hostedCardRequiredFields(adyen), isEmpty);
  });

  test('CD-02 collects hosted card required fields', () {
    virtual((async) {
      final api = loading('session-cm-aggregate.json', config: 'sdk-config-card-cinetpay.json')
        ..on('POST /pay/process', 'process-redirect-card-hosted.json')
        ..on('GET /pay/status', 'status-processing.json');
      final checkout = Checkout(async, api, locale: 'en');
      checkout.controller.selectMethod(checkout.method(MethodFamily.card));
      expect(checkout.controller.cardRequiredFields,
          ['first_name', 'last_name', 'email', 'phone', 'address', 'city', 'country', 'zip_code']);
      final values = {
        'first_name': 'Awa',
        'last_name': 'Ngono',
        'email': 'awa.ngono@example.com',
        'phone': '+237677123456',
        'address': 'Rue 1',
        'city': 'Douala',
        'country': 'cm',
        'zip_code': '00237',
      };
      values.forEach(checkout.controller.setCardField);
      checkout.run(checkout.controller.payCard);
      final data = Map.of(api.bodies('/pay/process').single['data'] as Map)..remove('_client');
      expect(data, {...values, 'country': 'CM'});
      expect(checkout.opened, ['https://checkout.psp.example/pay/abc123']);
      checkout.end();
    });
  });

  test('CD-03 never sends raw card data in live', () {
    expect(CheckoutController.carriesCardData({'card.number': '4242', 'cvv': '123'}), isTrue);
    expect(CheckoutController.carriesCardData({'pin': '1234'}), isTrue);
    expect(CheckoutController.carriesCardData({'payment_method_id': 'pm_1', 'email': 'a@b.c'}), isFalse);
    const cardKeys = {
      'card.number',
      'card_number',
      'number',
      'cvv',
      'cvc',
      'pin',
      'exp',
      'expiry_month',
      'expiry_year'
    };
    for (final (config, start) in [
      ('sdk-config-card-cinetpay.json', 'POST /pay/process'),
      ('sdk-config-card-mollie.json', 'POST /pay/process'),
      ('sdk-config-card-paystack.json', 'POST /pay/client-session'),
      ('sdk-config-cm-stripe.json', 'POST /pay/process'),
    ]) {
      virtual((async) {
        // Every live card flavour: what leaves the device carries no card data.
        final api = loading('session-cm-aggregate.json', config: config)
          ..on('POST /pay/process', 'process-redirect-card-hosted.json')
          ..on('POST /pay/client-session', 'client-session-start-202.json')
          ..on('GET /pay/status', 'status-processing.json');
        final checkout = Checkout(async, api, stripePaymentMethod: (key, holder) async => 'pm_test_1');
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        for (final field in checkout.controller.cardRequiredFields) {
          checkout.controller.setCardField(field, field == 'email' ? 'a@b.cm' : (field == 'country' ? 'CM' : 'x'));
        }
        checkout.controller.setCardField('card.number', '4242424242424242');
        checkout.controller.setCardField('cvv', '123');
        checkout.run(checkout.controller.payCard);
        final path = start.split(' ').last;
        final body = api.bodies(path).single;
        final data = path == '/pay/process' ? body['data'] as Map : body;
        expect(data.keys.toSet().intersection(cardKeys), isEmpty, reason: config);
        checkout.end();
      });
    }
    virtual((async) {
      // A live session whose sdk-config offers the test-card form: no card.
      final checkout = Checkout(async, loading('session-cm-aggregate.json', config: 'sdk-config-sandbox.json'));
      expect(checkout.controller.methods.map((m) => m.family), [MethodFamily.mobileMoney]);
      checkout.end();
    });
    final error = WajubError.fromResponse(status: 422, body: fixtureBody('process-422-raw-card-data-live.json'));
    expect(error.code, 'raw_card_data_not_accepted');
    expect(error.retryable, isFalse);
  });

  test('WL-01 pays one-tap wallets', () {
    virtual((async) {
      final api = loading('session-ci-xof-wallets.json', config: 'sdk-config-ci-wallets.json')
        ..on('POST /pay/process', 'process-redirect-wallet-djamo.json')
        ..on('GET /pay/status', 'status-processing.json');
      final checkout = Checkout(async, api);
      checkout.controller.selectMethod(checkout.method(MethodFamily.wallet));
      expect(checkout.controller.state, CheckoutState.collectingDetails);
      checkout.run(checkout.controller.payWallet);
      final body = api.bodies('/pay/process').single;
      expect(body['channel'], 'ci.djamo');
      expect((body['data'] as Map).keys, ['_client']);
      expect(checkout.opened, ['https://djamo.ci/?type=payment_confirmation&id=abc']);
      expect(checkout.recorder.stateMethods.last, 'wallet');
      checkout.end();
    });
  });

  test('WL-02 follows a wave redirect', () {
    virtual((async) {
      final api = loading('session-ci-xof-wallets.json', config: 'sdk-config-ci-wallets.json')
        ..on('POST /pay/process', 'process-redirect-wave.json')
        ..on('GET /pay/status', 'status-processing.json');
      final checkout = Checkout(async, api);
      checkout.mobileMoney('0701020304', pick: 'wave');
      checkout.run(checkout.controller.payMobileMoney);
      final body = api.bodies('/pay/process').single;
      expect(body['channel'], 'ci.wave');
      expect((body['data'] as Map)['phone'], '+2250701020304');
      expect(checkout.opened, ['https://pay.wave.com/c/cos-1x2y3z?a=10000&c=XOF&m=Maquis']);
      expect(checkout.controller.state, CheckoutState.pending);
      checkout.end();
    });
  });

  test('MM-06 shows the approval screen', () {
    for (final (session, process, phone) in [
      ('session-cm-aggregate.json', 'process-processing-mobile-money-live.json', '677123456'),
      ('session-sandbox-cm.json', 'process-processing-mobile-money-sandbox.json', '670000000'),
    ]) {
      virtual((async) {
        final api = loading(session, config: 'sdk-config-cm-stripe.json')
          ..on('POST /pay/process', process)
          ..on('GET /pay/status', 'status-processing.json');
        final checkout = Checkout(async, api);
        checkout.mobileMoney(phone, pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.state, CheckoutState.approvalRequired, reason: process);
        expect(checkout.controller.screen, CheckoutScreen.approval);
        expect(checkout.controller.instruction,
            'Confirm the transaction on your phone. If no prompt appears, dial *126# to complete.');
        expect(checkout.controller.approvalPhone, '+237$phone');
        checkout.elapse(const Duration(seconds: 6));
        expect(api.calls('/pay/status'), isNotEmpty, reason: 'watching');
        checkout.end();
      });
    }
  });

  test('MM-05 sends the mobile money request through the sheet', () {
    virtual((async) {
      final api = loading('session-sandbox-cm.json', config: 'sdk-config-sandbox.json')
        ..on('POST /pay/process', 'process-processing-mobile-money-sandbox.json')
        ..on('GET /pay/status', 'status-processing.json');
      final checkout = Checkout(async, api);
      checkout.mobileMoney('67 00 00 000', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      final reference = fixtureRequestBody('process-processing-mobile-money-sandbox.json')!;
      final body = api.bodies('/pay/process').single;
      expect(body['channel'], reference['channel']);
      final data = Map.of(body['data'] as Map)..remove('_client');
      final expected = Map.of(reference['data'] as Map)..remove('_client');
      expect(data, expected);
      checkout.end();
    });
  });

  test('a sandbox test number of another operator is refused in the sheet', () {
    virtual((async) {
      // +23768 tests Express Union, where the numbering plan has MTN.
      final api = loading('session-sandbox-cm.json', config: 'sdk-config-sandbox.json')
        ..on('POST /pay/process', 'process-processing-mobile-money-sandbox.json')
        ..on('GET /pay/status', 'status-processing.json');
      final checkout = Checkout(async, api, locale: 'en');
      checkout.mobileMoney('680000000', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/process'), isEmpty);
      expect(checkout.controller.fieldErrors['data.phone'], startsWith('This number belongs to'));
      // Its own operator: sent as read.
      checkout.mobileMoney('680000000', pick: 'eu');
      checkout.run(checkout.controller.payMobileMoney);
      expect((api.bodies('/pay/process').single['data'] as Map)['phone'], '+237680000000');
      checkout.end();
    });
    virtual((async) {
      // In live the plan's operator decides.
      final api = loading('session-cm-aggregate.json');
      final checkout = Checkout(async, api, locale: 'en');
      checkout.mobileMoney('670000000', pick: 'orange');
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/process'), isEmpty);
      expect(checkout.controller.fieldErrors['data.phone'], startsWith('This number belongs to MTN MoMo.'));
      checkout.end();
    });
  });
}
