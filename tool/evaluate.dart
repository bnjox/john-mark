import 'dart:convert';
import 'dart:io';

import 'package:guide/core/models.dart';
import 'package:guide/features/bible/bible_repository.dart';
import 'package:guide/features/matching/scripture_matcher.dart';
import 'package:sqlite3/sqlite3.dart';

const _usage =
    'Usage: dart run tool/evaluate.dart '
    '--database <bibles.db> --fixtures <fixtures.ndjson>';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final repository = _CliBibleRepository.open(options.database);
    try {
      final metrics = await _evaluate(repository, File(options.fixtures));
      stdout
        ..writeln('total: ${metrics.total}')
        ..writeln('top-one: ${metrics.topOne}')
        ..writeln('top-four: ${metrics.topFour}')
        ..writeln('false-positive: ${metrics.falsePositive}')
        ..writeln('no-result: ${metrics.noResult}')
        ..writeln(
          'median-time: ${metrics.medianMilliseconds.toStringAsFixed(3)} ms',
        );
    } finally {
      await repository.close();
    }
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on _FixtureException catch (error) {
    stderr.writeln('Fixtures line ${error.line}: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Unable to read required evaluation input: ${error.message}',
    );
    exitCode = 66;
  } on SqliteException catch (error) {
    stderr.writeln('Unable to query the Bible database: ${error.message}');
    exitCode = 65;
  }
}

_Options _parseArguments(List<String> arguments) {
  String? database;
  String? fixtures;
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length) {
      throw const _UsageException('Every option requires a value.');
    }
    switch (arguments[index]) {
      case '--database':
        database = arguments[index + 1];
      case '--fixtures':
        fixtures = arguments[index + 1];
      default:
        throw _UsageException('Unknown option: ${arguments[index]}');
    }
  }
  if (database == null || fixtures == null) {
    throw const _UsageException('Both options are required.');
  }
  return _Options(database: database, fixtures: fixtures);
}

Future<_Metrics> _evaluate(BibleRepository repository, File fixtures) async {
  final translationIds = (await repository.translations())
      .map((translation) => translation.id)
      .toSet();
  var total = 0;
  var topOne = 0;
  var topFour = 0;
  var falsePositive = 0;
  var noResult = 0;
  final elapsedMicroseconds = <int>[];

  var lineNumber = 0;
  await for (final rawLine
      in fixtures
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    lineNumber++;
    if (rawLine.trim().isEmpty) continue;
    final fixture = _Fixture.parse(rawLine, lineNumber);
    if (!translationIds.contains(fixture.translation)) {
      throw _FixtureException(
        lineNumber,
        'translation is not present in the database.',
      );
    }
    final matcher = ScriptureMatcher(
      repository: repository,
      translationId: fixture.translation,
    );

    final stopwatch = Stopwatch()..start();
    var update = await matcher.match(fixture.transcript);
    if (update?.featured == null) {
      // Possible-confidence matches require confirmation in two windows.
      update = await matcher.match(fixture.transcript) ?? matcher.current;
    }
    stopwatch.stop();

    final candidates = <MatchCandidate>[
      ?update?.featured,
      ...?update?.alternatives,
    ];
    total++;
    elapsedMicroseconds.add(stopwatch.elapsedMicroseconds);
    if (candidates.isEmpty) noResult++;

    final expected = fixture.expected;
    if (expected == null) {
      if (candidates.isNotEmpty) falsePositive++;
      continue;
    }
    if (candidates.isNotEmpty &&
        _sameLabel(candidates.first.passage.label, expected)) {
      topOne++;
    }
    if (candidates
        .take(4)
        .any((candidate) => _sameLabel(candidate.passage.label, expected))) {
      topFour++;
    }
  }

  if (total == 0) {
    throw const _FixtureException(0, 'no fixture rows found.');
  }
  elapsedMicroseconds.sort();
  final middle = elapsedMicroseconds.length ~/ 2;
  final medianMicroseconds = elapsedMicroseconds.length.isOdd
      ? elapsedMicroseconds[middle].toDouble()
      : (elapsedMicroseconds[middle - 1] + elapsedMicroseconds[middle]) / 2;
  return _Metrics(
    total: total,
    topOne: topOne,
    topFour: topFour,
    falsePositive: falsePositive,
    noResult: noResult,
    medianMilliseconds: medianMicroseconds / 1000,
  );
}

bool _sameLabel(String actual, String expected) =>
    _canonicalLabel(actual) == _canonicalLabel(expected);

String _canonicalLabel(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ');

class _Options {
  const _Options({required this.database, required this.fixtures});

  final String database;
  final String fixtures;
}

class _Fixture {
  const _Fixture({
    required this.translation,
    required this.transcript,
    required this.expected,
  });

  factory _Fixture.parse(String line, int lineNumber) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw _FixtureException(lineNumber, 'invalid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw _FixtureException(lineNumber, 'row must be a JSON object.');
    }
    final translation = decoded['translation'];
    final transcript = decoded['transcript'];
    final expected = decoded['expected'];
    if (translation is! String || translation.trim().isEmpty) {
      throw _FixtureException(lineNumber, 'translation must be a string.');
    }
    if (transcript is! String || transcript.trim().isEmpty) {
      throw _FixtureException(lineNumber, 'transcript must be a string.');
    }
    if (expected != null && expected is! String) {
      throw _FixtureException(lineNumber, 'expected must be a string or null.');
    }
    if (expected is String && expected.trim().isEmpty) {
      throw _FixtureException(lineNumber, 'expected must not be empty.');
    }
    return _Fixture(
      translation: translation,
      transcript: transcript,
      expected: expected as String?,
    );
  }

  final String translation;
  final String transcript;
  final String? expected;
}

