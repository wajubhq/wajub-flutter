/// The payment sheet's words, in the two languages it speaks. Error texts
/// come from the error catalogue; these are the screens' own.
class SheetStrings {
  const SheetStrings._(this.language, this._texts);

  /// `fr` or `en`.
  final String language;
  final Map<String, String> _texts;

  String get title => _texts['title']!;
  String get chooseMethod => _texts['chooseMethod']!;
  String get amountToPay => _texts['amountToPay']!;
  String get testMode => _texts['testMode']!;
  String get securedBy => _texts['securedBy']!;
  String get close => _texts['close']!;
  String get retry => _texts['retry']!;
  String get tryAgain => _texts['tryAgain']!;
  String get cancelPayment => _texts['cancelPayment']!;
  String get back => _texts['back']!;
  String get mobileMoney => _texts['mobileMoney']!;
  String get card => _texts['card']!;
  String get loadErrorTitle => _texts['loadErrorTitle']!;
  String get country => _texts['country']!;
  String get operator => _texts['operator']!;
  String get mobileMoneyNumber => _texts['mobileMoneyNumber']!;
  String get changeOperator => _texts['changeOperator']!;
  String get processing => _texts['processing']!;
  String get walletHint => _texts['walletHint']!;
  String get approvalTitle => _texts['approvalTitle']!;
  String get instructions => _texts['instructions']!;
  String get waitingConfirmation => _texts['waitingConfirmation']!;
  String get ussdTitle => _texts['ussdTitle']!;
  String get verify => _texts['verify']!;
  String get resend => _texts['resend']!;
  String get threeDsTitle => _texts['threeDsTitle']!;
  String get threeDsBrowser => _texts['threeDsBrowser']!;
  String get pendingTitle => _texts['pendingTitle']!;
  String get pendingBrowser => _texts['pendingBrowser']!;
  String get pendingWaiting => _texts['pendingWaiting']!;
  String get continuePayment => _texts['continuePayment']!;
  String get capped => _texts['capped']!;
  String get successTitle => _texts['successTitle']!;
  String get receipt => _texts['receipt']!;
  String get failedTitle => _texts['failedTitle']!;
  String get expiredTitle => _texts['expiredTitle']!;
  String get cancelledTitle => _texts['cancelledTitle']!;
  String get endedTitle => _texts['endedTitle']!;
  String get sandboxCardHint => _texts['sandboxCardHint']!;
  String get hostedCardHint => _texts['hostedCardHint']!;
  String get cardUnavailable => _texts['cardUnavailable']!;

  String pay(String amount) => _fill('pay', {'amount': amount});
  String payWith(String name) => _fill('payWith', {'name': name});
  String minimum(String amount) => _fill('minimum', {'amount': amount});
  String maximum(String amount) => _fill('maximum', {'amount': amount});
  String approvalSentTo(String phone) => _fill('approvalSentTo', {'phone': phone});
  String codeSentTo(String contact) => _fill('codeSentTo', {'contact': contact});
  String resendIn(int seconds) => _fill('resendIn', {'seconds': '$seconds'});
  String expiresIn(String time) => _fill('expiresIn', {'time': time});
  String tryAgainIn(int seconds) => _fill('tryAgainIn', {'seconds': '$seconds'});
  String paidTo(String merchant) => _fill('paidTo', {'merchant': merchant});
  String reference(String reference) => _fill('reference', {'reference': reference});

  /// The title of a confirmation step: `otp`, `pin`, `phone`, `birthday`,
  /// `address`.
  String stepTitle(String step) => _texts['step.$step']!;

  /// A field's label, by its request key (`email`, `card.number`, `code`…).
  String field(String key) => _texts['field.$key'] ?? key;

  String _fill(String key, Map<String, String> values) =>
      values.entries.fold(_texts[key]!, (text, entry) => text.replaceAll('{${entry.key}}', entry.value));

