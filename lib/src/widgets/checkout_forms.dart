import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../appearance/wajub_theme.dart';
import '../checkout/checkout_controller.dart';
import '../checkout/digits.dart';
import '../checkout/checkout_methods.dart';
import '../errors/error_catalogue.dart';
import '../mobile_money/mobile_money_data.dart';
import '../mobile_money/operator_choice.dart';
import '../mobile_money/operator_logo.dart';
import '../models/payer_otp.dart';
import '../models/payment_result.dart';
import 'network_logo.dart';
import 'sheet_strings.dart';

/// The form of the method being paid.
class CheckoutForm extends StatelessWidget {
  const CheckoutForm({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final method = controller.method;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.canGoBack)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('wajub-back'),
              onPressed: controller.backToMethods,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(strings.back),
            ),
          ),
        if (controller.banner != null) ...[
          Banner(message: controller.banner!),
          SizedBox(height: theme.gapRow),
        ],
        switch (method?.family) {
          MethodFamily.mobileMoney => MobileMoneyForm(controller: controller, strings: strings),
          MethodFamily.card => _CardForm(controller: controller, strings: strings),
          MethodFamily.wallet => _WalletForm(controller: controller, strings: strings),
          null => const SizedBox.shrink(),
        },
        if (controller.canCancel) ...[
          SizedBox(height: theme.spacingUnit * 2),
          CancelPaymentButton(controller: controller, strings: strings),
        ],
      ],
    );
  }
}

/// "Cancel payment".
class CancelPaymentButton extends StatelessWidget {
  const CancelPaymentButton({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) => TextButton(
        key: const ValueKey('wajub-cancel-payment'),
        onPressed: controller.busy ? null : controller.cancelPayment,
        style: TextButton.styleFrom(foregroundColor: WajubTheme.of(context).colors.textSecondary),
        child: Text(strings.cancelPayment),
      );
}

/// A refusal tied to no field.
class Banner extends StatelessWidget {
  const Banner({super.key, required this.message, this.warning = false});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    return Container(
      key: ValueKey(warning ? 'wajub-warning' : 'wajub-banner'),
      padding: EdgeInsets.all(theme.spacingUnit * 3),
      decoration: BoxDecoration(
        color: warning ? colors.warningBackground : colors.dangerBackground,
        borderRadius: BorderRadius.circular(theme.radius),
      ),
      child: Text(
        message,
        style: TextStyle(color: warning ? colors.warning : colors.danger, fontSize: theme.fontSizeLabel),
      ),
    );
  }
}

/// The Pay button, busy while the request runs.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.controller, required this.label, required this.onPressed});

  final CheckoutController controller;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final busy = controller.busy;
    final colors = WajubTheme.of(context).colors;
    return FilledButton(
      key: const ValueKey('wajub-pay-button'),
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
            )
          : Text(label),
    );
  }
}

String _amount(CheckoutController controller) =>
    formatAmount(controller.amountToPay, controller.sessionData!.transaction.currency, controller.language);

