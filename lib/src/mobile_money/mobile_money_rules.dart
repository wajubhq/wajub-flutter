import 'mobile_money_data.dart';
import 'operator_choice.dart';

/// The Mobile Money form's rules: validation, mismatch, preselection by
/// detection and the `operator` hint, with the error catalogue's form codes.
abstract final class MobileMoneyRules {
  /// What stops a submission, checked in this order: `phone_required`,
  /// `invalid_phone`, `operator_mismatch`, `operator_required`; null when
  /// nothing does. In a [sandbox] session a test number's operator is its
  /// prefix's, and a mismatch blocks as in live.
  static String? validate({
    required MobileMoneyData data,
    required String phone,
    required String country,
    required List<String> choiceIds,
    required String? selectedId,
    bool sandbox = false,
  }) {
    if (MobileMoneyData.sanitize(phone).isEmpty) return 'phone_required';
    if (!data.isValid(phone, country, sandbox: sandbox)) return 'invalid_phone';
    final mismatched = mismatch(
      data: data,
      phone: phone,
      country: country,
      choiceIds: choiceIds,
      selectedId: selectedId,
      sandbox: sandbox,
    );
    if (mismatched != null) return 'operator_mismatch';
    if (selectedId == null || !choiceIds.contains(selectedId)) return 'operator_required';
    return null;
  }

  /// The operator the number belongs to when it is offered, is not the one
  /// selected, and the selection is not a wallet that takes any number — the
  /// `{detected}` of `operator_mismatch`. Null otherwise, and without a
  /// selection.
  static String? mismatch({
    required MobileMoneyData data,
    required String phone,
    required String country,
    required List<String> choiceIds,
    required String? selectedId,
    bool sandbox = false,
  }) {
    if (selectedId == null || data.isOperatorIndependent(selectedId)) return null;
    final detected = data.detectOperator(phone, country, sandbox: sandbox);
    if (detected == null || detected == selectedId || !choiceIds.contains(detected)) return null;
    return detected;
  }

  /// The selection once the number changed: an operator the payer picked by
  /// hand is kept ("a payer who picked Wave keeps it on their Orange
  /// number"); otherwise a detected operator among the choices is selected;
  /// otherwise the selection stays, or the first choice is.
  static String? preselect({
    required List<String> choiceIds,
    required String? currentId,
    required bool pickedByHand,
    required String? detectedId,
  }) {
    final current = currentId != null && choiceIds.contains(currentId) ? currentId : null;
    if (pickedByHand && current != null) return current;
    if (detectedId != null && choiceIds.contains(detectedId)) return detectedId;
    return current ?? (choiceIds.isEmpty ? null : choiceIds.first);
  }

  /// The `operator` to send: only through an aggregate, and only when the
  /// payer picked it by hand or the number names it. A default the payer
  /// never touched is not sent — the API would route to it instead of
  /// refusing the number.
  static String? operatorHint({
    required bool viaAggregate,
    required String selectedId,
    required bool pickedByHand,
    required String? detectedId,
  }) {
    if (!viaAggregate) return null;
    return pickedByHand || detectedId == selectedId ? selectedId : null;
  }

  /// `data` of `POST /pay/process` for [choice], without `_client`,
  /// `return_url` or `altcha`: `{phone (E.164), country, operator?}`.
  static Map<String, Object?> requestData({
    required MobileMoneyData data,
    required String phone,
    required String country,
    required OperatorChoice choice,
    required bool pickedByHand,
    bool sandbox = false,
  }) {
    final hint = operatorHint(
      viaAggregate: choice.viaAggregate,
      selectedId: choice.id,
      pickedByHand: pickedByHand,
      detectedId: data.detectOperator(phone, country, sandbox: sandbox),
    );
    return {
      'phone': data.e164(phone, country, sandbox: sandbox),
      'country': country.toUpperCase(),
      if (hint != null) 'operator': hint,
    };
  }

  /// Whether the operator list shows. With `operatorMode:
  /// "detect"` it stays hidden until the number (6 digits or more) names no
  /// offered operator, or a wallet that takes any number is offered while the
  /// number names an operator, or the payer opens it; meanwhile
  /// [fieldBadge] shows inside the field. Any other mode always shows it.
  static bool showOperatorList({
    required MobileMoneyData data,
    required String operatorMode,
    required String phone,
    required String country,
    required List<String> choiceIds,
    bool openedByPayer = false,
    bool sandbox = false,
  }) {
    if (operatorMode != 'detect' || openedByPayer) return true;
    if (data.nationalDigits(phone, country).length < 6) return false;
    final detected = data.detectOperator(phone, country, sandbox: sandbox);
    if (detected == null || !choiceIds.contains(detected)) return true;
    return choiceIds.any(data.isOperatorIndependent);
  }

  /// The operator shown inside the phone field while the list is hidden: the
  /// detected one when it is offered, else the only choice, else none.
  static String? fieldBadge({
    required MobileMoneyData data,
    required String phone,
    required String country,
    required List<String> choiceIds,
    bool sandbox = false,
  }) {
    final detected = data.detectOperator(phone, country, sandbox: sandbox);
    if (detected != null && choiceIds.contains(detected)) return detected;
    return choiceIds.length == 1 ? choiceIds.single : null;
  }
}
