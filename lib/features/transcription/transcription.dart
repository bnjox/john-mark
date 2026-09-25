import 'dart:typed_data';

enum TranscriptionEventType { interim, finalized, disconnected, error }

class TranscriptionEvent {
  const TranscriptionEvent({
    required this.type,
    this.text = '',
    this.confidence,
    this.errorCode,
    this.eventId,
  });

  final TranscriptionEventType type;
  final String text;
  final double? confidence;
  final String? errorCode;
  final String? eventId;
}

abstract interface class AudioSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

abstract interface class TranscriptionConnection {
  Stream<TranscriptionEvent> get events;
  void send(Uint8List audio);
  Future<void> close();
}

abstract interface class TranscriptionClient {
  Future<TranscriptionConnection> open({required List<String> keyterms});
}
