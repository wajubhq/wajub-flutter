import 'payment_result.dart';

/// How a confirmation step appears in the API's answers and requests.
extension PaymentStepKeys on PaymentStepKind {
  /// The id key of the step's `202` and of its verify body: `otp_id`.
  String get idKey => '${name}_id';

  /// The key of the step's text in the `202`: `otp_masked_contact`,
  /// `pin_instruction`…
  String get hintKey => this == PaymentStepKind.otp ? 'otp_masked_contact' : '${name}_instruction';
}

/// `confirm_otp` → [PaymentStepKind.otp]; anything else → null.
PaymentStepKind? stepKindOf(String? action) {
  for (final kind in PaymentStepKind.values) {
    if (action == 'confirm_${kind.name}') return kind;
  }
  return null;
}
