import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

class BoundedAudioQueue {
  BoundedAudioQueue({this.capacity = 64}) : assert(capacity > 0);

  final int capacity;
  final Queue<Uint8List> _frames = Queue<Uint8List>();
  final Queue<Completer<Uint8List?>> _waiters = Queue<Completer<Uint8List?>>();

  int get length => _frames.length;

  void add(Uint8List frame) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(frame);
      return;
    }
    if (_frames.length == capacity) _frames.removeFirst();
    _frames.addLast(frame);
  }

  Future<Uint8List?> take() {
    if (_frames.isNotEmpty) return Future.value(_frames.removeFirst());
    final waiter = Completer<Uint8List?>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void clear() {
    _frames.clear();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }
}
