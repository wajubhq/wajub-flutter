import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../adapters/hosted_redirect.dart';
import '../appearance/appearance_resolver.dart';
import '../appearance/wajub_theme.dart';
import '../checkout/checkout_controller.dart';
import '../checkout/checkout_methods.dart';
import '../checkout/checkout_types.dart';
import '../checkout/present_options.dart';
import 'checkout_forms.dart';
import 'network_logo.dart';
import 'sheet_strings.dart';

/// The payment sheet's content for a [CheckoutController]: the merchant's
/// header, the amount, the screen of the moment and "Secured by Wajub", in
/// the resolved appearance. It loads the payment when it first shows, and
/// owns the controller from then on: when it goes away without an outcome,
/// the payment settles as the host going away.
class WajubCheckoutView extends StatefulWidget {
  const WajubCheckoutView({super.key, required this.controller, required this.onDismissRequested});

  final CheckoutController controller;

  /// The close button: the payer leaves.
  final VoidCallback onDismissRequested;

  @override
  State<WajubCheckoutView> createState() => _WajubCheckoutViewState();
}

class _WajubCheckoutViewState extends State<WajubCheckoutView> with WidgetsBindingObserver {
  CheckoutController get _controller => widget.controller;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_changed);
    unawaited(_controller.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _controller.onAppPaused();
      case AppLifecycleState.resumed:
        // Back from the browser, a wallet app or the approval prompt.
        unawaited(_controller.onAppResumed());
      default:
        break;
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _syncTicker();
  }

  /// Countdowns (resend, the 3-D Secure code, a rate limit) redraw every
  /// second while one runs.
  void _syncTicker() {
    final now = clock.now();
    bool future(DateTime? at) => at != null && at.isAfter(now);
    final counting = (_controller.screen == CheckoutScreen.step && future(_controller.resendAt)) ||
        (_controller.screen == CheckoutScreen.threeDs &&
            (future(_controller.resendAt) || future(_controller.threeDsDeadline))) ||
        (_controller.screen == CheckoutScreen.failed && future(_controller.retryAt));
    if (!counting) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.hostGone();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final session = controller.sessionData;
    final theme = AppearanceResolver.resolve(
      appearance: controller.options.appearance,
      branding: session?.merchantBranding,
      platformBrightness: MediaQuery.platformBrightnessOf(context),
      hostTheme: Theme.of(context),
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    final strings = SheetStrings.forLocale(controller.language);
    final colors = theme.colors;
    final unit = theme.spacingUnit;
    final branding = session?.merchantBranding;
    final showSummary = session != null &&
        controller.screen != CheckoutScreen.loading &&
        controller.screen != CheckoutScreen.loadError &&
        controller.screen != CheckoutScreen.success;

    return WajubTheme(
      data: theme,
      child: Theme(
        data: AppearanceResolver.materialTheme(theme),
        child: Builder(
          builder: (context) => DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                if (theme.elevation > 0)
                  BoxShadow(
                      color: const Color(0x33000000), blurRadius: theme.elevation * 4, offset: const Offset(0, -1)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The handle and the header stay out of the scrolling part:
                  // a swipe down on them drags the sheet away.
                  Padding(
                    padding: EdgeInsets.fromLTRB(unit * 5, unit * 2, unit * 5, unit * 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            key: const ValueKey('wajub-drag-handle'),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.borderStrong,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        SizedBox(height: unit * 2),
                        _Header(controller: controller, strings: strings, onClose: widget.onDismissRequested),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        unit * 5,
                        0,
                        unit * 5,
                        unit * 4 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSummary) ...[
                            _Summary(controller: controller, strings: strings),
                            SizedBox(height: unit * 5),
                          ],
                          AnimatedSwitcher(
                            duration: theme.disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [...previous, if (current != null) current],
                            ),
                            child: KeyedSubtree(
                              key: ValueKey('${controller.screen.name}-${controller.method?.family.name}'),
                              child: _screen(controller, strings),
                            ),
                          ),
                          if (branding?.whiteLabel != true) ...[
                            SizedBox(height: unit * 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_outline, size: theme.fontSizeHint, color: colors.textPlaceholder),
                                SizedBox(width: unit),
                                Text(
                                  strings.securedBy,
                                  style: TextStyle(color: colors.textPlaceholder, fontSize: theme.fontSizeHint),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _screen(CheckoutController controller, SheetStrings strings) => switch (controller.screen) {
        CheckoutScreen.loading => _Loader(loader: controller.options.loader),
        CheckoutScreen.loadError => _LoadError(controller: controller, strings: strings),
        CheckoutScreen.methods => _MethodList(controller: controller, strings: strings),
        CheckoutScreen.form => CheckoutForm(controller: controller, strings: strings),
        CheckoutScreen.approval => _Waiting(controller: controller, strings: strings, ussd: false),
        CheckoutScreen.ussd => _Waiting(controller: controller, strings: strings, ussd: true),
        CheckoutScreen.step => StepForm(controller: controller, strings: strings),
        CheckoutScreen.threeDs => ThreeDsForm(controller: controller, strings: strings),
        CheckoutScreen.pending => _Pending(controller: controller, strings: strings),
        CheckoutScreen.success => _Success(controller: controller, strings: strings),
        CheckoutScreen.failed => _Failure(controller: controller, strings: strings),
      };
}

/// The merchant's logo (at most 40 high) or name, and the close button.
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.strings, required this.onClose});

  final CheckoutController controller;
  final SheetStrings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final branding = controller.sessionData?.merchantBranding;
    final name = Text(
      branding?.businessName ?? strings.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.colors.text,
        fontSize: theme.fontSizeBase * 1.125,
        fontWeight: theme.fontWeightBold,
      ),
    );
    final logo = branding?.logo;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: logo == null
                ? name
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 40, maxWidth: 160),
                    child: NetworkLogo(url: logo, width: 160, height: 40, fallback: name),
                  ),
          ),
        ),
        IconButton(
          key: const ValueKey('wajub-dismiss'),
          tooltip: strings.close,
          onPressed: controller.cancelling ? null : onClose,
          icon: Icon(Icons.close, color: theme.colors.textSecondary),
        ),
      ],
    );
  }
}