/// Country, operator and number: the number preselects its operator until
/// the payer picks one, and is formatted as it is typed.
class MobileMoneyForm extends StatefulWidget {
  const MobileMoneyForm({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  State<MobileMoneyForm> createState() => _MobileMoneyFormState();
}

class _MobileMoneyFormState extends State<MobileMoneyForm> {
  late final _phone = TextEditingController(text: MobileMoneyData.formatAsYouType(widget.controller.phone));

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.strings;
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final data = controller.mobileMoneyData;
    final countryInfo = controller.country == null ? null : data?.countries[controller.country];
    final choices = controller.choices;
    final errors = controller.fieldErrors;
    final showList = controller.showOperatorList;
    final badge = showList ? null : controller.badgeOperator;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!controller.countryLocked && data != null) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('wajub-country'),
            // `value` is deprecated from Flutter 3.35 for `initialValue`,
            // which 3.24 (this package's floor) does not have.
            // ignore: deprecated_member_use
            value: controller.country,
            decoration: InputDecoration(labelText: strings.country),
            items: [
              for (final code in controller.countries)
                DropdownMenuItem(
                  value: code,
                  child: Text('${data.countries[code]?.name ?? code} (${data.countries[code]?.dialCode ?? code})'),
                ),
            ],
            onChanged: controller.busy
                ? null
                : (code) {
                    if (code == null) return;
                    controller.setCountry(code);
                    _phone.clear();
                    controller.setPhone('');
                  },
          ),
          SizedBox(height: theme.gapRow),
        ],
        if (showList) ...[
          Text(
            strings.operator,
            style: TextStyle(
                color: colors.textSecondary, fontSize: theme.fontSizeLabel, fontWeight: theme.fontWeightMedium),
          ),
          SizedBox(height: theme.spacingUnit * 2),
          if (choices.isEmpty)
            Banner(message: _operatorUnavailable(controller.language))
          else
            for (final choice in choices) ...[
              _OperatorTile(
                choice: choice,
                selected: choice.id == controller.selectedOperatorId,
                note: _blockText(controller, strings, controller.operatorBlock(choice)),
                onTap: controller.busy || controller.operatorBlock(choice) != null
                    ? null
                    : () => controller.pickOperator(choice.id),
              ),
              SizedBox(height: theme.spacingUnit * 2),
            ],
          if (errors['data.operator'] != null)
            Padding(
              padding: EdgeInsets.only(bottom: theme.spacingUnit * 2),
              child:
                  Text(errors['data.operator']!, style: TextStyle(color: colors.danger, fontSize: theme.fontSizeHint)),
            ),
          SizedBox(height: theme.gapRow - theme.spacingUnit * 2),
        ],
        TextField(
          key: const ValueKey('wajub-phone-field'),
          controller: _phone,
          enabled: !controller.busy,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [_PhoneFormatter()],
          style: TextStyle(color: colors.text, fontSize: theme.inputFontSize),
          decoration: InputDecoration(
            labelText: strings.mobileMoneyNumber,
            hintText: countryInfo?.placeholderFormatted,
            prefixText: countryInfo == null ? null : '${countryInfo.dialCode} ',
            errorText: errors['data.phone'],
            errorMaxLines: 3,
            suffixIcon: badge == null
                ? null
                : Padding(
                    padding: EdgeInsets.all(theme.spacingUnit * 2),
                    child: OperatorLogo(key: const ValueKey('wajub-operator-badge'), choice: badge, size: 24),
                  ),
          ),
          onChanged: controller.setPhone,
          onSubmitted: (_) => unawaited(controller.payMobileMoney()),
        ),
        if (!showList && choices.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('wajub-change-operator'),
              onPressed: controller.openOperatorList,
              child: Text(strings.changeOperator),
            ),
          ),
        SizedBox(height: theme.gapRow),
        if (controller.announcedPayerOtp case final announced?) ...[
          Text(
            strings.payerOtpFormHint(announced.ussdCode),
            key: const ValueKey('wajub-payer-otp-hint'),
            style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel),
          ),
          SizedBox(height: theme.gapRow),
        ],
        _PayButton(
          controller: controller,
          label: strings.pay(_amount(controller)),
          // A disabled operator is never selected: with none offered, no Pay.
          onPressed: controller.hasOfferedOperator ? () => unawaited(controller.payMobileMoney()) : null,
        ),
      ],
    );
  }

  /// Why an operator cannot take the payment, in words.
  static String? _blockText(CheckoutController controller, SheetStrings strings, OperatorBlock? block) {
    if (block == null) return null;
    final limit = block.limit;
    if (limit == null) return block.message;
    return (limit.minimum
        ? strings.minimum
        : strings.maximum)(formatAmount(limit.amount, limit.currency, controller.language));
  }

  String _operatorUnavailable(String language) =>
      ErrorCatalogue.text(ErrorCatalogue.lookup('operator_unavailable')!, language);
}

