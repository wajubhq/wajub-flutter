/// The values of `SdkChannelConfig.sdk` the SDK acts on: a form it draws,
/// Stripe's card field, or the provider's own page. Any other value hides
/// the method.
abstract final class SdkFlavor {
  static const form = 'form';
  static const stripeElements = 'stripe_elements';
  static const hostedRedirect = 'hosted_redirect';
}
