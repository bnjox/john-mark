import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide/features/transcription/deepgram_messages.dart';
import 'package:guide/features/transcription/transcription.dart';

void main() {
  group('DeepgramMessageDecoder', () {
    late DeepgramMessageDecoder decoder;

    setUp(() => decoder = DeepgramMessageDecoder());

    test('decodes the first interim alternative', () {
      final event = decoder.decode(_result('John three', confidence: 0.8));

      expect(event?.type, TranscriptionEventType.interim);
      expect(event?.text, 'John three');
      expect(event?.confidence, 0.8);
    });

    test('decodes a final with a stable segment ID', () {
      final event = decoder.decode(
        _result('John 3:16', start: 1.25, duration: 0.75, isFinal: true),
      );

      expect(event?.type, TranscriptionEventType.finalized);
      expect(event?.eventId, '1.25:0.75:John 3:16');
    });

    test('ignores blank results', () {
      expect(decoder.decode(_result('   ')), isNull);
    });

    test('emits a repeated final only once', () {
      final payload = _result(
        'John 3:16',
        start: 1,
        duration: 2,
        isFinal: true,
      );

      expect(decoder.decode(payload), isNotNull);
      expect(decoder.decode(payload), isNull);
    });

    test('ignores interim and reordered finals behind finalized audio', () {
      expect(
        decoder.decode(_result('later', start: 4, duration: 2, isFinal: true)),
        isNotNull,
      );

      expect(decoder.decode(_result('old interim', start: 5)), isNull);
      expect(
        decoder.decode(
          _result('earlier', start: 1, duration: 2, isFinal: true),
        ),
        isNull,
      );
      expect(
        decoder.decode(
          _result('overlapping', start: 5, duration: 3, isFinal: true),
        ),
        isNull,
      );
    });

    test('bounds remembered final IDs', () {
      decoder = DeepgramMessageDecoder(finalizedIdLimit: 2);

      decoder.decode(_result('one', start: 1, duration: 1, isFinal: true));
      decoder.decode(_result('two', start: 2, duration: 1, isFinal: true));
      decoder.decode(_result('three', start: 3, duration: 1, isFinal: true));

      expect(decoder.rememberedFinalizedIdCount, 2);
    });

    test('decodes Error without carrying its description', () {
      final event = decoder.decode(
        jsonEncode({
          'type': 'Error',
          'err_code': 'INVALID_AUTH',
          'description': 'sensitive provider detail',
        }),
      );

      expect(event?.type, TranscriptionEventType.error);
      expect(event?.errorCode, 'INVALID_AUTH');
      expect(event?.text, isEmpty);
    });

    test('ignores malformed result fields instead of throwing', () {
      final payload = jsonEncode({
        'type': 'Results',
        'start': 'not-a-number',
        'duration': [],
        'is_final': true,
        'channel': {
          'alternatives': [
            {'transcript': 'text', 'confidence': 'high'},
          ],
        },
      });

      expect(() => decoder.decode(payload), returnsNormally);
      expect(decoder.decode(payload), isNull);
    });
  });
}

String _result(
  String transcript, {
  double start = 0,
  double duration = 1,
  double confidence = 0.9,
  bool isFinal = false,
}) => jsonEncode({
  'type': 'Results',
  'start': start,
  'duration': duration,
  'is_final': isFinal,
  'channel': {
    'alternatives': [
      {'transcript': transcript, 'confidence': confidence},
      {'transcript': 'ignored', 'confidence': 1},
    ],
  },
});
