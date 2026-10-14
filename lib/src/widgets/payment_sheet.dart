import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../action_handler.dart';
import '../mapper/payment_mapper.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';
import '../wajub_session.dart';
import 'sheet_strings.dart';

enum _PaymentTab { mobileMoney, card, wallet }

/// Native payment sheet — Mobile Money + card, no WebView.
///
/// Card tab by sdk-config flavor: `clientSession` (Paystack / Flutterwave —
/// the PSP's hosted checkout in the system browser), `stripe_elements`
/// (native Stripe field), `hosted_redirect` (PayPal / Mollie / Paddle /
/// Kkiapay / FedaPay / PayDunya / CinetPay — plus whatever contact/billing
/// fields sdk-config still requires). Adyen cards come through
/// `clientSession` (Pay by Link).
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
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> with WidgetsBindingObserver {
  SessionData? _session;
  SdkConfig? _sdkConfig;
  bool _loading = true;
  bool _submitting = false;
  WajubError? _error;
  SessionChannel? _selectedMomo;
  final _phoneController = TextEditingController();
  final _holderController = TextEditingController();
  final _emailController = TextEditingController();
  final Map<String, TextEditingController> _billingControllers = {};
  Completer<void>? _resumeCompleter;
  bool _leftForeground = false;
  String _country = 'CM';
  _PaymentTab _tab = _PaymentTab.mobileMoney;
  bool _cardComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  /// Completes [_resumeCompleter] the first time the app comes back to the
  /// foreground AFTER having left it (the PSP page opened in the browser).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final completer = _resumeCompleter;
    if (completer == null || completer.isCompleted) return;
    if (state == AppLifecycleState.resumed) {
      if (_leftForeground) completer.complete();
    } else {
      _leftForeground = true;
    }
  }

  Future<void> _waitForAppResume() {
    _leftForeground = false;
    final completer = Completer<void>();
    _resumeCompleter = completer;
    return completer.future;
  }

  SheetStrings get _t => SheetStrings.forLocale(widget.locale ?? _session?.locale);

  /// Marks the start of an attempt, for [showWajubPaymentSheet]: a sheet
  /// closed after it does not cancel the payment.
  void _started() {
    _submitting = true;
    _error = null;
    widget.onPaymentStarted?.call();
  }

  SdkChannelConfig? _cardConfig() {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    return _sdkConfig?.channels[cardSlug];
  }

  Future<void> _load() async {
    try {
      final session = await widget.session.loadSession();
      final sdkConfig = await widget.session.getSdkConfig();
      final momo = session.channels.where(
        (c) => c.type.toLowerCase() == 'mobile_money' || c.type.toLowerCase() == 'mobile',
      );
      final hasCard = session.channels.any((c) => c.type.toLowerCase() == 'card');
      final hasWallet = session.channels.any(
        (c) => PaymentMapper.isRedirectWalletChannel(c, sdkConfig.channels[c.slug]),
      );
      setState(() {
        _session = session;
        _sdkConfig = sdkConfig;
        _loading = false;
        _selectedMomo = momo.isNotEmpty ? momo.first : null;
        _country = _selectedMomo?.countries.firstOrNull ?? 'CM';
        if (momo.isEmpty && hasCard) _tab = _PaymentTab.card;
        if (momo.isEmpty && !hasCard && hasWallet) _tab = _PaymentTab.wallet;
      });
    } on WajubError catch (e) {
      setState(() {
        _loading = false;
        _error = e;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = WajubError.network(e.toString());
      });
    }
  }

  Future<void> _finish(PaymentResult result) async {
    await handlePaymentAction(widget.session, result);
    widget.onResult(result);
  }

  Future<void> _payMomo() async {
    final channel = _selectedMomo;
    if (channel == null) return;
    setState(_started);
    try {
      final result = await widget.session.payMobileMoney(
        MobileMoneyInput(
          channelSlug: channel.slug,
          phone: _phoneController.text.trim(),
          country: _country,
        ),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await _finish(result);
    } on WajubError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e;
      });
    }
  }

  Future<void> _payWallet(SessionChannel channel) async {
    setState(_started);
    try {
      final result = await widget.session.payWallet(channelSlug: channel.slug);
      if (!mounted) return;
      setState(() => _submitting = false);
      await _finish(result);
    } on WajubError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e;
      });
    }
  }

  Future<void> _payCard() async {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    final cardCfg = _sdkConfig?.channels[cardSlug];
    if (cardCfg?.sdk != SdkFlavor.stripeElements || cardCfg?.publishableKey == null) {
      setState(() => _error = WajubError(
            type: WajubErrorType.paymentError,
            message: _t.cardUnavailable,
            code: 'provider_unavailable',
          ));
      return;
    }
    setState(_started);
    try {
      final result = await widget.session.payCardWithStripeElements(
        channelSlug: cardSlug,
        publishableKey: cardCfg!.publishableKey!,
        cardholderName: _holderController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await _finish(result);
    } on WajubError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e;
      });
    }
  }

  /// Paystack / Flutterwave: open the PSP's hosted checkout in the system
  /// browser, wait for the payer to come back, then verify server-side.
  Future<void> _payCardClientSession() async {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    setState(_started);
    PaymentRequiresAction? started;
    try {
      final email = _emailController.text.trim();
      final result = await widget.session.startClientSession(
        channelSlug: cardSlug,
        email: email.isEmpty ? null : email,
      );
      if (!mounted) return;
      if (result is! PaymentRequiresAction ||
          result.action != ActionKind.clientSession ||
          result.clientSession == null) {
        setState(() => _submitting = false);
        await _finish(result);
        return;
      }
      started = result;

      final resumed = _waitForAppResume();
      final opened = await widget.session.handleRedirectAction(result);
      if (!opened) {
        _resumeCompleter = null;
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = WajubError(
            type: WajubErrorType.apiError,
            message: _t.couldNotOpenPage,
            code: 'redirect_failed',
          );
        });
        return;
      }
      await resumed;
      if (!mounted) return;

      final completed = await widget.session.completeClientSession(result.clientSession!.id);
      if (!mounted) return;
      setState(() => _submitting = false);
      await _finish(completed);
    } on WajubError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final transaction = started?.transaction;
      if (transaction != null) {
        // The payer went through the PSP's page, so end the sheet instead of
        // offering a retry. Only a 402 (declineCode set) is a verified
        // decline; anything else (network, expired session) may still be
        // settled by the PSP webhook → processing, keep watching the status.
        await _finish(
          e.declineCode != null ? PaymentFailed(error: e, transaction: transaction) : PaymentProcessing(transaction),
        );
        return;
      }
      setState(() => _error = e);
    }
  }

  /// sdk-config `requiredFields` a hosted-redirect PSP can ask the payer for.
  List<String> _redirectFields(SdkChannelConfig? cfg) =>
      (cfg?.requiredFields ?? const []).where(PaymentMapper.hostedCardFields.contains).toList();

  TextEditingController _billingController(String field) =>
      _billingControllers.putIfAbsent(field, TextEditingController.new);

  /// The PSP's own page collects the card (PayPal, Mollie, Paddle, Kkiapay,
  /// FedaPay, PayDunya, CinetPay).
  Future<void> _payCardHostedRedirect() async {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    final billing = {
      for (final field in _redirectFields(_cardConfig())) field: _billingController(field).text,
    };
    setState(_started);
    try {
      final result = await widget.session.payCardHostedRedirect(
        channelSlug: cardSlug,
        billing: billing,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await _finish(result);
    } on WajubError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final pending = _resumeCompleter;
    if (pending != null && !pending.isCompleted) pending.complete();
    _phoneController.dispose();
    _holderController.dispose();
    _emailController.dispose();
    for (final controller in _billingControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _cardTab() {
    final cfg = _cardConfig();
    if (cfg != null && cfg.clientSession) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: _t.emailForReceipt, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _payCardClientSession,
            child: Text(_submitting ? _t.processing : _t.payByCard),
          ),
        ],
      );
    }
    if (cfg?.sdk == SdkFlavor.stripeElements && cfg?.publishableKey != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _holderController,
            decoration: InputDecoration(labelText: _t.cardholderName, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          CardField(
            onCardChanged: (details) => setState(() => _cardComplete = details?.complete ?? false),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting || !_cardComplete ? null : _payCard,
            child: Text(_submitting ? _t.processing : _t.payWithCard),
          ),
        ],
      );
    }
    if (cfg?.sdk == SdkFlavor.hostedRedirect) {
      final fields = _redirectFields(cfg);
      final valid = fields.every((f) => PaymentMapper.hostedCardFieldError(f, _billingController(f).text) == null);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in fields) ...[
            TextField(
              key: ValueKey('hosted-card-$field'),
              controller: _billingController(field),
              keyboardType: field == 'email'
                  ? TextInputType.emailAddress
                  : field == 'phone'
                      ? TextInputType.phone
                      : TextInputType.text,
              textCapitalization: field == 'country' ? TextCapitalization.characters : TextCapitalization.none,
              maxLength: field == 'country' ? 2 : null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _t.fields[field],
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _submitting || !valid ? null : _payCardHostedRedirect,
            child: Text(_submitting ? _t.processing : _t.payByCard),
          ),
        ],
      );
    }
    return Text(_t.cardUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final momoChannels = _session?.channels
            .where(
              (c) => c.type.toLowerCase() == 'mobile_money' || c.type.toLowerCase() == 'mobile',
            )
            .toList() ??
        [];
    final hasCard = _session?.channels.any((c) => c.type.toLowerCase() == 'card') ?? false;
    final walletChannels = _session?.channels
            .where((c) => PaymentMapper.isRedirectWalletChannel(c, _sdkConfig?.channels[c.slug]))
            .toList() ??
        [];
    final tabs = [
      if (momoChannels.isNotEmpty) _PaymentTab.mobileMoney,
      if (hasCard) _PaymentTab.card,
      if (walletChannels.isNotEmpty) _PaymentTab.wallet,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_t.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close)),
                ],
              ),
              if (tabs.length > 1) ...[
                SegmentedButton<_PaymentTab>(
                  segments: [
                    for (final tab in tabs)
                      ButtonSegment(
                        value: tab,
                        label: Text(switch (tab) {
                          _PaymentTab.mobileMoney => _t.mobileMoney,
                          _PaymentTab.card => _t.card,
                          _PaymentTab.wallet => _t.wallet,
                        }),
                      ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
                const SizedBox(height: 16),
              ],
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_session == null)
                Text(
                  _error?.message ?? _t.loadFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else ...[
                // Submit errors stay inline so the payer can fix the input
                // (e.g. an email the PSP requires) and retry.
                if (_error != null) ...[
                  Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                if (_tab == _PaymentTab.wallet) ...[
                  Text(_t.walletHint),
                  const SizedBox(height: 12),
                  for (final ch in walletChannels) ...[
                    FilledButton(
                      onPressed: _submitting ? null : () => _payWallet(ch),
                      child: Text(_submitting ? _t.processing : _t.payWith(ch.name)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ] else if (_tab == _PaymentTab.mobileMoney) ...[
                  if (momoChannels.isEmpty)
                    Text(_t.noMobileMoney)
                  else ...[
                    Wrap(
                      spacing: 8,
                      children: momoChannels.map((ch) {
                        return ChoiceChip(
                          label: Text(ch.name),
                          selected: _selectedMomo?.slug == ch.slug,
                          onSelected: (_) => setState(() {
                            _selectedMomo = ch;
                            _country = ch.countries.firstOrNull ?? _country;
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: _t.phoneNumber, border: const OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submitting || _phoneController.text.trim().isEmpty ? null : _payMomo,
                      child: Text(_submitting ? _t.processing : _t.payNow),
                    ),
                  ],
                ] else if (!hasCard)
                  Text(_t.noCardChannel)
                else
                  _cardTab(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [PaymentSheet] as a modal bottom sheet.
///
/// [onResult] receives the outcome of a payment the payer submitted.
/// [onCancel] is called when the payer closes the sheet (the close button, a
/// swipe down, the back button) without a result. When nothing had been
/// submitted yet, the payment is also cancelled on Wajub (`/pay/cancel`), as
/// the hosted checkout does. When an attempt was under way, it is left
/// alone: a Mobile Money approval can still land after the sheet is gone, so
/// follow it with `watchStatus()` or your webhook.
///
/// [locale] (`fr` or `en`) picks the sheet's language; without it the sheet
/// follows the payment's own.
Future<void> showWajubPaymentSheet({
  required BuildContext context,
  required WajubSession session,
  required ValueChanged<PaymentResult> onResult,
  VoidCallback? onCancel,
  String? locale,
}) async {
  var settled = false;
  var started = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => PaymentSheet(
      session: session,
      locale: locale,
      onPaymentStarted: () => started = true,
      onDismiss: () => Navigator.of(ctx).pop(),
      onResult: (result) {
        settled = true;
        onResult(result);
        Navigator.of(ctx).pop();
      },
    ),
  );

  if (settled) return;
  if (!started) {
    // Best effort: the payer left, the payment should not stay open. A
    // failure here changes nothing for the app, which already moves on.
    unawaited(session.cancel().then((_) {}, onError: (Object _) {}));
  }
  onCancel?.call();
}