/// Digits only, grouped by two, as the payer types (`algorithms.format_as_you_type`).
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = MobileMoneyData.formatAsYouType(newValue.text);
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _OperatorTile extends StatelessWidget {
  const _OperatorTile({required this.choice, required this.selected, required this.onTap, this.note});

  final OperatorChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  /// Why it cannot take the payment: the tile is then disabled.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final tile = Material(
      color: selected ? colors.selectedBackground : colors.inputBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
        side: BorderSide(color: selected ? colors.primary : colors.inputBorder, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('wajub-operator-${choice.id}'),
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: theme.spacingUnit * 3, vertical: theme.spacingUnit * 2),
            child: Row(
              children: [
                OperatorLogo(choice: choice),
                SizedBox(width: theme.spacingUnit * 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice.label,
                        style: TextStyle(
                            color: colors.text, fontSize: theme.fontSizeBase, fontWeight: theme.fontWeightMedium),
                      ),
                      if (note != null)
                        Text(note!, style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeHint)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? colors.primary : colors.textPlaceholder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return note == null ? tile : Opacity(opacity: theme.disabledOpacity, child: tile);
  }
}

/// The card form of the flavour sdk-config names.
class _CardForm extends StatefulWidget {
  const _CardForm({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  var _stripeComplete = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.strings;
    final theme = WajubTheme.of(context);
    final flavour = controller.method?.cardFlavour;
    final fields = controller.cardRequiredFields;
    final hint = switch (flavour) {
      CardFlavour.sandboxForm => strings.sandboxCardHint,
      CardFlavour.clientSession || CardFlavour.hostedRedirect => strings.hostedCardHint,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null) ...[
          Text(hint, style: TextStyle(color: theme.colors.textSecondary, fontSize: theme.fontSizeLabel)),
          SizedBox(height: theme.gapRow),
        ],
        if (flavour == CardFlavour.stripe) ...[
          _Field(controller: controller, strings: strings, name: 'card_holder'),
          SizedBox(height: theme.gapRow),
          CardField(onCardChanged: (details) => setState(() => _stripeComplete = details?.complete ?? false)),
        ] else if (flavour == CardFlavour.sandboxForm) ...[
          _Field(controller: controller, strings: strings, name: 'card.number', keyboard: TextInputType.number),
          SizedBox(height: theme.gapRow),
          _Field(controller: controller, strings: strings, name: 'card_holder'),
          SizedBox(height: theme.gapRow),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final name in const ['expiry_month', 'expiry_year', 'cvv']) ...[
                if (name != 'expiry_month') SizedBox(width: theme.gapColumn),
                Expanded(
                  child: _Field(
                    controller: controller,
                    strings: strings,
                    name: name,
                    keyboard: TextInputType.number,
                    obscure: name == 'cvv',
                  ),
                ),
              ],
            ],
          ),
        ] else
          for (final name in fields) ...[
            _Field(
              controller: controller,
              strings: strings,
              name: name,
              keyboard: switch (name) {
                'email' => TextInputType.emailAddress,
                'phone' => TextInputType.phone,
                _ => TextInputType.text,
              },
            ),
            SizedBox(height: theme.gapRow),
          ],
        if (flavour == CardFlavour.stripe || flavour == CardFlavour.sandboxForm) SizedBox(height: theme.gapRow),
        _PayButton(
          controller: controller,
          label: strings.pay(_amount(controller)),
          onPressed: flavour == null || (flavour == CardFlavour.stripe && !_stripeComplete)
              ? null
              : () => unawaited(controller.payCard()),
        ),
      ],
    );
  }
}

/// One text field of a form, under its request key.
class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.strings,
    required this.name,
    this.keyboard = TextInputType.text,
    this.obscure = false,
  });

  final CheckoutController controller;
  final SheetStrings strings;
  final String name;
  final TextInputType keyboard;
  final bool obscure;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _text = TextEditingController(text: widget.controller.cardFields[widget.name] ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errors = widget.controller.fieldErrors;
    return TextField(
      key: ValueKey('wajub-field-${widget.name}'),
      controller: _text,
      enabled: !widget.controller.busy,
      keyboardType: widget.keyboard,
      inputFormatters: const [AsciiDigitsFormatter()],
      obscureText: widget.obscure,
      textCapitalization: widget.name == 'country' ? TextCapitalization.characters : TextCapitalization.none,
      style: TextStyle(fontSize: WajubTheme.of(context).inputFontSize),
      decoration: InputDecoration(
        labelText: widget.strings.field(widget.name),
        errorText: errors[widget.name] ?? errors['data.${widget.name}'],
      ),
      onChanged: (value) => widget.controller.setCardField(widget.name, value),
    );
  }
}

