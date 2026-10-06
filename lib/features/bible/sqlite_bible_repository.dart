import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import 'bible_repository.dart';

class SqliteBibleRepository implements BibleRepository {
  SqliteBibleRepository._(this._database);

  final Database _database;

  static Future<SqliteBibleRepository> open({
    String assetPath = 'assets/bibles.db',
    String databaseName = 'bibles.db',
  }) async {
    final directory = await getDatabasesPath();
    final destination = File(path.join(directory, databaseName));
    await destination.parent.create(recursive: true);

    final data = await rootBundle.load(assetPath);
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }

    final database = await openDatabase(
      destination.path,
      readOnly: true,
      singleInstance: false,
    );
    return SqliteBibleRepository._(database);
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
    final exact = await _database.rawQuery(
      '''
        SELECT p.*, b.name AS book_name
        FROM passages p
        JOIN books b
          ON b.translation_id = p.translation_id
          AND b.number = p.book_number
        WHERE p.translation_id = ?
          AND p.book_number = ?
          AND p.chapter = ?
          AND p.start_verse = ?
          AND p.end_verse = ?
        LIMIT 1
      ''',
      [
        translationId,
        reference.book,
        reference.chapter,
        reference.startVerse,
        reference.endVerse,
      ],
    );
    if (exact.isNotEmpty) return _passageFromRow(exact.single);

    final verses = await _individualVerses(translationId, reference);
    if (!_covers(verses, reference.startVerse, reference.endVerse)) {
      return null;
    }
    return _combine(verses, reference.startVerse, reference.endVerse);
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
        SELECT p.*, b.name AS book_name
        FROM passages p
        JOIN books b
          ON b.translation_id = p.translation_id
          AND b.number = p.book_number
        WHERE p.translation_id = ?
          AND p.book_number = ?
          AND p.chapter = ?
          AND p.start_verse = p.end_verse
        ORDER BY p.start_verse
      ''',
      [translationId, reference.book, reference.chapter],
    );
    final first = rows.indexWhere(
      (row) => (row['start_verse']! as int) == reference.startVerse,
    );
    final last = rows.indexWhere(
      (row) => (row['end_verse']! as int) == reference.endVerse,
    );
    if (first < 0 || last < first) return null;
    final startIndex = (first - before).clamp(0, rows.length - 1);
    final endIndex = (last + after).clamp(0, rows.length - 1);
    final selected = rows.sublist(startIndex, endIndex + 1);
    return _combine(
      selected,
      selected.first['start_verse']! as int,
      selected.last['end_verse']! as int,
    );
  }

  @override
  Future<String> fingerprint() async {
    final versionRows = await _database.rawQuery('PRAGMA user_version');
    final schemaVersion = versionRows.single.values.single! as int;
    final verses = await _database.rawQuery('''
      SELECT translation_id, book_number, chapter, start_verse, end_verse,
        display_text
      FROM passages
      WHERE start_verse = end_verse
      ORDER BY translation_id COLLATE BINARY, book_number, chapter,
        start_verse, end_verse
    ''');
    final bytes = BytesBuilder(copy: false)
      ..add(_lengthPrefixed('$schemaVersion'));
    for (final verse in verses) {
      for (final field in [
        verse['translation_id'],
        verse['book_number'],
        verse['chapter'],
        verse['start_verse'],
        verse['end_verse'],
        verse['display_text'],
      ]) {
        bytes.add(_lengthPrefixed('$field'));
      }
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  @override
  Future<void> close() => _database.close();

  Future<List<Map<String, Object?>>> _individualVerses(
    String translationId,
    ScriptureReference reference,
  ) {
    return _database.rawQuery(
      '''
        SELECT p.*, b.name AS book_name
        FROM passages p
        JOIN books b
          ON b.translation_id = p.translation_id
          AND b.number = p.book_number
        WHERE p.translation_id = ?
          AND p.book_number = ?
          AND p.chapter = ?
          AND p.start_verse = p.end_verse
          AND p.start_verse BETWEEN ? AND ?
        ORDER BY p.start_verse
      ''',
      [
        translationId,
        reference.book,
        reference.chapter,
        reference.startVerse,
        reference.endVerse,
      ],
    );
  }
}

Uint8List _lengthPrefixed(String value) {
  final valueBytes = utf8.encode(value);
  final result = Uint8List(4 + valueBytes.length);
  ByteData.sublistView(result).setUint32(0, valueBytes.length, Endian.little);
  result.setRange(4, result.length, valueBytes);
  return result;
}

bool _covers(List<Map<String, Object?>> rows, int start, int end) {
  if (rows.length != end - start + 1) return false;
  for (var index = 0; index < rows.length; index++) {
    if (rows[index]['start_verse'] != start + index) return false;
  }
  return true;
}

Passage _passageFromRow(Map<String, Object?> row) {
  return Passage(
    reference: ScriptureReference(
      book: row['book_number']! as int,
      chapter: row['chapter']! as int,
      startVerse: row['start_verse']! as int,
      endVerse: row['end_verse']! as int,
    ),
    label: row['label']! as String,
    text: row['display_text']! as String,
  );
}

Passage _combine(List<Map<String, Object?>> rows, int start, int end) {
  final chapter = rows.first['chapter']! as int;
  final verseLabel = start == end ? '$start' : '$start–$end';
  return Passage(
    reference: ScriptureReference(
      book: rows.first['book_number']! as int,
      chapter: chapter,
      startVerse: start,
      endVerse: end,
    ),
    label: '${rows.first['book_name']} $chapter:$verseLabel',
    text: rows.map((row) => row['display_text']! as String).join(' '),
  );
}
