import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'deepgram_messages.dart';
import 'transcription.dart';

typedef DeepgramSocketConnector = Future<WebSocket> Function(
  String url,
  Map<String, dynamic> headers,
);

class DeepgramClient implements TranscriptionClient {
  const DeepgramClient({
    this.apiKey = const String.fromEnvironment('DEEPGRAM_API_KEY'),
    this.connect = _connectWebSocket,
  });

  final String apiKey;
  final DeepgramSocketConnector connect;

  @override
  Future<TranscriptionConnection> open({required List<String> keyterms}) async {
    if (apiKey.isEmpty) {
      throw const TranscriptionOpenException(
        TranscriptionFailure.invalidRequest,
      );
    }

    try {
      final socket = await connect(_uriFor(keyterms).toString(), {
        'Authorization': 'Token $apiKey',
      });
      return _DeepgramConnection(socket);
    } on WebSocketException catch (error) {
      throw TranscriptionOpenException(_classifyHandshakeFailure(error));
    }
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

Future<WebSocket> _connectWebSocket(String url, Map<String, dynamic> headers) =>
    WebSocket.connect(url, headers: headers);

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
  Future<void> send(Uint8List audio) async {
    if (_closed || audio.isEmpty) return;
    // addStream completes when dart:io has accepted this frame. It is not a
    // remote acknowledgement, but it prevents the controller from issuing
    // more than one transport write at a time.
    await _socket.addStream(Stream<Uint8List>.value(audio));
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

TranscriptionFailure _classifyHandshakeFailure(WebSocketException error) {
  final message = error.message.toLowerCase();
  final status = RegExp(r'(?:status(?: code)?[: ]+|http[/ ]\S+\s+)(\d{3})')
      .firstMatch(message)
      ?.group(1);
  return switch (status) {
    '401' || '403' => TranscriptionFailure.authentication,
    '402' || '429' => TranscriptionFailure.quota,
    '400' || '404' || '422' => TranscriptionFailure.invalidRequest,
    _ => TranscriptionFailure.unavailable,
  };
}
