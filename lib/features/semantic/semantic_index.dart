import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/models.dart';
import 'semantic_retriever.dart';

const _magic = 'SCRIPIDX';
const _formatVersion = 1;
const _headerLength = 20;
const _rowHeaderLength = 10;
const _maximumResults = 8;
const _quantization = 'symmetric-int8-per-row';

class SemanticIndex implements SemanticVectorIndex {
  SemanticIndex._({
    required this.metadata,
    required this.dimensions,
    required List<_IndexRow> rows,
  }) : _rowCount = rows.length,
       _rows = rows;

  factory SemanticIndex.parse(
    Uint8List bytes, {
    required String expectedModelId,
    required String expectedModelRevision,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
    required Iterable<String> expectedTranslationIds,
  }) {
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
    if (dimensions != expectedDimensions) {
      throw const FormatException('Semantic index dimensions do not match');
    }
    final metadataLength = data.getUint32(12, Endian.little);
    final rowCount = data.getUint32(16, Endian.little);
    final rowLength = _rowHeaderLength + dimensions;
    final expectedLength =
        _headerLength + metadataLength + rowCount * rowLength;
    if (expectedLength != bytes.length) {
      throw const FormatException('Truncated or trailing semantic index data');
    }

    final metadata = _parseMetadata(
      Uint8List.sublistView(
        bytes,
        _headerLength,
        _headerLength + metadataLength,
      ),
    );
    if (metadata.modelId != expectedModelId) {
      throw const FormatException('Semantic index model does not match');
    }
    if (metadata.modelRevision != expectedModelRevision) {
      throw const FormatException('Semantic index revision does not match');
    }
    if (metadata.quantization != _quantization) {
      throw const FormatException('Semantic index quantization does not match');
    }
    if (metadata.bibleFingerprint != expectedBibleFingerprint) {
      throw const FormatException(
        'Semantic index Bible fingerprint does not match',
      );
    }
    final expectedTranslations = expectedTranslationIds.toList()..sort();
    final indexedTranslations = [...metadata.translations]..sort();
    if (!_sameStrings(expectedTranslations, indexedTranslations)) {
      throw const FormatException(
        'Semantic index translation set does not match',
      );
    }

    final rows = <_IndexRow>[];
    final seen = <String>{};
    var offset = _headerLength + metadataLength;
    for (var i = 0; i < rowCount; i++) {
      final translationOrdinal = data.getUint8(offset);
      final book = data.getUint8(offset + 1);
      final chapter = data.getUint16(offset + 2, Endian.little);
      final verse = data.getUint16(offset + 4, Endian.little);
      final scale = data.getFloat32(offset + 6, Endian.little);
      if (translationOrdinal >= metadata.translations.length) {
        throw const FormatException(
          'Invalid semantic index translation ordinal',
        );
      }
      if (book == 0 ||
          chapter == 0 ||
          verse == 0 ||
          !scale.isFinite ||
          scale <= 0) {
        throw const FormatException('Invalid semantic index row');
      }
      final key = '$translationOrdinal:$book:$chapter:$verse';
      if (!seen.add(key)) {
        throw const FormatException('Duplicate semantic index row');
      }
      rows.add(
        _IndexRow(
          translationOrdinal: translationOrdinal,
          book: book,
          chapter: chapter,
          verse: verse,
          scale: scale,
          vector: Int8List.sublistView(
            bytes,
            offset + _rowHeaderLength,
            offset + rowLength,
          ),
        ),
      );
      offset += rowLength;
    }
    return SemanticIndex._(
      metadata: metadata,
      dimensions: dimensions,
      rows: rows,
    );
  }

  final SemanticAssetMetadata metadata;
  final int dimensions;
  final int _rowCount;
  List<_IndexRow> _rows;
  Future<SendPort>? _worker;
  bool _disposed = false;

  @override
  Future<List<SemanticHit>> search(List<double> query, {int limit = 8}) async {
    if (_disposed) return const [];
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
    if (limit <= 0 || _rowCount == 0) return const [];

    final boundedLimit = math.min(limit, _maximumResults);
    final worker = await (_worker ??= _startWorker());
    if (_disposed) return const [];
    final response = ReceivePort();
    worker.send(_SearchRequest(query, boundedLimit, response.sendPort));
    try {
      return await response.first as List<SemanticHit>;
    } finally {
      response.close();
    }
  }

