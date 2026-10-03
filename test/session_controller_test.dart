import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/session/bounded_audio_queue.dart';
import 'package:john_mark/features/session/session_controller.dart';
import 'package:john_mark/features/transcription/transcription.dart';

void main() {
  test(
    'bounded queue drops oldest frames and clear releases a taker',
    () async {
      final queue = BoundedAudioQueue(capacity: 2);
      queue.add(Uint8List.fromList([1]));
      queue.add(Uint8List.fromList([2]));
      queue.add(Uint8List.fromList([3]));

      expect(await queue.take(), Uint8List.fromList([2]));
      expect(await queue.take(), Uint8List.fromList([3]));
      final pending = queue.take();
      queue.clear();
      expect(await pending, isNull);
    },
  );

  test('concurrent start opens and starts capture once', () async {
    final fixture = _Fixture();

    await Future.wait([fixture.controller.start(), fixture.controller.start()]);

    expect(fixture.client.openCount, 1);
    expect(fixture.audio.startCount, 1);
    expect(fixture.controller.state.phase, SessionPhase.listening);
    await fixture.controller.stop();
  });

  test('concurrent stop and background close resources once', () async {
    final fixture = _Fixture();
    await fixture.controller.start();

    await Future.wait([
      fixture.controller.stop(),
      fixture.controller.onAppBackgrounded(),
    ]);

    expect(fixture.audio.stopCount, 1);
    expect(fixture.client.connections.single.closeCount, 1);
    expect(fixture.controller.state.phase, SessionPhase.stopped);
  });

  test(
    'stop updates immediately while a connection attempt is pending',
    () async {
      final fixture = _Fixture();
      final gate = Completer<TranscriptionConnection>();
      fixture.client.openGate = gate;

      final start = fixture.controller.start();
      await _flush();
      expect(fixture.controller.state.phase, SessionPhase.connecting);

      final stop = fixture.controller.stop();
      expect(fixture.controller.state.phase, SessionPhase.stopped);

      final connection = _FakeConnection();
      gate.complete(connection);
      await Future.wait([start, stop]);
      expect(connection.closeCount, 1);
      expect(fixture.audio.startCount, 0);
    },
  );

  test('slow matching does not block stop or apply a stale result', () async {
    final matchResult = Completer<MatchUpdate?>();
    final matchStarted = Completer<void>();
    final fixture = _Fixture(
      matcher: (_) {
        if (!matchStarted.isCompleted) matchStarted.complete();
        return matchResult.future;
      },
    );
    await fixture.controller.start();
    fixture.client.connections.single.eventsController.add(
      const TranscriptionEvent(
        type: TranscriptionEventType.finalized,
        text: 'slow finalized text',
        eventId: 'slow',
      ),
    );
    await matchStarted.future;

    await fixture.controller.stop();

    expect(fixture.audio.stopCount, 1);
    expect(fixture.client.connections.single.closeCount, 1);
    expect(fixture.controller.state.phase, SessionPhase.stopped);
    matchResult.complete(_match);
    await _flush();
    expect(fixture.controller.state.matches.featured, isNull);
  });

  test(
    'awaits one send while retaining only the newest 64 queued frames',
    () async {
      final fixture = _Fixture();
      await fixture.controller.start();
      final connection = fixture.client.connections.single;
      connection.sendGate = Completer<void>();

      for (var value = 0; value <= 70; value++) {
        fixture.audio.streams.single.add(Uint8List.fromList([value]));
      }
      await _flush();

      expect(connection.sent.map((frame) => frame.single), [0]);
      expect(fixture.controller.state.phase, SessionPhase.delayed);
      connection.sendGate!.complete();
      await _flush(80);
      expect(connection.sent, hasLength(65));
      expect(connection.sent.skip(1).map((frame) => frame.single), [
        for (var value = 7; value <= 70; value++) value,
      ]);
      expect(fixture.controller.state.phase, SessionPhase.listening);
      await fixture.controller.stop();
    },
  );

  test('disconnect stops capture and never replays pre-loss audio', () async {
    final delays = <_PendingDelay>[];
    final fixture = _Fixture(
      reconnectDelay: (duration) {
        final pending = _PendingDelay(duration);
        delays.add(pending);
        return pending.completer.future;
      },
    );
    await fixture.controller.start();
    final firstAudio = fixture.audio.streams.single;
    firstAudio.add(Uint8List.fromList([1]));
    fixture.client.connections.first.eventsController.add(
      const TranscriptionEvent(
        type: TranscriptionEventType.finalized,
        text: 'before loss',
        eventId: 'reused-provider-id',
      ),
    );
    await _flush();
    expect(fixture.client.connections.first.sent, hasLength(1));

    fixture.client.connections.first.eventsController.add(
      const TranscriptionEvent(type: TranscriptionEventType.disconnected),
    );
    await _flush();
    expect(fixture.audio.stopCount, 1);
    expect(delays.single.duration, const Duration(seconds: 1));

    firstAudio.add(Uint8List.fromList([2]));
    delays.single.completer.complete();
    await _flush();
    expect(fixture.client.openCount, 2);
    expect(fixture.controller.state.resultIsStale, isTrue);
    expect(fixture.client.connections.first.sent, hasLength(1));
    expect(fixture.client.connections.last.sent, isEmpty);

    fixture.audio.streams.last.add(Uint8List.fromList([3]));
    fixture.client.connections.last.eventsController.add(
      const TranscriptionEvent(
        type: TranscriptionEventType.finalized,
        text: 'current speech',
        eventId: 'reused-provider-id',
      ),
    );
    await _flush();
    expect(fixture.client.connections.last.sent.single, [3]);
    expect(fixture.controller.state.resultIsStale, isFalse);
    expect(
      fixture.controller.state.transcript.finalized,
      'before loss current speech',
    );
    await fixture.controller.stop();
  });

  test('retry backoff is injected, capped, and cancelled by stop', () async {
    final delays = <_PendingDelay>[];
    final fixture = _Fixture(
      reconnectDelay: (duration) {
        final pending = _PendingDelay(duration);
        delays.add(pending);
        return pending.completer.future;
      },
    );
    fixture.client.failOpenAfterFirst = true;
    await fixture.controller.start();

    fixture.client.connections.single.eventsController.add(
      const TranscriptionEvent(type: TranscriptionEventType.disconnected),
    );
    await _flush();
    for (var i = 0; i < 5; i++) {
      delays[i].completer.complete();
      await _flush();
    }

    expect(delays.map((delay) => delay.duration), const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
      Duration(seconds: 15),
    ]);
    await fixture.controller.stop();
    final opensAtStop = fixture.client.openCount;
    delays.last.completer.complete();
    await _flush();
    expect(fixture.client.openCount, opensAtStop);
  });

  for (final code in ['INVALID_AUTH', 'INVALID_REQUEST', 'QUOTA_EXCEEDED']) {
    test('$code is terminal and does not retry', () async {
      var delayCalls = 0;
      final fixture = _Fixture(reconnectDelay: (_) async => delayCalls++);
      await fixture.controller.start();

      fixture.client.connections.single.eventsController.add(
        TranscriptionEvent(type: TranscriptionEventType.error, errorCode: code),
      );
      await _flush();

      expect(fixture.controller.state.phase, SessionPhase.serviceError);
      expect(fixture.audio.stopCount, 1);
      expect(fixture.client.openCount, 1);
      expect(delayCalls, 0);
      await fixture.controller.stop();
    });
  }

  test('terminal handshake failure does not retry', () async {
    var delayCalls = 0;
    final fixture = _Fixture(reconnectDelay: (_) async => delayCalls++);
    fixture.client.openError = const TranscriptionOpenException(
      TranscriptionFailure.authentication,
    );

    await fixture.controller.start();

    expect(fixture.controller.state.phase, SessionPhase.serviceError);
    expect(fixture.controller.state.message, contains('authentication'));
    expect(fixture.client.openCount, 1);
    expect(fixture.audio.startCount, 0);
    expect(delayCalls, 0);
  });

  test('capture failure stops without scheduling a reconnect', () async {
    var delayCalls = 0;
    final fixture = _Fixture(reconnectDelay: (_) async => delayCalls++);
    fixture.audio.startError = StateError('no input');

    await fixture.controller.start();

    expect(fixture.controller.state.phase, SessionPhase.serviceError);
    expect(fixture.controller.state.message, contains('Microphone capture'));
    expect(fixture.client.openCount, 1);
    expect(fixture.client.connections.single.closeCount, 1);
    expect(delayCalls, 0);
  });

  test('runtime capture failure stops and closes the connection', () async {
    final fixture = _Fixture();
    await fixture.controller.start();

    fixture.audio.streams.single.addError(StateError('input lost'));
    await _flush();

    expect(fixture.controller.state.phase, SessionPhase.serviceError);
    expect(fixture.controller.state.message, contains('Microphone capture'));
    expect(fixture.client.connections.single.closeCount, 1);
    expect(fixture.audio.stopCount, 1);
  });

  test('resets matcher state at start and stop boundaries', () async {
    var resets = 0;
    final fixture = _Fixture(resetMatcher: () => resets++);

    await fixture.controller.start();
    expect(resets, 1);
    await fixture.controller.stop();
    expect(resets, 2);
  });

  test('repeated final IDs append and match once', () async {
    var matches = 0;
    final fixture = _Fixture(
      matcher: (_) async {
        matches++;
        return null;
      },
    );
    await fixture.controller.start();
    const finalEvent = TranscriptionEvent(
      type: TranscriptionEventType.finalized,
      text: 'John three sixteen',
      eventId: 'segment-1',
    );

    fixture.client.connections.single.eventsController
      ..add(finalEvent)
      ..add(finalEvent);
    await _flush();

    expect(fixture.controller.state.transcript.finalized, 'John three sixteen');
    expect(matches, 1);
    await fixture.controller.stop();
  });

  test('finalized and interim transcript text stays bounded', () async {
    final fixture = _Fixture();
    await fixture.controller.start();
    final connection = fixture.client.connections.single;

    connection.eventsController.add(
      TranscriptionEvent(
        type: TranscriptionEventType.finalized,
        text: 'a' * 2000,
        eventId: 'long-final',
      ),
    );
    await _flush();
    expect(
      fixture.controller.state.transcript.finalized.length,
      SessionController.transcriptLimit,
    );

    connection.eventsController.add(
      TranscriptionEvent(
        type: TranscriptionEventType.interim,
        text: 'b' * 2000,
      ),
    );
    await _flush();
    expect(
      fixture.controller.state.transcript.interim.length,
      SessionController.transcriptLimit,
    );
    await fixture.controller.stop();
  });

  test('stop clears transcript, matches, IDs, and timers', () async {
    final fixture = _Fixture(matcher: (_) async => _match);
    await fixture.controller.start();
    fixture.client.connections.single.eventsController.add(
      const TranscriptionEvent(
        type: TranscriptionEventType.finalized,
        text: 'a final',
        eventId: 'one',
      ),
    );
    await _flush();

    await fixture.controller.stop();

    expect(fixture.controller.state.phase, SessionPhase.stopped);
    expect(fixture.controller.state.transcript.finalized, isEmpty);
    expect(fixture.controller.state.matches.featured, isNull);
    expect(fixture.controller.state.elapsed, Duration.zero);
    expect(fixture.controller.state.resultIsStale, isFalse);
  });
}

