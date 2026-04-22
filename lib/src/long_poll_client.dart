import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:long_poll_client/long_poll_client.dart' show HttpClientImpl;
import 'package:long_poll_client/src/http/http_client_impl.dart'
    show HttpClientImpl;

import 'package:long_poll_client/src/http/i_http_client.dart';
import 'package:long_poll_client/src/long_poll_config.dart';
import 'package:long_poll_client/src/long_poll_event.dart';
import 'package:long_poll_client/src/long_poll_exceptions.dart';

/// A production-ready long-polling client.
///
/// ### Usage
/// ```dart
/// final client = LongPollClient(
///   config: LongPollConfig(uri: Uri.parse('https://api.example.com/poll')),
///   httpClient: HttpClientImpl(),
/// );
///
/// client.events.listen((event) {
///   switch (event) {
///     case LongPollDataEvent(:final response):
///       print('New data: ${response.body}');
///     case LongPollErrorEvent(:final error):
///       print('Error: $error');
///     default:
///       break;
///   }
/// });
///
/// await client.start();
/// // ...later...
/// client.stop();
/// ```
///
/// ### Back-off Formula
/// When [LongPollConfig.useExponentialBackoff] is `true`, the delay before
/// each retry is:
///
/// $$d_n = \min(d_0 \times 2^{n-1},\ d_{\max})$$
///
/// where $d_0$ is [LongPollConfig.retryDelay], $n$ is the consecutive error
/// count, and $d_{\max}$ is [LongPollConfig.maxBackoffDelay].
final class LongPollClient {
  /// Creates a [LongPollClient].
  ///
  /// - [config]     : polling configuration.
  /// - [httpClient] : injectable HTTP transport (defaults to [HttpClientImpl]).
  LongPollClient({
    required LongPollConfig config,
    required IHttpClient httpClient,
    String? initialCursor,
  }) : _config = config,
       _httpClient = httpClient,
       _cursor = initialCursor;
  static final _log = Logger('LongPollClient');

  final LongPollConfig _config;
  final IHttpClient _httpClient;

  final StreamController<LongPollEvent> _controller =
      StreamController.broadcast();

  bool _running = false;
  bool _disposed = false;
  int _consecutiveErrors = 0;
  int _totalAttempts = 0;
  String? _cursor;

  /// Broadcast stream of [LongPollEvent]s.
  ///
  /// Multiple listeners are supported. The stream never closes on recoverable
  /// errors; it only closes after [stop] is called or
  /// [LongPollMaxErrorsExceededException] is thrown.
  Stream<LongPollEvent> get events => _controller.stream;

  /// Whether the client is currently polling.
  bool get isRunning => _running;

  /// The last cursor received from the server.
  String? get cursor => _cursor;

  /// Starts long-polling. Returns a [Future] that completes when polling stops
  /// (either via [stop] or a fatal error).
  ///
  /// Calling [start] while already running is a no-op.
  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _log.info('Long-poll client starting → ${_config.uri}');
    await _pollLoop();
  }

  /// Gracefully stops polling and closes the event stream.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _log.info('Long-poll client stopping.');
    _emit(const LongPollStoppedEvent());
    if (!_controller.isClosed) await _controller.close();
  }

  /// Releases all resources. Must be called when the client is no longer
  /// needed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_running) await stop();
    _httpClient.close();
  }

  Future<void> _pollLoop() async {
    while (_running) {
      try {
        _totalAttempts++;
        final effectiveUri = _buildUri();

        _emit(
          LongPollPollingEvent(
            attemptNumber: _totalAttempts,
            uri: effectiveUri,
          ),
        );

        _log.fine('Poll #$_totalAttempts → $effectiveUri');

        final response = await _httpClient.get(
          HttpRequest(
            uri: effectiveUri,
            headers: _config.headers,
            timeout: _config.httpTimeout,
          ),
        );

        await _handleResponse(response);
        _consecutiveErrors = 0; // reset on success
      } on LongPollTimeoutException catch (e, st) {
        // Timeouts are expected and fully recoverable.
        _log.fine('Poll timeout (normal): $e');
        await _handleError(e, st, recoverable: true);
      } on LongPollHttpException catch (e, st) {
        // 4xx (except 408/429) are unrecoverable.
        final recoverable = _isRecoverableStatus(e.statusCode);
        _log.warning('HTTP error ${e.statusCode}: $e', e, st);
        await _handleError(e, st, recoverable: recoverable);
        if (!recoverable) return;
      } on Object catch (e, st) {
        // Network errors, socket exceptions, etc. — always retry.
        _log.warning('Unexpected poll error: $e', e, st);
        await _handleError(e, st, recoverable: true);
      }
    }
  }

  Future<void> _handleResponse(HttpResponse response) async {
    if (response.statusCode == 204) {
      _log.fine('No new data (204).');
      _emit(const LongPollNoDataEvent());
      return;
    }

    if (!response.isSuccess) {
      throw LongPollHttpException(
        'Server returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    // Extract cursor from response headers if the server provides one.
    final nextCursor =
        response.headers['x-next-cursor'] ?? response.headers['x-poll-cursor'];

    if (nextCursor != null && nextCursor.isNotEmpty) {
      _cursor = nextCursor;
    }

    _log.fine('Received data (${response.statusCode}), cursor: $_cursor');
    _emit(LongPollDataEvent(response: response, nextCursor: _cursor));
  }

  Future<void> _handleError(
    Object error,
    StackTrace stackTrace, {
    required bool recoverable,
  }) async {
    if (!recoverable || !_running) return;

    _consecutiveErrors++;

    final max = _config.maxConsecutiveErrors;
    if (max != null && _consecutiveErrors >= max) {
      final fatal = LongPollMaxErrorsExceededException(
        'Exceeded $max consecutive errors. Last: $error',
        maxErrors: max,
      );
      _log.severe('Max consecutive errors exceeded.', fatal, stackTrace);
      _running = false;
      _controller.addError(fatal, stackTrace);
      await _controller.close();
      return;
    }

    final delay = _currentRetryDelay();

    _emit(
      LongPollErrorEvent(
        error: error,
        stackTrace: stackTrace,
        consecutiveErrors: _consecutiveErrors,
        retryDelay: delay,
      ),
    );

    _log.info(
      'Retrying in $delay '
      '(consecutive errors: $_consecutiveErrors)...',
    );

    await Future<void>.delayed(delay);
  }

  Uri _buildUri() {
    final cursorParam = _config.cursorQueryParam;
    if (cursorParam == null || _cursor == null) return _config.uri;

    final params = Map<String, String>.from(_config.uri.queryParameters)
      ..[cursorParam] = _cursor!;

    return _config.uri.replace(queryParameters: params);
  }

  Duration _currentRetryDelay() {
    if (!_config.useExponentialBackoff || _consecutiveErrors <= 1) {
      return _config.retryDelay;
    }

    // d_n = min(d0 * 2^(n-1), d_max)
    final factor = math.pow(2, _consecutiveErrors - 1).toDouble();
    final ms = (_config.retryDelay.inMilliseconds * factor).round();
    return Duration(
      milliseconds: math.min(ms, _config.maxBackoffDelay.inMilliseconds),
    );
  }

  /// Returns `true` for status codes that should trigger a retry.
  bool _isRecoverableStatus(int status) =>
      status == 408 || // Request Timeout
      status == 429 || // Too Many Requests
      status >= 500; // Server errors

  void _emit(LongPollEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }
}
