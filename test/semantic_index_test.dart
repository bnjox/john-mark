import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/features/semantic/semantic_index.dart';

void main() {
  late Uint8List bytes;

  setUp(() {
    bytes = File('test/fixtures/semantic/tiny_index.bin').readAsBytesSync();
  });

  SemanticIndex parse([Uint8List? input]) => SemanticIndex.parse(
    input ?? bytes,
    expectedModelId: 'BAAI/bge-base-en-v1.5',
    expectedDimensions: 768,
    expectedBibleFingerprint: 'fixture-db',
  );

  test('parses valid metadata and searches the synthetic index', () async {
    final index = parse();

    expect(index.metadata.modelRevision, 'fixture-revision');
    expect(index.metadata.translations, ['alpha', 'beta']);
    final query = List<double>.filled(768, 0)..first = 1;
    final hits = await index.search(query, limit: 8);

    expect(hits, hasLength(8));
    expect(hits.first.translationId, 'alpha');
    expect(hits.first.reference.book, 43);
    expect(hits.first.reference.chapter, 3);
    expect(hits.first.reference.startVerse, 16);
  });

  test('rejects bad magic, unsupported versions, and truncation', () {
    final badMagic = Uint8List.fromList(bytes)..[0] = 0;
    final badVersion = Uint8List.fromList(bytes)..[8] = 2;

    expect(() => parse(badMagic), throwsFormatException);
    expect(() => parse(badVersion), throwsFormatException);
    expect(
      () => parse(Uint8List.sublistView(bytes, 0, bytes.length - 1)),
      throwsFormatException,
    );
  });

  test('rejects incompatible model, dimensions, and fingerprint', () {
    expect(
      () => SemanticIndex.parse(
        bytes,
        expectedModelId: 'other-model',
        expectedDimensions: 768,
        expectedBibleFingerprint: 'fixture-db',
      ),
      throwsFormatException,
    );
    expect(
      () => SemanticIndex.parse(
        bytes,
        expectedModelId: 'BAAI/bge-base-en-v1.5',
        expectedDimensions: 384,
        expectedBibleFingerprint: 'fixture-db',
      ),
      throwsFormatException,
    );
    expect(
      () => SemanticIndex.parse(
        bytes,
        expectedModelId: 'BAAI/bge-base-en-v1.5',
        expectedDimensions: 768,
        expectedBibleFingerprint: 'stale-db',
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid translation ordinals and duplicate rows', () {
    final metadataLength = ByteData.sublistView(bytes)
        .getUint32(12, Endian.little);
    final firstRow = 20 + metadataLength;
    final invalidOrdinal = Uint8List.fromList(bytes)..[firstRow] = 2;
    final duplicateRow = Uint8List.fromList(bytes);
    duplicateRow.setRange(
      firstRow + 778,
      firstRow + 784,
      duplicateRow,
      firstRow,
    );

    expect(() => parse(invalidOrdinal), throwsFormatException);
    expect(() => parse(duplicateRow), throwsFormatException);
  });

  test('rejects zero-norm and non-normalized queries', () async {
    final index = parse();

    expect(
      () => index.search(List<double>.filled(768, 0)),
      throwsArgumentError,
    );
    expect(
      () => index.search(List<double>.filled(768, 1)),
      throwsArgumentError,
    );
  });

  test('ties use canonical reference then translation ordering', () async {
    final query = List<double>.filled(768, 0)..first = 1;
    final hits = await parse().search(query, limit: 3);

    expect(
      hits.map(
        (hit) =>
            '${hit.reference.book}:${hit.reference.chapter}:'
            '${hit.reference.startVerse}:${hit.translationId}',
      ),
      ['43:3:16:alpha', '43:3:16:beta', '45:8:28:alpha'],
    );
  });

  test('search never returns more than eight hits', () async {
    final query = List<double>.filled(768, 0)..first = 1;

    expect(await parse().search(query, limit: 100), hasLength(8));
  });
}
