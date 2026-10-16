import 'package:meta/meta.dart';

import 'json_read.dart';

/// One step to get the payer's own code.
class PayerOtpStep {
  const PayerOtpStep({required this.text, this.template});

  /// The step, ready to show.
  final String text;

  /// The same step with `{ussd_code}`, `{amount}` and `{currency}` left to
  /// fill, to show those values your own way.
  final String? template;

  static PayerOtpStep? fromJson(Object? json) {
    final map = readMap(json);
    final text = readText(map?['text']);
    if (map == null || text == null) return null;
    return PayerOtpStep(text: text, template: readText(map['template']));
  }
}

/// What a part of a step is: plain words, the code to dial, the amount.
@internal
enum PayerOtpPart { text, ussdCode, amount }

/// How the payer generates, in the operator's menu, the code their operator
/// asks for before the payment, for its exact amount. The payment sheet
/// shows it by itself.
class PayerOtpInstructions {
  const PayerOtpInstructions({
    required this.channel,
    this.ussdCode,
    this.otpLength,
    required this.amount,
    required this.currency,
    this.steps = const {},
    this.reason,
    this.attemptsRemaining,
  });

  /// The channel the code is for.
  final String channel;

  /// The code to dial (`*144*4*6#`), shown as is.
  final String? ussdCode;

  /// The code's exact number of digits; null: 4 to 8.
  final int? otpLength;

  /// The exact amount the payer types in the operator's menu: show it as
  /// it is, never reformatted.
  final String amount;
  final String currency;

  /// By language (`fr`, `en`…).
  final Map<String, List<PayerOtpStep>> steps;

  /// Why the payment asks for it: `required` (no code yet), `invalid` (not
  /// the right length; it does not count), `refused` (the operator did not
  /// accept it). Null when the payment's channel announces it.
  final String? reason;

  /// Codes the operator may still refuse for this payment on this channel.
  final int? attemptsRemaining;

  /// A `tel:` link that opens the dialer on [ussdCode] (`#` written
  /// `%23`), or null without one. Android dials it; iOS refuses `*` and `#`
  /// in a link, so offer to copy the code there.
  String? get dialUrl {
    final code = ussdCode;
    return code == null ? null : 'tel:${code.replaceAll('#', '%23')}';
  }

  /// The shortest and the longest code when [otpLength] does not say.
  static const minLength = 4;
  static const maxLength = 8;

  /// Whether [code] is digits 0-9 of the length the operator wants.
  bool accepts(String code) {
    if (!RegExp(r'^[0-9]+$').hasMatch(code)) return false;
    final length = otpLength;
    return length == null ? code.length >= minLength && code.length <= maxLength : code.length == length;
  }

  /// The steps in [language], else English, else French; empty when none.
  List<PayerOtpStep> stepsFor(String language) {
    for (final key in [language, 'en', 'fr']) {
      final list = steps[key];
      if (list != null && list.isNotEmpty) return list;
    }
    return const [];
  }

  /// [step] in parts: from its template when every value it names is known,
  /// else its plain text.
  @internal
  List<(PayerOtpPart, String)> parts(PayerOtpStep step) {
    final template = step.template;
    if (template == null) return [(PayerOtpPart.text, step.text)];
    final values = <String, (PayerOtpPart, String?)>{
      'ussd_code': (PayerOtpPart.ussdCode, ussdCode),
      'amount': (PayerOtpPart.amount, amount),
      'currency': (PayerOtpPart.text, currency),
    };
    final parts = <(PayerOtpPart, String)>[];
    var at = 0;
    for (final match in RegExp(r'\{([^{}]*)\}').allMatches(template)) {
      final value = values[match.group(1)];
      if (value == null || value.$2 == null || value.$2!.isEmpty) return [(PayerOtpPart.text, step.text)];
      if (match.start > at) parts.add((PayerOtpPart.text, template.substring(at, match.start)));
      parts.add((value.$1, value.$2!));
      at = match.end;
    }
    if (at < template.length) parts.add((PayerOtpPart.text, template.substring(at)));
    return parts;
  }

  static PayerOtpInstructions? fromJson(Object? json) {
    final map = readMap(json);
    final amount = readText(map?['amount']);
    if (map == null || amount == null) return null;
    final length = readInt(map['otp_length']);
    return PayerOtpInstructions(
      channel: readString(map['channel']) ?? '',
      ussdCode: readText(map['ussd_code']),
      otpLength: length != null && length > 0 ? length : null,
      amount: amount,
      currency: readString(map['currency']) ?? '',
      steps: {
        for (final entry in (readMap(map['steps']) ?? const <String, dynamic>{}).entries)
          entry.key.toLowerCase(): [
            for (final step in entry.value is List ? entry.value as List : const []) PayerOtpStep.fromJson(step),
          ].whereType<PayerOtpStep>().toList(),
      },
      reason: readText(map['reason'])?.toLowerCase(),
      attemptsRemaining: readInt(map['attempts_remaining']),
    );
  }
}
