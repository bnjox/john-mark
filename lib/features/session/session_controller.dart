import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../transcription/transcription.dart';
import 'bounded_audio_queue.dart';

typedef TranscriptMatcher = Future<MatchUpdate?> Function(
  String translationId,
  String finalizedText,
);
typedef ReconnectDelay = Future<void> Function(Duration duration);
typedef MatcherReset = void Function();

class SessionController extends ChangeNotifier {
  SessionController({
    required this.audioSource,
    required this.transcriptionClient,
    required this.matchTranscript,
    required this.resetMatcher,
    List<String> keyterms = const [],
    this.reconnectDelay = _defaultDelay,
  }) : _keyterms = List.unmodifiable(keyterms);

  static const int transcriptLimit = 1500;
  static const List<Duration> reconnectBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  final AudioSource audioSource;
  final TranscriptionClient transcriptionClient;
  final TranscriptMatcher matchTranscript;
  final MatcherReset resetMatcher;
  final ReconnectDelay reconnectDelay;
  final List<String> _keyterms;
  final BoundedAudioQueue _audioQueue = BoundedAudioQueue();
  final Set<String> _finalizedIds = <String>{};
  final List<String> _finalizedIdOrder = <String>[];

  ListenerViewState _state = const ListenerViewState();
  Future<void> _operations = Future.value();
  TranscriptionConnection? _connection;
  StreamSubscription<TranscriptionEvent>? _eventSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _elapsedTimer;
  DateTime? _startedAt;
  int _generation = 0;
  int _reconnectAttempt = 0;
  bool _active = false;
  bool _captureStarted = false;
  bool _disposed = false;
  _MatchWork? _matchWork;

  ListenerViewState get state => _state;

  Future<void> start(Translation translation) => _serialize(() async {
    if (_active) return;
    final generation = ++_generation;
    resetMatcher();
    _matchWork = _MatchWork(generation);
    _active = true;
    _reconnectAttempt = 0;
    _setState(
      ListenerViewState(
        phase: SessionPhase.connecting,
        translation: translation,
      ),
    );

    if (!await audioSource.hasPermission()) {
      if (!_isCurrent(generation)) return;
      _active = false;
      _setState(
        ListenerViewState(
          phase: SessionPhase.permissionDenied,
          translation: translation,
          message: 'Microphone permission is required.',
        ),
      );
      return;
    }

    try {
      await _connectAndCapture(generation);
    } on TranscriptionOpenException catch (error) {
      if (!_isCurrent(generation)) return;
      if (error.isTerminal) {
        await _failTerminal(generation, error.failure);
      } else {
        await _beginReconnect(generation);
      }
    } catch (_) {
      if (_isCurrent(generation)) await _beginReconnect(generation);
    }
  });

  Future<void> stop() => _serialize(_stop);

  Future<void> onAppBackgrounded() => stop();

  Future<void> _stop() async {
    ++_generation;
    _active = false;
    _cancelMatching();
    await _releaseConnection();
    _clearTransientState();
    _setState(const ListenerViewState(phase: SessionPhase.stopped));
  }

  Future<void> _connectAndCapture(int generation) async {
    final connection = await transcriptionClient.open(keyterms: _keyterms);
    if (!_isCurrent(generation)) {
      await connection.close();
      return;
    }

    _connection = connection;
    _eventSubscription = connection.events.listen(
      (event) => unawaited(
        _serialize(() => _handleProviderEvent(event, connection, generation)),
      ),
    );

    final audio = await audioSource.start();
    if (!_isCurrent(generation)) {
      await _releaseConnection();
      return;
    }
    _captureStarted = true;
    _audioSubscription = audio.listen(_audioQueue.add);
    unawaited(_pumpAudio(connection, generation));
    _reconnectAttempt = 0;
    _startedAt ??= DateTime.now();
    _startElapsedTimer(generation);
    _setState(_copyState(phase: SessionPhase.listening, message: null));
  }

  Future<void> _pumpAudio(
    TranscriptionConnection connection,
    int generation,
  ) async {
    while (_isCurrent(generation) && identical(_connection, connection)) {
      final frame = await _audioQueue.take();
      if (frame == null ||
          !_isCurrent(generation) ||
          !identical(_connection, connection)) {
        return;
      }
      try {
        await connection.send(frame);
      } catch (_) {
        unawaited(_serialize(() => _beginReconnect(generation)));
        return;
      }
    }
  }

  Future<void> _handleProviderEvent(
    TranscriptionEvent event,
    TranscriptionConnection connection,
    int generation,
  ) async {
    if (!_isCurrent(generation) || !identical(_connection, connection)) return;
    switch (event.type) {
      case TranscriptionEventType.interim:
        _setState(
          _copyState(
            transcript: TranscriptUpdate(
              finalized: _state.transcript.finalized,
              interim: _bounded(event.text.trim()),
            ),
          ),
        );
      case TranscriptionEventType.finalized:
        if (!_rememberFinal(event.eventId)) return;
        final finalized = _appendFinal(event.text);
        _setState(
          _copyState(
            transcript: TranscriptUpdate(finalized: finalized),
            resultIsStale: false,
          ),
        );
        _scheduleMatch(generation, finalized);
      case TranscriptionEventType.disconnected:
        await _beginReconnect(generation);
      case TranscriptionEventType.error:
        if (_isTerminalError(event.errorCode)) {
          await _failTerminal(generation);
        } else {
          await _beginReconnect(generation);
        }
    }
  }

