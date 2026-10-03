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

class SemanticIndex {
  SemanticIndex._({
    required this.metadata,
    required this.dimensions,
    required this._rows,
  });

  factory SemanticIndex.parse(
    Uint8List bytes, {
    required String expectedModelId,
    required int expectedDimensions,
    required String expectedBibleFingerprint,
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
    if (metadata.bibleFingerprint != expectedBibleFingerprint) {
      throw const FormatException(
        'Semantic index Bible fingerprint does not match',
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
  final List<_IndexRow> _rows;

  Future<List<SemanticHit>> search(List<double> query, {int limit = 8}) {
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
    if (limit <= 0 || _rows.isEmpty) return Future.value(const []);

    final boundedLimit = math.min(limit, _maximumResults);
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
    final transferable = TransferableTypedData.fromList([vectorBytes]);

    return Isolate.run(() {
      final vectors = transferable.materialize().asUint8List();
      final scored = <(int, double)>[];
      for (var row = 0; row < ordinals.length; row++) {
        var dot = 0.0;
        final start = row * dimensions;
        for (var dimension = 0; dimension < dimensions; dimension++) {
          final byte = vectors[start + dimension];
          dot += query[dimension] * (byte > 127 ? byte - 256 : byte);
        }
        scored.add((row, dot * scales[row]));
      }
      scored.sort((left, right) {
        final scoreOrder = right.$2.compareTo(left.$2);
        if (scoreOrder != 0) return scoreOrder;
        final leftRow = left.$1;
        final rightRow = right.$1;
        var order = books[leftRow].compareTo(books[rightRow]);
        if (order == 0) order = chapters[leftRow].compareTo(chapters[rightRow]);
        if (order == 0) order = verses[leftRow].compareTo(verses[rightRow]);
        if (order == 0) {
          order = metadata.translations[ordinals[leftRow]].compareTo(
            metadata.translations[ordinals[rightRow]],
          );
        }
        return order;
      });
      return scored
          .take(boundedLimit)
          .map((entry) {
            final row = entry.$1;
            return SemanticHit(
              reference: ScriptureReference(
                book: books[row],
                chapter: chapters[row],
                startVerse: verses[row],
                endVerse: verses[row],
              ),
              translationId: metadata.translations[ordinals[row]],
              score: entry.$2,
            );
          })
          .toList(growable: false);
    });
  }
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
