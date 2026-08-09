enum RealtimeEventType {
  paymentConfirmed,
  paymentFailed,
  sessionExpired,
  statusUpdate,
}

class RealtimeEvent {
  const RealtimeEvent({required this.type, this.status, this.message});

  final RealtimeEventType type;
  final String? status;
  final String? message;

  bool get isTerminal =>
      type == RealtimeEventType.paymentConfirmed ||
      type == RealtimeEventType.paymentFailed ||
      type == RealtimeEventType.sessionExpired;
}