/// A one-tap wallet: nothing to fill, its page opens its app.
class _WalletForm extends StatelessWidget {
  const _WalletForm({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final channel = controller.method!.channel;
    final name = channel.localizedName(controller.language);
    final logo = NetworkLogo.of(
      logo: channel.logo,
      logoPng: channel.logoPng,
      width: 40,
      height: 40,
      fallback: Icon(Icons.account_balance_wallet_outlined, color: theme.colors.textSecondary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (logo != null) ...[
              logo,
              SizedBox(width: theme.spacingUnit * 3),
            ],
            Expanded(
              child: Text(
                strings.walletHint,
                style: TextStyle(color: theme.colors.textSecondary, fontSize: theme.fontSizeLabel),
              ),
            ),
          ],
        ),
        SizedBox(height: theme.gapRow),
        _PayButton(
          controller: controller,
          label: strings.payWith(name),
          onPressed: () => unawaited(controller.payWallet()),
        ),
      ],
    );
  }
}

/// Seconds left before [at], at least 0.
int _secondsUntil(DateTime? at) =>
    at == null ? 0 : (at.difference(clock.now()).inMilliseconds / 1000).ceil().clamp(0, 1 << 30);

/// A confirmation step: OTP, card PIN, phone, date of birth or billing
/// address.
class StepForm extends StatefulWidget {
  const StepForm({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  State<StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<StepForm> {
  final _fields = <String, TextEditingController>{};

  TextEditingController _field(String name) => _fields.putIfAbsent(name, TextEditingController.new);

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  static List<String> _names(PaymentStepKind kind) => switch (kind) {
        PaymentStepKind.otp => const ['code'],
        PaymentStepKind.pin => const ['pin'],
        PaymentStepKind.phone => const ['phone'],
        PaymentStepKind.birthday => const ['birthday'],
        PaymentStepKind.address => const ['address', 'city', 'state', 'zip_code'],
      };

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => _field('birthday').text = '${picked.year}-${two(picked.month)}-${two(picked.day)}');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.strings;
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final kind = controller.stepKind!;
    final hint = controller.stepHint;
    final errors = controller.fieldErrors;
    final busy = controller.busy;
    final wait = _secondsUntil(controller.resendAt);
    final names = _names(kind);

    void submit() => unawaited(controller.submitStep({for (final name in names) name: _field(name).text}));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.stepTitle(kind.name),
          style: TextStyle(color: colors.text, fontSize: theme.fontSizeBase * 1.125, fontWeight: theme.fontWeightBold),
        ),
        if (hint != null && hint.isNotEmpty) ...[
          SizedBox(height: theme.spacingUnit * 2),
          Text(
            kind == PaymentStepKind.otp ? strings.codeSentTo(hint) : hint,
            style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel),
          ),
        ],
        SizedBox(height: theme.gapRow),
        if (controller.banner != null) ...[
          Banner(message: controller.banner!),
          SizedBox(height: theme.gapRow),
        ],
        for (final name in names) ...[
          TextField(
            key: ValueKey('wajub-step-$name'),
            controller: _field(name),
            enabled: !busy,
            readOnly: name == 'birthday',
            onTap: name == 'birthday' && !busy ? _pickBirthday : null,
            obscureText: name == 'pin',
            keyboardType: switch (name) {
              'code' || 'pin' => TextInputType.number,
              'phone' => TextInputType.phone,
              _ => TextInputType.text,
            },
            inputFormatters: switch (name) {
              'code' => [
                  const AsciiDigitsFormatter(),
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10)
                ],
              'pin' => [
                  const AsciiDigitsFormatter(),
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6)
                ],
              _ => [const AsciiDigitsFormatter()],
            },
            style: TextStyle(fontSize: theme.inputFontSize),
            decoration: InputDecoration(
              labelText: strings.field(name),
              hintText: name == 'birthday' ? 'YYYY-MM-DD' : null,
              errorText: errors[name],
              suffixIcon: name == 'birthday' ? const Icon(Icons.calendar_today_outlined) : null,
            ),
            onSubmitted: (_) => submit(),
          ),
          SizedBox(height: theme.gapRow),
        ],
        FilledButton(
          key: const ValueKey('wajub-step-submit'),
          onPressed: busy ? null : submit,
          child: busy
              ? SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
              : Text(strings.verify),
        ),
        if (kind == PaymentStepKind.otp)
          TextButton(
            key: const ValueKey('wajub-resend'),
            onPressed: busy || wait > 0 ? null : () => unawaited(controller.resend()),
            child: Text(wait > 0 ? strings.resendIn(wait) : strings.resend),
          ),
      ],
    );
  }
}

