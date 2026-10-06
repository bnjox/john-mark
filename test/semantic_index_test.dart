import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/features/semantic/semantic_index.dart';

void main() {
  test('returns distinct references and reuses its search worker', () async {
    final index = await SemanticIndex.fromBytes(
      _indexBytes(),
      expectedModelId: 'test-model',
      expectedModelRevision: 'test-revision',
      expectedDimensions: 2,
      expectedBibleFingerprint: 'test-fingerprint',
      expectedTranslationIds: const ['alpha', 'beta'],
    );
    addTearDown(index.dispose);

    final first = await index.search(const [1, 0], limit: 2);
    final second = await index.search(const [1, 0], limit: 2);

    for (final hits in [first, second]) {
      expect(hits, hasLength(2));
      expect(
        hits.map(
          (hit) => (
            hit.reference.book,
            hit.reference.chapter,
            hit.reference.startVerse,
          ),
        ),
        [(43, 3, 16), (19, 23, 1)],
      );
      expect(hits.first.translationId, 'alpha');
    }
  });

  test('rejects metadata that does not match the corpus', () async {
    await expectLater(
      SemanticIndex.fromBytes(
        _indexBytes(),
        expectedModelId: 'test-model',
        expectedModelRevision: 'test-revision',
        expectedDimensions: 2,
        expectedBibleFingerprint: 'different-fingerprint',
        expectedTranslationIds: const ['alpha', 'beta'],
      ),
      throwsStateError,
    );
  });

  test('dispose completes an in-flight search without retaining it', () async {
    final index = await SemanticIndex.fromBytes(
      _indexBytes(rowCopies: 10000),
      expectedModelId: 'test-model',
      expectedModelRevision: 'test-revision',
      expectedDimensions: 2,
      expectedBibleFingerprint: 'test-fingerprint',
      expectedTranslationIds: const ['alpha', 'beta'],
    );

    final search = index.search(const [1, 0], limit: 2);
    await index.dispose();

    expect(await search, isEmpty);
    expect(await index.search(const [1, 0]), isEmpty);
  });
}

Uint8List _indexBytes({int rowCopies = 1}) {
  const dimensions = 2;
  final metadata = utf8.encode(
    jsonEncode({
      'modelId': 'test-model',
      'modelRevision': 'test-revision',
      'bibleFingerprint': 'test-fingerprint',
      'translations': ['alpha', 'beta'],
      'quantization': 'symmetric-int8-per-row',
      'createdByVersion': 'test',
    }),
  );
  final sourceRows = [
    (translation: 0, book: 43, chapter: 3, verse: 16, score: 1.0),
    (translation: 1, book: 43, chapter: 3, verse: 16, score: 0.99),
    (translation: 0, book: 19, chapter: 23, verse: 1, score: 0.80),
    (translation: 0, book: 50, chapter: 4, verse: 13, score: 0.70),
  ];
  final rows = [
    for (var copy = 0; copy < rowCopies; copy++)
      for (final row in sourceRows)
        (
          translation: row.translation,
          book: row.book,
          chapter: row.chapter + copy,
          verse: row.verse,
          score: row.score,
        ),
  ];
  const headerLength = 20;
  const rowLength = 10 + dimensions;
  final bytes = Uint8List(
    headerLength + metadata.length + rows.length * rowLength,
  );
  bytes.setRange(0, 8, ascii.encode('SCRIPIDX'));
  final data = ByteData.sublistView(bytes);
  data.setUint16(8, 1, Endian.little);
  data.setUint16(10, dimensions, Endian.little);
  data.setUint32(12, metadata.length, Endian.little);
  data.setUint32(16, rows.length, Endian.little);
  bytes.setRange(headerLength, headerLength + metadata.length, metadata);
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final offset = headerLength + metadata.length + index * rowLength;
    data.setUint8(offset, row.translation);
    data.setUint8(offset + 1, row.book);
    data.setUint16(offset + 2, row.chapter, Endian.little);
    data.setUint16(offset + 4, row.verse, Endian.little);
    data.setFloat32(offset + 6, row.score / 127, Endian.little);
    data.setInt8(offset + 10, 127);
    data.setInt8(offset + 11, index == rows.length - 1 ? 100 : 0);
  }
  return bytes;
}
