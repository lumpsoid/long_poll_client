import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:long_poll_client/long_poll_client.dart';
import 'package:test/test.dart';

HttpClientImpl _mockHttpClient(MockClientHandler handler) =>
    HttpClientImpl(client: MockClient(handler));

void main() {
  final baseUri = Uri.parse('https://api.example.com/poll');

  group('LongPollClient', () {
    test('emits LongPollDataEvent on 200 response', () async {
      final httpClient = _mockHttpClient(
        (_) async => http.Response(
          '{"msg":"hello"}',
          200,
          headers: {'x-next-cursor': 'abc'},
        ),
      );

      final client = LongPollClient(
        config: LongPollConfig(
          uri: baseUri,
          maxConsecutiveErrors: 1,
          retryDelay: Duration.zero,
        ),
        httpClient: httpClient,
      );

      final events = <LongPollEvent>[];
      final completer = Completer<void>();

      client.events.listen((e) {
        events.add(e);
        if (e is LongPollDataEvent) {
          client.stop();
          completer.complete();
        }
      });

      unawaited(client.start());
      await completer.future.timeout(const Duration(seconds: 5));

      expect(events.whereType<LongPollDataEvent>(), isNotEmpty);
      final dataEvent = events.whereType<LongPollDataEvent>().first;
      expect(dataEvent.response.body, '{"msg":"hello"}');
      expect(dataEvent.nextCursor, 'abc');

      client.dispose();
    });

    test('emits LongPollNoDataEvent on 204 response', () async {
      final httpClient = _mockHttpClient((_) async => http.Response('', 204));

      final client = LongPollClient(
        config: LongPollConfig(uri: baseUri, maxConsecutiveErrors: 1),
        httpClient: httpClient,
      );

      final completer = Completer<LongPollNoDataEvent>();
      client.events.listen((e) {
        if (e is LongPollNoDataEvent) {
          client.stop();
          completer.complete(e);
        }
      });

      unawaited(client.start());
      final event = await completer.future.timeout(const Duration(seconds: 5));
      expect(event, isA<LongPollNoDataEvent>());

      client.dispose();
    });

    test('emits LongPollMaxErrorsExceededException on repeated 500s', () async {
      final httpClient = _mockHttpClient(
        (_) async => http.Response('error', 500),
      );

      final client = LongPollClient(
        config: LongPollConfig(
          uri: baseUri,
          maxConsecutiveErrors: 3,
          retryDelay: Duration.zero,
          useExponentialBackoff: false,
        ),
        httpClient: httpClient,
      );

      Object? caughtError;
      client.events.listen((_) {}, onError: (Object? e) => caughtError = e);

      await expectLater(
        client.start,
        returnsNormally,
      );

      expect(caughtError, isA<LongPollMaxErrorsExceededException>());
      client.dispose();
    });

    test('appends cursor query param on subsequent requests', () async {
      final capturedUris = <Uri>[];
      var callCount = 0;

      final httpClient = _mockHttpClient((req) async {
        capturedUris.add(req.url);
        callCount++;
        return http.Response(
          'data',
          200,
          headers: {'x-next-cursor': 'cursor-$callCount'},
        );
      });

      final client = LongPollClient(
        config: LongPollConfig(
          uri: baseUri,
          cursorQueryParam: 'lastEventId',
          maxConsecutiveErrors: 1,
          retryDelay: Duration.zero,
        ),
        httpClient: httpClient,
      );

      var dataCount = 0;
      client.events.listen((e) {
        if (e is LongPollDataEvent) {
          dataCount++;
          if (dataCount == 2) client.stop();
        }
      });

      unawaited(client.start());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(capturedUris.length, greaterThanOrEqualTo(2));
      expect(capturedUris[0].queryParameters['lastEventId'], isNull);
      expect(capturedUris[1].queryParameters['lastEventId'], 'cursor-1');

      client.dispose();
    });

    test('does not retry on unrecoverable 401', () async {
      var callCount = 0;
      final httpClient = _mockHttpClient((_) async {
        callCount++;
        return http.Response('Unauthorized', 401);
      });

      final client = LongPollClient(
        config: LongPollConfig(
          uri: baseUri,
          maxConsecutiveErrors: 10,
          retryDelay: Duration.zero,
        ),
        httpClient: httpClient,
      );

      client.events.listen((_) {}, onError: (_) {});
      await client.start();

      expect(callCount, 1); // Must not retry on 401
      client.dispose();
    });
  });
}
