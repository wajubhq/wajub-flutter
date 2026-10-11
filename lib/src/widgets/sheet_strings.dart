/// The payment sheet's words, in the languages it speaks. The language is the
/// one [showWajubPaymentSheet] asks for, else the payment's own (`locale` on
/// the session), else English.
class SheetStrings {
  const SheetStrings({
    required this.title,
    required this.mobileMoney,
    required this.card,
    required this.wallet,
    required this.phoneNumber,
    required this.payNow,
    required this.payByCard,
    required this.payWithCard,
    required this.payWithPrefix,
    required this.processing,
    required this.walletHint,
    required this.emailForReceipt,
    required this.cardholderName,
    required this.noMobileMoney,
    required this.noCardChannel,
    required this.cardUnavailable,
    required this.loadFailed,
    required this.couldNotOpenPage,
    required this.fields,
  });

  final String title;
  final String mobileMoney;
  final String card;
  final String wallet;
  final String phoneNumber;
  final String payNow;
  final String payByCard;
  final String payWithCard;
  final String payWithPrefix;
  final String processing;
  final String walletHint;
  final String emailForReceipt;
  final String cardholderName;
  final String noMobileMoney;
  final String noCardChannel;
  final String cardUnavailable;
  final String loadFailed;
  final String couldNotOpenPage;
  final Map<String, String> fields;

  String payWith(String name) => '$payWithPrefix $name';

  static const en = SheetStrings(
    title: 'Pay with Wajub',
    mobileMoney: 'Mobile Money',
    card: 'Card',
    wallet: 'Wallet',
    phoneNumber: 'Phone number',
    payNow: 'Pay now',
    payByCard: 'Pay by card',
    payWithCard: 'Pay with card',
    payWithPrefix: 'Pay with',
    processing: 'Processing…',
    walletHint: 'You will approve the payment in the wallet app.',
    emailForReceipt: 'Email (for your receipt)',
    cardholderName: 'Cardholder name',
    noMobileMoney: 'No Mobile Money channels available.',
    noCardChannel: 'No card channel available.',
    cardUnavailable: 'Card payments unavailable for this session.',
    loadFailed: 'Failed to load session',
    couldNotOpenPage: 'Could not open the payment page.',
    fields: {
      'first_name': 'First name',
      'last_name': 'Last name',
      'email': 'Email',
      'phone': 'Phone number',
      'address': 'Address',
      'city': 'City',
      'country': 'Country (2-letter code, e.g. CI)',
      'state': 'State / region',
      'zip_code': 'Postal code',
    },
  );

  static const fr = SheetStrings(
    title: 'Payer avec Wajub',
    mobileMoney: 'Mobile Money',
    card: 'Carte',
    wallet: 'Portefeuille',
    phoneNumber: 'Numéro de téléphone',
    payNow: 'Payer',
    payByCard: 'Payer par carte',
    payWithCard: 'Payer par carte',
    payWithPrefix: 'Payer avec',
    processing: 'Traitement…',
    walletHint: "Vous validerez le paiement dans l'application du portefeuille.",
    emailForReceipt: 'E-mail (pour votre reçu)',
    cardholderName: 'Nom du titulaire de la carte',
    noMobileMoney: 'Aucun moyen Mobile Money disponible.',
    noCardChannel: 'Aucun moyen de paiement par carte disponible.',
    cardUnavailable: 'Le paiement par carte est indisponible pour ce paiement.',
    loadFailed: "Le paiement n'a pas pu être chargé",
    couldNotOpenPage: "La page de paiement n'a pas pu s'ouvrir.",
    fields: {
      'first_name': 'Prénom',
      'last_name': 'Nom',
      'email': 'E-mail',
      'phone': 'Numéro de téléphone',
      'address': 'Adresse',
      'city': 'Ville',
      'country': 'Pays (code à 2 lettres, ex. CI)',
      'state': 'État / région',
      'zip_code': 'Code postal',
    },
  );

  /// `fr`, `fr-CM`, `fr_CI` read French; anything else, or nothing, English.
  static SheetStrings forLocale(String? locale) =>
      (locale ?? '').toLowerCase().startsWith('fr') ? fr : en;
}