const _match = MatchUpdate(
  featured: MatchCandidate(
    passage: Passage(
      reference: ScriptureReference(
        book: 43,
        chapter: 3,
        startVerse: 16,
        endVerse: 16,
      ),
      label: 'John 3:16',
      text: 'Fictional text',
    ),
    score: 1,
    band: ConfidenceBand.high,
    explicitReference: true,
  ),
);

class _Fixture {
  _Fixture({
    ReconnectDelay? reconnectDelay,
    TranscriptMatcher? matcher,
    MatcherReset? resetMatcher,
  }) : audio = _FakeAudioSource(),
       client = _FakeTranscriptionClient() {
    controller = SessionController(
      audioSource: audio,
      transcriptionClient: client,
      matchTranscript: matcher ?? (_) async => null,
      resetMatcher: resetMatcher ?? () {},
      reconnectDelay: reconnectDelay ?? (_) async {},
    );
  }

  final _FakeAudioSource audio;
  final _FakeTranscriptionClient client;
  late final SessionController controller;
}

class _FakeAudioSource implements AudioSource {
  int startCount = 0;
  int stopCount = 0;
  bool permission = true;
  Object? startError;
  final List<StreamController<Uint8List>> streams = [];

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    startCount++;
    if (startError case final error?) throw error;
    final stream = StreamController<Uint8List>.broadcast();
    streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async => stopCount++;
}

class _FakeTranscriptionClient implements TranscriptionClient {
  int openCount = 0;
  bool failOpenAfterFirst = false;
  Object? openError;
  Completer<TranscriptionConnection>? openGate;
  final List<_FakeConnection> connections = [];

  @override
  Future<TranscriptionConnection> open({required List<String> keyterms}) async {
    openCount++;
    if (openError case final error?) throw error;
    if (openGate case final gate?) return gate.future;
    if (failOpenAfterFirst && openCount > 1) throw StateError('offline');
    final connection = _FakeConnection();
    connections.add(connection);
    return connection;
  }
}

class _FakeConnection implements TranscriptionConnection {
  final eventsController = StreamController<TranscriptionEvent>.broadcast();
  final List<Uint8List> sent = [];
  int closeCount = 0;
  Completer<void>? sendGate;

  @override
  Stream<TranscriptionEvent> get events => eventsController.stream;

  @override
  Future<void> send(Uint8List audio) async {
    sent.add(Uint8List.fromList(audio));
    await sendGate?.future;
  }

  @override
  Future<void> close() async => closeCount++;
}

class _PendingDelay {
  _PendingDelay(this.duration);

  final Duration duration;
  final Completer<void> completer = Completer<void>();
}

Future<void> _flush([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
