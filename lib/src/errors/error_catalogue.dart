import '../models/wajub_error.dart';

/// One code of the error catalogue: its type, whether the
/// payer can try again, and its payer-facing text in both languages. `{…}`
/// are placeholders.
class ErrorEntry {
  const ErrorEntry(this.type, this.retryable, this.en, this.fr);

  final WajubErrorType type;
  final bool retryable;
  final String en;
  final String fr;
}

/// The codes the SDK knows, with their texts for the payer.
/// An API code missing here is passed through as it is.
abstract final class ErrorCatalogue {
  static const _api = WajubErrorType.apiError;
  static const _auth = WajubErrorType.authenticationError;
  static const _invalid = WajubErrorType.invalidRequestError;
  static const _payment = WajubErrorType.paymentError;

  static const _loadFailedEn = "We couldn't load the payment. Check your connection and try again.";
  static const _loadFailedFr = 'Impossible de charger le paiement. Vérifiez votre connexion et réessayez.';
  static const _stepExpiredEn = 'This verification has expired.';
  static const _stepExpiredFr = 'Cette vérification a expiré.';

  /// The text of a 402 whose `error_code` (`failed`, `stolen_card`…) is not
  /// in the catalogue.
  static const declineFallback = ErrorEntry(
    _payment,
    true,
    'This payment could not be completed. Try again or use another payment method.',
    "Ce paiement n'a pas abouti. Réessayez ou utilisez un autre moyen de paiement.",
  );

  /// `payment_in_progress` when a cancel is refused: the payment is being
  /// paid. (On a payment, the same code is not an error: the sheet waits.)
  static const cancelInProgress = ErrorEntry(
    _invalid,
    false,
    "This payment is being paid and can't be cancelled now.",
    'Ce paiement est en cours de règlement et ne peut pas être annulé maintenant.',
  );

  /// The entry of [code], [cancelling] when the error answers a cancel.
  static ErrorEntry? entryFor(String code, {bool cancelling = false}) =>
      cancelling && code == 'payment_in_progress' ? cancelInProgress : lookup(code);

