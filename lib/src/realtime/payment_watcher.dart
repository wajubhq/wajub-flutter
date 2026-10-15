import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';

import '../client/pay_client.dart';
import '../errors/error_catalogue.dart';
import '../models/models.dart';
import '../models/wajub_error.dart';
import 'pusher_socket.dart';

/// How a watched payment ended.
enum WatchVerdict {
  success,
  failed,
  cancelled,
  expired,

  /// Still running when the watch's time ran out (15 minutes, or the
  /// session's `expires_at`): the merchant will be told.
  capped,
}

class WatchDecision {
  const WatchDecision(this.verdict, {this.update, this.error});

  final WatchVerdict verdict;

  /// The status answer or event that decided, when one did.
  final PaymentStatusUpdate? update;

  /// For [WatchVerdict.failed], [WatchVerdict.cancelled], [WatchVerdict.expired].
  final WajubError? error;
}

/// What one status says about the attempt (spec README §13.2), or null to
/// keep watching. A `pending` counts only once the attempt was seen
/// `processing`: before that it is the previous attempt's leftover. An answer
/// without a status says nothing.
WatchDecision? decideStatus(PaymentStatusUpdate update, {required bool seenProcessing, String language = 'en'}) {
  switch (update.status) {
    case 'succeeded' || 'refunded' || 'partially_refunded':
      return WatchDecision(WatchVerdict.success, update: update);
    case 'failed':
      return WatchDecision(WatchVerdict.failed,
          update: update, error: WajubError.of('payment_failed', language: language));
    case 'cancelled':
      return WatchDecision(
        WatchVerdict.cancelled,
        update: update,
        error: WajubError.of('payment_cancelled', language: language),
      );
    case 'expired':
      return WatchDecision(WatchVerdict.expired,
          update: update, error: WajubError.of('session_expired', language: language));
    case 'pending' when seenProcessing:
      return WatchDecision(WatchVerdict.failed, update: update, error: attemptEndedError(update, language));
  }
  return null;
}

/// The attempt went back to `pending` without charging: the refusal's own
/// code when the API gave one, `payment_attempt_ended` otherwise.
WajubError attemptEndedError(PaymentStatusUpdate update, String language) {
  final code = update.errorCode;
  if (code == null) return WajubError.of('payment_attempt_ended', language: language);
  final entry = ErrorCatalogue.lookup(code);
  return WajubError(
    type: entry?.type ?? WajubErrorType.paymentError,
    message: entry != null
        ? ErrorCatalogue.text(entry, language)
        : language != 'fr' && update.payerMessage != null
            ? update.payerMessage!
            : ErrorCatalogue.text(ErrorCatalogue.declineFallback, language),
    code: code,
    declineCode: code,
    retryable: entry?.retryable ?? true,
    apiMessage: update.payerMessage,
  );
}

/// Follows one payment attempt to its outcome (spec README §13): polls
/// `GET /pay/status` — every 5 s, slowing ×1.5 up to 15 s after 2 minutes
/// without a change, every 15 s while the realtime socket is joined, backing
/// off on errors — and listens to the payment's channel when the session has
/// one. Stops by itself on an outcome, and on [stop].
class PaymentWatcher {
  PaymentWatcher({
    required PayClient client,
    required String token,
    required this.onDecision,
    this.onStatus,
    this.realtime,
    this.seenProcessing = false,
    Duration? cap,
    bool capped = true,
    RealtimeConnector? connector,
    Random? random,
    this.language = 'en',
    this.interval = defaultInterval,
  })  : _client = client,
        _token = token,
        _cap = capped ? cap ?? overallCap : null,
        _connector = connector,
        _random = random ?? Random();

  static const defaultInterval = Duration(seconds: 5);
  static const slowAfter = Duration(minutes: 2);
  static const maxInterval = Duration(seconds: 15);
  static const withSocket = Duration(seconds: 15);
  static const errorBase = Duration(seconds: 5);
  static const errorMax = Duration(seconds: 60);
  static const overallCap = Duration(minutes: 15);

  final PayClient _client;
  final String _token;

  /// How long the watch may still run, counted by a timer (the device's
  /// monotonic time, never its wall clock or a server timestamp). Null: no
  /// cap (the 1.5 `watchStatus` stream watches until an outcome).
  final Duration? _cap;
  final RealtimeConnector? _connector;
  final Random _random;

  /// Called once, with the outcome.
  final void Function(WatchDecision decision) onDecision;

  /// Every status read or heard that did not decide.
  final void Function(PaymentStatusUpdate update)? onStatus;
  final RealtimeEndpoint? realtime;
  final String language;

  /// The polling interval while nothing slows it down.
  final Duration interval;

  /// Whether this attempt was seen `processing` (its 2xx, or a status).
  bool seenProcessing;

