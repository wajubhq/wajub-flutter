import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../adapters/hosted_redirect.dart';
import '../adapters/stripe_adapter.dart';
import '../client/ids.dart';
import '../errors/error_catalogue.dart';
import '../mapper/payment_mapper.dart';
import '../mobile_money/mobile_money_data.dart';
import '../mobile_money/mobile_money_rules.dart';
import '../mobile_money/operator_choice.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';
import '../realtime/payment_watcher.dart';
import '../realtime/pusher_socket.dart';
import '../wajub_session.dart';
import 'altcha.dart';
import 'checkout_methods.dart';
import 'checkout_types.dart';
import 'present_options.dart';

/// What the sheet draws.
enum CheckoutScreen {
  /// The skeleton or spinner.
  loading,

  /// The payment could not be offered: [CheckoutController.error], Retry
  /// when it is retryable.
  loadError,

  /// The method list (`INITIATED`).
  methods,

  /// A method's form (`COLLECTING_DETAILS`, `PROCESSING` while it submits).
  form,

  /// "Approve on your phone" (`APPROVAL_REQUIRED`).
  approval,

  /// "Dial this code" (`USSD_REQUIRED`).
  ussd,

  /// OTP, PIN, phone, date of birth or address (`*_REQUIRED`, `VERIFYING`).
  step,

  /// The sandbox 3-D Secure email code (`3DS_REQUIRED`, `VERIFYING`).
  threeDs,

  /// "Payment in progress" (`PENDING`, or `3DS_REQUIRED` in the browser).
  pending,

  /// `SUCCESS`.
  success,

  /// `FAILED`, `EXPIRED`, `CANCELLED`: [CheckoutController.error], Try again
  /// when it is retryable.
  failed,
}

