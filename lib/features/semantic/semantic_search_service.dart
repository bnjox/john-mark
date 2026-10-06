import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/performance_trace.dart';
import 'onnx_text_embedder.dart';
import 'semantic_retriever.dart';

typedef SemanticAssetsLoader = Future<SemanticComponents> Function();

class SemanticComponents {
  const SemanticComponents({required this.embedder, required this.index});

  final TextEmbedder embedder;
  final SemanticVectorIndex index;
}

class SemanticSearchService extends ChangeNotifier
    implements SemanticRetriever, ValueListenable<SemanticStatus> {
  SemanticSearchService({required this._loadAssets});

  final SemanticAssetsLoader _loadAssets;
  SemanticStatus _status = SemanticStatus.initializing;
  SemanticComponents? _components;
  Future<void>? _initialization;
  Future<void>? _activeSearch;
  _PendingSearch? _initializingSearch;
  _PendingSearch? _pendingSearch;
  bool _disposed = false;
  String? _diagnosticCategory;

  @override
  SemanticStatus get status => _status;

  @override
  SemanticStatus get value => _status;

  String? get diagnosticCategory => _diagnosticCategory;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final components = await _loadAssets();
      if (_disposed) {
        await components.embedder.dispose();
        await components.index.dispose();
        return;
      }
      _components = components;
      _setStatus(SemanticStatus.ready);
      final waiting = _initializingSearch;
      _initializingSearch = null;
      if (waiting != null) _start(waiting);
    } catch (error) {
      if (_disposed) return;
      _initializingSearch?.complete(const []);
      _initializingSearch = null;
      _diagnosticCategory = error.runtimeType.toString();
      _setStatus(SemanticStatus.unavailable);
    }
  }

  @override
  Future<List<SemanticHit>> search(String text, {int limit = 8}) {
    if (_disposed ||
        _status == SemanticStatus.unavailable ||
        text.trim().isEmpty) {
      return Future.value(const []);
    }
    final request = _PendingSearch(text, limit.clamp(1, 8));
    if (_status == SemanticStatus.initializing) {
      _initializingSearch?.complete(const []);
      _initializingSearch = request;
      unawaited(initialize());
      return request.future;
    }
    if (_activeSearch != null) {
      _pendingSearch?.complete(const []);
      _pendingSearch = request;
    } else {
      _start(request);
    }
    return request.future;
  }

  void _start(_PendingSearch request) {
    _activeSearch = _run(request).whenComplete(() {
      _activeSearch = null;
      if (_disposed || _status != SemanticStatus.ready) {
        _pendingSearch?.complete(const []);
        _pendingSearch = null;
        return;
      }
      final next = _pendingSearch;
      _pendingSearch = null;
      if (next != null) _start(next);
    });
  }

  Future<void> _run(_PendingSearch request) async {
    try {
      final components = _components;
      if (components == null) {
        request.complete(const []);
        return;
      }
      final hits = await tracePerformance('search.semantic', () async {
        final embedding = await components.embedder.embed(request.text);
        return components.index.search(embedding, limit: request.limit);
      });
      request.complete(_disposed ? const [] : hits);
    } catch (error) {
      request.complete(const []);
      if (!_disposed) {
        _diagnosticCategory = error.runtimeType.toString();
        _setStatus(SemanticStatus.unavailable);
      }
    }
  }

  void _setStatus(SemanticStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initializingSearch?.complete(const []);
    _initializingSearch = null;
    _pendingSearch?.complete(const []);
    _pendingSearch = null;
    final components = _components;
    _components = null;
    if (components != null) {
      unawaited(components.embedder.dispose());
      unawaited(components.index.dispose());
    }
    super.dispose();
  }
}

class _PendingSearch {
  _PendingSearch(this.text, this.limit);

  final String text;
  final int limit;
  final Completer<List<SemanticHit>> _completer = Completer();

  Future<List<SemanticHit>> get future => _completer.future;

  void complete(List<SemanticHit> hits) {
    if (!_completer.isCompleted) _completer.complete(hits);
  }
}