  PusherSocket? _socket;
  Timer? _timer;
  DateTime? _nextPoll;
  Timer? _capTimer;
  var _running = false;
  var _polling = false;
  var _failures = 0;
  late var _current = interval;
  late DateTime _lastChange;

  /// The status as last known: `processing` once the attempt was seen so,
  /// so that reading it again is no change.
  late String? _lastStatus = seenProcessing ? 'processing' : null;

  bool get running => _running;

  /// Starts watching; [pollNow] reads the status at once (a restored
  /// session, the payer back from a browser) instead of after an interval.
  void start({bool pollNow = false}) {
    if (_running) return;
    _running = true;
    _lastChange = clock.now();
    final left = _cap;
    if (left != null) {
      if (left <= Duration.zero) {
        _decide(const WatchDecision(WatchVerdict.capped));
        return;
      }
      _capTimer = Timer(left, () => _decide(const WatchDecision(WatchVerdict.capped)));
    }
    final endpoint = realtime;
    if (endpoint != null) {
      _socket = PusherSocket(
        endpoint: endpoint,
        connector: _connector,
        authorize: (socketId, channel) => _client.authorizeChannel(_token, socketId, channel),
        onEvent: _onEvent,
        onSubscribed: (joined) {
          // A lost socket brings the next read forward to the normal pace;
          // a joined one stretches the reads after the next.
          if (!joined && !_polling) _scheduleAtMost(_nextDelay());
        },
      )..start();
    }
    if (pollNow) {
      unawaited(_poll());
    } else {
      _schedule(interval);
    }
  }

  /// Reads the status now (the app came back to the foreground).
  void pollNow() {
    if (!_running || _polling) return;
    _timer?.cancel();
    unawaited(_poll());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _capTimer?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(socket?.stop());
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_running) return;
    _nextPoll = clock.now().add(delay);
    _timer = Timer(delay, () => unawaited(_poll()));
  }

  /// [_schedule], only when it reads sooner than planned.
  void _scheduleAtMost(Duration delay) {
    final planned = _nextPoll;
    if (planned != null && !clock.now().add(delay).isBefore(planned)) return;
    _schedule(delay);
  }

  Future<void> _poll() async {
    if (!_running) return;
    _polling = true;
    Duration next;
    try {
      final update = await _client.getStatus(_token);
      if (!_running) return;
      _failures = 0;
      if (_see(update)) return;
      next = _nextDelay();
    } on WajubError catch (error) {
      if (!_running) return;
      // An ended or unknown session decides on its status, whatever code
      // the API gives it.
      final status = error.httpStatus;
      if (status == 410 || error.code == 'session_terminal_expired') {
        _decide(WatchDecision(
          WatchVerdict.expired,
          error: WajubError.of('session_terminal_expired', language: language, httpStatus: status),
        ));
        return;
      }
      if (status == 401 || status == 403 || status == 404 || error.code == 'session_not_found') {
        _decide(WatchDecision(
          WatchVerdict.failed,
          error: WajubError.of('session_not_found', language: language, httpStatus: status),
        ));
        return;
      }
      if (error.code == 'rate_limited' && error.retryAfterSeconds != null) {
        next = Duration(seconds: error.retryAfterSeconds!);
      } else {
        _failures++;
        next = _errorDelay();
      }
    } finally {
      _polling = false;
    }
    _schedule(next);
  }

  void _onEvent(String event, Map<String, dynamic> data) {
    if (!_running || event != 'PaymentStatusUpdated') return;
    _see(PaymentStatusUpdate.fromJson(data));
  }

  /// True when [update] ended the watch.
  bool _see(PaymentStatusUpdate update) {
    // An answer or an event without a status: nothing to go on.
    if (update.status == null) return false;
    if (update.status != _lastStatus) {
      _lastStatus = update.status;
      _lastChange = clock.now();
      _current = interval;
    }
    final decision = decideStatus(update, seenProcessing: seenProcessing, language: language);
    if (decision != null) {
      _decide(decision);
      return true;
    }
    if (update.status == 'processing' || update.status == 'partial') seenProcessing = true;
    onStatus?.call(update);
    return false;
  }

  void _decide(WatchDecision decision) {
    if (!_running) return;
    stop();
    onDecision(decision);
  }

  Duration _nextDelay() {
    if (_socket?.subscribed ?? false) return withSocket;
    if (clock.now().difference(_lastChange) >= slowAfter) {
      final slower = _current * 1.5;
      _current = slower > maxInterval ? maxInterval : slower;
      return _current < interval ? interval : _current;
    }
    return interval;
  }

  /// `min(5 s × 2^n, 60 s) ± 20 %`, n the consecutive failures.
  Duration _errorDelay() {
    final base = min(errorBase.inMilliseconds * pow(2, _failures), errorMax.inMilliseconds).toDouble();
    return Duration(milliseconds: (base * (1 + (_random.nextDouble() * 0.4 - 0.2))).round());
  }
}