/// The sandbox 3-D Secure email code.
class ThreeDsForm extends StatefulWidget {
  const ThreeDsForm({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  State<ThreeDsForm> createState() => _ThreeDsFormState();
}

class _ThreeDsFormState extends State<ThreeDsForm> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.strings;
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final busy = controller.busy;
    final wait = _secondsUntil(controller.resendAt);
    final left = _secondsUntil(controller.threeDsDeadline);
    final email = controller.stepHint;
    void submit() => unawaited(controller.submitThreeDsCode(_code.text));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.threeDsTitle,
          style: TextStyle(color: colors.text, fontSize: theme.fontSizeBase * 1.125, fontWeight: theme.fontWeightBold),
        ),
        if (email != null) ...[
          SizedBox(height: theme.spacingUnit * 2),
          Text(strings.codeSentTo(email), style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel)),
        ],
        if (controller.threeDsDeadline != null) ...[
          SizedBox(height: theme.spacingUnit),
          Text(
            strings.expiresIn('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}'),
            style: TextStyle(color: colors.textPlaceholder, fontSize: theme.fontSizeHint),
          ),
        ],
        SizedBox(height: theme.gapRow),
        if (controller.banner != null) ...[
          Banner(message: controller.banner!),
          SizedBox(height: theme.gapRow),
        ],
        TextField(
          key: const ValueKey('wajub-3ds-code'),
          controller: _code,
          enabled: !busy,
          keyboardType: TextInputType.number,
          inputFormatters: [
            const AsciiDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8)
          ],
          style: TextStyle(fontSize: theme.inputFontSize),
          decoration: InputDecoration(labelText: strings.field('code'), errorText: controller.fieldErrors['code']),
          onSubmitted: (_) => submit(),
        ),
        SizedBox(height: theme.gapRow),
        FilledButton(
          key: const ValueKey('wajub-step-submit'),
          onPressed: busy ? null : submit,
          child: busy
              ? SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
              : Text(strings.verify),
        ),
        TextButton(
          key: const ValueKey('wajub-resend'),
          onPressed: busy || wait > 0 ? null : () => unawaited(controller.resend()),
          child: Text(wait > 0 ? strings.resendIn(wait) : strings.resend),
        ),
      ],
    );
  }
}

