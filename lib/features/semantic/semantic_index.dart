import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/models.dart';
import 'semantic_retriever.dart';

const _magic = 'SCRIPIDX';
const _formatVersion = 1;
const _headerLength = 20;
const _rowHeaderLength = 10;
const _maximumResults = 8;
const _quantization = 'symmetric-int8-per-row';

class SemanticIndex implements SemanticVectorIndex {
  SemanticIndex._(
    this.dimensions,
    this._isolate,
    this._worker,
    this._events,
    this._subscription,
    this._pending,
  );

  static Future<SemanticIndex> loadAsset(
    String assetPath, {
    required RootIsolateToken rootIsolateToken,
    required String expectedModelId,
    required String expectedModelRevision,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
    required Iterable<String> expectedTranslationIds,
  }) => _start(
    _WorkerConfig.asset(
      assetPath: assetPath,
      rootIsolateToken: rootIsolateToken,
      expectedModelId: expectedModelId,
      expectedModelRevision: expectedModelRevision,
      expectedDimensions: expectedDimensions,
      expectedBibleFingerprint: expectedBibleFingerprint,
      expectedTranslationIds: expectedTranslationIds.toList(growable: false),
    ),
  );

  static Future<SemanticIndex> fromBytes(
    Uint8List bytes, {
    required String expectedModelId,
    required String expectedModelRevision,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
    required Iterable<String> expectedTranslationIds,
  }) => _start(
    _WorkerConfig.bytes(
      bytes: TransferableTypedData.fromList([bytes]),
      expectedModelId: expectedModelId,
      expectedModelRevision: expectedModelRevision,
      expectedDimensions: expectedDimensions,
      expectedBibleFingerprint: expectedBibleFingerprint,
      expectedTranslationIds: expectedTranslationIds.toList(growable: false),
    ),
  );

  static Future<SemanticIndex> _start(_WorkerConfig config) async {
    final events = ReceivePort();
    final ready = Completer<SendPort>();
    final pending = <int, Completer<List<SemanticHit>>>{};
    var disposed = false;
    late final StreamSubscription<dynamic> subscription;
    subscription = events.listen((message) {
      switch (message) {
        case _WorkerReady(:final port):
          if (!ready.isCompleted) ready.complete(port);
        case _WorkerFailure(:final category):
          final error = StateError('Semantic index worker failed: $category');
          if (!ready.isCompleted) ready.completeError(error);
          for (final completer in pending.values) {
            if (!completer.isCompleted) completer.completeError(error);
          }
          pending.clear();
        case _WorkerResponse(:final id, :final hits):
          final completer = pending.remove(id);
          if (!disposed && completer != null && !completer.isCompleted) {
            completer.complete(hits);
          }
      }
    });
    final workerConfig = config.withEvents(events.sendPort);
    final isolate = await Isolate.spawn(_runWorker, workerConfig);
    try {
      final worker = await ready.future;
      return SemanticIndex._(
        config.expectedDimensions,
        isolate,
        worker,
        events,
        subscription,
        pending,
      );
    } catch (_) {
      disposed = true;
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      events.close();
      rethrow;
    }
  }

  final int dimensions;
  final Isolate _isolate;
  final SendPort _worker;
  final ReceivePort _events;
  final StreamSubscription<dynamic> _subscription;
  final Map<int, Completer<List<SemanticHit>>> _pending;
  int _nextRequestId = 0;
  bool _disposed = false;

  @override
  Future<List<SemanticHit>> search(List<double> query, {int limit = 8}) {
    if (_disposed || limit <= 0) return Future.value(const []);
    _validateQuery(query, dimensions);
    final id = _nextRequestId++;
    final completer = Completer<List<SemanticHit>>();
    _pending[id] = completer;
    _worker.send(
      _WorkerSearch(
        id,
        Float64List.fromList(query),
        math.min(limit, _maximumResults),
      ),
    );
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(const []);
    }
    _pending.clear();
    _worker.send(null);
    _isolate.kill(priority: Isolate.immediate);
    await _subscription.cancel();
    _events.close();
  }
}

