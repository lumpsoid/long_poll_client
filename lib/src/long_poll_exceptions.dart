import 'package:long_poll_client/long_poll_client.dart' show LongPollConfig;
import 'package:long_poll_client/src/long_poll_config.dart' show LongPollConfig;

/// Base class for all long-poll exceptions.
sealed class LongPollException implements Exception {
  const LongPollException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the HTTP request times out.
final class LongPollTimeoutException extends LongPollException {
  const LongPollTimeoutException(super.message);
}

/// Thrown when the server returns an unrecoverable HTTP error (e.g. 401, 403).
final class LongPollHttpException extends LongPollException {
  const LongPollHttpException(super.message, {required this.statusCode});
  final int statusCode;

  @override
  String toString() => 'LongPollHttpException($statusCode): $message';
}

/// Thrown when [LongPollConfig.maxConsecutiveErrors] is exceeded.
final class LongPollMaxErrorsExceededException extends LongPollException {
  const LongPollMaxErrorsExceededException(
    super.message, {
    required this.maxErrors,
  });
  final int maxErrors;
}
