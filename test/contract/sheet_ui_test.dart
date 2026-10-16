import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wajub_mobile/src/adapters/hosted_redirect.dart';
import 'package:wajub_mobile/src/appearance/appearance.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/checkout/present_options.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';
import 'package:wajub_mobile/src/widgets/network_logo.dart';
import 'package:wajub_mobile/src/widgets/present.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// A sheet presented over a bare app.
class Sheet {
  Sheet(this.api, {PresentOptions? options, this.browserOpens = true}) {
    controller = checkoutController(
      api,
      options: options ?? PresentOptions(sessionToken: 'tok_test', callbacks: recorder.callbacks),
      opened: opened,
      browserOpens: browserOpens,
    );
    unawaited(controller.result.then((r) => result = r));
  }

  final FakeApi api;
  final bool browserOpens;
  final recorder = Recorder();
  final opened = <String>[];
  late final CheckoutController controller;
  CheckoutResult? result;
  late BuildContext context;

  Future<void> open(WidgetTester tester, {ThemeData? theme, bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
      home: Builder(builder: (context) {
        this.context = context;
        return const SizedBox.expand();
      }),
    ));
    unawaited(presentCheckout(context, controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

FakeApi sandboxApi({Object status = 'status-processing.json'}) => FakeApi(routes: {
      'GET /pay/session': 'session-sandbox-cm.json',
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      'POST /pay/process': 'process-processing-mobile-money-sandbox.json',
      'GET /pay/status': status,
      'POST /pay/cancel': 'cancel-200.json',
    });

/// Scrolls [finder] into the sheet's view, then taps it.
Future<void> tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

class FakeLauncher extends UrlLauncherPlatform {
  final launches = <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));
    return true;
  }
}