  static const entries = <String, ErrorEntry>{
    // Load.
    'session_not_found': ErrorEntry(
      _auth,
      false,
      "We couldn't find this payment session. Check the link you received or ask the merchant for a new one.",
      "Nous n'avons pas pu retrouver cette session de paiement. Vérifiez le lien reçu ou demandez-en un nouveau au "
          'marchand.',
    ),
    'session_terminal_expired': ErrorEntry(
      _invalid,
      false,
      'This payment session has expired.',
      'Cette session de paiement a expiré.',
    ),
    'session_terminal_cancelled': ErrorEntry(
      _invalid,
      false,
      'This payment was cancelled.',
      'Ce paiement a été annulé.',
    ),
    'session_terminal_failed': ErrorEntry(
      _invalid,
      false,
      'This payment has ended without being paid. Ask the merchant for a new payment link.',
      "Ce paiement s'est terminé sans être réglé. Demandez un nouveau lien de paiement au marchand.",
    ),
    'load_error': ErrorEntry(_api, true, _loadFailedEn, _loadFailedFr),
    'ready_timeout': ErrorEntry(_api, true, _loadFailedEn, _loadFailedFr),
    'no_payment_method': ErrorEntry(
      _invalid,
      false,
      'No payment method is available for this payment.',
      "Aucun moyen de paiement n'est disponible pour ce paiement.",
    ),
    // Transport.
    'network_error': ErrorEntry(
      _api,
      true,
      'Connection error. Check your network.',
      'Erreur de connexion. Vérifiez votre réseau.',
    ),
    'timeout': ErrorEntry(_api, true, 'The request timed out.', "Le délai d'attente a été dépassé."),
    'server_error': ErrorEntry(
      _api,
      true,
      'Service temporarily unavailable.',
      'Service temporairement indisponible.',
    ),
    'rate_limited': ErrorEntry(
      WajubErrorType.rateLimitError,
      true,
      'Too many attempts. Please wait {seconds} s before trying again.',
      'Trop de tentatives. Merci de patienter {seconds} s avant de réessayer.',
    ),
    'request_failed': ErrorEntry(
      _invalid,
      false,
      'An error occurred. Please try again.',
      'Une erreur est survenue. Veuillez réessayer.',
    ),
    // Form: shown on the field, never sent to onError.
    'phone_required': ErrorEntry(
      _invalid,
      true,
      'Enter the Mobile Money number to pay with.',
      'Saisissez le numéro Mobile Money qui va payer.',
    ),
    'invalid_phone': ErrorEntry(_invalid, true, 'Invalid phone number', 'Numéro de téléphone invalide'),
    'operator_mismatch': ErrorEntry(
      _invalid,
      true,
      'This number belongs to {detected}. Pick {detected} in the list, or enter a {selected} number.',
      'Ce numéro est un numéro {detected}. Choisissez {detected} dans la liste, ou saisissez un numéro {selected}.',
    ),
    'operator_required': ErrorEntry(
      _invalid,
      true,
      'Choose your Mobile Money operator.',
      'Choisissez votre opérateur Mobile Money.',
    ),
    'operator_unavailable': ErrorEntry(
      _invalid,
      true,
      'No Mobile Money operator is available for this country. Try another payment method.',
      "Aucun opérateur Mobile Money n'est disponible pour ce pays. Essayez un autre moyen de paiement.",
    ),
    'field_required': ErrorEntry(_invalid, true, 'This field is required', 'Ce champ est requis'),
    'invalid_email': ErrorEntry(
      _invalid,
      true,
      'Enter a valid email address.',
      'Saisissez une adresse e-mail valide.',
    ),
    'validation_error': ErrorEntry(
      _invalid,
      true,
      'Check the information entered.',
      'Vérifiez les informations saisies.',
    ),
    // Payment.
    'payment_declined': ErrorEntry(
      _payment,
      true,
      'Payment declined by the issuer.',
      "Paiement refusé par l'émetteur.",
    ),
    'insufficient_funds': ErrorEntry(_payment, true, 'Insufficient funds.', 'Fonds insuffisants.'),
    'merchant_not_verified': ErrorEntry(
      _payment,
      false,
      "This merchant can't accept payments yet. Please contact them.",
      'Ce marchand ne peut pas encore accepter de paiements. Veuillez le contacter.',
    ),
    'limit_exceeded': ErrorEntry(
      _payment,
      true,
      "This payment exceeds this merchant's allowed limit. Try a smaller amount or contact the merchant.",
      'Ce paiement dépasse la limite autorisée pour ce marchand. Essayez un montant plus faible ou contactez le '
          'marchand.',
    ),
    'shield_blocked': ErrorEntry(
      _payment,
      false,
      'Payment blocked for security. Reference: {block_reference}.',
      'Paiement bloqué pour sécurité. Référence : {block_reference}.',
    ),
    'merchant_restricted': ErrorEntry(
      _payment,
      false,
      'Payments are currently restricted for this merchant.',
      'Les paiements sont actuellement restreints pour ce marchand.',
    ),
    'payment_method_restricted': ErrorEntry(
      _payment,
      true,
      'This payment method is not available for this merchant.',
      "Ce moyen de paiement n'est pas disponible pour ce marchand.",
    ),
    'otp_attempts_exceeded': ErrorEntry(
      _payment,
      true,
      'Your operator refused too many codes for this payment. Choose another payment method.',
      'Votre opérateur a refusé trop de codes pour ce paiement. Choisissez un autre moyen de paiement.',
    ),
    'country_restricted': ErrorEntry(
      _payment,
      false,
      'This merchant does not accept payments from your country.',
      "Ce marchand n'accepte pas les paiements depuis votre pays.",
    ),
    'currency_restricted': ErrorEntry(
      _payment,
      false,
      'This merchant does not accept payments in this currency.',
      "Ce marchand n'accepte pas les paiements dans cette devise.",
    ),
    'channel_not_accepted': ErrorEntry(
      _payment,
      true,
      'This payment method is not available for this payment.',
      "Ce moyen de paiement n'est pas disponible pour ce paiement.",
    ),
    'payment_failed': ErrorEntry(
      _payment,
      false,
      'Your payment could not be processed.',
      "Votre paiement n'a pas pu être traité.",
    ),
    'payment_attempt_ended': ErrorEntry(
      _payment,
      true,
      'Your payment was not completed, and nothing was charged. Choose a payment method to try again.',
      "Votre paiement n'a pas abouti et rien n'a été débité. Choisissez un moyen de paiement pour réessayer.",
    ),
    'payment_cancelled': ErrorEntry(_payment, false, 'This payment was cancelled.', 'Ce paiement a été annulé.'),
    'session_expired': ErrorEntry(_invalid, false, 'This payment has expired.', 'Ce paiement a expiré.'),
    'not_processable': ErrorEntry(
      _invalid,
      false,
      'This payment can no longer be processed.',
      'Ce paiement ne peut plus être traité.',
    ),
    'payment_partly_paid': ErrorEntry(
      _invalid,
      false,
      "Part of this payment has already been paid, so it can't be cancelled.",
      'Une partie de ce paiement a déjà été réglée : il ne peut plus être annulé.',
    ),
    'order_not_validated': ErrorEntry(
      _invalid,
      false,
      'The merchant has not confirmed this order yet. Try again in a moment.',
      "Le marchand n'a pas encore confirmé cette commande. Réessayez dans un instant.",
    ),
    'raw_card_data_not_accepted': ErrorEntry(
      _invalid,
      false,
      "This payment method can't be used here.",
      'Ce moyen de paiement ne peut pas être utilisé ici.',
    ),
    'security_check_failed': ErrorEntry(
      _invalid,
      true,
      'The security check failed. Try again in a moment.',
      'La vérification de sécurité a échoué. Réessayez dans un instant.',
    ),
    'unsupported_action': ErrorEntry(
      _api,
      false,
      "This payment step isn't supported in the app. Try another payment method.",
      "Cette étape de paiement n'est pas prise en charge dans l'application. Essayez un autre moyen de paiement.",
    ),
    'redirect_unavailable': ErrorEntry(
      _api,
      true,
      "We couldn't open the payment page. Check that a web browser is enabled, then try again.",
      "Impossible d'ouvrir la page de paiement. Vérifiez qu'un navigateur est activé, puis réessayez.",
    ),
    // Confirmation steps.
    'invalid_otp':
        ErrorEntry(_invalid, true, 'Incorrect code. {n} attempts left.', 'Code incorrect. Encore {n} essais.'),
    'otp_expired': ErrorEntry(_invalid, true, 'The code has expired.', 'Le code a expiré.'),
    'invalid_pin': ErrorEntry(
      _invalid,
      true,
      'Incorrect PIN. {n} attempts left.',
      'Code PIN incorrect. Encore {n} essais.',
    ),
    'pin_expired': ErrorEntry(_invalid, true, _stepExpiredEn, _stepExpiredFr),
    'phone_expired': ErrorEntry(_invalid, true, _stepExpiredEn, _stepExpiredFr),
    'invalid_birthday': ErrorEntry(
      _invalid,
      true,
      'This date of birth was not accepted. {n} attempts left.',
      "Cette date de naissance n'a pas été acceptée. Encore {n} essais.",
    ),
    'birthday_expired': ErrorEntry(_invalid, true, _stepExpiredEn, _stepExpiredFr),
    'invalid_address': ErrorEntry(
      _invalid,
      true,
      'This address was not accepted. {n} attempts left.',
      "Cette adresse n'a pas été acceptée. Encore {n} essais.",
    ),
    'address_expired': ErrorEntry(_invalid, true, _stepExpiredEn, _stepExpiredFr),
    'max_attempts_exceeded': ErrorEntry(
      _payment,
      true,
      'Too many incorrect attempts.',
      'Trop de tentatives incorrectes.',
    ),
    'invalid_code': ErrorEntry(_invalid, true, 'Invalid verification code.', 'Code de vérification invalide.'),
    '3ds_failed': ErrorEntry(
      _payment,
      true,
      '3D Secure verification failed.',
      'La vérification 3D Secure a échoué.',
    ),
    '3ds_rejected': ErrorEntry(
      _payment,
      true,
      'Your bank declined the payment during 3D Secure.',
      'Votre banque a refusé le paiement lors du 3D Secure.',
    ),
    '3ds_cancelled': ErrorEntry(
      _payment,
      true,
      '3D Secure verification was cancelled.',
      'La vérification 3D Secure a été annulée.',
    ),
    '3ds_timeout': ErrorEntry(
      _payment,
      true,
      '3D Secure verification has expired.',
      'La vérification 3D Secure a expiré.',
    ),
    // Client sessions.
    'client_session_unavailable': ErrorEntry(
      _invalid,
      false,
      'Card payment is not available in test mode for this provider.',
      "Le paiement par carte n'est pas disponible en mode test pour ce prestataire.",
    ),
    'client_session_expired': ErrorEntry(
      _invalid,
      true,
      'This card payment session has expired. Start again.',
      'Cette session de paiement par carte a expiré. Recommencez.',
    ),
    // SDK use: developer-facing, English only.
    'sheet_already_presented': ErrorEntry(
      _invalid,
      false,
      'A Wajub payment sheet is already presented.',
      'A Wajub payment sheet is already presented.',
    ),
  };

  static ErrorEntry? lookup(String code) => entries[code];

  /// [entry]'s text in [language] (`fr` or `en`), its placeholders filled.
  /// A sentence whose placeholder has no value is left out ("{n} attempts
  /// left." without a count).
  static String text(ErrorEntry entry, String language, [Map<String, Object?> values = const {}]) {
    final template = language == 'fr' ? entry.fr : entry.en;
    final sentences = <String>[];
    for (final sentence in template.split(RegExp(r'(?<=\.) '))) {
      var filled = sentence;
      var complete = true;
      for (final match in RegExp(r'\{(\w+)\}').allMatches(sentence)) {
        final value = values[match.group(1)];
        if (value == null) {
          complete = false;
          break;
        }
        filled = filled.replaceAll(match.group(0)!, '$value');
      }
      if (complete) sentences.add(filled);
    }
    return sentences.join(' ');
  }
}
