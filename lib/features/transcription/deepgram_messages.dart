import 'dart:collection';
import 'dart:convert';

import 'transcription.dart';

class DeepgramMessageDecoder {
  DeepgramMessageDecoder({this.finalizedIdLimit = 100})
    : assert(finalizedIdLimit > 0);

  final int finalizedIdLimit;
  final Queue<String> _finalizedIds = Queue<String>();
  final Set<String> _finalizedIdSet = <String>{};
  double _finalizedThrough = 0;

  int get rememberedFinalizedIdCount => _finalizedIds.length;

  TranscriptionEvent? decode(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    return switch (decoded['type']) {
      'Results' => _decodeResult(decoded),
      'Error' => TranscriptionEvent(
        type: TranscriptionEventType.error,
        errorCode: decoded['err_code'] is String
            ? decoded['err_code'] as String
            : 'deepgram_error',
      ),
      _ => null,
    };
  }

  TranscriptionEvent? _decodeResult(Map<String, dynamic> message) {
    final channel = message['channel'];
    if (channel is! Map<String, dynamic>) return null;
    final alternatives = channel['alternatives'];
    if (alternatives is! List || alternatives.isEmpty) return null;
    final alternative = alternatives.first;
    if (alternative is! Map<String, dynamic>) return null;

    final text = alternative['transcript'];
    if (text is! String || text.trim().isEmpty) return null;

    final startValue = message['start'];
    final durationValue = message['duration'];
    final confidenceValue = alternative['confidence'];
    final start = startValue is num ? startValue.toDouble() : null;
    final duration = durationValue is num ? durationValue.toDouble() : null;
    final parsedConfidence = confidenceValue is num
        ? confidenceValue.toDouble()
        : null;
    final confidence =
        parsedConfidence != null &&
            parsedConfidence >= 0 &&
            parsedConfidence <= 1
        ? parsedConfidence
        : null;
    final isFinal = message['is_final'] == true;

    if (!isFinal) {
      if (start != null && start < _finalizedThrough) return null;
      return TranscriptionEvent(
        type: TranscriptionEventType.interim,
        text: text,
        confidence: confidence,
      );
    }

    if (start == null || start < 0 || duration == null || duration <= 0) {
      return null;
    }
    final eventId = '$start:$duration:$text';
    final end = start + duration;
    if (_finalizedIdSet.contains(eventId) || start < _finalizedThrough) {
      return null;
    }

    _rememberFinalized(eventId);
    _finalizedThrough = end;
    return TranscriptionEvent(
      type: TranscriptionEventType.finalized,
      text: text,
      confidence: confidence,
      eventId: eventId,
    );
  }

  void _rememberFinalized(String eventId) {
    _finalizedIds.addLast(eventId);
    _finalizedIdSet.add(eventId);
    if (_finalizedIds.length <= finalizedIdLimit) return;
    _finalizedIdSet.remove(_finalizedIds.removeFirst());
  }
}
