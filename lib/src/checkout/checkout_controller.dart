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
  })  : _openUrl = openUrl ?? HostedRedirect.open,
        _loadMobileMoneyData = mobileMoneyData ?? MobileMoneyData.load,
        _solveAltcha = altchaSolver ?? _solveInBackground,
        _realtimeConnector = realtimeConnector,
        _deviceLanguage = deviceLanguage ?? PlatformDispatcher.instance.locale.languageCode;

  final WajubSession session;
  final PresentOptions options;
  final Future<bool> Function(String url) _openUrl;
  final Future<MobileMoneyData> Function() _loadMobileMoneyData;
  final Future<int?> Function(AltchaChallenge challenge) _solveAltcha;
  final RealtimeConnector? _realtimeConnector;
  final String _deviceLanguage;

  CheckoutCallbacks get _callbacks => options.callbacks;

  /// Called when the sheet must close (an outcome, Cancel payment, Close).
  VoidCallback? onClose;

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
  bool get settled => _result.isCompleted;

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
  var _paymentStartedFired = false;
  bool _seenProcessing = false;
  String? _clientSessionId;
  var _awayInBrowser = false;
  Future<int?>? _altcha;
  var _altchaReloaded = false;
  var _closing = false;

  /// "Cancel payment" is offered while no attempt is in flight.
  bool get canCancel =>
      !_attemptStarted &&
      !_inFlight &&
      !_isFinal &&
      (_screen == CheckoutScreen.methods ||
          _screen == CheckoutScreen.form ||
          (_screen == CheckoutScreen.failed && !_endedAtLoad && (_error?.retryable ?? false)));

  /// The form can go back to the method list.
  bool get canGoBack => _screen == CheckoutScreen.form && !_busy && _methods.where((m) => m.enabled).length > 1;

  bool get _isFinal => const {CheckoutState.success, CheckoutState.expired, CheckoutState.cancelled}.contains(_state);

  /// [attempt] is no longer the one under way, or the sheet has settled.
  bool _stale(int attempt) => settled || attempt != _attempt;

  // ── Loading (README §4) ──────────────────────────────────────────────────

  /// Loads the session and sdk-config in parallel, then shows the first
  /// screen. Called once by the sheet, and again by Retry.
  Future<void> load() async {
    final generation = ++_generation;
    session.language = language;
    _ready = false;
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
    final configLoad = session.getSdkConfig().then<SdkConfig?>((c) => c, onError: (Object _) => null);
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
    final config = await configLoad;
    final data = await dataLoad;
    if (generation != _generation || settled) return;
    _readyTimer?.cancel();
    _session = loaded;
    _sdkConfig = config;
    _mobileMoneyData = data;
    _transaction = loaded.transaction;
    session.language = language;
    _error = null;
    _start(loaded);
  }

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
    // One load error per load: a failure before the timer ends it.
    _readyTimer?.cancel();
    _error = error;
    _setScreen(CheckoutScreen.loadError);
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
          _loadError(WajubError.of('no_payment_method', language: language));
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
    _call(() => _callbacks.onLoadError?.call(_error!));
  }

  /// A payment already in progress when the sheet opened (README §4.2).
  void _restore(SessionTransaction transaction) {
    final context = transaction.processingContext;
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
    // The stripe flavour is only offered with a publishable key.
    final key = method.config!.publishableKey!;
    final attempt = ++_attempt;
    _setBusy(true);
    _enter(CheckoutState.processing, CheckoutScreen.form);
    String paymentMethodId;
    try {
      await StripeAdapter.ensureInitialized(key);
      paymentMethodId = await StripeAdapter.createPaymentMethod(cardholderName: _cardFields['card_holder']);
    } catch (e) {
      if (_stale(attempt)) return;
      _setBusy(false);
      // Stripe's own refusal, or the plugin failing (its setup in the app).
      _banner = e is WajubError ? e.message : ErrorCatalogue.text(ErrorCatalogue.lookup('request_failed')!, language);
      _enter(CheckoutState.collectingDetails, CheckoutScreen.form);
      return;
    }
    if (_stale(attempt)) return;
    _setBusy(false);
    await _process(
      method.channel.slug,
      buildStripeCardRequest(paymentMethodId: paymentMethodId, cardholderName: _cardFields['card_holder']),
      MethodFamily.card,
    );
  }

  Future<void> _process(String channel, Map<String, dynamic> data, MethodFamily family) async {
    if (_inFlight || settled) return;
    if (!(_session?.transaction.sandbox ?? false) && _carriesCardData(data)) {
      // The API refuses raw card data in live (README §7); never send it.
      _fail(WajubError.of('raw_card_data_not_accepted', language: language));
      return;
    }
    final attempt = ++_attempt;
    _inFlight = true;
    _clearMessages();
    _setBusy(true);
    _enter(CheckoutState.processing, CheckoutScreen.form);
    // One key per press of Pay, reused only by the client's own retries.
    final key = uuidV4();
    final body = {
      ...data,
      if (options.returnUrl != null) 'return_url': options.returnUrl,
    };
    try {
      final altcha = await _altchaSolution();
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
      // Still busy while a refused challenge is renewed.
      final retry = await _retryAltcha(e);
      if (_stale(attempt)) return;
      _inFlight = false;
      _setBusy(false);
      switch (retry) {
        case true:
          await _process(channel, data, family);
        case null:
          await _onRefusal(e, family, channel);
        case false:
          break;
      }
    }
  }

  static bool _carriesCardData(Map<String, dynamic> data) =>
      const {'card.number', 'card_number', 'number', 'cvv', 'cvc', 'pin'}.any(data.containsKey);

  Future<void> _startClientSession(CheckoutMethod method, Map<String, String> fields) async {
    if (_inFlight || settled) return;
    final attempt = ++_attempt;
    _inFlight = true;
    _clearMessages();
    _setBusy(true);
    _enter(CheckoutState.processing, CheckoutScreen.form);
    try {
      final altcha = await _altchaSolution();
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
      _inFlight = false;
      _setBusy(false);
      switch (retry) {
        case true:
          await _startClientSession(method, fields);
        case null:
          await _onRefusal(e, MethodFamily.card, method.channel.slug);
        case false:
          break;
      }
    }
  }

  /// A 2xx of `/pay/process` or `/pay/client-session` (README §9).
  void _onAnswer(RawProcessResponse raw, MethodFamily family, String channel) {
    _paymentStarted(family, channel);
    final transaction = raw.transaction;
    if (transaction != null) _transaction = transaction;
    if (raw.httpStatus == 202 || const {'processing', 'partial'}.contains(transaction?.status)) {
      _seenProcessing = true;
    }
    _handle(PaymentMapper.mapProcessResponse(raw, family.wireName));
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
    if (opened) {
      _awayInBrowser = true;
    } else {
      _fail(WajubError.of('redirect_unavailable', language: language));
    }
  }

  /// "Continue payment": the same page again.
  Future<void> continuePayment() async {
    final url = _continueUrl;
    if (url == null || settled) return;
    await _redirect(
        url, _state == CheckoutState.threeDsRequired ? CheckoutState.threeDsRequired : CheckoutState.pending);
  }

  /// A refusal of `/pay/process` or `/pay/client-session` (README §9).
  Future<void> _onRefusal(WajubError e, MethodFamily family, String channel) async {
    final error = e.localized(language);
    final status = error.httpStatus;
    if (status == null || status >= 500 || error.code == 'server_error' || error.code == 'timeout') {
      // No answer: the charge may be running. Never a failure — watch.
      _attemptStarted = true;
      _enter(CheckoutState.pending, CheckoutScreen.pending);
      _watch(pollNow: true);
      return;
    }
    switch (status) {
      case 400:
        await _settleFromStatus(fallback: error);
      case 409 when error.code == 'payment_in_progress':
        _paymentStarted(family, channel);
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

  /// A 400, or a refused cancel: the status says how the payment ended
  /// ([known] when it was already read).
  Future<void> _settleFromStatus({required WajubError fallback, PaymentStatusUpdate? known}) async {
    final attempt = _attempt;
    var update = known;
    if (update == null) {
      try {
        update = await session.status();
      } on WajubError catch (_) {
        // Unreadable: the payment cannot go on from here.
      }
      if (_stale(attempt)) return;
    }
    if (update != null) {
      final decision = decideStatus(update, seenProcessing: false, language: language);
      if (decision != null) {
        _onDecision(decision);
        return;
      }
      if (update.status == 'processing' || update.status == 'partial') {
        // An attempt is running: follow it.
        _attemptStarted = true;
        _seenProcessing = true;
        _enter(CheckoutState.pending, CheckoutScreen.pending);
        _watch(pollNow: true);
        return;
      }
    }
    _fail(WajubError.of('not_processable', language: language, httpStatus: 400, apiMessage: fallback.apiMessage));
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
    if (kind == null || id == null || _busy || settled) return;
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
        switch (transaction?.status) {
          case 'succeeded':
            _succeed(transaction!, method: _family);
          case 'failed':
            _fail(WajubError.of('payment_failed', language: language));
          default:
            // A provider may chain steps the API cannot show yet: wait.
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
    if (id == null || _busy || settled || _screen != CheckoutScreen.threeDs) return;
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
    final expiresAt = DateTime.tryParse(loaded.transaction.expiresAt ?? '');
    final cap = clock.now().add(PaymentWatcher.overallCap);
    _watcher = PaymentWatcher(
      client: session.client,
      token: session.token,
      language: language,
      realtime: RealtimeEndpoint.resolve(loaded, options.realtime),
      connector: _realtimeConnector,
      seenProcessing: _seenProcessing,
      // A past `expires_at` is the device's clock being off: keep the cap.
      deadline: expiresAt != null && expiresAt.isBefore(cap) && expiresAt.isAfter(clock.now()) ? expiresAt : cap,
      onStatus: (update) {
        if (update.status == 'processing' || update.status == 'partial') _seenProcessing = true;
        _transaction = _transaction?.copyWith(status: update.status);
      },
      onDecision: _onDecision,
    )..start(pollNow: pollNow);
  }

  void _onDecision(WatchDecision decision) {
    if (settled || _isFinal) return;
    _watcher?.stop();
    final status = decision.update?.status;
    if (status != null) _transaction = _transaction?.copyWith(status: status);
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

  /// The app came back to the foreground — from the browser, a wallet app,
  /// the phone's approval prompt: read the status at once (README §12).
  Future<void> onAppResumed() async {
    if (settled) return;
    final clientSession = _clientSessionId;
    final wasAway = _awayInBrowser;
    _awayInBrowser = false;
    if (clientSession != null && wasAway) {
      await _completeClientSession(clientSession);
      return;
    }
    if (_watcher?.running ?? false) _watcher!.pollNow();
  }

  /// `POST /pay/client-session/complete` once the payer is back (README §11).
  Future<void> _completeClientSession(String id) async {
    final attempt = _attempt;
    try {
      final raw = await session.client.completeClientSession(session.token, id);
      if (_stale(attempt)) return;
      final transaction = raw.transaction;
      if (transaction != null) _transaction = transaction;
      if (transaction?.status == 'succeeded') {
        _succeed(transaction!, method: MethodFamily.card.wireName);
      } else {
        // Not paid yet: the PSP's webhook settles it.
        _watcher?.pollNow();
      }
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      final error = e.localized(language);
      if (error.httpStatus == 402 || error.code == 'client_session_expired') {
        _clientSessionId = null;
        _fail(error);
      } else {
        _watcher?.pollNow();
      }
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
    final attempt = _attempt;
    _setBusy(true);
    try {
      final cancelled = await session.client.cancel(session.token);
      if (_stale(attempt)) return;
      _enter(CheckoutState.cancelled, _screen);
      _finish(CheckoutCancelled(reason: CancelReason.payerCancelled, redirectUrl: cancelled.redirectUrl));
    } on WajubError catch (e) {
      if (_stale(attempt)) return;
      _setBusy(false);
      if (e.httpStatus == 400) {
        // Refused — or a retry refused after the first try went through.
        PaymentStatusUpdate? update;
        try {
          update = await session.status();
        } on WajubError catch (_) {
          // Unreadable: decided below as a payment that cannot go on.
        }
        if (_stale(attempt)) return;
        if (update?.status == 'cancelled') {
          _enter(CheckoutState.cancelled, _screen);
          _finish(const CheckoutCancelled(reason: CancelReason.payerCancelled));
          return;
        }
        await _settleFromStatus(fallback: e, known: update);
        return;
      }
      _enter(CheckoutState.cancelled, _screen);
      _finish(const CheckoutCancelled(reason: CancelReason.payerCancelled));
    }
  }

  /// Close on an outcome screen, or the success screen's timer.
  void close() {
    if (settled) return;
    _finish(_resultNow(reason: CancelReason.dismissed));
  }

  /// The payer closed the sheet: the close button, a swipe down, back.
  /// Before any attempt the payment is cancelled on Wajub (unless
  /// `cancelOnDismiss` is off); after one, nothing is called.
  Future<void> dismiss() async {
    if (settled || _closing) return;
    final result = _resultNow(reason: CancelReason.dismissed);
    if (result is CheckoutCancelled && options.cancelOnDismiss && _session != null && !_isFinal) {
      _closing = true;
      String? redirectUrl;
      try {
        redirectUrl = (await session.client.cancel(session.token)).redirectUrl;
      } catch (_) {
        // A failed cancel changes nothing for the payer.
      }
      _finish(CheckoutCancelled(reason: CancelReason.dismissed, redirectUrl: redirectUrl), routeGone: true);
      return;
    }
    _finish(result, routeGone: true);
  }

  /// The screen that presented the sheet went away: settle, never cancel.
  void hostGone() {
    // A dismiss already on its way (its cancel call) decides the result.
    if (settled || _closing) return;
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
    return CheckoutCancelled(reason: reason);
  }

  void _finish(CheckoutResult result, {bool routeGone = false}) {
    if (settled) return;
    _readyTimer?.cancel();
    _autoClose?.cancel();
    _threeDsTimer?.cancel();
    _watcher?.stop();
    _generation++;
    if (result is CheckoutCancelled) {
      final event = CancelEvent(reason: result.reason, redirectUrl: result.redirectUrl);
      _call(() => _callbacks.onCancel?.call(event));
    }
    _call(() => _callbacks.onComplete?.call(result));
    _result.complete(result);
    if (!routeGone) onClose?.call();
    notifyListeners();
  }

  // ── Altcha (README §15) ──────────────────────────────────────────────────

  Future<int?>? _startAltcha(SessionData loaded) {
    final challenge = loaded.altcha;
    if (challenge == null) return null;
    // In the background, from the moment the form shows.
    return _solveAltcha(challenge).catchError((Object _) => null);
  }

  Future<Map<String, Object?>?> _altchaSolution() async {
    final challenge = _session?.altcha;
    if (challenge == null) return null;
    final number = await (_altcha ??= _startAltcha(_session!))!;
    return number == null ? null : altchaPayload(challenge, number);
  }

  /// A refused challenge: one new session (a new challenge) and `true` to
  /// submit again, then `security_check_failed` and `false`. Null when
  /// [error] is not about the challenge.
  Future<bool?> _retryAltcha(WajubError error) async {
    final isAltcha = error.httpStatus == 422 &&
        (error.details.containsKey('altcha') || (error.apiMessage ?? '').contains('Security challenge'));
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