class _Metrics {
  const _Metrics({
    required this.total,
    required this.topOne,
    required this.topFour,
    required this.falsePositive,
    required this.noResult,
    required this.medianMilliseconds,
  });

  final int total;
  final int topOne;
  final int topFour;
  final int falsePositive;
  final int noResult;
  final double medianMilliseconds;
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

class _FixtureException implements Exception {
  const _FixtureException(this.line, this.message);

  final int line;
  final String message;
}

class _CliBibleRepository implements BibleRepository {
  _CliBibleRepository._(this._database);

  factory _CliBibleRepository.open(String databasePath) {
    return _CliBibleRepository._(
      sqlite3.open(databasePath, mode: OpenMode.readOnly),
    );
  }

  final Database _database;

  @override
  Future<List<Translation>> translations() async {
    return _database
        .select('SELECT id, name FROM translations ORDER BY name, id')
        .map(
          (row) =>
              Translation(id: row['id'] as String, name: row['name'] as String),
        )
        .toList(growable: false);
  }

  @override
  Future<Passage?> passage(
    String translationId,
    ScriptureReference reference,
  ) async {
    final exact = _database.select(
      '''
      SELECT p.*, b.name AS book_name
      FROM passages p
      JOIN books b ON b.translation_id = p.translation_id
        AND b.number = p.book_number
      WHERE p.translation_id = ? AND p.book_number = ? AND p.chapter = ?
        AND p.start_verse = ? AND p.end_verse = ?
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
    if (exact.isNotEmpty) return _passageFromRow(exact.first);

    final verses = _individualVerses(translationId, reference);
    if (!_covers(verses, reference.startVerse, reference.endVerse)) return null;
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
    final rows = _database.select(
      '''
      SELECT p.*, b.name AS book_name
      FROM passages p
      JOIN books b ON b.translation_id = p.translation_id
        AND b.number = p.book_number
      WHERE p.translation_id = ? AND p.book_number = ? AND p.chapter = ?
        AND p.start_verse = p.end_verse
      ORDER BY p.start_verse
      ''',
      [translationId, reference.book, reference.chapter],
    );
    final first = rows.indexWhere(
      (row) => row['start_verse'] == reference.startVerse,
    );
    final last = rows.indexWhere(
      (row) => row['end_verse'] == reference.endVerse,
    );
    if (first < 0 || last < first) return null;
    final startIndex = (first - before).clamp(0, rows.length - 1);
    final endIndex = (last + after).clamp(0, rows.length - 1);
    final selected = rows.sublist(startIndex, endIndex + 1);
    return _combine(
      selected,
      selected.first['start_verse'] as int,
      selected.last['end_verse'] as int,
    );
  }

  @override
  Future<List<Passage>> quoteCandidates(
    String translationId,
    List<String> tokens, {
    int limit = 40,
  }) async {
    if (limit <= 0) return const [];
    final distinctTokens = tokens
        .map((token) => token.trim().toLowerCase())
        .where((token) => RegExp(r'^[a-z0-9]+$').hasMatch(token))
        .toSet()
        .take(64)
        .toList(growable: false);
    if (distinctTokens.isEmpty) return const [];
    final placeholders = List.filled(distinctTokens.length, '?').join(', ');
    final rows = _database.select(
      '''
      SELECT p.*, b.name AS book_name, COUNT(DISTINCT t.token) AS token_hits
      FROM passage_tokens t
      JOIN passages p ON p.id = t.passage_id
      JOIN books b ON b.translation_id = p.translation_id
        AND b.number = p.book_number
      WHERE p.translation_id = ? AND t.token IN ($placeholders)
      GROUP BY p.id
      ORDER BY token_hits DESC, p.id ASC
      LIMIT ?
      ''',
      [translationId, ...distinctTokens, limit.clamp(1, 40)],
    );
    return rows.map(_passageFromRow).toList(growable: false);
  }

  @override
  Future<void> close() async => _database.close();

  ResultSet _individualVerses(
    String translationId,
    ScriptureReference reference,
  ) {
    return _database.select(
      '''
      SELECT p.*, b.name AS book_name
      FROM passages p
      JOIN books b ON b.translation_id = p.translation_id
        AND b.number = p.book_number
      WHERE p.translation_id = ? AND p.book_number = ? AND p.chapter = ?
        AND p.start_verse = p.end_verse AND p.start_verse BETWEEN ? AND ?
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

bool _covers(List<Row> rows, int start, int end) {
  if (rows.length != end - start + 1) return false;
  for (var index = 0; index < rows.length; index++) {
    if (rows[index]['start_verse'] != start + index) return false;
  }
  return true;
}

Passage _passageFromRow(Row row) {
  return Passage(
    reference: ScriptureReference(
      book: row['book_number'] as int,
      chapter: row['chapter'] as int,
      startVerse: row['start_verse'] as int,
      endVerse: row['end_verse'] as int,
    ),
    label: row['label'] as String,
    text: row['display_text'] as String,
  );
}

Passage _combine(List<Row> rows, int start, int end) {
  final chapter = rows.first['chapter'] as int;
  final verseLabel = start == end ? '$start' : '$start–$end';
  return Passage(
    reference: ScriptureReference(
      book: rows.first['book_number'] as int,
      chapter: chapter,
      startVerse: start,
      endVerse: end,
    ),
    label: '${rows.first['book_name']} $chapter:$verseLabel',
    text: rows.map((row) => row['display_text'] as String).join(' '),
  );
}