/// The amount to pay, and the test-mode flag.
class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final transaction = controller.sessionData!.transaction;
    return Container(
      padding: EdgeInsets.all(theme.spacingUnit * 4),
      decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(theme.radius)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.amountToPay, style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel)),
                SizedBox(height: theme.spacingUnit),
                Text(
                  formatAmount(transaction.payableAmount, transaction.currency, controller.language),
                  key: const ValueKey('wajub-amount'),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: theme.fontSizeBase * 1.5,
                    fontWeight: theme.fontWeightBold,
                  ),
                ),
                if (transaction.description != null) ...[
                  SizedBox(height: theme.spacingUnit),
                  Text(
                    transaction.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeHint),
                  ),
                ],
              ],
            ),
          ),
          if (transaction.sandbox)
            Container(
              padding: EdgeInsets.symmetric(horizontal: theme.spacingUnit * 2, vertical: theme.spacingUnit),
              decoration: BoxDecoration(
                color: colors.warningBackground,
                borderRadius: BorderRadius.circular(theme.radius),
              ),
              child: Text(
                strings.testMode,
                style:
                    TextStyle(color: colors.warning, fontSize: theme.fontSizeHint, fontWeight: theme.fontWeightMedium),
              ),
            ),
        ],
      ),
    );
  }
}

/// The skeleton (placeholder blocks, pulsing unless animations are off) or
/// the spinner.
class _Loader extends StatefulWidget {
  const _Loader({required this.loader});

  final WajubLoader loader;

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WajubTheme.of(context).disableAnimations || widget.loader == WajubLoader.spinner) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    if (widget.loader == WajubLoader.spinner) {
      return Padding(
        key: const ValueKey('wajub-spinner'),
        padding: EdgeInsets.symmetric(vertical: theme.spacingUnit * 12),
        child: Center(child: CircularProgressIndicator(color: theme.colors.primary)),
      );
    }
    final colors = theme.colors;
    final radius = BorderRadius.circular(theme.radius);
    Widget block(double height, {Color? color, bool outlined = false}) => Container(
          height: height,
          decoration: BoxDecoration(
            color: color ?? colors.inputBackground,
            borderRadius: radius,
            border: outlined ? Border.all(color: colors.inputBorder) : null,
          ),
        );
    return FadeTransition(
      key: const ValueKey('wajub-skeleton'),
      opacity: Tween<double>(begin: 0.55, end: 1).animate(_pulse),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(76, color: colors.surfaceMuted),
          SizedBox(height: theme.spacingUnit * 5),
          for (var i = 0; i < 3; i++) ...[
            block(56, outlined: true),
            SizedBox(height: theme.spacingUnit * 3),
          ],
          SizedBox(height: theme.spacingUnit * 2),
          block(48, color: colors.surfaceMuted),
        ],
      ),
    );
  }
}

