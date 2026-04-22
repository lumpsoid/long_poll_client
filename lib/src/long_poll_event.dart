import 'package:long_poll_client/long_poll_client.dart' show LongPollClient;
import 'package:long_poll_client/src/http/i_http_client.dart';
import 'package:long_poll_client/src/long_poll_client.dart' show LongPollClient;

/// Sealed base type for all events emitted by [LongPollClient].
sealed class LongPollEvent {
  const LongPollEvent();
}

/// Emitted when the server returns a successful, non-empty response.
final class LongPollDataEvent extends LongPollEvent {
  const LongPollDataEvent({required this.response, this.nextCursor});
  final HttpResponse response;

  /// The cursor/token extracted from the response, if available.
  /// Sent to the server on the next poll request.
  final String? nextCursor;

  @override
  String toString() =>
      'LongPollDataEvent(status: ${response.statusCode}, '
      'cursor: $nextCursor)';
}

/// Emitted when the server returns a 204 No Content (no new data).
final class LongPollNoDataEvent extends LongPollEvent {
  const LongPollNoDataEvent();

  @override
  String toString() => 'LongPollNoDataEvent()';
}

/// Emitted each time the client starts a new poll cycle.
final class LongPollPollingEvent extends LongPollEvent {
  const LongPollPollingEvent({
    required this.attemptNumber,
    required this.uri,
  });
  final int attemptNumber;
  final Uri uri;

  @override
  String toString() =>
      'LongPollPollingEvent(attempt: $attemptNumber, uri: $uri)';
}

/// Emitted on a recoverable error. Polling will continue after [retryDelay].
final class LongPollErrorEvent extends LongPollEvent {
  const LongPollErrorEvent({
    required this.error,
    required this.stackTrace,
    required this.consecutiveErrors,
    required this.retryDelay,
  });
  final Object error;
  final StackTrace stackTrace;
  final int consecutiveErrors;
  final Duration retryDelay;

  @override
  String toString() =>
      'LongPollErrorEvent(error: $error, '
      'consecutiveErrors: $consecutiveErrors, '
      'retryIn: $retryDelay)';
}

/// Emitted when polling is intentionally stopped via [LongPollClient.stop].
final class LongPollStoppedEvent extends LongPollEvent {
  const LongPollStoppedEvent();

  @override
  String toString() => 'LongPollStoppedEvent()';
}
