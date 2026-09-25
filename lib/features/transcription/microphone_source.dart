import 'dart:typed_data';

import 'package:record/record.dart';

import 'transcription.dart';

class MicrophoneSource implements AudioSource {
  MicrophoneSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
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
    try {
      return await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
        ),
      );
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_running || _stopping) return;
    _stopping = true;
    try {
      await _recorder.stop();
    } finally {
      _running = false;
      _stopping = false;
    }
  }
}
