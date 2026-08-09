import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../action_handler.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';
import '../wajub_session.dart';

enum _PaymentTab { mobileMoney, card }

/// Native payment sheet — Mobile Money + Stripe card, no WebView.
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

class _PaymentSheetState extends State<PaymentSheet> {
  SessionData? _session;
  SdkConfig? _sdkConfig;
  bool _loading = true;
  bool _submitting = false;
  WajubError? _error;
  SessionChannel? _selectedMomo;
  final _phoneController = TextEditingController();
  final _holderController = TextEditingController();
  String _country = 'CM';
  _PaymentTab _tab = _PaymentTab.mobileMoney;
  bool _cardComplete = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    if (cardCfg?.sdk != 'stripe_elements' || cardCfg?.publishableKey == null) {
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

  @override
  void dispose() {
    _phoneController.dispose();
    _holderController.dispose();
    super.dispose();
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
              else if (_error != null)
                Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error))
              else if (_tab == _PaymentTab.mobileMoney) ...[
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
              else ...[
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
