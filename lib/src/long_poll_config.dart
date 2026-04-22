import 'package:long_poll_client/long_poll_client.dart'
    show IHttpClient, LongPollClient;

/// Immutable configuration for [LongPollClient].
final class LongPollConfig {
  const LongPollConfig({
    required this.uri,
    this.headers = const {},
    this.serverHoldTimeout = const Duration(seconds: 25),
    this.clientTimeoutBuffer = const Duration(seconds: 5),
    this.retryDelay = const Duration(seconds: 1),
    this.maxConsecutiveErrors,
    this.maxBackoffDelay = const Duration(seconds: 30),
    this.useExponentialBackoff = true,
    this.cursorQueryParam,
  });

  /// The endpoint to poll.
  final Uri uri;

  /// Headers sent with every request (e.g. Authorization).
  final Map<String, String> headers;

  /// How long the server is expected to hold the connection open.
  /// Should be slightly less than the server-side timeout.
  final Duration serverHoldTimeout;

  /// Extra buffer added on top of [serverHoldTimeout] for the client-side
  /// HTTP timeout, to avoid a race between server and client timeouts.
  final Duration clientTimeoutBuffer;

  /// Delay before retrying after a recoverable error.
  final Duration retryDelay;

  /// Maximum number of consecutive errors before the stream closes with an
  /// error. Set to `null` for unlimited retries.
  final int? maxConsecutiveErrors;

  /// Maximum back-off delay when using exponential back-off.
  final Duration maxBackoffDelay;

  /// Whether to use exponential back-off on repeated errors.
  final bool useExponentialBackoff;

  /// Optional query parameter name used to pass the last-event token/cursor
  /// to the server (e.g. `"lastEventId"`).
  final String? cursorQueryParam;

  /// The total timeout passed to [IHttpClient] per request.
  Duration get httpTimeout => serverHoldTimeout + clientTimeoutBuffer;

  LongPollConfig copyWith({
    Uri? uri,
    Map<String, String>? headers,
    Duration? serverHoldTimeout,
    Duration? clientTimeoutBuffer,
    Duration? retryDelay,
    int? maxConsecutiveErrors,
    Duration? maxBackoffDelay,
    bool? useExponentialBackoff,
    String? cursorQueryParam,
  }) {
    return LongPollConfig(
      uri: uri ?? this.uri,
      headers: headers ?? this.headers,
      serverHoldTimeout: serverHoldTimeout ?? this.serverHoldTimeout,
      clientTimeoutBuffer: clientTimeoutBuffer ?? this.clientTimeoutBuffer,
      retryDelay: retryDelay ?? this.retryDelay,
      maxConsecutiveErrors: maxConsecutiveErrors ?? this.maxConsecutiveErrors,
      maxBackoffDelay: maxBackoffDelay ?? this.maxBackoffDelay,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      cursorQueryParam: cursorQueryParam ?? this.cursorQueryParam,
    );
  }

  @override
  String toString() =>
      'LongPollConfig(uri: $uri, '
      'serverHoldTimeout: $serverHoldTimeout, '
      'retryDelay: $retryDelay, '
      'maxConsecutiveErrors: $maxConsecutiveErrors)';
}
