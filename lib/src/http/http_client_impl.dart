import 'package:http/http.dart' as http;

import 'package:long_poll_client/src/http/i_http_client.dart';
import 'package:long_poll_client/src/long_poll_exceptions.dart';

/// Concrete [IHttpClient] backed by the `http` package's [http.Client].
///
/// Supports optional injection of a custom [http.Client] instance,
/// which is useful for testing (e.g. [MockClient]) or custom configurations
/// such as a pinned certificate client.
final class HttpClientImpl implements IHttpClient {
  HttpClientImpl({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  Future<HttpResponse> get(HttpRequest request) async {
    final response = await _client
        .get(request.uri, headers: request.headers)
        .timeout(
          request.timeout,
          onTimeout: () => throw LongPollTimeoutException(
            'HTTP GET timed out after ${request.timeout.inSeconds}s '
            'for ${request.uri}',
          ),
        );

    return HttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
    );
  }

  @override
  void close() => _client.close();
}