/// The code the payer generates in the operator's menu, for the exact
/// amount, before the payment goes through.
class PayerOtpForm extends StatefulWidget {
  const PayerOtpForm({super.key, required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  /// The code that pays in test mode.
  static const sandboxCode = '123456';

  @override
  State<PayerOtpForm> createState() => _PayerOtpFormState();
}

class _PayerOtpFormState extends State<PayerOtpForm> {
  final _code = TextEditingController();
  late final _dial = TapGestureRecognizer()..onTap = _dialCode;
  Timer? _copiedTimer;
  var _copied = false;

  /// Android dials a code with `*` and `#` from a link; iOS does not.
  bool get _dials => defaultTargetPlatform == TargetPlatform.android;

  void _dialCode() => unawaited(widget.controller.dialPayerOtpCode());

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _dial.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.strings;
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final unit = theme.spacingUnit;
    final busy = controller.busy;
    final instructions = controller.payerOtp!;
    final ussd = instructions.ussdCode;
    final steps = instructions.stepsFor(controller.language);
    final attempts = controller.payerOtpAttemptsRemaining;
    final error = switch (controller.payerOtpNotice) {
      PayerOtpNotice.invalidLength => strings.payerOtpLength(instructions.otpLength),
      PayerOtpNotice.refused => ErrorCatalogue.text(ErrorCatalogue.payerOtpRefused, controller.language),
      null => null,
    };
    final label =
        TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeHint, fontWeight: theme.fontWeightMedium);
    final body = TextStyle(color: colors.text, fontSize: theme.fontSizeLabel);
    final strong = body.copyWith(fontWeight: theme.fontWeightBold);
    final link = strong.copyWith(color: colors.link, decoration: TextDecoration.underline);

    Widget block(String title, Widget child) => Container(
          padding: EdgeInsets.all(unit * 3),
          decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(theme.radius)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: label), SizedBox(height: unit), child],
          ),
        );

    InlineSpan part((PayerOtpPart, String) part) => switch (part.$1) {
          PayerOtpPart.ussdCode =>
            TextSpan(text: part.$2, style: _dials ? link : strong, recognizer: _dials ? _dial : null),
          PayerOtpPart.amount => TextSpan(text: part.$2, style: strong),
          PayerOtpPart.text => TextSpan(text: part.$2),
        };

    final lines = steps.isEmpty
        ? [
            for (final text in strings.payerOtpGenericSteps(instructions.amountText)) TextSpan(text: text),
          ]
        : [
            for (final step in steps) TextSpan(children: [for (final p in instructions.parts(step)) part(p)]),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.payerOtp('title'),
          style: TextStyle(color: colors.text, fontSize: theme.fontSizeBase * 1.125, fontWeight: theme.fontWeightBold),
        ),
        SizedBox(height: unit * 2),
        Text(strings.payerOtp('description'),
            style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel)),
        SizedBox(height: theme.gapRow),
        if (ussd != null) ...[
          block(
            strings.payerOtp('dial'),
            Row(
              children: [
                Expanded(
                  child: _dials
                      ? InkWell(
                          key: const ValueKey('wajub-payer-otp-dial'),
                          onTap: _dialCode,
                          child: Text(ussd, style: link.copyWith(fontSize: theme.fontSizeBase * 1.25)),
                        )
                      : Text(ussd,
                          key: const ValueKey('wajub-payer-otp-ussd'),
                          style: strong.copyWith(fontSize: theme.fontSizeBase * 1.25)),
                ),
                TextButton.icon(
                  key: const ValueKey('wajub-payer-otp-copy'),
                  onPressed: () => unawaited(_copy(ussd)),
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                  label: Text(strings.payerOtp(_copied ? 'copied' : 'copy')),
                ),
              ],
            ),
          ),
          SizedBox(height: unit * 2),
        ],
        if (instructions.amountText case final amount?) ...[
          block(
            strings.payerOtp('amount'),
            Text(
              amount,
              key: const ValueKey('wajub-payer-otp-amount'),
              style: strong.copyWith(fontSize: theme.fontSizeBase * 1.25),
            ),
          ),
          SizedBox(height: theme.gapRow),
        ],
        Text(strings.payerOtp('stepsTitle'), style: label),
        SizedBox(height: unit),
        for (final (index, line) in lines.indexed) ...[
          Row(
            key: ValueKey('wajub-payer-otp-step-$index'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: unit * 6, child: Text('${index + 1}.', style: body)),
              Expanded(child: Text.rich(line, style: body)),
            ],
          ),
          SizedBox(height: unit),
        ],
        if (controller.sandbox) ...[
          SizedBox(height: unit),
          Banner(message: strings.payerOtpSandboxHint(PayerOtpForm.sandboxCode), warning: true),
        ],
        SizedBox(height: theme.gapRow),
        if (instructions.otpLength case final length? when length <= PayerOtpInstructions.maxLength)
          _CodeBoxes(
            controller: _code,
            length: length,
            enabled: !busy,
            label: strings.payerOtp('codeLabel'),
            error: error,
            onChanged: controller.payerOtpTyped,
          )
        else
          TextField(
            key: const ValueKey('wajub-payer-otp-code'),
            controller: _code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              const AsciiDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(instructions.otpLength ?? PayerOtpInstructions.maxLength),
            ],
            style: TextStyle(fontSize: theme.inputFontSize, letterSpacing: 4),
            decoration: InputDecoration(labelText: strings.payerOtp('codeLabel'), errorText: error, errorMaxLines: 3),
            onChanged: (_) => controller.payerOtpTyped(),
          ),
        if (attempts != null) ...[
          SizedBox(height: unit),
          Text(
            strings.payerOtpAttempts(attempts),
            key: const ValueKey('wajub-payer-otp-attempts'),
            style: TextStyle(color: colors.danger, fontSize: theme.fontSizeHint),
          ),
        ],
        SizedBox(height: theme.gapRow),
        FilledButton(
          key: const ValueKey('wajub-payer-otp-submit'),
          onPressed: busy ? null : () => unawaited(controller.submitPayerOtp(_code.text)),
          child: busy
              ? SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
              : Text(strings.payerOtp('submit')),
        ),
        TextButton(
          key: const ValueKey('wajub-payer-otp-change'),
          onPressed: busy ? null : controller.leavePayerOtp,
          child: Text(strings.payerOtp('changeMethod')),
        ),
      ],
    );
  }
}

