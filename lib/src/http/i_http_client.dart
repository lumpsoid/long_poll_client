import 'dart:typed_data';

/// Represents an HTTP response returned by [IHttpClient].
class HttpResponse {
  const HttpResponse({
    required this.statusCode,
    required this.body,
    required this.bodyBytes,
    required this.headers,
  });
  final int statusCode;
  final String body;
  final Uint8List bodyBytes;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'HttpResponse(statusCode: $statusCode, body: $body)';
}

/// Represents an HTTP request sent through [IHttpClient].
class HttpRequest {
  const HttpRequest({
    required this.uri,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
  });
  final Uri uri;
  final Map<String, String> headers;
  final Duration timeout;
}

/// Abstract HTTP client interface.
///
/// Decouples the long-poll engine from any concrete HTTP implementation,
/// enabling easy mocking, testing, and swapping of transports.
abstract interface class IHttpClient {
  const IHttpClient();

  /// Performs an HTTP GET request.
  Future<HttpResponse> get(HttpRequest request);

  /// Releases any resources held by this client.
  void close();
}
