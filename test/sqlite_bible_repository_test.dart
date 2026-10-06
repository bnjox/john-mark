import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:john_mark/core/models.dart';
import 'package:john_mark/features/bible/corpus_manifest.dart';
import 'package:john_mark/features/bible/sqlite_bible_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _fingerprint =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

void main() {
  late Directory temporary;
  late _MemoryBundle bundle;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bible_repository_');
    bundle = await _corpusBundle(temporary);
  });

  tearDown(() => temporary.delete(recursive: true));

  test(
    'installs once, reuses the database, and reads ranges/context',
    () async {
      final repository = await _open(bundle, temporary);
      expect(await repository.translations(), hasLength(1));
      expect(await repository.fingerprint(), _fingerprint);
      expect(
        await repository.passage(
          'alpha',
          const ScriptureReference(
            book: 43,
            chapter: 3,
            startVerse: 15,
            endVerse: 17,
          ),
        ),
        isA<Passage>()
            .having((passage) => passage.label, 'label', 'John 3:15–17')
            .having((passage) => passage.text, 'text', 'First. Second. Third.'),
      );
      expect(
        await repository.context(
          'alpha',
          const ScriptureReference(
            book: 43,
            chapter: 3,
            startVerse: 16,
            endVerse: 16,
          ),
        ),
        isA<Passage>().having(
          (passage) => passage.reference,
          'reference',
          const ScriptureReference(
            book: 43,
            chapter: 3,
            startVerse: 15,
            endVerse: 17,
          ),
        ),
      );
      await repository.close();

      final installed = File('${temporary.path}/installed/bibles.db');
      final modified = await installed.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final reopened = await _open(bundle, temporary);
      await reopened.close();

      expect(await installed.lastModified(), modified);
    },
  );

  test(
    'recovers a corrupt installed database and removes abandoned temp',
    () async {
      final first = await _open(bundle, temporary);
      await first.close();
      final directory = Directory('${temporary.path}/installed');
      final installed = File('${directory.path}/bibles.db');
      await installed.writeAsString('corrupt');
      final abandoned = File('${installed.path}.tmp')
        ..writeAsStringSync('partial');

      final recovered = await _open(bundle, temporary);
      expect(await recovered.translations(), hasLength(1));
      await recovered.close();
      expect(await abandoned.exists(), isFalse);
      expect(await installed.length(), bundle.database.length);
    },
  );

  test('rejects passage ranges containing a missing verse', () async {
    bundle = await _corpusBundle(
      temporary,
      verses: const {15: 'First.', 17: 'Third.'},
    );
    final repository = await _open(bundle, temporary);
    addTearDown(repository.close);

    expect(
      await repository.passage(
        'alpha',
        const ScriptureReference(
          book: 43,
          chapter: 3,
          startVerse: 15,
          endVerse: 17,
        ),
      ),
      isNull,
    );
  });

  test('rejects an invalid bundled manifest', () async {
    bundle.assets['assets/bibles.manifest.json'] = Uint8List.fromList(
      utf8.encode('{}'),
    );

    await expectLater(_open(bundle, temporary), throwsFormatException);
  });
}

Future<SqliteBibleRepository> _open(
  _MemoryBundle bundle,
  Directory temporary,
) => SqliteBibleRepository.open(
  bundle: bundle,
  databaseDirectory: '${temporary.path}/installed',
  databaseFactory: databaseFactoryFfi,
);

Future<_MemoryBundle> _corpusBundle(
  Directory root, {
  Map<int, String> verses = const {15: 'First.', 16: 'Second.', 17: 'Third.'},
}) async {
  final source = File('${root.path}/source-${verses.length}.db');
  final database = sqlite.sqlite3.open(source.path);
  database.execute('''
    PRAGMA user_version = 3;
    CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE translations (id TEXT PRIMARY KEY, name TEXT NOT NULL) WITHOUT ROWID;
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
  database.execute("INSERT INTO metadata VALUES ('schema_version', '3')");
  database.execute("INSERT INTO metadata VALUES ('fingerprint_contract', '1')");
  database.execute(
    "INSERT INTO metadata VALUES ('corpus_fingerprint', '$_fingerprint')",
  );
  database.execute("INSERT INTO translations VALUES ('alpha', 'Alpha')");
  database.execute("INSERT INTO books VALUES ('alpha', 43, 'John')");
  for (final MapEntry(key: verse, value: text) in verses.entries) {
    database.execute('INSERT INTO verses VALUES (?, 43, 3, ?, ?)', [
      'alpha',
      verse,
      text,
    ]);
  }
  database.execute('VACUUM');
  database.close();
  final bytes = await source.readAsBytes();
  final manifest = CorpusManifest(
    assetId: sha256.convert(bytes).toString(),
    databaseBytes: bytes.length,
    translationIds: const ['alpha'],
    corpusFingerprint: _fingerprint,
  );
  return _MemoryBundle({
    'assets/bibles.db': bytes,
    'assets/bibles.manifest.json': Uint8List.fromList(
      utf8.encode(manifest.encode()),
    ),
  });
}

class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle(this.assets);

  final Map<String, Uint8List> assets;
  Uint8List get database => assets['assets/bibles.db']!;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}
