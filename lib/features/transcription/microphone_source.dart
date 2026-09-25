import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'transcription.dart';

class MicrophoneSource implements AudioSource {
  MicrophoneSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<RecordState>? _stateSubscription;
  StreamController<Uint8List>? _streamController;
  bool _running = false;
  bool _stopping = false;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() async {
    if (_running || _stopping) {
      throw StateError('Microphone capture is already running.');
    }
    _running = true;
    final controller = StreamController<Uint8List>();
    _streamController = controller;
    try {
      var compatible = true;
      await _recorder.setOnConfigChanged((config) {
        compatible =
            config.encoder == AudioEncoder.pcm16bits &&
            config.sampleRate == 16000 &&
            config.numChannels == 1;
        if (!compatible && !controller.isClosed) {
          controller.addError(
            StateError('The microphone changed to an incompatible format.'),
          );
        }
      });
      final source = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
          audioInterruption: AudioInterruptionMode.pause,
        ),
      );
      if (!compatible) {
        await _recorder.stop();
        throw StateError('The microphone cannot provide the required format.');
      }
      _dataSubscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: true,
      );
      _stateSubscription = _recorder.onStateChanged().listen((state) {
        if (!_running || _stopping || state == RecordState.record) return;
        if (!controller.isClosed) {
          controller.addError(
            StateError('Microphone capture was interrupted.'),
          );
        }
      }, onError: controller.addError);
      return controller.stream;
    } catch (_) {
      await _dataSubscription?.cancel();
      await _stateSubscription?.cancel();
      _dataSubscription = null;
      _stateSubscription = null;
      if (!controller.isClosed) await controller.close();
      _streamController = null;
      await _recorder.setOnConfigChanged(null);
      _running = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_running || _stopping) return;
    _stopping = true;
    try {
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      await _recorder.stop();
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      final controller = _streamController;
      _streamController = null;
      if (controller != null && !controller.isClosed) {
        await controller.close();
      }
    } finally {
      await _recorder.setOnConfigChanged(null);
      _running = false;
      _stopping = false;
    }
  }
}