  Future<SendPort> _startWorker() async {
    final ready = ReceivePort();
    final vectorBytes = Uint8List(_rows.length * dimensions);
    final ordinals = <int>[];
    final books = <int>[];
    final chapters = <int>[];
    final verses = <int>[];
    final scales = <double>[];
    for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++) {
      final row = _rows[rowIndex];
      vectorBytes.setRange(
        rowIndex * dimensions,
        (rowIndex + 1) * dimensions,
        row.vector,
      );
      ordinals.add(row.translationOrdinal);
      books.add(row.book);
      chapters.add(row.chapter);
      verses.add(row.verse);
      scales.add(row.scale);
    }
    _rows = const [];
    final transferable = TransferableTypedData.fromList([vectorBytes]);
    await Isolate.spawn(
      _runSearchWorker,
      _SearchWorkerConfig(
        ready: ready.sendPort,
        vectors: transferable,
        ordinals: ordinals,
        books: books,
        chapters: chapters,
        verses: verses,
        scales: scales,
        translations: metadata.translations,
        dimensions: dimensions,
      ),
    );
    try {
      return await ready.first as SendPort;
    } finally {
      ready.close();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _rows = const [];
    final worker = _worker;
    if (worker != null) (await worker).send(null);
  }
}

void _runSearchWorker(_SearchWorkerConfig config) {
  final vectors = config.vectors.materialize().asUint8List();
  final requests = ReceivePort();
  config.ready.send(requests.sendPort);
  requests.listen((message) {
    if (message == null) {
      requests.close();
      return;
    }
    final request = message as _SearchRequest;
    final strongest = <(int, int, int), (int, double)>{};
    for (var row = 0; row < config.ordinals.length; row++) {
      var dot = 0.0;
      final start = row * config.dimensions;
      for (var dimension = 0; dimension < config.dimensions; dimension++) {
        final byte = vectors[start + dimension];
        dot += request.query[dimension] * (byte > 127 ? byte - 256 : byte);
      }
      final score = dot * config.scales[row];
      final key = (config.books[row], config.chapters[row], config.verses[row]);
      final current = strongest[key];
      if (current == null || score > current.$2) strongest[key] = (row, score);
    }
    final scored = strongest.values.toList(growable: false)
      ..sort((left, right) {
        final scoreOrder = right.$2.compareTo(left.$2);
        if (scoreOrder != 0) return scoreOrder;
        final leftRow = left.$1;
        final rightRow = right.$1;
        var order = config.books[leftRow].compareTo(config.books[rightRow]);
        if (order == 0) {
          order = config.chapters[leftRow].compareTo(config.chapters[rightRow]);
        }
        if (order == 0) {
          order = config.verses[leftRow].compareTo(config.verses[rightRow]);
        }
        return order;
      });
    request.response.send(
      scored
          .take(request.limit)
          .map((entry) {
            final row = entry.$1;
            return SemanticHit(
              reference: ScriptureReference(
                book: config.books[row],
                chapter: config.chapters[row],
                startVerse: config.verses[row],
                endVerse: config.verses[row],
              ),
              translationId: config.translations[config.ordinals[row]],
              score: entry.$2,
            );
          })
          .toList(growable: false),
    );
  });
}

class _SearchWorkerConfig {
  const _SearchWorkerConfig({
    required this.ready,
    required this.vectors,
    required this.ordinals,
    required this.books,
    required this.chapters,
    required this.verses,
    required this.scales,
    required this.translations,
    required this.dimensions,
  });

  final SendPort ready;
  final TransferableTypedData vectors;
  final List<int> ordinals;
  final List<int> books;
  final List<int> chapters;
  final List<int> verses;
  final List<double> scales;
  final List<String> translations;
  final int dimensions;
}

class _SearchRequest {
  const _SearchRequest(this.query, this.limit, this.response);

  final List<double> query;
  final int limit;
  final SendPort response;
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

class _IndexRow {
  const _IndexRow({
    required this.translationOrdinal,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.scale,
    required this.vector,
  });

  final int translationOrdinal;
  final int book;
  final int chapter;
  final int verse;
  final double scale;
  final Int8List vector;
}
