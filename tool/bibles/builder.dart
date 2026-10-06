import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../../lib/features/bible/corpus_manifest.dart';
import 'fsb_parser.dart';
import 'model.dart';
import 'xml_parser.dart';

class BuiltTranslation {
  const BuiltTranslation({
    required this.id,
    required this.name,
    required this.verseCount,
  });

  final String id;
  final String name;
  final int verseCount;
}

class BibleBuildResult {
  const BibleBuildResult({
    required this.outputPath,
    required this.manifestPath,
    required this.translations,
    required this.verseCount,
  });

  final String outputPath;
  final String manifestPath;
  final List<BuiltTranslation> translations;
  final int verseCount;
}

class BibleBuilder {
  Future<BibleBuildResult> build(List<File> sources, String outputPath) async {
    if (sources.isEmpty) {
      throw const FormatException('At least one Bible source is required');
    }

    final parsed = <_ParsedBible>[];
    final ids = <String>{};
    for (final source in sources) {
      final bible = await _parse(source);
      final id = _slug(bible.name);
      if (id.isEmpty) {
        throw FormatException(
          '${bible.sourcePath}: ${_nameLocation(source)} cannot form an ASCII ID',
        );
      }
      if (!ids.add(id)) {
        throw FormatException(
          '${bible.sourcePath}: ${_nameLocation(source)} creates duplicate '
          'translation ID "$id"',
        );
      }
      parsed.add(_ParsedBible(id, bible));
    }
    parsed.sort((left, right) => left.id.compareTo(right.id));
    final fingerprint = fingerprintCorpus(_fingerprintVerses(parsed));

    final output = File(outputPath).absolute;
    final manifestOutput = File(
      path.join(
        output.parent.path,
        '${path.basenameWithoutExtension(output.path)}.manifest.json',
      ),
    );
    await output.parent.create(recursive: true);
    final temporary = File(
      '${output.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    final temporaryManifest = File('${temporary.path}.manifest.json');
    Database? database;
    try {
      database = sqlite3.open(temporary.path);
      _createSchema(database);
      database.execute('BEGIN IMMEDIATE');
      final builtTranslations = <BuiltTranslation>[];
      var totalVerses = 0;
      try {
        _insertMetadata(database, fingerprint);
        for (final item in parsed) {
          final count = _insertBible(database, item.id, item.bible);
          totalVerses += count;
          builtTranslations.add(
            BuiltTranslation(
              id: item.id,
              name: item.bible.name,
              verseCount: count,
            ),
          );
        }
        database.execute('PRAGMA user_version = $corpusSchemaVersion');
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      database.execute('VACUUM');
      database.close();
      database = null;

      final assetId = (await sha256.bind(temporary.openRead()).first)
          .toString();
      final manifest = CorpusManifest(
        assetId: assetId,
        databaseBytes: await temporary.length(),
        translationIds: parsed.map((item) => item.id).toList(growable: false),
        corpusFingerprint: fingerprint,
      );
      await temporaryManifest.writeAsString(manifest.encode(), flush: true);
      await temporary.rename(output.path);
      await temporaryManifest.rename(manifestOutput.path);
      return BibleBuildResult(
        outputPath: output.path,
        manifestPath: manifestOutput.path,
        translations: builtTranslations,
        verseCount: totalVerses,
      );
    } finally {
      database?.close();
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (await temporaryManifest.exists()) {
        await temporaryManifest.delete();
      }
    }
  }

  Future<SourceBible> _parse(File source) {
    switch (path.extension(source.path).toLowerCase()) {
      case '.fsb':
        return FsbParser().parse(source);
      case '.xml':
        return ZefaniaXmlParser().parse(source);
      default:
        throw FormatException(
          '${source.path}: unsupported Bible source extension '
          '"${path.extension(source.path)}"',
        );
    }
  }

  String _nameLocation(File source) =>
      path.extension(source.path).toLowerCase() == '.xml'
      ? '/XMLBIBLE/@biblename'
      : r'$[1].name';
}

class _ParsedBible {
  const _ParsedBible(this.id, this.bible);

  final String id;
  final SourceBible bible;
}

void _createSchema(Database database) {
  database.execute('''
    CREATE TABLE metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE translations (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE books (
      translation_id TEXT NOT NULL,
      number INTEGER NOT NULL,
      name TEXT NOT NULL,
      PRIMARY KEY (translation_id, number)
    ) WITHOUT ROWID;
    CREATE TABLE verses (
      translation_id TEXT NOT NULL,
      book_number INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      display_text TEXT NOT NULL,
      PRIMARY KEY (translation_id, book_number, chapter, verse)
    ) WITHOUT ROWID;
  ''');
}

void _insertMetadata(Database database, String fingerprint) {
  for (final entry in {
    'schema_version': '$corpusSchemaVersion',
    'fingerprint_contract': '$corpusFingerprintContract',
    'corpus_fingerprint': fingerprint,
  }.entries) {
    database.execute('INSERT INTO metadata (key, value) VALUES (?, ?)', [
      entry.key,
      entry.value,
    ]);
  }
}

int _insertBible(Database database, String id, SourceBible bible) {
  database.execute('INSERT INTO translations (id, name) VALUES (?, ?)', [
    id,
    bible.name,
  ]);
  final books = [...bible.books]
    ..sort((left, right) => left.number.compareTo(right.number));
  var verseCount = 0;
  for (final book in books) {
    database.execute(
      'INSERT INTO books (translation_id, number, name) VALUES (?, ?, ?)',
      [id, book.number, book.name],
    );
    final chapters = [...book.chapters]
      ..sort((left, right) => left.number.compareTo(right.number));
    for (final chapter in chapters) {
      final verses = [...chapter.verses]
        ..sort((left, right) => left.number.compareTo(right.number));
      for (final verse in verses) {
        _insertVerse(database, id, book.number, chapter.number, verse);
        verseCount++;
      }
    }
  }
  return verseCount;
}

void _insertVerse(
  Database database,
  String translationId,
  int book,
  int chapter,
  SourceVerse verse,
) {
  database.execute(
    '''
      INSERT INTO verses (
        translation_id,
        book_number,
        chapter,
        verse,
        display_text
      ) VALUES (?, ?, ?, ?, ?)
    ''',
    [translationId, book, chapter, verse.number, verse.text],
  );
}

Iterable<CorpusFingerprintVerse> _fingerprintVerses(
  List<_ParsedBible> parsed,
) sync* {
  for (final item in parsed) {
    for (final book in item.bible.books) {
      for (final chapter in book.chapters) {
        for (final verse in chapter.verses) {
          yield CorpusFingerprintVerse(
            translationId: item.id,
            book: book.number,
            chapter: chapter.number,
            verse: verse.number,
            text: verse.text,
          );
        }
      }
    }
  }
}

String _slug(String name) {
  var ascii = name.toLowerCase();
  const replacements = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
  };
  replacements.forEach((from, to) => ascii = ascii.replaceAll(from, to));
  return ascii
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