  Future<void> _beginReconnect(int generation) async {
    if (!_isCurrent(generation) || _state.phase == SessionPhase.reconnecting) {
      return;
    }
    await _releaseConnection();
    if (!_isCurrent(generation)) return;
    _finalizedIds.clear();
    _finalizedIdOrder.clear();
    _setState(
      _copyState(
        phase: SessionPhase.reconnecting,
        resultIsStale: true,
        transcript: TranscriptUpdate(finalized: _state.transcript.finalized),
      ),
    );
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    final index = _reconnectAttempt.clamp(0, reconnectBackoff.length - 1);
    final delay = reconnectBackoff[index];
    _reconnectAttempt++;
    unawaited(() async {
      await reconnectDelay(delay);
      await _serialize(() async {
        if (!_isCurrent(generation) ||
            _state.phase != SessionPhase.reconnecting) {
          return;
        }
        try {
          await _connectAndCapture(generation);
        } on TranscriptionOpenException catch (error) {
          await _releaseConnection();
          if (!_isCurrent(generation)) return;
          if (error.isTerminal) {
            await _failTerminal(generation, error.failure);
          } else {
            _scheduleReconnect(generation);
          }
        } catch (_) {
          await _releaseConnection();
          if (_isCurrent(generation)) _scheduleReconnect(generation);
        }
      });
    }());
  }

  Future<void> _failTerminal(
    int generation, [
    TranscriptionFailure? failure,
  ]) async {
    await _releaseConnection();
    if (!_isCurrent(generation)) return;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _active = false;
    _cancelMatching();
    resetMatcher();
    ++_generation;
    _setState(
      _copyState(
        phase: SessionPhase.serviceError,
        message: _terminalFailureMessage(failure),
      ),
    );
  }

  Future<void> _releaseConnection() async {
    _audioQueue.clear();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (_captureStarted) {
      _captureStarted = false;
      await audioSource.stop();
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }

  void _clearTransientState() {
    _audioQueue.clear();
    _finalizedIds.clear();
    _finalizedIdOrder.clear();
    _reconnectAttempt = 0;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _startedAt = null;
    resetMatcher();
  }

  void _scheduleMatch(int generation, String finalizedText) {
    final work = _matchWork;
    if (work == null || work.generation != generation) return;
    if (work.inFlight) {
      work.pendingText = finalizedText;
      return;
    }
    unawaited(_runMatch(work, finalizedText));
  }

  Future<void> _runMatch(_MatchWork work, String finalizedText) async {
    work.inFlight = true;
    try {
      final translationId = _state.translation?.id;
      if (translationId == null) return;
      final match = await matchTranscript(translationId, finalizedText);
      if (identical(_matchWork, work) &&
          _isCurrent(work.generation) &&
          match != null) {
        _setState(_copyState(matches: match));
      }
    } catch (_) {
      // A failed lookup must not terminate the session or block Stop.
    } finally {
      work.inFlight = false;
      if (identical(_matchWork, work) && _isCurrent(work.generation)) {
        final pending = work.pendingText;
        work.pendingText = null;
        if (pending != null) unawaited(_runMatch(work, pending));
      }
    }
  }

  void _cancelMatching() {
    _matchWork?.pendingText = null;
    _matchWork = null;
  }

  bool _rememberFinal(String? id) {
    if (id == null || id.isEmpty) return true;
    if (!_finalizedIds.add(id)) return false;
    _finalizedIdOrder.add(id);
    if (_finalizedIdOrder.length > 100) {
      _finalizedIds.remove(_finalizedIdOrder.removeAt(0));
    }
    return true;
  }

  String _appendFinal(String text) {
    final addition = text.trim();
    if (addition.isEmpty) return _state.transcript.finalized;
    final existing = _state.transcript.finalized;
    return _bounded(existing.isEmpty ? addition : '$existing $addition');
  }

  String _bounded(String text) => text.length <= transcriptLimit
      ? text
      : text.substring(text.length - transcriptLimit);

  bool _isCurrent(int generation) => _active && generation == _generation;

  static bool _isTerminalError(String? code) {
    final normalized = (code ?? '').toUpperCase();
    return normalized.contains('AUTH') ||
        normalized.contains('INVALID') ||
        normalized.contains('QUOTA') ||
        normalized.contains('CREDIT') ||
        normalized.contains('PAYMENT');
  }

  static String _terminalFailureMessage(TranscriptionFailure? failure) =>
      switch (failure) {
        TranscriptionFailure.authentication =>
          'Transcription authentication failed. Rebuild with a valid key.',
        TranscriptionFailure.quota =>
          'Transcription quota is unavailable. Check the service account.',
        TranscriptionFailure.invalidRequest =>
          'Transcription configuration is invalid for this build.',
        _ => 'Transcription service is unavailable.',
      };

  void _startElapsedTimer(int generation) {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isCurrent(generation) || _startedAt == null) return;
      _setState(_copyState(elapsed: DateTime.now().difference(_startedAt!)));
    });
  }

  ListenerViewState _copyState({
    SessionPhase? phase,
    TranscriptUpdate? transcript,
    MatchUpdate? matches,
    Duration? elapsed,
    String? message,
    bool? resultIsStale,
  }) => ListenerViewState(
    phase: phase ?? _state.phase,
    translation: _state.translation,
    transcript: transcript ?? _state.transcript,
    matches: matches ?? _state.matches,
    elapsed: elapsed ?? _state.elapsed,
    message: message,
    resultIsStale: resultIsStale ?? _state.resultIsStale,
  );

  void _setState(ListenerViewState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final completer = Completer<void>();
    _operations = _operations.then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _active = false;
    _cancelMatching();
    _elapsedTimer?.cancel();
    _audioQueue.clear();
    unawaited(_audioSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_connection?.close());
    if (_captureStarted) unawaited(audioSource.stop());
    super.dispose();
  }
}

Future<void> _defaultDelay(Duration duration) => Future.delayed(duration);

class _MatchWork {
  _MatchWork(this.generation);

  final int generation;
  bool inFlight = false;
  String? pendingText;
}