  static const en = SheetStrings._('en', {
    'title': 'Pay with Wajub',
    'chooseMethod': 'Choose a payment method',
    'amountToPay': 'Amount to pay',
    'testMode': 'Test mode',
    'securedBy': 'Secured by Wajub',
    'close': 'Close',
    'retry': 'Retry',
    'tryAgain': 'Try again',
    'cancelPayment': 'Cancel payment',
    'back': 'Back',
    'mobileMoney': 'Mobile Money',
    'card': 'Card',
    'loadErrorTitle': "We couldn't load the payment",
    'country': 'Country',
    'operator': 'Operator',
    'mobileMoneyNumber': 'Mobile Money number',
    'changeOperator': 'Change',
    'processing': 'Processing…',
    'walletHint': 'You will approve the payment in the wallet app.',
    'approvalTitle': 'Approve the payment on your phone',
    'approvalSentTo': 'We sent a payment request to {phone}. Approve it to finish.',
    'instructions': 'Instructions',
    'waitingConfirmation': 'Waiting for confirmation…',
    'ussdTitle': 'Dial this code to pay',
    'verify': 'Confirm',
    'resend': 'Resend code',
    'resendIn': 'Resend in {seconds} s',
    'codeSentTo': 'Enter the code sent to {contact}.',
    'threeDsTitle': 'Verify your payment',
    'threeDsBrowser': 'Complete 3-D Secure in the page that opened, then come back here.',
    'expiresIn': 'Expires in {time}',
    'pendingTitle': 'Payment in progress',
    'pendingBrowser': 'Finish the payment in the page that opened, then come back here.',
    'pendingWaiting': 'We are waiting for the confirmation.',
    'continuePayment': 'Continue payment',
    'capped': 'Payment in progress — you will be notified.',
    'successTitle': 'Payment successful',
    'paidTo': 'Paid to {merchant}',
    'reference': 'Reference: {reference}',
    'receipt': 'View receipt',
    'failedTitle': 'Payment failed',
    'expiredTitle': 'This payment has expired',
    'cancelledTitle': 'Payment cancelled',
    'endedTitle': 'This payment has ended',
    'tryAgainIn': 'Try again in {seconds} s',
    'pay': 'Pay {amount}',
    'payWith': 'Pay with {name}',
    'minimum': 'Minimum {amount}',
    'maximum': 'Maximum {amount}',
    'sandboxCardHint': 'Test mode: use a test card, such as 4242 4242 4242 4242.',
    'hostedCardHint': 'You will enter your card on a secure payment page.',
    'cardUnavailable': 'Card payments unavailable for this session.',
    'step.otp': 'Enter the verification code',
    'step.pin': 'Enter your card PIN',
    'step.phone': 'Confirm your phone number',
    'step.birthday': 'Enter your date of birth',
    'step.address': 'Enter your billing address',
    'field.code': 'Code',
    'field.pin': 'PIN',
    'field.phone': 'Phone number',
    'field.birthday': 'Date of birth',
    'field.address': 'Address',
    'field.city': 'City',
    'field.state': 'State / region',
    'field.zip_code': 'Postal code',
    'field.first_name': 'First name',
    'field.last_name': 'Last name',
    'field.email': 'Email',
    'field.country': 'Country (2-letter code, e.g. CI)',
    'field.card.number': 'Card number',
    'field.card_holder': 'Cardholder name',
    'field.expiry_month': 'MM',
    'field.expiry_year': 'YY',
    'field.cvv': 'CVV',
  });