void main() {
  testWidgets('LD-07 offers retry on load failure', (tester) async {
    final api = FakeApi(routes: {
      'GET /pay/session': [
        for (var i = 0; i < 4; i++) const FakeAnswer.network(),
        FakeAnswer.fixture('session-sandbox-cm.json')
      ],
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
    });
    final sheet = Sheet(api, options: const PresentOptions(sessionToken: 'tok_test', locale: 'en'));
    await sheet.open(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text("We couldn't load the payment"), findsOneWidget);
    expect(sheet.controller.error?.code, 'load_error');
    expect(sheet.controller.error?.retryable, isTrue);

    await tester.tap(find.byKey(const ValueKey('wajub-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Choose a payment method'), findsOneWidget);
    expect(api.calls('/pay/session'), hasLength(5));

    await tester.tap(find.byKey(const ValueKey('wajub-dismiss')));
    await tester.pump(const Duration(seconds: 1));
    expect(sheet.result, isA<CheckoutCancelled>());
  });

  testWidgets('AP-07 draws the loader', (tester) async {
    Future<double> pulse(WidgetTester tester) async {
      final opacity = tester.widget<FadeTransition>(find.byKey(const ValueKey('wajub-skeleton'))).opacity;
      final first = opacity.value;
      await tester.pump(const Duration(milliseconds: 450));
      return (opacity.value - first).abs();
    }

    final slow = FakeApi(routes: {
      'GET /pay/session': FakeAnswer.fixture('session-sandbox-cm.json', delay: const Duration(seconds: 5)),
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      'POST /pay/cancel': 'cancel-200.json',
    });
    final skeleton = Sheet(slow);
    await skeleton.open(tester);
    expect(find.byKey(const ValueKey('wajub-skeleton')), findsOneWidget, reason: 'the default loader');
    expect(await pulse(tester), greaterThan(0), reason: 'it pulses');
    await tester.pump(const Duration(seconds: 5));
    skeleton.controller.hostGone();
    await tester.pumpWidget(const SizedBox());

    for (final (appearance, reduceMotion) in [
      (const Appearance(disableAnimations: true), false),
      (null, true),
    ]) {
      final sheet = Sheet(
        FakeApi(routes: {
          'GET /pay/session': FakeAnswer.fixture('session-sandbox-cm.json', delay: const Duration(seconds: 5)),
          'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        }),
        options: PresentOptions(sessionToken: 'tok_test', appearance: appearance),
      );
      await sheet.open(tester, reduceMotion: reduceMotion);
      expect(await pulse(tester), 0, reason: 'static without animations');
      await tester.pump(const Duration(seconds: 5));
      sheet.controller.hostGone();
      await tester.pumpWidget(const SizedBox());
    }

    final spinner = Sheet(
      FakeApi(routes: {
        'GET /pay/session': FakeAnswer.fixture('session-sandbox-cm.json', delay: const Duration(seconds: 5)),
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      }),
      options: const PresentOptions(sessionToken: 'tok_test', loader: WajubLoader.spinner),
    );
    await spinner.open(tester);
    expect(find.byKey(const ValueKey('wajub-spinner')), findsOneWidget);
    expect(find.byKey(const ValueKey('wajub-skeleton')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    spinner.controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RD-01 opens provider pages in the system browser', (tester) async {
    final api = FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-card-mollie.json',
      'POST /pay/process': 'process-redirect-card-hosted.json',
      'GET /pay/status': 'status-processing.json',
    });
    final recorder = Recorder();
    final calls = <String>[];
    final controller = CheckoutController(
      session: api.session(),
      options: PresentOptions(
        sessionToken: 'tok_test',
        locale: 'en',
        callbacks: CheckoutCallbacks(onRedirect: (e) => calls.add('onRedirect ${e.url} ${e.method}')),
      ),
      openUrl: (url) async {
        calls.add('browser $url');
        return true;
      },
      mobileMoneyData: () async => mobileMoneyData,
      altchaSolver: (_) async => null,
      realtimeConnector: FakeRealtime(refuse: true).connect,
    );
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox.expand();
    })));
    unawaited(presentCheckout(context, controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('wajub-method-card')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    const url = 'https://checkout.psp.example/pay/abc123';
    expect(calls, ['onRedirect $url GET', 'browser $url']);
    expect(find.byKey(const ValueKey('wajub-continue')), findsOneWidget);
    expect(recorder.events, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wajub-continue')));
    await tester.pump();
    expect(calls.last, 'browser $url', reason: '"Continue payment" reopens the same page');

    // The default opener: the system browser, never a web view.
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    expect(await HostedRedirect.open(url), isTrue);
    expect(launcher.launches.single, (url, PreferredLaunchMode.externalApplication));

    controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ST-04 settles when the host goes away', (tester) async {
    final idle = Sheet(sandboxApi());
    await idle.open(tester);
    await tester.pumpWidget(const SizedBox());
    expect(idle.result, isA<CheckoutCancelled>());
    expect((idle.result! as CheckoutCancelled).reason, CancelReason.hostGone);
    expect(idle.api.calls('/pay/cancel'), isEmpty, reason: 'never cancels for the host');

    final api = sandboxApi();
    final paying = Sheet(api);
    await paying.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '670000000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(paying.controller.state, CheckoutState.approvalRequired);
    await tester.pumpWidget(const SizedBox());
    expect(paying.result, isA<CheckoutProcessing>());
    final reads = api.calls('/pay/status').length;
    await tester.pump(const Duration(seconds: 30));
    expect(api.calls('/pay/status'), hasLength(reads), reason: 'the watch stopped');
    expect(api.calls('/pay/cancel'), isEmpty);
  });

  testWidgets('a dismiss waits for its cancel, and a host removal never cancels', (tester) async {
    final slow = FakeApi(routes: {
      'GET /pay/session': 'session-sandbox-cm.json',
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      'POST /pay/cancel': FakeAnswer.fixture('cancel-200.json', delay: const Duration(seconds: 2)),
    });
    final dismissed = Sheet(slow);
    await dismissed.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-dismiss')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(dismissed.result, isNull, reason: 'the cancel is still running after the sheet left');
    await tester.pump(const Duration(seconds: 2));
    expect((dismissed.result! as CheckoutCancelled).reason, CancelReason.dismissed);
    expect((dismissed.result! as CheckoutCancelled).redirectUrl, fixtureBody('cancel-200.json')['redirect_url']);

    final api = sandboxApi();
    final replaced = Sheet(api);
    await replaced.open(tester);
    unawaited(Navigator.of(replaced.context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const Text('signed out')),
      (_) => false,
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((replaced.result! as CheckoutCancelled).reason, CancelReason.hostGone);
    expect(api.calls('/pay/cancel'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a present that cannot show leaves the next one free', (tester) async {
    late BuildContext bare;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (context) {
        bare = context;
        return const SizedBox();
      }),
    ));
    expect(() => presentCheckout(bare, checkoutController(sandboxApi())), throwsA(anything));
    final sheet = Sheet(sandboxApi());
    await sheet.open(tester);
    expect(find.byKey(const ValueKey('wajub-method-mobile_money')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a present from a page already gone resolves host_gone at once and leaves the next one free',
      (tester) async {
    late BuildContext gone;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      gone = context;
      return const SizedBox();
    })));
    await tester.pumpWidget(const SizedBox());
    final api = sandboxApi();
    final result = await presentCheckout(gone, checkoutController(api));
    expect((result as CheckoutCancelled).reason, CancelReason.hostGone);
    expect(api.calls('/pay/cancel'), isEmpty);
    final sheet = Sheet(sandboxApi());
    await sheet.open(tester);
    expect(find.byKey(const ValueKey('wajub-method-mobile_money')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ST-05 rejects a second present', (tester) async {
    final first = Sheet(sandboxApi());
    await first.open(tester);
    final second = checkoutController(sandboxApi());
    await expectLater(
      presentCheckout(first.context, second),
      throwsA(isA<WajubError>()
          .having((e) => e.code, 'code', 'sheet_already_presented')
          .having((e) => e.type, 'type', WajubErrorType.invalidRequestError)),
    );
    expect(first.controller.settled, isFalse, reason: 'the open sheet is left alone');
    expect(find.byKey(const ValueKey('wajub-method-mobile_money')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the phone field takes Arabic-Indic digits and shows them as 0-9', (tester) async {
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
    }));
    await sheet.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '٦٧٧١٢٣٤٥٦');
    await tester.pump();
    expect(find.text('67 71 23 45 6'), findsOneWidget, reason: 'shown as the digits they are');
    expect(sheet.controller.phone, '67 71 23 45 6');
    expect(sheet.controller.selectedOperatorId, 'mtn', reason: 'its operator recognised');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the OTP screen says where the code was sent, and nothing when the provider names nowhere',
      (tester) async {
    for (final (contact, shown) in [
      ('080******78', 'Enter the code sent to 080******78.'),
      ('', null),
      ('Please enter the OTP sent to 080******78', 'Enter the code sent to 080******78.'),
    ]) {
      final otp = fixtureBody('process-requires-otp.json')..['otp_masked_contact'] = contact;
      final sheet = Sheet(
        FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-card-mollie.json',
          'POST /pay/process': FakeAnswer(202, otp),
          'GET /pay/status': 'status-processing.json',
        }),
        options: const PresentOptions(sessionToken: 'tok_test', locale: 'en'),
      );
      await sheet.open(tester);
      sheet.controller.selectMethod(sheet.controller.methods.firstWhere((m) => m.family == MethodFamily.card));
      unawaited(sheet.controller.payCard());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('wajub-step-code')), findsOneWidget, reason: contact);
      if (shown == null) {
        expect(find.textContaining('sent to'), findsNothing, reason: 'an empty contact: the prompt alone');
      } else {
        expect(find.text(shown), findsOneWidget, reason: contact);
        expect(find.textContaining('Please enter'), findsNothing, reason: "never the provider's sentence");
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a confirmation code typed in Arabic-Indic digits shows as 0-9', (tester) async {
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-card-mollie.json',
      'POST /pay/process': 'process-requires-otp.json',
      'GET /pay/status': 'status-processing.json',
    }));
    await sheet.open(tester);
    sheet.controller.selectMethod(sheet.controller.methods.firstWhere((m) => m.family == MethodFamily.card));
    unawaited(sheet.controller.payCard());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-step-code')), '١٢٣٤٥٦');
    await tester.pump();
    expect(find.text('123456'), findsOneWidget, reason: 'the code as the payer typed it, in 0-9');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CH-06 prefers logo_png where SVG cannot be drawn', (tester) async {
    // Flutter draws SVG: `logo` first, `logo_png` when it does not load,
    // the brand badge when neither does.
    final png =
        base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"/></svg>';
    Future<void> show(String session, String config, {required bool svgLoads}) async {
      final fetched = <String>[];
      NetworkLogo.clearCache();
      await http.runWithClient(() async {
        final sheet = Sheet(FakeApi(routes: {'GET /pay/session': session, 'GET /pay/sdk-config': config}));
        await sheet.open(tester);
        await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
          () => MockClient((request) async {
                fetched.add(request.url.toString());
                final path = request.url.path;
                if (path.endsWith('.png')) return http.Response.bytes(png, 200);
                if (path.endsWith('.svg') && svgLoads) return http.Response(svg, 200);
                return http.Response('', 404);
              }));
      final logo = find.byKey(const ValueKey('wajub-operator-logo-mtn'));
      if (session == 'session-cm-aggregate.json' && !svgLoads) {
        expect(fetched, contains('https://api.wajub.com/img/channels/momo.png'));
        expect(find.descendant(of: logo, matching: find.byType(Image)), findsWidgets, reason: 'the PNG');
      } else if (svgLoads) {
        expect(fetched.where((url) => url.contains('/img/channels/') && url.endsWith('.png')), isEmpty,
            reason: 'the SVG is kept');
        expect(find.descendant(of: logo, matching: find.byType(SvgPicture)), findsWidgets);
      } else {
        expect(find.byKey(const ValueKey('wajub-operator-badge-mtn')), findsWidgets, reason: 'a 2.0 session: badge');
      }
      await tester.pumpWidget(const SizedBox());
    }

    await show('session-cm-aggregate.json', 'sdk-config-cm-stripe.json', svgLoads: false);
    await show('session-cm-aggregate.json', 'sdk-config-cm-stripe.json', svgLoads: true);
    await show('session-ci-xof-wallets.json', 'sdk-config-ci-wallets.json', svgLoads: false);
    NetworkLogo.clearCache();
  });

  testWidgets('a Mobile Money payment, from the operators to the success screen', (tester) async {
    final api = FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
      'POST /pay/process': 'process-processing-mobile-money-live.json',
      'GET /pay/status': ['status-processing.json', 'status-succeeded.json'],
    });
    final recorder = Recorder();
    final sheet = Sheet(api, options: PresentOptions(sessionToken: 'tok_test', callbacks: recorder.callbacks));
    await sheet.open(tester);
    expect(find.text('Boutique Akwa'), findsOneWidget, reason: 'the merchant name while its logo cannot load');
    expect(find.text('25 000 XAF'), findsOneWidget);
    expect(find.text('Choisissez un moyen de paiement'), findsOneWidget);
    expect(find.text('Sécurisé par Wajub'), findsNothing, reason: 'white label');

    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('wajub-operator-mtn')), findsOneWidget);
    expect(find.byKey(const ValueKey('wajub-operator-orange')), findsOneWidget);
    expect(find.text('+237 '), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '691234567');
    await tester.pump();
    expect(find.text('69 12 34 56 7'), findsOneWidget, reason: 'formatted as typed');
    expect(sheet.controller.selectedOperatorId, 'orange', reason: 'detected');
    await tester.tap(find.byKey(const ValueKey('wajub-operator-mtn')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    expect(find.textContaining('Ce numéro est un numéro Orange Money'), findsOneWidget, reason: 'a mismatch blocks');
    expect(api.calls('/pay/process'), isEmpty);

    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '677123456');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Validez le paiement sur votre téléphone'), findsOneWidget);
    expect(find.text('Instructions'), findsOneWidget);
    expect(find.text('Confirm the transaction on your phone. If no prompt appears, dial *126# to complete.'),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Paiement réussi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sheet.result, isA<CheckoutComplete>());
    expect(recorder.completions, 1);
    expect(find.text('Paiement réussi'), findsNothing, reason: 'closed itself');
  });

  testWidgets('the dark scheme follows the platform live', (tester) async {
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': 'session-ci-xof-wallets.json',
      'GET /pay/sdk-config': 'sdk-config-ci-wallets.json',
    }));
    await sheet.open(tester);
    Color background() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.borderRadius == const BorderRadius.vertical(top: Radius.circular(16)))
        .color!;
    expect(background(), const Color(0xFFFFFFFF));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(background(), const Color(0xFF0A0A0A));
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CH-07 shows what the payer pays on the chosen channel (the sheet)', (tester) async {
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': 'session-payer-fee-per-channel.json',
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
    }));
    await sheet.open(tester);
    String amount() => tester.widget<Text>(find.byKey(const ValueKey('wajub-amount'))).data!;
    expect(amount(), '10,200 XAF');
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pay 10,200 XAF'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '690000000');
    await tester.pump();
    expect(find.text('Pay 10,450 XAF'), findsOneWidget, reason: 'the Orange number');
    expect(amount(), '10,450 XAF', reason: 'the summary too');
    sheet.controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('MM-14 offers the operator\'s code to dial', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final session = fixtureBody('session-payer-otp-announced.json');
    (((session['channels'] as List).first) as Map).remove('payer_otp');
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': FakeAnswer(200, session),
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      'POST /pay/process': 'process-payer-otp-required.json',
    }));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await sheet.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '70000000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheet.controller.state, CheckoutState.payerOtpRequired);

    // Android dials it from a link.
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-dial')));
    await tester.pump();
    expect(sheet.opened, ['tel:*144*4*6%23']);
    // Every platform copies it.
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-copy')));
    await tester.pump();
    expect(copied, ['*144*4*6#']);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Test mode: enter the code 123456. Any other code is refused.'), findsOneWidget);

    // iOS refuses * and # in a tel: link: copy only.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-copy')));
    await tester.pump();
    expect(copied, ['*144*4*6#', '*144*4*6#']);
    expect(find.byKey(const ValueKey('wajub-payer-otp-dial')), findsNothing);
    expect(find.byKey(const ValueKey('wajub-payer-otp-ussd')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    sheet.controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the payer code screen shows how to get the code and takes it', (tester) async {
    final sheet = Sheet(
      FakeApi(routes: {
        'GET /pay/session': 'session-payer-otp-announced.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': ['process-payer-otp-refused.json', 'process-payer-otp-accepted-sandbox.json'],
        'GET /pay/status': 'status-processing.json',
      }),
      options: PresentOptions(sessionToken: 'tok_test', locale: 'fr', callbacks: Recorder().callbacks),
    );
    await sheet.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '70000000');
    await tester.pump();
    expect(find.text("Pour ce paiement, vous générerez un code en composant *144*4*6# : l'étape suivante vous guide."),
        findsOneWidget,
        reason: 'the form hint of an announced channel');
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheet.api.calls('/pay/process'), isEmpty);

    expect(find.text('Générez votre code de paiement'), findsOneWidget);
    expect(find.text('Code à composer'), findsOneWidget);
    expect(find.text('Montant exact à saisir'), findsOneWidget);
    expect(find.text('1000 XOF'), findsOneWidget, reason: 'exactly as sent');
    expect(find.text('Comment obtenir votre code'), findsOneWidget);
    expect(find.text('Sur le téléphone du compte Orange Money, composez *144*4*6#.'), findsOneWidget);
    expect(find.text('Saisissez le montant exact : 1000 XOF.'), findsOneWidget);
    expect(find.byKey(const ValueKey('wajub-payer-otp-step-3')), findsOneWidget);
    expect(find.text('Mode test : saisissez le code 123456. Tout autre code est refusé.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('wajub-payer-otp-code')), '12345');
    await tester.pump();
    expect(find.text('12345'), findsOneWidget, reason: 'no automatic submission');
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-submit')));
    await tester.pump();
    expect(find.text('Le code doit comporter 6 chiffres.'), findsOneWidget);
    expect(sheet.api.calls('/pay/process'), isEmpty);

    await tester.enterText(find.byKey(const ValueKey('wajub-payer-otp-code')), '6543217');
    await tester.pump();
    expect(find.text('654321'), findsOneWidget, reason: 'no more than 6 digits');
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Votre opérateur n'a pas accepté ce code. Générez-en un nouveau et réessayez."), findsOneWidget);
    expect(find.text('Il vous reste 2 essais.'), findsOneWidget);
    expect(find.text('654321'), findsNothing, reason: 'the field emptied');

    await tester.enterText(find.byKey(const ValueKey('wajub-payer-otp-code')), '123456');
    await tester.pump();
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheet.controller.state, CheckoutState.approvalRequired);
    expect(find.text('Code reçu. Votre opérateur traite le paiement, cela peut prendre quelques instants.'),
        findsOneWidget);
    sheet.controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the payer code screen without steps shows the generic ones, and leaves for the form', (tester) async {
    final session = fixtureBody('session-payer-otp-announced.json');
    final otp = (((session['channels'] as List).first) as Map)['payer_otp'] as Map;
    otp['steps'] = <String, Object>{};
    otp['ussd_code'] = null;
    otp['otp_length'] = null;
    final sheet = Sheet(FakeApi(routes: {
      'GET /pay/session': FakeAnswer(200, session),
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
    }));
    await sheet.open(tester);
    await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '70000000');
    await tester.pump();
    expect(find.text("For this payment, you will generate a code from your operator's menu: the next step guides you."),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Code to dial'), findsNothing);
    expect(find.text("Open your operator's Mobile Money menu (USSD code or app)."), findsOneWidget);
    expect(find.text('Generate a payment code for the exact amount: 1000 XOF.'), findsOneWidget);
    expect(find.text('Enter the code you received below.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('wajub-payer-otp-code')), '123');
    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-submit')));
    await tester.pump();
    expect(find.text('The code must have between 4 and 8 digits.'), findsOneWidget);

    await tapShown(tester, find.byKey(const ValueKey('wajub-payer-otp-change')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sheet.controller.state, CheckoutState.collectingDetails);
    expect(find.byKey(const ValueKey('wajub-phone-field')), findsOneWidget);
    sheet.controller.hostGone();
    await tester.pumpWidget(const SizedBox());
  });

  test('ST-01 reports Wajub.js states', () {
    expect(CheckoutState.values.map((s) => s.wireName), [
      'INITIATED',
      'COLLECTING_DETAILS',
      'PROCESSING',
      'OTP_REQUIRED',
      'PIN_REQUIRED',
      'PHONE_REQUIRED',
      'BIRTHDAY_REQUIRED',
      'ADDRESS_REQUIRED',
      '3DS_REQUIRED',
      'USSD_REQUIRED',
      'APPROVAL_REQUIRED',
      'VERIFYING',
      'PENDING',
      'SUCCESS',
      'FAILED',
      'EXPIRED',
      'CANCELLED',
      'PAYER_OTP_REQUIRED',
    ]);
    for (final (process, state) in [
      ('process-processing-mobile-money-sandbox.json', CheckoutState.approvalRequired),
      ('process-requires-otp.json', CheckoutState.otpRequired),
      ('process-redirect-card-hosted.json', CheckoutState.pending),
      ('process-payer-otp-required.json', CheckoutState.payerOtpRequired),
    ]) {
      virtual((async) {
        final api = sandboxApi()..on('POST /pay/process', process);
        final checkout = Checkout(async, api);
        checkout.mobileMoney('670000000', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(
            checkout.recorder.states,
            [
              CheckoutState.initiated,
              CheckoutState.collectingDetails,
              CheckoutState.processing,
              state,
            ],
            reason: process);
        expect(checkout.recorder.stateMethods.skip(1), everyElement('mobile_money'));
        checkout.end();
      });
    }
  });

  test('ST-02 fires callbacks in order', () {
    virtual((async) {
      final api = sandboxApi(status: 'status-succeeded.json');
      final checkout = Checkout(async, api);
      checkout.mobileMoney('670000000', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 6));
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.recorder.events, [
        'ready',
        'state:INITIATED',
        'state:COLLECTING_DETAILS',
        'state:PROCESSING',
        'started:mobile_money:cm.mobile',
        'state:APPROVAL_REQUIRED',
        'state:SUCCESS',
        'success:mobile_money',
        'complete:complete',
      ]);
    });
  });

  test('ST-03 resolves present once', () {
    virtual((async) {
      final checkout = Checkout(async, sandboxApi());
      checkout.run(checkout.controller.cancelPayment);
      final first = checkout.result;
      expect(first, isA<CheckoutCancelled>());
      checkout.controller.close();
      checkout.run(checkout.controller.dismiss);
      checkout.controller.hostGone();
      expect(checkout.result, same(first));
      expect(checkout.recorder.completions, 1);
    });
  });

  test('ST-06 builds PaymentSuccess', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-card-paystack.json',
        'POST /pay/client-session': 'client-session-start-202.json',
        'POST /pay/client-session/complete': 'client-session-complete-200.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.controller.selectMethod(checkout.controller.methods.first);
      checkout.run(checkout.controller.payCard);
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      final payment = checkout.recorder.success!;
      expect(payment.toMap(), {
        'id': 'trx_ClientSessN7aQ2LmX9k',
        'reference': 'CMD-4172',
        'amount': 1000.0,
        'currency': 'NGN',
        'method': 'card',
        'status': 'success',
        'timestamp': '2026-10-14T09:30:00+00:00',
        'receipt_url': 'https://invoice.wajub.com/r/trx_ClientSessN7aQ2LmX9k?s=SIGNATURE',
      });
      checkout.end();
    });
    final fee = SessionData.fromJson(fixtureBody('session-payer-bears-fee.json')).transaction;
    expect(PaymentSuccess.from(fee, method: 'unknown').amount, 10350, reason: 'amount_total');

    // The channel's price: what the charge took, not what the session said.
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-payer-fee-per-channel.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': 'process-payer-fee-on-channel-sandbox.json',
        'GET /pay/status': 'status-succeeded.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('690000000');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.recorder.success?.amount, 10450, reason: 'not 10 200');
      expect(checkout.recorder.success?.currency, 'XAF');
      checkout.end();
    });
  });

  test('ST-07 survives throwing callbacks', () {
    virtual((async) {
      void boom(Object _) => throw StateError('host bug');
      var completed = 0;
      final api = sandboxApi(status: 'status-succeeded.json');
      final controller = checkoutController(
        api,
        options: PresentOptions(
          sessionToken: 'tok_test',
          callbacks: CheckoutCallbacks(
            onReady: boom,
            onStateChange: boom,
            onPaymentStarted: boom,
            onSuccess: boom,
            onComplete: (r) {
              completed++;
              throw StateError('host bug');
            },
          ),
        ),
      );
      CheckoutResult? result;
      controller.result.then((r) => result = r);
      controller.load();
      async.flushMicrotasks();
      controller.selectMethod(controller.methods.firstWhere((m) => m.family == MethodFamily.mobileMoney));
      controller.setPhone('670000000');
      controller.payMobileMoney();
      async.elapse(const Duration(seconds: 10));
      expect(result, isA<CheckoutComplete>());
      expect(completed, 1);
    });
  });
}