/// A big round icon above a title and a text: every outcome screen.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    this.message,
    this.children = const [],
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final unit = theme.spacingUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32),
          ),
        ),
        SizedBox(height: unit * 4),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.colors.text,
            fontSize: theme.fontSizeBase * 1.25,
            fontWeight: theme.fontWeightBold,
          ),
        ),
        if (message != null) ...[
          SizedBox(height: unit * 2),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colors.textSecondary, fontSize: theme.fontSizeBase),
          ),
        ],
        if (children.isNotEmpty) SizedBox(height: unit * 6),
        ...children,
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final error = controller.error!;
    final connection = error.code == 'load_error' || error.code == 'ready_timeout';
    return _Notice(
      icon: Icons.error_outline,
      color: theme.colors.danger,
      background: theme.colors.dangerBackground,
      title: connection ? strings.loadErrorTitle : error.message,
      message: connection ? error.message : null,
      children: [
        if (error.retryable) ...[
          FilledButton(key: const ValueKey('wajub-retry'), onPressed: controller.retryLoad, child: Text(strings.retry)),
          SizedBox(height: theme.spacingUnit * 3),
        ],
        OutlinedButton(key: const ValueKey('wajub-close'), onPressed: controller.close, child: Text(strings.close)),
      ],
    );
  }
}

class _MethodList extends StatelessWidget {
  const _MethodList({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final unit = theme.spacingUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.chooseMethod,
          style: TextStyle(color: colors.text, fontSize: theme.fontSizeBase, fontWeight: theme.fontWeightBold),
        ),
        SizedBox(height: unit * 3),
        for (final method in controller.methods) ...[
          _MethodTile(method: method, controller: controller, strings: strings),
          SizedBox(height: unit * 2),
        ],
        if (controller.canCancel) ...[
          SizedBox(height: unit * 2),
          CancelPaymentButton(controller: controller, strings: strings),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.controller, required this.strings});

