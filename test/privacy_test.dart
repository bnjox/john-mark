import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/session/session_controller.dart';
import 'package:john_mark/features/transcription/transcription.dart';

void main() {
  test(
    'a complete session writes no audio, transcript, or match data',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'scripture-listener-privacy-',
      );
      final previousDirectory = Directory.current;
      final audio = _PrivacyAudio();
      final connection = _PrivacyConnection();
      final controller = SessionController(
        audioSource: audio,
        transcriptionClient: _PrivacyClient(connection),
        matchTranscript: (_) async => _match,
      );

      try {
        Directory.current = temporaryDirectory;
        await controller.start();
        audio.frames.add(Uint8List.fromList([1, 2, 3, 4]));
        connection.providerEvents.add(
          const TranscriptionEvent(
            type: TranscriptionEventType.finalized,
            text: 'John three sixteen',
            eventId: 'one',
          ),
        );
        await _flush();
        expect(controller.state.matches.featured, isNotNull);

        await controller.stop();

        expect(temporaryDirectory.listSync(), isEmpty);
        expect(controller.state.transcript.finalized, isEmpty);
        expect(controller.state.matches.featured, isNull);
      } finally {
        controller.dispose();
        Directory.current = previousDirectory;
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );
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
  ),
);

class _PrivacyAudio implements AudioSource {
  final frames = StreamController<Uint8List>.broadcast();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> start() async => frames.stream;

  @override
  Future<void> stop() async {}
}

class _PrivacyClient implements TranscriptionClient {
  _PrivacyClient(this.connection);

  final _PrivacyConnection connection;

  @override
  Future<TranscriptionConnection> open({
    required List<String> keyterms,
  }) async => connection;
}

class _PrivacyConnection implements TranscriptionConnection {
  final providerEvents = StreamController<TranscriptionEvent>.broadcast();

  @override
  Stream<TranscriptionEvent> get events => providerEvents.stream;

  @override
  Future<void> send(Uint8List audio) async {}

  @override
  Future<void> close() async {}
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