/// The checkout's state machine (spec states.md): loads the session, offers
/// the methods, submits, follows the payment, and reports through the
/// [CheckoutCallbacks] until [result] settles, exactly once. The payment
/// sheet draws it; it holds no widget.
class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required this.session,
    required this.options,
    Future<bool> Function(String url)? openUrl,
    Future<MobileMoneyData> Function()? mobileMoneyData,
    Future<int?> Function(AltchaChallenge challenge)? altchaSolver,
    RealtimeConnector? realtimeConnector,
    String? deviceLanguage,
    Future<String> Function(String publishableKey, String? cardholderName)? stripePaymentMethod,
    @visibleForTesting Stopwatch Function()? stopwatch,
    @visibleForTesting Future<void> Function(String appPublishableKey)? restoreStripeKey,
  })  : _attemptClock = (stopwatch ?? Stopwatch.new)(),
        _restoreStripeKey = restoreStripeKey ?? StripeAdapter.restore,
        _openUrl = openUrl ?? HostedRedirect.open,
        _loadMobileMoneyData = mobileMoneyData ?? MobileMoneyData.load,
        _solveAltcha = altchaSolver ?? _solveInBackground,
        _realtimeConnector = realtimeConnector,
        _deviceLanguage = deviceLanguage ?? PlatformDispatcher.instance.locale.languageCode,
        _stripePaymentMethod = stripePaymentMethod ?? _stripeElements;

  final WajubSession session;
  final PresentOptions options;
  final Future<bool> Function(String url) _openUrl;
  final Future<MobileMoneyData> Function() _loadMobileMoneyData;
  final Future<int?> Function(AltchaChallenge challenge) _solveAltcha;
  final RealtimeConnector? _realtimeConnector;
  final String _deviceLanguage;

  /// Stripe's native card field turned into a `pm_…`.
  final Future<String> Function(String publishableKey, String? cardholderName) _stripePaymentMethod;

  /// Puts the app's own Stripe key back ([StripeOptions]).
  final Future<void> Function(String appPublishableKey) _restoreStripeKey;

  /// The card form set the merchant's Stripe key.
  var _stripeKeySet = false;

  /// Monotonic time since the attempt under way began (the press of Pay, or
  /// the sheet opening on a payment already processing): the watch ends 15
  /// minutes after it (README §13.2).
  final Stopwatch _attemptClock;

  CheckoutCallbacks get _callbacks => options.callbacks;

  /// Called when the sheet must close (an outcome, Cancel payment, Close).
  VoidCallback? onClose;

  /// Called when the payer submits a payment, before any answer: the 1.5
  /// `PaymentSheet.onPaymentStarted`.
  VoidCallback? onSubmit;

  /// 1.5's rule for `showWajubPaymentSheet`: closing the sheet cancels the
  /// payment only if nothing was ever submitted.
  bool cancelOnlyBeforeSubmit = false;
  var _submitted = false;

  /// Called first when the sheet settles, before the route closes and the
  /// callbacks run: the presenter frees itself, so `onComplete` may present
  /// the next sheet.
  VoidCallback? onSettling;

  static Future<String> _stripeElements(String publishableKey, String? cardholderName) async {
    await StripeAdapter.ensureInitialized(publishableKey);
    return StripeAdapter.createPaymentMethod(cardholderName: cardholderName);
  }

  // ── What the sheet draws ─────────────────────────────────────────────────

  CheckoutScreen _screen = CheckoutScreen.loading;
  CheckoutScreen get screen => _screen;

  CheckoutState? _state;

  /// The last state reported to `onStateChange`.
  CheckoutState? get state => _state;

  SessionData? _session;
  SessionData? get sessionData => _session;
  SdkConfig? _sdkConfig;
  MobileMoneyData? _mobileMoneyData;
  MobileMoneyData? get mobileMoneyData => _mobileMoneyData;

  List<CheckoutMethod> _methods = const [];
  List<CheckoutMethod> get methods => _methods;
  CheckoutMethod? _method;

  /// The method being paid.
  CheckoutMethod? get method => _method;

  /// The sheet's language: `fr` or `en`.
  String get language =>
      _reduce(options.locale) ?? _reduce(_session?.sessionLocale) ?? _reduce(_deviceLanguage) ?? 'en';

  bool _busy = false;

  /// A submission is on its way (`PROCESSING`, `VERIFYING`).
  bool get busy => _busy;

  WajubError? _error;

  /// The load error, or the failure the failure screen shows.
  WajubError? get error => _error;

  /// The payment had already ended when the sheet opened.
  bool _endedAtLoad = false;
  bool get endedAtLoad => _endedAtLoad;

  String? _banner;

  /// A refusal shown above a form, tied to no field.
  String? get banner => _banner;

  Map<String, String> _fieldErrors = const {};

  /// Field → message, under the request's keys (`data.phone`, `email`,
  /// `code`…).
  Map<String, String> get fieldErrors => _fieldErrors;

  /// `processing_context.payer_instruction` (English), on the approval and
  /// USSD screens.
  String? _instruction;
  String? get instruction => _instruction;

  /// The number the approval was sent to.
  String? _approvalPhone;
  String? get approvalPhone => _approvalPhone;

  /// The page "Continue payment" reopens.
  String? _continueUrl;
  String? get continueUrl => _continueUrl;

  /// The watch ran out of time: "you will be notified".
  bool _capped = false;
  bool get capped => _capped;

  PaymentSuccess? _payment;
  PaymentSuccess? get payment => _payment;

  /// A 429: when the payer may try again.
  DateTime? _retryAt;
  DateTime? get retryAt => _retryAt;

  // ── Mobile Money form ────────────────────────────────────────────────────

  List<String> _countries = const [];
  List<String> get countries => _countries;
  String? _country;
  String? get country => _country;
  List<OperatorChoice> _choices = const [];
  List<OperatorChoice> get choices => _choices;
  String? _selectedId;
  String? get selectedOperatorId => _selectedId;
  bool _pickedByHand = false;
  bool _listOpened = false;
  String _phone = '';
  String get phone => _phone;

  /// The operator the number belongs to, among the choices or not.
  String? get detectedOperatorId => _country == null ? null : _mobileMoneyData?.detectOperator(_phone, _country!);

  /// Hide the country selector.
  bool get countryLocked =>
      _countries.length <= 1 || (options.mobileMoney.countryLocked && _countries.contains(_requestedCountry));

  String? get _requestedCountry => options.mobileMoney.country?.toUpperCase();

  /// In `detect` mode the operator list waits for the number.
  bool get showOperatorList {
    final data = _mobileMoneyData;
    if (data == null || _country == null) return true;
    return MobileMoneyRules.showOperatorList(
      data: data,
      operatorMode: options.mobileMoney.operatorMode.name,
      phone: _phone,
      country: _country!,
      choiceIds: [for (final choice in _choices) choice.id],
      openedByPayer: _listOpened,
    );
  }

  /// The operator shown inside the field while the list is hidden.
  OperatorChoice? get badgeOperator {
    final data = _mobileMoneyData;
    if (data == null || _country == null) return null;
    final id = MobileMoneyRules.fieldBadge(
      data: data,
      phone: _phone,
      country: _country!,
      choiceIds: [for (final choice in _choices) choice.id],
    );
    return _choices.where((choice) => choice.id == id).firstOrNull;
  }

  /// In sandbox, a mismatch only warns: its message, or null.
  String? get mismatchWarning {
    if (!(_session?.transaction.sandbox ?? false)) return null;
    final detected = _mismatch();
    return detected == null ? null : _mismatchMessage(detected);
  }

  // ── Card form ────────────────────────────────────────────────────────────

  final Map<String, String> _cardFields = {};

  /// Card: the fields typed so far, by request key.
  Map<String, String> get cardFields => _cardFields;

  /// The contact or billing fields the card flavour asks for.
  List<String> get cardRequiredFields => switch (_method?.cardFlavour) {
        CardFlavour.hostedRedirect || CardFlavour.clientSession => hostedCardRequiredFields(_method?.config),
        CardFlavour.sandboxForm => const ['card.number', 'card_holder', 'expiry_month', 'expiry_year', 'cvv'],
        _ => const [],
      };

  // ── Confirmation steps ───────────────────────────────────────────────────

  PaymentStepKind? _stepKind;
  PaymentStepKind? get stepKind => _stepKind;
  String? _stepId;
  String? _stepHint;

  /// `otp_masked_contact` or the step's instruction (English), or the masked
  /// email of the 3-D Secure code.
  String? get stepHint => _stepHint;

  /// The processing id the step's verify sends (`otp_id`…).
  String? get stepId => _stepId;
  int? _attemptsRemaining;
  int? get attemptsRemaining => _attemptsRemaining;
  DateTime? _resendAt;

  /// When "Resend" becomes available.
  DateTime? get resendAt => _resendAt;
  DateTime? _threeDsDeadline;

  /// When the sandbox 3-D Secure code expires.
  DateTime? get threeDsDeadline => _threeDsDeadline;
  Timer? _threeDsTimer;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  final _result = Completer<CheckoutResult>();

  /// Settles exactly once, when the sheet closes.
  Future<CheckoutResult> get result => _result.future;
  bool get settled => _settling || _result.isCompleted;

  /// [_finish] began: nothing settles twice, even from a callback.
  var _settling = false;

  var _generation = 0;

  /// Bumped by each submission and each outcome: an answer that comes back
  /// for an older one is dropped (a verify, a complete or a status read the
  /// watcher already beat, an attempt the payer started again).
  var _attempt = 0;
  var _ready = false;
  Timer? _readyTimer;
  Timer? _autoClose;
  PaymentWatcher? _watcher;
  SessionTransaction? _transaction;

  /// `onPaymentStarted` fired for the attempt under way, and no outcome yet:
  /// a dismiss resolves `processing`.
  var _attemptStarted = false;

  /// A request of the attempt is on its way.
  var _inFlight = false;

  /// An attempt the API accepted (a 2xx, `payment_in_progress`, or a payment
  /// processing when the sheet opened) has no definitive answer yet — a
  /// 402, a refusal the status reports, a step failed for good, an outcome.
  /// Until then the payment is never cancelled, even on a failure screen
  /// (`unsupported_action`, `redirect_unavailable`…).
  var _acceptedUndecided = false;
  var _paymentStartedFired = false;
  bool _seenProcessing = false;
  String? _clientSessionId;
  Future<int?>? _altcha;
  var _altchaReloaded = false;

  /// The challenge's solution went out with a request: the next attempt
  /// needs a new challenge.
  var _altchaUsed = false;

  /// The `Idempotency-Key` of a payment that got no answer: the next Pay
  /// sends it again, so a request that did reach the API is replayed, not
  /// charged twice (README §2.5).
  String? _unansweredKey;

  /// The call of a payment without an answer (`/pay/process` or
  /// `/pay/client-session`): it counts as never arrived 60 s after its last
  /// try was sent (the device's monotonic clock), if the status still reads
  /// a plain `pending`.
  String? _unansweredPath;
  static const _neverArrivedAfter = Duration(seconds: 60);

  /// The app went to the background since the browser opened.
  var _leftApp = false;

  /// [onLoadError] fired for the load under way.
  var _loadErrorReported = false;

  /// "Cancel payment" is waiting for its answer.
  var _cancelling = false;

  /// The last refusal code the payment carried (a decline, a status), and
  /// the one it carried when the attempt under way was sent: a refusal left
  /// by an earlier try is not news.
  String? _lastErrorCode;
  String? _errorCodeBeforeAttempt;

  /// How many `/pay/client-session/complete` calls are running (one per
  /// return to the app): while any runs, they decide, not a refusal the
  /// watch reads meanwhile (deferred here until the last one answers).
  var _completions = 0;
  bool get _completing => _completions > 0;
  WatchDecision? _deferredDecision;

  /// The sheet's route is gone while a cancel ran: settle without popping.
  var _routeGone = false;
  var _closing = false;

  /// "Cancel payment" is offered while no attempt is in flight.
  bool get canCancel =>
      _mayCancel &&
      !_isFinal &&
      (_screen == CheckoutScreen.methods ||
          _screen == CheckoutScreen.form ||
          (_screen == CheckoutScreen.failed && !_endedAtLoad && (_error?.retryable ?? false)));

  /// `POST /pay/cancel` is sent only for a loaded session whose last known
  /// status is `pending`, while no attempt is undecided — from the press of
  /// Pay to a definitive answer: the API also cancels a `processing` payment
  /// the payer may still approve (README §14). After a definitive refusal the
  /// payment is `pending` again and may be cancelled again.
  bool get _mayCancel =>
      _session != null &&
      (_transaction?.status ?? _session!.transaction.status) == 'pending' &&
      !_inFlight &&
      !_attemptStarted &&
      !_acceptedUndecided &&
      !_cancelling &&
      !_closing;

  /// A cancel call is on its way: Pay, Close and Cancel wait for it.
  bool get cancelling => _cancelling || _closing;

  /// The form can go back to the method list.
  bool get canGoBack => _screen == CheckoutScreen.form && !_busy && _methods.where((m) => m.enabled).length > 1;

  bool get _isFinal => const {CheckoutState.success, CheckoutState.expired, CheckoutState.cancelled}.contains(_state);

  /// [attempt] is no longer the one under way, or the sheet has settled.
  bool _stale(int attempt) => settled || _closing || attempt != _attempt;

  // ── Loading (README §4) ──────────────────────────────────────────────────

  /// Loads the session and sdk-config in parallel, then shows the first
  /// screen. Called once by the sheet, and again by Retry.
  Future<void> load() async {
    final generation = ++_generation;
    session.language = language;
    _ready = false;
    _loadErrorReported = false;
    _readyTimer?.cancel();
    _error = null;
    _setScreen(CheckoutScreen.loading);
    if (options.readyTimeout > Duration.zero) {
      _readyTimer = Timer(options.readyTimeout, () {
        if (generation != _generation || _ready || settled) return;
        final error = WajubError.of(
          'ready_timeout',
          language: language,
          apiMessage: 'Payment sheet not ready after ${options.readyTimeout.inMilliseconds} ms',
        );
        _loadError(error);
      });
    }

    final sessionLoad = session.loadSession(forceRefresh: true);
    _sdkConfigFailed = false;
    final configLoad = session.getSdkConfig().then<SdkConfig?>((c) => c, onError: (Object _) {
      _sdkConfigFailed = true;
      return null;
    });
    final dataLoad = _loadMobileMoneyData().then<MobileMoneyData?>((d) => d, onError: (Object _) => null);
    SessionData loaded;
    try {
      loaded = await sessionLoad;
    } on WajubError catch (e) {
      if (generation != _generation || settled) return;
      _loadError(_loadErrorFor(e));
      return;
    } catch (e) {
      if (generation != _generation || settled) return;
      _loadError(WajubError.of('load_error', language: language, apiMessage: '$e'));
      return;
    }
    if (generation != _generation || settled) return;
    // Known from now on: a dismiss decides on this status, without waiting
    // for sdk-config.
    _session = loaded;
    _transaction = loaded.transaction;
    // A refusal an earlier try left on the payment is not this sheet's news.
    _lastErrorCode ??= loaded.transaction.errorCode;
    if (!_payable(loaded.transaction.status)) {
      // Paid, ended or processing: the session alone says what to show, at
      // once. sdk-config and the Mobile Money tables, when they come, only
      // add the methods a "Try again" may need.
      _readyTimer?.cancel();
      session.language = language;
      _error = null;
      _start(loaded);
      unawaited(Future.wait<Object?>([configLoad, dataLoad]).then((loads) {
        if (generation != _generation || settled) return;
        _sdkConfig = loads[0] as SdkConfig?;
        _mobileMoneyData = loads[1] as MobileMoneyData?;
        final family = _method?.family;
        _methods = buildMethods(loaded, _sdkConfig);
        if (family != null) _method = _methods.where((m) => m.family == family).firstOrNull ?? _method;
        notifyListeners();
      }));
      return;
    }
    final config = await configLoad;
    final data = await dataLoad;
    if (generation != _generation || settled) return;
    _readyTimer?.cancel();
    _sdkConfig = config;
    _mobileMoneyData = data;
    session.language = language;
    _error = null;
    _start(loaded);
  }

  /// A status the payer may still pay from: the methods (and so sdk-config)
  /// are needed before anything shows.
  static bool _payable(String status) => const {'pending', 'unknown'}.contains(status.toLowerCase());

  /// sdk-config could not be read for the load under way.
  var _sdkConfigFailed = false;

  /// Retry on the error view: starts the load again, a new timer included.
  Future<void> retryLoad() => load();

  WajubError _loadErrorFor(WajubError e) {
    final code = switch (e.code) {
      'session_not_found' || 'session_terminal_expired' => e.code,
      _ when e.httpStatus == 401 || e.httpStatus == 403 || e.httpStatus == 404 => 'session_not_found',
      _ when e.httpStatus == 410 => 'session_terminal_expired',
      _ => 'load_error',
    };
    return WajubError.of(code,
        language: language, httpStatus: e.httpStatus, apiMessage: e.apiMessage, correlationId: e.correlationId);
  }

  void _loadError(WajubError error) {
    // A failure before the timer ends it.
    _readyTimer?.cancel();
    _error = error;
    _setScreen(CheckoutScreen.loadError);
    _reportLoadError(error);
  }

  /// `onLoadError` once per load: a load that fails after its
  /// `ready_timeout` updates the view, not the callback.
  void _reportLoadError(WajubError error) {
    if (_loadErrorReported) return;
    _loadErrorReported = true;
    _call(() => _callbacks.onLoadError?.call(error));
  }

  void _start(SessionData loaded) {
    final transaction = loaded.transaction;
    _methods = buildMethods(loaded, _sdkConfig);
    switch (transaction.status.toLowerCase()) {
      case 'succeeded' || 'refunded' || 'partially_refunded':
        _becomeReady();
        _succeed(transaction, method: 'unknown');
      case 'failed':
        _endAtLoad('session_terminal_failed', CheckoutState.failed);
      case 'cancelled':
        _endAtLoad('session_terminal_cancelled', CheckoutState.cancelled);
      case 'expired':
        _endAtLoad('session_terminal_expired', CheckoutState.expired);
      case 'processing' || 'partial':
        _becomeReady();
        _restore(transaction);
      default:
        if (_methods.isEmpty) {
          // Without sdk-config the cards and wallets cannot be offered: a
          // load error to retry, not "no payment method".
          _loadError(WajubError.of(_sdkConfigFailed ? 'load_error' : 'no_payment_method', language: language));
          return;
        }
        _becomeReady();
        _altcha = _startAltcha(loaded);
        final enabled = _methods.where((m) => m.enabled).toList();
        if (enabled.length == 1) {
          selectMethod(enabled.single);
        } else {
          _enter(CheckoutState.initiated, CheckoutScreen.methods);
        }
    }
  }

  void _becomeReady() {
    _ready = true;
    _readyTimer?.cancel();
    final loaded = _session!;
    final event = ReadyEvent(
      sessionId: loaded.transaction.id,
      environment: loaded.transaction.sandbox ? 'sandbox' : 'live',
      amount: loaded.transaction.payableAmount,
      currency: loaded.transaction.currency,
      methods: [
        for (final method in _methods)
          for (final channel in method.channels) channel.slug,
      ],
    );
    _call(() => _callbacks.onReady?.call(event));
  }

  void _endAtLoad(String code, CheckoutState state) {
    _becomeReady();
    _endedAtLoad = true;
    _error = WajubError.of(code, language: language);
    _enter(state, CheckoutScreen.failed);
    _reportLoadError(_error!);
  }

  /// A payment already in progress when the sheet opened (README §4.2).
  void _restore(SessionTransaction transaction) {
    final context = transaction.processingContext;
    _acceptedUndecided = true;
    _attemptClock
      ..reset()
      ..start();
    _attemptStarted = true;
    _paymentStartedFired = true;
    _seenProcessing = true;
    _method = _methodFor(context);
    _instruction = context?.payerInstruction;
    if (context?.isMobileMoney ?? false) {
      _enter(CheckoutState.approvalRequired, CheckoutScreen.approval);
    } else if (context?.isUssd ?? false) {
      _enter(CheckoutState.ussdRequired, CheckoutScreen.ussd);
    } else if (context?.threeDsId != null) {
      _showThreeDs(context!.threeDsId!, context.maskedEmail, context.threeDsTimeout);
    } else {
      _continueUrl = context?.actionUrl;
      _enter(CheckoutState.pending, CheckoutScreen.pending);
    }
    _watch(pollNow: true);
  }

  CheckoutMethod? _methodFor(ProcessingContext? context) {
    if (context?.isMobileMoney ?? false) {
      return _methods.where((m) => m.family == MethodFamily.mobileMoney).firstOrNull;
    }
    final slug = context?.channelSlug;
    return _methods.where((m) => m.channels.any((c) => c.slug == slug)).firstOrNull;
  }

  // ── Methods and forms ────────────────────────────────────────────────────

  void selectMethod(CheckoutMethod method) {
    if (!method.enabled || _busy || settled) return;
    _method = method;
    _clearMessages();
    if (method.family == MethodFamily.mobileMoney) _resetMobileMoney();
    if (method.family == MethodFamily.card) _prefillCard();
    _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
  }

  /// Back to the method list from a form.
  void backToMethods() {
    if (!canGoBack) return;
    _clearMessages();
    _method = null;
    _enter(CheckoutState.initiated, CheckoutScreen.methods);
  }

  void _resetMobileMoney() {
    final channels = _method?.channels ?? const <SessionChannel>[];
    _pickedByHand = false;
    _listOpened = false;
    _countries = mobileMoneyCountries(channels);
    _country ??= defaultMobileMoneyCountry(
      channels,
      requested: _requestedCountry,
      geoCountry: _session?.geoCountry,
    );
    _refreshChoices();
  }

  void setCountry(String country) {
    if (_busy || country == _country) return;
    _country = country.toUpperCase();
    _pickedByHand = false;
    _listOpened = false;
    _clearMessages();
    _refreshChoices();
    notifyListeners();
  }

  void _refreshChoices() {
    final data = _mobileMoneyData;
    final country = _country;
    _choices = data == null || country == null
        ? const []
        : operatorChoices(_method?.channels ?? const [], country, data, language: language);
    _selectedId = _choices.isEmpty ? null : _choices.first.id;
    _preselect();
  }

  /// The payer picked an operator: detection never overrides it.
  void pickOperator(String id) {
    if (_busy || !_choices.any((choice) => choice.id == id)) return;
    _selectedId = id;
    _pickedByHand = true;
    _clearMessages();
    notifyListeners();
  }

  /// `detect` mode: the payer opened the operator list.
  void openOperatorList() {
    _listOpened = true;
    notifyListeners();
  }

  void setPhone(String value) {
    if (_busy) return;
    _phone = value;
    _fieldErrors = const {};
    _banner = null;
    _preselect();
    notifyListeners();
  }

  void _preselect() {
    final data = _mobileMoneyData;
    if (data == null || _country == null) return;
    _selectedId = MobileMoneyRules.preselect(
      choiceIds: [for (final choice in _choices) choice.id],
      currentId: _selectedId,
      pickedByHand: _pickedByHand,
      detectedId: data.detectOperator(_phone, _country!),
    );
  }

  String? _mismatch() {
    final data = _mobileMoneyData;
    if (data == null || _country == null) return null;
    return MobileMoneyRules.mismatch(
      data: data,
      phone: _phone,
      country: _country!,
      choiceIds: [for (final choice in _choices) choice.id],
      selectedId: _selectedId,
    );
  }

  String _mismatchMessage(String detected) {
    String label(String? id) => _choices.where((c) => c.id == id).firstOrNull?.label ?? id ?? '';
    return ErrorCatalogue.text(
      ErrorCatalogue.lookup('operator_mismatch')!,
      language,
      {'detected': label(detected), 'selected': label(_selectedId)},
    );
  }

  void setCardField(String key, String value) {
    _cardFields[key] = value;
    if (_fieldErrors.containsKey(key) || _fieldErrors.containsKey('data.$key')) {
      _fieldErrors = Map.of(_fieldErrors)
        ..remove(key)
        ..remove('data.$key');
    }
    notifyListeners();
  }

  void _prefillCard() {
    final customer = _session?.transaction.customer;
    final name = customer?.name?.split(RegExp(r'\s+')) ?? const <String>[];
    final known = {
      'email': customer?.email,
      'first_name': name.isNotEmpty ? name.first : null,
      'last_name': name.length > 1 ? name.sublist(1).join(' ') : null,
      'card_holder': customer?.name,
    };
    for (final entry in known.entries) {
      if (entry.value != null) _cardFields.putIfAbsent(entry.key, () => entry.value!);
    }
  }

  void _clearMessages() {
    _fieldErrors = const {};
    _banner = null;
  }

  // ── Paying (README §6–§9, §11) ───────────────────────────────────────────

  /// Pay with the Mobile Money form: validates as the web checkout does,
  /// then submits.
  Future<void> payMobileMoney() async {
    final data = _mobileMoneyData;
    final country = _country;
    if (_busy || data == null || country == null || settled) return;
    if (_choices.isEmpty) {
      _formError('data.operator', ErrorCatalogue.text(ErrorCatalogue.lookup('operator_unavailable')!, language));
      return;
    }
    final code = MobileMoneyRules.validate(
      data: data,
      phone: _phone,
      country: country,
      choiceIds: [for (final choice in _choices) choice.id],
      selectedId: _selectedId,
      sandbox: _session?.transaction.sandbox ?? false,
    );
    if (code != null) {
      final message = code == 'operator_mismatch'
          ? _mismatchMessage(_mismatch()!)
          : ErrorCatalogue.text(ErrorCatalogue.lookup(code)!, language);
      _formError(code == 'operator_required' ? 'data.operator' : 'data.phone', message);
      return;
    }
    final choice = _choices.firstWhere((c) => c.id == _selectedId);
    final request = MobileMoneyRules.requestData(
      data: data,
      phone: _phone,
      country: country,
      choice: choice,
      pickedByHand: _pickedByHand,
    );
    _approvalPhone = request['phone'] as String?;
    await _process(choice.channelSlug, request, MethodFamily.mobileMoney);
  }

  /// One tap on a wallet (Djamo): nothing to collect.
  Future<void> payWallet() async {
    final method = _method;
    if (_busy || method?.family != MethodFamily.wallet || settled) return;
    await _process(method!.channel.slug, const {}, MethodFamily.wallet);
  }

  /// The card form: what its flavour needs, then submits.
  Future<void> payCard({String? stripePublishableKeyOverride}) async {
    final method = _method;
    if (_busy || method?.family != MethodFamily.card || settled) return;
    final errors = <String, String>{};
    for (final field in cardRequiredFields) {
      final message = _cardFieldError(field, _cardFields[field]);
      if (message != null) errors[field] = message;
    }
    if (errors.isNotEmpty) {
      _fieldErrors = errors;
      _banner = null;
      notifyListeners();
      return;
    }
    final fields = {for (final field in cardRequiredFields) field: (_cardFields[field] ?? '').trim()};
    switch (method!.cardFlavour) {
      case CardFlavour.clientSession:
        await _startClientSession(method, fields);
      case CardFlavour.hostedRedirect:
        await _process(method.channel.slug, PaymentMapper.buildHostedCardRequest(fields), MethodFamily.card);
      case CardFlavour.sandboxForm:
        await _process(method.channel.slug, fields, MethodFamily.card);
      case CardFlavour.stripe:
        await _payStripe(method);
      case null:
        break;
    }
  }

  String? _cardFieldError(String field, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return ErrorCatalogue.text(ErrorCatalogue.lookup('field_required')!, language);
    if (field == 'email' && !PaymentMapper.isEmail(text)) {
      return ErrorCatalogue.text(ErrorCatalogue.lookup('invalid_email')!, language);
    }
    if (field == 'country' && !RegExp(r'^[A-Za-z]{2}$').hasMatch(text)) {
      return ErrorCatalogue.text(ErrorCatalogue.lookup('validation_error')!, language);
    }
    return null;
  }

  Future<void> _payStripe(CheckoutMethod method) async {
    if (_inFlight || settled || cancelling) return;
    // The stripe flavour is only offered with a publishable key.
    final key = method.config!.publishableKey!;
    // In flight from the press: a dismiss while Stripe tokenizes resolves
    // `processing` and the charge is never sent.
    final attempt = _beginAttempt();
    String paymentMethodId;
    _stripeKeySet = true;
    try {
      paymentMethodId = await _stripePaymentMethod(key, _cardFields['card_holder']);
    } catch (e) {
      if (_stale(attempt)) return;
      _inFlight = false;
      _setBusy(false);
      // Stripe's own refusal, or the plugin failing (its setup in the app).
      _banner = e is WajubError ? e.message : ErrorCatalogue.text(ErrorCatalogue.lookup('request_failed')!, language);
      _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
      return;
    }
    if (_stale(attempt)) return;
    await _sendProcess(
      attempt,
      method.channel.slug,
      buildStripeCardRequest(paymentMethodId: paymentMethodId, cardholderName: _cardFields['card_holder']),
      MethodFamily.card,
    );
  }

  Future<void> _process(String channel, Map<String, dynamic> data, MethodFamily family) async {
    if (_inFlight || settled || cancelling) return;
    if (!(_session?.transaction.sandbox ?? false) && carriesCardData(data)) {
      // The API refuses raw card data in live (README §7); never send it.
      _fail(WajubError.of('raw_card_data_not_accepted', language: language));
      return;
    }
    await _sendProcess(_beginAttempt(), channel, data, family);
  }

  /// A press of Pay: a new attempt, in flight until its answer.
  int _beginAttempt() {
    final attempt = ++_attempt;
    _submitted = true;
    _attemptClock
      ..reset()
      ..start();
    _errorCodeBeforeAttempt = _lastErrorCode;
    _inFlight = true;
    _altchaReloaded = false;
    _continueUrl = null;
    _clearMessages();
    _setBusy(true);
    _enter(CheckoutState.processing, CheckoutScreen.form);
    _call(() => onSubmit?.call());
    return attempt;
  }

  Future<void> _sendProcess(int attempt, String channel, Map<String, dynamic> data, MethodFamily family) async {
    // One key per press of Pay, reused by the client's own retries — and by
    // the next press when this one got no answer (README §2.5).
    final key = _unansweredKey ?? uuidV4();
    final body = {
      ...data,
      if (options.returnUrl != null) 'return_url': options.returnUrl,
    };
    final solved = await _altchaFor(attempt);
    if (solved == null || _stale(attempt)) return;
    final altcha = solved.$1;
    try {
      final raw = await session.client.process(
        session.token,
        channel,
        {...body, if (altcha != null) 'altcha': altcha},
        idempotencyKey: key,
      );
      if (_stale(attempt)) return;
      _inFlight = false;
      _setBusy(false);
      _onAnswer(raw, family, channel);
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      // Still in flight while a refused challenge is renewed.
      final retry = await _retryAltcha(e);
      if (_stale(attempt)) return;
      switch (retry) {
        case true:
          _unansweredKey = null;
          await _sendProcess(attempt, channel, data, family);
        case null:
          await _onRefusal(e, family, channel, attempt: attempt, key: key, path: '/pay/process');
        case false:
          break;
      }
    }
  }

  /// Card numbers, CVCs and PINs: never sent to `/pay/process` in live.
  @visibleForTesting
  static bool carriesCardData(Map<String, dynamic> data) =>
      const {'card.number', 'card_number', 'number', 'cvv', 'cvc', 'pin'}.any(data.containsKey);

  Future<void> _startClientSession(CheckoutMethod method, Map<String, String> fields) async {
    if (_inFlight || settled || cancelling) return;
    await _sendClientSession(_beginAttempt(), method, fields);
  }

  Future<void> _sendClientSession(int attempt, CheckoutMethod method, Map<String, String> fields) async {
    final solved = await _altchaFor(attempt);
    if (solved == null || _stale(attempt)) return;
    final altcha = solved.$1;
    try {
      final raw = await session.client.startClientSession(
        session.token,
        method.channel.slug,
        email: fields['email'],
        returnUrl: options.returnUrl,
        billing: {
          for (final entry in fields.entries)
            if (entry.key != 'email') entry.key: entry.key == 'country' ? entry.value.toUpperCase() : entry.value,
        },
        altcha: altcha,
      );
      if (_stale(attempt)) return;
      _inFlight = false;
      _setBusy(false);
      _onAnswer(raw, MethodFamily.card, method.channel.slug);
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      final retry = await _retryAltcha(e);
      if (_stale(attempt)) return;
      switch (retry) {
        case true:
          await _sendClientSession(attempt, method, fields);
        case null:
          await _onRefusal(e, MethodFamily.card, method.channel.slug,
              attempt: attempt, key: null, path: '/pay/client-session');
        case false:
          break;
      }
    }
  }

  /// A 2xx of `/pay/process` or `/pay/client-session` (README §9).
  void _onAnswer(RawProcessResponse raw, MethodFamily family, String channel) {
    _paymentStarted(family, channel);
    _acceptedUndecided = true;
    _unansweredKey = null;
    _unansweredPath = null;
    final transaction = raw.transaction;
    if (transaction != null) _transaction = transaction;
    if (raw.httpStatus == 202 || const {'processing', 'partial'}.contains(transaction?.status)) {
      _seenProcessing = true;
    }
    if (transaction == null && raw.action == null) {
      // Accepted, but without its transaction: the outcome is unknown, never
      // a failure — follow the status.
      _seenProcessing = true;
      _enter(CheckoutState.pending, CheckoutScreen.pending);
      _watch(pollNow: true);
      return;
    }
    _handle(PaymentMapper.mapProcessAnswer(raw, family.wireName, fallback: _transaction ?? _session?.transaction));
  }

  void _handle(PaymentResult result) {
    switch (result) {
      case PaymentComplete(:final transaction):
        _succeed(transaction, method: _family);
      case PaymentFailed(:final error):
        _fail(error.localized(language));
      case PaymentProcessing(:final instruction, :final kind):
        _instruction = instruction;
        if (kind == ProcessingKind.ussd) {
          _enter(CheckoutState.ussdRequired, CheckoutScreen.ussd);
        } else if (kind == ProcessingKind.approval) {
          _enter(CheckoutState.approvalRequired, CheckoutScreen.approval);
        } else {
          _enter(CheckoutState.pending, CheckoutScreen.pending);
        }
        _watch();
      case PaymentRequiresAction():
        _onAction(result);
    }
  }

  void _onAction(PaymentRequiresAction result) {
    final step = result.step;
    if (step != null) {
      _showStep(step, result.stepId!, result.hint);
      _watch();
      return;
    }
    switch (result.action) {
      case ActionKind.pushApproval:
        _instruction = result.transaction.processingContext?.payerInstruction;
        _enter(CheckoutState.approvalRequired, CheckoutScreen.approval);
        _watch();
      case ActionKind.confirm3ds when result.stepId != null:
        _showThreeDs(result.stepId!, result.hint, result.timeoutSeconds);
        _watch();
      case ActionKind.clientSession:
        final url = result.actionUrl;
        if (url == null) {
          _fail(WajubError.of(PaymentMapper.unsupportedActionCode, language: language));
          return;
        }
        _clientSessionId = result.clientSession?.id;
        _watch();
        unawaited(_redirect(url, CheckoutState.pending));
      default:
        _watch();
        unawaited(_redirect(
          result.actionUrl!,
          result.action == ActionKind.confirm3ds ? CheckoutState.threeDsRequired : CheckoutState.pending,
        ));
    }
  }

  /// `onRedirect`, then the system browser — never a WebView (README §12).
  Future<void> _redirect(String url, CheckoutState state) async {
    final attempt = _attempt;
    _continueUrl = url;
    _enter(state, CheckoutScreen.pending);
    _call(() => _callbacks.onRedirect?.call(RedirectEvent(url: url)));
    bool opened;
    try {
      opened = await _openUrl(url);
    } catch (_) {
      opened = false;
    }
    if (_stale(attempt)) return;
    if (!opened) _fail(WajubError.of('redirect_unavailable', language: language));
  }

  /// "Continue payment": the same page again.
  Future<void> continuePayment() async {
    final url = _continueUrl;
    if (url == null || settled) return;
    await _redirect(
        url, _state == CheckoutState.threeDsRequired ? CheckoutState.threeDsRequired : CheckoutState.pending);
  }

  /// A refusal of `/pay/process` or `/pay/client-session` (README §9). The
  /// attempt stays in flight until it is decided: a dismiss meanwhile
  /// resolves `processing`.
  Future<void> _onRefusal(
    WajubError e,
    MethodFamily family,
    String channel, {
    required int attempt,
    required String? key,
    required String path,
  }) async {
    final error = e.localized(language);
    final status = error.httpStatus;
    if (status == null || status >= 500 || error.code == 'server_error' || error.code == 'timeout') {
      // No answer: the charge may be running. Never a failure — watch. If
      // the status still says nothing 60 s after the last try, the request
      // most likely never arrived (README §2.5).
      _unansweredKey = key;
      _unansweredPath = path;
      _attemptStarted = true;
      _inFlight = false;
      _setBusy(false);
      _enter(CheckoutState.pending, CheckoutScreen.pending);
      _watch(pollNow: true);
      return;
    }
    _unansweredKey = null;
    _unansweredPath = null;
    if (status == 402) {
      _lastErrorCode = error.declineCode ?? error.code;
      _pendingAgain();
    }
    if (status == 400) {
      await _settleFromStatus(fallback: error);
      if (!_stale(attempt)) {
        _inFlight = false;
        _setBusy(false);
      }
      return;
    }
    _inFlight = false;
    _setBusy(false);
    switch (status) {
      case 409 when error.code == 'payment_in_progress':
        _paymentStarted(family, channel);
        _acceptedUndecided = true;
        _seenProcessing = true;
        _enter(CheckoutState.pending, CheckoutScreen.pending);
        _watch(pollNow: true);
      case 410:
        _fail(WajubError.of('session_terminal_expired', language: language, httpStatus: 410),
            state: CheckoutState.expired);
      case 422 when !_formErrorCodes.contains(error.code) && ErrorCatalogue.lookup(error.code) != null:
        _fail(error);
      case 422:
        _showFieldErrors(error);
      case 429:
        _retryAt = clock.now().add(Duration(seconds: error.retryAfterSeconds ?? 60));
        _fail(error);
      default:
        _fail(error);
    }
  }

  /// A definitive refusal (a 402, a step failed for good, a `pending` read):
  /// the payment is `pending` again, so "Cancel payment" is offered again.
  void _pendingAgain() {
    _acceptedUndecided = false;
    _transaction = (_transaction ?? _session?.transaction)?.copyWith(status: 'pending');
  }

  /// A payment that got no answer and whose status never moved: back to the
  /// form, retryable; the next Pay sends the same `Idempotency-Key`.
  void _backToForm() {
    _watcher?.stop();
    _unansweredPath = null;
    _attemptStarted = false;
    _inFlight = false;
    _busy = false;
    _continueUrl = null;
    final error = WajubError.of('network_error', language: language);
    _fieldErrors = const {};
    _banner = error.message;
    _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
    _call(() => _callbacks.onError?.call(error));
  }

  static const _formErrorCodes = {'validation_error', 'invalid_phone', 'operator_mismatch', 'field_required'};

  /// A 422: the form stays, its fields show what the API refused (README §9.1).
  void _showFieldErrors(WajubError error) {
    final errors = <String, String>{};
    String? banner;
    final generic = language == 'fr' || error.apiMessage == null
        ? ErrorCatalogue.text(ErrorCatalogue.lookup('validation_error')!, language)
        : error.apiMessage!;
    for (final entry in error.details.entries) {
      final key = entry.key;
      if (const {'data.phone', 'phone', 'data.account_number'}.contains(key)) {
        final mismatch = entry.value.contains('belongs to');
        errors['data.phone'] = ErrorCatalogue.text(
          ErrorCatalogue.lookup(mismatch ? 'operator_mismatch' : 'invalid_phone')!,
          language,
          {'detected': _detectedLabel(entry.value), 'selected': _selectedLabel()},
        );
      } else if (key == 'request' || key == 'channel' || key.isEmpty) {
        banner = language == 'fr' ? generic : entry.value;
      } else {
        final field = key.startsWith('data.') ? key.substring(5) : key;
        errors[field] = language == 'fr' ? generic : entry.value;
      }
    }
    if (errors.isEmpty && banner == null) banner = generic;
    _fieldErrors = errors;
    _banner = banner;
    _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
    notifyListeners();
  }

  /// The operator the API says the number belongs to ("belongs to ORANGE
  /// (cm.orange)"), else the one the number names.
  String _detectedLabel(String apiMessage) {
    final named = RegExp(r'belongs to ([A-Za-z_]+)').firstMatch(apiMessage)?.group(1)?.toLowerCase();
    final id = named ?? detectedOperatorId;
    final brand = id == null ? null : _mobileMoneyData?.operators[id]?.brand?.label;
    return _choices.where((c) => c.id == id).firstOrNull?.label ?? brand ?? id?.toUpperCase() ?? '';
  }

  String _selectedLabel() => _choices.where((c) => c.id == _selectedId).firstOrNull?.label ?? '';

  void _formError(String key, String message) {
    _fieldErrors = {key: message};
    _banner = null;
    _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
    notifyListeners();
  }

  /// A `400` on a payment: the status says how it stands (README §9) —
  /// terminal: that outcome; `pending`: `not_processable`; `processing`, or
  /// nothing readable: an attempt may be running, follow it.
  Future<void> _settleFromStatus({required WajubError fallback}) async {
    final attempt = _attempt;
    PaymentStatusUpdate? update;
    try {
      update = await session.status();
    } on WajubError catch (_) {
      // Unreadable after its retries.
    }
    if (_stale(attempt)) return;
    final decision = update == null ? null : decideStatus(update, seenProcessing: false, language: language);
    if (decision != null) {
      _onDecision(decision);
      return;
    }
    if (update?.status == 'pending') {
      _pendingAgain();
      _fail(WajubError.of('not_processable', language: language, httpStatus: 400, apiMessage: fallback.apiMessage));
      return;
    }
    _attemptStarted = true;
    _seenProcessing = update?.status == 'processing' || update?.status == 'partial';
    _enter(CheckoutState.pending, CheckoutScreen.pending);
    _watch(pollNow: true);
  }

  // ── Confirmation steps (README §10) ──────────────────────────────────────

  void _showStep(PaymentStepKind kind, String id, String? hint) {
    _stepKind = kind;
    _stepId = id;
    _stepHint = hint;
    _attemptsRemaining = null;
    _resendAt = clock.now().add(const Duration(seconds: 60));
    _clearMessages();
    _enter(_stepState(kind), CheckoutScreen.step);
  }

  static CheckoutState _stepState(PaymentStepKind kind) => switch (kind) {
        PaymentStepKind.otp => CheckoutState.otpRequired,
        PaymentStepKind.pin => CheckoutState.pinRequired,
        PaymentStepKind.phone => CheckoutState.phoneRequired,
        PaymentStepKind.birthday => CheckoutState.birthdayRequired,
        PaymentStepKind.address => CheckoutState.addressRequired,
      };

  /// The fields of the step on screen: `{code}`, `{pin}`, `{phone}`,
  /// `{birthday}` (`YYYY-MM-DD`), or `{address, city, state, zip_code}`.
  Future<void> submitStep(Map<String, String> fields) async {
    final kind = _stepKind;
    final id = _stepId;
    if (kind == null || id == null || _busy || settled || cancelling) return;
    final missing = {
      for (final entry in fields.entries)
        if (entry.value.trim().isEmpty)
          entry.key: ErrorCatalogue.text(ErrorCatalogue.lookup('field_required')!, language),
    };
    if (missing.isNotEmpty) {
      _fieldErrors = missing;
      notifyListeners();
      return;
    }
    final attempt = _attempt;
    _clearMessages();
    _setBusy(true);
    _enter(CheckoutState.verifying, CheckoutScreen.step);
    try {
      final answer = await session.verifyStep(kind, id, {
        for (final entry in fields.entries) entry.key: entry.value.trim(),
      });
      if (_stale(attempt)) return;
      _setBusy(false);
      if (answer.success) {
        final transaction = answer.transaction;
        if (transaction != null) _transaction = transaction;
        final next = answer.next;
        if (next != null) {
          // The provider asks for another step: followed as a payment
          // answer (its own screen and attempts, or its page); paid only
          // when a status says so.
          if (const {'processing', 'partial'}.contains(transaction?.status)) _seenProcessing = true;
          _handle(next);
          return;
        }
        switch (transaction?.status) {
          case 'succeeded':
            // A step the provider settles at once.
            _succeed(transaction!, method: _family);
          case 'failed':
            _fail(WajubError.of('payment_failed', language: language));
          default:
            _enter(CheckoutState.pending, CheckoutScreen.pending);
            _watcher?.pollNow();
        }
        return;
      }
      final error = WajubError.fromStep(answer, language: language);
      if ((answer.errorCode?.startsWith('invalid_') ?? false) && (answer.attemptsRemaining ?? 0) > 0) {
        _attemptsRemaining = answer.attemptsRemaining;
        _banner = error.message;
        _enter(_stepState(kind), CheckoutScreen.step);
        notifyListeners();
      } else {
        // A step failed for good: the attempt is refused.
        _pendingAgain();
        _fail(error);
      }
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      _setBusy(false);
      _onStepRefusal(e.localized(language), _stepState(kind));
    }
  }

  void _onStepRefusal(WajubError error, CheckoutState stay) {
    switch (error.httpStatus) {
      case 422:
        _fieldErrors = {
          for (final entry in error.details.entries)
            entry.key: language == 'fr'
                ? ErrorCatalogue.text(ErrorCatalogue.lookup('validation_error')!, language)
                : entry.value,
        };
        _banner = _fieldErrors.isEmpty ? error.message : null;
      case 410:
        _fail(WajubError.of('session_terminal_expired', language: language, httpStatus: 410),
            state: CheckoutState.expired);
        return;
      case 401 || 403 || 404:
        _fail(WajubError.of('session_not_found', language: language));
        return;
      default:
        // No answer: the status may already know; the payer can try again.
        _banner = error.message;
        _watcher?.pollNow();
    }
    _enter(stay, _screen);
    notifyListeners();
  }

  /// "Resend", 60 s after the step opened; the countdown starts again.
  Future<void> resend() async {
    final now = clock.now();
    if (_resendAt != null && now.isBefore(_resendAt!)) return;
    final attempt = _attempt;
    _resendAt = now.add(const Duration(seconds: 60));
    notifyListeners();
    try {
      if (_screen == CheckoutScreen.threeDs && _stepId != null) {
        final email = await session.sendThreeDs(_stepId!);
        if (email != null) _stepHint = email;
      } else if (_stepKind != null && _stepId != null) {
        await session.resendStep(_stepKind!, _stepId!);
      }
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      _banner = e.localized(language).message;
    }
    notifyListeners();
  }

  void _showThreeDs(String id, String? maskedEmail, int? timeoutSeconds) {
    _stepKind = null;
    _stepId = id;
    _stepHint = maskedEmail;
    _attemptsRemaining = null;
    _resendAt = clock.now().add(const Duration(seconds: 60));
    _threeDsTimer?.cancel();
    if (timeoutSeconds != null && timeoutSeconds > 0) {
      _threeDsDeadline = clock.now().add(Duration(seconds: timeoutSeconds));
      _threeDsTimer = Timer(Duration(seconds: timeoutSeconds), () {
        if (_screen == CheckoutScreen.threeDs && !settled) _fail(WajubError.of('3ds_timeout', language: language));
      });
    }
    _clearMessages();
    _enter(CheckoutState.threeDsRequired, CheckoutScreen.threeDs);
  }

  /// The sandbox 3-D Secure email code (README §10.1).
  Future<void> submitThreeDsCode(String code) async {
    final id = _stepId;
    if (id == null || _busy || settled || cancelling || _screen != CheckoutScreen.threeDs) return;
    if (code.trim().length < 4 || code.trim().length > 8) {
      _fieldErrors = {'code': ErrorCatalogue.text(ErrorCatalogue.lookup('invalid_code')!, language)};
      notifyListeners();
      return;
    }
    final attempt = _attempt;
    _clearMessages();
    _setBusy(true);
    _enter(CheckoutState.verifying, CheckoutScreen.threeDs);
    try {
      await session.verifyThreeDs(id, code.trim());
      if (_stale(attempt)) return;
      // Accepted: the provider decides now; the screen waits on the status,
      // and the code's own deadline no longer applies.
      _threeDsTimer?.cancel();
      _watcher?.pollNow();
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      _setBusy(false);
      final status = e.httpStatus ?? 0;
      final retryable = e.code == 'invalid_code' || status >= 500 || (status == 422 && e.code == 'validation_error');
      if (retryable) {
        // The API answers a wrong code with a 500 today: same screen.
        _fieldErrors = {
          'code': WajubError.of('invalid_code', language: language, attemptsRemaining: e.attemptsRemaining).message,
        };
        _enter(CheckoutState.threeDsRequired, CheckoutScreen.threeDs);
        notifyListeners();
      } else if (status == 422) {
        _fail(e.localized(language));
      } else {
        _onStepRefusal(e.localized(language), CheckoutState.threeDsRequired);
      }
    }
  }

  // ── Watching (README §13) ────────────────────────────────────────────────

  void _watch({bool pollNow = false}) {
    if (settled) return;
    if (_watcher?.running ?? false) {
      if (pollNow) _watcher!.pollNow();
      return;
    }
    final loaded = _session;
    if (loaded == null) return;
    _watcher = PaymentWatcher(
      client: session.client,
      token: session.token,
      language: language,
      realtime: RealtimeEndpoint.resolve(loaded),
      connector: _realtimeConnector,
      seenProcessing: _seenProcessing,
      cap: _attemptClock.isRunning ? PaymentWatcher.overallCap - _attemptClock.elapsed : null,
      onStatus: _onStatus,
      onDecision: _onDecision,
    )..start(pollNow: pollNow);
  }

  /// A status that did not decide. After a payment without an answer
  /// (README §2.5): a `pending` with a refusal code is that payment refused
  /// at once; a plain `pending` 60 s after its last try means it never
  /// arrived.
  void _onStatus(PaymentStatusUpdate update) {
    final status = update.status;
    if (status == null || settled) return;
    _transaction = _transaction?.copyWith(status: status);
    final code = update.errorCode;
    if (code != null) _lastErrorCode = code;
    if (status == 'processing' || status == 'partial') {
      _seenProcessing = true;
      _unansweredPath = null;
      return;
    }
    final path = _unansweredPath;
    if (path == null || _seenProcessing || status != 'pending') return;
    if (code != null && code != _errorCodeBeforeAttempt) {
      // A refusal of this very attempt, answered before the first read.
      _onDecision(WatchDecision(WatchVerdict.failed, update: update, error: attemptEndedError(update, language)));
    } else if ((session.client.sinceSent(path) ?? _neverArrivedAfter) >= _neverArrivedAfter) {
      _backToForm();
    }
  }

  void _onDecision(WatchDecision decision) {
    if (settled || _isFinal) return;
    final code = decision.update?.errorCode;
    if (code != null) _lastErrorCode = code;
    if (_completing && decision.verdict == WatchVerdict.failed && decision.update?.status == 'pending') {
      // The client session's completion is on its way: it decides.
      _deferredDecision = decision;
      return;
    }
    _watcher?.stop();
    final status = decision.update?.status;
    if (status != null) _transaction = _transaction?.copyWith(status: status);
    _unansweredPath = null;
    // An outcome, or a refusal: the attempt is decided (the cap is not).
    if (decision.verdict != WatchVerdict.capped) _acceptedUndecided = false;
    switch (decision.verdict) {
      case WatchVerdict.success:
        _succeed(_transaction ?? _session!.transaction, method: _family);
      case WatchVerdict.failed:
        _fail(decision.error!);
      case WatchVerdict.cancelled:
        _fail(decision.error!, state: CheckoutState.cancelled);
      case WatchVerdict.expired:
        _fail(decision.error!, state: CheckoutState.expired);
      case WatchVerdict.capped:
        _capped = true;
        _busy = false;
        _enter(CheckoutState.pending, CheckoutScreen.pending);
        notifyListeners();
    }
  }

  /// The app went to the background: a provider's page, a wallet app, the
  /// phone's approval prompt.
  void onAppPaused() => _leftApp = true;

  /// The app came back to the foreground: complete an open client session
  /// (on every return), otherwise read the status at once (README §12).
  Future<void> onAppResumed() async {
    if (settled) return;
    final returned = _leftApp;
    _leftApp = false;
    final clientSession = _clientSessionId;
    if (clientSession != null && returned) {
      await _completeClientSession(clientSession);
      return;
    }
    if (_watcher?.running ?? false) _watcher!.pollNow();
  }

  /// `POST /pay/client-session/complete` once the payer is back (README §11).
  Future<void> _completeClientSession(String id) async {
    final attempt = _attempt;
    if (!_completing) _deferredDecision = null;
    _completions++;
    var counted = true;
    void done() {
      if (counted) _completions--;
      counted = false;
    }

    try {
      final raw = await session.client.completeClientSession(session.token, id);
      done();
      if (settled || _closing) return;
      final transaction = raw.transaction;
      if (transaction?.status == 'succeeded') {
        // A success always wins, even over a refusal shown meanwhile.
        _succeed(transaction!, method: MethodFamily.card.wireName);
        return;
      }
      if (_stale(attempt)) return;
      if (transaction != null) _transaction = transaction;
      _resumeAfterCompletion();
    } on WajubError catch (e) {
      done();
      if (_stale(attempt)) return;
      final error = e.localized(language);
      if (error.httpStatus == 402 || error.code == 'client_session_expired') {
        if (error.httpStatus == 402) _lastErrorCode = error.declineCode ?? error.code;
        _pendingAgain();
        _clientSessionId = null;
        _deferredDecision = null;
        _fail(error);
      } else {
        _resumeAfterCompletion();
      }
    } finally {
      done();
    }
  }

  /// Not decided by the completion (not paid yet, or no answer): what the
  /// watch read meanwhile stands once no other completion runs, else it
  /// reads again now.
  void _resumeAfterCompletion() {
    if (_completing) return;
    final deferred = _deferredDecision;
    _deferredDecision = null;
    if (deferred != null) {
      _onDecision(deferred);
    } else if (_watcher?.running ?? false) {
      _watcher!.pollNow();
    } else {
      _watch(pollNow: true);
    }
  }

  // ── Outcomes ─────────────────────────────────────────────────────────────

  String get _family => _method?.family.wireName ?? 'unknown';

  void _paymentStarted(MethodFamily family, String channel) {
    _attemptStarted = true;
    if (_paymentStartedFired) return;
    _paymentStartedFired = true;
    final event = PaymentStartedEvent(method: family.wireName, channel: channel);
    _call(() => _callbacks.onPaymentStarted?.call(event));
  }

  void _succeed(SessionTransaction transaction, {required String method}) {
    if (settled || _isFinal) return;
    _attempt++;
    _watcher?.stop();
    _threeDsTimer?.cancel();
    _transaction = transaction;
    _clientSessionId = null;
    _unansweredKey = null;
    _unansweredPath = null;
    _inFlight = false;
    _attemptStarted = false;
    _busy = false;
    _payment = PaymentSuccess.from(transaction, method: method);
    _enter(CheckoutState.success, CheckoutScreen.success, method: method);
    final payment = _payment!;
    _call(() => _callbacks.onSuccess?.call(payment));
    if (options.autoCloseSuccess > Duration.zero) {
      _autoClose = Timer(options.autoCloseSuccess, close);
    }
  }

  void _fail(WajubError error, {CheckoutState state = CheckoutState.failed}) {
    if (settled || _isFinal) return;
    _attempt++;
    _watcher?.stop();
    _threeDsTimer?.cancel();
    _attemptStarted = false;
    _paymentStartedFired = false;
    _seenProcessing = false;
    _clientSessionId = null;
    _continueUrl = null;
    _unansweredKey = null;
    _unansweredPath = null;
    _busy = false;
    _inFlight = false;
    _error = error;
    _enter(state, CheckoutScreen.failed);
    _call(() => _callbacks.onError?.call(error));
  }

  /// "Try again" on a retryable failure: the same method's form, and a new
  /// `Idempotency-Key` on the next Pay.
  void tryAgain() {
    final error = _error;
    if (settled || _screen != CheckoutScreen.failed || error == null || !error.retryable || _endedAtLoad) return;
    final at = _retryAt;
    if (at != null && clock.now().isBefore(at)) return;
    _retryAt = null;
    _error = null;
    _clearMessages();
    final method = _method;
    if (method != null && method.enabled) {
      _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
    } else {
      _method = null;
      _enter(CheckoutState.initiated, CheckoutScreen.methods);
    }
  }

  // ── Closing (README §14, states.md §4–5) ─────────────────────────────────

  /// "Cancel payment": cancels it on Wajub, then closes.
  Future<void> cancelPayment() async {
    if (!canCancel || settled) return;
    _cancelling = true;
    _setBusy(true);
    try {
      final cancelled = await session.client.cancel(session.token);
      if (settled) return;
      _enter(CheckoutState.cancelled, _screen);
      _finish(CheckoutCancelled(reason: CancelReason.payerCancelled, redirectUrl: cancelled.redirectUrl),
          routeGone: _routeGone);
    } on WajubError catch (e) {
      if (settled) return;
      if (e.httpStatus == 400) {
        await _settleRefusedCancel();
        return;
      }
      // A failed call changes nothing for the payer: they leave.
      _enter(CheckoutState.cancelled, _screen);
      _finish(const CheckoutCancelled(reason: CancelReason.payerCancelled), routeGone: _routeGone);
    } finally {
      _cancelling = false;
      if (!settled) _setBusy(false);
    }
  }

  /// A cancel refused (`400`), or a retry refused after the first try went
  /// through: the status says how the payment stands (README §14, CN-04).
  Future<void> _settleRefusedCancel() async {
    PaymentStatusUpdate? update;
    try {
      update = await session.status();
    } on WajubError catch (_) {
      // Unreadable: the payment may be running.
    }
    if (settled) return;
    final status = update?.status;
    switch (status) {
      case 'cancelled':
        _enter(CheckoutState.cancelled, _screen);
        _finish(const CheckoutCancelled(reason: CancelReason.payerCancelled), routeGone: _routeGone);
      case 'succeeded' || 'refunded' || 'partially_refunded':
        _succeed((_transaction ?? _session!.transaction).copyWith(status: status), method: _family);
        _settleIfGone();
      case 'failed' || 'expired':
        _onDecision(decideStatus(update!, seenProcessing: false, language: language)!);
        _settleIfGone();
      case 'pending':
        _fail(WajubError.of('not_processable', language: language, httpStatus: 400));
        _settleIfGone();
      default:
        // `processing`, or nothing readable: money may move.
        _finish(CheckoutProcessing(transaction: _transaction), routeGone: _routeGone);
    }
  }

  /// The sheet's route went away while a cancel ran: settle with what the
  /// cancel left on screen, never hang.
  void _settleIfGone() {
    if (_routeGone) _finish(_resultNow(reason: CancelReason.dismissed), routeGone: true);
  }

  /// Close on an outcome screen, or the success screen's timer. On a
  /// failure, a payment still cancellable is cancelled as on a dismiss.
  void close() {
    if (settled || _cancelling || _closing) return;
    unawaited(_leave(_resultNow(reason: CancelReason.dismissed), routeGone: _routeGone));
  }

  /// The payer closed the sheet: the close button, a swipe down, back. A
  /// `pending` payment with no attempt undecided is cancelled on Wajub
  /// (unless `cancelOnDismiss` is off) — on a failure screen too, where the
  /// result stays `failed`; anything else is settled as it stands, without
  /// a call.
  Future<void> dismiss() async {
    if (settled || _closing) return;
    if (_cancelling) {
      // "Cancel payment" is on its way: its answer settles the sheet.
      _routeGone = true;
      return;
    }
    await _leave(_resultNow(reason: CancelReason.dismissed), routeGone: true);
  }

  /// Settles with [result], cancelling the payment on Wajub first when it
  /// is cancellable and `cancelOnDismiss` is on: before any attempt, or on
  /// the failure screen of a refused payment (`pending` again), where the
  /// result stays the failure the payer saw and releases the order.
  Future<void> _leave(CheckoutResult result, {required bool routeGone}) async {
    final releases = result is CheckoutFailed && _screen == CheckoutScreen.failed && !_endedAtLoad;
    final legacyKeeps = cancelOnlyBeforeSubmit && _submitted;
    if (legacyKeeps ||
        !((result is CheckoutCancelled || releases) && options.cancelOnDismiss && _mayCancel && !_isFinal)) {
      _finish(result, routeGone: routeGone);
      return;
    }
    _closing = true;
    notifyListeners();
    String? redirectUrl;
    try {
      redirectUrl = (await session.client.cancel(session.token)).redirectUrl;
    } catch (_) {
      // A failed cancel changes nothing for the payer.
    }
    _finish(
      result is CheckoutCancelled
          ? CheckoutCancelled(reason: CancelReason.dismissed, redirectUrl: redirectUrl)
          : result,
      routeGone: routeGone || _routeGone,
    );
  }

  /// The screen that presented the sheet went away: settle, never cancel.
  void hostGone() {
    // A cancel already on its way decides the result.
    if (settled || _closing) return;
    if (_cancelling) {
      _routeGone = true;
      return;
    }
    _finish(_resultNow(reason: CancelReason.hostGone), routeGone: true);
  }

  CheckoutResult _resultNow({required CancelReason reason}) {
    final payment = _payment;
    if (_state == CheckoutState.success && payment != null) {
      return CheckoutComplete(payment: payment, transaction: _transaction);
    }
    final error = _error;
    if (error != null && (_screen == CheckoutScreen.failed || _screen == CheckoutScreen.loadError)) {
      return CheckoutFailed(error: error, transaction: _transaction);
    }
    if (_attemptStarted || _inFlight) return CheckoutProcessing(transaction: _transaction);
    final loaded = _session;
    if (_screen == CheckoutScreen.loading && loaded != null) {
      // The session answered, the sheet is not drawn yet: its status decides.
      final transaction = loaded.transaction;
      switch (transaction.status.toLowerCase()) {
        case 'processing' || 'partial':
          return CheckoutProcessing(transaction: transaction);
        case 'succeeded' || 'refunded' || 'partially_refunded':
          return CheckoutComplete(
              payment: PaymentSuccess.from(transaction, method: 'unknown'), transaction: transaction);
        case 'failed' || 'cancelled' || 'expired':
          return CheckoutFailed(
            error: WajubError.of('session_terminal_${transaction.status.toLowerCase()}', language: language),
            transaction: transaction,
          );
      }
    }
    return CheckoutCancelled(reason: reason);
  }

  void _finish(CheckoutResult result, {bool routeGone = false}) {
    if (settled) return;
    _readyTimer?.cancel();
    _autoClose?.cancel();
    _threeDsTimer?.cancel();
    _watcher?.stop();
    _generation++;
    _settling = true;
    // The presenter is free and the sheet's route on its way out before the
    // callbacks run: onComplete may present the next sheet.
    onSettling?.call();
    if (!routeGone) onClose?.call();
    if (result is CheckoutCancelled) {
      final event = CancelEvent(reason: result.reason, redirectUrl: result.redirectUrl);
      _call(() => _callbacks.onCancel?.call(event));
    }
    _call(() => _callbacks.onComplete?.call(result));
    _result.complete(result);
    notifyListeners();
    final appKey = options.stripe.appPublishableKey;
    if (_stripeKeySet && appKey != null) {
      unawaited(Future.sync(() => _restoreStripeKey(appKey)).then((_) {}, onError: (Object _) {}));
    }
  }

  // ── Altcha (README §15) ──────────────────────────────────────────────────

  Future<int?>? _startAltcha(SessionData loaded) {
    final challenge = loaded.altcha;
    if (challenge == null) return null;
    // In the background, from the moment the form shows.
    return _solveAltcha(challenge).catchError((Object _) => null);
  }

  /// The challenge's solution for one request, or null when the API asks
  /// for none. A solution already sent is not sent again: a new session
  /// brings a new challenge first. Throws when there is no solution to send:
  /// a payment never leaves without one while Altcha is on.
  Future<Map<String, Object?>?> _altchaSolution() async {
    if (_session?.altcha == null) return null;
    if (_altchaUsed) {
      final SessionData reloaded;
      try {
        reloaded = await session.loadSession(forceRefresh: true);
      } on WajubError {
        throw WajubError.of('network_error', language: language);
      }
      _session = reloaded;
      _altcha = _startAltcha(reloaded);
      _altchaUsed = false;
    }
    final challenge = _session?.altcha;
    if (challenge == null) return null;
    final number = await (_altcha ??= _startAltcha(_session!))!;
    if (number == null) {
      // Unsolved: the next Pay fetches a new challenge rather than this one.
      _altcha = null;
      _altchaUsed = true;
      throw WajubError.of('security_check_failed', language: language);
    }
    _altchaUsed = true;
    return altchaPayload(challenge, number);
  }

  /// [_altchaSolution] for the attempt under way; null and the attempt
  /// failed (retryable) when there is none to send.
  Future<(Map<String, Object?>?,)?> _altchaFor(int attempt) async {
    try {
      return (await _altchaSolution(),);
    } on WajubError catch (e) {
      if (_stale(attempt)) return null;
      _fail(e);
      return null;
    }
  }

  /// A refused challenge: one new session (a new challenge) and `true` to
  /// submit again, then `security_check_failed` and `false`. Null when
  /// [error] is not about the challenge.
  Future<bool?> _retryAltcha(WajubError error) async {
    // Recognised by its code; an older answer had none and only its message
    // (`validation_error` then) told it apart.
    final isAltcha = error.httpStatus == 422 &&
        (error.code == 'security_check_failed' ||
            (error.code == 'validation_error' &&
                (error.details.containsKey('altcha') || (error.apiMessage ?? '').contains('Security challenge'))));
    if (!isAltcha) return null;
    if (_altchaReloaded) {
      _fail(WajubError.of('security_check_failed', language: language, httpStatus: 422));
      return false;
    }
    _altchaReloaded = true;
    try {
      final reloaded = await session.loadSession(forceRefresh: true);
      if (settled) return false;
      _session = reloaded;
      _altcha = _startAltcha(reloaded);
      _altchaUsed = false;
      return true;
    } on WajubError {
      _fail(WajubError.of('security_check_failed', language: language, httpStatus: 422));
      return false;
    }
  }

  static Future<int?> _solveInBackground(AltchaChallenge challenge) => compute(solveAltcha, challenge);

  // ── Plumbing ─────────────────────────────────────────────────────────────

  void _enter(CheckoutState state, CheckoutScreen screen, {String? method}) {
    _screen = screen;
    if (_state != state) {
      _state = state;
      final event = StateChangeEvent(state: state, method: method ?? _family);
      _call(() => _callbacks.onStateChange?.call(event));
    }
    notifyListeners();
  }

  void _setScreen(CheckoutScreen screen) {
    _screen = screen;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  /// A callback that throws must not break the sheet.
  void _call(void Function() callback) {
    try {
      callback();
    } catch (error) {
      debugPrint('wajub_mobile: a checkout callback threw: $error');
    }
  }

  static String? _reduce(String? locale) {
    if (locale == null || locale.trim().isEmpty) return null;
    return locale.toLowerCase().startsWith('fr') ? 'fr' : 'en';
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _readyTimer?.cancel();
    _autoClose?.cancel();
    _threeDsTimer?.cancel();
    _watcher?.stop();
    super.dispose();
  }
}
