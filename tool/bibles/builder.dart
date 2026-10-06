import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import 'fsb_parser.dart';
import 'model.dart';
import 'xml_parser.dart';

class BuiltTranslation {
  const BuiltTranslation({
    required this.id,
    required this.name,
    required this.passageCount,
  });

  final String id;
  final String name;
  final int passageCount;
}

class BibleBuildResult {
  const BibleBuildResult({
    required this.outputPath,
    required this.translations,
    required this.passageCount,
  });

  final String outputPath;
  final List<BuiltTranslation> translations;
  final int passageCount;
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

    final output = File(outputPath).absolute;
    await output.parent.create(recursive: true);
    final temporary = File(
      '${output.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    Database? database;
    try {
      database = sqlite3.open(temporary.path);
      _createSchema(database);
      database.execute('BEGIN IMMEDIATE');
      final builtTranslations = <BuiltTranslation>[];
      var totalPassages = 0;
      try {
        for (final item in parsed) {
          final count = _insertBible(database, item.id, item.bible);
          totalPassages += count;
          builtTranslations.add(
            BuiltTranslation(
              id: item.id,
              name: item.bible.name,
              passageCount: count,
            ),
          );
        }
        database.execute('PRAGMA user_version = 2');
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      database.execute('VACUUM');
      database.close();
      database = null;

      await temporary.rename(output.path);
      return BibleBuildResult(
        outputPath: output.path,
        translations: builtTranslations,
        passageCount: totalPassages,
      );
    } finally {
      database?.close();
      if (await temporary.exists()) {
        await temporary.delete();
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
    CREATE TABLE translations (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    );
    CREATE TABLE books (
      translation_id TEXT NOT NULL,
      number INTEGER NOT NULL,
      name TEXT NOT NULL,
      PRIMARY KEY (translation_id, number)
    );
    CREATE TABLE passages (
      id INTEGER PRIMARY KEY,
      translation_id TEXT NOT NULL,
      book_number INTEGER NOT NULL,
      chapter INTEGER NOT NULL,
      start_verse INTEGER NOT NULL,
      end_verse INTEGER NOT NULL,
      label TEXT NOT NULL,
      display_text TEXT NOT NULL,
      UNIQUE (
        translation_id,
        book_number,
        chapter,
        start_verse,
        end_verse
      )
    );
    CREATE INDEX passage_reference_lookup
      ON passages(
        translation_id,
        book_number,
        chapter,
        start_verse,
        end_verse
      );
  ''');
}

int _insertBible(Database database, String id, SourceBible bible) {
  database.execute('INSERT INTO translations (id, name) VALUES (?, ?)', [
    id,
    bible.name,
  ]);
  final books = [...bible.books]
    ..sort((left, right) => left.number.compareTo(right.number));
  var passageCount = 0;
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
      for (var start = 0; start < verses.length; start++) {
        for (var length = 1; length <= 3; length++) {
          final end = start + length - 1;
          if (end >= verses.length) break;
          if (!_isConsecutive(verses, start, end)) break;
          _insertPassage(
            database,
            id,
            book,
            chapter.number,
            verses.sublist(start, end + 1),
          );
          passageCount++;
        }
      }
    }
  }
  return passageCount;
}

bool _isConsecutive(List<SourceVerse> verses, int start, int end) {
  for (var index = start + 1; index <= end; index++) {
    if (verses[index - 1].endNumber + 1 != verses[index].number) {
      return false;
    }
  }
  return true;
}

void _insertPassage(
  Database database,
  String translationId,
  SourceBook book,
  int chapter,
  List<SourceVerse> verses,
) {
  final startVerse = verses.first.number;
  final endVerse = verses.last.endNumber;
  final displayText = verses.map((verse) => verse.text).join(' ');
  final verseLabel = startVerse == endVerse
      ? '$startVerse'
      : '$startVerse–$endVerse';
  database.execute(
    '''
      INSERT INTO passages (
        translation_id,
        book_number,
        chapter,
        start_verse,
        end_verse,
        label,
        display_text
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      translationId,
      book.number,
      chapter,
      startVerse,
      endVerse,
      '${book.name} $chapter:$verseLabel',
      displayText,
    ],
  );
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
