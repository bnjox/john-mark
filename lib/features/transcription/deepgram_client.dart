import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'deepgram_messages.dart';
import 'transcription.dart';

class DeepgramClient implements TranscriptionClient {
  const DeepgramClient({
    this.apiKey = const String.fromEnvironment('DEEPGRAM_API_KEY'),
  });

  final String apiKey;

  @override
  Future<TranscriptionConnection> open({required List<String> keyterms}) async {
    if (apiKey.isEmpty) {
      throw StateError(
        'DEEPGRAM_API_KEY is missing. Supply it with --dart-define.',
      );
    }

    final socket = await WebSocket.connect(
      _uriFor(keyterms).toString(),
      headers: {'Authorization': 'Token $apiKey'},
    );
    return _DeepgramConnection(socket);
  }

  Uri _uriFor(List<String> keyterms) {
    final acceptedKeyterms = <String>[];
    var tokenCount = 0;
    for (final keyterm in keyterms) {
      final trimmed = keyterm.trim();
      if (trimmed.isEmpty) continue;
      final tokens = trimmed.split(RegExp(r'\s+')).length;
      if (tokenCount + tokens >= 500) continue;
      acceptedKeyterms.add(trimmed);
      tokenCount += tokens;
    }

    return Uri(
      scheme: 'wss',
      host: 'api.deepgram.com',
      path: '/v1/listen',
      queryParameters: <String, dynamic>{
        'model': 'nova-3',
        'language': 'en-US',
        'encoding': 'linear16',
        'sample_rate': '16000',
        'channels': '1',
        'interim_results': 'true',
        'smart_format': 'true',
        'endpointing': '300',
        if (acceptedKeyterms.isNotEmpty) 'keyterm': acceptedKeyterms,
      },
    );
  }
}

class _DeepgramConnection implements TranscriptionConnection {
  _DeepgramConnection(this._socket) {
    _subscription = _socket.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final WebSocket _socket;
  final DeepgramMessageDecoder _decoder = DeepgramMessageDecoder();
  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>();
  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  @override
  void send(Uint8List audio) {
    if (_closed || audio.isEmpty) return;
    _socket.add(audio);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket.add(jsonEncode({'type': 'CloseStream'}));
    } on StateError {
      // The peer may have closed between the local state check and this send.
    } on WebSocketException {
      // Closing remains idempotent if the transport has already failed.
    }
    await _socket.close();
    await _subscription.cancel();
    await _events.close();
  }

  void _onMessage(dynamic payload) {
    if (_closed || payload is! String) return;
    final event = _decoder.decode(payload);
    if (event != null) _events.add(event);
  }

  void _onError(Object _) {
    if (_closed) return;
    _events.add(
      const TranscriptionEvent(
        type: TranscriptionEventType.error,
        errorCode: 'websocket_error',
      ),
    );
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _events.add(
      const TranscriptionEvent(type: TranscriptionEventType.disconnected),
    );
    unawaited(_events.close());
  }
}
