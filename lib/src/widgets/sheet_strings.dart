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

  /// The code screen's own words: `title`, `description`, `dial`, `copy`,
  /// `copied`, `amount`, `stepsTitle`, `codeLabel`, `submit`, `changeMethod`,
  /// `approval`, `refused`.
  String payerOtp(String key) => _texts['payerOtp.$key']!;

  /// The three steps shown when the operator's own are not known.
  List<String> payerOtpGenericSteps(String amount) => [
        _texts['payerOtp.generic1']!,
        _fill('payerOtp.generic2', {'amount': amount}),
        _texts['payerOtp.generic3']!,
      ];

  String payerOtpSandboxHint(String code) => _fill('payerOtp.sandboxHint', {'code': code});

  /// The Mobile Money form's line for a channel whose operator wants a code.
  String payerOtpFormHint(String? ussdCode) =>
      ussdCode == null ? _texts['payerOtp.formHintGeneric']! : _fill('payerOtp.formHint', {'ussd_code': ussdCode});

  String payerOtpAttempts(int count) => switch (count) {
        <= 0 => _texts['payerOtp.attempts0']!,
        1 => _texts['payerOtp.attempts1']!,
        _ => _fill('payerOtp.attemptsN', {'count': '$count'}),
      };

  /// The code's length: exactly [length] digits, else 4 to 8.
  String payerOtpLength(int? length) => length == null
      ? _fill('payerOtp.lengthRange', {'min': '4', 'max': '8'})
      : _fill('payerOtp.length', {'length': '$length'});

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
    'payerOtp.title': 'Generate your payment code',
    'payerOtp.description':
        'Before you pay, your operator asks for a code you generate yourself from its menu, for the '
            'exact amount of the payment.',
    'payerOtp.dial': 'Code to dial',
    'payerOtp.copy': 'Copy',
    'payerOtp.copied': 'Copied',
    'payerOtp.amount': 'Exact amount to enter',
    'payerOtp.stepsTitle': 'How to get your code',
    'payerOtp.generic1': "Open your operator's Mobile Money menu (USSD code or app).",
    'payerOtp.generic2': 'Generate a payment code for the exact amount: {amount}.',
    'payerOtp.generic3': 'Enter the code you received below.',
    'payerOtp.codeLabel': 'Payment code',
    'payerOtp.submit': 'Confirm payment',
    'payerOtp.changeMethod': 'Use another payment method',
    'payerOtp.sandboxHint': 'Test mode: enter the code {code}. Any other code is refused.',
    'payerOtp.approval': 'Code received. Your operator is processing the payment, this can take a moment.',
    'payerOtp.formHint': 'For this payment, you will generate a code by dialing {ussd_code}: the next step guides you.',
    'payerOtp.formHintGeneric':
        "For this payment, you will generate a code from your operator's menu: the next step guides you.",
    'payerOtp.attempts0': 'No tries left.',
    'payerOtp.attempts1': '1 try left.',
    'payerOtp.attemptsN': '{count} tries left.',
    'payerOtp.length': 'The code must have {length} digits.',
    'payerOtp.lengthRange': 'The code must have between {min} and {max} digits.',
    'payerOtp.refused': 'Your operator did not accept this code. Generate a new one and try again.',
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
    'payerOtp.title': 'Générez votre code de paiement',
    'payerOtp.description': 'Avant de payer, votre opérateur demande un code que vous générez vous-même depuis son '
        'menu, pour le montant exact du paiement.',
    'payerOtp.dial': 'Code à composer',
    'payerOtp.copy': 'Copier',
    'payerOtp.copied': 'Copié',
    'payerOtp.amount': 'Montant exact à saisir',
    'payerOtp.stepsTitle': 'Comment obtenir votre code',
    'payerOtp.generic1': 'Ouvrez le menu Mobile Money de votre opérateur (code USSD ou application).',
    'payerOtp.generic2': 'Générez un code de paiement pour le montant exact : {amount}.',
    'payerOtp.generic3': 'Saisissez ci-dessous le code que vous avez reçu.',
    'payerOtp.codeLabel': 'Code de paiement',
    'payerOtp.submit': 'Valider le paiement',
    'payerOtp.changeMethod': 'Changer de moyen de paiement',
    'payerOtp.sandboxHint': 'Mode test : saisissez le code {code}. Tout autre code est refusé.',
    'payerOtp.approval': 'Code reçu. Votre opérateur traite le paiement, cela peut prendre quelques instants.',
    'payerOtp.formHint':
        "Pour ce paiement, vous générerez un code en composant {ussd_code} : l'étape suivante vous guide.",
    'payerOtp.formHintGeneric':
        "Pour ce paiement, vous générerez un code depuis le menu de votre opérateur : l'étape suivante vous guide.",
    'payerOtp.attempts0': 'Plus aucun essai possible.',
    'payerOtp.attempts1': 'Il vous reste 1 essai.',
    'payerOtp.attemptsN': 'Il vous reste {count} essais.',
    'payerOtp.length': 'Le code doit comporter {length} chiffres.',
    'payerOtp.lengthRange': 'Le code doit comporter entre {min} et {max} chiffres.',
    'payerOtp.refused': "Votre opérateur n'a pas accepté ce code. Générez-en un nouveau et réessayez.",
  });

  /// `fr`, `fr-CM`, `fr_CI` read French; anything else, or nothing, English.
  static SheetStrings forLocale(String? locale) => (locale ?? '').toLowerCase().startsWith('fr') ? fr : en;
}