  static const fr = SheetStrings._('fr', {
    'title': 'Payer avec Wajub',
    'chooseMethod': 'Choisissez un moyen de paiement',
    'amountToPay': 'Montant à payer',
    'testMode': 'Mode test',
    'securedBy': 'Sécurisé par Wajub',
    'close': 'Fermer',
    'retry': 'Réessayer',
    'tryAgain': 'Réessayer',
    'cancelPayment': 'Annuler le paiement',
    'back': 'Retour',
    'mobileMoney': 'Mobile Money',
    'card': 'Carte bancaire',
    'loadErrorTitle': 'Impossible de charger le paiement',
    'country': 'Pays',
    'operator': 'Opérateur',
    'mobileMoneyNumber': 'Numéro Mobile Money',
    'changeOperator': 'Changer',
    'processing': 'Traitement…',
    'walletHint': "Vous validerez le paiement dans l'application du portefeuille.",
    'approvalTitle': 'Validez le paiement sur votre téléphone',
    'approvalSentTo': 'Une demande de paiement a été envoyée au {phone}. Validez-la pour terminer.',
    'instructions': 'Instructions',
    'waitingConfirmation': 'En attente de confirmation…',
    'ussdTitle': 'Composez ce code pour payer',
    'verify': 'Confirmer',
    'resend': 'Renvoyer le code',
    'resendIn': 'Renvoyer dans {seconds} s',
    'codeSentTo': 'Saisissez le code envoyé à {contact}.',
    'threeDsTitle': 'Vérifiez votre paiement',
    'threeDsBrowser': "Terminez le 3-D Secure dans la page qui s'est ouverte, puis revenez ici.",
    'expiresIn': 'Expire dans {time}',
    'pendingTitle': 'Paiement en cours',
    'pendingBrowser': "Terminez le paiement dans la page qui s'est ouverte, puis revenez ici.",
    'pendingWaiting': 'Nous attendons la confirmation.',
    'continuePayment': 'Continuer le paiement',
    'capped': 'Paiement en cours — vous serez notifié.',
    'successTitle': 'Paiement réussi',
    'paidTo': 'Payé à {merchant}',
    'reference': 'Référence : {reference}',
    'receipt': 'Voir le reçu',
    'failedTitle': 'Paiement échoué',
    'expiredTitle': 'Ce paiement a expiré',
    'cancelledTitle': 'Paiement annulé',
    'endedTitle': 'Ce paiement est terminé',
    'tryAgainIn': 'Réessayer dans {seconds} s',
    'pay': 'Payer {amount}',
    'payWith': 'Payer avec {name}',
    'minimum': 'Minimum {amount}',
    'maximum': 'Maximum {amount}',
    'sandboxCardHint': 'Mode test : utilisez une carte de test, par exemple 4242 4242 4242 4242.',
    'hostedCardHint': 'Vous saisirez votre carte sur une page de paiement sécurisée.',
    'cardUnavailable': 'Le paiement par carte est indisponible pour ce paiement.',
    'step.otp': 'Saisissez le code de vérification',
    'step.pin': 'Saisissez le code PIN de votre carte',
    'step.phone': 'Confirmez votre numéro de téléphone',
    'step.birthday': 'Saisissez votre date de naissance',
    'step.address': 'Saisissez votre adresse de facturation',
    'field.code': 'Code',
    'field.pin': 'Code PIN',
    'field.phone': 'Numéro de téléphone',
    'field.birthday': 'Date de naissance',
    'field.address': 'Adresse',
    'field.city': 'Ville',
    'field.state': 'État / région',
    'field.zip_code': 'Code postal',
    'field.first_name': 'Prénom',
    'field.last_name': 'Nom',
    'field.email': 'E-mail',
    'field.country': 'Pays (code à 2 lettres, ex. CI)',
    'field.card.number': 'Numéro de carte',
    'field.card_holder': 'Nom du titulaire',
    'field.expiry_month': 'MM',
    'field.expiry_year': 'AA',
    'field.cvv': 'CVV',
  });

  /// `fr`, `fr-CM`, `fr_CI` read French; anything else, or nothing, English.
  static SheetStrings forLocale(String? locale) => (locale ?? '').toLowerCase().startsWith('fr') ? fr : en;
}
