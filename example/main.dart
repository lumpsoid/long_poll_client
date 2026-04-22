import 'dart:async';
import 'package:logging/logging.dart';
import 'package:long_poll_client/long_poll_client.dart';

void main() async {
  // Set up logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => print('[${r.level.name}] ${r.loggerName}: ${r.message}'),
  );

  final config = LongPollConfig(
    uri: Uri.parse('https://api.example.com/events'),
    headers: {'Authorization': 'Bearer <token>'},
    retryDelay: const Duration(seconds: 2),
    maxConsecutiveErrors: 10,
    cursorQueryParam: 'lastEventId', // appended automatically
  );

  final client = LongPollClient(
    config: config,
    httpClient: HttpClientImpl(),
    initialCursor: 'event-42', // resume from a known position
  );

  // Handle all events with exhaustive pattern matching
  final sub = client.events.listen((event) {
    switch (event) {
      case LongPollDataEvent(:final response, :final nextCursor):
        print('✅ Data received [cursor: $nextCursor]: ${response.body}');

      case LongPollNoDataEvent():
        print('⏳ No new data — server held and returned empty.');

      case LongPollPollingEvent(:final attemptNumber, :final uri):
        print('🔄 Polling attempt #$attemptNumber → $uri');

      case LongPollErrorEvent(
        :final error,
        :final consecutiveErrors,
        :final retryDelay,
      ):
        print(
          '⚠️  Error ($consecutiveErrors consecutive): $error, '
          'retrying in $retryDelay',
        );

      case LongPollStoppedEvent():
        print('🛑 Long-poll client stopped.');
    }
  });

  // Stop after 2 minutes in this example
  Timer(const Duration(minutes: 2), client.stop);

  try {
    await client.start(); // blocks until stopped or fatal error
  } on LongPollMaxErrorsExceededException catch (e) {
    print('💥 Fatal: $e');
  } finally {
    await sub.cancel();
    client.dispose();
  }
}
