import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../action_handler.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';
import '../wajub_session.dart';

enum _PaymentTab { mobileMoney, card }

/// Native payment sheet — Mobile Money + card, no WebView.
///
/// Card tab by sdk-config flavor: `clientSession` (Paystack / Flutterwave —
/// the PSP's hosted checkout in the system browser), `stripe_elements`
/// (native Stripe field), `hosted_redirect` (PayPal / Mollie / Paddle).
/// `adyen_custom_card` is shown as unavailable.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.session,
    required this.onDismiss,
    required this.onResult,
  });

  final WajubSession session;
  final VoidCallback onDismiss;
  final ValueChanged<PaymentResult> onResult;

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
      setState(() {
        _session = session;
        _sdkConfig = sdkConfig;
        _loading = false;
        _selectedMomo = momo.isNotEmpty ? momo.first : null;
        _country = _selectedMomo?.countries.firstOrNull ?? 'CM';
        if (momo.isEmpty && hasCard) _tab = _PaymentTab.card;
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
    setState(() {
      _submitting = true;
      _error = null;
    });
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

  Future<void> _payCard() async {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    final cardCfg = _sdkConfig?.channels[cardSlug];
    if (cardCfg?.sdk != SdkFlavor.stripeElements || cardCfg?.publishableKey == null) {
      setState(() => _error = const WajubError(
            type: WajubErrorType.paymentError,
            message: 'Card payments unavailable for this session',
            code: 'provider_unavailable',
          ));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
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
    setState(() {
      _submitting = true;
      _error = null;
    });
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
          _error = const WajubError(
            type: WajubErrorType.apiError,
            message: 'Could not open the payment page.',
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
          e.declineCode != null
              ? PaymentFailed(error: e, transaction: transaction)
              : PaymentProcessing(transaction),
        );
        return;
      }
      setState(() => _error = e);
    }
  }

  /// PayPal / Mollie / Paddle: the PSP's own page collects the card.
  Future<void> _payCardHostedRedirect() async {
    final cardSlug = widget.session.cardChannelSlug() ?? 'card';
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.session.payCardHostedRedirect(channelSlug: cardSlug);
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
            decoration: const InputDecoration(labelText: 'Email (for your receipt)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _payCardClientSession,
            child: Text(_submitting ? 'Processing…' : 'Pay by card'),
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
            decoration: const InputDecoration(labelText: 'Cardholder name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          CardField(
            onCardChanged: (details) => setState(() => _cardComplete = details?.complete ?? false),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting || !_cardComplete ? null : _payCard,
            child: Text(_submitting ? 'Processing…' : 'Pay with card'),
          ),
        ],
      );
    }
    if (cfg?.sdk == SdkFlavor.hostedRedirect) {
      return FilledButton(
        onPressed: _submitting ? null : _payCardHostedRedirect,
        child: Text(_submitting ? 'Processing…' : 'Pay by card'),
      );
    }
    return const Text('Card payments unavailable for this session.');
  }

  @override
  Widget build(BuildContext context) {
    final momoChannels = _session?.channels.where(
          (c) => c.type.toLowerCase() == 'mobile_money' || c.type.toLowerCase() == 'mobile',
        ).toList() ??
        [];
    final hasCard = _session?.channels.any((c) => c.type.toLowerCase() == 'card') ?? false;

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
                  const Expanded(
                    child: Text('Pay with Wajub', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close)),
                ],
              ),
              if (momoChannels.isNotEmpty && hasCard) ...[
                SegmentedButton<_PaymentTab>(
                  segments: const [
                    ButtonSegment(value: _PaymentTab.mobileMoney, label: Text('Mobile Money')),
                    ButtonSegment(value: _PaymentTab.card, label: Text('Card')),
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
                  _error?.message ?? 'Failed to load session',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else ...[
                // Submit errors stay inline so the payer can fix the input
                // (e.g. an email the PSP requires) and retry.
                if (_error != null) ...[
                  Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                if (_tab == _PaymentTab.mobileMoney) ...[
                if (momoChannels.isEmpty)
                  const Text('No Mobile Money channels available.')
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
                    decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting || _phoneController.text.trim().isEmpty ? null : _payMomo,
                    child: Text(_submitting ? 'Processing…' : 'Pay now'),
                  ),
                ],
                ] else if (!hasCard)
                  const Text('No card channel available.')
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
Future<void> showWajubPaymentSheet({
  required BuildContext context,
  required WajubSession session,
  required ValueChanged<PaymentResult> onResult,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => PaymentSheet(
      session: session,
      onDismiss: () => Navigator.of(ctx).pop(),
      onResult: (result) {
        onResult(result);
        Navigator.of(ctx).pop();
      },
    ),
  );
}