  final CheckoutMethod method;
  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final language = controller.language;
    final name = method.family == MethodFamily.mobileMoney
        ? strings.mobileMoney
        : method.channels.isEmpty
            ? strings.card
            : method.channel.localizedName(language);
    final limit = method.limit;
    final limitText = limit == null
        ? null
        : (limit.minimum ? strings.minimum : strings.maximum)(formatAmount(limit.amount, limit.currency, language));
    final logo = method.channels.isEmpty ? null : method.channel.logo;
    final icon = Icon(
      switch (method.family) {
        MethodFamily.mobileMoney => Icons.phone_iphone,
        MethodFamily.card => Icons.credit_card,
        MethodFamily.wallet => Icons.account_balance_wallet_outlined,
      },
      color: colors.textSecondary,
    );
    // Mobile Money folds several channels: its tile goes by the family.
    final slug = method.family == MethodFamily.mobileMoney || method.channels.isEmpty
        ? method.family.wireName
        : method.channel.slug;
    return Opacity(
      opacity: method.enabled ? 1 : theme.disabledOpacity,
      child: Material(
        color: colors.inputBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radius),
          side: BorderSide(color: colors.inputBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('wajub-method-$slug'),
          onTap: method.enabled ? () => controller.selectMethod(method) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: theme.spacingUnit * 4, vertical: theme.spacingUnit * 3),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 32,
                  child: logo == null ? icon : NetworkLogo(url: logo, width: 32, height: 32, fallback: icon),
                ),
                SizedBox(width: theme.spacingUnit * 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: theme.fontSizeBase,
                          fontWeight: theme.fontWeightMedium,
                        ),
                      ),
                      if (limitText != null)
                        Text(limitText, style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeHint)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textPlaceholder),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Approval on the phone, or the USSD code to dial.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.controller, required this.strings, required this.ussd});

  final CheckoutController controller;
  final SheetStrings strings;
  final bool ussd;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final unit = theme.spacingUnit;
    final instruction = controller.instruction;
    final phone = controller.approvalPhone;
    // The API's instruction is English: a French sheet shows it as such,
    // under a label, and its own sentence first.
    final englishOnly = controller.language == 'fr' || ussd;
    return _Notice(
      icon: ussd ? Icons.dialpad : Icons.phone_iphone,
      color: colors.primary,
      background: colors.selectedBackground,
      title: ussd ? strings.ussdTitle : strings.approvalTitle,
      message: ussd ? null : (phone != null ? strings.approvalSentTo(phone) : null),
      children: [
        if (instruction != null) ...[
          Container(
            key: const ValueKey('wajub-instruction'),
            padding: EdgeInsets.all(unit * 4),
            decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(theme.radius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (englishOnly)
                  Text(
                    strings.instructions,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: theme.fontSizeHint,
                      fontWeight: theme.fontWeightMedium,
                    ),
                  ),
                if (englishOnly) SizedBox(height: unit),
                Text(instruction, style: TextStyle(color: colors.text, fontSize: theme.fontSizeBase)),
              ],
            ),
          ),
          SizedBox(height: unit * 5),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary)),
            SizedBox(width: unit * 3),
            Text(strings.waitingConfirmation,
                style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel)),
          ],
        ),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final threeDs = controller.state == CheckoutState.threeDsRequired;
    final url = controller.continueUrl;
    return _Notice(
      icon: threeDs ? Icons.verified_user_outlined : Icons.hourglass_top,
      color: colors.primary,
      background: colors.selectedBackground,
      title: threeDs ? strings.threeDsTitle : strings.pendingTitle,
      message: controller.capped
          ? strings.capped
          : threeDs
              ? strings.threeDsBrowser
              : url != null
                  ? strings.pendingBrowser
                  : strings.pendingWaiting,
      children: [
        if (!controller.capped) ...[
          Center(child: CircularProgressIndicator(color: colors.primary)),
          if (url != null) SizedBox(height: theme.spacingUnit * 6),
        ],
        if (url != null && !controller.capped)
          FilledButton(
            key: const ValueKey('wajub-continue'),
            onPressed: controller.continuePayment,
            child: Text(strings.continuePayment),
          ),
        if (controller.capped)
          OutlinedButton(key: const ValueKey('wajub-close'), onPressed: controller.close, child: Text(strings.close)),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final payment = controller.payment!;
    final merchant = controller.sessionData?.merchantBranding.businessName;
    final receipt = payment.receiptUrl;
    return _Notice(
      icon: Icons.check,
      color: colors.success,
      background: colors.successBackground,
      title: strings.successTitle,
      message: formatAmount(payment.amount, payment.currency, controller.language),
      children: [
        if (merchant != null)
          Text(
            strings.paidTo(merchant),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel),
          ),
        if (payment.reference != null) ...[
          SizedBox(height: theme.spacingUnit),
          Text(
            strings.reference(payment.reference!),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: theme.fontSizeLabel),
          ),
        ],
        if (receipt != null)
          TextButton(
            key: const ValueKey('wajub-receipt'),
            onPressed: () => unawaited(HostedRedirect.open(receipt).then((_) {}, onError: (Object _) {})),
            child: Text(strings.receipt),
          ),
        SizedBox(height: theme.spacingUnit * 4),
        FilledButton(key: const ValueKey('wajub-close'), onPressed: controller.close, child: Text(strings.close)),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.controller, required this.strings});

  final CheckoutController controller;
  final SheetStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = WajubTheme.of(context);
    final colors = theme.colors;
    final error = controller.error;
    final title = controller.endedAtLoad
        ? strings.endedTitle
        : switch (controller.state) {
            CheckoutState.expired => strings.expiredTitle,
            CheckoutState.cancelled => strings.cancelledTitle,
            _ => strings.failedTitle,
          };
    final retryAt = controller.retryAt;
    final wait = retryAt == null ? 0 : (retryAt.difference(clock.now()).inMilliseconds / 1000).ceil();
    final canRetry = (error?.retryable ?? false) && !controller.endedAtLoad;
    return _Notice(
      icon: controller.state == CheckoutState.expired ? Icons.timer_off_outlined : Icons.error_outline,
      color: colors.danger,
      background: colors.dangerBackground,
      title: title,
      message: error?.message,
      children: [
        if (canRetry) ...[
          FilledButton(
            key: const ValueKey('wajub-try-again'),
            onPressed: wait > 0 ? null : controller.tryAgain,
            child: Text(wait > 0 ? strings.tryAgainIn(wait) : strings.tryAgain),
          ),
          SizedBox(height: theme.spacingUnit * 3),
        ],
        OutlinedButton(key: const ValueKey('wajub-close'), onPressed: controller.close, child: Text(strings.close)),
        if (controller.canCancel) ...[
          SizedBox(height: theme.spacingUnit * 2),
          CancelPaymentButton(controller: controller, strings: strings),
        ],
      ],
    );
  }
}
