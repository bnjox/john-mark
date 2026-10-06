import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import 'bible_repository.dart';
import 'corpus_manifest.dart';

class SqliteBibleRepository implements BibleRepository {
  SqliteBibleRepository._(this._database, this._fingerprint);

  final Database _database;
  final String _fingerprint;

  static Future<SqliteBibleRepository> open({
    String assetPath = 'assets/bibles.db',
    String manifestAssetPath = 'assets/bibles.manifest.json',
    String databaseName = 'bibles.db',
    AssetBundle? bundle,
    String? databaseDirectory,
    DatabaseFactory? databaseFactory,
  }) async {
    final assets = bundle ?? rootBundle;
    final manifest = CorpusManifest.parse(
      await assets.loadString(manifestAssetPath),
    );
    final factory = databaseFactory ?? databaseFactorySqflitePlugin;
    final directory = databaseDirectory ?? await getDatabasesPath();
    final destination = File(path.join(directory, databaseName));
    final marker = File('${destination.path}.manifest');
    final temporary = File('${destination.path}.tmp');
    final temporaryMarker = File('${marker.path}.tmp');
    await destination.parent.create(recursive: true);
    await _deleteIfPresent(temporary);
    await _deleteIfPresent(temporaryMarker);

    if (await _matchesInstalled(destination, marker, manifest)) {
      try {
        return await _openValidated(factory, destination.path, manifest);
      } catch (_) {
        // The generated database is safe to replace from the bundled asset.
      }
    }

    final data = await assets.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != manifest.databaseBytes ||
        sha256.convert(bytes).toString() != manifest.assetId) {
      throw const FormatException('Bible database does not match its manifest');
    }
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      final candidate = await _openValidated(
        factory,
        temporary.path,
        manifest,
        checkIntegrity: true,
      );
      await candidate.close();
      await temporary.rename(destination.path);
      await temporaryMarker.writeAsString(manifest.encode(), flush: true);
      await temporaryMarker.rename(marker.path);
      return await _openValidated(factory, destination.path, manifest);
    } finally {
      await _deleteIfPresent(temporary);
      await _deleteIfPresent(temporaryMarker);
    }
  }

  @override
  Future<List<Translation>> translations() async {
    final rows = await _database.query(
      'translations',
      columns: ['id', 'name'],
      orderBy: 'name COLLATE NOCASE, id',
    );
    return rows
        .map(
          (row) => Translation(
            id: row['id']! as String,
            name: row['name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async {
    final verses = await _database.rawQuery(
      '''
        SELECT v.verse, v.display_text, b.name AS book_name
        FROM verses v
        JOIN books b
          ON b.translation_id = v.translation_id
          AND b.number = v.book_number
        WHERE v.translation_id = ?
          AND v.book_number = ?
          AND v.chapter = ?
          AND v.verse BETWEEN ? AND ?
        ORDER BY v.verse
      ''',
      [
        translationId,
        reference.book,
        reference.chapter,
        reference.startVerse,
        reference.endVerse,
      ],
    );
    if (!_covers(verses, reference.startVerse, reference.endVerse)) {
      return null;
    }
    return _combine(verses, reference);
  }

  @override
  Future<Passage?> context(
    String translationId,
    ScriptureReference reference, {
    int before = 1,
    int after = 1,
  }) async {
    if (before < 0 || after < 0) {
      throw ArgumentError('Context bounds must not be negative');
    }
    final rows = await _database.rawQuery(
      '''
        SELECT v.verse, v.display_text, b.name AS book_name
        FROM verses v
        JOIN books b
          ON b.translation_id = v.translation_id
          AND b.number = v.book_number
        WHERE v.translation_id = ?
          AND v.book_number = ?
          AND v.chapter = ?
        ORDER BY v.verse
      ''',
      [translationId, reference.book, reference.chapter],
    );
    final first = rows.indexWhere(
      (row) => (row['verse']! as int) == reference.startVerse,
    );
    final last = rows.indexWhere(
      (row) => (row['verse']! as int) == reference.endVerse,
    );
    if (first < 0 || last < first) return null;
    final startIndex = (first - before).clamp(0, rows.length - 1);
    final endIndex = (last + after).clamp(0, rows.length - 1);
    final selected = rows.sublist(startIndex, endIndex + 1);
    return _combine(
      selected,
      ScriptureReference(
        book: reference.book,
        chapter: reference.chapter,
        startVerse: selected.first['verse']! as int,
        endVerse: selected.last['verse']! as int,
      ),
    );
  }

  @override
  Future<String> fingerprint() async => _fingerprint;

  @override
  Future<void> close() => _database.close();
}

Future<SqliteBibleRepository> _openValidated(
  DatabaseFactory factory,
  String databasePath,
  CorpusManifest manifest, {
  bool checkIntegrity = false,
}) async {
  final database = await factory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final version = await database.rawQuery('PRAGMA user_version');
    if (version.single.values.single != corpusSchemaVersion) {
      throw const FormatException('Unsupported Bible database schema');
    }
    final metadataRows = await database.query('metadata');
    final metadata = {
      for (final row in metadataRows)
        row['key'] as String: row['value'] as String,
    };
    if (metadata['schema_version'] != '$corpusSchemaVersion' ||
        metadata['fingerprint_contract'] != '$corpusFingerprintContract' ||
        metadata['corpus_fingerprint'] != manifest.corpusFingerprint) {
      throw const FormatException('Bible database metadata does not match');
    }
    final translations = await database.query(
      'translations',
      columns: ['id'],
      orderBy: 'id COLLATE BINARY',
    );
    final translationIds = translations
        .map((row) => row['id']! as String)
        .toList(growable: false);
    if (!_sameStrings(translationIds, manifest.translationIds)) {
      throw const FormatException('Bible database translations do not match');
    }
    if (checkIntegrity) {
      final result = await database.rawQuery('PRAGMA quick_check');
      if (result.length != 1 || result.single.values.single != 'ok') {
        throw const FormatException('Bible database integrity check failed');
      }
    }
    return SqliteBibleRepository._(database, manifest.corpusFingerprint);
  } catch (_) {
    await database.close();
    rethrow;
  }
}

bool _covers(List<Map<String, Object?>> rows, int start, int end) {
  if (rows.length != end - start + 1) return false;
  for (var index = 0; index < rows.length; index++) {
    if (rows[index]['verse'] != start + index) return false;
  }
  return true;
}

Passage _combine(
  List<Map<String, Object?>> rows,
  ScriptureReference reference,
) {
  final verseLabel = reference.startVerse == reference.endVerse
      ? '${reference.startVerse}'
      : '${reference.startVerse}–${reference.endVerse}';
  return Passage(
    reference: reference,
    label: '${rows.first['book_name']} ${reference.chapter}:$verseLabel',
    text: rows.map((row) => row['display_text']! as String).join(' '),
  );
}

Future<bool> _matchesInstalled(
  File database,
  File marker,
  CorpusManifest manifest,
) async {
  if (!await database.exists() || !await marker.exists()) return false;
  if (await database.length() != manifest.databaseBytes) return false;
  try {
    return await marker.readAsString() == manifest.encode();
  } on FileSystemException {
    return false;
  }
}

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) await file.delete();
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