/// One box per digit of the code, over one field the payer types in: a digit
/// fills the next box, backspace empties the last one, and a pasted or
/// autofilled code fills them all. Nothing is sent until the payer confirms.
class _CodeBoxes extends StatefulWidget {
  const _CodeBoxes({
    required this.controller,
    required this.length,
    required this.enabled,
    required this.label,
    this.error,
    this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final bool enabled;
  final String label;
  final String? error;

  /// The payer typed, erased or pasted.
  final VoidCallback? onChanged;

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_caretAtEnd);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_caretAtEnd);
    _focus.dispose();
    super.dispose();
  }

  /// Digits are typed and erased in order: the caret stays after the last.
  void _caretAtEnd() {
    final controller = widget.controller;
    final end = TextSelection.collapsed(offset: controller.text.length);
    if (controller.selection.isValid && controller.selection != end) controller.selection = end;
  }

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final unit = theme.spacingUnit;
    final error = widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style:
              TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel, fontWeight: theme.fontWeightMedium),
        ),
        SizedBox(height: unit * 2),
        Stack(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([widget.controller, _focus]),
              builder: (context, _) {
                final code = widget.controller.text;
                final current = code.length < widget.length ? code.length : widget.length - 1;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.length; i++) ...[
                      if (i > 0) SizedBox(width: unit * 2),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 52),
                          child: Container(
                            key: ValueKey('wajub-payer-otp-box-$i'),
                            width: double.infinity,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.enabled ? colors.inputBackground : colors.disabledBackground,
                              borderRadius: BorderRadius.circular(theme.radius),
                              border: Border.all(
                                color: error != null
                                    ? colors.danger
                                    : _focus.hasFocus && i == current
                                        ? colors.focusRing
                                        : colors.inputBorder,
                                width: _focus.hasFocus && i == current ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              i < code.length ? code[i] : '',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: theme.inputFontSize * 1.25,
                                fontWeight: theme.fontWeightBold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            // The field takes the taps, the keyboard, the paste menu and the
            // code the phone suggests; the boxes show what it holds. It is
            // drawn in transparent ink, not hidden: hidden, its paste menu
            // would not show.
            Positioned.fill(
              child: TextSelectionTheme(
                data: const TextSelectionThemeData(
                  cursorColor: Colors.transparent,
                  selectionColor: Colors.transparent,
                  selectionHandleColor: Colors.transparent,
                ),
                child: TextField(
                  key: const ValueKey('wajub-payer-otp-code'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  expands: true,
                  maxLines: null,
                  style: const TextStyle(color: Colors.transparent),
                  inputFormatters: [
                    const AsciiDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                    _PastedCodeReplaces(widget.length),
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  decoration: const InputDecoration.collapsed(hintText: null),
                  onChanged: (_) => widget.onChanged?.call(),
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          SizedBox(height: unit * 2),
          Text(error, style: TextStyle(color: colors.danger, fontSize: theme.fontSizeHint)),
        ],
      ],
    );
  }
}

/// A whole code pasted or autofilled after digits already typed replaces
/// them; a shorter paste completes them.
class _PastedCodeReplaces extends TextInputFormatter {
  const _PastedCodeReplaces(this.length);

  final int length;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final old = oldValue.text;
    if (old.isEmpty || !newValue.text.startsWith(old)) return newValue;
    final pasted = newValue.text.substring(old.length);
    if (pasted.length < length) return newValue;
    return TextEditingValue(text: pasted, selection: TextSelection.collapsed(offset: pasted.length));
  }
}