void _validateQuery(List<double> query, int dimensions) {
  if (query.length != dimensions) {
    throw ArgumentError.value(
      query.length,
      'query',
      'must have $dimensions elements',
    );
  }
  var squaredNorm = 0.0;
  for (final value in query) {
    if (!value.isFinite) {
      throw ArgumentError.value(query, 'query', 'must be finite');
    }
    squaredNorm += value * value;
  }
  if ((math.sqrt(squaredNorm) - 1).abs() > 1e-4) {
    throw ArgumentError.value(query, 'query', 'must be normalized');
  }
}

Future<void> _runWorker(_WorkerConfig config) async {
  final events = config.events!;
  try {
    final bytes = await _loadBytes(config);
    final index = _WorkerIndex.parse(bytes, config);
    final requests = ReceivePort();
    events.send(_WorkerReady(requests.sendPort));
    await for (final message in requests) {
      if (message == null) {
        requests.close();
        return;
      }
      final request = message as _WorkerSearch;
      events.send(
        _WorkerResponse(request.id, index.search(request.query, request.limit)),
      );
    }
  } catch (error) {
    events.send(_WorkerFailure(error.runtimeType.toString()));
  }
}

Future<Uint8List> _loadBytes(_WorkerConfig config) async {
  final transferable = config.bytes;
  if (transferable != null) return transferable.materialize().asUint8List();
  final token = config.rootIsolateToken;
  final assetPath = config.assetPath;
  if (token == null || assetPath == null) {
    throw StateError('Semantic index worker has no asset source');
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final encoded = utf8.encode(Uri(path: assetPath).path);
  final data = await BackgroundIsolateBinaryMessenger.instance.send(
    'flutter/assets',
    ByteData.sublistView(Uint8List.fromList(encoded)),
  );
  if (data == null) throw StateError('Semantic index asset is unavailable');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class _WorkerIndex {
  _WorkerIndex._({
    required this.bytes,
    required this.metadata,
    required this.dimensions,
    required this.rowOffset,
    required this.rowLength,
    required this.ordinals,
    required this.books,
    required this.chapters,
    required this.verses,
    required this.scales,
  });

  factory _WorkerIndex.parse(Uint8List bytes, _WorkerConfig config) {
    if (bytes.length < _headerLength) {
      throw const FormatException('Truncated semantic index header');
    }
    final data = ByteData.sublistView(bytes);
    if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != _magic) {
      throw const FormatException('Invalid semantic index magic');
    }
    final version = data.getUint16(8, Endian.little);
    if (version != _formatVersion) {
      throw FormatException('Unsupported semantic index version: $version');
    }
    final dimensions = data.getUint16(10, Endian.little);
    if (dimensions != config.expectedDimensions) {
      throw const FormatException('Semantic index dimensions do not match');
    }
    final metadataLength = data.getUint32(12, Endian.little);
    final rowCount = data.getUint32(16, Endian.little);
    final rowLength = _rowHeaderLength + dimensions;
    final rowOffset = _headerLength + metadataLength;
    if (rowOffset + rowCount * rowLength != bytes.length) {
      throw const FormatException('Truncated or trailing semantic index data');
    }
    final metadata = _parseMetadata(
      Uint8List.sublistView(bytes, _headerLength, rowOffset),
    );
    _validateMetadata(metadata, config);

    final ordinals = Uint8List(rowCount);
    final books = Uint8List(rowCount);
    final chapters = Uint16List(rowCount);
    final verses = Uint16List(rowCount);
    final scales = Float32List(rowCount);
    final seen = <int>{};
    for (var row = 0; row < rowCount; row++) {
      final offset = rowOffset + row * rowLength;
      final ordinal = data.getUint8(offset);
      final book = data.getUint8(offset + 1);
      final chapter = data.getUint16(offset + 2, Endian.little);
      final verse = data.getUint16(offset + 4, Endian.little);
      final scale = data.getFloat32(offset + 6, Endian.little);
      if (ordinal >= metadata.translations.length ||
          book == 0 ||
          chapter == 0 ||
          verse == 0 ||
          !scale.isFinite ||
          scale <= 0) {
        throw const FormatException('Invalid semantic index row');
      }
      final key = (((ordinal << 8) | book) << 16 | chapter) << 16 | verse;
      if (!seen.add(key)) {
        throw const FormatException('Duplicate semantic index row');
      }
      ordinals[row] = ordinal;
      books[row] = book;
      chapters[row] = chapter;
      verses[row] = verse;
      scales[row] = scale;
    }
    return _WorkerIndex._(
      bytes: bytes,
      metadata: metadata,
      dimensions: dimensions,
      rowOffset: rowOffset,
      rowLength: rowLength,
      ordinals: ordinals,
      books: books,
      chapters: chapters,
      verses: verses,
      scales: scales,
    );
  }

  final Uint8List bytes;
  final SemanticAssetMetadata metadata;
  final int dimensions;
  final int rowOffset;
  final int rowLength;
  final Uint8List ordinals;
  final Uint8List books;
  final Uint16List chapters;
  final Uint16List verses;
  final Float32List scales;

  List<SemanticHit> search(Float64List query, int limit) {
    final strongest = <int, _ScoredRow>{};
    for (var row = 0; row < ordinals.length; row++) {
      var dot = 0.0;
      final vectorOffset = rowOffset + row * rowLength + _rowHeaderLength;
      for (var dimension = 0; dimension < dimensions; dimension++) {
        final byte = bytes[vectorOffset + dimension];
        dot += query[dimension] * (byte > 127 ? byte - 256 : byte);
      }
      final score = dot * scales[row];
      final key = (books[row] << 32) | (chapters[row] << 16) | verses[row];
      final current = strongest[key];
      if (current == null || score > current.score) {
        strongest[key] = _ScoredRow(row, score);
      }
    }

    final top = <_ScoredRow>[];
    for (final candidate in strongest.values) {
      var insertion = 0;
      while (insertion < top.length &&
          _compareRows(top[insertion], candidate) <= 0) {
        insertion++;
      }
      if (insertion < limit) {
        top.insert(insertion, candidate);
        if (top.length > limit) top.removeLast();
      } else if (top.length < limit) {
        top.add(candidate);
      }
    }
    return top
        .map((entry) {
          final row = entry.row;
          return SemanticHit(
            reference: ScriptureReference(
              book: books[row],
              chapter: chapters[row],
              startVerse: verses[row],
              endVerse: verses[row],
            ),
            translationId: metadata.translations[ordinals[row]],
            score: entry.score,
          );
        })
        .toList(growable: false);
  }

  int _compareRows(_ScoredRow left, _ScoredRow right) {
    var order = right.score.compareTo(left.score);
    if (order == 0) order = books[left.row].compareTo(books[right.row]);
    if (order == 0) {
      order = chapters[left.row].compareTo(chapters[right.row]);
    }
    if (order == 0) order = verses[left.row].compareTo(verses[right.row]);
    if (order == 0) {
      order = metadata.translations[ordinals[left.row]].compareTo(
        metadata.translations[ordinals[right.row]],
      );
    }
    return order;
  }
}

class _ScoredRow {
  const _ScoredRow(this.row, this.score);

  final int row;
  final double score;
}

class _WorkerConfig {
  const _WorkerConfig._({
    required this.events,
    required this.assetPath,
    required this.rootIsolateToken,
    required this.bytes,
    required this.expectedModelId,
    required this.expectedModelRevision,
    required this.expectedDimensions,
    required this.expectedBibleFingerprint,
    required this.expectedTranslationIds,
  });

  factory _WorkerConfig.asset({
    required String assetPath,
    required RootIsolateToken rootIsolateToken,
    required String expectedModelId,
    required String expectedModelRevision,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
    required List<String> expectedTranslationIds,
  }) => _WorkerConfig._(
    events: null,
    assetPath: assetPath,
    rootIsolateToken: rootIsolateToken,
    bytes: null,
    expectedModelId: expectedModelId,
    expectedModelRevision: expectedModelRevision,
    expectedDimensions: expectedDimensions,
    expectedBibleFingerprint: expectedBibleFingerprint,
    expectedTranslationIds: expectedTranslationIds,
  );

  factory _WorkerConfig.bytes({
    required TransferableTypedData bytes,
    required String expectedModelId,
    required String expectedModelRevision,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
    required List<String> expectedTranslationIds,
  }) => _WorkerConfig._(
    events: null,
    assetPath: null,
    rootIsolateToken: null,
    bytes: bytes,
    expectedModelId: expectedModelId,
    expectedModelRevision: expectedModelRevision,
    expectedDimensions: expectedDimensions,
    expectedBibleFingerprint: expectedBibleFingerprint,
    expectedTranslationIds: expectedTranslationIds,
  );

  final SendPort? events;
  final String? assetPath;
  final RootIsolateToken? rootIsolateToken;
  final TransferableTypedData? bytes;
  final String expectedModelId;
  final String expectedModelRevision;
  final int expectedDimensions;
  final String expectedBibleFingerprint;
  final List<String> expectedTranslationIds;

  _WorkerConfig withEvents(SendPort value) => _WorkerConfig._(
    events: value,
    assetPath: assetPath,
    rootIsolateToken: rootIsolateToken,
    bytes: bytes,
    expectedModelId: expectedModelId,
    expectedModelRevision: expectedModelRevision,
    expectedDimensions: expectedDimensions,
    expectedBibleFingerprint: expectedBibleFingerprint,
    expectedTranslationIds: expectedTranslationIds,
  );
}

class _WorkerReady {
  const _WorkerReady(this.port);
  final SendPort port;
}

class _WorkerFailure {
  const _WorkerFailure(this.category);
  final String category;
}

class _WorkerSearch {
  const _WorkerSearch(this.id, this.query, this.limit);
  final int id;
  final Float64List query;
  final int limit;
}

class _WorkerResponse {
  const _WorkerResponse(this.id, this.hits);
  final int id;
  final List<SemanticHit> hits;
}

void _validateMetadata(SemanticAssetMetadata metadata, _WorkerConfig config) {
  if (metadata.modelId != config.expectedModelId) {
    throw const FormatException('Semantic index model does not match');
  }
  if (metadata.modelRevision != config.expectedModelRevision) {
    throw const FormatException('Semantic index revision does not match');
  }
  if (metadata.quantization != _quantization) {
    throw const FormatException('Semantic index quantization does not match');
  }
  if (metadata.bibleFingerprint != config.expectedBibleFingerprint) {
    throw const FormatException(
      'Semantic index Bible fingerprint does not match',
    );
  }
  final expected = [...config.expectedTranslationIds]..sort();
  final indexed = [...metadata.translations]..sort();
  if (!_sameStrings(expected, indexed)) {
    throw const FormatException(
      'Semantic index translation set does not match',
    );
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

SemanticAssetMetadata _parseMetadata(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) throw const FormatException();
    String stringValue(String key) {
      final field = value[key];
      if (field is! String || field.isEmpty) throw const FormatException();
      return field;
    }

    final translationsValue = value['translations'];
    if (translationsValue is! List ||
        translationsValue.isEmpty ||
        translationsValue.any((item) => item is! String || item.isEmpty)) {
      throw const FormatException();
    }
    final translations = translationsValue.cast<String>();
    if (translations.toSet().length != translations.length) {
      throw const FormatException();
    }
    return SemanticAssetMetadata(
      modelId: stringValue('modelId'),
      modelRevision: stringValue('modelRevision'),
      bibleFingerprint: stringValue('bibleFingerprint'),
      translations: List.unmodifiable(translations),
      quantization: stringValue('quantization'),
      createdByVersion: stringValue('createdByVersion'),
    );
  } on FormatException {
    throw const FormatException('Invalid semantic index metadata');
  }
}
